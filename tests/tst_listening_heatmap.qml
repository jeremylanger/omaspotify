import QtQuick
import QtQuick.Window
import QtTest

import ".."

TestCase {
  id: testCase
  name: "ListeningHeatmap"
  when: testWindow.visible

  property var sampleGrid: {
    var weeks = []
    for (var w = 0; w < 30; w++) {
      var days = []
      for (var d = 0; d < 7; d++)
        days.push({
          key: "2026-09-0" + (d + 1),
          count: d,
          level: d % 4,
          future: false
        })
      weeks.push(days)
    }
    return weeks
  }

  Window {
    id: testWindow
    width: 600
    height: 200
    visible: true

    ListeningHeatmap {
      id: heatmap
      grid: testCase.sampleGrid
      accent: "#f1dfb4"
      emptyFill: "#33a59d86"
      cellSize: 9
      spacing: 2
    }
  }

  function init() {
    mouseMove(testWindow, testWindow.width - 1, testWindow.height - 1)
  }

  function test_everyWeekGetsAColumnOfSevenDays() {
    var columns = 0
    for (var i = 0; i < heatmap.children.length; i++) {
      var days = 0
      var squares = heatmap.children[i].children
      for (var j = 0; j < squares.length; j++)
        if (squares[j].width === heatmap.cellSize) days++
      if (days === 7) columns++
    }
    compare(columns, 30)
  }

  function test_noDayIsNamedUntilOneIsHovered() {
    compare(heatmap.hoveredDay, null)
    compare(heatmap.hoveredText, "")
  }

  function test_hoveringADayNamesItAndItsPlays() {
    var cell = heatmap.children[0].children[1]

    mouseMove(cell, cell.width / 2, cell.height / 2)

    tryVerify(function() { return heatmap.hoveredDay !== null }, 2000)
    compare(heatmap.hoveredText, "2026-09-02 · 1 play")
  }

  function test_aDayWithSeveralPlaysIsPlural() {
    var cell = heatmap.children[0].children[3]

    mouseMove(cell, cell.width / 2, cell.height / 2)

    tryVerify(function() { return heatmap.hoveredDay !== null }, 2000)
    compare(heatmap.hoveredText, "2026-09-04 · 3 plays")
  }
}
