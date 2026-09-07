import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: page

  property var panel: null

  component KeyHint: PanelKeyHint {
    panel: page.panel
  }

  MediaCollection {
    anchors.fill: parent
    service: page.panel.service
    sourceItems: page.panel.service ? page.panel.service.discoverPlaylists : []
    filterText: page.panel.discoverFilter
    showFilter: false
    showQueue: false
    showPlaylist: false
    showSave: true
    browseContexts: true
    loading: page.panel.service && page.panel.service.discoverLoading
    hasMore: false
    restoredContentY: page.panel.scrollFor("discover")
    stateKey: "discover"
    emptyMessage: page.panel.service && page.panel.service.discoverLoading
      ? "Finding playlists picked for you…"
      : (page.panel.discoverFilter.trim() ? "No matches in Discover."
        : (page.panel.service && page.panel.service.discoverMessage
        ? page.panel.service.discoverMessage : "No discovery playlists are available yet."))
    onActivated: function(item, items, uri) {
      page.panel.activateMedia(item, items, uri)
    }
    onOpened: function(item) { page.panel.openItem(item) }
    onSaveToggled: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
    onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
      page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
    }
    onViewStateChanged: function(filter, sort, y) {
      page.panel.rememberScroll("discover", y)
    }
  }
}
