import QtQuick

import "Api.js" as Api

// A library-sized cache, separate from the small recently-opened-page cache.
// The service supplies transport and disk I/O; tests use the same scheduler
// with a fake clock/wire. Only one request is owned at a time.
Item {
  id: root
  visible: false
  property string owner: ""
  property string identity: ""
  // The user's choice. Off stops filling and refreshing; what is already kept
  // stays readable until it expires or the account signs out.
  property bool warmingEnabled: false
  property bool signedIn: false
  property bool idle: false
  // Reads go to the local player, which lists what the Web API refuses this
  // app and spends no quota, so neither a remembered refusal nor a quota
  // pause holds a list back while it is true.
  property bool localReads: false
  property bool diskReady: false
  property string diskRaw: ""
  property string checksRaw: ""
  property var playlists: []
  property var entries: ({})
  // Each entry's stored form, with the rows it was made from. A check that only
  // confirms a version reuses it, so neither the rows nor the file are redone.
  property var chunks: ({})
  property var validated: ({})
  property var retryAt: ({})
  property var sizes: ({})
  property var request: null
  property var abort: null
  property var now: function() { return Date.now() }
  property var handle: null
  property var work: null
  property int serial: 0
  property int cursor: 0
  property int maxEntries: 512
  property int maxRows: 50000
  property int maxBytes: 33554432
  property int itemLimit: 10000
  property int staleMs: 300000
  // Opening a list checks its version itself after five minutes, and the
  // library listing names a changed version within six hours, so asking
  // Spotify about every held list more often than daily only spends quota.
  property int recheckMs: 86400000
  property int maxAgeMs: 604800000
  property int spacingMs: 3000
  // A list Spotify will not show this app (403, or an empty answer for a list
  // the account neither owns nor collaborates on) stays that way; asking again
  // each hour cost two requests per list for nothing. A changed Client ID
  // forgets these at once.
  property int refusedRetryMs: 604800000
  // Spotify's daily quota, as opposed to its rolling rate limit. Its reply
  // does not always carry a Retry-After, so wait a good part of the day.
  property int quotaPauseMs: 21600000
  property double nextAt: 0
  property double suspendedUntil: 0
  property bool budgetFull: false
  property bool restoring: false
  property string lastResult: ""
  readonly property bool canRun: warmingEnabled && signedIn && idle && diskReady && owner !== ""
  readonly property var libraryIds: {
    var ids = ({})
    var list = playlists || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].id) ids[String(list[i].id)] = true
    return ids
  }
  // Pages opened from search or an artist are kept too, but progress is about
  // the library.
  readonly property int cachedCount: {
    var total = 0
    for (var id in entries) if (libraryIds[id]) total++
    return total
  }
  readonly property int completeCount: {
    var total = 0
    for (var id in entries)
      if (libraryIds[id] && !entries[id].data.next && entries[id].data.verified !== false) total++
    return total
  }
  readonly property string progress: completeCount + "/" + playlists.length
    + " lists complete · " + cachedCount + " available locally"
  readonly property string status: !warmingEnabled
      ? (cachedCount ? "Idle caching off · " + cachedCount + " saved lists stay readable" : "Idle caching off")
    : !signedIn ? "Waiting for Spotify sign-in"
    : !owner ? "Waiting for your Spotify account"
    : budgetFull ? "Cache budget reached · saved lists stay checked, others load when opened"
    : suspendedUntil > now() ? "Caching paused after Spotify refused a request"
    : !idle ? progress + " · resumes when the panel closes"
    : handle ? progress + " · downloading quietly"
    : progress + " · checking for changes"
  // Rows, versions or cursors changed: the whole file is due.
  signal changed()
  // Only when a list was last confirmed changed: the small checks file is due.
  signal rechecked()
  signal versionChecked(string playlistId, string snapshotId)

  onCanRunChanged: if (!canRun) pause()
  onIdentityChanged: { pause(); suspendedUntil = 0; retryAt = ({}) }
  onOwnerChanged: { pause(); restore() }
  onDiskReadyChanged: if (diskReady) restore()

  Timer {
    interval: 1000
    running: root.canRun
    repeat: true
    onTriggered: root.tick()
  }

  function pause() {
    serial++
    if (handle && typeof abort === "function") abort(handle)
    handle = null
    work = null
    validated = ({})
  }

  function read(id) {
    var entry = entries[String(id || "")]
    return entry && Api.timestampIsFresh(entry.updatedAt, now(), maxAgeMs)
      ? entry.data : null
  }

  function freshness(id) {
    var entry = entries[String(id || "")]
    if (entry && entry.data.verified === false) return "stale"
    return Api.queryCacheState(entry, now(), staleMs)
  }

  // An empty answer for a playlist you neither own nor collaborate on is
  // Spotify hiding its songs, not a playlist without any.
  function hidesSongs(item) {
    return Api.playlistItemsHiddenByApi(200, Api.playlistOwnedByUser(item, owner),
      !!item && item.collaborative === true, owner !== "")
  }

  function keep(data) {
    return warmingEnabled && store(data, now(), null)
  }

  function frame(entriesText) {
    return "{\"version\":2,\"owner\":" + JSON.stringify(owner) + ",\"entries\":{"
      + entriesText + "}}"
  }

  // Everything an entry adds to the file, assuming the widest timestamp and
  // flag, so the file can never be larger than the budget it was kept to.
  function entryBytes(id, chunk) {
    return 2 * (JSON.stringify(String(id)).length + chunk.text.length
      + ":{\"updatedAt\":,\"verified\":false,\"data\":},".length + 16)
  }

  function chunkFor(id, data, prepared) {
    var held = prepared || chunks[id]
    if (held && held.item === data.item && held.items === data.items && held.next === data.next)
      return held
    var encoded = Api.encodePlaylistSongs(data.items)
    return { item: data.item, items: data.items, next: data.next, text: JSON.stringify({
      item: data.item, next: String(data.next || ""), refs: encoded.refs, rows: encoded.rows }) }
  }

  function store(data, updatedAt, prepared) {
    if (!owner || !diskReady || !data || !data.item || !data.item.id
        || !Array.isArray(data.items)) return false
    var id = String(data.item.id)
    var capped = Api.cappedPageSnapshot(data, itemLimit)
    if (!capped.items.length && hidesSongs(capped.item)) return false
    var existing = read(id)
    // Opening a warmed page must not truncate its full copy back to 50 rows.
    if (existing && existing.item.snapshotId && existing.item.snapshotId === capped.item.snapshotId
        && existing.items.length > capped.items.length) capped = existing
    prune()
    var chunk = chunkFor(id, capped, prepared)
    var bytes = entryBytes(id, chunk)
    var totalBytes = 2 * frame("").length + bytes
    var totalRows = capped.items.length
    for (var key in entries) {
      if (key === id) continue
      totalBytes += Number(sizes[key]) || 0
      totalRows += entries[key].data.items.length
    }
    if (!(entries.hasOwnProperty(id) || Object.keys(entries).length < maxEntries)
        || totalBytes > maxBytes || totalRows > maxRows) {
      budgetFull = true
      return false
    }
    // A changed list can give room back without being removed. Let missing
    // lists try again; unchanged checks must not repeatedly reopen a full budget.
    if (existing && (capped.items.length < existing.items.length || bytes < sizes[id]))
      budgetFull = false
    var rewritten = chunk !== chunks[id]
    var next = Api.shallowCopy(entries)
    next[id] = { updatedAt: updatedAt, data: capped }
    chunks[id] = chunk
    sizes[id] = bytes
    entries = next
    if (!restoring) {
      if (rewritten) changed()
      else rechecked()
    }
    return true
  }

  // Past its age an entry is never drawn again, so it gives its room back.
  function prune() {
    var next = null
    for (var id in entries) {
      if (Api.timestampIsFresh(entries[id].updatedAt, now(), maxAgeMs)) continue
      if (!next) next = Api.shallowCopy(entries)
      delete next[id]
      delete chunks[id]
      delete sizes[id]
    }
    if (!next) return false
    entries = next
    budgetFull = false
    if (!restoring) changed()
    return true
  }

  // The header is stored at the size the detail page draws it; the same cover keeps the stored form.
  function withCover(data, cover) {
    if (!cover || cover === data.item.imageUrl) return data
    var next = Api.shallowCopy(data)
    next.item = Api.shallowCopy(data.item)
    next.item.imageUrl = cover
    return next
  }

  // A confirmed version always keeps its rows, even when a new cover does not fit yet.
  function confirm(data, cover) {
    var covered = withCover(data, cover)
    return keep(covered) || (covered !== data && keep(data))
  }

  // The Playlists page shows covers at list size. What it saves keeps the cover held
  // for the same version, else the larger one the library lists, else the one held before.
  function withHeldCover(data) {
    if (!data || !data.item) return data
    var held = read(data.item.id)
    var heldCover = held ? String(held.item.imageUrl || "") : ""
    return withCover(data, held && held.item.snapshotId === data.item.snapshotId
      ? heldCover : String(data.item.coverUrl || "") || heldCover)
  }

  function drop(id) {
    var key = String(id || "")
    // Edits cancel any in-flight read, including metadata/final verification.
    pause()
    delete retryAt[key]
    if (!entries.hasOwnProperty(key)) return
    var next = Api.shallowCopy(entries)
    delete next[key]
    delete chunks[key]
    delete sizes[key]
    entries = next
    budgetFull = false
    changed()
  }

  function clear() {
    pause()
    entries = ({})
    chunks = ({})
    sizes = ({})
    retryAt = ({})
    diskRaw = ""
    checksRaw = ""
    budgetFull = false
    suspendedUntil = 0
    changed()
  }

  function serialize() {
    var parts = []
    for (var id in entries)
      parts.push(JSON.stringify(id) + ":{\"updatedAt\":" + Math.floor(Number(entries[id].updatedAt) || 0)
        + ",\"verified\":" + (entries[id].data.verified !== false)
        + ",\"data\":" + chunks[id].text + "}")
    diskRaw = frame(parts.join(","))
    return diskRaw
  }

  function serializeChecks() {
    var checked = ({})
    for (var id in entries) {
      var data = entries[id].data
      checked[id] = [Math.floor(Number(entries[id].updatedAt) || 0), data.verified !== false,
        String(data.item.snapshotId || ""), data.items.length]
    }
    // Lists this app may not read are remembered too, so a restart does not
    // ask Spotify about every one of them again. Short waits are not worth a line.
    var refused = ({})
    for (var refusedId in retryAt)
      if (retryAt[refusedId] - now() > 3600000)
        refused[refusedId] = Math.floor(retryAt[refusedId])
    checksRaw = JSON.stringify({ version: 1, owner: owner, checked: checked,
      refused: refused })
    return checksRaw
  }

  function restore() {
    entries = ({})
    chunks = ({})
    sizes = ({})
    retryAt = ({})
    budgetFull = false
    if (!owner || !diskReady || diskRaw.length * 2 > maxBytes) return
    var record = Api.parseJson(diskRaw, ({}))
    if (!record || record.version !== 2 || record.owner !== owner) return
    var checks = Api.parseJson(checksRaw, ({}))
    var checked = checks && checks.version === 1 && checks.owner === owner && checks.checked
      ? checks.checked : ({})
    var refused = checks && checks.version === 1 && checks.owner === owner && checks.refused
      ? checks.refused : ({})
    var waits = ({})
    for (var refusedId in refused)
      if (Number(refused[refusedId]) > now()) waits[refusedId] = Number(refused[refusedId])
    retryAt = waits
    var stored = record.entries || ({})
    restoring = true
    for (var id in stored) {
      var entry = stored[id]
      var chunk = entry && entry.data
      if (!chunk || !chunk.item || String(chunk.item.id) !== id) continue
      var items = Api.decodePlaylistSongs(chunk)
      if (!items) continue
      var data = { item: chunk.item, items: items, next: String(chunk.next || ""),
        verified: entry.verified !== false }
      var updatedAt = Number(entry.updatedAt) || 0
      // A later check of the same rows lives in the small checks file.
      var check = checked[id]
      if (Array.isArray(check) && Number(check[0]) > updatedAt
          && check[2] === String(data.item.snapshotId || "") && check[3] === items.length) {
        updatedAt = Number(check[0])
        data.verified = check[1] === true
      }
      if (!Api.timestampIsFresh(updatedAt, now(), maxAgeMs)) continue
      store(data, updatedAt, { item: data.item, items: items, next: data.next,
        text: JSON.stringify(chunk) })
    }
    restoring = false
  }

  // Breadth first: all first pages before any deep paging, then round robin.
  // Full pages are compared with snapshot_id at most once a day, or as soon as
  // the library lists a different version (foreground freshness remains five minutes).
  // At the budget, lists already kept are still checked; new ones wait.
  function candidate() {
    var list = playlists || []
    for (var phase = 0; phase < 2; phase++) {
      for (var j = 0; j < list.length; j++) {
        var index = (cursor + j) % list.length
        var item = list[index]
        if (!item || !item.id) continue
        if (!localReads && (retryAt[item.id] || 0) > now()) continue
        var kept = read(item.id)
        if (!kept && budgetFull) continue
        if (phase === 0 && kept) continue
        if (phase === 1 && kept && !kept.next && kept.verified !== false
            && Api.timestampIsFresh(entries[item.id].updatedAt, now(), recheckMs)
            && (!item.snapshotId || item.snapshotId === kept.item.snapshotId)) continue
        if (kept && kept.items.length >= itemLimit && kept.next) continue
        cursor = (index + 1) % list.length
        return item
      }
    }
    return null
  }

  function send(path, query, callback) {
    var expected = serial
    var completed = false
    var returned = request(path, query, function(statusCode, payload, error, xhr) {
      completed = true
      if (expected !== root.serial) return
      root.handle = null
      root.nextAt = root.now() + root.spacingMs
      if (error) {
        var retryAfter = Api.responseRetryAfter(xhr)
        var quota = statusCode === 429 && Api.quotaExceededPayload(payload)
        root.lastResult = (quota ? "Spotify's daily quota for this app is spent"
          : "Cache request refused or failed (HTTP " + statusCode + ")")
          + (retryAfter ? ", retry after " + retryAfter + " s" : "")
        var id = root.work && root.work.item.id
        if (id) root.retryAt[id] = root.now()
          + (statusCode === 403 ? root.refusedRetryMs : statusCode === 404 ? 86400000 : 300000)
        if (statusCode === 403) root.rechecked()
        if (statusCode === 429) root.suspendedUntil = root.now()
          + Math.max(quota ? root.quotaPauseMs : 300000, Api.rateLimitRetryMs(retryAfter, 0))
        root.work = null
        return
      }
      root.lastResult = ""
      callback(payload)
    })
    if (!completed) handle = returned
  }

  function tick() {
    if (!canRun || handle || now() < nextAt || (!localReads && now() < suspendedUntil)
        || typeof request !== "function") return
    if (!work) {
      prune()
      var item = candidate()
      if (!item) return
      var kept = read(item.id)
      work = { item: item, kept: kept, stage: "metadata" }
      if (kept && kept.next && validated[item.id] === kept.item.snapshotId
          && (!item.snapshotId || item.snapshotId === kept.item.snapshotId))
        work = { item: kept.item, kept: kept, stage: "items" }
    }
    var id = String(work.item.id)
    if (work.stage === "items") {
      var existing = work.kept
      var path = existing ? existing.next : "/playlists/" + encodeURIComponent(id) + "/items"
      send(path, existing ? null : { limit: 50 }, function(payload) {
        if (!payload || !Array.isArray(payload.items)) {
          root.retryAt[id] = root.now() + 300000
          root.work = null
          return
        }
        var offset = Number(payload && payload.offset) || 0
        var page = Api.normalizePage(payload, function(value) {
          var position = offset++
          var track = Api.normalizeTrack(value, 96)
          if (track) track.playlistPosition = position
          return track
        })
        var data = { item: root.work.item,
          items: (root.work.kept ? root.work.kept.items : []).concat(page.items), next: page.next,
          verified: false }
        // A broken cursor must not spin forever or duplicate an entire page.
        if (root.work.kept && page.next && page.next === root.work.kept.next) {
          root.retryAt[id] = root.now() + 3600000
          root.work = null
          return
        }
        if (!root.keep(data)) {
          // Hidden or over budget: either way, asking again soon changes nothing.
          var hidden = !data.items.length && root.hidesSongs(data.item)
          if (hidden)
            root.lastResult = "Spotify hides the songs of playlists you neither own nor collaborate on, so those are not cached"
          root.retryAt[id] = root.now() + (hidden ? root.refusedRetryMs : 3600000)
          if (hidden) root.rechecked()
          root.work = null
          return
        }
        if (!page.next) root.work = { item: data.item, kept: data, stage: "verify" }
        else root.work = null
      })
    } else {
      var verifying = work.stage === "verify"
      send("/playlists/" + encodeURIComponent(id), { fields: "snapshot_id,images" }, function(payload) {
        var version = String(payload && payload.snapshot_id || "")
        var cover = Api.imageFor(payload && payload.images, 256)
        var kept = root.work.kept
        if (!version) {
          root.retryAt[id] = root.now() + 300000
          root.work = null
          return
        }
        root.versionChecked(id, version)
        if (verifying) {
          if (version === root.work.item.snapshotId) {
            kept.verified = true
            root.confirm(kept, cover)
          }
          else root.drop(id)
          root.work = null
          return
        }
        root.validated[id] = version
        var current = Api.shallowCopy(root.work.item)
        current.snapshotId = version
        if (cover) current.imageUrl = cover
        if (kept && version === kept.item.snapshotId && !kept.next) {
          kept.verified = true
          root.confirm(kept, cover)
          root.work = null
        } else root.work = { item: current, kept: kept && version === kept.item.snapshotId ? kept : null, stage: "items" }
      })
    }
  }
}
