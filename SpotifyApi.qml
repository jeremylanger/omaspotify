import QtQuick

import "Api.js" as Api

// Thin authenticated transport. It performs no polling and owns only one
// special request: search, which is cancelled whenever a newer query arrives.
// Requests share a small in-flight cap and a Retry-After cooldown so a
// development-mode app does not burst into Spotify's 429 window. After a
// 429, only one request goes out until a later call succeeds.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  required property var auth

  property var searchRequest: null
  property int searchSerial: 0
  property var requestQueue: []
  property int requestsInFlight: 0
  // Background jobs never take the last slots, so an opened page has somewhere
  // to run even while the library is still loading.
  property int backgroundInFlight: 0
  property double lastBackgroundStartedAt: 0
  property double lastInteractiveStartedAt: 0
  // Every refusal widens the gap between background requests for this run.
  property int backgroundRefusals: 0
  readonly property int backgroundSpacingMs:
    Api.backgroundSpacingForRefusals(backgroundRefusals)
  // Every request is logged while we are still tuning this; raise it to see
  // only the slow ones.
  property int slowRequestMs: 0
  property double rateLimitedUntil: 0
  // Set only when a request someone is waiting on is refused. Background
  // refusals must not hold an opened page back.
  property double interactiveLimitedUntil: 0
  // When the current pause began, so an opened page only waits a moment of it.
  property double rateLimitedSince: 0
  property bool cooldownProbeUsed: false
  property bool restrictInFlight: false
  property bool pumpingRequests: false
  property bool pumpAgain: false
  property var timedJobs: []
  property var xhrFactory: function() { return new XMLHttpRequest() }
  property var now: function() { return Date.now() }

  function removeTimedJob(job) {
    var next = []
    for (var i = 0; i < timedJobs.length; i++)
      if (timedJobs[i] !== job) next.push(timedJobs[i])
    timedJobs = next
  }

  function removeQueuedHandle(handle) {
    var next = []
    for (var i = 0; i < requestQueue.length; i++)
      if (!requestQueue[i] || requestQueue[i].handle !== handle)
        next.push(requestQueue[i])
    requestQueue = next
  }

  function abortXhr(xhr) {
    if (!xhr || typeof xhr.abort !== "function") return
    try {
      xhr.abort()
    } catch (error) {
      console.warn("Spotify API request abort failed: " + Api.redact(error))
    }
  }

  function markJobFinished(job) {
    if (!job || job.finished === true) return
    job.finished = true
    removeTimedJob(job)
    return true
  }

  function deliverJob(job, status, payload, error, xhr) {
    var ended = now()
    var queuedAt = job.queuedAt !== undefined ? job.queuedAt : ended
    var startedAt = job.startedAt !== undefined ? job.startedAt : queuedAt
    var authedAt = job.authedAt !== undefined ? job.authedAt : startedAt
    var elapsed = Math.max(0, ended - queuedAt)
    if (error || elapsed >= slowRequestMs)
      console.warn("Spotify API " + Api.requestTimingLine(job.method, job.path, {
        queuedMs: Math.max(0, startedAt - queuedAt),
        authMs: Math.max(0, authedAt - startedAt),
        wireMs: Math.max(0, ended - authedAt)
      }, {
        inFlight: requestsInFlight,
        background: backgroundInFlight,
        queued: requestQueue.length,
        priority: job.priority
      }) + (error ? ": " + Api.redact(error) : ""))
    releaseRequestSlot(job.handle)
    if (job.handle && job.handle.job === job) job.handle.job = null
    callbackIfCurrent(job, status, payload, error, xhr)
  }

  function finishJob(job, status, payload, error, xhr) {
    if (markJobFinished(job) !== true) return
    deliverJob(job, status, payload, error, xhr)
  }

  function expireTimedOutRequests(timestamp) {
    var current = Number(timestamp)
    if (!isFinite(current)) current = now()
    var jobs = timedJobs.slice()
    for (var i = 0; i < jobs.length; i++) {
      var job = jobs[i]
      if (!job || job.finished === true || !job.deadlineAt
          || current < job.deadlineAt) continue
      var handle = job.handle
      var xhr = handle ? handle.xhr : null
      if (markJobFinished(job) !== true) continue
      if (handle) {
        handle.xhr = null
        handle.aborted = true
        removeQueuedHandle(handle)
      }
      abortXhr(xhr)
      deliverJob(job, 0, null,
        "Spotify took too long to respond. Try again.", null)
    }
  }

  function abortRequest(handle) {
    if (!handle || handle.aborted) return
    handle.aborted = true
    removeQueuedHandle(handle)
    var xhr = handle.xhr
    handle.xhr = null
    if (handle.job && handle.job.finished !== true) {
      handle.job.finished = true
      removeTimedJob(handle.job)
    }
    handle.job = null
    abortXhr(xhr)
    releaseRequestSlot(handle)
  }

  function requestError(status, payload, xhr, fallback) {
    if (status === 429)
      return Api.rateLimitMessage(Api.responseRetryAfter(xhr))
    return Api.responseError(status, payload, fallback)
  }

  function enqueueJob(job) {
    requestQueue = Api.enqueueApiJob(requestQueue, job)
    pumpRequests()
    return job.handle
  }

  function releaseRequestSlot(handle) {
    if (handle && handle.slotOpen !== true) return
    if (handle) handle.slotOpen = false
    if (handle && handle.countedBackground === true) {
      handle.countedBackground = false
      backgroundInFlight = Math.max(0, backgroundInFlight - 1)
    }
    requestsInFlight = Math.max(0, requestsInFlight - 1)
    pumpRequests()
  }

  function pumpRequests() {
    if (pumpingRequests) {
      pumpAgain = true
      return
    }
    pumpingRequests = true
    pumpAgain = false
    while (requestsInFlight < Api.apiInFlightLimit(restrictInFlight)) {
      var limit = Api.apiInFlightLimit(restrictInFlight)
      var cooldown = Api.apiCooldownMs(now(), rateLimitedUntil)
      var backgroundDelay = Api.backgroundDispatchDelay(lastBackgroundStartedAt,
        lastInteractiveStartedAt, now(), backgroundSpacingMs)
      var allowBackground = cooldown === 0 && backgroundDelay === 0
        && backgroundInFlight < Api.backgroundInFlightLimit(limit)
      var taken = Api.dequeueApiJob(requestQueue, allowBackground)
      var job = taken.job
      // The pause that applies to this job, which for a page someone opened is
      // only ever its own refusals.
      var jobCooldown = Api.jobCooldownMs(job, now(), rateLimitedUntil,
        interactiveLimitedUntil)
      if (job && jobCooldown > 0
          && !Api.jobMayRunDuringCooldown(job, cooldownProbeUsed)) job = null
      if (job) {
        var wait = Api.foregroundCooldownMs(now(), interactiveLimitedUntil,
          rateLimitedSince, Api.API_FOREGROUND_COOLDOWN_CAP_MS)
        if (wait > 0) {
          rateLimitTimer.interval = Math.max(50, wait)
          rateLimitTimer.restart()
          break
        }
      }
      if (!job) {
        if (jobCooldown > 0 || cooldown > 0) {
          rateLimitTimer.interval = Math.max(50,
            jobCooldown > 0 ? jobCooldown : cooldown)
          rateLimitTimer.restart()
        } else if (backgroundDelay > 0 && requestQueue.length > 0) {
          // Background work waiting only on its spacing gets woken up again.
          backgroundPaceTimer.interval = backgroundDelay
          backgroundPaceTimer.restart()
        }
        break
      }
      if (jobCooldown > 0) cooldownProbeUsed = true
      requestQueue = taken.queue
      job.handle.slotOpen = true
      job.startedAt = now()
      if (Api.apiJobPriority(job) < 0) {
        // Counted on the handle, which outlives a job that gets cancelled.
        job.handle.countedBackground = true
        backgroundInFlight += 1
        lastBackgroundStartedAt = now()
      } else if (Api.apiJobPriority(job) >= 1) {
        lastInteractiveStartedAt = now()
      }
      requestsInFlight += 1
      startJob(job)
    }
    pumpingRequests = false
    if (pumpAgain) pumpRequests()
  }

  function startJob(job) {
    var handle = job.handle
    var url = Api.safeApiUrl(job.path)
    if (!url) {
      finishJob(job, 0, null, "Something went wrong while contacting Spotify", null)
      return
    }
    url = Api.appendQuery(url, job.query)

    auth.withAccessToken(function(token, tokenError) {
      job.authedAt = now()
      if (handle.aborted) {
        releaseRequestSlot(handle)
        return
      }
      if (!token) {
        finishJob(job, 0, null, tokenError || "Not logged in", null)
        return
      }
      var xhr = null
      try {
        xhr = xhrFactory()
        handle.xhr = xhr
        xhr.onreadystatechange = function() {
          if (xhr.readyState !== XMLHttpRequest.DONE || handle.xhr !== xhr) return
          handle.xhr = null
          if (handle.aborted || job.finished === true) return
          var payload = Api.parseJson(xhr.responseText, null)
          if (xhr.status === 401 && job.retried !== true) {
            auth.invalidateAccessToken()
            job.retried = true
            requestQueue = Api.enqueueApiJob(requestQueue, job)
            releaseRequestSlot(handle)
            return
          }
          if (xhr.status === 429) {
            restrictInFlight = true
            backgroundRefusals += 1
            rateLimitedSince = now()
            cooldownProbeUsed = false
            rateLimitedUntil = Api.nextRateLimitedUntil(now(),
              Api.responseRetryAfter(xhr), rateLimitedUntil, job.rateLimitRetries)
            if (Api.apiJobPriority(job) >= 1)
              interactiveLimitedUntil = Api.nextRateLimitedUntil(now(),
                Api.responseRetryAfter(xhr), interactiveLimitedUntil,
                job.rateLimitRetries)
            console.warn("Spotify API rate limited on "
              + String(job.method || "GET") + " " + Api.redact(String(job.path || ""))
              + "; pausing every request for "
              + Api.apiCooldownMs(now(), rateLimitedUntil) + " ms"
              + " (retry " + job.rateLimitRetries
              + ", background gap now " + backgroundSpacingMs + " ms)")
            if (job.retryRateLimit !== false
                && Api.shouldRetryRateLimit(job.rateLimitRetries)) {
              job.rateLimitRetries += 1
              requestQueue = Api.enqueueApiJob(requestQueue, job)
              releaseRequestSlot(handle)
              return
            }
          } else {
            restrictInFlight = false
          }
          var ok = xhr.status >= 200 && xhr.status < 300
          var error = ok ? "" : root.requestError(xhr.status, payload, xhr,
            "Spotify could not complete this request")
          finishJob(job, xhr.status, payload, error, xhr)
        }
        xhr.open(String(job.method || "GET"), url)
        xhr.setRequestHeader("Authorization", "Bearer " + token)
        if (job.body !== undefined && job.body !== null) {
          xhr.setRequestHeader("Content-Type", "application/json")
          xhr.send(JSON.stringify(job.body))
        } else {
          xhr.send()
        }
      } catch (error) {
        if (handle.xhr === xhr) handle.xhr = null
        if (handle.aborted) {
          releaseRequestSlot(handle)
          return
        }
        finishJob(job, 0, null, "Something went wrong while contacting Spotify", null)
      }
    })
  }

  function callbackIfCurrent(job, status, payload, error, xhr) {
    if (typeof job.callback === "function")
      job.callback(status, payload, error, xhr)
  }

  function request(method, path, query, body, callback, options) {
    var settings = options || ({})
    var handle = { aborted: false, xhr: null, job: null }
    var timeoutMs = Math.max(0, Number(settings.timeoutMs) || 0)
    var queuedAt = now()
    var job = {
      method: method,
      path: path,
      query: query,
      body: body,
      callback: callback,
      retried: false,
      rateLimitRetries: 0,
      retryRateLimit: settings.retryRateLimit !== false,
      priority: String(settings.priority || ""),
      timeoutMs: timeoutMs,
      queuedAt: queuedAt,
      deadlineAt: timeoutMs > 0 ? queuedAt + timeoutMs : 0,
      finished: false,
      handle: handle
    }
    handle.job = job
    if (timeoutMs > 0) timedJobs = timedJobs.concat([job])
    return enqueueJob(job)
  }

  function cancelSearch() {
    searchSerial++
    abortRequest(searchRequest)
    searchRequest = null
  }

  // Search still uses its own serial so a newer query can reject a stale
  // callback created while a token refresh is still in flight.
  function search(query, callback) {
    cancelSearch()
    var serial = searchSerial
    var term = String(query || "").trim()
    if (!term) {
      if (typeof callback === "function") callback(Api.searchGroups({}, 128), "")
      return
    }
    searchRequest = request("GET", "/search", {
      q: term,
      type: Api.SEARCH_TYPES.join(","),
      limit: 10
    }, null, function(status, payload, error) {
      if (serial !== root.searchSerial) return
      if (typeof callback !== "function") return
      if (error) callback(Api.searchGroups({}, 128), error)
      else callback(Api.searchGroups(payload, 128), "")
    }, {
      priority: "interactive",
      timeoutMs: Api.SEARCH_REQUEST_TIMEOUT_MS,
      retryRateLimit: false
    })
  }

  Timer {
    id: backgroundPaceTimer
    repeat: false
    onTriggered: root.pumpRequests()
  }

  Timer {
    id: rateLimitTimer
    repeat: false
    onTriggered: root.pumpRequests()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.timedJobs.length > 0
    onTriggered: root.expireTimedOutRequests(root.now())
  }
}
