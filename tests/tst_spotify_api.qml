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
  property int sharedInvalidations: 0
  property string sharedToken: "shared-token"
  property bool sharedLoggedIn: true

  QtObject {
    id: fakeAuth

    property string resolvedClientId: "old-app"

    function withAccessToken(callback) {
      callback(testCase.accessToken, testCase.accessTokenError)
    }
    function invalidateAccessToken() { testCase.tokenInvalidations++ }
  }

  QtObject {
    id: fakeSharedAuth

    property bool loggedIn: testCase.sharedLoggedIn
    function withAccessToken(callback) {
      callback(testCase.sharedToken, testCase.sharedToken ? "" : "Log in to Spotify first")
    }
    function invalidateAccessToken() { testCase.sharedInvalidations++ }
  }

  QtObject {
    id: shippedAuth

    property string resolvedClientId: "old-app"
    property bool loggedIn: true
    function withAccessToken(callback) { callback("shipped-token", "") }
    function invalidateAccessToken() {}
  }

  QtObject {
    id: otherSharedAuth

    property bool loggedIn: true
    function withAccessToken(callback) { callback("other-shared-token", "") }
    function invalidateAccessToken() {}
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
      authorization: "",
      setRequestHeader: function(name, value) {
        if (String(name).toLowerCase() === "authorization") this.authorization = value
      },
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
    fakeAuth.resolvedClientId = "old-app"
    requests = []
    clock = 1000
    tokenInvalidations = 0
    accessToken = "mock-token"
    accessTokenError = ""
    failFactory = false
    failOpen = false
    failSend = false
    sharedInvalidations = 0
    sharedToken = "shared-token"
    sharedLoggedIn = true
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

  function test_backgroundWarmCanDeclineSharedFallback() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    var result = 0
    api.request("GET", "/playlists/foreign/items", null, null,
      function(status) { result = status },
      { priority: "background", allowFallback: false, retryRateLimit: false })
    complete(requests[0], 403)
    compare(result, 403)
    compare(requests.length, 1, "warming must not hammer the shared catalog app")
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

  // A personal client id is refused the catalog endpoints, so what it cannot
  // answer is asked again through the shipped one.
  function test_catalogRefusalIsRetriedThroughTheSharedClient() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.fallbackAuth = fakeSharedAuth
    var results = []
    api.request("GET", "/artists/abc/related-artists", null, null,
      function(status) { results.push(status) })
    compare(requests.length, 1)
    complete(requests[0], 403)

    compare(results.length, 0, "the caller is not told about the first refusal")
    compare(requests.length, 2, "it is asked again")
    complete(requests[1], 200)
    compare(results, [200])
  }

  function test_theRetryUsesTheOtherIdentitysToken() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.fallbackAuth = fakeSharedAuth
    api.request("GET", "/artists/abc/albums", null, null, function() {})
    complete(requests[0], 400)
    compare(requests.length, 2)
    compare(requests[1].authorization, "Bearer shared-token")
  }

  function test_aTokenProblemRefreshesRatherThanSwitchingIdentity() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.fallbackAuth = fakeSharedAuth
    api.request("GET", "/me", null, null, function() {})
    complete(requests[0], 401)
    compare(tokenInvalidations, 1, "the identity that failed is refreshed")
    compare(sharedInvalidations, 0)
    compare(requests.length, 2)
    compare(requests[1].authorization, "Bearer mock-token", "still the personal id")
  }

  function test_aSharedRequestGoesThroughTheShippedClient() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.fallbackAuth = fakeSharedAuth
    sharedLoggedIn = false
    var results = []
    api.request("GET", "/me/playlists", { limit: 50 }, null,
      function(status) { results.push(status) }, { shared: true })
    compare(requests[0].authorization, "Bearer shared-token",
      "it waits for the shared client to finish signing in")
    complete(requests[0], 403)
    compare(requests.length, 1, "it is not asked twice on the same client")
    compare(results, [403])
  }

  function test_aSharedRequestIsNotSentWithoutASharedSession() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var errors = []
    api.request("GET", "/me/playlists", null, null,
      function(status, payload, error) { errors.push(error) }, { shared: true })
    api.fallbackAuth = fakeSharedAuth
    sharedToken = ""
    api.request("GET", "/me/playlists", null, null,
      function(status, payload, error) { errors.push(error) }, { shared: true })
    compare(requests.length, 0, "your own client would only repeat your own list")
    compare(errors.length, 2)
    verify(errors[0] !== "" && errors[1] !== "")
  }

  function test_aSignedOutSharedClientIsNotAskedAgain() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    api.fallbackAuth = fakeSharedAuth
    sharedLoggedIn = false
    var results = []
    api.request("GET", "/artists/abc/related-artists", null, null,
      function(status) { results.push(status) })
    complete(requests[0], 403)
    compare(requests.length, 1, "the refusal is not hidden behind a sign-in error")
    compare(results, [403])
  }

  function test_withoutAPersonalIdNothingIsRetriedElsewhere() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var results = []
    api.request("GET", "/artists/abc/related-artists", null, null,
      function(status) { results.push(status) })
    complete(requests[0], 403)
    compare(requests.length, 1, "there is nowhere else to ask")
    compare(results, [403])
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
    api.request("GET", "/me", null, null, function() { callbacks++ },
      { timeoutMs: 0 })
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    compare(api.rateLimitedUntil, 121400)
    api.request("GET", "/me/albums", null, null, function() { callbacks++ },
      { timeoutMs: 0 })

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
    api.request("GET", "/me", null, null, function() {}, { timeoutMs: 0 })
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
    api.request("GET", "/me", null, null, function() { calls++ },
      { priority: "background" })
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

  function test_defaultPageDeadlineIncludesRateLimitRetries() {
    var api = createTemporaryObject(apiComponent, testCase)
    var errors = []
    api.request("GET", "/me/albums", null, null,
      function(status, payload, error) { errors.push(error) })
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    clock += Api.API_FOREGROUND_TIMEOUT_MS
    api.expireTimedOutRequests(clock)
    compare(errors.length, 1, "the page is no longer loading indefinitely")
    verify(errors[0].indexOf("Spotify is busy") >= 0)
    compare(api.requestQueue.length, 0)
    compare(api.timedJobs.length, 0)
    clock = api.rateLimitedUntil
    api.pumpRequests()
    compare(requests.length, 1, "an expired read is never retried later")
  }

  function test_expiredMutationIsRemovedBeforeSlotsAreReleased() {
    var api = createTemporaryObject(apiComponent, testCase)
    var limit = fillEverySlot(api)
    var errors = []
    api.request("PUT", "/me/player/play", null, null,
      function(status, payload, error) { errors.push(error) })
    clock += Api.API_FOREGROUND_TIMEOUT_MS
    api.expireTimedOutRequests(clock)
    compare(errors.length, 1)
    compare(requests.length, limit, "timed-out Play must not be sent late")
    compare(api.requestsInFlight, 0)
    compare(api.requestQueue.length, 0)
  }

  function test_background429YieldsRecoveryTimeToForeground() {
    var api = createTemporaryObject(apiComponent, testCase)
    var errors = []
    api.request("GET", "/me/albums", null, null,
      function(status, payload, error) { errors.push(error) },
      { priority: "background" })
    api.request("GET", "/me/shows", null, null, function() {},
      { priority: "background" })
    complete(requests[0], 429)
    compare(errors.length, 1, "optional work does not silently retry four times")
    compare(api.requestQueue.length, 1)
    clock = api.rateLimitedUntil
    api.pumpRequests()
    compare(requests.length, 1, "the next crawl cannot immediately hit the quota again")
    api.request("GET", "/me/player", null, null, function() {})
    compare(requests.length, 2, "playback can use the recovered budget")
    complete(requests[1], 200)
    api.pumpRequests()
    compare(requests.length, 2, "a successful poll does not restart the crawl early")
    clock = api.backgroundSuspendedUntil
    api.pumpRequests()
    compare(requests.length, 3, "the crawl resumes after its recovery interval")
    verify(requests[2].url.indexOf("/me/shows") >= 0)
  }

  function test_longRefusalReturnsBeforeWatchdog() {
    var api = createTemporaryObject(apiComponent, testCase)
    var statuses = []
    var errors = []
    api.request("GET", "/playlists/uncached/items", null, null,
      function(status, payload, error) { statuses.push(status); errors.push(error) },
      { priority: "interactive" })
    requests[0].retryAfter = "30"
    complete(requests[0], 429)
    compare(statuses.length, 1, "a retry that cannot fit the deadline reports at once")
    compare(statuses[0], 429)
    verify(errors[0].indexOf("Try again in 30 seconds") >= 0)
    compare(api.timedJobs.length, 0)
    compare(api.requestQueue.length, 0)
    verify(api.backgroundSuspendedUntil >= clock + Api.API_BACKGROUND_RECOVERY_MS)
    api.expireTimedOutRequests(clock + Api.API_FOREGROUND_TIMEOUT_MS)
    clock = api.interactiveLimitedUntil
    api.pumpRequests()
    compare(statuses.length, 1, "the refused page is never reported twice")
    compare(requests.length, 1, "nothing is sent ahead of or after Retry-After")
  }

  function test_shortRefusalRetriesWithinDeadline() {
    var api = createTemporaryObject(apiComponent, testCase)
    var statuses = []
    api.request("GET", "/playlists/uncached/items", null, null,
      function(status) { statuses.push(status) }, { priority: "interactive" })
    requests[0].retryAfter = "2"
    complete(requests[0], 429)
    compare(statuses.length, 0)
    clock = api.interactiveLimitedUntil - 1
    api.pumpRequests()
    compare(requests.length, 1, "Retry-After is respected")
    clock = api.interactiveLimitedUntil
    api.pumpRequests()
    compare(requests.length, 2)
    complete(requests[1], 200)
    compare(statuses, [200])
  }

  function test_cancelledRefusedRequestIsNotRetried() {
    var api = createTemporaryObject(apiComponent, testCase)
    var calls = 0
    var handle = api.request("GET", "/playlists/uncached/items", null, null,
      function() { calls++ }, { priority: "interactive" })
    requests[0].retryAfter = "2"
    complete(requests[0], 429)
    api.abortRequest(handle)
    clock = api.interactiveLimitedUntil
    api.pumpRequests()
    api.expireTimedOutRequests(clock + Api.API_FOREGROUND_TIMEOUT_MS)
    compare(requests.length, 1)
    compare(calls, 0)
    compare(api.requestsInFlight, 0)
  }

  function test_pageRevalidationRunsAheadOfLibraryCrawl() {
    var api = createTemporaryObject(apiComponent, testCase)
    var crawl = []
    api.request("GET", "/me/albums", null, null, function() {},
      { priority: "background" })
    for (var i = 0; i < 3; i++)
      api.request("GET", "/me/albums", { offset: 50 * (i + 1) }, null,
        function() {}, { priority: "background" })
    var checked = 0
    api.request("GET", "/playlists/cached/items", null, null,
      function() { checked++ }, { priority: "revalidate", timeoutMs: 15000 })
    compare(requests.length, 1, "background spacing still applies")
    clock += Api.backgroundSpacingForRefusals(0)
    api.pumpRequests()
    compare(requests.length, 2)
    verify(requests[1].url.indexOf("/playlists/cached/items") >= 0,
      "the page check overtakes queued library pages")
    complete(requests[0], 429)
    complete(requests[1], 429)
    compare(checked, 1, "a refused check is not retried")
    clock = api.rateLimitedUntil
    api.pumpRequests()
    compare(requests.length, 2, "the recovery pause still holds the crawl")
    clock = api.backgroundSuspendedUntil
    api.pumpRequests()
    compare(requests.length, 3)
  }

  function test_expiredMutationCannotDispatchBetweenWatchdogTicks() {
    var api = createTemporaryObject(apiComponent, testCase)
    var limit = fillEverySlot(api)
    var errors = []
    api.request("PUT", "/me/player/play", null, null,
      function(status, payload, error) { errors.push(error) },
      { timeoutMs: 1000 })
    clock = 2000
    complete(requests[0], 200)
    compare(requests.length, limit, "expired Play must not dispatch between watchdog ticks")
    compare(errors.length, 1)
    verify(errors[0].indexOf("took too long") >= 0)
    compare(api.requestsInFlight, limit - 1)
    compare(api.requestQueue.length, 0)
    api.expireTimedOutRequests(clock)
    compare(errors.length, 1, "the expired Play reports once")
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
  function test_sharedRefusalDoesNotPausePersonalRead() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    api.request("GET", "/artists/catalog/albums", null, null, function() {},
      { priority: "interactive" })
    complete(requests[0], 403)
    compare(requests.length, 2)
    compare(requests[1].authorization, "Bearer shared-token")
    requests[1].retryAfter = "30"
    complete(requests[1], 429)
    api.request("GET", "/playlists/owned/items", null, null, function() {},
      { priority: "interactive" })
    compare(requests.length, 3, "A shared-client refusal must not hold a personal-client read")
    compare(requests[2].authorization, "Bearer mock-token")
    complete(requests[2], 200)
  }

  function test_personalRefusalDoesNotPauseSharedRead() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    api.request("GET", "/me", null, null, function() {},
      { priority: "interactive", retryRateLimit: false })
    requests[0].retryAfter = "30"
    complete(requests[0], 429)
    api.request("GET", "/me/playlists", null, null, function() {},
      { priority: "interactive", shared: true })
    // Direct shared jobs must bypass even the primary queue's cooldown.
    compare(requests.length, 2)
    compare(requests[1].authorization, "Bearer shared-token")
  }

  function test_fallbackCancellationAbortsWireRequest() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    var calls = 0
    var handle = api.request("GET", "/artists/catalog/albums", null, null,
      function() { calls++ }, { priority: "interactive" })
    complete(requests[0], 403)
    api.abortRequest(handle)
    verify(requests[1].aborted)
    complete(requests[1], 200)
    compare(calls, 0)
    compare(api.timedJobs.length, 0)
    compare(api.fallbackTransport.timedJobs.length, 0)
    compare(api.requestsInFlight, 0)
    compare(api.fallbackTransport.requestsInFlight, 0)
  }

  function test_fallbackKeepsOriginalDeadline() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    var results = []
    api.request("GET", "/artists/catalog/albums", null, null,
      function(status) { results.push(status) },
      { priority: "interactive", timeoutMs: 1000 })
    clock += 900
    complete(requests[0], 403)
    clock += 100
    api.expireTimedOutRequests(clock)
    compare(results, [], "the shared attempt owns the deadline it inherited")
    api.fallbackTransport.expireTimedOutRequests(clock)
    verify(requests[1].aborted)
    compare(results, [0])
    complete(requests[1], 200)
    compare(results, [0])
    compare(api.timedJobs.length, 0)
  }

  function test_forwardedExpiryReportsSharedCooldown() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    api.request("GET", "/me/playlists", null, null, function() {},
      { priority: "interactive", shared: true })
    requests[0].retryAfter = "30"
    complete(requests[0], 429)
    var errors = []
    api.request("GET", "/artists/catalog/albums", null, null,
      function(status, payload, error) { errors.push(error) },
      { priority: "interactive" })
    complete(requests[1], 403)
    compare(requests.length, 2, "the shared retry waits out the shared cooldown")
    clock += Api.API_FOREGROUND_TIMEOUT_MS
    api.expireTimedOutRequests(clock)
    api.fallbackTransport.expireTimedOutRequests(clock)
    compare(errors.length, 1)
    verify(errors[0].indexOf("Spotify is busy") >= 0, errors[0])
    api.expireTimedOutRequests(clock)
    compare(errors.length, 1)
    compare(api.timedJobs.length, 0)
  }

  function test_removingFallbackCancelsPendingRequest() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    var calls = 0
    var handle = api.request("GET", "/artists/catalog/albums", null, null,
      function() { calls++ }, { priority: "interactive" })
    var crawl = api.request("GET", "/me/playlists", null, null,
      function() { calls++ }, { priority: "background", shared: true })
    complete(requests[0], 403)
    api.fallbackAuth = null
    wait(1)
    api.abortRequest(handle)
    api.abortRequest(crawl)
    verify(requests[1].aborted, "Changing apps left the old shared request running")
    verify(requests[2].aborted, "Changing apps left a shared crawl running")
    compare(calls, 0)
    compare(api.timedJobs.length, 0)
    compare(api.requestsInFlight, 0)
    api.expireTimedOutRequests(clock + Api.API_FOREGROUND_TIMEOUT_MS)
    compare(calls, 0)
  }

  function test_cancelAllDoesNotDispatchQueuedSharedMutation() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    for (var i = 0; i < 4; i++)
      api.request("GET", "/me/playlists", null, null, function() {}, { shared: true })
    api.request("PUT", "/me/player/play", null, {}, function() {}, { shared: true })
    compare(requests.length, 4)
    api.cancelAll()
    compare(requests.length, 4, "Cancelling shared reads dispatched a queued mutation")
    compare(api.timedJobs.length, 0)
    compare(api.fallbackTransport.timedJobs.length, 0)
    compare(api.fallbackTransport.requestsInFlight, 0)
  }

  function test_removingFallbackDoesNotDispatchQueuedSharedMutation() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    var calls = 0
    for (var i = 0; i < 4; i++)
      api.request("GET", "/me/playlists", null, null, function() { calls++ }, { shared: true })
    api.request("PUT", "/me/player/play", null, {}, function() { calls++ }, { shared: true })
    compare(requests.length, 4)
    api.fallbackAuth = null
    wait(1)
    compare(requests.length, 4, "Changing clients dispatched a queued mutation")
    for (i = 0; i < 4; i++) verify(requests[i].aborted)
    compare(api.timedJobs.length, 0)
    compare(calls, 0)
  }

  function test_changingFallbackCancelsForwardedRequest() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    var calls = 0
    api.request("GET", "/artists/catalog/albums", null, null,
      function() { calls++ }, { priority: "interactive" })
    complete(requests[0], 403)
    var shared = api.fallbackTransport
    api.fallbackAuth = otherSharedAuth
    verify(requests[1].aborted)
    compare(shared.timedJobs.length, 0)
    complete(requests[1], 200)
    compare(calls, 0)
    api.request("GET", "/me/playlists", null, null, function() { calls++ },
      { priority: "interactive", shared: true })
    compare(requests[2].authorization, "Bearer other-shared-token")
    complete(requests[2], 200)
    compare(calls, 1)
  }

  function test_newPersonalIdentityDoesNotInheritSharedCooldown() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.request("GET", "/me", null, null, function() {})
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    verify(api.rateLimitedUntil > clock)
    api.cancelAll() // Service also cancels when the old identity logs out.
    fakeAuth.resolvedClientId = "personal-app"
    api.request("GET", "/me/playlists", null, null, function() {})
    compare(requests.length, 2, "a new authorized app reaches the wire immediately")
    compare(api.rateLimitedUntil, 0)
    compare(api.interactiveLimitedUntil, 0)
    compare(api.rateLimitedSince, 0)
    compare(api.cooldownProbeUsed, false)
    compare(api.restrictInFlight, false)
  }

  function test_identitySwitchClearsBackgroundPacingButKeepsSharedQuota() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = fakeSharedAuth
    verify(api.fallbackTransport)
    var shared = api.fallbackTransport
    shared.rateLimitedUntil = clock + 120000
    shared.backgroundRefusals = 3
    api.backgroundSuspendedUntil = clock + 120000
    api.backgroundRefusals = 4
    api.lastBackgroundStartedAt = clock
    api.lastInteractiveStartedAt = clock
    fakeAuth.resolvedClientId = "personal-app"
    compare(api.backgroundSuspendedUntil, 0)
    compare(api.backgroundRefusals, 0)
    compare(api.lastBackgroundStartedAt, 0)
    compare(api.lastInteractiveStartedAt, 0)
    compare(api.fallbackTransport, shared)
    compare(shared.rateLimitedUntil, clock + 120000)
    compare(shared.backgroundRefusals, 3)
    api.request("GET", "/me/albums", null, null, function() {},
      { priority: "background" })
    compare(requests.length, 1, "the new app has no inherited background pause")
  }

  function test_identitySwitchCancelsActiveAndQueuedOldRequests() {
    var api = createTemporaryObject(apiComponent, testCase)
    var limit = fillEverySlot(api)
    var calls = 0
    api.request("PUT", "/me/player/play", null, null, function() { calls++ })
    fakeAuth.resolvedClientId = "personal-app"
    compare(requests.length, limit, "cancelling cannot dispatch the queued mutation")
    compare(api.requestQueue.length, 0)
    compare(api.timedJobs.length, 0)
    compare(api.requestsInFlight, 0)
    for (var i = 0; i < limit; i++) {
      verify(requests[i].aborted)
      complete(requests[i], 200)
    }
    compare(calls, 0)
    api.request("GET", "/me/playlists", null, null, function() {})
    compare(requests.length, limit + 1)
  }

  function test_tokenRefreshAndUnchangedIdentityKeepQuota() {
    var api = createTemporaryObject(apiComponent, testCase)
    api.request("GET", "/me", null, null, function() {})
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    var until = api.rateLimitedUntil
    accessToken = "refreshed-token"
    fakeAuth.resolvedClientId = "old-app"
    api.request("GET", "/me/playlists", null, null, function() {})
    compare(api.rateLimitedUntil, until)
    compare(requests.length, 1, "refreshing a token cannot bypass the app's quota")
  }

  function sharedToPersonal(fallbackFirst) {
    var api = createTemporaryObject(apiComponent, testCase)
    api.request("GET", "/me", null, null, function() {})
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    var until = api.rateLimitedUntil
    verify(until > clock)
    if (fallbackFirst) api.fallbackAuth = shippedAuth
    fakeAuth.resolvedClientId = "personal-app"
    if (!fallbackFirst) api.fallbackAuth = shippedAuth
    var shared = api.fallbackTransport
    verify(shared)
    compare(api.rateLimitedUntil, 0)
    compare(shared.rateLimitedUntil, until, "the shipped app's Retry-After was forgotten")
    api.request("GET", "/me/playlists", null, null, function() {})
    compare(requests.length, 2, "the personal app is not held by the shipped app's pause")
    compare(requests[1].authorization, "Bearer mock-token")
    complete(requests[1], 200)
    var errors = []
    api.request("GET", "/artists/catalog/albums", null, null,
      function(status, payload, error) { errors.push(error) })
    complete(requests[2], 403)
    compare(requests.length, 3, "the first fallback ignored the shipped app's cooldown")
    var crawled = 0
    api.request("GET", "/me/playlists", null, null, function() { crawled++ },
      { priority: "background", shared: true })
    compare(requests.length, 3)
    clock = Math.max(until, shared.backgroundSuspendedUntil)
    shared.pumpRequests()
    verify(requests.length > 3, "the shared work never resumed after the cooldown")
    for (var i = 3; i < requests.length; i++)
      compare(requests[i].authorization, "Bearer shipped-token")
  }

  function test_sharedToPersonalKeepsTheShippedCooldown() { sharedToPersonal(false) }
  function test_sharedToPersonalKeepsTheShippedCooldownWhenFallbackArrivesFirst() {
    sharedToPersonal(true)
  }

  function personalToShared(fallbackFirst) {
    fakeAuth.resolvedClientId = "personal-app"
    var api = createTemporaryObject(apiComponent, testCase)
    api.fallbackAuth = shippedAuth
    api.request("GET", "/me/playlists", null, null, function() {},
      { priority: "background", shared: true })
    compare(requests[0].authorization, "Bearer shipped-token")
    requests[0].retryAfter = "120"
    complete(requests[0], 429)
    var until = api.fallbackTransport.rateLimitedUntil
    var suspended = api.fallbackTransport.backgroundSuspendedUntil
    verify(until > clock)
    compare(api.rateLimitedUntil, 0)
    if (fallbackFirst) api.fallbackAuth = null
    fakeAuth.resolvedClientId = "old-app"
    if (!fallbackFirst) api.fallbackAuth = null
    wait(1)
    compare(api.fallbackTransport, null)
    compare(api.rateLimitedUntil, until, "the shipped app's live cooldown was dropped")
    compare(api.backgroundSuspendedUntil, suspended)
    compare(api.backgroundRefusals, 1)
    api.request("GET", "/me/albums", null, null, function() {},
      { priority: "background" })
    compare(requests.length, 1, "the shipped app burst into its own Retry-After window")
    clock = suspended
    api.pumpRequests()
    compare(requests.length, 2)
    compare(requests[1].authorization, "Bearer mock-token")
  }

  function test_personalToSharedImportsTheChildCooldown() { personalToShared(false) }
  function test_personalToSharedImportsTheChildCooldownWhenFallbackLeavesFirst() {
    personalToShared(true)
  }
}
