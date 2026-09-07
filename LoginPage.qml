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
    id: loginScroll
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
      width: Math.min(Style.space(620), loginScroll.availableWidth)
      x: Math.max(0, (loginScroll.availableWidth - width) / 2)
      spacing: Style.space(14)

      Item { width: 1; height: Style.space(4) }

      Column {
        width: parent.width
        spacing: Style.space(5)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          color: page.panel.accent
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "OmaSpotify"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Your music, library, playlists, and Spotify Connect devices — at home in Omarchy."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }

      BorderSurface {
        width: parent.width
        implicitHeight: loginContent.implicitHeight + Style.space(28)
        color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
        borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)
        radius: Style.cornerRadius

        Column {
          id: loginContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(14)
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(10)

            BorderSurface {
              width: Style.space(34)
              height: width
              radius: width / 2
              color: page.panel.fullyConnected
                ? Style.selectedFillFor(page.panel.foreground, page.panel.accent)
                : Style.normalFillFor(page.panel.foreground, page.panel.accent)
              borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)

              Text {
                anchors.centerIn: parent
                text: page.panel.fullyConnected ? "󰄬" : ""
                color: page.panel.fullyConnected ? page.panel.accent : page.panel.foreground
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.icon
                font.bold: true
              }
            }

            Column {
              width: Math.max(40, parent.width - Style.space(44))
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: page.panel.connectionHeadline()
                color: page.panel.foreground
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                text: page.panel.service ? page.panel.service.loginProgress : "Spotify is unavailable"
                color: page.panel.fullyConnected
                  ? page.panel.accent : page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            width: parent.width
            text: "Two short steps. First connect your Spotify account so you can browse. Then approve playback on this computer if you want to listen here."
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.space(7)

            Row {
              spacing: Style.space(7)
              Text {
                text: page.panel.service && page.panel.service.auth.loggedIn ? "󰄬" : "󰋼"
                color: page.panel.service && page.panel.service.auth.loggedIn
                  ? page.panel.accent : page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: page.panel.service && page.panel.service.auth.loggedIn
                  ? "Your Spotify account is connected"
                  : (page.panel.service && page.panel.service.auth.loginBusy
                    ? "Connecting your Spotify account…"
                    : "Your Spotify account and library")
                color: page.panel.foreground
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              spacing: Style.space(7)
              Text {
                text: page.panel.service && page.panel.service.daemon.credentialsAvailable ? "󰄬" : "󰓃"
                color: page.panel.service && page.panel.service.daemon.credentialsAvailable
                  ? page.panel.accent : page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: page.panel.service && page.panel.service.daemon.credentialsAvailable
                  ? "Playback on this computer is connected"
                  : (page.panel.service && page.panel.service.daemon.authenticationBusy
                    ? "Connecting playback on this computer…"
                    : "Playback on this computer")
                color: page.panel.foreground
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(7)

            Button {
              width: page.panel.service && page.panel.service.loginBusy
                ? Math.max(80, parent.width - cancelLoginButton.width
                  - parent.spacing) : parent.width
              text: page.panel.connectionButtonText()
              iconText: "󰍂"
              foreground: page.panel.foreground
              selected: page.panel.fullyConnected
              enabled: page.panel.service && !page.panel.fullyConnected && !page.panel.service.loginBusy
              onClicked: if (page.panel.service) page.panel.service.login()
            }

            Button {
              id: cancelLoginButton
              text: "Cancel"
              foreground: page.panel.foreground
              visible: page.panel.service && page.panel.service.loginBusy
              onClicked: if (page.panel.service) page.panel.service.cancelLogin()
            }
          }

          Text {
            width: parent.width
            text: !page.panel.service || page.panel.service.daemon.playbackReady
              || page.panel.service.daemon.setupBusy ? ""
              : (page.panel.service.daemon.binaryAvailable
                ? "This prepares private, on-demand playback for your account."
                : "Omarchy may ask for your computer password to install its small playback component.")
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            visible: text !== ""
          }

          Text {
            width: parent.width
            text: page.panel.connectionErrorText()
            color: Color.urgent
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            visible: text !== ""
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Your password is entered only on Spotify's own page. OmaSpotify never sees it."
        color: page.panel.muted
        font.family: page.panel.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Item { width: 1; height: Style.space(4) }
    }
  }

  FastScrollHandler {
    parent: loginScroll.contentItem
    flickable: loginScroll.contentItem
  }
}
