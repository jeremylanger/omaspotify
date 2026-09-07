import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

import "Api.js" as Api

Popup {
  id: popup

  property var panel: null

  parent: popup.panel.windowContentItem
  x: Math.max(Style.space(8), (popup.panel.windowWidth - width) / 2)
  y: Math.max(Style.space(8), (popup.panel.windowHeight - height) / 2)
  width: Math.min(Style.space(400), popup.panel.windowWidth - Style.space(32))
  height: lyricsInstallContent.implicitHeight + padding * 2
  padding: Style.space(10)
  modal: true
  focus: true
  closePolicy: popup.panel.service && popup.panel.service.lyricsPluginBusy
    ? Popup.NoAutoClose
    : Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: popup.panel.disarmEscapeClose()
  onClosed: {
    if (popup.panel.service && !popup.panel.service.lyricsPluginBusy)
      popup.panel.service.cancelLyricsPlugin(popup.panel.lyricsRequestKey)
    Qt.callLater(function() { popup.panel.restoreFocus() })
  }

  background: BorderSurface {
    color: popup.panel.popupBackground
    radius: Style.cornerRadius
    borderSpec: popup.panel.popupBorderSpec
  }

  contentItem: LyricsInstallPrompt {
    id: lyricsInstallContent
    width: parent.width
    service: popup.panel.service
    foreground: popup.panel.foreground
    muted: popup.panel.muted
    surfaceKey: popup.panel.lyricsRequestKey
    onCanceled: popup.close()
  }
}
