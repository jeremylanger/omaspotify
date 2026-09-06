import QtQuick
import Quickshell.Services.Mpris

import "Api.js" as Api

// Pauses playback after a delay, after the current item, or at the end of the
// current album or playlist. Owns its own countdown so the service does not
// have to.
Item {
  id: sleep

  visible: false
  width: 0
  height: 0

  property var service: null

  property string mode: "off"
  property double endsAt: 0
  property string trackUri: ""
  property int remainingSeconds: 0
  readonly property bool active: mode !== "off"

  function setMinutes(minutes) {
    var value = Math.max(1, Math.min(720, Math.floor(Number(minutes) || 0)))
    contextTimer.stop()
    mode = "minutes"
    endsAt = Date.now() + value * 60000
    remainingSeconds = value * 60
    trackUri = ""
    scheduleDeadline()
    if (service) service.succeed("Sleep timer set for " + value + " minutes")
  }

  function afterTrack() {
    if (!service) return
    if (!service.currentUri || !service.playing) {
      service.fail("Play something before setting an end-of-track timer")
      return
    }
    deadlineTimer.stop()
    mode = "track"
    trackUri = service.currentUri
    endsAt = 0
    remainingSeconds = 0
    service.succeed("Playback will pause after this item")
  }

  function afterContext() {
    if (!service) return
    if (!service.playing) {
      service.fail("Play something before setting an end-of-context timer")
      return
    }
    deadlineTimer.stop()
    mode = "context"
    trackUri = ""
    endsAt = 0
    remainingSeconds = 0
    service.succeed("Playback will pause after this album or playlist")
  }

  function cancel(showStatus) {
    deadlineTimer.stop()
    mode = "off"
    endsAt = 0
    trackUri = ""
    remainingSeconds = 0
    contextTimer.stop()
    if (showStatus !== false && service) service.succeed("Sleep timer cancelled")
  }

  function finish() {
    if (!active) return
    if (service && service.playing) service.togglePlayback()
    cancel(false)
    if (service) service.succeed("Sleep timer finished")
  }

  function updateCountdown() {
    if (mode !== "minutes") {
      remainingSeconds = 0
      return
    }
    remainingSeconds = Api.deadlineRemainingSeconds(endsAt, Date.now())
  }

  function scheduleDeadline() {
    deadlineTimer.stop()
    if (mode !== "minutes") return
    var remaining = endsAt - Date.now()
    if (remaining <= 0) {
      updateCountdown()
      finish()
      return
    }
    deadlineTimer.interval = Math.max(1, Math.ceil(remaining))
    deadlineTimer.restart()
  }

  function statusText() {
    if (mode === "minutes") {
      var minutes = Math.floor(remainingSeconds / 60)
      var seconds = remainingSeconds % 60
      return "Sleep in " + minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    if (mode === "track") return "Sleep after this item"
    if (mode === "context") return "Sleep after this album or playlist"
    return "Sleep timer"
  }

  // The service forwards its playback signals here.
  function notePlaybackStateChanged(playbackState) {
    if ((mode === "context" || mode === "track")
        && playbackState === MprisPlaybackState.Stopped) contextTimer.restart()
    else contextTimer.stop()
  }

  function noteCurrentUriChanged(currentUri) {
    if (mode === "track" && trackUri && currentUri && currentUri !== trackUri)
      finish()
  }

  Timer {
    id: deadlineTimer
    repeat: false
    onTriggered: {
      sleep.updateCountdown()
      if (sleep.remainingSeconds <= 0) sleep.finish()
      else sleep.scheduleDeadline()
    }
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    running: sleep.mode === "minutes" && sleep.service && sleep.service.uiVisible
    onRunningChanged: if (running) sleep.updateCountdown()
    onTriggered: {
      sleep.updateCountdown()
      if (sleep.remainingSeconds <= 0) sleep.finish()
    }
  }

  Timer {
    id: contextTimer
    interval: 1800
    repeat: false
    onTriggered: if (sleep.mode === "context" || sleep.mode === "track")
      sleep.finish()
  }
}
