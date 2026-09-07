import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// A full view of what is playing: large artwork, the names around it, and
// where you are in the track. Everything here is readable from across a room.
Item {
  id: page

  property var panel: null

  readonly property var service: panel ? panel.service : null
  readonly property var item: service ? service.currentTrackItem : null
  readonly property bool hasTrack: !!(service && service.currentUri)
  readonly property bool spokenWord: !!(service && service.currentIsSpokenWord)
  // Artwork takes whatever the shorter side allows, so it never crowds the text.
  readonly property int artSize: Math.max(Style.space(80),
    Math.min(width - Style.space(40), height - Style.space(120)))

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width, Math.max(page.artSize, Style.space(220)))
    spacing: Style.space(10)
    visible: page.hasTrack

    BorderSurface {
      id: artFrame
      width: page.artSize
      height: page.artSize
      anchors.horizontalCenter: parent.horizontalCenter
      radius: Style.cornerRadius
      color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
      borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)

      Image {
        id: art
        anchors.fill: parent
        anchors.margins: Style.space(2)
        source: page.service && page.service.artUrl
          ? page.service.artworkFor(page.service.artUrl) : ""
        sourceSize.width: 640
        sourceSize.height: 640
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: page.spokenWord ? "󰦔" : "󰝚"
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.displayLarge
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(2)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: page.service ? page.service.title : ""
        color: page.panel.foreground
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: page.service ? page.service.artist : ""
        color: page.panel.accent
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          enabled: !!(page.item && page.item.artists && page.item.artists.length)
          onClicked: page.panel.openItem(page.item.artists[0])
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: page.service ? page.service.album : ""
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          enabled: !!(page.item && page.item.albumItem)
          onClicked: page.panel.openItem(page.item.albumItem)
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(5)

      Text {
        id: elapsed
        anchors.verticalCenter: parent.verticalCenter
        text: Api.millisecondsToClock(
          (page.service ? page.service.positionSeconds : 0) * 1000)
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: Math.max(40, parent.width - elapsed.width - total.width
          - parent.spacing * 2)
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter

        PlaybackSlider {
          anchors.fill: parent
          bar: page.panel.panelBar
          minimum: 0
          maximum: Math.max(1, page.service ? page.service.lengthSeconds : 1)
          step: 5
          sourceValue: page.service ? page.service.positionSeconds : 0
          sourcePending: page.service && page.service.pendingRemoteSeek !== null
          acknowledgeTolerance: 2
          contextKey: page.service
            ? page.service.currentUri + "|" + page.service.playbackDeviceName : ""
          onCommitted: function(value) {
            if (page.service) page.service.seekSeconds(value)
          }
        }
      }

      Text {
        id: total
        anchors.verticalCenter: parent.verticalCenter
        text: Api.millisecondsToClock(
          (page.service ? page.service.lengthSeconds : 0) * 1000)
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(6)
    visible: !page.hasTrack

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "󰝚"
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.displayLarge
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Nothing playing"
      color: page.panel.foreground
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.title
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Pick something from your library and it will show up here."
      color: page.panel.muted
      font.family: page.panel.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
