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
  // The shipped client id, kept for what a personal one is refused or not shown. Null
  // when there is no personal id, in which case `auth` is already the shipped
  // one and there is nothing to fall back to.
  property var fallbackAuth: null
  property var fallbackTransport: null
  // Named in every logged line, so a refusal can be blamed on the right app.
  property string appLabel: "personal"

  property var searchRequest: null
  property int searchSerial: 0
  property var requestQueue: []
  property int requestsInFlight: 0
  // Background jobs never take the last slots, so an opened page has somewhere
  // to run even while the library is still loading.
  property int backgroundInFlight: 0
  property double lastBackgroundStartedAt: 0
  property double lastInteractiveStartedAt: 0
  property double backgroundSuspendedUntil: 0
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
  property bool cancellingAll: false
  property bool expiringRequests: false
  property bool pumpAgain: false
  property var timedJobs: []
  property var diagnostics: []
  property int activeTimeoutMs: 15000
  property var xhrFactory: function() { return new XMLHttpRequest() }
  property var now: function() { return Date.now() }

  // A token refresh keeps the same app's quota. Changing the app in Settings
  // must instead cancel its work and start with that app's own pacing state.
  readonly property string quotaIdentity: auth && auth.resolvedClientId !== undefined
    ? String(auth.resolvedClientId) : ""
  property string previousQuotaIdentity: ""
  property bool quotaIdentityReady: false
  // Pacing belongs to the app, not to the transport carrying it: the shipped
  // app moves between the primary and the shared child as Settings change.
  property var pacingMemory: ({})
  property var pacingHome: root
  property var pacingPeer: fallbackTransport
  Component.onCompleted: {
    previousQuotaIdentity = quotaIdentity
    restorePacing(quotaIdentity)
    quotaIdentityReady = true
  }
  Component.onDestruction: rememberPacing(previousQuotaIdentity)
  onQuotaIdentityChanged: {
    if (!quotaIdentityReady || quotaIdentity === previousQuotaIdentity) return
    rememberPacing(previousQuotaIdentity)
    previousQuotaIdentity = quotaIdentity
    cancelAll()
    restorePacing(quotaIdentity)
  }

  function pacingState() {
    return {
      rateLimitedUntil: rateLimitedUntil,
      interactiveLimitedUntil: interactiveLimitedUntil,
      rateLimitedSince: rateLimitedSince,
      cooldownProbeUsed: cooldownProbeUsed,
      restrictInFlight: restrictInFlight,
      backgroundRefusals: backgroundRefusals,
      backgroundSuspendedUntil: backgroundSuspendedUntil,
      lastBackgroundStartedAt: lastBackgroundStartedAt,
      lastInteractiveStartedAt: lastInteractiveStartedAt
    }
  }

  function rememberPacing(identity) {
    if (!identity || !pacingHome) return
    var memory = Object.assign({}, pacingHome.pacingMemory)
    memory[identity] = pacingState()
    pacingHome.pacingMemory = memory
  }

  // A transport still carrying the app knows its latest state; otherwise the
  // last state handed back for that app applies.
  function restorePacing(identity) {
    var peer = pacingPeer
    var state = null
    if (identity && peer && peer !== root && transportAlive(peer)
        && peer.quotaIdentityReady === true && peer.previousQuotaIdentity === identity)
      state = peer.pacingState()
    else if (identity && pacingHome)
      state = pacingHome.pacingMemory[identity] || null
    state = state || ({})
    backgroundPaceTimer.stop()
    rateLimitTimer.stop()
    rateLimitedUntil = state.rateLimitedUntil || 0
    interactiveLimitedUntil = state.interactiveLimitedUntil || 0
    rateLimitedSince = state.rateLimitedSince || 0
    cooldownProbeUsed = state.cooldownProbeUsed === true
    restrictInFlight = state.restrictInFlight === true
    backgroundRefusals = state.backgroundRefusals || 0
    backgroundSuspendedUntil = state.backgroundSuspendedUntil || 0
    lastBackgroundStartedAt = state.lastBackgroundStartedAt || 0
    lastInteractiveStartedAt = state.lastInteractiveStartedAt || 0
  }

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
        priority: job.priority,
        app: appLabel
      }) + (error ? ": " + Api.redact(error) : ""))
    var entry = {
      route: String(job.path || "").split("?")[0].replace(/^https:\/\/api.spotify.com\/v1/, "")
        .replace(/\/(users|artists|albums|tracks|playlists|shows|episodes|audiobooks)\/[^/]+/g, "/$1/:id"),
      method: String(job.method || "GET"), status: status,
      durationMs: elapsed,
      queueMs: Math.max(0, (job.startedAt || now()) - job.queuedAt),
      tokenMs: job.sentAt ? Math.max(0, job.sentAt - job.startedAt) : 0,
      httpMs: job.sentAt ? Math.max(0, now() - job.sentAt) : 0,
      retries: job.rateLimitRetries + (job.retried ? 1 : 0),
      outcome: error ? (status ? "http-error" : "transport-error") : "success"
    }
    diagnostics = diagnostics.concat([entry]).slice(-100)
    releaseRequestSlot(job.handle)
    if (job.handle && job.handle.job === job) job.handle.job = null
    callbackIfCurrent(job, status, payload, error, xhr)
  }

  function finishJob(job, status, payload, error, xhr) {
    if (markJobFinished(job) !== true) return
    deliverJob(job, status, payload, error, xhr)
  }

  function expireTimedOutRequests(timestamp) {
    if (expiringRequests) return
    var current = Number(timestamp)
    if (!isFinite(current)) current = now()
    var jobs = timedJobs.slice()
    // Expire the whole batch before releasing slots can dispatch queued work.
    expiringRequests = true
    try {
      for (var i = 0; i < jobs.length; i++) {
        var job = jobs[i]
        if (!job || job.finished === true) continue
        var deadline = job.deadlineAt || job.activeDeadlineAt
        if (!deadline || current < deadline) continue
        var handle = job.handle
        // The shared queue holds the same deadline and knows why its attempt waited.
        if (handle && forwardedRequestLive(handle)) continue
        var xhr = handle ? handle.xhr : null
        var cooldownMs = Api.apiCooldownMs(current, rateLimitedUntil)
        var waitingForCooldown = cooldownMs > 0 && requestQueue.indexOf(job) >= 0
        var error = waitingForCooldown
          ? Api.rateLimitMessage(String(Math.ceil(cooldownMs / 1000)))
          : "Spotify took too long to respond. Try again."
        if (String(job.method || "GET") !== "GET" && job.sentAt)
          error = "Spotify did not confirm this action. Check playback or your collection before retrying."
        if (markJobFinished(job) !== true) continue
        if (handle) {
          handle.xhr = null
          handle.aborted = true
          removeQueuedHandle(handle)
        }
        if (handle && handle.forwardedRequest)
          abortRequest(handle.forwardedRequest)
        abortXhr(xhr)
        deliverJob(job, 0, null, error, null)
      }
    } finally {
      expiringRequests = false
    }
    pumpRequests()
  }

  function transportAlive(transport) {
    return !!transport && typeof transport.abortRequest === "function"
  }

  function forwardedRequestLive(handle) {
    var forwarded = handle.forwardedRequest
    return !!forwarded && forwarded.aborted !== true && !!forwarded.job
      && forwarded.job.finished !== true && transportAlive(forwarded.owner)
  }

  function abortRequest(handle) {
    if (!handle || handle.aborted) return
    if (handle.owner && handle.owner !== root) {
      if (transportAlive(handle.owner)) {
        handle.owner.abortRequest(handle)
        return
      }
      // Its transport is gone; only the wire request is left to stop.
      handle.aborted = true
      var orphan = handle.xhr
      handle.xhr = null
      abortXhr(orphan)
      return
    }
    if (handle.forwardedRequest) abortRequest(handle.forwardedRequest)
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

  function quotaExceeded(payload) {
    return Api.quotaExceededPayload(payload)
  }

  function requestError(status, payload, xhr, fallback) {
    if (status === 429 && quotaExceeded(payload)) {
      var wait = Api.responseRetryAfter(xhr)
      return "Spotify refused this request because the developer quota for this app is used up. It stays refused until Spotify resets that quota."
        + (wait ? " Spotify asks for " + wait + " s." : "")
    }
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
    if (cancellingAll || expiringRequests) return
    if (pumpingRequests) {
      pumpAgain = true
      return
    }
    pumpingRequests = true
    pumpAgain = false
    while (requestsInFlight < Api.apiInFlightLimit(restrictInFlight)) {
      var limit = Api.apiInFlightLimit(restrictInFlight)
      var cooldown = Api.apiCooldownMs(now(), rateLimitedUntil)
      var backgroundDelay = Math.max(
        Api.apiCooldownMs(now(), backgroundSuspendedUntil),
        Api.backgroundDispatchDelay(lastBackgroundStartedAt,
          lastInteractiveStartedAt, now(), backgroundSpacingMs))
      var allowBackground = cooldown === 0 && backgroundDelay === 0
        && backgroundInFlight < Api.backgroundInFlightLimit(limit)
      var taken = Api.dequeueApiJob(requestQueue, allowBackground)
      var job = taken.job
      if (job && job.deadlineAt && now() >= job.deadlineAt) {
        expireTimedOutRequests(now())
        continue
      }
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
          // Timer.interval is a signed int; recheck longer cooldowns in chunks.
          rateLimitTimer.interval = Math.min(2147483647, Math.max(50, wait))
          rateLimitTimer.restart()
          break
        }
      }
      if (!job) {
        if (jobCooldown > 0 || cooldown > 0) {
          // Timer.interval is a signed int; recheck longer cooldowns in chunks.
          rateLimitTimer.interval = Math.min(2147483647,
            Math.max(50, jobCooldown > 0 ? jobCooldown : cooldown))
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
    job.startedAt = now()
    job.activeDeadlineAt = job.startedAt + activeTimeoutMs
    var url = Api.safeApiUrl(job.path)
    if (!url) {
      finishJob(job, 0, null, "Something went wrong while contacting Spotify", null)
      return
    }
    url = Api.appendQuery(url, job.query)

    // Your own client would only repeat your own list, so a shared request has nowhere else to go.
    if (job.shared === true && !fallbackAuth) {
      finishJob(job, 0, null, "Not logged in", null)
      return
    }
    if (job.shared === true) {
      forwardToShared(job)
      return
    }
    var identity = job.fellBack === true && fallbackAuth ? fallbackAuth : auth
    identity.withAccessToken(function(token, tokenError) {
      job.authedAt = now()
      if (handle.aborted) {
        releaseRequestSlot(handle)
        return
      }
      if (!token) {
        finishJob(job, 0, null, tokenError || "Not logged in", null)
        return
      }
      job.sentAt = now()
      job.activeDeadlineAt = job.sentAt + activeTimeoutMs
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
            identity.invalidateAccessToken()
            job.activeDeadlineAt = 0
            job.retried = true
            requestQueue = Api.enqueueApiJob(requestQueue, job)
            releaseRequestSlot(handle)
            return
          }
          if (xhr.status === 429 && !quotaExceeded(payload)) {
            restrictInFlight = true
            backgroundRefusals += 1
            rateLimitedSince = now()
            cooldownProbeUsed = false
            rateLimitedUntil = Api.nextRateLimitedUntil(now(),
              Api.responseRetryAfter(xhr), rateLimitedUntil, job.rateLimitRetries)
            backgroundSuspendedUntil = Math.max(backgroundSuspendedUntil,
              rateLimitedUntil, now() + Api.API_BACKGROUND_RECOVERY_MS)
            if (Api.apiJobPriority(job) >= 1)
              interactiveLimitedUntil = Api.nextRateLimitedUntil(now(),
                Api.responseRetryAfter(xhr), interactiveLimitedUntil,
                job.rateLimitRetries)
            console.warn("Spotify API rate limited on "
              + String(job.method || "GET") + " " + Api.redact(String(job.path || ""))
              + "; pausing every request for "
              + Api.apiCooldownMs(now(), rateLimitedUntil) + " ms"
              + " (retry " + job.rateLimitRetries
              + ", background gap now " + backgroundSpacingMs + " ms) " + appLabel)
            var resumeAt = Api.apiJobPriority(job) >= 1
              ? interactiveLimitedUntil : rateLimitedUntil
            if (job.retryRateLimit !== false
                && Api.shouldRetryRateLimit(job.rateLimitRetries)
                && (!job.deadlineAt || resumeAt <= job.deadlineAt)) {
              job.activeDeadlineAt = 0
              job.rateLimitRetries += 1
              requestQueue = Api.enqueueApiJob(requestQueue, job)
              releaseRequestSlot(handle)
              return
            }
          } else {
            restrictInFlight = false
          }
          // Refused by the personal client: try the shipped one, which still
          // reaches the catalog endpoints Spotify closed to new apps.
          // Without a session of its own, the retry would hide the refusal behind "Not logged in".
          if (job.allowFallback !== false && Api.shouldFallBackToSharedClient(xhr.status, job.fellBack,
              !!fallbackAuth && fallbackAuth.loggedIn === true, job.method, job.path)) {
            forwardToShared(job)
            return
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

  // Each authorized app has its own queue and cooldown. The parent retains
  // the original deadline and cancellation handle across the fallback attempt.
  function forwardToShared(job) {
    if (!fallbackTransport) {
      finishJob(job, 0, null, "Not logged in", null)
      return
    }
    job.fellBack = true
    job.activeDeadlineAt = 0
    releaseRequestSlot(job.handle)
    job.handle.forwardedRequest = fallbackTransport.request(job.method,
      job.path, job.query, job.body, function(status, payload, error, xhr) {
        if (job.finished || job.handle.aborted) return
        finishJob(job, status, payload, error, xhr)
      }, {
        priority: job.priority,
        retryRateLimit: job.retryRateLimit,
        timeoutMs: job.deadlineAt ? Math.max(1, job.deadlineAt - now()) : 0
      })
  }

  function callbackIfCurrent(job, status, payload, error, xhr) {
    if (typeof job.callback === "function")
      job.callback(status, payload, error, xhr)
  }

  function request(method, path, query, body, callback, options) {
    var settings = options || ({})
    var handle = { aborted: false, xhr: null, job: null, owner: root }
    var background = Api.apiJobPriority({ method: method,
      priority: settings.priority }) < 0
    // Bound the whole wait, including the queue and repeated rate limits.
    // Optional crawling can wait for recovery without tying up an open page.
    var timeoutMs = settings.timeoutMs !== undefined
      ? Math.max(0, Number(settings.timeoutMs) || 0)
      : (background ? 0 : Api.API_FOREGROUND_TIMEOUT_MS)
    var queuedAt = now()
    var job = {
      method: method,
      path: path,
      query: query,
      body: body,
      callback: callback,
      retried: false,
      fellBack: false,
      shared: settings.shared === true,
      allowFallback: settings.allowFallback !== false,
      rateLimitRetries: 0,
      retryRateLimit: settings.retryRateLimit !== undefined
        ? settings.retryRateLimit === true : !background,
      priority: String(settings.priority || ""),
      timeoutMs: timeoutMs,
      queuedAt: queuedAt,
      deadlineAt: timeoutMs > 0 ? queuedAt + timeoutMs : 0,
      finished: false,
      handle: handle
    }
    handle.job = job
    timedJobs = timedJobs.concat([job])
    if (job.shared === true && fallbackTransport) {
      forwardToShared(job)
      return handle
    }
    return enqueueJob(job)
  }

  function cancelAll() {
    cancellingAll = true
    cancelForwardedRequests()
    var jobs = timedJobs.slice()
    for (var i = 0; i < jobs.length; i++) abortRequest(jobs[i].handle)
    cancelSearch()
    cancellingAll = false
  }

  // Cancelled with the shared transport that carries them, as on sign-out.
  // That queue is emptied first: freeing one of its slots would send its next job.
  function cancelForwardedRequests() {
    var jobs = timedJobs.slice()
    var i
    for (i = 0; i < jobs.length; i++) {
      var forwarded = jobs[i].handle ? jobs[i].handle.forwardedRequest : null
      if (forwarded && transportAlive(forwarded.owner)) forwarded.owner.cancelAll()
    }
    for (i = 0; i < jobs.length; i++)
      if (jobs[i].handle && jobs[i].handle.forwardedRequest) abortRequest(jobs[i].handle)
  }

  function cancelSearch() {
    searchSerial++
    abortRequest(searchRequest)
    searchRequest = null
  }

  // Search still uses its own serial so a newer query can reject a stale
  // callback created while a token refresh is still in flight.
  function search(query, type, callback) {
    cancelSearch()
    var serial = searchSerial
    var term = String(query || "").trim()
    var searchType = Api.normalizedSearchType(type)
    if (!term) {
      if (typeof callback === "function") callback(Api.searchGroups({}, 128), "")
      return
    }
    searchRequest = request("GET", "/search", {
      q: term,
      type: searchType,
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
    objectName: "rateLimitTimer"
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
