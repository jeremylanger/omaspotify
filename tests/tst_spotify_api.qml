pragma ComponentBehavior: Bound

import QtQuick
import QtTest

import ".." as Plugin

import "../Api.js" as Api

TestCase {
  id: testCase
  name: "SpotifyApiTransport"

  property var requests: []
  property double clock: 1000
  property int tokenInvalidations: 0
  property string accessToken: "mock-token"
  property string accessTokenError: ""
  property bool failFactory: false
  property bool failOpen: false
  property bool failSend: false

  QtObject {
    id: fakeAuth

    function withAccessToken(callback) {
      callback(testCase.accessToken, testCase.accessTokenError)
    }
    function invalidateAccessToken() { testCase.tokenInvalidations++ }
  }

  Component {
    id: apiComponent

    Plugin.SpotifyApi {
      auth: fakeAuth
      now: function() { return testCase.clock }
      xhrFactory: function() {
        if (testCase.failFactory) throw new Error("factory failed")
        return testCase.newRequest()
      }
    }
  }

  function newRequest() {
    var xhr = {
      readyState: XMLHttpRequest.UNSENT,
      status: 0,
      retryAfter: "1",
      responseText: "",
      url: "",
      method: "",
      aborted: false,
      onreadystatechange: null,
      open: function(method, url) {
        if (testCase.failOpen) throw new Error("open failed")
        this.method = method
        this.url = url
        this.readyState = XMLHttpRequest.OPENED
      },
      setRequestHeader: function() {},
      getResponseHeader: function(name) {
        return String(name).toLowerCase() === "retry-after" ? this.retryAfter : ""
      },
      send: function() {
        if (testCase.failSend) throw new Error("send failed")
      },
      abort: function() { this.aborted = true }
    }
    requests.push(xhr)
    return xhr
  }

  function complete(xhr, status, body) {
    xhr.status = status
    xhr.responseText = body || "{}"
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }

  function init() {
    requests = []
    clock = 1000
    tokenInvalidations = 0
    accessToken = "mock-token"
    accessTokenError = ""
    failFactory = false
    failOpen = false
    failSend = false
  }

  function test_priorityStartsMutationsThenInteractiveReads() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var limit = fillEverySlot(api)
    api.request("GET", "/me/albums", null, null, function() {})
    api.request("GET", "/search", null, null, function() {},
      { priority: "interactive" })
    api.request("PUT", "/me/player/play", null, null, function() {})
    compare(requests.length, limit, "nothing else starts while every slot is busy")

    complete(requests[0], 200)
    compare(requests.length, limit + 1)
    compare(requests[limit].method, "PUT", "a mutation jumps the queue")

    complete(requests[1], 200)
    compare(requests.length, limit + 2)
    verify(requests[limit + 1].url.indexOf("/search") >= 0)
  }

  function test_searchRequestsOnlyTheSelectedType() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.search("miles davis", "album", function(groups, error) {
      callbacks++
      compare(error, "")
    })
    compare(requests.length, 1)
    verify(requests[0].url.indexOf("type=album") >= 0)
    verify(requests[0].url.indexOf("artist%2Calbum") < 0)
    complete(requests[0], 200, "{\"albums\":{\"items\":[]}}")
    compare(callbacks, 1)
  }

  function test_searchFallsBackToTracksForAnInvalidType() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.search("miles davis", "unknown", function() {})
    compare(requests.length, 1)
    verify(requests[0].url.indexOf("type=track") >= 0)
  }

  function test_searchTimeoutAbortsAndReleasesSlotOnce() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    var error = ""
    api.search("stalled", "track", function(groups, reason) {
      callbacks++
      error = reason
    })
    compare(api.requestsInFlight, 1)
    clock = 9000
    api.expireTimedOutRequests(clock)
    verify(requests[0].aborted)
    verify(error.indexOf("too long") >= 0)
    compare(callbacks, 1)
    compare(api.requestsInFlight, 0)
    compare(api.timedJobs.length, 0)

    complete(requests[0], 0)
    compare(callbacks, 1)
    compare(api.requestsInFlight, 0)
  }

  function test_queuedSearchTimesOutBeforeARequestSlotOpens() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var limit = fillEverySlot(api)
    compare(api.requestsInFlight, limit)
    var error = ""
    api.search("queued", "track", function(groups, reason) { error = reason })
    compare(requests.length, limit)
    compare(api.requestQueue.length, 1)
    clock = 9000
    api.expireTimedOutRequests(clock)
    verify(error.indexOf("too long") >= 0)
    compare(api.requestQueue.length, 0)
    compare(api.requestsInFlight, limit)
  }

  function test_searchBlockedByCooldownReportsRemainingWait() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.rateLimitedUntil = 15000
    var errors = []
    api.search("waiting", "track", function(groups, error) { errors.push(error) })
    compare(requests.length, 1,
      "the first interactive job may probe a cooldown instead of waiting it out")
    complete(requests[0], 429, "{\"error\":{\"message\":\"Too many requests\"}}")
    compare(errors.length, 1)
    verify(errors[0].indexOf("Spotify is busy") >= 0,
      "the refused probe reports the wait honestly")
    compare(api.requestQueue.length, 0)
    compare(api.timedJobs.length, 0)
    compare(api.requestsInFlight, 0)
  }

  function test_inFlightSearchStillReportsTimeoutDuringAnotherCooldown() {
    var api = createTemporaryObject(apiComponent, testCase)
    var error = ""
    api.search("sent", "track", function(groups, reason) { error = reason })
    api.rateLimitedUntil = 15000
    clock = 9000
    api.expireTimedOutRequests(clock)
    compare(error, "Spotify took too long to respond. Try again.")
    verify(requests[0].aborted)
  }

  function test_cooldownCanExpireBeforeSearchDeadline() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.rateLimitedUntil = 4000
    var errors = []
    api.search("waiting", "track", function(groups, error) { errors.push(error) })
    clock = 4000
    api.pumpRequests()
    compare(requests.length, 1)
    complete(requests[0], 200, "{\"tracks\":{\"items\":[]}}")
    clock = 9000
    api.expireTimedOutRequests(clock)
    compare(errors, [""])
  }

  function test_cancelledSearchDuringCooldownHasNoStaleError() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.rateLimitedUntil = 15000
    var oldCalls = 0
    var newErrors = []
    api.search("old", "track", function() { oldCalls++ })
    clock = 2000
    api.search("new", "track", function(groups, error) { newErrors.push(error) })
    verify(requests[0].aborted, "a newer search cancels the probe")
    compare(requests.length, 2)
    complete(requests[1], 429, "{\"error\":{\"message\":\"Too many requests\"}}")
    compare(oldCalls, 0)
    compare(newErrors.length, 1)
    verify(newErrors[0].indexOf("Spotify is busy") >= 0)
    compare(api.requestsInFlight, 0)
  }

  function test_expiredCooldownDoesNotMislabelQueuedTimeout() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.rateLimitedUntil = 9000
    var error = ""
    api.search("waiting", "track", function(groups, reason) { error = reason })
    clock = 9000
    api.expireTimedOutRequests(clock)
    compare(error, "Spotify took too long to respond. Try again.")
  }

  function test_search429ReturnsWithoutSilentRetry() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    var error = ""
    api.search("busy", "track", function(groups, reason) {
      callbacks++
      error = reason
    })
    complete(requests[0], 429, "{\"error\":{\"message\":\"Too many requests\"}}")
    compare(callbacks, 1)
    verify(error.indexOf("Spotify is busy") >= 0)
    compare(api.requestQueue.length, 0)
    compare(api.requestsInFlight, 0)
    verify(api.rateLimitedUntil > clock)
  }

  // The library crawl being refused used to pause every request, so opening a
  // page while it ran cost the whole twenty-second cooldown.
  function test_backgroundRefusalDoesNotStallAnOpenedPage() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.request("GET", "/me/albums", null, null, function() {},
      { priority: "background", retryRateLimit: false })
    complete(requests[0], 429)
    verify(api.rateLimitedUntil > clock, "background work is told to wait")
    compare(api.interactiveLimitedUntil, 0, "the person was not refused")

    var opened = 0
    api.request("GET", "/playlists/discover-weekly", null, null,
      function() { opened++ }, { priority: "interactive" })
    compare(requests.length, 2, "the opened page goes out straight away")
    complete(requests[1], 200)
    compare(opened, 1)
  }

  // Their own request being refused still holds them back.
  function test_ownRefusalStillPausesTheOpenedPage() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.request("GET", "/playlists/one", null, null, function() {},
      { priority: "interactive", retryRateLimit: false })
    complete(requests[0], 429)
    verify(api.interactiveLimitedUntil > clock)

    api.request("GET", "/playlists/two", null, null, function() {},
      { priority: "interactive" })
    compare(requests.length, 1, "the next page waits its turn")
    clock = api.interactiveLimitedUntil
    api.pumpRequests()
    compare(requests.length, 2)
  }

  function test_default429StillRetriesAfterCooldown() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.request("GET", "/me", null, null, function() { callbacks++ })
    complete(requests[0], 429)
    compare(callbacks, 0)
    compare(api.requestQueue.length, 1)
    clock = api.rateLimitedUntil
    api.pumpRequests()
    compare(requests.length, 2)
    complete(requests[1], 200)
    compare(callbacks, 1)
  }

  function test_long429BlocksRetryAndOtherRequestsUntilDeadline() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.request("GET", "/me", null, null, function() { callbacks++ })
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    compare(api.rateLimitedUntil, 121400)
    api.request("GET", "/me/albums", null, null, function() { callbacks++ })

    clock = 31000
    api.pumpRequests()
    compare(requests.length, 1)
    clock = 121399
    api.pumpRequests()
    compare(requests.length, 1)
    compare(callbacks, 0)

    clock = 121400
    api.pumpRequests()
    // The first retry stays serial until a successful response clears 429 mode.
    compare(requests.length, 2)
    complete(requests[1], 200)
    compare(requests.length, 3)
    complete(requests[2], 200)
    compare(callbacks, 2)
    compare(api.requestQueue.length, 0)
  }

  function test_cooldownLongerThanTimerRangeRechecksWithoutDispatchingEarly() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.request("GET", "/me", null, null, function() {})
    requests[0].retryAfter = "3000000"
    complete(requests[0], 429)
    var deadline = 3000001400
    compare(api.rateLimitedUntil, deadline)
    var timer = findChild(api, "rateLimitTimer")
    verify(timer)
    compare(timer.interval, 2147483647)
    verify(timer.running)

    clock = 1000 + 2147483647
    timer.triggered()
    compare(requests.length, 1)
    compare(api.rateLimitedUntil, deadline)
    compare(timer.interval, deadline - clock)
    verify(timer.interval > 0)

    clock = deadline - 1
    timer.triggered()
    compare(requests.length, 1)
    clock = deadline
    timer.triggered()
    compare(requests.length, 2)
    complete(requests[1], 200)
  }

  function test_longSearch429DoesNotSilentlyRetry() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.search("busy", "track", function(groups, error) {
      callbacks++
      verify(error.indexOf("120 seconds") >= 0)
    })
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    compare(callbacks, 1)
    compare(api.requestQueue.length, 0)
    clock = 121400
    api.pumpRequests()
    compare(requests.length, 1)
    compare(callbacks, 1)
  }

  function test_401RetriesWithOneTokenInvalidation() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.request("GET", "/me", null, null, function() { callbacks++ })
    var firstRequest = requests[0]
    complete(requests[0], 401)
    compare(tokenInvalidations, 1)
    compare(callbacks, 0)
    compare(requests.length, 2)
    complete(firstRequest, 200)
    compare(callbacks, 0)
    complete(requests[1], 200)
    compare(callbacks, 1)
  }

  function test_newSearchCancelsStaleActiveRequest() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var staleCalls = 0
    var currentCalls = 0
    api.search("old", "track", function() { staleCalls++ })
    var oldRequest = requests[0]
    api.search("new", "artist", function() { currentCalls++ })
    verify(oldRequest.aborted)
    compare(requests.length, 2)
    complete(oldRequest, 200, "{\"tracks\":{\"items\":[]}}")
    complete(requests[1], 200, "{\"tracks\":{\"items\":[]}}")
    compare(staleCalls, 0)
    compare(currentCalls, 1)
    compare(api.requestsInFlight, 0)
  }

  // Occupy every request slot, whatever the current limit is.
  function fillEverySlot(api) {
    var limit = Api.apiInFlightLimit(false)
    for (var i = 0; i < limit; i++)
      api.request("GET", "/fill/" + i, null, null, function() {})
    compare(requests.length, limit)
    return limit
  }

  function test_cancelledQueuedRequestNeverStarts() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var limit = fillEverySlot(api)
    var callbacks = 0
    var handle = api.request("GET", "/search", null, null,
      function() { callbacks++ }, {
        priority: "interactive",
        timeoutMs: 8000
      })
    compare(api.requestQueue.length, 1)
    api.abortRequest(handle)
    compare(api.requestQueue.length, 0)
    complete(requests[0], 200)
    compare(requests.length, limit)
    compare(callbacks, 0)
    compare(api.timedJobs.length, limit - 1,
      "the still-running fills keep their deadlines; the aborted one drops its")
  }

  // A cancelled background request has to hand its slot back, or the library
  // crawl runs out of room and never finishes.
  function test_abortedBackgroundRequestHandsItsSlotBack() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var first = api.request("GET", "/me/tracks", null, null, function() {},
      { priority: "background" })
    clock += 1000
    api.request("GET", "/me/albums", null, null, function() {},
      { priority: "background" })
    compare(requests.length, 2, "both background slots are busy")
    compare(api.backgroundInFlight, 2)

    api.abortRequest(first)
    compare(api.backgroundInFlight, 1, "the cancelled one gave its slot back")
    clock += 1000
    api.request("GET", "/me/shows", null, null, function() {},
      { priority: "background" })
    compare(requests.length, 3, "so the next page can start")
  }

  function test_timeoutUsesInclusiveDeadlineBoundary() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.request("GET", "/search", null, null, function() { callbacks++ },
      { timeoutMs: 1000 })
    api.expireTimedOutRequests(1999)
    compare(callbacks, 0)
    verify(!requests[0].aborted)
    clock = 2000
    api.expireTimedOutRequests(clock)
    compare(callbacks, 1)
    verify(requests[0].aborted)
  }

  function test_queuedRateLimitRetryCanTimeOutDuringCooldown() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    var error = ""
    api.request("GET", "/me", null, null, function(status, payload, reason) {
      callbacks++
      error = reason
    }, { timeoutMs: 2000 })
    complete(requests[0], 429)
    compare(api.requestQueue.length, 1)
    clock = 3000
    api.expireTimedOutRequests(clock)
    compare(callbacks, 1)
    verify(error.indexOf("too long") >= 0)
    compare(api.requestQueue.length, 0)
  }

  function test_invalidUrlAndTokenFailureReleaseSlots() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var errors = 0
    api.request("GET", "https://example.com/not-spotify", null, null,
      function(status, payload, error) { if (error) errors++ })
    compare(errors, 1)
    compare(api.requestsInFlight, 0)

    accessToken = ""
    accessTokenError = "Session unavailable"
    api.request("GET", "/me", null, null,
      function(status, payload, error) { if (error) errors++ })
    compare(errors, 2)
    compare(api.requestsInFlight, 0)
  }

  function test_xhrSetupFailuresReleaseSlots() {
    var modes = ["factory", "open", "send"]
    for (var i = 0; i < modes.length; i++) {
      failFactory = modes[i] === "factory"
      failOpen = modes[i] === "open"
      failSend = modes[i] === "send"
      var api = createTemporaryObject(apiComponent, testCase)
      verify(api)
      var callbacks = 0
      api.request("GET", "/me", null, null,
        function(status, payload, error) {
          callbacks++
          verify(error !== "")
        })
      compare(callbacks, 1)
      compare(api.requestsInFlight, 0)
      api.destroy()
    }
  }

  function test_backgroundWatchdogReleasesSlots() {
    var api = createTemporaryObject(apiComponent, testCase)
    var calls = 0
    api.request("GET", "/me", null, null, function() { calls++ })
    api.request("GET", "/me/player", null, null, function() { calls++ })
    clock = 16000
    api.expireTimedOutRequests(clock)
    compare(calls, 2)
    compare(api.requestsInFlight, 0)
    verify(requests[0].aborted)
    complete(requests[0], 200)
    compare(calls, 2)
  }

  function test_backgroundCooldownDoesNotConsumeActiveTimeout() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.rateLimitedUntil = 121000
    var calls = 0
    api.request("GET", "/me", null, null, function() { calls++ })
    clock = 120000
    api.expireTimedOutRequests(clock)
    compare(calls, 0)
    compare(requests.length, 0)
    clock = 121000
    api.pumpRequests()
    compare(requests.length, 1)
    api.expireTimedOutRequests(clock)
    compare(calls, 0)
    complete(requests[0], 200)
    compare(calls, 1)
  }

  function test_quotaExceededDoesNotRetryOrInventCooldown() {
    var api = createTemporaryObject(apiComponent, testCase)
    var error = ""
    api.request("GET", "/search?q=private-query", null, null,
      function(status, payload, reason) { error = reason })
    complete(requests[0], 429, '{"error":{"reason":"QUOTA_EXCEEDED"}}')
    verify(error.indexOf("developer quota") >= 0)
    compare(api.rateLimitedUntil, 0)
    compare(api.requestQueue.length, 0)
    compare(api.diagnostics[0].route, "/search")
    verify(JSON.stringify(api.diagnostics).indexOf("private-query") < 0)
  }
}
