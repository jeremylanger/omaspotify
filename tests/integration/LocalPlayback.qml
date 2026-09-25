import QtQuick
import Quickshell
import "plugin" as Plugin

// Starts a song inside a playlist through the real Service. The runner stands
// in for the backend socket and checks which song the load command named.
ShellRoot {
  Plugin.Service { id: spotifyService }

  Timer {
    property int ticks: 0

    interval: 50
    repeat: true
    running: true
    onTriggered: {
      spotifyService.backend.wanted = true
      if (!spotifyService.backend.ready) {
        if (++ticks > 100) {
          console.log("LOCAL_PLAYBACK_FAIL the backend socket never connected")
          Qt.quit()
        }
        return
      }
      stop()
      spotifyService.pendingPlayback = { type: "track", uri: "spotify:track:clicked" }
      spotifyService.pendingPlaybackBody = { context_uri: "spotify:playlist:abc",
        offset: { position: 3 } }
      spotifyService.pendingPlaybackSerial = 7
      spotifyService.sendLocalSocketPlayback(7)
      sent.start()
    }
  }

  Timer {
    id: sent
    interval: 300
    onTriggered: {
      console.log("LOCAL_PLAYBACK_SENT")
      Qt.quit()
    }
  }
}
