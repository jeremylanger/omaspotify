import QtQuick

Item {
  id: root
  property string query: ""
  property bool active: false
  property bool loading: false
  property bool hasMore: false
  property bool blocked: false
  property double cooldownUntil: 0
  property double clock: Date.now()
  readonly property bool waitingForCooldown: cooldownUntil > clock
  property int itemCount: 0
  property int pageBudget: 5
  property int pagesRequested: 0
  property bool paused: false
  property bool awaitingPage: false
  property int countBeforeRequest: 0
  readonly property bool available: query.trim() !== "" && hasMore
  signal requestNext()

  function reset() {
    pagesRequested = 0
    awaitingPage = false
    paused = false
    schedule()
  }
  function cancel() { paused = true; stepTimer.stop() }
  function resume() { pagesRequested = 0; paused = false; schedule() }
  function schedule() {
    if (active && available && !paused && !blocked && !waitingForCooldown) stepTimer.restart()
    else stepTimer.stop()
  }
  function step() {
    if (!active || !available || paused || blocked || waitingForCooldown || loading) return
    if (awaitingPage) {
      awaitingPage = false
      if (itemCount <= countBeforeRequest) { cancel(); return }
    }
    if (pagesRequested >= pageBudget) { cancel(); return }
    countBeforeRequest = itemCount
    awaitingPage = true
    pagesRequested++
    requestNext()
  }
  onQueryChanged: reset()
  onActiveChanged: { if (!active) cancel(); else schedule() }
  onLoadingChanged: if (!loading) schedule()
  onHasMoreChanged: schedule()
  onItemCountChanged: schedule()
  onBlockedChanged: if (blocked) cancel()
  onCooldownUntilChanged: { clock = Date.now(); if (waitingForCooldown) cancel() }
  Timer {
    interval: 1000
    repeat: true
    running: root.active && root.waitingForCooldown
    onTriggered: root.clock = Date.now()
  }
  Timer { id: stepTimer; interval: 350; onTriggered: root.step() }
}
