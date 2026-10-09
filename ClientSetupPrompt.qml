import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: prompt
  property var service: null
  property color foreground: Color.foreground
  property color muted: Color.muted
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string clientId: service ? String(service.settings.clientId || "") : ""
  property string result: ""
  readonly property bool valid: clientId.trim() === "" || /^[0-9a-f]{32}$/i.test(clientId.trim())
  readonly property string redirectUri: service ? service.auth.redirectUri : "http://127.0.0.1:8989/login"
  readonly property string connection: !service ? ""
    : service.auth.loggedIn ? "Selected Spotify app is connected."
    : "Selected Spotify app is not connected yet."
  signal dismissed()
  signal clientSaved()
  signal copyRequested(string text)
  signal dashboardRequested()
  implicitHeight: content.implicitHeight

  function saveClient() {
    if (!service || !valid) return false
    service.persistSettings({ clientId: clientId.trim().toLowerCase() })
    result = clientId.trim() ? "Saved your Spotify app."
      : "Saved. The shared Spotify app is selected."
    clientSaved()
    return true
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(12)
    Text {
      width: parent.width
      text: "Use your own Spotify app?"
      color: prompt.foreground
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      width: parent.width
      text: "Optional: the shared app can reach its request quota. A personal app uses your developer account's quota, which also has limits. Spotify Premium is required. Some public playlist contents still need the shared app."
      color: prompt.muted
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
    Row {
      width: parent.width
      spacing: Style.space(20)
      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(8)
        Text {
          width: parent.width
          text: "1 · Create a developer app"
          color: prompt.foreground
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Text {
          width: parent.width
          text: "Open developer.spotify.com/dashboard. Create an app named OmaSpotify with a description such as Personal desktop player. Select Web API, then accept Spotify's terms if you agree."
          color: prompt.muted
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Button {
          objectName: "openDashboard"
          text: "Open Spotify dashboard"
          foreground: prompt.foreground
          onClicked: prompt.dashboardRequested()
        }
        Text {
          width: parent.width
          text: "Add this exact Redirect URI. It is the local login callback Spotify returns to after authorization."
          color: prompt.muted
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: prompt.redirectUri
          color: prompt.accent
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
        }
        Button {
          objectName: "copyRedirect"
          text: "Copy Redirect URI"
          foreground: prompt.foreground
          onClicked: { prompt.copyRequested(prompt.redirectUri); prompt.result = "Redirect URI copied." }
        }
      }
      Column {
        width: (parent.width - parent.spacing) / 2
        spacing: Style.space(8)
        Text {
          width: parent.width
          text: "2 · Paste the Client ID"
          color: prompt.foreground
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Text {
          width: parent.width
          text: "In your app's Settings, copy its Client ID. Enter only that ID here; keep the Client Secret private. OmaSpotify uses PKCE and needs no secret. Leave the field empty to use the shared app."
          color: prompt.muted
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        TextField {
          objectName: "clientIdField"
          width: parent.width
          foreground: prompt.foreground
          placeholderText: "32-character Client ID · optional"
          text: prompt.clientId
          onTextEdited: { prompt.clientId = text; prompt.result = "" }
        }
        Text {
          width: parent.width
          text: prompt.valid ? "Changing apps requires authorization for the selected app."
            : "Enter exactly 32 hexadecimal characters, or leave empty."
          color: prompt.valid ? prompt.muted : Color.urgent
          font.family: prompt.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Row {
          spacing: Style.space(8)
          Button {
            objectName: "saveClientId"
            text: "Save app"
            foreground: prompt.foreground
            enabled: prompt.service && prompt.valid
            onClicked: prompt.saveClient()
          }
          Button {
            objectName: "authorizeClient"
            text: prompt.service && prompt.service.auth.loginBusy ? "Authorizing…" : "Authorize"
            foreground: prompt.foreground
            enabled: prompt.service && !prompt.service.auth.loggedIn
              && !prompt.service.auth.loginBusy && !prompt.service.auth.refreshBusy
              && !prompt.service.auth.switchingIdentity && prompt.service.auth.validClientId
              && prompt.clientId.trim().toLowerCase() === String(prompt.service.settings.clientId || "")
            onClicked: prompt.service.auth.beginLogin()
          }
        }
      }
    }
    Text {
      objectName: "setupStatus"
      width: parent.width
      text: prompt.service && prompt.service.auth.lastError ? prompt.service.auth.lastError
        : (prompt.service && prompt.service.auth.loginBusy ? "Finish authorization on Spotify's page."
          : (prompt.result ? prompt.result + " " : "") + prompt.connection)
      color: prompt.service && prompt.service.auth.lastError ? Color.urgent : prompt.accent
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      // Reserve a status row so actions do not jump when their result arrives.
      height: Math.max(Style.space(36), implicitHeight)
    }
    Button {
      objectName: "dismissSetup"
      text: prompt.service && prompt.service.usingPersonalClientId ? "Done" : "Continue with shared app"
      foreground: prompt.foreground
      onClicked: prompt.dismissed()
    }
  }
}
