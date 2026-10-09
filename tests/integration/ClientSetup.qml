import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Plugin

ShellRoot {
  id: test
  property int saves: 0
  property int authorizations: 0
  property int focusRestores: 0
  QtObject {
    id: mockService
    property var settings: ({ clientId: "" })
    property bool usingPersonalClientId: settings.clientId !== ""
    property var auth: ({ redirectUri: "http://127.0.0.1:8989/login", lastError: "",
      loggedIn: false, loginBusy: false, refreshBusy: false, switchingIdentity: false,
      validClientId: true, beginLogin: function() { test.authorizations++ } })
    function persistSettings(values) { settings = values; test.saves++ }
  }
  QtObject {
    id: fakePanel
    property var service: mockService
    property var windowContentItem: screen
    property real windowWidth: screen.width
    property real windowHeight: screen.height
    property color foreground: "#f0eef5"
    property color muted: "#a8a3b5"
    property color accent: "#c7a6ff"
    property color popupBackground: "#211d2b"
    property var popupBorderSpec: Border.flat("#5c5470", 1)
    property string fontFamily: Style.font.family
    property string draftClientId: ""
    property string draftDeviceName: "Unsaved desk name"
    function disarmEscapeClose() {}
    function restoreFocus() { test.focusRestores++ }
  }
  FloatingWindow {
    id: window
    implicitWidth: 1280
    implicitHeight: 800
    visible: true
    color: "#17141f"
    // Offscreen windows keep their first size, so the panel area is resized instead.
    Item {
      id: screen
      width: 1024
      height: 768
    }
    Plugin.ClientSetupPopup {
      id: popup
      panel: fakePanel
    }
  }
  function find(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var result = find(item.children[i], name)
      if (result) return result
    }
    return null
  }
  function expect(value, message) { if (!value) throw new Error(message) }
  function status() { return find(popup.contentItem, "setupStatus").text }
  function expectFits() {
    expect(popup.x >= 0 && popup.y >= 0, "Setup starts off screen")
    expect(popup.x + popup.width <= screen.width
      && popup.y + popup.height <= screen.height, "Setup does not fit without scrolling")
    var dismiss = find(popup.contentItem, "dismissSetup")
    var bottom = dismiss.mapToItem(screen, 0, dismiss.height).y
    expect(bottom <= screen.height, "Dismiss control is unavailable")
    var line = find(popup.contentItem, "setupStatus")
    expect(line.mapToItem(screen, 0, line.height).y <= screen.height,
      "Action result is cut off")
  }
  property int phase: 0
  Timer {
    id: timer
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      var guide = popup.contentItem
      if (phase === 0) {
        popup.open()
      } else if (phase === 1) {
        expect(popup.opened, "Setup popup did not open")
        expect(status() === "Selected Spotify app is not connected yet.",
          "Opening did not show the live connection state")
        guide.clientId = "invalid"
        expect(!guide.saveClient() && test.saves === 0, "Invalid ID was saved")
        expect(!find(guide, "saveClientId").enabled, "Invalid ID enabled Save")
        guide.clientId = "ABCDEF0123456789ABCDEF0123456789"
        find(guide, "saveClientId").clicked()
        expect(mockService.settings.clientId === "abcdef0123456789abcdef0123456789", "Valid ID was not normalized and persisted")
        expect(fakePanel.draftClientId === mockService.settings.clientId,
          "Settings would re-apply the old Client ID")
        expect(fakePanel.draftDeviceName === "Unsaved desk name", "Saving reset another Settings draft")
        expect(status().indexOf("Saved your Spotify app.") === 0
          && status().indexOf("not connected") > 0, "Save result lost the connection state")
        find(guide, "authorizeClient").clicked()
        expect(test.authorizations === 1, "Authorization was not requested")
        mockService.auth = Object.assign({}, mockService.auth, { loggedIn: true })
        find(guide, "copyRedirect").clicked()
        expect(status() === "Redirect URI copied. Selected Spotify app is connected.",
          "Copy result was hidden while authorized: " + status())
        expectFits()
        find(guide, "dismissSetup").clicked()
      } else if (phase === 2) {
        expect(!popup.opened, "Done did not close the setup")
        expect(test.focusRestores === 1, "Closing did not return focus to the panel")
        popup.open()
      } else if (phase === 3) {
        expect(popup.opened, "Setup did not reopen")
        expect(guide.clientId === mockService.settings.clientId, "Reopening lost the saved ID")
        expect(status() === "Selected Spotify app is connected.",
          "Reopening an authorized app showed no connection state: " + status())
        guide.clientId = ""
        find(guide, "saveClientId").clicked()
        expect(mockService.settings.clientId === "", "Shared app could not be selected")
        expect(fakePanel.draftClientId === "", "Settings kept the removed Client ID")
        mockService.auth = Object.assign({}, mockService.auth, { loggedIn: false,
          lastError: "Spotify could not authorize this app. Verify the exact Redirect URI and try again." })
        expect(status().indexOf("Verify the exact Redirect URI") >= 0, "Authorization error was hidden")
      } else {
        expectFits()
        stop()
        popup.contentItem.grabToImage(function(result) {
          result.saveToFile(screen.width === 1024 ? "/tmp/omaspotify-client-setup-1024.png"
            : "/tmp/omaspotify-client-setup-1280.png")
          if (screen.width === 1024) {
            screen.width = 1280
            screen.height = 800
            timer.start()
          } else {
            console.log("CLIENT_SETUP_PASS")
            Qt.quit()
          }
        })
        return
      }
      phase++
    }
  }
}
