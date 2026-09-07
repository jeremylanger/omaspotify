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
    spacing: Style.space(6)

    Column {
      id: selectedPlaylistHeader
      width: parent.width
      spacing: Style.space(6)

      SearchableDropdown {
        visible: page.panel.compactWidth
        width: parent.width
        height: visible ? implicitHeight : 0
        showLabel: false
        foreground: page.panel.foreground
        background: page.panel.background
        accent: page.panel.accent
        fontFamily: page.panel.fontFamily
        placeholderText: "Choose a playlist…"
        emptyText: page.panel.service && page.panel.service.playlistsLoading
          ? "Loading playlists…" : "No playlists found"
        options: page.panel.playlistOptions()
        value: page.panel.service && page.panel.service.selectedPlaylist
          ? String(page.panel.service.selectedPlaylist.id) : ""
        onChanged: function(value) {
          page.panel.openSidebarItem(page.panel.sidebarItemById(value))
        }
      }

      Button {
        visible: page.panel.compactWidth && page.panel.service
          && page.panel.service.playlistsNext !== ""
        width: parent.width
        text: page.panel.service && page.panel.service.playlistsLoading
          ? "Loading more playlists…" : "Load more playlists"
        iconText: "󰑐"
        foreground: page.panel.foreground
        enabled: page.panel.service && !page.panel.service.playlistsLoading
        onClicked: page.panel.service.loadMorePlaylists()
      }

      Row {
        width: parent.width
        spacing: Style.space(4)

        Text {
          width: Math.max(40, parent.width
            - (playPlaylist.visible ? playPlaylist.width + parent.spacing : 0)
            - (playlistMoreActions.visible
              ? playlistMoreActions.width + parent.spacing : 0))
          text: page.panel.service && page.panel.service.selectedPlaylist
            ? page.panel.service.selectedPlaylist.name : "Select a playlist"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          id: playPlaylist
          visible: page.panel.service && page.panel.service.selectedPlaylist
          iconText: "󰐊"
          text: "Play"
          foreground: page.panel.foreground
          selected: true
          enabled: !playlistItemsCollection.playbackUsesVisibleOrder
            || playlistItemsCollection.visibleItems.length > 0
          hasCursor: page.panel.cursorOn("page", "playlist-play")
          tooltipText: playlistItemsCollection.playbackUsesVisibleOrder
            ? Api.visibleOrderPlaybackMessage(
              playlistItemsCollection.visibleItems.length)
            : "Play this playlist in its original order"
          onClicked: page.panel.playSelectedPlaylist()
          onHovered: function(on) {
            if (on) page.panel.setPanelCursor("page", "playlist-play")
          }
          KeyHint { region: "page"; action: "playlist-play" }
        }

        Button {
          id: playlistMoreActions
          visible: page.panel.service && page.panel.service.selectedPlaylist
          iconText: "󰇙"
          foreground: page.panel.foreground
          tooltipText: page.panel.shortcutHint("More actions", "C")
          hasCursor: page.panel.cursorOn("page", "playlist-more")
          onHovered: function(on) {
            if (on) page.panel.setPanelCursor("page", "playlist-more")
          }
          KeyHint {
            region: "page"
            action: "playlist-more"
            sequences: ["C"]
          }
          onClicked: {
            var point = playlistMoreActions.mapToItem(page.panel.windowContentItem,
              playlistMoreActions.width, 0)
            page.panel.openMediaContext(page.panel.service.selectedPlaylist, point.x, point.y,
              [], page.panel.service.selectedPlaylist.uri, -1)
          }
        }
      }

      Button {
        width: parent.width
        visible: page.panel.service && page.panel.service.selectedPlaylist
          && page.panel.service.currentUserId !== ""
          && !page.panel.service.playlistOwned(page.panel.service.selectedPlaylist)
        text: page.panel.service && page.panel.service.playlistConversionBusy
          ? "Making your copy…" : "Turn into your own playlist"
        iconText: "󰒍"
        foreground: page.panel.foreground
        selected: true
        enabled: page.panel.service && !page.panel.service.playlistActionBusy
        tooltipText: "Copy every available item, then remove the followed original"
        onClicked: page.panel.turnPlaylistIntoOwn(page.panel.service.selectedPlaylist)
      }
    }

    MediaCollection {
      id: playlistItemsCollection
      width: parent.width
      height: Math.max(40, parent.height - selectedPlaylistHeader.height - parent.spacing)
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.playlistItems : []
      filterText: page.panel.playlistFilter
      sortKey: page.panel.playlistSort
      contextUri: page.panel.service && page.panel.service.selectedPlaylist
        ? page.panel.service.selectedPlaylist.uri : ""
      showQueue: true
      showFilter: false
      showSort: true
      showSave: true
      browseContexts: false
      allowReorder: page.panel.service && page.panel.service.selectedPlaylist
        && page.panel.service.playlistOwned(page.panel.service.selectedPlaylist)
      reorderBusy: page.panel.service && page.panel.service.playlistActionBusy
      loading: page.panel.service && page.panel.service.playlistItemsLoading
      hasMore: page.panel.service && page.panel.service.playlistItemsNext !== ""
      emptyMessage: page.panel.service && page.panel.service.selectedPlaylist
        ? (page.panel.service.playlistItemsEmptyMessage
          || "This playlist has no visible items.")
        : (page.panel.compactWidth ? "Choose a playlist above."
          : "Choose a playlist from the sidebar.")
      restoredContentY: page.panel.scrollFor("playlist:" + (page.panel.service
        && page.panel.service.selectedPlaylist ? page.panel.service.selectedPlaylist.id : ""))
      stateKey: "playlist:" + (page.panel.service && page.panel.service.selectedPlaylist
        ? page.panel.service.selectedPlaylist.id : "")
      restoreReady: !page.panel.service || !page.panel.service.playlistRestorePending
      onActivated: function(item, items, uri) {
        page.panel.activateMedia(item, items, uri,
          playbackUsesVisibleOrder
            ? Api.visibleOrderPlaybackMessage(items.length) : "")
      }
      onOpened: function(item) { page.panel.openItem(item) }
      onQueued: function(item) { if (page.panel.service) page.panel.service.addToQueue(item) }
      onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
      onSaveToggled: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
        page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
      }
      onReorderRequested: function(sourceIndex, destinationIndex) {
        if (page.panel.service && page.panel.service.selectedPlaylist)
          page.panel.service.reorderPlaylistItem(sourceIndex, destinationIndex,
            page.panel.service.selectedPlaylist, page.panel.service.playlistItems.length,
            page.panel.service.playlistItems)
      }
      onLoadMoreRequested: if (page.panel.service) page.panel.service.loadMorePlaylistItems()
      onViewStateChanged: function(filter, sort, y) {
        page.panel.playlistFilter = filter
        page.panel.playlistSort = sort
        page.panel.rememberScroll("playlist:" + (page.panel.service
          && page.panel.service.selectedPlaylist ? page.panel.service.selectedPlaylist.id : ""), y)
      }
    }
  }
}
