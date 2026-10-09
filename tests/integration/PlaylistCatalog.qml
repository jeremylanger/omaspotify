import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Api.js" as Api

// Real Service/transport queues and observable HTTP requests; only auth and
// the network are fake. Personal quota exhaustion must not block a foreign
// playlist which the already-authorized catalog app can read.
ShellRoot {
  id: test
  Plugin.Service { id: service }
  property var requests: []
  property int phase: 0
  property var sharedIdentity: ({ loggedIn: true,
    withAccessToken: function(cb) { cb("catalog-token", "") },
    invalidateAccessToken: function() {} })
  function expect(ok, message) { if (!ok) throw new Error(message) }
  function wire(app) {
    return function() {
      var xhr = { readyState: 0, status: 0, responseText: "", url: "", app: app,
        headers: {}, aborted: false, method: "", retryAfter: "63000",
        open: function(method, url) { this.method = method; this.url = url },
        send: function() {}, abort: function() { this.aborted = true },
        setRequestHeader: function(k, v) { this.headers[k] = v },
        getResponseHeader: function(name) {
          return String(name).toLowerCase() === "retry-after" ? this.retryAfter : null } }
      requests.push(xhr)
      return xhr
    }
  }
  function complete(xhr, status, data, retryAfter) {
    if (retryAfter !== undefined) xhr.retryAfter = retryAfter
    xhr.status = status
    xhr.responseText = JSON.stringify(data)
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }
  function last() { return requests[requests.length - 1] }
  function expectXhr(xhr, app, path) {
    expect(!!xhr && xhr.app === app && xhr.url.indexOf(path) >= 0,
      "Wrong app for " + path + ": " + (xhr ? xhr.app + " " + xhr.url : "no request"))
    expect(xhr.headers.Authorization === "Bearer " + (app === "catalog" ? "catalog-token" : "personal-token"),
      "Wrong authorization identity")
    return xhr
  }
  function expectApp(app, path) { return expectXhr(last(), app, path) }
  function sentSince(count, path) {
    return requests.slice(count).filter(function(xhr) { return xhr.url.indexOf(path) >= 0 })
  }
  // Background pacing is time based; let a queued check go now.
  function pumpCatalog() {
    var catalog = service.api.fallbackTransport
    catalog.lastBackgroundStartedAt = 0
    catalog.lastInteractiveStartedAt = 0
    catalog.pumpRequests()
  }
  function row(id) {
    return { track: { id: id, name: id, uri: "spotify:track:" + id, artists: [] } }
  }
  Timer {
    interval: 30
    repeat: true
    running: true
    onTriggered: {
      if (phase++ === 0) {
        service.settings = { clientId: "11111111111111111111111111111111" }
        service.api.cancelAll()
        service.api.auth = { loggedIn: true,
          withAccessToken: function(cb) { cb("personal-token", "") },
          invalidateAccessToken: function() {} }
        service.api.fallbackAuth = sharedIdentity
        service.api.xhrFactory = wire("personal")
        service.currentUserId = "me"
        service.playlists = [
          { type: "playlist", id: "foreign", ownerId: "other", snapshotId: "v1" },
          { type: "playlist", id: "own", ownerId: "me" },
          { type: "playlist", id: "collab", ownerId: "other", collaborative: true },
          { type: "playlist", id: "unknown" },
          { type: "playlist", id: "foreign-stale", ownerId: "other", snapshotId: "s1" } ]
        return
      }
      stop()
      expect(!!service.api.fallbackTransport, "Catalog transport missing")
      service.api.fallbackTransport.xhrFactory = wire("catalog")
      service.api.fallbackTransport.lastBackgroundStartedAt = 0
      service.api.fallbackTransport.lastInteractiveStartedAt = 0
      // A followed foreign playlist kept from an earlier visit, now stale.
      var staleKey = Api.queryCacheKey(["playlist", "foreign-stale"])
      var stored = { version: Api.QUERY_CACHE_VERSION, order: [staleKey], entries: {} }
      stored.entries[staleKey] = { updatedAt: Date.now() - 600000, data: {
        item: { type: "playlist", id: "foreign-stale", ownerId: "other", snapshotId: "s1" },
        items: [{ id: "kept", uri: "spotify:track:kept", playlistPosition: 0 }], next: "" } }
      service.queryCacheReady = false
      service.applyQueryCacheFile(JSON.stringify(stored))
      service.openPlaylist(service.playlists[0])
      expectApp("catalog", "/playlists/foreign/items")
      expect(requests.length === 1, "Foreign playlist spent personal quota first")
      complete(last(), 200, { items: [row("first")], offset: 0,
        next: "https://api.spotify.com/v1/playlists/foreign/items?offset=1&limit=50" })
      expect(service.playlistItems.length === 1 && !service.playlistItemsError,
        "Catalog rows did not reach the playlist")
      service.loadMorePlaylistItems()
      expectApp("catalog", "offset=1")
      complete(last(), 200, { items: [row("second")], offset: 1, next: null })
      expect(service.playlistItems.length === 2, "Catalog continuation lost rows")
      service.keepPlaylistPage()
      var count = requests.length
      service.openPlaylist(service.playlists[0])
      expect(service.playlistItems.length === 2 && requests.length === count,
        "Reopening downloaded the cached songs again")
      var quota = { error: { status: 429, reason: "QUOTA_EXCEEDED", message: "Too many requests" } }
      service.openPlaylist(service.playlists[1])
      expectApp("personal", "/playlists/own/items")
      complete(last(), 429, quota)
      expect(service.playlistItemsEmptyMessage.indexOf("developer quota") >= 0,
        "Quota reason was replaced by generic retry advice")
      count = requests.length
      expect(!service.playlistItemsLoading && !service.pendingPlaybackBody,
        "Quota failure left loading or started playback")
      service.openPlaylist(service.playlists[2])
      expectApp("personal", "/playlists/collab/items")
      complete(last(), 200, { items: [], next: null })
      service.openPlaylist(service.playlists[3])
      expectApp("personal", "/playlists/unknown/items")
      complete(last(), 200, { items: [], next: null })
      service.currentUserId = ""
      service.openPlaylist({ type: "playlist", id: "no-profile", ownerId: "other" })
      expectApp("personal", "/playlists/no-profile/items")
      complete(last(), 200, { items: [], next: null })
      service.currentUserId = "me"
      sharedIdentity.loggedIn = false
      service.openPlaylist({ type: "playlist", id: "no-catalog-login", ownerId: "other" })
      expectApp("personal", "/playlists/no-catalog-login/items")
      complete(last(), 429, quota)
      expect(service.playlistItemsEmptyMessage.indexOf("developer quota") >= 0,
        "Unavailable catalog login hid the personal refusal")
      service.pageRequest("GET", "/me/playlists", null, function() {}, false)
      expectApp("personal", "/me/playlists")
      complete(last(), 429, quota)
      service.pageRequest("POST", "/playlists/foreign/items", null, function() {}, false)
      expectApp("personal", "/playlists/foreign/items")
      complete(last(), 200, {})
      sharedIdentity.loggedIn = true

      // A stale kept copy is drawn at once and only its version is checked.
      count = requests.length
      service.openPlaylist(service.playlists[4])
      expect(service.playlistItems.length === 1 && service.playlistItems[0].id === "kept",
        "Stale cached rows were not drawn immediately")
      pumpCatalog()
      var checks = sentSince(count, "/playlists/foreign-stale")
      expect(checks.length === 1 && requests.length === count + 1,
        "Stale reopen sent " + checks.length + " checks and " + (requests.length - count) + " requests")
      expectXhr(checks[0], "catalog", "fields=snapshot_id")
      complete(checks[0], 200, { snapshot_id: "s1" })
      expect(requests.length === count + 1 && service.playlistItems[0].id === "kept",
        "An unchanged version downloaded the songs again")

      // Detail pages: metadata and their continuation both use the catalog app,
      // and the continuation keeps its ordinary place behind a pause.
      count = requests.length
      service.openDetail({ kind: "context", type: "playlist", id: "foreign-detail",
        name: "Detail", ownerId: "other" })
      var metadata = sentSince(count, "/playlists/foreign-detail")
      expect(metadata.length === 1, "Detail metadata was not requested once")
      expectXhr(metadata[0], "catalog", "/playlists/foreign-detail")
      complete(metadata[0], 200, { id: "foreign-detail", type: "playlist",
        uri: "spotify:playlist:foreign-detail", name: "Detail", owner: { id: "other" },
        snapshot_id: "d1", items: { items: [row("d1")], offset: 0,
          next: "https://api.spotify.com/v1/playlists/foreign-detail/items?offset=1&limit=100" } })
      expect(service.detailItems.length === 1 && service.detailNext !== "",
        "Catalog metadata did not fill the detail page")
      var catalog = service.api.fallbackTransport
      catalog.rateLimitedUntil = Date.now() + 30000
      count = requests.length
      service.loadMoreDetail()
      expect(sentSince(count, "foreign-detail/items").length === 0,
        "Detail continuation skipped the catalog app's pause as an interactive request")
      catalog.rateLimitedUntil = 0
      catalog.pumpRequests()
      var more = sentSince(count, "foreign-detail/items?offset=1")
      expect(more.length === 1, "Detail continuation never left the catalog queue")
      expectXhr(more[0], "catalog", "offset=1")
      complete(more[0], 200, { items: [row("d2")], offset: 1, next: null })
      expect(service.detailItems.length === 2, "Catalog detail continuation lost rows")

      // Making a followed playlist your own reads it on the catalog app but
      // writes the copy and removes the original with the personal one.
      service.makePlaylistYourOwn({ type: "playlist", id: "foreign-copy",
        uri: "spotify:playlist:foreign-copy", name: "Copy me", ownerId: "other", total: 2 })
      expectApp("catalog", "/playlists/foreign-copy/items")
      complete(last(), 200, { items: [row("c1")], offset: 0,
        next: "https://api.spotify.com/v1/playlists/foreign-copy/items?offset=1&limit=50" })
      expectApp("catalog", "foreign-copy/items?offset=1")
      complete(last(), 200, { items: [row("c2")], offset: 1, next: null })
      expectApp("personal", "/me/playlists")
      expect(last().method === "POST", "Copy did not create the playlist")
      complete(last(), 201, { id: "mine", type: "playlist", uri: "spotify:playlist:mine",
        name: "Copy me", owner: { id: "me" } })
      expectApp("personal", "/playlists/mine/items")
      expect(last().method === "POST", "Copy did not add the songs")
      complete(last(), 201, { snapshot_id: "m1" })
      expectApp("personal", "/me/library")
      expect(last().method === "DELETE", "Copy did not remove the original")
      complete(last(), 200, {})
      expect(!service.playlistConversionBusy && !service.playlistActionBusy,
        "Copy did not finish")

      // Track radio probes a Spotify-owned candidate on the catalog app. A
      // candidate that does not start with the seed never starts playback.
      service.startRadio({ type: "track", id: "seed", uri: "spotify:track:seed",
        name: "Seed Song", artists: [] })
      expectApp("personal", "/search")
      complete(last(), 200, { playlists: { items: [{ id: "radio-mix", type: "playlist",
        uri: "spotify:playlist:radio-mix", name: "Seed Song Radio",
        owner: { id: "spotify", display_name: "Spotify" } }], next: null } })
      expectApp("catalog", "/playlists/radio-mix/items")
      complete(last(), 200, { items: [row("someone-else")], next: null })
      expectApp("personal", "/recommendations")
      complete(last(), 200, { tracks: [] })
      expect(!service.pendingPlaybackBody, "A rejected radio candidate started playback")

      // An ordinary catalog refusal keeps its own wait and stays on that app.
      count = requests.length
      service.openPlaylist({ type: "playlist", id: "foreign-busy", ownerId: "other" })
      expectApp("catalog", "/playlists/foreign-busy/items")
      complete(last(), 429, { error: { status: 429, message: "API rate limit exceeded" } }, "21")
      expect(requests.length === count + 1, "A catalog refusal fell back to the personal app")
      expect(service.playlistItemsEmptyMessage.indexOf("21 seconds") >= 0,
        "Caption lost the catalog Retry-After: " + service.playlistItemsEmptyMessage)
      catalog.rateLimitedUntil = 0
      catalog.interactiveLimitedUntil = 0
      catalog.restrictInFlight = false

      // Changing the Client ID cancels a catalog read already on the wire.
      service.auth.loggedIn = true
      service.openPlaylist({ type: "playlist", id: "foreign-switch", ownerId: "other" })
      var inFlight = expectApp("catalog", "/playlists/foreign-switch/items")
      count = requests.length
      service.applySettings({ clientId: "22222222222222222222222222222222" })
      expect(inFlight.aborted, "Changing the Client ID left the catalog read running")
      complete(inFlight, 200, { items: [row("late")], next: null })
      expect(!service.playlistItems.some(function(item) { return item.id === "late" }),
        "A cancelled catalog read applied late rows")
      expect(requests.length === count, "Changing the Client ID sent the read elsewhere")
      service.api.cancelAll()
      console.log("PLAYLIST_CATALOG_PASS")
      Qt.quit()
    }
  }
}
