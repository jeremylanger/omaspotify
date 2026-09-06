import QtQuick
import QtTest

import ".."

TestCase {
  id: testCase
  name: "SleepTimer"

  property var succeeded: []
  property var failed: []
  property int toggles: 0

  QtObject {
    id: stubService

    property string currentUri: "spotify:track:one"
    property bool playing: true
    property bool uiVisible: false

    function succeed(message) {
      testCase.succeeded = testCase.succeeded.concat([String(message)])
    }
    function fail(message) {
      testCase.failed = testCase.failed.concat([String(message)])
    }
    function togglePlayback() {
      testCase.toggles += 1
    }
  }

  SleepTimer {
    id: sleep
    service: stubService
  }

  function init() {
    sleep.cancel(false)
    stubService.currentUri = "spotify:track:one"
    stubService.playing = true
    succeeded = []
    failed = []
    toggles = 0
  }

  function test_startsOff() {
    compare(sleep.mode, "off")
    verify(!sleep.active)
    compare(sleep.statusText(), "Sleep timer")
  }

  function test_setMinutes_setsCountdownAndReports() {
    sleep.setMinutes(20)
    compare(sleep.mode, "minutes")
    verify(sleep.active)
    compare(sleep.remainingSeconds, 1200)
    compare(succeeded, ["Sleep timer set for 20 minutes"])
  }

  function test_setMinutes_clampsToARealRange() {
    sleep.setMinutes(0)
    compare(sleep.remainingSeconds, 60)
    sleep.cancel(false)
    sleep.setMinutes(99999)
    compare(sleep.remainingSeconds, 720 * 60)
    sleep.cancel(false)
    sleep.setMinutes("not a number")
    compare(sleep.remainingSeconds, 60)
  }

  function test_afterTrack_needsSomethingPlaying() {
    stubService.playing = false
    sleep.afterTrack()
    compare(sleep.mode, "off")
    compare(failed, ["Play something before setting an end-of-track timer"])
  }

  function test_afterTrack_remembersTheCurrentTrack() {
    sleep.afterTrack()
    compare(sleep.mode, "track")
    compare(sleep.trackUri, "spotify:track:one")
    compare(sleep.remainingSeconds, 0)
    compare(succeeded, ["Playback will pause after this item"])
  }

  function test_afterContext_needsSomethingPlaying() {
    stubService.playing = false
    sleep.afterContext()
    compare(sleep.mode, "off")
    compare(failed, ["Play something before setting an end-of-context timer"])
  }

  function test_afterContext_setsContextMode() {
    sleep.afterContext()
    compare(sleep.mode, "context")
    compare(sleep.trackUri, "")
  }

  function test_cancel_clearsEverythingAndCanStaySilent() {
    sleep.setMinutes(5)
    succeeded = []
    sleep.cancel(false)
    compare(sleep.mode, "off")
    compare(sleep.remainingSeconds, 0)
    compare(succeeded, [])

    sleep.setMinutes(5)
    succeeded = []
    sleep.cancel(true)
    compare(succeeded, ["Sleep timer cancelled"])
  }

  function test_finish_pausesPlaybackOnceAndResets() {
    sleep.afterTrack()
    succeeded = []
    sleep.finish()
    compare(toggles, 1)
    compare(sleep.mode, "off")
    compare(succeeded, ["Sleep timer finished"])

    // Already off, so a second finish must not pause anything again.
    sleep.finish()
    compare(toggles, 1)
  }

  function test_finish_doesNotPauseWhenAlreadyPaused() {
    sleep.afterTrack()
    stubService.playing = false
    sleep.finish()
    compare(toggles, 0)
    compare(sleep.mode, "off")
  }

  function test_trackModeEndsWhenTheTrackChanges() {
    sleep.afterTrack()
    sleep.noteCurrentUriChanged("spotify:track:one")
    compare(sleep.mode, "track", "the same track must not end the timer")

    sleep.noteCurrentUriChanged("spotify:track:two")
    compare(sleep.mode, "off")
    compare(toggles, 1)
  }

  function test_trackModeIgnoresAnEmptyUri() {
    sleep.afterTrack()
    sleep.noteCurrentUriChanged("")
    compare(sleep.mode, "track")
  }

  function test_minutesModeIgnoresTrackChanges() {
    sleep.setMinutes(10)
    sleep.noteCurrentUriChanged("spotify:track:two")
    compare(sleep.mode, "minutes")
  }

  function test_statusTextDescribesEachMode() {
    sleep.setMinutes(3)
    compare(sleep.statusText(), "Sleep in 3:00")
    sleep.cancel(false)
    sleep.afterTrack()
    compare(sleep.statusText(), "Sleep after this item")
    sleep.cancel(false)
    sleep.afterContext()
    compare(sleep.statusText(), "Sleep after this album or playlist")
  }

  function test_statusTextPadsTheSeconds() {
    sleep.setMinutes(1)
    sleep.remainingSeconds = 65
    compare(sleep.statusText(), "Sleep in 1:05")
  }

  // Playback stopping is what ends a context or track timer. The service
  // decides what "stopped" means so this component stays free of Mpris.
  function test_stoppingEndsAContextTimer() {
    sleep.afterContext()
    sleep.noteStopped(true)
    tryCompare(sleep, "mode", "off", 4000)
    compare(toggles, 1)
  }

  function test_resumingBeforeTheGraceWindowKeepsTheTimer() {
    sleep.afterContext()
    sleep.noteStopped(true)
    sleep.noteStopped(false)
    wait(2200)
    compare(sleep.mode, "context")
    compare(toggles, 0)
  }

  function test_stoppingDoesNothingWhenNoTimerIsSet() {
    sleep.noteStopped(true)
    wait(2200)
    compare(sleep.mode, "off")
    compare(toggles, 0)
  }
}
