import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Plugin

ShellRoot {
  id: test
  QtObject {
    id: mockService
    property bool cachePlaylistsOnIdle: true
    property string playlistCacheStatus: "23/119 lists complete · 119 available locally · resumes when the panel closes"
    property string playlistCacheResult: ""
    function persistSettings(values) { cachePlaylistsOnIdle = values.cachePlaylistsOnIdle === "On" }
  }
  QtObject {
    id: fakePanel
    property var service: mockService
    property var windowContentItem: screen
    property real windowWidth: screen.width
    property real windowHeight: screen.height
    property color foreground: Color.foreground
    property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
    property color accent: Color.accent
    property color popupBackground: Color.background
    property var popupBorderSpec: Border.flat(Color.accent, 1)
    property string fontFamily: Style.font.family
    function disarmEscapeClose() {}
    function restoreFocus() {}
  }
  FloatingWindow {
    implicitWidth: 1280
    implicitHeight: 800
    visible: true
    color: fakePanel.popupBackground
    Item { id: screen; width: 1024; height: 768 }
    Plugin.PlaylistCachePopup { id: popup; panel: fakePanel }
  }
  function expect(value, message) { if (!value) throw new Error(message) }
  function fits(item) {
    if (!item.visible) return
    var at = item.mapToItem(screen, 0, 0)
    expect(at.x >= 0 && at.y >= 0 && at.x + item.width <= screen.width + 1
      && at.y + item.height <= screen.height + 1, "Cache control/result exceeds viewport")
    for (var i = 0; i < item.children.length; i++) fits(item.children[i])
  }
  property int phase: 0
  Timer {
    interval: 150
    running: true
    repeat: true
    onTriggered: {
      if (phase === 0) { popup.open(); phase++; return }
      fits(popup.contentItem)
      if (phase === 1 || phase === 4) {
        mockService.playlistCacheStatus = "Caching paused after Spotify refused a request"
        mockService.playlistCacheResult = "Cache request refused or failed (HTTP 429)"
      } else if (phase === 2 || phase === 5) {
        mockService.playlistCacheStatus = "Cache budget reached · saved lists stay checked, others load when opened"
        mockService.playlistCacheResult = "Spotify hides the songs of playlists you neither own nor collaborate on, so those are not cached"
      } else if (phase === 3) {
        var out = Quickshell.env("OMASPOTIFY_LAYOUT_OUTPUT")
        if (out) popup.contentItem.grabToImage(function(image) { image.saveToFile(out + "/cache-1024.png") })
        screen.width = 1280; screen.height = 800
      } else if (phase === 6) {
        stop()
        var target = Quickshell.env("OMASPOTIFY_LAYOUT_OUTPUT")
        if (target) popup.contentItem.grabToImage(function(image) {
          image.saveToFile(target + "/cache-1280.png")
          console.log("PLAYLIST_CACHE_LAYOUT_PASS"); Qt.quit()
        })
        else { console.log("PLAYLIST_CACHE_LAYOUT_PASS"); Qt.quit() }
      }
      phase++
    }
  }
}
