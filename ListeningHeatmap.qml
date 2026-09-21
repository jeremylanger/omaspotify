import QtQuick

// A square for every day, darker the more you played that day. It reports the
// day under the pointer so the page can show one tooltip for the whole grid.
Row {
  id: heatmap

  property var grid: []
  property color accent: "white"
  property color emptyFill: "transparent"
  property real cellSize: 9
  property real cellRadius: 2
  property Item hoveredDay: null
  property string hoveredText: ""

  function shade(level) {
    if (level <= 0) return heatmap.emptyFill
    return Qt.rgba(heatmap.accent.r, heatmap.accent.g, heatmap.accent.b,
      0.22 + 0.24 * level)
  }

  function dayText(day) {
    if (!day) return ""
    return day.key + " · " + day.count + (day.count === 1 ? " play" : " plays")
  }

  function noteHovered(cell, on) {
    if (on) {
      hoveredDay = cell
      hoveredText = dayText(cell.modelData)
    } else if (hoveredDay === cell) {
      hoveredDay = null
      hoveredText = ""
    }
  }

  Repeater {
    model: heatmap.grid

    Column {
      required property var modelData
      spacing: heatmap.spacing

      Repeater {
        model: modelData

        Rectangle {
          id: cell
          required property var modelData
          width: heatmap.cellSize
          height: width
          radius: heatmap.cellRadius
          visible: !modelData.future
          color: heatmap.shade(modelData.level)

          HoverHandler {
            onHoveredChanged: heatmap.noteHovered(cell, hovered)
          }
        }
      }
    }
  }
}
