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

  ScrollView {
    id: devicesScroll
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
      width: devicesScroll.availableWidth
      spacing: Style.space(9)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: Math.max(80, parent.width - deviceRefresh.width - parent.spacing)
          text: "Choose where your music plays. This computer and nearby Spotify Connect devices appear here."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Button {
          id: deviceRefresh
          text: page.panel.service && page.panel.service.devicesLoading ? "Loading…" : "Refresh"
          iconText: "󰑐"
          foreground: page.panel.foreground
          enabled: page.panel.service && !page.panel.service.devicesLoading
            && !page.panel.service.deviceActivationBusy
          onClicked: page.panel.service.loadDevices(null, undefined, true)
        }
      }

      Button {
        text: "Start this computer"
        iconText: "󰓃"
        foreground: page.panel.foreground
        visible: page.panel.service && page.panel.service.fullyConnected
          && !page.panel.service.daemon.running
        enabled: page.panel.service && !page.panel.service.daemon.busy
        onClicked: if (page.panel.service) page.panel.service.startEngine()
      }

      Text {
        width: parent.width
        visible: page.panel.service && page.panel.service.devicesLoading
          && page.panel.service.devices.length === 0
        text: "Looking for speakers and this computer…"
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        text: "AVAILABLE DEVICES"
        color: page.panel.foreground
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        width: parent.width
        text: "A nearby speaker may take a moment to connect the first time you choose it."
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: page.panel.service ? page.panel.service.devices : []

        delegate: BorderSurface {
        id: deviceRow
        required property var modelData
        width: devicesScroll.availableWidth
        implicitHeight: Style.space(58)
        height: implicitHeight
        radius: Style.cornerRadius
        color: modelData.id === (page.panel.service ? page.panel.service.selectedDeviceId : "")
          ? Style.selectedFillFor(page.panel.foreground, page.panel.accent)
          : (deviceHover.hovered ? Style.hoverFillFor(page.panel.foreground, page.panel.accent) : "transparent")
        borderSpec: modelData.active
          ? Border.controlSpec("selected", page.panel.foreground, page.panel.accent) : Border.none()

        HoverHandler { id: deviceHover }
        MouseArea {
          anchors.fill: parent
          enabled: (!deviceRow.modelData.restricted
            || deviceRow.modelData.activationRequired) && page.panel.service
            && !page.panel.service.deviceActivationBusy
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
          onClicked: if (page.panel.service) page.panel.service.selectDevice(deviceRow.modelData.id, true)
        }

        Row {
          anchors.fill: parent
          anchors.margins: Style.space(9)
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: deviceRow.modelData.type.toLowerCase() === "computer" ? "󰟀" : "󰋋"
            color: deviceRow.modelData.active ? page.panel.accent : page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.iconLarge
          }

          Column {
            width: Math.max(40, parent.width - Style.space(150))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: deviceRow.modelData.name
              color: page.panel.foreground
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.body
              font.bold: deviceRow.modelData.active
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: deviceRow.modelData.type
                + (deviceRow.modelData.description ? " · " + deviceRow.modelData.description : "")
                + (deviceRow.modelData.local ? " · this computer" : "")
                + (deviceRow.modelData.localDiscovery ? " · nearby" : "")
                + (deviceRow.modelData.restricted
                  ? (deviceRow.modelData.active
                    ? (page.panel.service && page.panel.service.sonosControlAvailable
                      ? " · local controls" : " · limited controls")
                    : " · unavailable") : "")
              color: page.panel.muted
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.panel.service && page.panel.service.deviceActivationBusy
                && deviceRow.modelData.id === page.panel.service.selectedDeviceId ? "Connecting"
              : (deviceRow.modelData.active ? "Active"
                : (deviceRow.modelData.activationRequired ? "Available"
                  : Math.round(deviceRow.modelData.volumePercent) + "%"))
            color: deviceRow.modelData.active ? page.panel.accent : page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
      }

      Text {
        width: parent.width
        visible: page.panel.service && page.panel.service.devicesLoaded
          && page.panel.service.devices.length === 0
        text: "No Spotify Connect devices are available right now. Make sure the device is online, then refresh."
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Item { width: 1; height: Style.space(4) }
    }
  }

  FastScrollHandler {
    parent: devicesScroll.contentItem
    flickable: devicesScroll.contentItem
  }
}
