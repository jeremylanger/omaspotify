import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

Popup {
  id: popup

  property var panel: null

  // The panel drives keyboard navigation through these.
  function actionButtons() {
    return contextMenuContent ? contextMenuContent.children : []
  }

  component KeyHint: PanelKeyHint {
    panel: popup.panel
  }

  component ContextMenuButton: Button {
    id: ctxBtn
    property string contextAction: ""
    width: parent ? parent.width : implicitWidth
    foreground: popup.panel.foreground
    leftAlign: true
    hasCursor: popup.panel.cursorOn("popup", contextAction)
    focusable: false
    onHovered: function(on) {
      if (on && contextAction) popup.panel.setPanelCursor("popup", contextAction)
    }
    KeyHint {
      region: "popup"
      action: ctxBtn.contextAction
      active: popup.panel.shortcutHintsInPopup
    }
  }

  ShortcutModifiers {
    id: shortcutModifiers
  }
  // Where the caller asked for the menu. Keeping the corner as a binding
  // rather than a one-off assignment means a menu that grows a taller list of
  // actions moves back on screen instead of hanging off the bottom.
  property real requestedX: 0
  property real requestedY: 0

  parent: popup.panel.windowContentItem
  width: Math.min(Style.space(310), popup.panel.windowWidth - Style.space(24))
  height: Math.min(popup.panel.windowHeight - Style.space(24),
    contextMenuContent.implicitHeight + padding * 2)
  x: Math.max(Style.space(6),
    Math.min(popup.panel.windowWidth - width - Style.space(6), requestedX))
  y: Math.max(Style.space(6),
    Math.min(popup.panel.windowHeight - height - Style.space(6), requestedY))
  padding: Style.space(6)
  modal: true
  dim: false
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  onOpened: {
    popup.panel.popupReturnRegion = popup.panel.panelCursorRegion
    popup.panel.popupReturnAction = popup.panel.panelCursorAction
    popup.panel.latchShortcutMode()
    popup.panel.panelCursorActive = true
    popup.panel.panelCursorRegion = "popup"
    var actions = popup.panel.contextMenuCursorActions()
    popup.panel.panelCursorAction = actions.length ? actions[0] : ""
    popup.panel.ensurePanelCursor("popup")
    contextMenuFocus.forceActiveFocus()
  }
  onClosed: {
    if (popup.panel.panelCursorRegion === "popup") {
      popup.panel.panelCursorRegion = popup.panel.popupReturnRegion
      popup.panel.panelCursorAction = popup.panel.popupReturnAction
      popup.panel.ensurePanelCursor(popup.panel.popupReturnRegion)
      popup.panel.syncCursorFocus()
    }
    Qt.callLater(function() { popup.panel.restoreFocus() })
  }

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: FocusScope {
    id: contextMenuFocus
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: function(event) {
      if (shortcutModifiers.isHintModifierKey(event.key)) {
        popup.panel.considerShortcutModeKey(event, true)
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
          || event.key === Qt.Key_F6 || event.key === Qt.Key_Up
          || event.key === Qt.Key_Down || event.key === Qt.Key_Left
          || event.key === Qt.Key_Right || event.key === Qt.Key_J
          || event.key === Qt.Key_K || event.key === Qt.Key_H
          || event.key === Qt.Key_L || event.key === Qt.Key_Home
          || event.key === Qt.Key_End)
        event.accepted = true
    }
    Keys.onPressed: function(event) {
      popup.panel.considerShortcutModeKey(event, true)
      if (shortcutModifiers.isHintModifierKey(event.key)) {
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return
      if (popup.panel.handleContextMenuKey(event)) event.accepted = true
    }
    Keys.onReturnPressed: function(event) {
      if (popup.panel.handleContextMenuKey(event)) event.accepted = true
    }
    Keys.onEnterPressed: function(event) {
      if (popup.panel.handleContextMenuKey(event)) event.accepted = true
    }
    Keys.onReleased: function(event) {
      popup.panel.noteHeldModifiers(event, false)
      if (shortcutModifiers.isHintModifierKey(event.key)) event.accepted = true
    }

    Shortcut {
      sequences: ["Up", "K", "Left", "H"]
      enabled: popup.opened
      onActivated: popup.panel.moveContextMenuCursor(-1)
    }
    Shortcut {
      sequences: ["Down", "J", "Right", "L"]
      enabled: popup.opened
      onActivated: popup.panel.moveContextMenuCursor(1)
    }
    Shortcut {
      sequences: ["Return", "Enter"]
      enabled: popup.opened
      onActivated: popup.panel.activatePanelCursor()
    }

    ScrollView {
      id: contextMenuScroll
      anchors.fill: parent
      clip: true
      focus: false
      focusPolicy: Qt.NoFocus
      Keys.enabled: false
      rightPadding: contextMenuContent.implicitHeight > height
        ? popup.panel.popupScrollbarGutter : 0
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      Column {
        id: contextMenuContent
        width: contextMenuScroll.availableWidth
        spacing: Style.space(3)

    Text {
      width: parent.width
      leftPadding: Style.space(8)
      rightPadding: Style.space(8)
      topPadding: Style.space(4)
      bottomPadding: Style.space(4)
      text: popup.panel.contextItem ? String(popup.panel.contextItem.name || "Spotify item") : "Spotify item"
      color: popup.panel.muted
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      leftPadding: Style.space(8)
      rightPadding: Style.space(8)
      text: "Arrows or Enter to choose · Esc to close"
      color: popup.panel.muted
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    PanelSeparator { width: parent.width; foreground: popup.panel.foreground }

    ContextMenuButton {
      contextAction: "ctx-play"
      visible: popup.panel.contextItem
        && ["show", "audiobook"].indexOf(popup.panel.contextItem.type) < 0
      text: "Play"
      iconText: "󰐊"
      onClicked: {
        popup.close()
        popup.panel.activateMedia(popup.panel.contextItem, popup.panel.contextSourceItems,
          popup.panel.contextPlaybackUri)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-radio"
      visible: popup.panel.contextItem && popup.panel.contextItem.type === "track"
      text: "Start track radio"
      iconText: "󰎆"
      onClicked: {
        popup.close()
        if (popup.panel.service) popup.panel.service.startRadio(popup.panel.contextItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-queue"
      visible: popup.panel.contextItem
        && ["track", "episode"].indexOf(popup.panel.contextItem.type) >= 0
      text: "Add to queue"
      iconText: "󰐕"
      onClicked: {
        popup.close()
        if (popup.panel.service) popup.panel.service.addToQueue(popup.panel.contextItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-playlist"
      visible: popup.panel.contextItem
        && ["track", "episode"].indexOf(popup.panel.contextItem.type) >= 0
      text: "Add to playlist…"
      iconText: "󱁐"
      onClicked: {
        popup.close()
        popup.panel.openPlaylistPicker(popup.panel.contextItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-details"
      visible: popup.panel.contextItem && popup.panel.contextItem.kind === "context"
      text: "Open details"
      iconText: "󰋼"
      onClicked: {
        popup.close()
        popup.panel.openItem(popup.panel.contextItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-own"
      visible: popup.panel.contextItem && popup.panel.contextItem.type === "playlist"
        && popup.panel.service && popup.panel.service.currentUserId !== ""
        && !popup.panel.service.playlistOwned(popup.panel.contextItem)
      text: popup.panel.service && popup.panel.service.playlistConversionBusy
        ? "Making your copy…" : "Turn into your own playlist"
      iconText: "󰒍"
      enabled: popup.panel.service && !popup.panel.service.playlistActionBusy
      onClicked: {
        var playlist = popup.panel.contextItem
        popup.close()
        popup.panel.turnPlaylistIntoOwn(playlist)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-artist"
      visible: popup.panel.contextItem && popup.panel.contextItem.type === "track"
        && popup.panel.contextItem.artists && popup.panel.contextItem.artists.length
      text: "Go to artist"
      iconText: "󰠃"
      onClicked: {
        popup.close()
        popup.panel.openItem(popup.panel.contextItem.artists[0])
      }
    }

    ContextMenuButton {
      contextAction: "ctx-album"
      visible: popup.panel.contextItem && !!popup.panel.contextItem.albumItem
      text: "Go to album"
      iconText: "󰀥"
      onClicked: {
        popup.close()
        popup.panel.openItem(popup.panel.contextItem.albumItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-library"
      visible: popup.panel.contextItem && !!popup.panel.contextItem.uri
        && popup.panel.contextItem.type !== "chapter"
      text: popup.panel.service && popup.panel.service.isSaved(popup.panel.contextItem)
        ? "Remove from library" : "Save to library"
      iconText: popup.panel.service && popup.panel.service.isSaved(popup.panel.contextItem) ? "󰓎" : "󰋑"
      onClicked: {
        popup.close()
        if (popup.panel.service) popup.panel.service.toggleSaved(popup.panel.contextItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-move-up"
      visible: popup.panel.contextPlaylist && popup.panel.service
        && popup.panel.service.playlistEditable(popup.panel.contextPlaylist)
        && popup.panel.contextItem && popup.panel.contextItem.kind === "item"
      text: "Move up"
      iconText: "󰁝"
      enabled: popup.panel.contextPlaylistMoveSpec(-1).available
      onClicked: popup.panel.moveContextPlaylistItem(-1)
    }

    ContextMenuButton {
      contextAction: "ctx-move-down"
      visible: popup.panel.contextPlaylist && popup.panel.service
        && popup.panel.service.playlistEditable(popup.panel.contextPlaylist)
        && popup.panel.contextItem && popup.panel.contextItem.kind === "item"
      text: "Move down"
      iconText: "󰁅"
      enabled: popup.panel.contextPlaylistMoveSpec(1).available
      onClicked: popup.panel.moveContextPlaylistItem(1)
    }

    ContextMenuButton {
      contextAction: "ctx-remove"
      visible: popup.panel.contextPlaylist && popup.panel.service
        && popup.panel.service.playlistEditable(popup.panel.contextPlaylist)
        && popup.panel.contextItem && popup.panel.contextItem.kind === "item"
      text: "Remove from playlist"
      iconText: "󰅖"
      onClicked: {
        var position = popup.panel.playlistPosition(popup.panel.contextItem)
        popup.close()
        popup.panel.service.removePlaylistItem(popup.panel.contextItem, position, popup.panel.contextPlaylist)
      }
    }

    PanelSeparator {
      width: parent.width
      visible: popup.panel.contextItem && popup.panel.contextItem.externalUrl
      foreground: popup.panel.foreground
    }

    ContextMenuButton {
      contextAction: "ctx-copy"
      visible: popup.panel.contextItem && popup.panel.contextItem.externalUrl
      text: "Copy Spotify link"
      iconText: "󰌷"
      onClicked: {
        popup.close()
        popup.panel.copyExternal(popup.panel.contextItem)
      }
    }

    ContextMenuButton {
      contextAction: "ctx-open"
      visible: popup.panel.contextItem && popup.panel.contextItem.externalUrl
      text: "Open in Spotify"
      iconText: "󰏌"
      onClicked: {
        popup.close()
        popup.panel.openExternal(popup.panel.contextItem)
      }
    }
      }
    }
  }
}
