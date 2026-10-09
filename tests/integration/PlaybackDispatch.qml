import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin

// Real Service/transport dispatch with a held status response. Neither the
// user's keyring nor a real receiver is used by this fixture.
ShellRoot {
  id: test
  Plugin.Service { id: service }
  property var requests: []
  property int stage: 0
  property double probeStarted: 0
  property double waitStarted: 0
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  property bool backendServing: false
  property var backendPeer: null
  property var backendLoads: []

  // Stands in for the backend socket, only in the fixture's private runtime.
  SocketServer {
    active: test.backendServing
    path: test.runtimeDir + "/omaspotify/backend.sock"
    handler: Socket {
      id: peer
      onConnectionStateChanged: {
        if (!connected) return
        test.backendPeer = peer
        // The process is up, but its Spotify session is registering again.
        test.backendSend({ type: "event",
          state: { lifecycle: "starting", session_connected: false } })
      }
      parser: SplitParser {
        splitMarker: "\n"
        onRead: function(line) { test.backendRead(line) }
      }
    }
  }
  function backendSend(message) {
    backendPeer.write(JSON.stringify(message) + "\n")
    backendPeer.flush()
  }
  function backendRead(line) {
    var message = JSON.parse(line)
    if (message.command === "load") backendLoads = backendLoads.concat([message])
    backendSend({ type: "response", id: message.id, ok: true, result: {} })
  }

  function expect(value, message) { if (!value) throw new Error(message) }
  function song(uri) { return { type: "track", uri: "spotify:track:" + uri } }
  function writes() {
    return requests.filter(function(xhr) { return xhr.method === "PUT" })
  }
  function live(path) {
    return requests.filter(function(xhr) {
      return !xhr.aborted && xhr.method === "GET" && xhr.url.indexOf(path) >= 0
    })
  }
  function complete(xhr, status, payload) {
    xhr.status = status
    xhr.responseText = JSON.stringify(payload)
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }
  function speaker(id) {
    return { device: { id: id, name: "Speaker", type: "Speaker", is_active: true,
      is_restricted: false }, is_playing: false }
  }
  function reset() {
    service.api.cancelAll()
    service.api.rateLimitedUntil = 0
    service.clearPendingPlayback()
    service.remotePlaybackWaiters = []
    service.remotePlaybackLoading = false
    service.remotePlayback = null
    service.devicesLoading = false
    service.deviceLoadWaiters = []
    service.apiDevices = []
    service.devices = []
    service.localDeviceId = ""
    service.selectedDeviceId = ""
    service.selectedDeviceExplicit = false
    service.lastError = ""
    requests = []
  }
  function runningLocalReceiver(active) {
    service.daemon.credentialsAvailable = true
    service.daemon.binaryAvailable = true
    service.daemon.unitAvailable = true
    service.daemon.serviceActive = true
    service.localDeviceId = "local"
    service.devices = [{ id: "local", local: true, active: active, restricted: false }]
  }
  Timer {
    interval: 50
    running: true
    onTriggered: {
      service.api.cancelAll()
      service.api.auth = { loggedIn: true,
        withAccessToken: function(callback) { callback("test-token", "") },
        invalidateAccessToken: function() {} }
      service.api.fallbackAuth = null
      service.api.xhrFactory = function() {
        var xhr = { readyState: 0, status: 0, responseText: "", method: "", url: "",
          body: "", aborted: false, onreadystatechange: null,
          open: function(method, url) { this.method = method; this.url = url },
          send: function(body) { this.body = body || "" },
          setRequestHeader: function() {}, getResponseHeader: function() { return "" },
          abort: function() { this.aborted = true } }
        test.requests.push(xhr)
        return xhr
      }
      reset()
      // A displayed active receiver is already enough to dispatch the click.
      service.remotePlayback = { device: { id: "speaker", active: true, local: false } }
      service.devices = [service.remotePlayback.device]
      service.loadPlaybackState()
      expect(requests.length === 1, "Status request did not start")
      service.playItem(song("first"), null, "", "")
      phase.start()
    }
  }
  Timer {
    id: phase
    interval: 100
    onTriggered: {
      if (stage === 0) {
        expect(writes().length === 1,
          "Known receiver waited behind the unrelated status refresh")
        expect(writes()[0].url.indexOf("device_id=speaker") >= 0,
          "Playback moved off the displayed remote receiver")
        expect(JSON.parse(writes()[0].body).uris[0] === "spotify:track:first",
          "The wrong song was dispatched")
        reset()
        // With no known active receiver, the first refresh still wins the race
        // against automatically starting playback on this computer.
        service.loadPlaybackState()
        service.playItem(song("unknown"), null, "", "")
        expect(writes().length === 0, "Unknown receiver was chosen before the refresh")
        expect(live("/me/player").length === 1, "Click left more than one receiver read")
        complete(live("/me/player")[0], 200, speaker("fresh-speaker"))
        expect(writes().length === 1
          && writes()[0].url.indexOf("device_id=fresh-speaker") >= 0,
          "Fresh receiver was not used by the waiting click")
        reset()
        // A library crawl's 30-second pause holds the status poll in the queue.
        // The click's own read goes out now and finds the speaker in use.
        service.api.rateLimitedUntil = Date.now() + 30000
        service.loadPlaybackState()
        expect(requests.length === 0, "Status poll ignored the background pause")
        service.playItem(song("cooled"), null, "", "")
        expect(live("/me/player").length === 1,
          "Click waited behind a status poll held by the background pause")
        complete(live("/me/player")[0], 200, speaker("cooled-speaker"))
        expect(writes().length === 1
          && writes()[0].url.indexOf("device_id=cooled-speaker") >= 0
          && JSON.parse(writes()[0].body).uris[0] === "spotify:track:cooled",
          "Paused status poll moved the click off the speaker in use")
        reset()
        // A failed probe must not hand the song to a ready local receiver.
        runningLocalReceiver(false)
        service.loadPlaybackState()
        service.playItem(song("unconfirmed"), null, "", "")
        complete(live("/me/player")[0], 503,
          { error: { status: 503, message: "Service unavailable" } })
        expect(writes().length === 0, "Failed receiver probe moved playback to this computer")
        expect(!service.pendingPlaybackBody && service.lastError.length > 0,
          "Failed receiver probe gave no actionable error")
        reset()
        // A known running local receiver can use Connect immediately while
        // its optional socket is unavailable; no fixed five-second wait.
        runningLocalReceiver(true)
        service.selectedDeviceId = "local"
        service.selectedDeviceExplicit = true
        service.playItem(song("local"), null, "", "")
        stage = 1
        restart()
      } else if (stage === 1) {
        expect(writes().length === 1 && writes()[0].url.indexOf("device_id=local") >= 0,
          "Known local receiver waited for an unavailable socket")
        reset()
        service.daemon.serviceActive = false
        service.daemon.credentialsAvailable = false
        probeStarted = Date.now()
        service.loadPlaybackState()
        service.playItem(song("timeout"), null, "", "")
        stage = 2
        interval = 2400
        restart()
      } else if (stage === 2) {
        expect(!service.remotePlaybackLoading && !service.pendingPlaybackBody,
          "A stalled receiver refresh kept the click pending")
        expect(requests.every(function(xhr) { return xhr.aborted }),
          "Stalled receiver refresh was not cancelled")
        expect(Date.now() - probeStarted < 3500, "Receiver probe exceeded its short deadline")
        expect(writes().length === 0, "Failed probe sent playback to an unknown receiver")
        expect(service.lastError.length > 0, "Unavailable playback gave no actionable error")
        reset()
        // The receiver from an earlier run is still listed while a start is
        // in progress. The unit becomes active before Spotify registers it.
        runningLocalReceiver(false)
        service.daemon.serviceActive = false
        service.daemon.busy = true
        service.playItem(song("cold-first"), null, "", "")
        service.daemon.serviceActive = true
        service.playItem(song("cold-second"), null, "", "")
        expect(writes().length === 0, "Click used Connect before the receiver registered")
        expect(service.pendingPlaybackBody
          && service.pendingPlaybackBody.uris[0] === "spotify:track:cold-second",
          "The newest click did not replace the pending song")
        service.daemon.busy = false
        service.daemon.started()
        stage = 3
        interval = 1000
        restart()
      } else if (stage === 3) {
        var listed = live("/me/player/devices")
        expect(writes().length === 0 && listed.length === 1,
          "Started receiver was not looked up before playback")
        complete(listed[0], 200, { devices: [{ id: "local", name: service.deviceName,
          type: "Computer", is_active: false, is_restricted: false }] })
        expect(writes().length === 1 && writes()[0].url.indexOf("device_id=local") >= 0
          && JSON.parse(writes()[0].body).uris[0] === "spotify:track:cold-second",
          "The newest song did not play once the receiver registered")
        // That song's socket wait is over, so the next click goes out at once.
        service.playItem(song("after-register"), null, "", "")
        expect(writes().length === 2 && writes()[1].url.indexOf("device_id=local") >= 0
          && JSON.parse(writes()[1].body).uris[0] === "spotify:track:after-register",
          "Fresh registered receiver kept waiting on an obsolete socket timer")
        reset()
        expect(/\/dispatch-runtime$/.test(runtimeDir),
          "Refusing to serve a backend socket outside the fixture runtime")
        runningLocalReceiver(false)
        backendServing = true
        waitStarted = Date.now()
        stage = 4
        interval = 100
        restart()
      } else if (stage === 4) {
        if (!(service.backend.connected && service.backend.lifecycle === "starting")) {
          expect(Date.now() - waitStarted < 5000, "Fixture backend socket never connected")
          restart()
          return
        }
        // A registered receiver lost its session; Connect would reach the
        // interrupted one, so both clicks wait and the newest is kept.
        service.playItem(song("reconnect-first"), null, "", "")
        service.playItem(song("reconnect-second"), null, "", "")
        expect(writes().length === 0 && backendLoads.length === 0,
          "Click used Connect while the receiver was registering its session")
        expect(service.pendingPlaybackBody
          && service.pendingPlaybackBody.uris[0] === "spotify:track:reconnect-second",
          "The newest click did not stay pending during the reconnect")
        backendSend({ type: "event", state: { lifecycle: "ready", session_connected: true } })
        stage = 5
        interval = 600
        restart()
      } else {
        expect(writes().length === 0, "Reconnected receiver was reached through Connect")
        expect(backendLoads.length === 1
          && JSON.stringify(backendLoads[0]).indexOf("spotify:track:reconnect-second") >= 0,
          "The newest song did not play once the session was ready")
        backendServing = false
        service.daemon.serviceActive = false
        console.log("PLAYBACK_DISPATCH_PASS")
        Qt.quit()
      }
    }
  }
}
