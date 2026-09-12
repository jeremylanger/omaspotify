import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
  Plugin.Service { id: spotifyService }
  Plugin.Panel { id: panel; service: spotifyService; width: 1280; height: 800 }
  Plugin.BarWidget { id: widget }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      spotifyService.auth.customClientId = "invalid"
      spotifyService.search("smoke-test", "track")
      if (spotifyService.searchLoading || !spotifyService.searchError)
        throw new Error("Search service did not return the authorization error")
      if (!panel.primaryNavigationItems().some(function(item) { return item.id === "search" }))
        throw new Error("Search navigation is missing")
      spotifyService.clearSearch()
      if (spotifyService.searchQuery !== "") throw new Error("Search state did not clear")
      console.log("APP_SMOKE_PASS")
      Qt.quit()
    }
  }
}
