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

  readonly property var visibleItems: Api.filteredSorted(
    page.panel.service ? page.panel.service.queue : [], page.panel.queueFilter, "default")

  Column {
    anchors.fill: parent
    spacing: Style.space(8)

    Row {
      width: parent.width

      Text {
        text: "UP NEXT"
        color: page.panel.foreground
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Item { width: Math.max(0, parent.width - queueRefresh.width - Style.space(80)); height: 1 }

      Button {
        id: queueRefresh
        text: page.panel.service && page.panel.service.queueLoading ? "Loading…" : "Refresh"
        iconText: "󰑐"
        foreground: page.panel.foreground
        enabled: page.panel.service && !page.panel.service.queueLoading
        onClicked: page.panel.service.loadQueue()
      }
    }

    ListView {
      id: queueList
      objectName: "page-list"
      width: parent.width
      height: Math.max(60, parent.height - Style.space(44))
      model: page.visibleItems
      clip: true
      spacing: Style.space(3)
      reuseItems: true
      cacheBuffer: Style.space(140)
      keyNavigationEnabled: false
      highlightFollowsCurrentItem: true
      activeFocusOnTab: false
      ScrollBar.vertical: ScrollBar { }
      Keys.onReturnPressed: function(event) {
        if (!page.panel.cursorOn("page", "list")) {
          event.accepted = false
          return
        }
        if (currentItem) currentItem.triggerPrimary()
        event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (!page.panel.cursorOn("page", "list")) {
          event.accepted = false
          return
        }
        if (currentItem) currentItem.triggerPrimary()
        event.accepted = true
      }

      FastScrollHandler { parent: queueList; flickable: queueList }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.space(16)
        width: Math.max(80, parent.width - Style.space(24))
        visible: queueList.count === 0
        text: page.panel.service && page.panel.service.queueLoading
          ? "Loading the queue…"
          : (page.panel.queueFilter.trim()
            ? "No matching songs in the queue."
            : "Nothing is queued to play next.")
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }

      delegate: MediaRow {
        required property var modelData
        required property int index
        itemData: modelData
        service: page.panel.service
        foreground: page.panel.foreground
        accent: page.panel.accent
        fontFamily: page.panel.fontFamily
        selected: ListView.isCurrentItem
          && page.panel.cursorOn("page", "list")
        showQueue: false
        showSave: true
        saved: page.panel.service && page.panel.service.isSaved(modelData)
        onActivated: function(item) {
          page.panel.activateMedia(item, page.visibleItems, "")
        }
        onArtistRequested: function(item) { page.panel.openItem(item) }
        onAlbumRequested: function(item) { page.panel.openItem(item) }
        onOpenRequested: function(item) { page.panel.openItem(item) }
        onPlaylistRequested: function(item) { page.panel.openPlaylistPicker(item) }
        onSaveRequested: function(item) { if (page.panel.service) page.panel.service.toggleSaved(item) }
        onContextRequested: function(item, sceneX, sceneY) {
          page.panel.openMediaContext(item, sceneX, sceneY,
            page.visibleItems, "", index)
        }
        ShortcutHint {
          active: hint !== ""
          navHint: hint
          readonly property string hint: {
            queueList.currentIndex
            queueList.contentY
            page.panel.panelCursorAction
            page.panel.panelCursorRegion
            page.panel.hintCtrlHeld
            return page.panel.pageListRowHint(index, queueList)
          }
        }
      }
    }
  }
}
