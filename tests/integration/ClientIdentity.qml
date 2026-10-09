import QtQuick
import Quickshell
import "plugin" as Plugin

// Real settings, authentication and transports; only the clock and HTTP wire
// are fake. This fixture never authorizes an account or contacts Spotify.
ShellRoot {
  id: test
  property var requests: []
  Plugin.Service { id: service }
  function check(condition, message) {
    if (!condition) throw new Error(message)
  }
  function newRequest() {
    var xhr = {
      readyState: 0, status: 0, responseText: "", aborted: false,
      onreadystatechange: null, open: function() {}, send: function() {},
      setRequestHeader: function() {},
      abort: function() { this.aborted = true },
      getResponseHeader: function() { return "120" }
    }
    requests.push(xhr)
    return xhr
  }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      service.applySettings({ clientId: "11111111111111111111111111111111" })
      service.auth.switchingIdentity = false
      service.auth.accessToken = "fixture-token"
      service.auth.accessTokenExpiresAt = Date.now() + 3600000
      service.auth.loggedIn = true
      service.api.now = function() { return 1000 }
      service.api.xhrFactory = test.newRequest
      service.api.request("GET", "/me", null, null, function() {})
      check(requests.length === 1, "The first app did not reach the wire")
      requests[0].status = 429
      requests[0].readyState = XMLHttpRequest.DONE
      requests[0].responseText = "{}"
      requests[0].onreadystatechange()
      check(service.api.rateLimitedUntil > 1000, "The first app has no cooldown")
      var oldUntil = service.api.rateLimitedUntil
      service.auth.accessToken = "fixture-refreshed-token"
      service.applySettings({ clientId: "11111111111111111111111111111111" })
      check(service.api.rateLimitedUntil === oldUntil,
        "An unchanged Settings save or token refresh bypassed the quota")
      var shared = service.api.fallbackTransport
      check(!!shared, "The personal app has no shared fallback transport")
      shared.rateLimitedUntil = 121000
      service.api.backgroundRefusals = 4
      service.api.backgroundSuspendedUntil = 121000
      var queued = service.api.request("GET", "/me/albums", null, null, function() {})
      check(requests.length === 1, "The old app dispatched a queued read")
      service.applySettings({ clientId: "22222222222222222222222222222222" })
      check(queued.aborted && service.api.timedJobs.length === 0,
        "Changing Settings retained old queued work")
      check(service.api.rateLimitedUntil === 0
        && service.api.backgroundRefusals === 0
        && service.api.backgroundSuspendedUntil === 0,
        "The new Settings app inherited the old app's cooldown")
      check(service.api.fallbackTransport === shared && shared.rateLimitedUntil === 121000,
        "Changing the primary Settings app erased the shared app's quota")
      check(service.auth.accessToken === "" && !service.auth.loggedIn,
        "Changing Settings reused the old app's token")
      service.auth.switchingIdentity = false
      service.auth.accessToken = "fixture-new-app-token"
      service.auth.accessTokenExpiresAt = Date.now() + 3600000
      service.auth.loggedIn = true
      service.api.request("GET", "/me/playlists", null, null, function() {})
      check(requests.length === 2, "The newly authorized Settings app stayed blocked")
      service.applySettings({ clientId: "" })
      check(requests[1].aborted, "Returning to the shared app retained the personal app's work")
      check(service.api.fallbackTransport === null && service.api.rateLimitedUntil === 121000,
        "Returning to the shared app forgot that app's live cooldown")
      service.api.cancelAll()
      console.log("CLIENT_IDENTITY_PASS")
      Qt.quit()
    }
  }
}
