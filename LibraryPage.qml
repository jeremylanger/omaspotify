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

  Component.onCompleted: if (page.panel.service) page.panel.service.loadLibrary(page.panel.libraryType, false)

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      id: libraryTypes
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [
          { type: "tracks", label: "Songs", icon: "󰎈" },
          { type: "albums", label: "Albums", icon: "󰀥" },
          { type: "artists", label: "Artists", icon: "󰠃" },
          { type: "shows", label: "Podcasts", icon: "󰦔" },
          { type: "episodes", label: "Episodes", icon: "󰐾" },
          { type: "audiobooks", label: "Books", icon: "󰂺" }
        ]
        Button {
          required property var modelData
          text: modelData.label
          iconText: modelData.icon
          foreground: page.panel.foreground
          selected: page.panel.libraryType === modelData.type
          focusable: false
          hasCursor: page.panel.cursorOn("page", "library-" + modelData.type)
          onClicked: {
            page.panel.libraryType = modelData.type
            if (page.panel.service) page.panel.service.loadLibrary(modelData.type, false)
          }
          onHovered: function(on) {
            if (on) page.panel.setPanelCursor("page", "library-" + modelData.type)
          }
          KeyHint { region: "page"; action: "library-" + modelData.type }
        }
      }
    }

    MediaCollection {
      id: libraryCollection
      width: parent.width
      height: Math.max(40, parent.height - libraryTypes.height - parent.spacing)
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.libraryItems(page.panel.libraryType) : []
      filterText: page.panel.libraryFilter
      sortKey: page.panel.librarySort
      showFilter: false
      showSort: true
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.panel.service && page.panel.service.libraryLoading(page.panel.libraryType)
      hasMore: page.panel.service && page.panel.service.libraryNext(page.panel.libraryType) !== ""
      restoredContentY: page.panel.scrollFor("library:" + page.panel.libraryType)
      stateKey: "library:" + page.panel.libraryType
      emptyMessage: page.panel.service && page.panel.service.libraryLoading(page.panel.libraryType)
        ? "Loading your library…"
        : (page.panel.libraryFilter.trim()
          ? "No matches in " + page.panel.activeSearchScope.label + "."
          : "No saved items in this section.")
      onActivated: function(item, items, uri) {
        page.panel.activateMedia(item, items, uri)
      }
      onOpened: function(item) { page.panel.openItem(item) }
      onQueued: function(item) { if (page.panel.service) page.panel.service.addToQueue(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
      }
      onLoadMoreRequested: if (page.panel.service) page.panel.service.loadLibrary(page.panel.libraryType, true)
      onViewStateChanged: function(filter, sort, y) {
        page.panel.libraryFilter = filter
        page.panel.librarySort = sort
        page.panel.rememberScroll("library:" + page.panel.libraryType, y)
      }
    }
  }
}
