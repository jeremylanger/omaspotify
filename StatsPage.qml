import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// What you actually listened to. Spotify keeps the last fifty plays and shows
// you none of it; this is built from the record the app keeps itself.
Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property int weeks: Math.max(8,
    Math.min(30, Math.floor((width - Style.space(60)) / Style.space(11))))
  readonly property var grid: service
    ? Api.heatmapWeeks(service.listeningDays, Date.now(), weeks) : []

  function shade(level) {
    if (level <= 0) return Style.normalFillFor(panel.foreground, panel.accent)
    return Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b,
      0.22 + 0.24 * level)
  }

  Component.onCompleted: {
    if (!service) return
    service.loadStats()
    // Top up the play record on the way in, so the counts above are what you
    // have actually listened to rather than what the last poll happened to see.
    service.refreshPlayHistory(false)
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(9)

    Row {
      width: parent.width
      spacing: Style.space(24)

      Repeater {
        model: [
          { value: page.service ? page.service.listeningPlayCount : 0, label: "plays recorded" },
          { value: page.service ? page.service.listeningDayCount : 0, label: "days listening" },
          { value: page.service ? page.service.likedSongLinkCount : 0, label: "liked songs indexed" }
        ]

        Column {
          required property var modelData
          spacing: Style.space(2)

          Text {
            text: String(modelData.value)
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            text: modelData.label
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: "LISTENING"
        color: page.panel.foreground
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Row {
        spacing: Style.space(2)

        Repeater {
          model: page.grid

          Column {
            required property var modelData
            spacing: Style.space(2)

            Repeater {
              model: modelData

              Rectangle {
                required property var modelData
                width: Style.space(9)
                height: width
                radius: Style.space(2)
                visible: !modelData.future
                color: page.shade(modelData.level)

                HoverHandler { id: cellHover }
                PanelToolTip {
                  visible: cellHover.hovered
                  text: modelData.key + " · " + modelData.count
                    + (modelData.count === 1 ? " play" : " plays")
                }
              }
            }
          }
        }
      }

    }

    Row {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [
          { range: "short_term", label: "Last 4 weeks" },
          { range: "medium_term", label: "Last 6 months" },
          { range: "long_term", label: "All time" }
        ]

        Button {
          required property var modelData
          text: modelData.label
          foreground: page.panel.foreground
          focusable: false
          selected: page.service && page.service.statsRange === modelData.range
          onClicked: if (page.service) page.service.setStatsRange(modelData.range)
        }
      }
    }

    Row {
      width: parent.width
      height: Math.max(Style.space(60), parent.height - y)
      spacing: Style.space(10)

      Column {
        width: Math.max(80, (parent.width - parent.spacing) / 2)
        height: parent.height
        spacing: Style.space(4)

        Text {
          id: artistsHeading
          text: "TOP ARTISTS"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        MediaCollection {
          width: parent.width
          height: Math.max(30, parent.height - artistsHeading.height - parent.spacing)
          keyboardListId: "list-stats-artists"
          service: page.service
          sourceItems: page.service ? page.service.statsArtists : []
          showFilter: false
          showSort: false
          browseContexts: true
          loading: page.service && page.service.statsLoading
          emptyMessage: "No ranking yet."
          onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
          onOpened: function(item) { page.panel.openItem(item) }
        }
      }

      Column {
        width: Math.max(80, parent.width - parent.spacing
          - Math.max(80, (parent.width - parent.spacing) / 2))
        height: parent.height
        spacing: Style.space(4)

        Text {
          id: tracksHeading
          text: "TOP SONGS"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        MediaCollection {
          width: parent.width
          height: Math.max(30, parent.height - tracksHeading.height - parent.spacing)
          keyboardListId: "list-stats-tracks"
          service: page.service
          sourceItems: page.service ? page.service.statsTracks : []
          showFilter: false
          showSort: false
          showSave: true
          loading: page.service && page.service.statsLoading
          emptyMessage: "No ranking yet."
          onActivated: function(item, items, uri) { page.panel.activateMedia(item, items, uri) }
          onOpened: function(item) { page.panel.openItem(item) }
          onSaveToggled: function(item) { if (page.service) page.service.toggleSaved(item) }
        }
      }
    }
  }
}
