import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Api.js" as Api

ShellRoot {
  id: test
  Plugin.Service { id: service }
  Plugin.Panel { id: panel; service: service; width: 1024; height: 768 }
  property var requests: []
  property double clock: Date.now()
  property int songFileWrites: 0
  Connections {
    target: service.playlistCache
    function onChanged() { test.songFileWrites++ }
  }
  function expect(value, message) { if (!value) throw new Error(message) }
  // Spotify's mosaic playlist covers come in these three sizes.
  function mosaic(name) {
    return [640, 300, 60].map(function(size) {
      return { url: "https://i.scdn.co/image/" + name + "-" + size, width: size, height: size }
    })
  }
  function playlistRequests() { return requests.filter(function(x) { return x.url.indexOf("/playlists/warm") >= 0 }) }
  function last() { var rows = playlistRequests(); return rows[rows.length - 1] }
  function lastFor(id) {
    var rows = requests.filter(function(x) { return x.url.indexOf("/playlists/" + id) >= 0 })
    return rows[rows.length - 1]
  }
  function complete(status, payload, xhr) {
    xhr = xhr || last()
    xhr.status = status
    xhr.responseText = JSON.stringify(payload)
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }
  function step() {
    clock += 4000
    service.api.lastBackgroundStartedAt = 0
    service.api.lastInteractiveStartedAt = 0
    service.api.pumpRequests()
    service.playlistCache.tick()
  }
  Timer {
    id: finishTimer
    interval: 150
    onTriggered: {
      expect(panel.shortcutsBlocked, "cache popup owns keyboard focus")
      expect(panel.dismissTransientPopup(), "Escape can dismiss cache controls")
      console.log("PLAYLIST_WARMING_PASS")
      Qt.quit()
    }
  }
  Timer {
    interval: 100
    running: true
    onTriggered: {
      stop()
      service.api.cancelAll()
      service.api.auth = { loggedIn: true,
        withAccessToken: function(callback) { callback("test-token", "") },
        invalidateAccessToken: function() {} }
      service.api.fallbackAuth = null
      service.api.now = function() { return test.clock }
      service.api.xhrFactory = function() {
        var xhr = { readyState: 0, status: 0, responseText: "", url: "", aborted: false,
          onreadystatechange: null, open: function(method, url) { this.url = url },
          send: function() {}, setRequestHeader: function() {},
          abort: function() { this.aborted = true }, getResponseHeader: function() { return "300" } }
        test.requests.push(xhr)
        return xhr
      }
      service.auth.loggedIn = true
      service.currentUserId = "warming-account"
      service.playlistCache.diskReady = true
      service.playlistCache.clear()
      service.playlistCache.now = function() { return test.clock }
      service.playlists = [{ id: "warm", type: "playlist", kind: "context", name: "Fixture", snapshotId: "v1" }]
      service.applySettings({ cachePlaylistsOnIdle: "On" })
      expect(service.cachePlaylistsOnIdle, "real Settings enable warming")
      service.playlistCache.tick()
      expect(last().url.indexOf("/playlists/warm?") >= 0, "warm metadata sent")
      expect(decodeURIComponent(last().url).indexOf("fields=snapshot_id,images") >= 0,
        "the version check did not ask for the cover: " + last().url)
      complete(200, { snapshot_id: "v1", images: mosaic("cover") }); step()
      expect(last().url.indexOf("/playlists/warm/items") >= 0, "warm rows sent")
      var rows = []
      for (var i = 0; i < 50; i++) rows.push({ track: { id: "row" + i, name: "Track", uri: "spotify:track:row" + i, artists: [] } })
      complete(200, { items: rows, offset: 0, next: null }); step()
      complete(200, { snapshot_id: "v1", images: mosaic("cover") })
      expect(service.playlistCache.read("warm").item.imageUrl === "https://i.scdn.co/image/cover-300",
        "warming did not keep the 300 px cover")
      var count = playlistRequests().length
      service.setUiVisible("test", true)
      service.openPlaylist(service.playlists[0])
      expect(service.playlistItems.length === 50, "warmed songs draw immediately")
      expect(!service.playlistItemsLoading, "cache avoids loading screen")
      expect(playlistRequests().length === count, "fresh opening sends no Spotify read")
      service.openDetail(service.playlists[0])
      expect(service.detailItems.length === 50 && !service.detailLoading, "detail shares warmed rows")
      expect(service.detailItem.imageUrl === "https://i.scdn.co/image/cover-300",
        "a fresh warmed detail page drew a low-resolution cover: " + service.detailItem.imageUrl)
      expect(playlistRequests().length === count, "a fresh warmed detail page asked Spotify")
      // A stale copy stays readable, and unchanged metadata costs one request.
      clock += 301000
      service.api.cancelAll()
      service.openPlaylist(service.playlists[0]); step()
      expect(service.playlistItems.length === 50, "stale rows remain visible")
      var writes = songFileWrites
      complete(200, { snapshot_id: "v1" })
      expect(service.playlistItems.length === 50 && !service.playlistItemsLoading, "unchanged keeps songs")
      expect(songFileWrites === writes, "a confirmed version rewrote the whole song file")
      expect(service.playlistCache.freshness("warm") === "fresh", "a confirmed version stayed stale")
      // An unchanged version keeps the warmed songs, but the header takes the
      // playlist's own cover at the size the page draws it.
      clock += 301000
      service.openDetail(service.playlists[0]); step()
      writes = songFileWrites
      complete(200, { id: "warm", type: "playlist", name: "Fixture", snapshot_id: "v1",
        owner: { id: "warming-account" }, tracks: { total: 50 }, images: mosaic("cover") }, lastFor("warm"))
      expect(service.detailItem.imageUrl === "https://i.scdn.co/image/cover-300",
        "an unchanged warmed playlist kept a low-resolution cover: " + service.detailItem.imageUrl)
      expect(service.detailItem.snapshotId === "v1" && service.detailItems.length === 50
        && !service.detailLoading, "the confirmed detail page lost its warmed songs or version")
      expect(songFileWrites === writes, "a confirmed detail page rewrote the whole song file")
      // A new cover on the same version replaces the header and is kept with the songs.
      clock += 301000
      service.openDetail(service.playlists[0]); step()
      complete(200, { id: "warm", type: "playlist", name: "Fixture", snapshot_id: "v1",
        owner: { id: "warming-account" }, tracks: { total: 50 }, images: mosaic("new-cover") }, lastFor("warm"))
      expect(service.detailItem.imageUrl === "https://i.scdn.co/image/new-cover-300",
        "a changed cover did not refresh the header")
      expect(service.detailItem.snapshotId === "v1" && service.detailItems.length === 50
        && service.detailNext === "", "a changed cover lost the songs, version or cursor")
      expect(songFileWrites === writes + 1, "a changed cover was not saved")
      var asked = playlistRequests().length
      service.openDetail(service.playlists[0])
      expect(service.detailItem.imageUrl === "https://i.scdn.co/image/new-cover-300"
        && service.detailItems.length === 50 && playlistRequests().length === asked,
        "the saved cover was not drawn on a fresh open")
      // A newer version read on the Playlists page keeps the detail-size cover.
      service.playlists = service.playlists.map(function(row) {
        return service.playlistWithVersion(row, "warm", "v2")
      })
      service.openPlaylist(service.playlists[0]); step()
      expect(lastFor("warm").url.indexOf("fields=snapshot_id") >= 0, "the new version was not checked")
      complete(200, { snapshot_id: "v2" }, lastFor("warm")); step()
      expect(lastFor("warm").url.indexOf("/playlists/warm/items") >= 0, "the new version was not read")
      complete(200, { items: rows, offset: 0, next: null }, lastFor("warm"))
      service.keepPlaylistPage()
      expect(service.playlistCache.read("warm").item.snapshotId === "v2", "the new version was not kept")
      asked = playlistRequests().length
      service.openDetail(service.playlists[0])
      expect(service.detailItem.imageUrl === "https://i.scdn.co/image/new-cover-300"
        && service.detailItems.length === 50 && playlistRequests().length === asked,
        "a version saved from the Playlists page drew a list-size cover: " + service.detailItem.imageUrl)
      // A library file saved before the songs were, as after a restart, names an
      // older version. Spotify decides which is current: the songs stay.
      service.playlists = service.playlists.map(function(row) {
        return service.playlistWithVersion(row, "warm", "v1")
      })
      asked = playlistRequests().length
      service.openPlaylist(service.playlists[0]); step()
      expect(service.playlistItems.length === 50, "the saved songs were not drawn")
      expect(playlistRequests().length === asked + 1
        && lastFor("warm").url.indexOf("fields=snapshot_id") >= 0,
        "an older library version was trusted over the saved songs: " + lastFor("warm").url)
      complete(200, { snapshot_id: "v2" }, lastFor("warm")); step()
      expect(playlistRequests().length === asked + 1, "unchanged saved songs were downloaded again")
      expect(service.playlistItems.length === 50 && service.selectedPlaylist.snapshotId === "v2"
        && service.playlistCache.read("warm").item.snapshotId === "v2",
        "the saved songs lost the version Spotify confirmed")
      expect(service.playlistById("warm").snapshotId === "v2", "the library kept the older version")
      // A list first saved from the Playlists page uses the cover its listing gave.
      var listed = service.libraryMapper("playlist")({ id: "listed", type: "playlist", name: "Listed",
        uri: "spotify:playlist:listed", snapshot_id: "l1", owner: { id: "warming-account" },
        images: mosaic("listed") })
      expect(listed.imageUrl === "https://i.scdn.co/image/listed-60", "the listing fixture is not a mosaic")
      service.openPlaylist(listed); step()
      complete(200, { items: rows.slice(0, 5), offset: 0, next: null }, lastFor("listed"))
      service.keepPlaylistPage()
      var listedReads = function() {
        return requests.filter(function(x) { return x.url.indexOf("/playlists/listed") >= 0 }).length
      }
      asked = listedReads()
      service.openDetail(listed)
      expect(service.detailItem.imageUrl === "https://i.scdn.co/image/listed-300"
        && service.detailItems.length === 5 && listedReads() === asked,
        "a list saved from the Playlists page drew a list-size cover: " + service.detailItem.imageUrl)
      // Spotify hides the songs of a playlist you only follow: that is a message,
      // not an empty list to keep and show without it next time.
      var followed = { id: "followed", type: "playlist", kind: "context", name: "Followed",
        snapshotId: "f1", ownerId: "someone-else" }
      service.openDetail(followed); step()
      complete(200, { id: "followed", type: "playlist", name: "Followed", snapshot_id: "f1",
        owner: { id: "someone-else" } }, lastFor("followed"))
      expect(service.detailMessage === Api.playlistItemsHiddenMessage(), "hidden songs are explained")
      service.keepDetailPage()
      expect(!service.playlistCache.read("followed"), "hidden songs were cached as an empty list")
      asked = requests.length
      service.openDetail(followed); step()
      expect(requests.length === asked + 1 && service.detailLoading, "a hidden list was drawn from the cache")
      complete(200, { id: "followed", type: "playlist", name: "Followed", snapshot_id: "f1",
        owner: { id: "someone-else" } }, lastFor("followed"))
      expect(service.detailMessage === Api.playlistItemsHiddenMessage(), "reopening lost the explanation")
      // Off adds nothing from opened pages; songs already saved stay readable.
      service.applySettings({ cachePlaylistsOnIdle: "Off" })
      var other = { id: "other", type: "playlist", kind: "context", name: "Other",
        snapshotId: "o1", ownerId: "warming-account" }
      service.openPlaylist(other); step()
      complete(200, { items: rows.slice(0, 5), offset: 0, next: null }, lastFor("other"))
      expect(service.playlistItems.length === 5, "opened playlist loads while Off")
      service.keepPlaylistPage()
      expect(!service.playlistCache.read("other"), "Off still filled the library cache")
      service.openPlaylist(service.playlists[0])
      expect(service.playlistItems.length === 50, "Off stopped reading saved songs")
      expect(service.playlistCacheStatus.indexOf("Idle caching off") === 0, "Off status")
      service.applySettings({ cachePlaylistsOnIdle: "On" })
      service.setUiVisible("test", false)
      service.api.cancelAll()
      service.forgetCachedPlaylist(service.playlists[0])
      step()
      var pending = last()
      service.setUiVisible("test", true)
      expect(pending.aborted, "foreground opening aborts the warmer")
      // A version the warmer checked is one playlist, not a fresh library: the
      // panel still reads the whole library when it next opens.
      expect(service.libraryCacheReady, "the library file never loaded")
      var crawledAt = Date.now() - 7 * 3600000
      service.libraryCrawlIncomplete = false
      service.libraryCacheFetchedAt = crawledAt
      expect(!service.libraryCacheFresh, "a seven-hour-old library counted as fresh")
      service.setUiVisible("test", false)
      service.api.cancelAll()
      step()
      expect(lastFor("warm").url.indexOf("fields=snapshot_id") >= 0, "the warmer did not check the version")
      complete(200, { snapshot_id: "v3" }, lastFor("warm"))
      expect(service.playlistById("warm").snapshotId === "v3", "the checked version was not recorded")
      service.flushLibraryCache()
      expect(service.libraryCacheFetchedAt === crawledAt, "one checked playlist restamped the whole library")
      service.setUiVisible("test", true)
      service.auth.switchingIdentity = false
      service.auth.accessToken = "fixture-token"
      service.auth.accessTokenExpiresAt = Date.now() + 3600000
      service.activate("queue")
      expect(service.savedAlbumsLoading && service.followedArtistsLoading && service.savedShowsLoading,
        "opening the panel skipped a library refresh it needed")
      service.api.cancelAll()
      panel.opened = true
      Qt.callLater(function() { panel.openPlaylistCache(); finishTimer.start() })
    }
  }
}
