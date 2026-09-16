import QtQuick
import qs.Commons
import qs.Ui

// What is playing, full size: large artwork, the names around it, and a live
// equalizer. The player bar below keeps playback controls, seek and volume.
Item {
  id: page

  property var panel: null
  // The equalizer runs only while this is true, so a closed view costs nothing.
  property bool active: false

  readonly property var service: panel ? panel.service : null

  Item {
    id: stage
    anchors.fill: parent
    anchors.margins: Style.space(22)
    readonly property real artSize: Math.max(Style.space(120),
      Math.min(height * 0.5, width * 0.34, Style.space(320)))

    Button {
      id: closeButton
      z: 2
      anchors.top: parent.top
      anchors.right: parent.right
      iconText: "󰅖"
      foreground: page.panel.foreground
      tooltipText: page.panel.shortcutHint("Close", "Esc")
      onClicked: page.panel.toggleNowPlayingExpanded()
    }

    Row {
      id: hero
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: stage.artSize
      spacing: Style.space(24)

      BorderSurface {
        id: heroArt
        width: stage.artSize
        height: width
        radius: Style.cornerRadius
        color: Style.selectedFillFor(page.panel.foreground, page.panel.accent)
        borderSpec: Border.controlSpec("normal", page.panel.foreground, page.panel.accent)

        RetryImage {
          id: heroImage
          anchors.fill: parent
          anchors.margins: Style.space(2)
          requestedSource: page.service && page.service.artworkEnabled
            ? page.service.artworkFor(page.service.artUrl) : ""
          sourceSize.width: 640
          sourceSize.height: 640
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: true
          visible: status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: heroImage.status !== Image.Ready
          text: "󰎈"
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Column {
        width: Math.max(80, parent.width - heroArt.width - parent.spacing
          - closeButton.width - Style.space(8))
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          width: parent.width
          text: page.service && page.service.title
            ? page.service.title : "Nothing playing"
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        ArtistLinks {
          width: parent.width
          artists: page.service ? page.service.currentArtists : []
          fallbackText: page.service && page.service.artist
            ? page.service.artist : "Choose something to play"
          fallbackClickable: page.service && page.service.artist !== ""
            && page.service.currentArtistContextAvailable
            && artists.length === 0
          color: page.service && page.service.artist
            && page.service.currentArtistContextAvailable ? page.panel.accent
            : page.panel.muted
          accent: page.panel.accent
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.title
          maximumLineCount: 1
          elide: Text.ElideRight
          onArtistRequested: function(item) { page.panel.openItem(item) }
          onFallbackRequested: page.panel.openCurrentArtist()
        }

        Text {
          width: parent.width
          visible: page.service && page.service.album !== ""
          text: page.service ? page.service.album : ""
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: page.service && page.service.playbackDeviceName !== ""
          text: page.service
            ? ((page.service.playing ? "Playing on " : "Connected to ")
              + page.service.playbackDeviceName)
            : ""
          color: page.panel.muted
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    Equalizer {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: hero.bottom
      anchors.topMargin: Style.space(22)
      anchors.bottom: parent.bottom
      active: page.active
      playing: page.service && page.service.playing
      configPath: page.service && page.service.stateDir
        ? page.service.stateDir + "/cava.conf" : ""
      scriptPath: page.service && page.service.pluginDir
        ? page.service.pluginDir + "/scripts/equalizer.sh" : ""
      mode: page.panel.equalizerMode
      onModeCycleRequested: page.panel.cycleEqualizerMode()
    }
  }
}
