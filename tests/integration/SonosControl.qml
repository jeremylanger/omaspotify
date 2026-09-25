import QtQuick
import Quickshell
import "plugin" as Plugin

// Drives a Sonos through the real Service. The runner swaps in a helper that
// answers each command after a short pause, like a speaker on the network.
ShellRoot {
  id: shell

  readonly property string sonosId: "4c1e461f8fe6be10d41c504f6e5121a5275d1d6d"
  property var ran: []
  property var failures: []

  Plugin.Service { id: spotifyService }

  Connections {
    target: spotifyService.connectManager
    function onControlled(deviceId, action, value) {
      shell.ran = shell.ran.concat([action + " " + value])
    }
  }

  function expect(ok, message) {
    if (!ok) failures = failures.concat([message])
  }

  function playOnSonos(volumePercent) {
    spotifyService.applyPlaybackState({
      device: { id: sonosId, name: "Kitchen", type: "Speaker", is_active: true,
        is_restricted: true, volume_percent: volumePercent, supports_volume: true },
      is_playing: true, shuffle_state: false, repeat_state: "off"
    })
  }

  function sliderPercent() {
    return Math.round(spotifyService.volume * 100)
  }

  function finish() {
    if (failures.length) console.log("SONOS_CONTROL_FAIL " + failures.join(" | "))
    else console.log("SONOS_CONTROL_PASS")
    Qt.quit()
  }

  Timer {
    interval: 20
    running: true
    onTriggered: {
      // Discovery read 30 from the speaker a while ago.
      spotifyService.connectManager.devices = [{ id: shell.sonosId,
        name: "Kitchen", type: "Speaker", brand: "Sonos", volumePercent: 30 }]
      shell.playOnSonos(null)
      shell.expect(shell.sliderPercent() === 30,
        "With no volume from Spotify the slider showed " + shell.sliderPercent()
        + ", not the speaker's own 30")
      shell.playOnSonos(55)
      spotifyService.mergeConnectDevices()
      shell.expect(shell.sliderPercent() === 55,
        "The slider showed " + shell.sliderPercent()
        + " from the last discovery sweep, not the speaker's current 55")
      shell.playOnSonos(null)
      shell.expect(shell.sliderPercent() === 55,
        "A missing reading put the slider back to " + shell.sliderPercent())
      // A new sweep reads the speaker again, which is newer than Spotify's 55.
      spotifyService.connectManager.devices = [{ id: shell.sonosId,
        name: "Kitchen", type: "Speaker", brand: "Sonos", volumePercent: 20 }]
      spotifyService.connectManager.refreshed()
      shell.expect(shell.sliderPercent() === 20,
        "A fresh discovery sweep left the slider at " + shell.sliderPercent())

      spotifyService.applySonosControlResult("mode", "SHUFFLE_REPEAT_ONE")
      shell.expect(spotifyService.shuffle && spotifyService.repeatMode === "track",
        "Shuffle with repeat one showed as shuffle " + spotifyService.shuffle
        + ", repeat " + spotifyService.repeatMode)

      shell.expect(spotifyService.sendSonosControl("seek", "30"),
        "A seek was refused")
      shell.expect(spotifyService.sendSonosControl("mode", "SHUFFLE"),
        "A press while the speaker was busy was refused")
      shell.expect(spotifyService.sendSonosControl("mode", "SHUFFLE_NOREPEAT"),
        "A second press while the speaker was busy was refused")
      shell.expect(!spotifyService.sendSonosControl("dance", ""),
        "An unknown command was reported as sent")
      drain.start()
    }
  }

  Timer {
    id: drain

    property int ticks: 0

    interval: 50
    repeat: true
    onTriggered: {
      if (shell.ran.length < 2 && ++ticks < 60) return
      stop()
      shell.expect(shell.ran.join(", ") === "seek 30, mode SHUFFLE_NOREPEAT",
        "The speaker ran [" + shell.ran.join(", ")
        + "] instead of the seek and then the last shuffle press")
      shell.finish()
    }
  }
}
