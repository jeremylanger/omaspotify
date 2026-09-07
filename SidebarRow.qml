import QtQuick
import qs.Commons
import qs.Ui

// One entry in the library sidebar. Renders as a row or as a grid cell, with or
// without artwork, so the four view modes share a single delegate.
BorderSurface {
  id: row

  property var item: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property bool compact: false
  property bool grid: false
  property bool selected: false
  property bool hasCursor: false
  property int thumbnailSize: Style.space(32)
  property string fallbackGlyph: "󰲸"
  property var service: null

  readonly property bool pinned: !!(item && item.pinned)
  readonly property string label: item ? String(item.name || "Untitled") : ""
  readonly property bool hovered: hoverHandler.hovered

  signal activated()
  signal contextRequested()

  radius: Style.cornerRadius
  color: selected ? Style.selectedFillFor(foreground, accent)
    : (hovered || hasCursor ? Style.hoverFillFor(foreground, accent) : "transparent")
  borderSpec: selected ? Border.controlSpec("selected", foreground, accent)
    : Border.none()
  clip: true

  HoverHandler { id: hoverHandler }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) row.contextRequested()
      else row.activated()
    }
  }

  // Artwork, or the type glyph when there is none to show.
  Component {
    id: artworkPart

    BorderSurface {
      width: row.thumbnailSize
      height: row.thumbnailSize
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(row.foreground, row.accent)
      borderSpec: Border.controlSpec("normal", row.foreground, row.accent)

      Image {
        id: art
        anchors.fill: parent
        anchors.margins: Style.space(2)
        source: row.service && row.item && row.item.imageUrl
          ? row.service.artworkFor(row.item.imageUrl)
          : (row.item && row.item.imageUrl ? row.item.imageUrl : "")
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: row.fallbackGlyph
        color: row.muted
        font.family: row.fontFamily
        font.pixelSize: Style.font.icon
      }
    }
  }

  // Row layout: artwork, name, pin marker. Children of a positioner must not
  // be anchored, so each takes the full height and centres its own content.
  Row {
    anchors.fill: parent
    anchors.margins: Style.space(3)
    spacing: Style.space(5)
    visible: !row.grid

    Item {
      width: row.compact ? Style.space(14) : row.thumbnailSize
      height: parent.height

      Loader {
        anchors.centerIn: parent
        active: !row.compact
        sourceComponent: row.compact ? null : artworkPart
      }

      Text {
        anchors.centerIn: parent
        visible: row.compact
        text: row.fallbackGlyph
        color: row.muted
        font.family: row.fontFamily
        font.pixelSize: Style.font.iconSmall
      }
    }

    Text {
      width: Math.max(10, parent.width - parent.spacing * 2
        - (row.compact ? Style.space(14) : row.thumbnailSize)
        - (row.pinned ? Style.space(12) : 0))
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      text: row.label
      color: row.foreground
      font.family: row.fontFamily
      font.pixelSize: row.compact ? Style.font.bodySmall : Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: row.pinned
      width: visible ? Style.space(12) : 0
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      text: "󰐃"
      color: row.accent
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Grid layout: artwork above the name.
  Column {
    anchors.fill: parent
    anchors.margins: Style.space(3)
    spacing: Style.space(3)
    visible: row.grid

    Item {
      width: parent.width
      height: row.thumbnailSize

      Loader {
        anchors.centerIn: parent
        sourceComponent: artworkPart
      }
    }

    Text {
      width: parent.width
      visible: !row.compact
      text: row.label
      color: row.foreground
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

  }
}
