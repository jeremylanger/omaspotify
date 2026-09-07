import QtQuick
import Quickshell
import Quickshell.Io

import "Api.js" as Api

// Installs, enables and opens the Omasing lyrics plugin, and remembers the
// request across the shell reload that installing a plugin causes.
Item {
  id: lyrics

  visible: false
  width: 0
  height: 0

  property var service: null
  property var pluginRegistry: null

  readonly property string pluginId: "stappmus.lyrics"
  readonly property string pluginUrl: "https://github.com/stappmus/Omasing.git"

  readonly property string availability: {
    var plugins = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins : ({})
    var installed = !!plugins[pluginId]
    var enabled = installed && pluginRegistry
      && typeof pluginRegistry.inBar === "function"
      && pluginRegistry.inBar(pluginId)
    return Api.optionalPluginState(installed, enabled)
  }

  property bool busy: false
  property string operation: ""
  property string error: ""
  property string requestSurface: ""
  property var pendingSong: null
  property int launchAttempts: 0
  property double installStartedAt: 0

  signal promptRequested(string surface, string availability)
  signal opened(string surface)

  onAvailabilityChanged: resumeIntent()

  function currentSong() {
    return service ? service.currentLyricsSong : null
  }

  function request(surface) {
    if (!currentSong()) return "unavailable"
    requestSurface = String(surface || "")
    pendingSong = currentSong()
    error = ""
    launchAttempts = 0
    if (availability === "ready") {
      launch()
      return "opening"
    }
    promptRequested(requestSurface, availability)
    return availability
  }

  function pendingInstall() {
    var state = service ? service.sessionState : null
    var pending = state && state.pendingLyricsInstall
    return pending && typeof pending === "object" ? pending : null
  }

  function persistIntent() {
    if (!pendingSong || !service) return
    var state = Api.shallowCopy(service.sessionState)
    state.pendingLyricsInstall = Api.lyricsInstallIntent(pendingSong,
      requestSurface, Date.now())
    service.persistSession(state)
  }

  function clearIntent() {
    if (!pendingInstall() || !service) return
    service.persistSession(Api.sessionWithoutLyricsInstall(service.sessionState))
  }

  function confirm(surface) {
    if (busy) return false
    if (surface) requestSurface = String(surface)
    if (!pendingSong) pendingSong = currentSong()
    if (!pendingSong) {
      error = "Play a song first, then try lyrics again."
      return false
    }
    error = ""

    if (availability === "ready") {
      launchAttempts = 0
      launch()
      return true
    }

    var command = Api.optionalPluginSetupCommand(availability, pluginId, pluginUrl)
    if (!command.length) {
      error = "Omasing could not be prepared for installation."
      return false
    }
    operation = availability
    busy = true
    persistIntent()

    // Adding a plugin writes into ~/.config/omarchy/plugins, which reloads
    // the shell and would kill a child Process before enable finishes.
    // Detach the add and resume from the saved intent after reload.
    if (availability === "missing") {
      installStartedAt = Date.now()
      Quickshell.execDetached(command)
      installPoll.restart()
      return true
    }

    setupProcess.command = command
    setupProcess.running = true
    return true
  }

  function resumeIntent() {
    var intent = pendingInstall()
    if (!intent) return
    if (!Api.lyricsInstallIntentIsFresh(intent, Date.now(), 180000)) {
      clearIntent()
      return
    }
    if (!pendingSong) pendingSong = intent.song
    if (!requestSurface) requestSurface = String(intent.surface || "")

    if (availability === "ready") {
      installPoll.stop()
      busy = false
      error = ""
      launchAttempts = 0
      clearIntent()
      launch()
      return
    }

    if (busy || setupProcess.running || installPoll.running) return

    if (availability === "disabled") {
      confirm(requestSurface)
      return
    }

    busy = true
    operation = "missing"
    installStartedAt = Number(intent.startedAt) || Date.now()
    installPoll.restart()
  }

  function finishInstallWatch() {
    if (availability === "ready") {
      busy = false
      error = ""
      launchAttempts = 0
      clearIntent()
      launch()
      return true
    }
    if (availability === "disabled") {
      busy = false
      confirm(requestSurface)
      return true
    }
    if (Date.now() - installStartedAt < 90000) return false
    busy = false
    error = "Omasing could not be installed. Check your network and try again."
    clearIntent()
    promptRequested(requestSurface, availability)
    return true
  }

  function cancel(surface) {
    if (busy) return
    if (surface && String(surface) !== requestSurface) return
    installPoll.stop()
    requestSurface = ""
    pendingSong = null
    error = ""
    clearIntent()
  }

  function launch() {
    if (!pendingSong || launchProcess.running) return
    launchAttempts++
    launchProcess.command = ["/usr/bin/omarchy-shell",
      pluginId, "lyrics", JSON.stringify(pendingSong)]
    launchProcess.running = true
  }

  function finishLaunch(exitCode) {
    if (Number(exitCode) === 0) {
      var openedSurface = requestSurface
      pendingSong = null
      requestSurface = ""
      error = ""
      launchAttempts = 0
      opened(openedSurface)
      return
    }
    if (launchAttempts < 20) {
      launchRetry.restart()
      return
    }
    var detail = String(launchStderr.text || "").trim()
    error = service
      ? service.safeError(detail
        || "Omasing is installed, but its lyrics window could not be opened.")
      : "Omasing is installed, but its lyrics window could not be opened."
    promptRequested(requestSurface, availability)
  }

  Timer {
    id: launchRetry
    interval: 250
    repeat: false
    onTriggered: lyrics.launch()
  }

  Timer {
    id: installPoll
    interval: 400
    repeat: true
    onTriggered: if (lyrics.finishInstallWatch()) stop()
  }

  Process {
    id: setupProcess
    running: false
    command: []
    stdout: StdioCollector { id: setupStdout; waitForEnd: true }
    stderr: StdioCollector { id: setupStderr; waitForEnd: true }
    onExited: function(exitCode) {
      lyrics.busy = false
      if (Number(exitCode) === 0) {
        lyrics.operation = ""
        lyrics.error = ""
        lyrics.launchAttempts = 0
        launchRetry.restart()
        return
      }
      var detail = String(setupStderr.text || setupStdout.text || "").trim()
      lyrics.error = lyrics.service
        ? lyrics.service.safeError(detail || "Omasing could not be installed.")
        : "Omasing could not be installed."
    }
  }

  Process {
    id: launchProcess
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: launchStderr; waitForEnd: true }
    onExited: function(exitCode) { lyrics.finishLaunch(exitCode) }
  }
}
