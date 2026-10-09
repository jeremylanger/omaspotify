import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/Api.js" as Api

ShellRoot {
  id: test
  Plugin.Service { id: service }
  Plugin.Panel { id: panel; service: service; width: 1280; height: 800 }
  property var requests: []
  function complete(xhr, status, payload) {
    xhr.status = status
    xhr.responseText = JSON.stringify(payload)
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }
  function expect(value, message) { if (!value) throw new Error(message) }
  // Reopen the way the sidebar does, with the library's own copy.
  function library(id) {
    for (var i = 0; i < service.playlists.length; i++)
      if (service.playlists[i].id === id) return service.playlists[i]
    return null
  }
  function pump() {
    service.api.lastBackgroundStartedAt = 0
    service.api.lastInteractiveStartedAt = 0
    service.api.pumpRequests()
  }
  function last() { return requests[requests.length - 1] }
  function rows(id) {
    return { items: [{ track: { id: id, name: id, uri: "spotify:track:" + id,
      artists: [] } }], next: null }
  }
  function page(id, offset, count, next) {
    var items = []
    for (var i = 0; i < count; i++)
      items.push({ track: { id: id, name: id, uri: "spotify:track:" + id, artists: [] } })
    return { items: items, offset: offset, next: next || null }
  }
  function distinctRows(prefix, count) {
    var items = []
    for (var i = 0; i < count; i++)
      items.push({ id: prefix + "-" + i, uri: "spotify:track:" + prefix + "-" + i,
        playlistPosition: i })
    return items
  }
  function keptRows(id, count) {
    var items = []
    for (var i = 0; i < count; i++)
      items.push({ id: id, uri: "spotify:track:" + id, playlistPosition: i })
    return items
  }
  function requestsFor(id) {
    return requests.filter(function(xhr) { return xhr.url.indexOf("/playlists/" + id) >= 0 })
  }
  Timer {
    interval: 20
    running: true
    onTriggered: {
      stop()
      service.api.cancelAll()
      service.api.auth = { loggedIn: true,
        withAccessToken: function(callback) { callback("test-token", "") },
        invalidateAccessToken: function() {} }
      service.api.fallbackAuth = null
      service.api.xhrFactory = function() {
        var xhr = { readyState: 0, status: 0, responseText: "", url: "", aborted: false,
          onreadystatechange: null,
          method: "", body: "",
          open: function(method, url) { this.method = method; this.url = url },
          send: function(body) { this.body = body || "" }, setRequestHeader: function() {},
          abort: function() { this.aborted = true },
          getResponseHeader: function() { return "30" } }
        test.requests.push(xhr)
        return xhr
      }
      var names = ["unchanged", "changed", "unknown", "failed", "deep", "large", "edited",
        "reordered", "rolledback", "removed", "added", "grown"]
      var editable = ["edited", "reordered", "rolledback", "removed", "added", "grown"]
      var cache = { version: Api.QUERY_CACHE_VERSION, order: [], entries: {} }
      var entries = []
      for (var i = 0; i < names.length; i++) {
        var key = Api.queryCacheKey(["playlist", names[i]])
        cache.order.push(key)
        var data = {
          item: { type: "playlist", id: names[i], snapshotId: "v1" },
          items: [{ id: "old-" + names[i], uri: "spotify:track:old-" + names[i] }], next: "" }
        if (names[i] === "deep") {
          data.items = keptRows("old-deep", 100)
          data.next = "https://api.spotify.com/v1/playlists/deep/items?offset=100&limit=50"
        } else if (names[i] === "large") {
          // What a capped playlist page leaves on disk.
          data = Api.cappedPageSnapshot({ item: data.item,
            items: keptRows("repeat", 250), next: "" }, 200)
        }
        else if (names[i] === "edited") data.items = keptRows("old-edited", 3)
        else if (editable.indexOf(names[i]) >= 0) data.items = distinctRows(names[i], 3)
        cache.entries[key] = { updatedAt: Date.now() - 600000, data: data }
        entries.push({ type: "playlist", id: names[i], name: names[i],
          uri: "spotify:playlist:" + names[i], snapshotId: "v1",
          collaborative: editable.indexOf(names[i]) >= 0 })
      }
      var racedKey = Api.queryCacheKey(["detail", "playlist", "detail-raced", ""])
      cache.order.push(racedKey)
      cache.entries[racedKey] = { updatedAt: Date.now() - 600000, data: {
        item: { kind: "context", type: "playlist", id: "detail-raced", name: "detail-raced",
          uri: "spotify:playlist:detail-raced", snapshotId: "v1", collaborative: true },
        items: distinctRows("detail-raced", 3), next: "" } }
      var detailKey = Api.queryCacheKey(["detail", "playlist", "detailed", ""])
      cache.order.push(detailKey)
      cache.entries[detailKey] = { updatedAt: Date.now(), data: Api.cappedPageSnapshot({
        item: { kind: "context", type: "playlist", id: "detailed", name: "detailed",
          uri: "spotify:playlist:detailed", snapshotId: "v1" },
        items: keptRows("detail-row", 250), next: "" }, 200) }
      service.playlists = entries
      service.queryCacheReady = false
      service.applyQueryCacheFile(JSON.stringify(cache))

      // Unchanged: one metadata check, no track download, then fresh.
      service.openPlaylist(library("unchanged"))
      expect(service.playlistItems[0].id === "old-unchanged", "Cache was not drawn immediately")
      expect(!service.playlistItemsLoading, "Version check blocked cached rows")
      expect(requests.length === 1 && requests[0].url.indexOf("fields=snapshot_id") >= 0,
        "Stale cache did not use the metadata endpoint")
      complete(requests[0], 200, { snapshot_id: "v1" })
      service.openPlaylist(library("unchanged"))
      pump()
      expect(requests.length === 1, "Unchanged version downloaded tracks again")

      // Changed: the new version reaches the library copy, so the sidebar
      // reopen trusts the rows it just fetched.
      service.openPlaylist(library("changed"))
      pump()
      expect(requests.length === 2 && last().url.indexOf("fields=snapshot_id") >= 0,
        "Changed playlist was not checked")
      complete(last(), 200, { snapshot_id: "v2" })
      pump()
      expect(requests.length === 3 && last().url.indexOf("/items") >= 0,
        "A changed version kept the old rows")
      complete(last(), 200, rows("new-changed"))
      expect(service.playlistItems[0].id === "new-changed", "Changed rows were not replaced")
      expect(library("changed").snapshotId === "v2", "The library kept the old version")
      expect(library("unchanged").snapshotId === "v1", "Another playlist's version changed")
      service.keepPlaylistPage()
      service.openPlaylist(library("changed"))
      pump()
      expect(requests.length === 3, "Reopening from the sidebar downloaded tracks again")
      expect(service.playlistItems[0].id === "new-changed", "Reopening lost the new rows")

      // A different library version is checked even against a fresh cache:
      // the library may be the older of the two.
      service.playlists = service.playlists.map(function(item) {
        if (item.id !== "unchanged") return item
        var copy = Object.assign({}, item)
        copy.snapshotId = "v3"
        return copy
      })
      service.openPlaylist(library("unchanged"))
      pump()
      expect(requests.length === 4 && last().url.indexOf("fields=snapshot_id") >= 0,
        "A known changed version was treated as fresh")
      expect(service.selectedPlaylist.snapshotId === "v1",
        "Cached rows were labelled with a version they do not show")
      complete(last(), 200, { snapshot_id: "v3" })
      pump()
      expect(requests.length === 5 && last().url.indexOf("/items") >= 0,
        "A confirmed newer version kept the old rows")
      expect(service.selectedPlaylist.snapshotId === "v1",
        "The new version was published before its rows arrived")
      complete(last(), 200, rows("new-unchanged"))
      expect(service.selectedPlaylist.snapshotId === "v3", "Fetched rows kept the old label")

      // Unknown: no version in the reply means the rows are fetched.
      service.openPlaylist(library("unknown"))
      pump()
      complete(last(), 200, {})
      pump()
      expect(requests.length === 7 && last().url.indexOf("/items") >= 0,
        "An unknown version was trusted")
      expect(service.selectedPlaylist.snapshotId === "v1", "Kept rows lost their version early")
      complete(last(), 200, rows("new-unknown"))
      expect(service.selectedPlaylist.snapshotId === "", "Rows of an unknown version kept a label")
      expect(service.playlistItems[0].id === "new-unknown", "Unknown version rows were not replaced")
      expect(library("unknown").snapshotId === "v1", "An unknown version was written to the library")

      // Failed: the visible cache stays and is checked again next visit.
      service.openPlaylist(library("failed"))
      pump()
      complete(last(), 500, { error: { status: 500, message: "Server error" } })
      pump()
      expect(requests.length === 8, "A failed check downloaded tracks")
      expect(service.playlistItems[0].id === "old-failed", "A failed check dropped cached rows")
      expect(!service.playlistItemsLoading, "A failed check left Loading on")
      service.openPlaylist(library("failed"))
      pump()
      expect(requests.length === 9 && last().url.indexOf("fields=snapshot_id") >= 0,
        "A failed check was treated as fresh")

      // Changed while the panel restores a deeper position: the new version
      // is fetched from the top, not appended onto the old rows.
      panel.currentTab = "playlists"
      panel.restoredPlaylistId = "deep"
      panel.restoredPlaylistItemCount = 150
      service.openPlaylist(library("deep"), 150)
      pump()
      var deep = requestsFor("deep")
      expect(deep.length === 1 && deep[0].url.indexOf("fields=snapshot_id") >= 0,
        "Deep playlist was not checked")
      complete(deep[0], 200, { snapshot_id: "v2" })
      pump()
      deep = requestsFor("deep")
      expect(deep.length === 2 && deep[1].url.indexOf("offset=100") < 0
        && deep[1].url.indexOf("/items") >= 0, "The restore paged on from stale rows")
      expect(library("deep").snapshotId === "v1" && service.selectedPlaylist.snapshotId === "v1",
        "The new version was published before its rows arrived")
      complete(deep[1], 200, page("new-deep", 0, 50,
        "https://api.spotify.com/v1/playlists/deep/items?offset=50&limit=50"))
      expect(library("deep").snapshotId === "v2" && service.selectedPlaylist.snapshotId === "v2",
        "The fetched version was not published")
      pump()
      complete(requestsFor("deep")[2], 200, page("new-deep", 50, 50,
        "https://api.spotify.com/v1/playlists/deep/items?offset=100&limit=50"))
      pump()
      deep = requestsFor("deep")
      expect(deep.length === 4 && deep[3].url.indexOf("offset=100") >= 0,
        "The remembered depth was not restored")
      complete(deep[3], 200, page("new-deep", 100, 50))
      expect(service.playlistItems.length === 150, "The remembered depth was lost")
      expect(service.playlistItems.every(function(row) { return row.id === "new-deep" }),
        "Old and new versions were mixed")
      panel.restoredPlaylistId = ""
      panel.currentTab = "home"

      // Capped: a kept 200-row page still pages on from its last position.
      service.openPlaylist(library("large"))
      pump()
      var large = requestsFor("large")
      complete(large[0], 200, { snapshot_id: "v1" })
      expect(requestsFor("large").length === 1, "An unchanged capped playlist downloaded tracks")
      expect(service.playlistItems.length === 200, "The capped rows were not drawn")
      expect(service.playlistItemsNext.indexOf("offset=200") >= 0,
        "An unchanged capped playlist lost Load More")
      service.loadMorePlaylistItems()
      large = requestsFor("large")
      expect(large.length === 2 && large[1].url.indexOf("offset=200") >= 0,
        "Load More did not resume after the kept rows")
      complete(large[1], 200, page("repeat", 200, 50))
      expect(service.playlistItems.length === 250
        && service.playlistItems[249].playlistPosition === 249,
        "Load More misplaced the remaining rows")
      service.openPlaylist(library("large"), 250)
      pump()
      large = requestsFor("large")
      expect(large.length === 3 && large[2].url.indexOf("offset=200") >= 0,
        "A deeper remembered position was not restored from the capped cache")
      complete(large[2], 200, page("repeat", 200, 50))
      expect(service.playlistItems.length === 250, "The deeper position was not reached")


      // Changed, but the rows are slow to come: the old rows keep their own
      // version for an edit made meanwhile, and a failed or expired refetch
      // leaves them stale for the next visit.
      function reads(id) {
        return requestsFor(id).filter(function(xhr) { return xhr.method === "GET" })
      }
      service.openPlaylist(library("edited"))
      pump()
      complete(reads("edited")[0], 200, { snapshot_id: "v2" })
      pump()
      expect(reads("edited").length === 2, "The changed rows were not requested")
      service.requestPlaylistItemReorder(0, 2)
      var edits = requestsFor("edited").filter(function(xhr) { return xhr.method === "PUT" })
      expect(edits.length === 1 && JSON.parse(edits[0].body).snapshot_id === "v1",
        "An edit before the new rows arrived was sent against the wrong version")
      complete(reads("edited")[1], 500, { error: { status: 500, message: "Server error" } })
      expect(service.selectedPlaylist.snapshotId === "v1" && library("edited").snapshotId === "v1",
        "A failed refetch published a version it never showed")
      expect(service.playlistItems.length === 3 && service.playlistItems[0].id === "old-edited",
        "A failed refetch dropped the kept rows")
      service.openPlaylist(library("edited"))
      pump()
      expect(reads("edited").length === 3 && last().url.indexOf("fields=snapshot_id") >= 0,
        "A failed refetch left the cache trusted")
      complete(reads("edited")[2], 200, { snapshot_id: "v2" })
      pump()
      service.api.expireTimedOutRequests(Date.now() + Api.API_FOREGROUND_TIMEOUT_MS + 1000)
      expect(service.selectedPlaylist.snapshotId === "v1" && !service.playlistItemsLoading,
        "An expired refetch published its version")
      service.openPlaylist(library("edited"))
      pump()
      complete(reads("edited")[4], 200, { snapshot_id: "v2" })
      pump()
      complete(reads("edited")[5], 200, rows("new-edited"))
      expect(service.selectedPlaylist.snapshotId === "v2" && library("edited").snapshotId === "v2"
        && service.playlistItems[0].id === "new-edited", "The retried refetch was not kept")

      // A capped playlist detail page continues from its kept rows too.
      service.openDetail({ kind: "context", type: "playlist", id: "detailed",
        name: "detailed", uri: "spotify:playlist:detailed", snapshotId: "v1" })
      expect(service.detailItems.length === 200 && service.detailNext.indexOf("offset=200") >= 0,
        "The capped detail page lost its place")
      service.loadMoreDetail()
      pump()
      var detail = requestsFor("detailed")
      expect(detail.length === 1 && detail[0].url.indexOf("offset=200") >= 0,
        "Detail Load More did not resume after the kept rows")
      complete(detail[0], 200, page("detail-row", 200, 50,
        "https://api.spotify.com/v1/playlists/detailed/items?offset=250&limit=50"))
      expect(service.detailItems.length === 250
        && service.detailItems[249].playlistPosition === 249,
        "A later playlist detail page was not read")
      expect(service.detailNext.indexOf("offset=250") >= 0, "Detail paging stopped early")


      // An edit stops older reads of the same playlist, so a late check or
      // refetch cannot replace the edited rows or the version the edit
      // returned. The edit then reads again: from the top at the depth on
      // screen after success, or by resuming the check after a failure.
      function writes(id, method) {
        return requestsFor(id).filter(function(xhr) { return xhr.method === method })
      }
      function answerLibraryChecks() {
        requests.filter(function(xhr) {
          return xhr.url.indexOf("/me/library/contains") >= 0 && !xhr.aborted
            && xhr.readyState !== XMLHttpRequest.DONE
        }).forEach(function(xhr) { complete(xhr, 200, [false]) })
      }
      function ids() { return service.playlistItems.map(function(row) { return row.id }).join() }

      service.openPlaylist(library("reordered"), 120)
      pump()
      complete(reads("reordered")[0], 200, { snapshot_id: "v2" })
      pump()
      var refetch = reads("reordered")[1]
      service.requestPlaylistItemReorder(0, 2)
      expect(refetch.aborted, "A reorder left an older refetch running")
      var put = writes("reordered", "PUT")[0]
      expect(JSON.parse(put.body).snapshot_id === "v1", "The reorder used a version it does not show")
      complete(put, 200, { snapshot_id: "v3" })
      complete(refetch, 200, rows("new-reordered"))
      expect(service.playlistItems.length === 0 && service.playlistItemsLoading,
        "Rows from before an external change were kept under the edit's version")
      expect(service.selectedPlaylist.snapshotId === "v3" && library("reordered").snapshotId === "v3",
        "A late refetch replaced the version the edit returned")
      var after = reads("reordered")
      expect(after.length === 3 && after[2].url.indexOf("offset=") < 0,
        "The interrupted playlist was not read again from the top")
      complete(after[2], 200, page("post-edit", 0, 50,
        "https://api.spotify.com/v1/playlists/reordered/items?offset=50&limit=50"))
      pump()
      complete(reads("reordered")[3], 200, page("post-edit", 50, 50,
        "https://api.spotify.com/v1/playlists/reordered/items?offset=100&limit=50"))
      pump()
      after = reads("reordered")
      expect(after.length === 5 && after[4].url.indexOf("offset=100") >= 0,
        "The edit's reread lost the remembered depth")
      complete(after[4], 200, page("post-edit", 100, 20))
      expect(service.playlistItems.length === 120 && service.playlistItems[0].id === "post-edit",
        "The post-edit rows were not shown at the remembered depth")
      service.keepPlaylistPage()
      service.openPlaylist(library("reordered"))
      pump()
      expect(reads("reordered").length === 5 && service.playlistItems.length === 120
        && service.playlistItems[0].id === "post-edit",
        "The reopened cache did not hold the post-edit rows")

      service.openPlaylist(library("rolledback"))
      pump()
      var check = reads("rolledback")[0]
      service.requestPlaylistItemReorder(0, 1)
      expect(check.aborted, "A reorder left an older version check running")
      complete(writes("rolledback", "PUT")[0], 500, { error: { status: 500, message: "No" } })
      complete(check, 200, { snapshot_id: "v9" })
      expect(ids() === "rolledback-0,rolledback-1,rolledback-2", "A failed reorder was not rolled back")
      expect(service.selectedPlaylist.snapshotId === "v1", "A failed reorder changed the version")
      expect(service.lastError !== "", "A failed reorder was not reported")
      pump()
      var resumed = reads("rolledback")
      expect(resumed.length === 2 && resumed[1].url.indexOf("fields=snapshot_id") >= 0,
        "A failed reorder did not resume the version check")
      complete(resumed[1], 200, { snapshot_id: "v2" })
      pump()
      complete(reads("rolledback")[2], 200, rows("new-rolledback"))
      expect(ids() === "new-rolledback" && service.selectedPlaylist.snapshotId === "v2",
        "The resumed check did not bring the changed rows")

      service.openPlaylist(library("removed"))
      pump()
      check = reads("removed")[0]
      service.removePlaylistItem(service.playlistItems[0], 0)
      expect(check.aborted, "A removal left an older version check running")
      complete(writes("removed", "DELETE")[0], 200, { snapshot_id: "v3" })
      complete(check, 200, { snapshot_id: "v1" })
      expect(service.selectedPlaylist.snapshotId === "v3", "The removal's version was lost")
      expect(reads("removed").length === 2 && reads("removed")[1].url.indexOf("/items") >= 0
        && service.playlistItems.length === 0 && service.playlistItemsLoading,
        "The removal did not reload the playlist")
      complete(reads("removed")[1], 200, rows("after-removal"))
      expect(service.playlistItems[0].id === "after-removal", "The reloaded rows were not shown")
      service.keepPlaylistPage()
      service.openPlaylist(library("removed"))
      pump()
      expect(reads("removed").length === 2 && service.playlistItems[0].id === "after-removal",
        "The reopened cache did not hold the rows after the removal")

      service.openPlaylist(library("added"))
      pump()
      complete(reads("added")[0], 200, { snapshot_id: "v2" })
      pump()
      refetch = reads("added")[1]
      service.addItemToPlaylist({ type: "track", uri: "spotify:track:added-song" },
        service.selectedPlaylist)
      expect(refetch.aborted, "An add left an older refetch running")
      complete(writes("added", "POST")[0], 500, { error: { status: 500, message: "No" } })
      complete(refetch, 200, rows("late-added"))
      expect(ids() === "added-0,added-1,added-2" && service.selectedPlaylist.snapshotId === "v1",
        "A failed add lost the kept rows or their version")
      pump()
      complete(reads("added")[2], 200, { snapshot_id: "v2" })
      pump()
      complete(reads("added")[3], 200, rows("new-added"))
      expect(ids() === "new-added" && service.selectedPlaylist.snapshotId === "v2",
        "A failed add did not resume the changed version")

      service.openPlaylist(library("grown"))
      pump()
      check = reads("grown")[0]
      service.addItemToPlaylist({ type: "track", uri: "spotify:track:grown-song" },
        service.selectedPlaylist)
      expect(check.aborted, "An add left an older version check running")
      complete(writes("grown", "POST")[0], 201, { snapshot_id: "v3" })
      complete(check, 200, { snapshot_id: "v1" })
      expect(service.playlistItems.length === 0 && service.playlistItemsLoading
        && service.selectedPlaylist.snapshotId === "v3",
        "An add kept rows from before it under its version")
      complete(reads("grown")[1], 200, rows("with-song"))
      expect(ids() === "with-song", "The rows after the add were not shown")

      service.openDetail({ kind: "context", type: "playlist", id: "detail-raced",
        name: "detail-raced", uri: "spotify:playlist:detail-raced", snapshotId: "v1",
        collaborative: true })
      pump()
      answerLibraryChecks()
      var metadata = reads("detail-raced")[0]
      expect(service.detailRevalidating, "The stale detail page was not being checked")
      service.requestPlaylistItemReorder(0, 1, service.detailItem)
      expect(!service.detailRevalidating, "A detail reorder left an older detail read current")
      complete(writes("detail-raced", "PUT")[0], 200, { snapshot_id: "v3" })
      complete(metadata, 200, { type: "playlist", id: "detail-raced", name: "detail-raced",
        uri: "spotify:playlist:detail-raced", snapshot_id: "v2",
        items: { items: rows("late-detail").items, offset: 0, next: null } })
      expect(service.detailItems.length === 0 && service.detailLoading,
        "Detail rows from before an external change were kept under the edit's version")
      pump()
      answerLibraryChecks()
      var reread = reads("detail-raced")
      expect(reread.length === 2, "The interrupted detail page was not read again")
      complete(reread[1], 200, { type: "playlist", id: "detail-raced", name: "detail-raced",
        uri: "spotify:playlist:detail-raced", snapshot_id: "v3",
        items: { items: rows("post-detail").items, offset: 0, next: null } })
      expect(service.detailItems[0].id === "post-detail" && service.detailItem.snapshotId === "v3"
        && !service.detailLoading, "The detail page did not show the rows after the edit")

      // A failed edit with nothing in the cache, during a deeper restore:
      // the rows on screen stay and are checked again instead of blanked.
      service.playlists = service.playlists.concat([
        { type: "playlist", id: "unsaved", name: "unsaved", uri: "spotify:playlist:unsaved",
          snapshotId: "v1", collaborative: true },
        { type: "playlist", id: "unsaved-fail", name: "unsaved-fail",
          uri: "spotify:playlist:unsaved-fail", snapshotId: "v1", collaborative: true }])
      function failEditWithoutCache(id) {
        service.openPlaylist(library(id), 120)
        pump()
        complete(reads(id)[0], 200, page(id + "-row", 0, 50,
          "https://api.spotify.com/v1/playlists/" + id + "/items?offset=50&limit=50"))
        pump()
        var restoring = reads(id)[1]
        expect(restoring && restoring.url.indexOf("offset=50") >= 0,
          "The remembered depth was not being restored")
        var shown = ids()
        service.requestPlaylistItemReorder(0, 1)
        expect(restoring.aborted, "A reorder left the restore running")
        complete(writes(id, "PUT")[0], 409, { error: { status: 409, message: "Conflict" } })
        complete(restoring, 200, page("late-" + id, 50, 50))
        expect(ids() === shown && service.playlistItems.length === 50
          && !service.playlistItemsLoading,
          "A failed edit without a cache entry blanked the rows on screen")
        expect(service.selectedPlaylist.snapshotId === "v1", "A failed edit changed the version")
        pump()
        var check = reads(id)[2]
        expect(check && check.url.indexOf("fields=snapshot_id") >= 0,
          "A failed edit did not check the rows on screen again")
        return check
      }
      complete(failEditWithoutCache("unsaved"), 200, { snapshot_id: "v1" })
      pump()
      var resumedPage = reads("unsaved")[3]
      expect(resumedPage && resumedPage.url.indexOf("offset=50") >= 0,
        "The confirmed rows did not resume the remembered depth")
      complete(resumedPage, 200, page("unsaved-row", 50, 50,
        "https://api.spotify.com/v1/playlists/unsaved/items?offset=100&limit=50"))
      pump()
      complete(reads("unsaved")[4], 200, page("unsaved-row", 100, 20))
      expect(service.playlistItems.length === 120, "The remembered depth was not reached")
      service.keepPlaylistPage()
      service.openPlaylist(library("unsaved"))
      pump()
      expect(reads("unsaved").length === 6,
        "Rows kept only on screen were cached as fresh")

      complete(failEditWithoutCache("unsaved-fail"), 500,
        { error: { status: 500, message: "Server error" } })
      pump()
      expect(service.playlistItems.length === 50 && !service.playlistItemsLoading
        && reads("unsaved-fail").length === 3,
        "A failed check after a failed edit lost the rows on screen")
      service.openPlaylist(library("unsaved-fail"))
      pump()
      expect(service.playlistItems.length === 0 && service.playlistItemsLoading,
        "Rows kept only on screen were cached")

      // The same in a playlist detail page whose cache entry is gone.
      service.openDetail({ kind: "context", type: "playlist", id: "detail-unsaved",
        name: "detail-unsaved", uri: "spotify:playlist:detail-unsaved", snapshotId: "v1",
        collaborative: true }, "", 120)
      pump()
      answerLibraryChecks()
      complete(reads("detail-unsaved")[0], 200, { type: "playlist", id: "detail-unsaved",
        name: "detail-unsaved", uri: "spotify:playlist:detail-unsaved", snapshot_id: "v1",
        collaborative: true, items: page("detail-unsaved-row", 0, 50,
          "https://api.spotify.com/v1/playlists/detail-unsaved/items?offset=50&limit=50") })
      pump()
      answerLibraryChecks()
      var detailRestore = reads("detail-unsaved")[1]
      expect(detailRestore && detailRestore.url.indexOf("offset=50") >= 0 && service.detailLoading,
        "The detail depth was not being restored")
      service.requestPlaylistItemReorder(0, 1, service.detailItem)
      complete(writes("detail-unsaved", "PUT")[0], 500, { error: { status: 500, message: "No" } })
      complete(detailRestore, 200, page("late-detail-unsaved", 50, 50))
      expect(service.detailItems.length === 50 && service.detailItems[0].id === "detail-unsaved-row"
        && service.detailRevalidating && !service.detailLoading,
        "A failed edit without a detail cache entry blanked the detail rows")
      pump()
      answerLibraryChecks()
      var detailCheck = reads("detail-unsaved")[2]
      expect(detailCheck && detailCheck.url.indexOf("offset=") < 0,
        "A failed detail edit did not check the rows on screen again")
      complete(detailCheck, 200, { type: "playlist", id: "detail-unsaved",
        name: "detail-unsaved", uri: "spotify:playlist:detail-unsaved", snapshot_id: "v1",
        collaborative: true, items: page("detail-checked", 0, 50,
          "https://api.spotify.com/v1/playlists/detail-unsaved/items?offset=50&limit=50") })
      pump()
      answerLibraryChecks()
      var detailPages = reads("detail-unsaved")
      expect(detailPages.length === 4 && detailPages[3].url.indexOf("offset=50") >= 0,
        "The detail check did not resume the remembered depth")
      complete(detailPages[3], 200, page("detail-checked", 50, 50))
      expect(service.detailItems.length === 100 && service.detailItems[0].id === "detail-checked",
        "The checked detail rows were not shown at depth")

      // A successful add shows no rows from before it under its version while
      // its refresh is pending, so a later failed edit has nothing stale to keep.
      service.playlists = service.playlists.concat([
        { type: "playlist", id: "readded", name: "readded", uri: "spotify:playlist:readded",
          snapshotId: "v1", collaborative: true },
        { type: "playlist", id: "readded-fail", name: "readded-fail",
          uri: "spotify:playlist:readded-fail", snapshotId: "v1", collaborative: true }])
      function addThenFailEdit(id) {
        service.openPlaylist(library(id))
        pump()
        complete(reads(id)[0], 200, { items: distinctRows(id, 3).map(function(row) {
          return { track: { id: row.id, name: row.id, uri: row.uri, artists: [] } }
        }), offset: 0, next: null })
        expect(ids() === id + "-0," + id + "-1," + id + "-2" && service.playlistItemsNext === "",
          "The complete playlist was not shown")
        service.addItemToPlaylist({ type: "track", uri: "spotify:track:" + id + "-song" },
          service.selectedPlaylist)
        complete(writes(id, "POST")[0], 201, { snapshot_id: "v2" })
        expect(service.selectedPlaylist.snapshotId === "v2" && service.playlistItems.length === 0
          && service.playlistItemsLoading,
          "Rows from before the add were shown under its version")
        var refresh = reads(id)[1]
        expect(refresh && refresh.url.indexOf("offset=") < 0, "The add did not refresh the rows")
        service.requestPlaylistItemReorder(0, 1)
        expect(writes(id, "PUT").length === 0, "A reorder was offered without rows")
        service.addItemToPlaylist({ type: "track", uri: "spotify:track:" + id + "-second" },
          service.selectedPlaylist)
        complete(writes(id, "POST")[1], 409, { error: { status: 409, message: "Conflict" } })
        expect(!refresh.aborted && reads(id).length === 2 && service.playlistItems.length === 0,
          "A failed edit replaced the pending refresh with rows from before the add")
        return refresh
      }
      complete(addThenFailEdit("readded"), 200, { items: [
        { track: { id: "readded-song", name: "song", uri: "spotify:track:readded-song",
          artists: [] } }].concat(distinctRows("readded", 3).map(function(row) {
          return { track: { id: row.id, name: row.id, uri: row.uri, artists: [] } }
        })), offset: 0, next: null })
      expect(ids() === "readded-song,readded-0,readded-1,readded-2"
        && service.selectedPlaylist.snapshotId === "v2" && !service.playlistItemsLoading,
        "The refresh after the add was not shown")

      complete(addThenFailEdit("readded-fail"), 500,
        { error: { status: 500, message: "Server error" } })
      expect(service.playlistItems.length === 0 && !service.playlistItemsLoading
        && service.playlistItemsError !== "",
        "A failed refresh after the add brought back rows from before it")
      service.openPlaylist(library("readded-fail"))
      pump()
      expect(reads("readded-fail").length === 3 && reads("readded-fail")[2].url.indexOf("/items") >= 0
        && service.playlistItemsLoading, "Rows from before the add were trusted on reopening")

      // The detail page of the same kind is emptied and read again too.
      service.openDetail({ kind: "context", type: "playlist", id: "detail-readded",
        name: "detail-readded", uri: "spotify:playlist:detail-readded", snapshotId: "v1",
        collaborative: true })
      pump()
      answerLibraryChecks()
      complete(reads("detail-readded")[0], 200, { type: "playlist", id: "detail-readded",
        name: "detail-readded", uri: "spotify:playlist:detail-readded", snapshot_id: "v1",
        collaborative: true, items: page("detail-readded-row", 0, 3) })
      service.addItemToPlaylist({ type: "track", uri: "spotify:track:detail-song" },
        service.detailItem)
      complete(writes("detail-readded", "POST")[0], 201, { snapshot_id: "v2" })
      expect(service.detailItems.length === 0 && service.detailLoading,
        "Detail rows from before the add were shown under its version")
      pump()
      answerLibraryChecks()
      complete(reads("detail-readded")[1], 200, { type: "playlist", id: "detail-readded",
        name: "detail-readded", uri: "spotify:playlist:detail-readded", snapshot_id: "v2",
        collaborative: true, items: page("detail-added", 0, 4) })
      expect(service.detailItems.length === 4 && service.detailItem.snapshotId === "v2",
        "The detail refresh after the add was not shown")

      service.api.cancelAll()
      console.log("PLAYLIST_VERSIONS_PASS")
      Qt.quit()
    }
  }
}
