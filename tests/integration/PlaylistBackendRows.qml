import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Api.js" as Api

// Opens a playlist through the real Service while the runner stands in for
// the backend socket. The rows must come from the socket, shaped like the Web
// API's, with no Web API request made for them; a read the player refuses
// must fall through to the Web API with the page's own options.
ShellRoot {
  id: test
  Plugin.Service { id: service }
  property var requests: []
  property int phase: 0
  function expect(ok, message) { if (!ok) throw new Error(message) }
  function fail(message) { console.log("PLAYLIST_BACKEND_ROWS_FAIL " + message); Qt.quit() }
  function xhrFactory() {
    var xhr = { readyState: 0, status: 0, responseText: "", url: "", method: "",
      headers: {}, aborted: false,
      open: function(method, url) { this.method = method; this.url = url },
      send: function() {}, abort: function() { this.aborted = true },
      setRequestHeader: function(k, v) { this.headers[k] = v },
      getResponseHeader: function() { return null } }
    requests.push(xhr)
    return xhr
  }

  Timer {
    property int ticks: 0
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (ticks === 0) {
        service.api.cancelAll()
        service.api.auth = { loggedIn: true, resolvedClientId: "app-a",
          withAccessToken: function(cb) { cb("token", "") },
          invalidateAccessToken: function() {} }
        service.api.xhrFactory = test.xhrFactory
        service.backend.wanted = true
      }
      if (!service.backend.ready) {
        if (++ticks > 100) fail("the backend socket never connected")
        return
      }
      stop()
      test.phase = 1
      service.openPlaylist({ id: "abc", uri: "spotify:playlist:abc", type: "playlist",
        name: "Foreign", ownerId: "someone-else", snapshotId: "" }, 0, null)
      settle.start()
    }
  }

  Timer {
    id: settle
    interval: 400
    onTriggered: {
      if (test.phase === 1) {
        expect(service.playlistItems.length === 2, "two rows expected, got " + service.playlistItems.length)
        expect(service.playlistItems[0].name === "Song One", "first row is the backend's song")
        expect(service.playlistItems[1].uri === "", "a null row keeps its place")
        expect(service.playlistItemsNext === Api.safeApiUrl("/playlists/abc/items?offset=2&limit=50"),
          "the cursor is the Web API address for the rest: " + service.playlistItemsNext)
        expect(service.selectedPlaylist.snapshotId === "AAAAAnRld", "the backend's version labels the rows")
        expect(requests.filter(function(x) { return x.url.indexOf("/playlists/abc") >= 0 }).length === 0,
          "no Web API request was made for rows the player had")
        test.phase = 2
        service.openPlaylist({ id: "refused", uri: "spotify:playlist:refused", type: "playlist",
          name: "Refused", ownerId: "someone-else", snapshotId: "" }, 0, null)
        settle.restart()
        return
      }
      var fallback = requests.filter(function(x) { return x.url.indexOf("/playlists/refused/items") >= 0 })
      expect(fallback.length === 1, "a refused read fell through to the Web API once, saw " + fallback.length)
      console.log("PLAYLIST_BACKEND_ROWS_PASS")
      Qt.quit()
    }
  }
}
