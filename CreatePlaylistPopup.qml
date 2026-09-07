import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

Popup {
  id: popup

  property var panel: null

  parent: popup.panel.windowContentItem
  x: Math.max(Style.space(8), (popup.panel.windowWidth - width) / 2)
  y: Math.max(Style.space(8), (popup.panel.windowHeight - height) / 2)
  width: Math.min(Style.space(400), popup.panel.windowWidth - Style.space(24))
  height: createPlaylistContent.implicitHeight + padding * 2
  padding: Style.space(9)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: Qt.callLater(function() {
    createPlaylistNameField.selectAll()
    createPlaylistNameField.forceActiveFocus()
  })
  onClosed: popup.panel.createPlaylistName = ""

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: Column {
    id: createPlaylistContent
    spacing: Style.space(8)

    Text {
      width: parent.width
      text: "Create a new playlist"
      color: popup.panel.foreground
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      width: parent.width
      text: "Give your new private playlist a name."
      color: popup.panel.muted
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    TextField {
      id: createPlaylistNameField
      width: parent.width
      foreground: popup.panel.foreground
      placeholderText: "Playlist name"
      text: popup.panel.createPlaylistName
      maximumLength: 100
      onTextEdited: popup.panel.createPlaylistName = text
      onAccepted: popup.panel.createNamedPlaylist()
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Button {
        width: (parent.width - parent.spacing) / 2
        text: "Cancel"
        foreground: popup.panel.foreground
        focusable: true
        enabled: !popup.panel.service || !popup.panel.service.playlistActionBusy
        onClicked: popup.close()
      }

      Button {
        id: confirmNewPlaylistButton
        width: (parent.width - parent.spacing) / 2
        text: popup.panel.service && popup.panel.service.playlistActionBusy ? "Creating…" : "Create"
        iconText: "󰐕"
        foreground: popup.panel.foreground
        selected: true
        focusable: true
        enabled: popup.panel.service && popup.panel.createPlaylistName.trim() !== ""
          && !popup.panel.service.playlistActionBusy
        onClicked: popup.panel.createNamedPlaylist()
      }
    }
  }
}
