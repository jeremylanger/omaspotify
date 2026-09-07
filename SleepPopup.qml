import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

Popup {
  id: popup

  property var panel: null

  component KeyHint: PanelKeyHint {
    panel: popup.panel
  }
  parent: popup.panel.windowContentItem
  x: Math.max(Style.space(8), popup.panel.windowWidth - width - Style.space(24))
  y: Math.max(Style.space(8), popup.panel.windowHeight - height - Style.space(130))
  width: Math.min(Style.space(270), popup.panel.windowWidth - Style.space(24))
  height: sleepContent.implicitHeight + padding * 2
  padding: Style.space(7)
  modal: false
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: {
    popup.panel.panelCursorActive = true
    popup.panel.panelCursorRegion = "popup"
    popup.panel.panelCursorAction = "sleep-15"
    popup.panel.ensurePanelCursor("popup")
  }
  onClosed: {
    if (popup.panel.panelCursorRegion === "popup") {
      popup.panel.panelCursorRegion = "footer"
      popup.panel.panelCursorAction = "sleep"
      popup.panel.ensurePanelCursor("footer")
    }
  }

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: Column {
    id: sleepContent
    spacing: Style.space(3)

    Text {
      width: parent.width
      text: popup.panel.service ? popup.panel.service.sleepStatusText() : "Sleep timer"
      color: popup.panel.foreground
      font.family: popup.panel.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      leftPadding: Style.space(7)
    }
    PanelSeparator { width: parent.width; foreground: popup.panel.foreground }
    Repeater {
      model: [15, 30, 60, 120]
      Button {
        required property int modelData
        width: sleepContent.width
        text: modelData + " minutes"
        iconText: "󰔛"
        foreground: popup.panel.foreground
        leftAlign: true
        hasCursor: popup.panel.cursorOn("popup", "sleep-" + modelData)
        KeyHint { region: "popup"; action: "sleep-" + modelData }
        onClicked: {
          if (popup.panel.service) popup.panel.service.setSleepMinutes(modelData)
          popup.close()
        }
      }
    }
    Button {
      width: parent.width
      text: "After this item"
      iconText: "󰐾"
      foreground: popup.panel.foreground
      leftAlign: true
      hasCursor: popup.panel.cursorOn("popup", "sleep-track")
      KeyHint { region: "popup"; action: "sleep-track" }
      onClicked: {
        if (popup.panel.service) popup.panel.service.sleepAfterTrack()
        popup.close()
      }
    }
    Button {
      width: parent.width
      text: "After this album or playlist"
      iconText: "󰓛"
      foreground: popup.panel.foreground
      leftAlign: true
      hasCursor: popup.panel.cursorOn("popup", "sleep-context")
      KeyHint { region: "popup"; action: "sleep-context" }
      onClicked: {
        if (popup.panel.service) popup.panel.service.sleepAfterContext()
        popup.close()
      }
    }
    Button {
      width: parent.width
      visible: popup.panel.service && popup.panel.service.sleepActive
      text: "Cancel timer"
      iconText: "󰅖"
      foreground: popup.panel.foreground
      leftAlign: true
      hasCursor: popup.panel.cursorOn("popup", "sleep-cancel")
      KeyHint { region: "popup"; action: "sleep-cancel" }
      onClicked: {
        popup.panel.service.cancelSleepTimer(true)
        popup.close()
      }
    }
  }
}
