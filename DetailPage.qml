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

  readonly property bool isArtist: page.panel.service && page.panel.service.detailItem
    && page.panel.service.detailItem.type === "artist"
  readonly property bool searchActive: isArtist && page.panel.artistScopedSearchActive
  readonly property bool searchLoading: page.panel.service
    && page.panel.service.artistCatalogLoading
  readonly property int searchResultCount: page.panel.service
    ? page.panel.service.artistSongs.length + page.panel.service.artistAlbums.length
      + page.panel.service.artistPlaylists.length : 0
  readonly property int searchColumnCount: Api.responsiveResultColumns(
    Math.max(0, width - Style.space(10)), Style.space(760))
  readonly property var searchRows: Api.sectionedMediaRows([
    {
      id: "songs",
      heading: "SONGS",
      items: page.panel.service ? page.panel.service.artistSongs : [],
      loading: page.panel.service && page.panel.service.artistSongsLoading,
      hasMore: page.panel.service && page.panel.service.artistSongsNext !== ""
    },
    {
      id: "albums",
      heading: "ALBUMS & EPS",
      items: page.panel.service ? page.panel.service.artistAlbums : [],
      loading: page.panel.service && page.panel.service.artistAlbumsLoading,
      hasMore: page.panel.service && page.panel.service.artistAlbumsNext !== ""
    },
    {
      id: "playlists",
      heading: "PLAYLISTS",
      items: page.panel.service ? page.panel.service.artistPlaylists : [],
      loading: page.panel.service && page.panel.service.artistPlaylistsLoading,
      hasMore: page.panel.service && page.panel.service.artistPlaylistsNext !== ""
    }
  ], searchColumnCount)

  function artistSearchSource(sectionId) {
    if (!page.panel.service) return []
    if (sectionId === "albums") return page.panel.service.artistAlbums
    if (sectionId === "playlists") return page.panel.service.artistPlaylists
    return page.panel.service.artistSongs
  }

  function loadMoreArtistSearch(sectionId) {
    if (!page.panel.service) return
    if (sectionId === "albums") page.panel.service.loadMoreArtistAlbums()
    else if (sectionId === "playlists") page.panel.service.loadMoreArtistPlaylists()
    else page.panel.service.loadMoreArtistSongs()
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(8)

    BorderSurface {
      id: detailHero
      width: parent.width
      height: visible ? Style.space(132) : 0
      visible: !page.searchActive
      radius: Style.cornerRadius
      color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
      borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)

      Row {
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(12)

        BorderSurface {
          width: parent.height
          height: width
          radius: Style.cornerRadius
          color: Style.selectedFillFor(page.panel.foreground, page.panel.accent)
          borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)

          Image {
            id: detailArtwork
            anchors.fill: parent
            anchors.margins: Style.space(2)
            source: page.panel.service && page.panel.service.detailItem
              ? String(page.panel.service.detailItem.imageUrl || "") : ""
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            visible: status === Image.Ready
          }
          Text {
            anchors.centerIn: parent
            visible: detailArtwork.status !== Image.Ready
            text: ""
            color: page.panel.service && page.panel.service.detailItem
              ? page.panel.muted
              : page.panel.accent
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          width: Math.max(80, parent.width - parent.height - detailActions.width
            - parent.spacing * 2)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            width: parent.width
            text: page.panel.service && page.panel.service.detailItem
              ? page.panel.service.detailItem.name : "Loading…"
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
          ArtistLinks {
            width: parent.width
            artists: page.panel.service && page.panel.service.detailItem
              ? page.panel.service.detailItem.artists : []
            fallbackText: page.panel.service && page.panel.service.detailItem
              ? String(page.panel.service.detailItem.subtitle || "") : ""
            suffixText: page.panel.service && page.panel.service.detailItem
              ? Api.artistSubtitleSuffix(page.panel.service.detailItem) : ""
            color: page.panel.accent
            accent: page.panel.accent
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.body
            onArtistRequested: function(item) { page.panel.openItem(item) }
          }
          Text {
            width: parent.width
            visible: page.isArtist && text !== ""
            text: page.panel.service
              ? Api.artistDetailLine(page.panel.service.detailItem) : ""
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: page.panel.service && page.panel.service.detailItem
              ? String(page.panel.service.detailItem.description
                || page.panel.service.detailItem.releaseDate || "") : ""
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            maximumLineCount: 2
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
          }
        }

        Column {
          id: detailActions
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Button {
            text: "Play"
            iconText: "󰐊"
            foreground: page.panel.foreground
            selected: true
            focusable: false
            hasCursor: page.panel.cursorShown("page", "detail-play")
            enabled: page.panel.service && page.panel.service.detailItem
              && (["show", "audiobook"].indexOf(page.panel.service.detailItem.type) < 0
                || page.panel.service.detailItems.length > 0)
            onClicked: {
              if (["show", "audiobook"].indexOf(page.panel.service.detailItem.type) >= 0)
                page.panel.activateMedia(page.panel.service.detailItems[0],
                  page.panel.service.detailItems, "")
              else page.panel.activateMedia(page.panel.service.detailItem)
            }
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "detail-play")
            }
            KeyHint { region: "page"; action: "detail-play" }
          }
          Button {
            text: page.panel.service && page.panel.service.isSaved(page.panel.service.detailItem)
              ? "Saved" : "Save"
            iconText: page.panel.service && page.panel.service.isSaved(page.panel.service.detailItem)
              ? "󰓎" : "󰋑"
            foreground: Color.urgent
            accent: Color.urgent
            focusable: false
            hasCursor: page.panel.cursorShown("page", "detail-save")
            enabled: page.panel.service && page.panel.service.detailItem
              && !page.panel.service.isSaved(page.panel.service.detailItem)
            onClicked: if (page.panel.service && !page.panel.service.isSaved(page.panel.service.detailItem))
              page.panel.service.toggleSaved(page.panel.service.detailItem)
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "detail-save")
            }
            KeyHint { region: "page"; action: "detail-save" }
          }
          Button {
            id: detailMoreActions
            visible: page.panel.service && page.panel.service.detailItem
            iconText: "󰇙"
            foreground: page.panel.foreground
            tooltipText: page.panel.shortcutHint("More actions", "C")
            focusable: false
            hasCursor: page.panel.cursorShown("page", "detail-more")
            onHovered: function(on) {
              if (on) page.panel.setPanelCursor("page", "detail-more")
            }
            KeyHint {
              region: "page"
              action: "detail-more"
              sequences: ["C"]
            }
            onClicked: {
              var point = detailMoreActions.mapToItem(page.panel.windowContentItem,
                detailMoreActions.width, 0)
              page.panel.openMediaContext(page.panel.service.detailItem, point.x, point.y,
                page.panel.service.detailItems, page.panel.service.detailItem.uri, -1)
            }
          }
        }
      }
    }

    Text {
      id: detailNotice
      width: parent.width
      height: visible ? implicitHeight : 0
      visible: page.panel.service && page.panel.service.detailMessage !== ""
      text: page.panel.service ? page.panel.service.detailMessage : ""
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Column {
      id: artistCatalog
      width: parent.width
      height: visible ? Math.max(40, parent.height - detailHero.height
        - detailNotice.height - parent.spacing * 2) : 0
      visible: page.isArtist && !page.searchActive
      spacing: Style.space(7)

      Row {
        id: artistLists
        width: parent.width
        height: parent.height - relatedStrip.height
          - (relatedStrip.visible ? parent.spacing : 0)
        spacing: Style.space(10)

        readonly property bool showLiked: page.panel.service
          && page.panel.service.artistLikedSongs.length > 0
        readonly property real columnWidth: Api.evenColumnWidth(width, spacing,
          showLiked ? 3 : 2)

        Column {
          width: artistLists.columnWidth
          height: parent.height
          spacing: Style.space(5)

          Text {
            id: artistAlbumsHeading
            width: parent.width
            text: page.panel.artistSearchText.trim() ? "ALBUMS & EPS" : "TOP ALBUMS & EPS"
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MediaCollection {
            width: parent.width
            height: Math.max(30, parent.height - artistAlbumsHeading.height
              - parent.spacing)
            keyboardListId: "list-albums"
            service: page.panel.service
            sourceItems: page.panel.service ? page.panel.service.artistAlbums : []
            showFilter: false
            showQueue: false
            showSave: true
            browseContexts: true
            loading: page.panel.service && page.panel.service.artistAlbumsLoading
            hasMore: page.panel.service && page.panel.service.artistAlbumsNext !== ""
            emptyMessage: page.panel.service && (page.panel.service.artistAlbumsLoading
              || page.panel.service.detailLoading)
              ? "Finding releases…" : "No matching albums or EPs."
            onActivated: function(item, items, uri) {
              page.panel.activateMedia(item, items, uri)
            }
            onOpened: function(item) { page.panel.openItem(item) }
            onSaveToggled: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
            onContextRequested: function(item, x, y, index, items, uri, playbackUri) {
              page.panel.openMediaContext(item, x, y, items, uri, index, playbackUri)
            }
            onLoadMoreRequested: if (page.panel.service) page.panel.service.loadMoreArtistAlbums()
          }
        }

        Column {
          width: artistLists.columnWidth
          height: parent.height
          spacing: Style.space(5)

          Text {
            id: artistSongsHeading
            width: parent.width
            text: page.panel.artistSearchText.trim() ? "SONGS" : "TOP 10 SONGS"
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MediaCollection {
            width: parent.width
            height: Math.max(30, parent.height - artistSongsHeading.height
              - artistThisIsRow.height - parent.spacing
              * (artistThisIsRow.visible ? 2 : 1))
            keyboardListId: "list-songs"
            service: page.panel.service
            sourceItems: page.panel.service ? page.panel.service.artistSongs : []
            showFilter: false
            showQueue: true
            showSave: true
            browseContexts: false
            loading: page.panel.service && page.panel.service.artistSongsLoading
            hasMore: page.panel.service && page.panel.service.artistSongsNext !== ""
            emptyMessage: page.panel.service && (page.panel.service.artistSongsLoading
              || page.panel.service.detailLoading)
              ? "Finding songs…" : "No matching songs."
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
            onLoadMoreRequested: if (page.panel.service) page.panel.service.loadMoreArtistSongs()
          }

          MediaRow {
            id: artistThisIsRow
            objectName: "artist-thisis"
            service: page.panel.service
            width: parent.width
            height: visible ? implicitHeight : 0
            visible: page.panel.service && page.panel.service.artistThisIsPlaylist
            itemData: page.panel.service ? page.panel.service.artistThisIsPlaylist : null
            selected: page.panel.cursorOn("page", "detail-thisis")
            foreground: page.panel.foreground
            accent: page.panel.accent
            fontFamily: page.panel.fontFamily
            browseOnActivate: true
            showQueue: false
            showPlaylist: false
            showSave: true
            saved: page.panel.service && page.panel.service.isSaved(itemData)
            onActivated: function(item) { page.panel.activateMedia(item, [item], item.uri) }
            onOpenRequested: function(item) { page.panel.openItem(item) }
            onSaveRequested: function(item) {
              if (page.panel.service) page.panel.service.toggleSaved(item)
            }
            onContextRequested: function(item, sceneX, sceneY) {
              page.panel.openMediaContext(item, sceneX, sceneY, [item], item.uri, 0)
            }
            ShortcutHint {
              active: page.panel.shortcutHintsActive
                && page.panel.navHintFor("page", "detail-thisis") !== ""
              navHint: page.panel.navHintFor("page", "detail-thisis")
            }
          }
        }

        Column {
          width: artistLists.columnWidth
          height: parent.height
          spacing: Style.space(5)
          visible: artistLists.showLiked

          Text {
            id: artistLikedHeading
            width: parent.width
            text: "YOUR LIKED SONGS"
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MediaCollection {
            width: parent.width
            height: Math.max(30, parent.height - artistLikedHeading.height
              - parent.spacing)
            keyboardListId: "list-liked-songs"
            service: page.panel.service
            sourceItems: page.panel.service ? page.panel.service.artistLikedSongs : []
            showFilter: false
            showQueue: true
            showSave: true
            loading: page.panel.service && page.panel.service.artistLikedSongsLoading
            emptyMessage: "No liked songs by this artist."
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
          }
        }
      }

      Column {
        id: relatedStrip
        width: parent.width
        spacing: Style.space(3)
        visible: page.panel.service && page.panel.service.artistRelated.length > 0
        height: visible ? implicitHeight : 0

        Text {
          text: "FANS ALSO LIKE"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          spacing: Style.space(4)

          Repeater {
            model: page.panel.service ? page.panel.service.artistRelated : []

            SidebarRow {
              required property var modelData
              width: Style.space(52)
              height: Style.space(52)
              item: modelData
              grid: true
              thumbnailSize: Style.space(30)
              fallbackGlyph: "󰠃"
              service: page.panel.service
              foreground: page.panel.foreground
              accent: page.panel.accent
              muted: page.panel.muted
              fontFamily: page.panel.fontFamily
              onActivated: page.panel.openItem(modelData)
            }
          }
        }
      }

    }

    Item {
      id: artistSearchPage
      width: parent.width
      height: visible ? Math.max(40, parent.height - detailNotice.height
        - parent.spacing) : 0
      visible: page.searchActive

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        Text {
          id: artistSearchStatus
          width: parent.width
          text: page.searchLoading
            ? "Searching " + (page.panel.service && page.panel.service.detailItem
              ? page.panel.service.detailItem.name : "this artist") + "…"
            : page.searchResultCount
              + (page.searchResultCount === 1 ? " result" : " results")
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: artistSearchList
          width: Math.max(1, parent.width - Style.space(10))
          height: Math.max(30, parent.height - artistSearchStatus.height
            - artistSearchEmpty.height - parent.spacing * 2)
          property string queryKey: page.panel.artistSearchText
          model: page.searchRows.length
          clip: true
          spacing: Style.space(4)
          reuseItems: true
          cacheBuffer: Style.space(160)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          onQueryKeyChanged: positionViewAtBeginning()

          FastScrollHandler {
            parent: artistSearchList
            flickable: artistSearchList
          }

          delegate: Loader {
            id: artistSearchRowLoader
            required property int index
            property var rowData: page.searchRows[index]
            width: ListView.view.width
            height: {
              if (!rowData) return 0
              if (rowData.kind === "items") return Style.space(72)
              return rowData.kind === "heading" ? Style.space(28) : Style.space(40)
            }
            sourceComponent: {
              if (!rowData) return null
              if (rowData.kind === "items") return artistSearchMediaRow
              return rowData.kind === "heading" ? artistSearchHeadingRow
                : artistSearchMoreRow
            }
            onLoaded: if (item) item.rowData = rowData
            onRowDataChanged: if (item) item.rowData = rowData
          }
        }

        Text {
          id: artistSearchEmpty
          width: parent.width
          height: visible ? implicitHeight : 0
          visible: !page.searchLoading
            && page.searchResultCount === 0
          text: "No songs, albums, or playlists matched this search."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      Component {
        id: artistSearchHeadingRow

        Row {
          id: searchHeadingRow
          property var rowData: null
          spacing: Style.space(8)

          Text {
            width: Math.max(40, parent.width - artistSearchSectionCount.width
              - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            text: searchHeadingRow.rowData
              ? searchHeadingRow.rowData.heading : "RESULTS"
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: artistSearchSectionCount
            anchors.verticalCenter: parent.verticalCenter
            text: searchHeadingRow.rowData && searchHeadingRow.rowData.loading
              && searchHeadingRow.rowData.count === 0 ? "Finding…"
              : String(searchHeadingRow.rowData
                ? searchHeadingRow.rowData.count : 0)
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Component {
        id: artistSearchMediaRow

        Item {
          id: searchMediaGroup
          property var rowData: null

          Row {
            anchors.fill: parent
            spacing: Style.space(4)

            Repeater {
              model: searchMediaGroup.rowData
                ? Api.arrayValues(searchMediaGroup.rowData.items) : []

              MediaRow {
                required property var modelData
                required property int index
                width: Math.max(40, (parent.width - parent.spacing
                  * (page.searchColumnCount - 1))
                  / page.searchColumnCount)
                height: parent.height
                itemData: modelData
                service: page.panel.service
                foreground: page.panel.foreground
                accent: page.panel.accent
                fontFamily: page.panel.fontFamily
                browseOnActivate: searchMediaGroup.rowData
                  && searchMediaGroup.rowData.sectionId !== "songs"
                  && modelData && modelData.kind === "context"
                showQueue: searchMediaGroup.rowData
                  && searchMediaGroup.rowData.sectionId === "songs"
                showPlaylist: showQueue
                showSave: true
                saved: page.panel.service && page.panel.service.isSaved(modelData)
                onActivated: function(item) {
                  var sectionId = searchMediaGroup.rowData.sectionId
                  page.panel.activateMedia(item,
                    page.artistSearchSource(sectionId), "")
                }
                onOpenRequested: function(item) { page.panel.openItem(item) }
                onArtistRequested: function(item) { page.panel.openItem(item) }
                onAlbumRequested: function(item) { page.panel.openItem(item) }
                onQueueRequested: function(item) {
                  if (page.panel.service) page.panel.service.addToQueue(item)
                }
                onPlaylistRequested: function(item) {
                  page.panel.openPlaylistPicker(item)
                }
                onSaveRequested: function(item) {
                  if (page.panel.service) page.panel.service.toggleSaved(item)
                }
                onContextRequested: function(item, sceneX, sceneY) {
                  var row = searchMediaGroup.rowData
                  var items = page.artistSearchSource(row.sectionId)
                  page.panel.openMediaContext(item, sceneX, sceneY, items, "",
                    row.startIndex + index)
                }
              }
            }
          }
        }
      }

      Component {
        id: artistSearchMoreRow

        Item {
          id: searchMoreRow
          property var rowData: null

          Button {
            anchors.centerIn: parent
            text: searchMoreRow.rowData && searchMoreRow.rowData.loading
              ? "Loading…" : "Load more"
            foreground: page.panel.foreground
            enabled: searchMoreRow.rowData && searchMoreRow.rowData.hasMore
              && !searchMoreRow.rowData.loading
            onClicked: if (searchMoreRow.rowData)
              page.loadMoreArtistSearch(searchMoreRow.rowData.sectionId)
          }
        }
      }
    }

    MediaCollection {
      id: detailCollection
      width: parent.width
      height: Math.max(40, parent.height - detailHero.height - detailNotice.height
        - parent.spacing * 2)
      visible: !page.isArtist
      service: page.panel.service
      sourceItems: page.panel.service ? page.panel.service.detailItems : []
      filterText: page.panel.detailFilter
      sortKey: page.panel.detailSort
      contextUri: page.panel.service && page.panel.service.detailItem
        ? page.panel.service.detailItem.uri : ""
      showQueue: true
      showFilter: true
      showSort: true
      showSave: true
      browseContexts: true
      allowReorder: page.panel.service && page.panel.service.detailItem
        && page.panel.service.playlistOwned(page.panel.service.detailItem)
      reorderBusy: page.panel.service && page.panel.service.playlistActionBusy
      loading: page.panel.service && page.panel.service.detailLoading
      hasMore: page.panel.service && page.panel.service.detailNext !== ""
      restoredContentY: page.panel.scrollFor("detail:" + (page.panel.service && page.panel.service.detailItem
        ? page.panel.service.detailItem.uri : ""))
      stateKey: "detail:" + (page.panel.service && page.panel.service.detailItem
        ? page.panel.service.detailItem.uri : "")
      restoreReady: !page.panel.service || !page.panel.service.detailRestorePending
      emptyMessage: page.panel.service && page.panel.service.detailMessage
        ? page.panel.service.detailMessage : "No items are available for this selection."
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
      onReorderRequested: function(sourceIndex, destinationIndex) {
        if (page.panel.service && page.panel.service.detailItem)
          page.panel.service.reorderPlaylistItem(sourceIndex, destinationIndex,
            page.panel.service.detailItem, page.panel.service.detailItems.length,
            page.panel.service.detailItems)
      }
      onLoadMoreRequested: if (page.panel.service) page.panel.service.loadMoreDetail()
      onViewStateChanged: function(filter, sort, y) {
        page.panel.detailFilter = filter
        page.panel.detailSort = sort
        page.panel.rememberScroll("detail:" + (page.panel.service && page.panel.service.detailItem
          ? page.panel.service.detailItem.uri : ""), y)
      }
    }
  }
}
