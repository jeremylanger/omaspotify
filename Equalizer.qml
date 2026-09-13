import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Live spectrum for the expanded now-playing view.
//
// scripts/equalizer.sh points cava at the plugin's own PipeWire output
// stream and streams one ascii frame per line ("v;v;v;...", 0..1000 per
// band), or "idle" while nothing plays on this computer. The bands are drawn
// in one of four styles that all follow the active Omarchy theme:
//
//   bars    solid gradient bars
//   pixels  chunky LED matrix
//   scope   mirrored oscilloscope trace
//   matrix  falling glyph columns
//
// The helper only runs while the view is visible, so an idle player costs
// nothing.
Item {
  id: root

  property bool active: false
  property bool playing: false
  property string configPath: ""
  property string scriptPath: ""
  property int barCount: 48
  property string mode: "bars"
  property color barColor: Color.accent
  property color foreground: Color.foreground
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property real barGap: Style.space(4)

  property var levels: []
  // Set only once the helper says nothing plays here, so the note about
  // another device does not flash while cava is still starting.
  property bool streamIdle: false
  property bool unavailable: false
  property string unavailableReason: ""

  readonly property real barWidth: Math.max(2,
    (width - barGap * (barCount - 1)) / barCount)
  readonly property real minBarHeight: Math.max(2, Style.space(3))
  readonly property bool idle: streamIdle || (!playing
    && levels.every(function(v) { return v <= 0.001 }))

  signal modeCycleRequested()

  onActiveChanged: active ? start() : stop()
  onScriptPathChanged: if (active) start()
  onConfigPathChanged: if (active) start()
  onModeChanged: modeBadge.flash()
  Component.onCompleted: if (active) start()
  Component.onDestruction: stop()

  function start() {
    if (helper.running || !configPath || !scriptPath || unavailable) return
    helper.running = true
  }

  function stop() {
    if (helper.running) helper.running = false
    levels = []
    streamIdle = false
    // Try again next time the view opens, so installing cava needs no restart.
    unavailable = false
  }

  function handleLine(line) {
    var text = String(line || "")
    if (text === "idle") {
      streamIdle = true
      if (levels.length) levels = []
      return
    }
    var parts = text.split(";")
    var next = []
    for (var i = 0; i < parts.length && next.length < barCount; i++) {
      if (parts[i] === "") continue
      var v = Number(parts[i])
      if (!isFinite(v)) continue
      next.push(Math.max(0, Math.min(1, v / 1000)))
    }
    if (!next.length) return
    streamIdle = false
    levels = next
  }

  function bandLevel(index) {
    return index < levels.length ? levels[index] : 0
  }

  // Merge neighbouring bands for the chunkier styles.
  function groupedLevel(index, groupSize) {
    var peak = 0
    for (var i = index * groupSize; i < (index + 1) * groupSize; i++)
      peak = Math.max(peak, bandLevel(i))
    return peak
  }

  Process {
    id: helper
    command: ["/usr/bin/bash", root.scriptPath, root.configPath,
      String(root.barCount)]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.levels = []
      root.streamIdle = false
      // A stop requested by the view arrives here after active already
      // flipped, so only a failure while still active is worth reporting.
      if (!root.active) return
      if (exitCode === 127) {
        root.unavailable = true
        root.unavailableReason = "Install cava to see the live equalizer"
      } else if (exitCode === 126) {
        root.unavailable = true
        root.unavailableReason = "The equalizer needs pw-dump and python3"
      } else if (exitCode !== 0) {
        root.unavailable = true
        root.unavailableReason = "The equalizer could not start (exit "
          + exitCode + ")"
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !root.unavailable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.modeCycleRequested()
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    visible: !root.unavailable && root.mode !== "scope"
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
  }

  // Style 1: gradient bars.
  Item {
    id: barsStage
    anchors.fill: parent
    visible: !root.unavailable && root.mode === "bars"

    Repeater {
      model: barsStage.visible ? root.barCount : 0

      Rectangle {
        required property int index
        readonly property real level: root.bandLevel(index)

        x: index * (root.barWidth + root.barGap)
        width: root.barWidth
        anchors.bottom: parent.bottom
        height: Math.max(root.minBarHeight, level * barsStage.height)
        radius: Math.min(Style.cornerRadius, width / 2)
        antialiasing: true
        opacity: root.idle ? 0.35 : 1
        gradient: Gradient {
          GradientStop { position: 0.0; color: root.barColor }
          GradientStop {
            position: 1.0
            color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.28)
          }
        }

        Behavior on height {
          NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
        }
        Behavior on opacity { NumberAnimation { duration: 400 } }
      }
    }
  }

  // Style 2: LED pixel matrix. Two bands per column, square cells.
  Item {
    id: pixelStage
    anchors.fill: parent
    visible: !root.unavailable && root.mode === "pixels"

    readonly property int columns: Math.max(1, Math.floor(root.barCount / 2))
    readonly property real gap: Math.max(2, Style.space(3))
    // Square cells sized by width, but never so large that fewer than six
    // rows fit; the grid is centred when the height caps the cell size.
    readonly property real cell: Math.max(3, Math.min(
      (width - gap * (columns - 1)) / columns,
      (height + gap) / 6 - gap))
    readonly property int rows: Math.max(1, Math.floor((height + gap) / (cell + gap)))
    readonly property real gridWidth: columns * cell + gap * (columns - 1)
    readonly property real originX: Math.max(0, (width - gridWidth) / 2)

    Repeater {
      model: pixelStage.visible ? pixelStage.columns : 0

      Item {
        id: pixelColumn
        required property int index
        readonly property real level: root.groupedLevel(index, 2)
        readonly property int lit: Math.round(level * pixelStage.rows)

        x: pixelStage.originX + index * (pixelStage.cell + pixelStage.gap)
        width: pixelStage.cell
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Repeater {
          model: pixelStage.rows

          Rectangle {
            required property int index
            // Row 0 sits at the bottom of the column.
            readonly property bool on: index < pixelColumn.lit
            readonly property bool head: on && index === pixelColumn.lit - 1

            width: pixelStage.cell
            height: pixelStage.cell
            y: pixelColumn.height - (index + 1) * (pixelStage.cell + pixelStage.gap)
            radius: Math.min(Style.cornerRadius, 2)
            color: head
              ? Qt.lighter(root.barColor, 1.25)
              : (on ? root.barColor
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06))
            opacity: on ? (root.idle ? 0.35 : 1) : 1
          }
        }
      }
    }
  }

  // Style 3: mirrored oscilloscope trace.
  Canvas {
    id: scopeStage
    anchors.fill: parent
    visible: !root.unavailable && root.mode === "scope"
    renderStrategy: Canvas.Cooperative

    Connections {
      target: root
      function onLevelsChanged() { if (scopeStage.visible) scopeStage.requestPaint() }
      function onIdleChanged() { if (scopeStage.visible) scopeStage.requestPaint() }
    }
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      var w = width, h = height, cy = h / 2
      ctx.clearRect(0, 0, w, h)
      var n = root.barCount
      if (n < 2) return
      var step = w / (n - 1)
      var alpha = root.idle ? 0.35 : 1

      // Base line.
      ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g,
        root.foreground.b, 0.18)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, cy)
      ctx.lineTo(w, cy)
      ctx.stroke()

      // Upper half, then the mirrored lower half, closed into one shape.
      ctx.beginPath()
      var amp = function(i) {
        return Math.max(1.5, root.bandLevel(i) * (cy - 2))
      }
      ctx.moveTo(0, cy - amp(0))
      for (var i = 1; i < n; i++) {
        var x0 = (i - 1) * step, x1 = i * step
        var mid = (x0 + x1) / 2
        ctx.quadraticCurveTo(x0, cy - amp(i - 1), mid, cy - (amp(i - 1) + amp(i)) / 2)
      }
      ctx.lineTo(w, cy - amp(n - 1))
      ctx.lineTo(w, cy + amp(n - 1))
      for (var j = n - 1; j > 0; j--) {
        var xa = j * step, xb = (j - 1) * step
        var m2 = (xa + xb) / 2
        ctx.quadraticCurveTo(xa, cy + amp(j), m2, cy + (amp(j) + amp(j - 1)) / 2)
      }
      ctx.lineTo(0, cy + amp(0))
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b,
        0.22 * alpha)
      ctx.fill()
      ctx.strokeStyle = Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b,
        alpha)
      ctx.lineWidth = 2
      ctx.stroke()
    }
  }

  // Style 4: falling glyph columns.
  Item {
    id: matrixStage
    anchors.fill: parent
    visible: !root.unavailable && root.mode === "matrix"
    clip: true

    readonly property int columns: Math.max(1, Math.floor(root.barCount / 2))
    readonly property real cellWidth: width / columns
    readonly property real fontPx: Math.max(8, Math.min(Style.font.body,
      Math.floor(cellWidth * 0.9)))
    readonly property real lineHeight: Math.round(fontPx * 1.25)
    readonly property int rows: Math.max(1, Math.floor(height / lineHeight))
    readonly property string glyphs: "0123456789ABCDEF#$%&*+=<>/\\|:;"
    property var grid: []

    function reseed() {
      var next = []
      for (var r = 0; r < rows; r++) {
        var row = ""
        for (var c = 0; c < columns; c++)
          row += glyphs.charAt(Math.floor(Math.random() * glyphs.length))
        next.push(row)
      }
      grid = next
    }

    onRowsChanged: reseed()
    onColumnsChanged: reseed()
    onVisibleChanged: if (visible) reseed()

    Timer {
      interval: 140
      running: matrixStage.visible && !root.idle
      repeat: true
      onTriggered: matrixStage.reseed()
    }

    // Dim resting grid so the whole area reads as a terminal.
    Repeater {
      model: matrixStage.visible ? matrixStage.columns : 0
      Text {
        required property int index
        x: index * matrixStage.cellWidth
        anchors.bottom: parent.bottom
        width: matrixStage.cellWidth
        horizontalAlignment: Text.AlignHCenter
        lineHeight: matrixStage.lineHeight
        lineHeightMode: Text.FixedHeight
        font.family: root.fontFamily
        font.pixelSize: matrixStage.fontPx
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        text: {
          var s = ""
          for (var r = 0; r < matrixStage.rows; r++) s += (r ? "\n" : "") + "·"
          return s
        }
      }
    }

    Repeater {
      model: matrixStage.visible ? matrixStage.columns : 0
      Text {
        required property int index
        readonly property real level: root.groupedLevel(index, 2)
        readonly property int lit: Math.round(level * matrixStage.rows)

        x: index * matrixStage.cellWidth
        anchors.bottom: parent.bottom
        width: matrixStage.cellWidth
        horizontalAlignment: Text.AlignHCenter
        lineHeight: matrixStage.lineHeight
        lineHeightMode: Text.FixedHeight
        font.family: root.fontFamily
        font.pixelSize: matrixStage.fontPx
        font.bold: true
        color: root.barColor
        opacity: root.idle ? 0.35 : 1
        textFormat: Text.RichText
        text: {
          var rows = matrixStage.rows
          var grid = matrixStage.grid
          var head = Qt.lighter(root.barColor, 1.35).toString()
          var out = ""
          for (var r = 0; r < rows; r++) {
            // Row 0 is the top line; lit rows fill up from the bottom.
            var fromBottom = rows - 1 - r
            var on = fromBottom < lit
            var glyph = on && grid[r] ? grid[r].charAt(index) : "&nbsp;"
            if (glyph === "<") glyph = "&lt;"
            else if (glyph === ">") glyph = "&gt;"
            else if (glyph === "&") glyph = "&amp;"
            if (on && fromBottom === lit - 1)
              glyph = "<font color=\"" + head + "\">" + glyph + "</font>"
            out += (r ? "<br>" : "") + glyph
          }
          return out
        }
      }
    }
  }

  // Mode badge: shows the style name briefly after a change.
  Item {
    id: modeBadge
    anchors.top: parent.top
    anchors.right: parent.right
    width: badgeText.implicitWidth + Style.space(12)
    height: badgeText.implicitHeight + Style.space(6)
    opacity: 0
    visible: !root.unavailable

    function flash() {
      opacity = 1
      badgeTimer.restart()
    }

    Behavior on opacity { NumberAnimation { duration: 350 } }
    Timer { id: badgeTimer; interval: 1600; onTriggered: modeBadge.opacity = 0 }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.16)
      border.width: 1
      border.color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.5)
    }
    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.mode.toUpperCase() + " · V"
      color: root.barColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Text {
    anchors.centerIn: parent
    visible: !root.unavailable && root.streamIdle
    width: Math.min(parent.width, Style.space(420))
    text: root.playing
      ? "Playing on another device · the equalizer follows local playback"
      : "Play something on this computer to light up the equalizer"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }

  Text {
    anchors.centerIn: parent
    visible: root.unavailable
    width: Math.min(parent.width, Style.space(420))
    text: root.unavailableReason
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
}
