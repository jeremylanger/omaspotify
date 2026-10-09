import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Popup {
  id: popup
  property var panel: null
  parent: popup.panel.windowContentItem
  width: Math.min(Style.space(740), popup.panel.windowWidth - Style.space(32))
  height: body.implicitHeight + padding * 2
  x: Math.max(Style.space(8), (popup.panel.windowWidth - width) / 2)
  y: Math.max(Style.space(8), (popup.panel.windowHeight - height) / 2)
  padding: Style.space(16)
  modal: true
  focus: true
  onOpened: popup.panel.disarmEscapeClose()
  onClosed: Qt.callLater(function() { popup.panel.restoreFocus() })
  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }
  contentItem: Column {
    id: body
    spacing: Style.space(12)
    Text {
      text: "PLAYLIST CACHE"
      color: popup.panel.foreground
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
    Row {
      width: parent.width
      spacing: Style.space(16)
      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(8)
        Text {
          width: parent.width
          text: "Keep song lists ready before you open them. Downloads one page at a time while this panel is closed; browsing and search take priority."
          color: popup.panel.foreground
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: "Checks playlist versions and skips unchanged lists. Changed lists are downloaded again. Progress survives restart. Off stops downloads and updates; saved lists stay readable until they are a week old or you log out."
          color: popup.panel.muted
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(8)
        Text {
          width: parent.width
          text: popup.panel.service ? popup.panel.service.playlistCacheStatus : "Spotify unavailable"
          color: popup.panel.accent
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: popup.panel.service ? popup.panel.service.playlistCacheResult : ""
          visible: text !== ""
          color: popup.panel.muted
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: "Song lists only, no audio downloads. Room for about 40,000 to 50,000 songs (32 MiB) in up to 512 playlists, 10,000 per playlist. Spotify hides the songs of playlists you only follow."
          color: popup.panel.muted
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Button {
          text: popup.panel.service && popup.panel.service.cachePlaylistsOnIdle
            ? "Idle caching · On" : "Idle caching · Off"
          foreground: popup.panel.foreground
          bordered: true
          focusable: true
          onClicked: if (popup.panel.service) popup.panel.service.persistSettings({
            cachePlaylistsOnIdle: popup.panel.service.cachePlaylistsOnIdle ? "Off" : "On"
          })
        }
      }
    }
    Button {
      text: "Done"
      foreground: popup.panel.foreground
      focusable: true
      onClicked: popup.close()
    }
  }
}
