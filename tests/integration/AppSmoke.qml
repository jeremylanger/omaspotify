import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Api.js" as Api

ShellRoot {
  Plugin.Service { id: spotifyService }
  Plugin.Panel { id: panel; service: spotifyService; width: 1280; height: 800 }
  Plugin.BarWidget { id: widget }
  Plugin.MediaCollection {
    id: playlistView
    service: spotifyService
    sourceItems: spotifyService.playlistItems
    loading: spotifyService.playlistItemsLoading
    hasMore: spotifyService.playlistItemsNext !== ""
    onLoadMoreRequested: spotifyService.loadMorePlaylistItems()
  }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      spotifyService.applySettings({ deviceName: "Desk" })
      spotifyService.applySettings({})
      if (spotifyService.deviceName !== "Desk")
        throw new Error("A blank settings push reset saved settings")
      spotifyService.libraryCacheReady = false
      spotifyService.applyLibraryCacheFile(JSON.stringify({ version: 1, playlists: [
        { id: "r", uri: "spotify:playlist:r", ownerId: "spotify" },
        { id: "m", uri: "spotify:playlist:m", ownerId: "jeremy" }] }))
      if (spotifyService.spotifyPlaylists.length !== 1)
        throw new Error("Spotify's playlists from last time were not kept aside")
      spotifyService.playDays = ({ "2026-09-14": 3 })
      spotifyService.libraryCacheFetchedAt = Date.now()
      spotifyService.auth.loggedOut()
      if (!spotifyService.playDays["2026-09-14"])
        throw new Error("A changed client id erased the listening record")
      if (spotifyService.libraryCacheFresh)
        throw new Error("A changed client id kept an emptied library as fresh")
      if (spotifyService.spotifyPlaylists.length)
        throw new Error("The next account would inherit Spotify's playlists")
      spotifyService.libraryCacheReady = true
      spotifyService.forgetPersonalRecord()
      if (spotifyService.libraryCacheFresh)
        throw new Error("An emptied library was kept as fresh")
      spotifyService.auth.customClientId = "invalid"
      spotifyService.search("smoke-test", "track")
      if (spotifyService.searchLoading || !spotifyService.searchError)
        throw new Error("Search service did not return the authorization error")
      if (!panel.primaryNavigationItems().some(function(item) { return item.id === "search" }))
        throw new Error("Search navigation is missing")
      spotifyService.clearSearch()
      if (spotifyService.searchQuery !== "") throw new Error("Search state did not clear")
      spotifyService.api.cancelAll()
      spotifyService.api.rateLimitedUntil = Date.now() + 60000
      var cachedRefresh = spotifyService.pageRequest("GET", "/me/albums", null,
        function() {}, true)
      if (!cachedRefresh.job || cachedRefresh.job.priority !== "revalidate")
        throw new Error("A cached page bypassed background pacing")
      spotifyService.api.cancelAll()
      spotifyService.api.rateLimitedUntil = 0
      spotifyService.api.backgroundSuspendedUntil = Date.now() + 60000
      var cachedKey = Api.queryCacheKey(["playlist", "cached-list"])
      var stored = { version: Api.QUERY_CACHE_VERSION, order: [cachedKey], entries: {} }
      stored.entries[cachedKey] = { updatedAt: Date.now() - 600000, data: {
        item: { id: "cached-list" },
        items: [{ id: "cached-row", uri: "spotify:track:cached-row" }],
        next: "https://api.spotify.com/v1/playlists/cached-list/items?offset=50&limit=50" } }
      spotifyService.queryCacheReady = false
      spotifyService.applyQueryCacheFile(JSON.stringify(stored))
      var crawlPages = []
      for (var page = 1; page <= 3; page++)
        crawlPages.push(spotifyService.api.request("GET", "/me/albums",
          { offset: page * 50 }, null, function() {}, { priority: "background" }))
      spotifyService.openPlaylist({ id: "cached-list" })
      var check = spotifyService.api.requestQueue[0]
      if (!check || check.priority !== "revalidate" || !check.deadlineAt)
        throw new Error("A cached playlist check waited behind the library crawl")
      for (page = 0; page < crawlPages.length; page++)
        spotifyService.api.abortRequest(crawlPages[page])
      if (playlistView.loading || !playlistView.hasMore)
        throw new Error("A cached playlist check disabled Load More")
      playlistView.requestMore()
      if (spotifyService.api.requestQueue.length || playlistView.loading)
        throw new Error("Load More waited behind a paused cached check")
      if (!spotifyService.lastError)
        throw new Error("A failed Load More was not reported")
      if (spotifyService.playlistItems.length !== 1
          || spotifyService.playlistItems[0].id !== "cached-row")
        throw new Error("Load More dropped the cached rows")
      var realAuth = spotifyService.api.auth
      spotifyService.api.auth = { loggedIn: true,
        withAccessToken: function() {}, invalidateAccessToken: function() {} }
      spotifyService.openPlaylist({ id: "uncached-a" })
      if (!playlistView.loading) throw new Error("An uncached playlist did not show Loading")
      spotifyService.openPlaylist({ id: "uncached-b" })
      if (spotifyService.api.timedJobs.length !== 1)
        throw new Error("Switching playlists left the previous request running")
      spotifyService.api.expireTimedOutRequests(Date.now() + Api.API_FOREGROUND_TIMEOUT_MS + 1000)
      if (playlistView.loading || spotifyService.selectedPlaylist.id !== "uncached-b")
        throw new Error("A timed-out playlist kept Loading")
      if (spotifyService.playlistItemsError.indexOf("Try again") < 0)
        throw new Error("A timed-out playlist gave no retry message")
      spotifyService.ensurePlaylistItemCount(100)
      if (playlistView.loading || spotifyService.api.timedJobs.length)
        throw new Error("Restoring the scroll depth reloaded a failed playlist")
      var realXhrFactory = spotifyService.api.xhrFactory
      var refused = null
      spotifyService.api.auth = { loggedIn: true,
        withAccessToken: function(callback) { callback("smoke-token", "") },
        invalidateAccessToken: function() {} }
      spotifyService.api.xhrFactory = function() {
        refused = { readyState: 0, status: 0, responseText: "",
          onreadystatechange: null, open: function() {}, send: function() {},
          setRequestHeader: function() {}, abort: function() {},
          getResponseHeader: function(name) {
            return String(name).toLowerCase() === "retry-after" ? "30" : "" } }
        return refused
      }
      spotifyService.openPlaylist({ id: "uncached-c" })
      if (!playlistView.loading || !refused)
        throw new Error("An uncached playlist was not requested")
      refused.status = 429
      refused.responseText = "{}"
      refused.readyState = XMLHttpRequest.DONE
      refused.onreadystatechange()
      if (playlistView.loading || spotifyService.playlistItemsStatus !== 429
          || spotifyService.playlistItemsError.indexOf("Spotify is busy") < 0)
        throw new Error("A long refusal kept the playlist Loading")
      spotifyService.api.xhrFactory = realXhrFactory
      spotifyService.api.auth = realAuth
      spotifyService.api.rateLimitedUntil = 0
      spotifyService.api.interactiveLimitedUntil = 0
      spotifyService.api.restrictInFlight = false
      spotifyService.api.backgroundRefusals = 0
      spotifyService.api.backgroundSuspendedUntil = 0
      spotifyService.api.lastBackgroundStartedAt = 0
      spotifyService.api.lastInteractiveStartedAt = 0
      spotifyService.lastError = ""
      spotifyService.savedAlbums = [{ id: "cached-album" }]
      spotifyService.fillSidebarCollection("albums")
      if (spotifyService.savedAlbumsLoading || spotifyService.lastError)
        throw new Error("A failed optional refresh hid the visible action status")
      if (spotifyService.savedAlbums.length !== 1
          || spotifyService.savedAlbums[0].id !== "cached-album")
        throw new Error("A failed crawl replaced cached data")
      if (!spotifyService.libraryCrawlIncomplete)
        throw new Error("A failed crawl was treated as complete")
      spotifyService.libraryCrawlIncomplete = false
      spotifyService.api.lastBackgroundStartedAt = 0
      spotifyService.savedAlbums = [{ id: "first-page" }]
      spotifyService.savedAlbumsNext = "https://api.spotify.com/v1/me/albums?offset=50&limit=50"
      spotifyService.requestCollectionOffsets("albums",
        spotifyService.libraryCollectionSpec("albums"), [50], 0,
        [{ id: "cached-album" }, { id: "cached-second" }])
      offsetCrawlCheck.start()
    }
  }
  Timer {
    id: offsetCrawlCheck
    interval: 100
    repeat: true
    property int ticks: 0
    onTriggered: {
      if (!spotifyService.libraryCrawlIncomplete) {
        if (++ticks > 80) throw new Error("A failing offset crawl never gave up")
        return
      }
      stop()
      if (spotifyService.api.timedJobs.length || spotifyService.lastError)
        throw new Error("A failed offset crawl left work queued or replaced the action status")
      var ids = spotifyService.savedAlbums.map(function(item) { return item.id })
      if (ids.join(",") !== "first-page,cached-album,cached-second")
        throw new Error("A failed offset crawl dropped cached rows: " + ids.join(","))
      if (!spotifyService.savedAlbumsNext)
        throw new Error("A failed offset crawl was marked complete")
      spotifyService.libraryCrawlIncomplete = false
      spotifyService.requestCollectionOffsets("playlists",
        spotifyService.libraryCollectionSpec("playlists"), [], 0, [])
      freshnessCheck.start()
    }
  }
  Timer {
    id: freshnessCheck
    interval: 100
    repeat: true
    property int ticks: 0
    property bool failed: false
    onTriggered: {
      if (++ticks > 60) throw new Error("The library cache never settled")
      if (!failed) {
        if (!spotifyService.libraryCacheFresh) return
        spotifyService.api.lastBackgroundStartedAt = 0
        spotifyService.api.lastInteractiveStartedAt = 0
        spotifyService.followedArtists = [{ id: "cached-artist" }]
        spotifyService.fillSidebarCollection("artists")
        if (spotifyService.libraryCacheFresh)
          throw new Error("A late crawl failure left the library marked fresh")
        failed = true
        ticks = 0
        return
      }
      if (ticks < 15) return
      stop()
      if (spotifyService.libraryCacheFresh || spotifyService.libraryCacheFetchedAt !== 0)
        throw new Error("A late crawl failure was saved as fresh")
      if (spotifyService.followedArtists.length !== 1)
        throw new Error("A late crawl failure dropped cached artists")
      console.log("APP_SMOKE_PASS")
      Qt.quit()
    }
  }
}
