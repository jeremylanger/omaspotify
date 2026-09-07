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
        return String(name).toLowerCase() === "retry-after" ? "1" : ""
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

  function test_searchKeepsTheExistingAllTypesRequest() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    api.search("miles davis", function(groups, error) {
      callbacks++
      compare(error, "")
    })
    compare(requests.length, 1)
    verify(decodeURIComponent(requests[0].url).indexOf(
      "type=track,artist,album,playlist,show,episode,audiobook") >= 0)
    complete(requests[0], 200, "{\"tracks\":{\"items\":[]}}")
    compare(callbacks, 1)
  }

  function test_searchTimeoutAbortsAndReleasesSlotOnce() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    var error = ""
    api.search("stalled", function(groups, reason) {
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
    api.search("queued", function(groups, reason) { error = reason })
    compare(requests.length, limit)
    compare(api.requestQueue.length, 1)
    clock = 9000
    api.expireTimedOutRequests(clock)
    verify(error.indexOf("too long") >= 0)
    compare(api.requestQueue.length, 0)
    compare(api.requestsInFlight, limit)
  }

  function test_search429ReturnsWithoutSilentRetry() {
    var api = createTemporaryObject(apiComponent, testCase)
    verify(api)
    var callbacks = 0
    var error = ""
    api.search("busy", function(groups, reason) {
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
    api.search("old", function() { staleCalls++ })
    var oldRequest = requests[0]
    api.search("new", function() { currentCalls++ })
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
    compare(api.timedJobs.length, 0)
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
}
