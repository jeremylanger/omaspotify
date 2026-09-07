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
    id: setupScroll
    anchors.fill: parent
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
      width: setupScroll.availableWidth
      spacing: Style.space(16)

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "SPOTIFY ACCOUNT"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          width: parent.width
          text: "Connect Spotify to search, browse your library, manage playlists, and listen on this computer or another Spotify Connect device."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        BorderSurface {
          width: parent.width
          implicitHeight: accountStatus.implicitHeight + Style.space(16)
          color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
          borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)
          radius: Style.cornerRadius

          Text {
            id: accountStatus
            anchors.fill: parent
            anchors.margins: Style.space(8)
            text: !page.panel.service ? "Spotify is unavailable"
              : (page.panel.service.loginBusy ? page.panel.service.loginProgress + "…"
              : (page.panel.fullyConnected ? "Connected and ready to play"
              : (page.panel.service.auth.loggedIn
                ? "Spotify is connected · playback needs approval"
                : (page.panel.service.daemon.credentialsAvailable
                  ? "Playback is ready · Spotify needs approval"
                  : "Not connected"))))
            color: page.panel.fullyConnected ? page.panel.accent : page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        Row {
          spacing: Style.space(7)

          Button {
            text: page.panel.connectionButtonText()
            iconText: "󰍂"
            foreground: page.panel.foreground
            selected: page.panel.fullyConnected
            visible: !page.panel.fullyConnected
            enabled: page.panel.service && !page.panel.service.loginBusy
            onClicked: if (page.panel.service) page.panel.service.login()
          }
          Button {
            text: "Cancel"
            foreground: page.panel.foreground
            visible: page.panel.service && page.panel.service.loginBusy
            onClicked: if (page.panel.service) page.panel.service.cancelLogin()
          }
          Button {
            text: "Reconnect Spotify"
            iconText: "󰑐"
            foreground: page.panel.foreground
            visible: page.panel.service && page.panel.service.auth.loggedIn
            enabled: page.panel.service && !page.panel.service.loginBusy
            tooltipText: "Reconnect if library or playlist features are not working"
            onClicked: page.panel.service.reconnectAccount()
          }
          Button {
            text: "Log out"
            iconText: "󰍃"
            foreground: page.panel.foreground
            visible: page.panel.service && (page.panel.service.auth.loggedIn
              || page.panel.service.daemon.credentialsAvailable)
            enabled: page.panel.service && !page.panel.service.loginBusy
              && !page.panel.service.daemon.busy
            onClicked: page.panel.service.logout()
          }
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

      PanelSeparator { foreground: page.panel.foreground }

      Column {
        id: localPlaybackSetup
        width: parent.width
        spacing: Style.space(7)
        visible: page.panel.service && !page.panel.service.daemon.playbackReady

        Text {
          text: "PLAYBACK ON THIS COMPUTER"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          width: parent.width
          text: "A lightweight background player starts only when you need it, works with Omarchy's media controls, and appears in Spotify Connect as this computer."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        BorderSurface {
          width: parent.width
          implicitHeight: engineStatus.implicitHeight + Style.space(16)
          color: Style.normalFillFor(page.panel.foreground, page.panel.accent)
          borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)
          radius: Style.cornerRadius

          Text {
            id: engineStatus
            anchors.fill: parent
            anchors.margins: Style.space(8)
            text: page.panel.playbackStatusText()
            color: page.panel.foreground
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        Row {
          spacing: Style.space(7)

          Button {
            text: page.panel.service && page.panel.service.daemon.setupBusy
              ? "Setting up playback…" : "Set up playback"
            iconText: "󰓃"
            foreground: page.panel.foreground
            visible: page.panel.service && !page.panel.service.daemon.playbackReady
            enabled: page.panel.service && !page.panel.service.loginBusy
            onClicked: page.panel.service.login()
          }
        }
      }

      PanelSeparator {
        foreground: page.panel.foreground
        visible: localPlaybackSetup.visible
      }

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "PREFERENCES"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          text: "SPOTIFY CONNECT"
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Column {
            width: Math.round(parent.width * 0.58)
            spacing: Style.space(4)

            Text {
              text: "THIS COMPUTER APPEARS AS"
              color: page.panel.muted
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            TextField {
              width: parent.width
              foreground: page.panel.foreground
              placeholderText: "OmaSpotify"
              text: page.panel.draftDeviceName
              onTextEdited: page.panel.draftDeviceName = text
              onEditingFinished: page.panel.persistDraftSettings()
            }
          }
          Column {
            width: Math.max(Style.space(150), parent.width - Math.round(parent.width * 0.58)
              - parent.spacing)
            spacing: Style.space(4)

            Text {
              text: "STOP WHEN IDLE · MINUTES"
              color: page.panel.muted
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            TextField {
              width: parent.width
              foreground: page.panel.foreground
              placeholderText: "15"
              text: page.panel.draftIdleMinutes
              validator: IntValidator { bottom: 0; top: 1440 }
              onTextEdited: page.panel.draftIdleMinutes = text
              onEditingFinished: page.panel.persistDraftSettings()
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "BAR PLAYER"
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Button {
            text: "Mini-player first · "
              + (page.panel.draftShowMiniPlayer ? "On" : "Off")
            iconText: "󰍹"
            foreground: page.panel.foreground
            selected: page.panel.draftShowMiniPlayer
            tooltipText: page.panel.draftShowMiniPlayer
              ? "Clicking the bar icon opens the mini-player first"
              : "Clicking the bar icon opens the full player directly"
            onClicked: {
              page.panel.draftShowMiniPlayer = !page.panel.draftShowMiniPlayer
              page.panel.persistDraftSettings()
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "KEYBOARD"
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Button {
            text: "Super + Shift + M · " + page.panel.draftShortcutPlayer
            iconText: "󰌌"
            foreground: page.panel.foreground
            selected: page.panel.draftShortcutPlayer !== "Omarchy Music app"
            focusable: true
            tooltipText: "Cycle between Omarchy's Music app, full player, and mini-player"
            onClicked: page.panel.cycleShortcutPlayer()
          }

          Text {
            width: parent.width
            text: "Cycles Omarchy Music app → Full player → Mini player. Super+Shift+M then opens that target."
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            text: "Shortcut hints · "
              + (page.panel.draftShortcutHints ? "On" : "Off")
            iconText: "󰘳"
            foreground: page.panel.foreground
            selected: page.panel.draftShortcutHints
            tooltipText: page.panel.draftShortcutHints
              ? "The first shortcut lights matching controls with the next key"
              : "Shortcuts still work, without the on-control overlay"
            onClicked: {
              page.panel.draftShortcutHints = !page.panel.draftShortcutHints
              page.panel.persistDraftSettings()
            }
          }

          Text {
            width: parent.width
            text: "After a shortcut or Tab, matching buttons glow and show the next key. Hold Ctrl, Shift, or Alt to see those chords, or press Ctrl+H to turn them off. Turn them on here again whenever you want the overlay back."
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "BAR TEXT"
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Title · " + (page.panel.draftShowTitle ? "On" : "Off")
              foreground: page.panel.foreground
              selected: page.panel.draftShowTitle
              tooltipText: "Show the song title in the top bar"
              onClicked: {
                page.panel.draftShowTitle = !page.panel.draftShowTitle
                page.panel.enforceScrollAvailability()
                page.panel.persistDraftSettings()
              }
            }
            Button {
              text: "Artist · " + (page.panel.draftShowArtist ? "On" : "Off")
              foreground: page.panel.foreground
              selected: page.panel.draftShowArtist
              tooltipText: "Show the artist name in the top bar"
              onClicked: {
                page.panel.draftShowArtist = !page.panel.draftShowArtist
                page.panel.enforceScrollAvailability()
                page.panel.persistDraftSettings()
              }
            }
            Button {
              text: "While paused · "
                + (page.panel.draftShowPausedTrack ? "Show" : "Hide")
              foreground: page.panel.foreground
              selected: page.panel.draftShowPausedTrack
              tooltipText: page.panel.draftShowPausedTrack
                ? "Keep the configured title and artist visible while paused"
                : "Show only the Spotify icon while paused"
              onClicked: {
                page.panel.draftShowPausedTrack = !page.panel.draftShowPausedTrack
                page.panel.persistDraftSettings()
              }
            }
            Button {
              text: "Scroll overflow · " + (page.panel.draftScrollBarText ? "On" : "Off")
              foreground: page.panel.foreground
              selected: page.panel.draftScrollBarText
              enabled: Api.canScrollBarText(page.panel.draftShowTitle, page.panel.draftShowArtist)
                && !page.panel.barTextWidthUnlimited
              tooltipText: page.panel.barTextWidthUnlimited
                ? "Unavailable while the bar width is unlimited — the label always fits"
                : "Scroll bar text only when it is too wide to fit"
              onClicked: {
                page.panel.draftScrollBarText = !page.panel.draftScrollBarText
                page.panel.persistDraftSettings()
              }
            }
            // Discloses the width slider rather than changing a setting;
            // the selected highlight marks the open state.
            Button {
              text: "Width · " + page.panel.maxBarTextWidthLabel()
              foreground: page.panel.foreground
              selected: page.panel.barTextWidthExpanded
              enabled: Api.canScrollBarText(page.panel.draftShowTitle, page.panel.draftShowArtist)
              tooltipText: "How wide the bar label may grow"
              onClicked: page.panel.barTextWidthExpanded = !page.panel.barTextWidthExpanded
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: Api.canScrollBarText(page.panel.draftShowTitle, page.panel.draftShowArtist)
              && page.panel.draftScrollBarText

            Row {
              width: parent.width

              Text {
                id: scrollSpeedTitle
                text: "SCROLL SPEED"
                color: page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Item {
                width: Math.max(0, parent.width - scrollSpeedTitle.implicitWidth
                  - scrollSpeedValue.implicitWidth)
                height: 1
              }
              Text {
                id: scrollSpeedValue
                text: page.panel.scrollSpeedLabel()
                color: page.panel.foreground
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            PanelSlider {
              width: parent.width
              bar: page.panel.panelBar
              minimum: 0.25
              maximum: 3
              step: 0.25
              tickCount: 12
              value: page.panel.draftScrollSpeed
              onMoved: function(value) {
                page.panel.draftScrollSpeed = Api.normalizedScrollSpeed(value)
              }
              onReleased: function(value) {
                page.panel.draftScrollSpeed = Api.normalizedScrollSpeed(value)
                page.panel.persistDraftSettings()
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: Api.canScrollBarText(page.panel.draftShowTitle, page.panel.draftShowArtist)
              && page.panel.barTextWidthExpanded

            Row {
              width: parent.width

              Text {
                id: maxBarWidthTitle
                text: "MAX WIDTH"
                color: page.panel.muted
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Item {
                width: Math.max(0, parent.width - maxBarWidthTitle.implicitWidth
                  - maxBarWidthValue.implicitWidth)
                height: 1
              }
              Text {
                id: maxBarWidthValue
                text: page.panel.maxBarTextWidthLabel()
                color: page.panel.foreground
                font.family: page.panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            PanelSlider {
              width: parent.width
              bar: page.panel.panelBar
              minimum: page.panel.barTextWidthSlider.min
              maximum: page.panel.barTextWidthSlider.unlimited
              step: page.panel.barTextWidthSlider.step
              tickCount: page.panel.barTextWidthSlider.ticks
              value: page.panel.maxBarTextWidthSliderValue()
              onMoved: function(value) {
                page.panel.setMaxBarTextWidthFromSlider(value)
              }
              onReleased: function(value) {
                page.panel.setMaxBarTextWidthFromSlider(value)
                page.panel.persistDraftSettings()
              }
            }

            Text {
              width: parent.width
              visible: page.panel.barTextWidthUnlimited
              text: "Very long titles will take space from other bar widgets."
              color: page.panel.muted
              font.family: page.panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Text {
            width: parent.width
            visible: page.panel.draftScrollBarText
            text: "Long labels scroll and fade at the edges only when they exceed the available bar space."
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "PLAYBACK"
            color: page.panel.muted
            font.family: page.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Button {
            text: "Audio quality · " + page.panel.audioQualityLabel()
            iconText: "󰎈"
            foreground: page.panel.foreground
            tooltipText: "Change streaming quality"
            onClicked: page.panel.cycleAudioQuality()
          }

          Button {
            text: "Normalize volume · "
              + (page.panel.draftNormalizeVolume ? "On" : "Off")
            iconText: "󰕾"
            foreground: page.panel.foreground
            tooltipText: "Play quiet and loud tracks at a similar level"
            onClicked: page.panel.toggleNormalizeVolume()
          }

          Button {
            text: "Volume level · " + page.panel.volumeLevelLabel()
            iconText: "󰝝"
            foreground: page.panel.foreground
            enabled: page.panel.draftNormalizeVolume
            tooltipText: "How loud normalized playback aims to be"
            onClicked: page.panel.cycleVolumeLevel()
          }
        }

        Text {
          width: parent.width
          text: "This computer stays visible in Spotify Connect while the player is open. After it closes, an empty receiver sleeps at the idle timeout; paused media stays available to resume. Use 0 minutes to keep this computer available even while the player is closed. Device name, audio quality and volume settings apply the next time local playback starts."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "Changes apply immediately. Device name and audio quality update the next time local playback starts."
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  FastScrollHandler {
    parent: setupScroll.contentItem
    flickable: setupScroll.contentItem
  }
}
