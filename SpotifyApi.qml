import QtQuick

// Separate transports prevent the shipped app's quota from delaying a
// personal app. No second queue is created until a fallback identity exists.
SpotifyTransport {
  id: root
  fallbackTransport: sharedTransport.item
  // Without a personal Client ID the primary queue is the shipped app itself.
  appLabel: fallbackAuth !== null ? "personal" : "shared"
  onFallbackAuthChanged: cancelForwardedRequests()

  Loader {
    id: sharedTransport
    active: root.fallbackAuth !== null
    sourceComponent: Component {
      SpotifyTransport {
        auth: root.fallbackAuth
        appLabel: "catalog"
        now: root.now
        xhrFactory: root.xhrFactory
        activeTimeoutMs: root.activeTimeoutMs
        slowRequestMs: root.slowRequestMs
        pacingHome: root
        pacingPeer: root
      }
    }
  }
}
