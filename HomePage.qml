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

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      id: homeTypes
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [
          { type: "recent", label: "Recently played", icon: "󰋚" },
          { type: "tracks", label: "Top songs", icon: "󰎈" },
          { type: "artists", label: "Top artists", icon: "󰠃" },
          { type: "releases", label: "New releases", icon: "󰀥" }
        ]
        Button {
          required property var modelData
          text: modelData.label
          iconText: modelData.icon
          foreground: page.panel.foreground
          selected: page.panel.homeType === modelData.type
          focusable: false
          hasCursor: page.panel.cursorShown("page", "home-" + modelData.type)
          onClicked: page.panel.homeType = modelData.type
          onHovered: function(on) {
            if (on) page.panel.setPanelCursor("page", "home-" + modelData.type)
          }
          KeyHint { region: "page"; action: "home-" + modelData.type }
        }
      }
    }

    MediaCollection {
      width: parent.width
      height: Math.max(40, parent.height - homeTypes.height - parent.spacing)
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.homeItems(page.panel.homeType) : []
      filterText: page.panel.homeFilter
      showFilter: false
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.panel.service && page.panel.service.homeLoading
      hasMore: false
      restoredContentY: page.panel.scrollFor("home:" + page.panel.homeType)
      stateKey: "home:" + page.panel.homeType
      emptyMessage: page.panel.service && page.panel.service.homeLoading
        ? "Loading your listening history…"
        : (page.panel.homeFilter.trim() ? "No matches in " + page.panel.activeSearchScope.label + "."
          : "No listening history is available yet.")
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
      onViewStateChanged: function(filter, sort, y) {
        page.panel.rememberScroll("home:" + page.panel.homeType, y)
      }
    }
  }
}
