import QtQuick

// The panel's shortcut hint. Pages live in their own files, so this takes the
// panel explicitly instead of reading it from the surrounding scope.
ShortcutHint {
  property var panel: null
  property string region: ""
  property string action: ""

  ctrlHeld: panel ? panel.hintCtrlHeld : false
  shiftHeld: panel ? panel.hintShiftHeld : false
  altHeld: panel ? panel.hintAltHeld : false
  active: panel ? panel.shortcutHintsActive : false
  foreground: panel ? panel.foreground : Color.foreground
  accent: panel ? panel.accent : Color.accent

  // Reading these keeps the hint bound to every input that can move the
  // keyboard cursor, so it re-reads the label whenever any of them changes.
  navHint: {
    if (!panel) return ""
    panel.panelCursorAction
    panel.panelCursorRegion
    panel.panelCursorVisible
    panel.panelCursorActive
    panel.shortcutModeLatched
    panel.hintCtrlHeld
    panel.hintShiftHeld
    panel.hintAltHeld
    panel.playlistShortcutIndex
    panel.searchFieldFocused
    return region && action ? panel.navHintFor(region, action) : ""
  }
}
