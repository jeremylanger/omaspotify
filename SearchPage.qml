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


  Component.onDestruction: {
    if (page.panel.service) page.panel.service.cancelSearch(false)
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      id: searchTypes
      width: parent.width
      spacing: Style.space(3)

      Repeater {
        model: [
          { type: "track", label: "Songs" },
          { type: "artist", label: "Artists" },
          { type: "album", label: "Albums" },
          { type: "playlist", label: "Playlists" },
          { type: "show", label: "Podcasts" },
          { type: "episode", label: "Episodes" },
          { type: "audiobook", label: "Books" }
        ]

        Button {
          required property var modelData
          text: modelData.label
          foreground: page.panel.foreground
          selected: page.panel.searchType === modelData.type
          focusable: false
          horizontalPadding: Style.space(7)
          hasCursor: page.panel.cursorOn("page", "search-" + modelData.type)
          onClicked: page.panel.searchType = modelData.type
          onHovered: function(on) {
            if (on) page.panel.setPanelCursor("page", "search-" + modelData.type)
          }
          KeyHint { region: "page"; action: "search-" + modelData.type }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(7)
      visible: page.panel.searchText.trim() === ""

      Row {
        width: parent.width

        Text {
          text: "RECENT SEARCHES"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Item { width: Math.max(0, parent.width - clearHistory.width - Style.space(120)); height: 1 }
        Button {
          id: clearHistory
          text: "Clear"
          foreground: page.panel.foreground
          visible: page.panel.service && page.panel.service.searchHistory.length > 0
          onClicked: page.panel.service.clearSearchHistory()
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(5)

        Repeater {
          model: page.panel.service ? page.panel.service.searchHistory : []
          Button {
            required property string modelData
            text: modelData
            iconText: "󰍉"
            foreground: page.panel.foreground
            onClicked: {
              page.panel.searchText = modelData
              page.panel.service.search(modelData)
              Qt.callLater(function() { page.panel.focusSearchField() })
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: !page.panel.service || page.panel.service.searchHistory.length === 0
        text: "Type a title, artist, album, playlist, podcast, episode, or audiobook."
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    MediaCollection {
      id: resultsView
      width: parent.width
      height: Math.max(40, parent.height - searchTypes.height - parent.spacing)
      visible: page.panel.searchText.trim() !== ""
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.searchItems(page.panel.searchType) : []
      showFilter: false
      showQueue: true
      showSave: true
      browseContexts: true
      loading: page.panel.service && page.panel.service.searchLoading
      hasMore: page.panel.service && page.panel.service.searchNext(page.panel.searchType) !== ""
      restoredContentY: page.panel.scrollFor("search:" + page.panel.searchType)
      stateKey: "search:" + page.panel.searchType
      emptyMessage: page.panel.service && page.panel.service.searchLoading
        ? "Searching…" : "No " + Api.searchTypeLabel(page.panel.searchType)
          + " results."
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
      onLoadMoreRequested: if (page.panel.service) page.panel.service.loadMoreSearch(page.panel.searchType)
      onViewStateChanged: function(filter, sort, y) {
        page.panel.rememberScroll("search:" + page.panel.searchType, y)
      }
    }
  }
}
