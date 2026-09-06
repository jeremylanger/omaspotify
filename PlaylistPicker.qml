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
  width: Math.min(Style.space(410), popup.panel.windowWidth - Style.space(32))
  height: Math.min(Style.space(520), pickerContent.implicitHeight + padding * 2)
  padding: Style.space(8)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: Column {
    id: pickerContent
    spacing: Style.space(7)

    Text {
      width: parent.width
      text: popup.panel.pendingPlaylistItem
        ? "Add “" + String(popup.panel.pendingPlaylistItem.name || "song") + "” to a playlist"
        : "Add to playlist"
      color: popup.panel.foreground
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: "Choose one of your playlists, or create a new private playlist."
      color: popup.panel.muted
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: newPlaylistField
        width: Math.max(80, parent.width - createPlaylistButton.width - parent.spacing)
        foreground: popup.panel.foreground
        placeholderText: "Name a new playlist"
        text: popup.panel.newPlaylistName
        onTextEdited: popup.panel.newPlaylistName = text
        onAccepted: createPlaylistButton.clicked()
      }

      Button {
        id: createPlaylistButton
        text: "Create"
        iconText: "󰐕"
        foreground: popup.panel.foreground
        enabled: popup.panel.service && popup.panel.newPlaylistName.trim() !== ""
          && !popup.panel.service.playlistActionBusy
        onClicked: {
          if (!popup.panel.service) return
          popup.panel.service.createPlaylist(popup.panel.newPlaylistName, function(playlist) {
            if (popup.panel.pendingPlaylistItem) popup.panel.service.addItemToPlaylist(
              popup.panel.pendingPlaylistItem, playlist)
            popup.panel.newPlaylistName = ""
            popup.close()
          })
        }
      }
    }

    PanelSeparator { width: parent.width; foreground: popup.panel.foreground }

    ListView {
      id: playlistPickerList
      width: parent.width
      height: Math.min(Style.space(340), Math.max(Style.space(80), contentHeight))
      model: popup.panel.service ? popup.panel.service.editablePlaylists() : []
      clip: true
      spacing: Style.space(2)
      keyNavigationEnabled: true
      highlightFollowsCurrentItem: true
      activeFocusOnTab: true
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      Keys.onReturnPressed: if (currentItem) currentItem.clicked()
      Keys.onEnterPressed: if (currentItem) currentItem.clicked()

      FastScrollHandler { parent: playlistPickerList; flickable: playlistPickerList }

      delegate: Button {
        required property var modelData
        width: Math.max(80, ListView.view.width
          - (playlistPickerList.contentHeight > playlistPickerList.height
            ? popup.panel.popupScrollbarGutter : 0))
        text: modelData.name || "Playlist"
        iconText: "󰲸"
        foreground: popup.panel.foreground
        leftAlign: true
        onClicked: {
          if (popup.panel.service && popup.panel.pendingPlaylistItem)
            popup.panel.service.addItemToPlaylist(popup.panel.pendingPlaylistItem, modelData)
          popup.close()
        }
      }
    }
  }
}
