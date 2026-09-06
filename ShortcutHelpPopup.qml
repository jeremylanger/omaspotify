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
  x: Math.max(Style.space(8), (popup.panel.windowWidth - width) / 2)
  y: Math.max(Style.space(8), (popup.panel.windowHeight - height) / 2)
  width: Math.min(Style.space(640), popup.panel.windowWidth - Style.space(32))
  height: Math.min(Style.space(560), popup.panel.windowHeight - Style.space(24))
  padding: Style.space(12)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: popup.panel.disarmEscapeClose()
  onClosed: Qt.callLater(function() { popup.panel.restoreFocus() })

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: Column {
    id: shortcutHelpContent
    spacing: Style.space(7)

    Row {
      id: shortcutHelpHeader
      width: parent.width
      spacing: Style.space(6)

      Column {
        width: Math.max(80, parent.width - shortcutHelpClose.width - parent.spacing)
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: "Keyboard shortcuts"
          color: popup.panel.foreground
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: "The first shortcut lights matching controls. Playback shortcuts pause while you type."
          color: popup.panel.muted
          font.family: popup.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Button {
        id: shortcutHelpClose
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        foreground: popup.panel.foreground
        tooltipText: popup.panel.shortcutHint("Close", "Esc")
        focusable: true
        onClicked: popup.close()
        KeyHint {
          sequences: ["Esc"]
          active: popup.panel.shortcutHintsInPopup
        }
      }
    }

    PanelSeparator {
      id: shortcutHelpSeparator
      width: parent.width
      foreground: popup.panel.foreground
    }

    ScrollView {
      id: shortcutHelpScroll
      width: parent.width
      height: Math.max(80, parent.height - shortcutHelpHeader.height
        - shortcutHelpSeparator.height - parent.spacing * 2)
      rightPadding: popup.panel.popupScrollbarGutter
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      Column {
        id: shortcutHelpList
        width: shortcutHelpScroll.availableWidth
        spacing: Style.space(3)

        Repeater {
          model: popup.panel.shortcutRows()

          delegate: Column {
            id: shortcutRow
            required property var modelData
            width: shortcutHelpList.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              visible: String(shortcutRow.modelData.section || "") !== ""
              topPadding: visible ? Style.space(3) : 0
              text: String(shortcutRow.modelData.section || "")
              color: popup.panel.accent
              font.family: popup.panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: Math.max(80, parent.width - shortcutKey.width - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: String(shortcutRow.modelData.action || "")
                color: popup.panel.foreground
                font.family: popup.panel.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              BorderSurface {
                id: shortcutKey
                width: shortcutKeyText.implicitWidth + Style.space(12)
                height: shortcutKeyText.implicitHeight + Style.space(6)
                radius: Style.cornerRadius
                color: Style.normalFillFor(popup.panel.foreground, popup.panel.accent)
                borderSpec: Border.controlSpec("normal", popup.panel.foreground, popup.panel.accent)

                Text {
                  id: shortcutKeyText
                  anchors.centerIn: parent
                  text: String(shortcutRow.modelData.keys || "")
                  color: popup.panel.foreground
                  font.family: popup.panel.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }
        }
      }
    }
  }
}
