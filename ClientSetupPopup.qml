import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

Popup {
  id: popup
  property var panel: null
  parent: popup.panel.windowContentItem
  width: Math.min(Style.space(840), popup.panel.windowWidth - Style.space(32))
  height: guide.implicitHeight + padding * 2
  x: Math.max(Style.space(8), (popup.panel.windowWidth - width) / 2)
  y: Math.max(Style.space(8), (popup.panel.windowHeight - height) / 2)
  padding: Style.space(16)
  modal: true
  focus: true
  onOpened: {
    guide.clientId = String(popup.panel.service.settings.clientId || "")
    guide.result = ""
    popup.panel.disarmEscapeClose()
  }
  onClosed: Qt.callLater(function() { popup.panel.restoreFocus() })
  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }
  contentItem: ClientSetupPrompt {
    id: guide
    service: popup.panel.service
    foreground: popup.panel.foreground
    muted: popup.panel.muted
    accent: popup.panel.accent
    fontFamily: popup.panel.fontFamily
    onDismissed: popup.close()
    onClientSaved: popup.panel.draftClientId = String(popup.panel.service.settings.clientId || "")
    onDashboardRequested: Qt.openUrlExternally("https://developer.spotify.com/dashboard")
    onCopyRequested: function(text) { Quickshell.execDetached(["wl-copy", text]) }
  }
}
