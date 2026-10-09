import QtQuick
import QtTest
import ".." as Plugin
import "../Api.js" as Api

TestCase {
  id: test
  name: "PlaylistLibraryCache"
  property double clock: 10000
  property var requests: []

  Component {
    id: component
    Plugin.PlaylistCache {
      owner: "account-a"
      identity: "app-a"
      diskReady: true
      warmingEnabled: true
      signedIn: true
      idle: true
      now: function() { return test.clock }
      request: function(path, query, callback) {
        var job = { path: path, query: query, callback: callback, aborted: false }
        test.requests.push(job)
        return job
      }
      abort: function(job) { job.aborted = true }
    }
  }
  SignalSpy { id: changedSpy; signalName: "changed" }
  SignalSpy { id: recheckedSpy; signalName: "rechecked" }
  function init() { clock = 10000; requests = [] }
  function cache(list) {
    return createTemporaryObject(component, test, { playlists: list || [playlist("a")] })
  }
  function playlist(id, version) { return { id: id, type: "playlist", snapshotId: version || "v1" } }
  function owned(id) { var item = playlist(id); item.ownerId = "account-a"; return item }
  function spotifyId(prefix, n) {
    var tail = n.toString(36)
    return prefix + "0000000000000000000000".slice(0, 22 - prefix.length - tail.length) + tail
  }
  function spotifyArtist(n) {
    var id = spotifyId("ar", n)
    return { external_urls: { spotify: "https://open.spotify.com/artist/" + id },
      href: "https://api.spotify.com/v1/artists/" + id, id: id, name: "Artist Name " + n,
      type: "artist", uri: "spotify:artist:" + id }
  }
  // Shaped like GET /playlists/{id}/items. Within a playlist an album tends to
  // appear about one and a half times and an artist about two and a half.
  function spotifyItem(list, n) {
    var albumNumber = list * 10000 + Math.floor(n * 2 / 3)
    var albumId = spotifyId("al", albumNumber)
    var artists = [spotifyArtist(list * 10000 + Math.floor(n * 2 / 5))]
    if (n % 3 === 0) artists.push(spotifyArtist(list * 10000 + 5000 + n % 7))
    var art = "https://i.scdn.co/image/ab67616d"
    var image = spotifyId("im", albumNumber)
    var id = spotifyId("tr", list * 10000 + n)
    return { added_at: "2025-0" + (1 + n % 9) + "-1" + (n % 10) + "T12:34:56Z",
      added_by: { id: "account-a" }, is_local: false, primary_color: null,
      item: { album: { album_type: "album", artists: artists.slice(0, 1),
        available_markets: ["US", "CA"], external_urls: { spotify: "https://open.spotify.com/album/" + albumId },
        href: "https://api.spotify.com/v1/albums/" + albumId, id: albumId,
        images: [{ height: 640, url: art + "0000b273" + image, width: 640 },
          { height: 300, url: art + "00001e02" + image, width: 300 },
          { height: 64, url: art + "00004851" + image, width: 64 }],
        name: "Album Title " + albumNumber, release_date: "20" + (10 + n % 15) + "-04-1" + (n % 10),
        release_date_precision: "day", total_tracks: 12, type: "album", uri: "spotify:album:" + albumId },
      artists: artists, disc_number: 1, duration_ms: 150000 + n * 37, explicit: n % 5 === 0,
      external_ids: { isrc: "USRC1" + n }, external_urls: { spotify: "https://open.spotify.com/track/" + id },
      href: "https://api.spotify.com/v1/tracks/" + id, id: id, is_local: false, is_playable: true,
      name: "Song Title " + n + " (Remastered)", popularity: 50, preview_url: null,
      track_number: 1 + n % 12, type: "track", uri: "spotify:track:" + id } }
  }
  // Normalized exactly as the warmer does it, positions included.
  function realisticRows(list, count) {
    var values = []
    for (var n = 0; n < count; n++) values.push(spotifyItem(list, n))
    var offset = 0
    return Api.normalizePage({ items: values }, function(value) {
      var position = offset++
      var track = Api.normalizeTrack(value, 96)
      if (track) track.playlistPosition = position
      return track
    }).items
  }
  function track(id) { return { id: id, name: id, uri: "spotify:track:" + id, artists: [] } }
  // Spotify's mosaic playlist covers come in these three sizes.
  function mosaic(name) {
    return [640, 300, 60].map(function(size) {
      return { url: "https://i.scdn.co/image/" + name + "-" + size, width: size, height: size }
    })
  }
  function snapshot(id, count, next, version) {
    var rows = []
    for (var i = 0; i < count; i++) { var row = track("same"); row.playlistPosition = i; rows.push(row) }
    return { item: playlist(id, version), items: rows, next: next || "" }
  }
  function step(c) { clock += c.spacingMs; c.tick(); return requests[requests.length - 1] }
  function answer(payload, status, error) {
    requests[requests.length - 1].callback(status || 200, payload, error || "")
  }
  function start(c) { c.tick(); answer({ snapshot_id: "v1" }); step(c) }
  function finish(c) {
    start(c)
    answer({ items: [{ track: track("one") }], offset: 0, next: null })
    step(c); answer({ snapshot_id: "v1" })
  }

  function test_firstPagesBeforeDeepPages() {
    var c = cache([playlist("a"), playlist("b")])
    start(c)
    answer({ items: [{ track: track("one") }], next: "/playlists/a/items?offset=1" })
    compare(c.read("a").items.length, 1)
    compare(step(c).path, "/playlists/b")
    answer({ snapshot_id: "v1" })
    compare(step(c).path, "/playlists/b/items")
  }
  function test_completePlaylistNeedsNoTrackRequestsOnReopen() {
    var c = cache(); finish(c)
    compare(c.read("a").items[0].id, "one")
    compare(c.freshness("a"), "fresh")
    var count = requests.length
    step(c)
    compare(requests.length, count)
  }
  function test_staleUnchangedVersionSkipsTracks() {
    var c = cache(); finish(c); clock += c.recheckMs + 1
    compare(step(c).path, "/playlists/a")
    answer({ snapshot_id: "v1" })
    compare(c.freshness("a"), "fresh")
    var count = requests.length; step(c); compare(requests.length, count)
  }
  function test_changedVersionStartsFromFirstPageAndReplacesRows() {
    var c = cache(); c.keep(snapshot("a", 2)); c.playlists = [playlist("a", "v2")]
    c.tick(); answer({ snapshot_id: "v2" })
    compare(step(c).path, "/playlists/a/items")
    compare(c.read("a").items.length, 2, "old rows remain until a replacement arrives")
    answer({ items: [{ track: track("new") }], next: null })
    compare(c.read("a").items[0].id, "new")
    compare(c.read("a").item.snapshotId, "v2")
  }
  function test_restartResumesCheckedCursor() {
    var c = cache(); c.keep(snapshot("a", 2, "/playlists/a/items?offset=2"))
    var raw = c.serialize()
    var restored = cache(); restored.diskRaw = raw; restored.restore()
    compare(restored.read("a").items.length, 2)
    restored.tick(); answer({ snapshot_id: "v1" })
    compare(step(restored).path, "/playlists/a/items?offset=2")
  }
  function test_partialChangedAfterRestartDoesNotAppendOldRows() {
    var c = cache(); c.keep(snapshot("a", 2, "/playlists/a/items?offset=2"))
    c.tick(); answer({ snapshot_id: "v2" })
    compare(step(c).path, "/playlists/a/items")
    answer({ items: [{ track: track("new") }], next: null })
    compare(c.read("a").items.length, 1)
  }
  function test_knownLibraryChangeInvalidatesInSessionContinuation() {
    var c = cache(); start(c)
    answer({ items: [{ track: track("old") }], next: "/playlists/a/items?offset=1" })
    c.playlists = [playlist("a", "v2")]
    compare(step(c).path, "/playlists/a", "changed library version must be checked before appending")
    answer({ snapshot_id: "v2" })
    compare(step(c).path, "/playlists/a/items")
  }
  function test_pauseAbortsAndIgnoresLateResponses() {
    var c = cache(); c.tick(); var job = requests[0]
    c.idle = false
    verify(job.aborted)
    job.callback(200, { snapshot_id: "v1" }, "")
    compare(c.work, null); compare(c.handle, null)
    var count = requests.length; step(c); compare(requests.length, count)
    c.idle = true; compare(step(c).path, "/playlists/a")
  }
  function test_disableAndIdentityChangeCancelOldWork() {
    var c = cache(); c.tick(); c.warmingEnabled = false; verify(requests[0].aborted)
    c.warmingEnabled = true; step(c); var job = requests[1]
    c.identity = "app-b"; verify(job.aborted)
    job.callback(200, { snapshot_id: "v1" }, ""); compare(c.work, null)
  }
  function test_accountScopeAndLogoutForgetRows() {
    var c = cache(); c.keep(snapshot("a", 2)); var raw = c.serialize()
    c.owner = "account-b"; compare(c.read("a"), null)
    c.diskRaw = raw; c.restore(); compare(c.read("a"), null)
    c.owner = "account-a"; compare(c.read("a").items.length, 2)
    c.clear(); compare(c.read("a"), null); compare(c.diskRaw, "")
  }
  function test_longerWarmCopySurvivesShortForegroundPage() {
    var c = cache(); c.keep(snapshot("a", 300)); c.keep(snapshot("a", 50))
    compare(c.read("a").items.length, 300)
  }
  function test_successfulEmptyPlaylistIsRemembered() {
    var c = cache([owned("a")]); start(c); answer({ items: [], next: null })
    step(c); answer({ snapshot_id: "v1" })
    verify(c.read("a")); compare(c.read("a").items.length, 0)
    var count = requests.length; step(c); compare(requests.length, count)
  }
  function test_duplicatesAndUnavailablePositionsRemainCorrect() {
    var c = cache(); start(c)
    answer({ items: [{ track: track("same") }, { track: null }, { track: track("same") }], offset: 7, next: "/playlists/a/items?offset=10" })
    var rows = c.read("a").items
    compare(rows.length, 3); compare(rows[0].id, rows[2].id)
    compare(rows[1].uri, "", "unavailable row retains its original position")
    compare(rows[0].playlistPosition, 7); compare(rows[2].playlistPosition, 9)
  }
  function test_rateLimitStopsWholeWarmerAndPreservesRows() {
    var c = cache(); c.keep(snapshot("a", 2)); clock += c.recheckMs + 1
    c.tick(); answer(null, 429, "rate limited")
    compare(c.read("a").items.length, 2)
    verify(c.suspendedUntil > clock)
    var count = requests.length; step(c); compare(requests.length, count)
  }
  function retryAfter(value) {
    return { getResponseHeader: function(name) {
      return String(name).toLowerCase() === "retry-after" ? value : null } }
  }
  function test_longQuotaRetryAfterHoldsEveryPlaylistUntilItEnds() {
    var c = cache([playlist("a"), playlist("b")]); c.keep(snapshot("a", 2))
    c.tick()
    var refusedAt = clock
    requests[0].callback(429, { error: { reason: "QUOTA_EXCEEDED" } }, "quota",
      retryAfter("63287"))
    compare(c.read("a").items.length, 2, "saved rows stay readable during the refusal")
    clock += 300001; c.tick()
    compare(requests.length, 1, "Cache ignored the server's long quota Retry-After")
    clock = refusedAt + 63287000 - 1; c.tick()
    compare(requests.length, 1)
    clock = refusedAt + 63288000; c.tick()
    compare(requests.length, 2, "warming never resumed after the quota window")
  }
  function test_missingOrInvalidRetryAfterPausesFiveMinutes() {
    var values = [null, "", "soon", "-5", "21"]
    for (var i = 0; i < values.length; i++) {
      requests = []
      var c = cache([playlist("a"), playlist("b")])
      c.tick()
      requests[0].callback(429, null, "rate limited",
        values[i] === null ? null : retryAfter(values[i]))
      clock += 299999; c.tick()
      compare(requests.length, 1, "resumed early for Retry-After " + values[i])
      clock += 2; c.tick()
      compare(requests.length, 2, "stayed paused for Retry-After " + values[i])
    }
  }
  function test_anotherAppIsNotHeldByTheOldAppsQuota() {
    var c = cache([playlist("a"), playlist("b")]); c.keep(snapshot("a", 2))
    c.tick()
    requests[0].callback(429, { error: { reason: "QUOTA_EXCEEDED" } }, "quota",
      retryAfter("63287"))
    step(c); compare(requests.length, 1)
    c.identity = "app-b"; c.tick()
    compare(requests.length, 2, "a different app inherited the old app's quota refusal")
    compare(c.read("a").items.length, 2)
  }
  function test_forbiddenPlaylistDoesNotBlockOthers() {
    var c = cache([playlist("a"), playlist("b")]); c.tick(); answer(null, 403, "forbidden")
    compare(step(c).path, "/playlists/b")
    verify(c.retryAt.a >= clock + 3500000)
  }
  // A personal app is never shown a list it was refused once, so asking each
  // hour was two wasted requests per list; the checks file carries the wait
  // across a restart, where retryAt used to start empty.
  function test_forbiddenPlaylistWaitsAWeekAndSurvivesRestore() {
    var c = cache([playlist("a"), playlist("b")])
    recheckedSpy.target = c; recheckedSpy.clear()
    c.tick(); answer(null, 403, "forbidden")
    verify(c.retryAt.a >= clock + c.refusedRetryMs - 1)
    compare(recheckedSpy.count, 1, "the wait is worth a checks-file write")
    var raw = c.serialize(); var checks = c.serializeChecks()
    verify(checks.indexOf("\"refused\"") >= 0)
    clock += c.recheckMs
    var restored = cache([playlist("a"), playlist("b")])
    restored.checksRaw = checks; restored.diskRaw = raw; restored.restore()
    compare(step(restored).path, "/playlists/b", "a refused list is skipped after a restart too")
    clock += c.refusedRetryMs
    var later = cache([playlist("a")]); later.checksRaw = checks; later.diskRaw = raw; later.restore()
    compare(step(later).path, "/playlists/a", "an expired wait is not restored")
  }
  // A refusal and a quota pause are the Web API's; the local player reads
  // those lists and spends nothing, so it is asked regardless.
  function test_localReadsIgnoreWebApiRefusalsAndPauses() {
    var c = cache([playlist("a"), playlist("b")]); c.tick(); answer(null, 403, "forbidden")
    c.suspendedUntil = clock + c.quotaPauseMs
    var count = requests.length; step(c); compare(requests.length, count, "the Web API stays paused")
    c.localReads = true
    compare(step(c).path, "/playlists/b", "the pause does not hold the player back")
    answer({ snapshot_id: "v1" })
    compare(step(c).path, "/playlists/b/items")
    answer({ items: [{ track: track("one") }], next: null })
    compare(step(c).path, "/playlists/b", "the final page is verified")
    answer({ snapshot_id: "v1" })
    compare(step(c).path, "/playlists/a", "the refused list is asked again through the player")
  }

  function test_hiddenSongsWaitAWeekAndAreRemembered() {
    var c = cache(); recheckedSpy.target = c; recheckedSpy.clear()
    start(c); answer({ items: [], next: null })
    verify(c.retryAt.a >= clock + c.refusedRetryMs - 1)
    compare(recheckedSpy.count, 1)
  }
  function test_spentQuotaPausesForHoursWithoutARetryAfter() {
    var c = cache(); c.keep(snapshot("a", 2)); clock += c.recheckMs + 1
    c.tick(); answer({ error: { status: 429, message: "Too many requests", reason: "QUOTA_EXCEEDED" } }, 429, "quota")
    verify(c.suspendedUntil >= clock + c.quotaPauseMs, "a spent daily quota is not a five-minute wait")
    verify(c.lastResult.indexOf("daily quota") >= 0)
    compare(c.read("a").items.length, 2)
    var count = requests.length; clock += 3600000; step(c); compare(requests.length, count)
  }
  function test_plainRateLimitStillPausesFiveMinutes() {
    var c = cache(); c.keep(snapshot("a", 2)); clock += c.recheckMs + 1
    c.tick(); answer({ error: { status: 429, message: "Too many requests" } }, 429, "busy")
    verify(c.suspendedUntil >= clock + 300000)
    verify(c.suspendedUntil < clock + c.quotaPauseMs)
  }
  function test_oneRequestAtATimeAndSpacing() {
    var c = cache(); c.tick(); c.tick(); compare(requests.length, 1)
    answer({ snapshot_id: "v1" }); c.tick(); compare(requests.length, 1)
    step(c); compare(requests.length, 2)
  }
  function test_editDropsRowsAndLateReadCannotRepopulate() {
    var c = cache(); c.keep(snapshot("a", 2)); clock += c.recheckMs + 1
    c.tick(); var job = requests[0]; c.drop("a"); verify(job.aborted)
    job.callback(200, { snapshot_id: "v1" }, ""); compare(c.read("a"), null)
  }
  function test_versionChangingDuringDownloadDiscardsMixedCopy() {
    var c = cache(); start(c); answer({ items: [{ track: track("one") }], next: null })
    compare(c.freshness("a"), "stale")
    step(c); answer({ snapshot_id: "v2" }); compare(c.read("a"), null)
  }
  function test_budgetStopsWithoutEvicting() {
    var c = cache(); c.maxRows = 3; verify(c.keep(snapshot("a", 3)))
    verify(!c.keep(snapshot("b", 1))); verify(c.budgetFull)
    compare(c.read("a").items.length, 3); c.tick(); compare(requests.length, 0)
    c.drop("a"); verify(!c.budgetFull); verify(c.keep(snapshot("b", 1)))
  }
  function test_atTheBudgetKeptListsAreStillChecked() {
    var c = cache([playlist("a"), playlist("b")]); c.maxRows = 3
    verify(c.keep(snapshot("a", 3))); verify(!c.keep(snapshot("b", 1))); verify(c.budgetFull)
    clock += c.recheckMs + 1
    compare(step(c).path, "/playlists/a", "a full cache still compares the lists it holds")
    answer({ snapshot_id: "v1" })
    compare(c.freshness("a"), "fresh")
    var count = requests.length; step(c); compare(requests.length, count, "a new list waits for room")
  }
  function test_smallerChangedPlaylistReturnsRoom() {
    var c = cache([playlist("a"), playlist("b")]); c.maxRows = 3
    verify(c.keep(snapshot("a", 3)))
    verify(!c.keep(snapshot("b", 1))); verify(c.budgetFull)
    var shorter = snapshot("a", 1); shorter.item.snapshotId = "v2"
    verify(c.keep(shorter)); verify(!c.budgetFull, "a changed smaller playlist returns room")
    compare(step(c).path, "/playlists/b", "the scheduler resumes filling missing lists")
  }
  function test_expiredEntriesGiveTheirRoomBack() {
    var c = cache(); c.maxEntries = 1; verify(c.keep(snapshot("a", 1)))
    clock += c.maxAgeMs + 1
    verify(c.keep(snapshot("b", 1)), "an entry too old to draw still held the only slot")
    compare(Object.keys(c.entries), ["b"])
  }
  function test_expiryReopensAFullBudgetToIdleWork() {
    var c = cache([playlist("a"), playlist("b"), playlist("c")]); c.maxEntries = 2
    verify(c.keep(snapshot("a", 1)))
    clock += c.maxAgeMs - 1000
    verify(c.keep(snapshot("b", 1))); verify(!c.keep(snapshot("c", 1))); verify(c.budgetFull)
    clock += 2000
    changedSpy.target = c; changedSpy.clear()
    var count = requests.length
    c.tick()
    compare(requests.length, count + 1, "rows too old to draw held the budget shut")
    verify(!c.budgetFull)
    compare(Object.keys(c.entries), ["b"], "only the expired entry gives its room back")
    compare(c.read("b").items.length, 1)
    compare(changedSpy.count, 1, "removing expired rows must be saved")
  }
  function test_coverIsKeptAtTheDetailSize() {
    var c = cache()
    c.tick()
    compare(requests[0].query.fields, "snapshot_id,images", "the version check asks for the cover too")
    answer({ snapshot_id: "v1", images: mosaic("a") })
    step(c); answer({ items: [{ track: track("one") }], offset: 0, next: null })
    step(c); answer({ snapshot_id: "v1", images: mosaic("a") })
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/a-300")
    changedSpy.target = c; recheckedSpy.target = c
    changedSpy.clear(); recheckedSpy.clear()
    var held = c.read("a")
    clock += c.recheckMs + 1
    compare(step(c).path, "/playlists/a"); answer({ snapshot_id: "v1", images: mosaic("a") })
    compare(changedSpy.count, 0, "the same cover rewrote the song file")
    compare(recheckedSpy.count, 1)
    verify(c.read("a").item === held.item, "the same cover replaced the stored header")
    clock += c.recheckMs + 1
    compare(step(c).path, "/playlists/a"); answer({ snapshot_id: "v1", images: mosaic("b") })
    compare(changedSpy.count, 1, "a new cover must be saved")
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/b-300")
    compare(c.read("a").item.snapshotId, "v1")
    verify(c.read("a").items === held.items, "a new cover replaced the songs")
    compare(c.read("a").next, "")
  }
  function test_coverFollowsDeepPagesAndCursor() {
    var c = cache()
    c.tick(); answer({ snapshot_id: "v1", images: mosaic("a") })
    step(c); answer({ items: [{ track: track("one") }], offset: 0, next: "https://api.spotify.com/v1/playlists/a/items?offset=1" })
    compare(step(c).path, "https://api.spotify.com/v1/playlists/a/items?offset=1")
    answer({ items: [{ track: track("two") }], offset: 1, next: "https://api.spotify.com/v1/playlists/a/items?offset=2" })
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/a-300", "a resumed page dropped the cover")
    c.pause()
    compare(step(c).path, "/playlists/a"); answer({ snapshot_id: "v1", images: mosaic("b") })
    compare(step(c).path, "https://api.spotify.com/v1/playlists/a/items?offset=2", "a new cover restarted the download")
    answer({ items: [{ track: track("three") }], offset: 2, next: null })
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/b-300")
    compare(c.read("a").items.map(function(row) { return row.id }), ["one", "two", "three"])
  }
  function test_coverThatDoesNotFitStillConfirmsTheRows() {
    var c = cache()
    c.tick(); answer({ snapshot_id: "v1", images: mosaic("a") })
    step(c); answer({ items: [{ track: track("one") }], offset: 0, next: null })
    step(c); answer({ snapshot_id: "v1", images: mosaic("a") })
    var used = 2 * c.frame("").length
    for (var id in c.sizes) used += c.sizes[id]
    c.maxBytes = used
    changedSpy.target = c; recheckedSpy.target = c
    changedSpy.clear(); recheckedSpy.clear()
    var held = c.read("a")
    clock += c.recheckMs + 1
    compare(step(c).path, "/playlists/a")
    answer({ snapshot_id: "v1", images: mosaic("a-custom-cover-with-a-much-longer-address") })
    compare(changedSpy.count, 0, "a cover over the budget rewrote the song file")
    compare(recheckedSpy.count, 1, "the unchanged rows were not confirmed")
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/a-300")
    verify(c.read("a").items === held.items)
    compare(c.read("a").item.snapshotId, "v1"); compare(c.read("a").next, "")
    compare(c.freshness("a"), "fresh")
    var count = requests.length
    for (var i = 0; i < 5; i++) step(c)
    compare(requests.length, count, "a cover that does not fit was asked for every few seconds")
    clock += c.recheckMs + 1
    step(c)
    compare(requests.length, count + 1, "the list was not checked again an hour later")
  }
  function test_playlistsPageKeepsTheDetailSizeCover() {
    var c = cache([playlist("a"), playlist("b")])
    var listed = Api.normalizePlaylist({ id: "a", type: "playlist", name: "A", snapshot_id: "v1",
      owner: { id: "account-a" }, images: mosaic("a") }, 96)
    compare(listed.imageUrl, "https://i.scdn.co/image/a-60")
    compare(listed.coverUrl, "https://i.scdn.co/image/a-300")
    verify(c.keep(c.withHeldCover({ item: listed, items: [track("one")], next: "" })))
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/a-300", "a new list kept the list-size cover")
    // A row saved before rows listed their larger cover.
    var plain = Api.shallowCopy(listed); delete plain.coverUrl
    verify(c.keep(c.withHeldCover({ item: plain, items: [track("one"), track("two")], next: "" })))
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/a-300", "the same version lost its cover")
    var newer = Api.shallowCopy(plain); newer.snapshotId = "v2"
    verify(c.keep(c.withHeldCover({ item: newer, items: [track("three")], next: "" })))
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/a-300", "a new version lost the held cover")
    var relisted = Api.normalizePlaylist({ id: "a", type: "playlist", name: "A", snapshot_id: "v3",
      owner: { id: "account-a" }, images: mosaic("b") }, 96)
    verify(c.keep(c.withHeldCover({ item: relisted, items: [track("four")], next: "" })))
    compare(c.read("a").item.imageUrl, "https://i.scdn.co/image/b-300", "a newly listed cover was ignored")
    compare(c.read("a").items[0].id, "four")
    var held = c.read("a")
    changedSpy.target = c; recheckedSpy.target = c
    changedSpy.clear(); recheckedSpy.clear()
    verify(c.keep(c.withHeldCover(held)))
    compare(changedSpy.count, 0, "confirming the held copy rewrote the song file")
    compare(recheckedSpy.count, 1)
  }
  function test_entryAndByteBudgets() {
    var c = cache(); c.maxEntries = 1; c.keep(snapshot("a", 1)); verify(!c.keep(snapshot("b", 1)))
    c.clear(); c.maxBytes = 10; verify(!c.keep(snapshot("a", 1)))
  }
  function test_perPlaylistCapPreservesSafeCursor() {
    var c = cache(); c.itemLimit = 2; c.keep(snapshot("a", 5))
    compare(c.read("a").items.length, 2)
    verify(c.read("a").next.indexOf("offset=2") >= 0)
  }
  function test_corruptExpiredAndForeignFilesAreIgnored() {
    var c = cache(); c.diskRaw = "broken"; c.restore(); compare(c.cachedCount, 0)
    c.keep(snapshot("a", 1)); var raw = c.serialize(); clock += c.maxAgeMs + 1
    c.diskRaw = raw; c.restore(); compare(c.read("a"), null)
  }
  function test_missingItemsResponseCannotEraseCache() {
    var c = cache(); c.keep(snapshot("a", 2, "/playlists/a/items?offset=2"))
    c.tick(); answer({ snapshot_id: "v1" }); step(c); answer({})
    compare(c.read("a").items.length, 2); verify(c.retryAt.a > clock)
  }
  function test_storedRowsReadBackExactly() {
    var rows = realisticRows(3, 60)
    var offset = rows.length
    var odd = [spotifyItem(3, 4), { track: null },
      { added_at: "", is_local: true, item: { id: null, uri: "spotify:local:Band:Tape:Demo:181",
        name: "Demo", artists: [{ name: "Band" }], album: { name: "Tape", images: [] },
        type: "track", duration_ms: 181000, is_local: true } },
      { added_at: "2025-01-01T00:00:00Z", item: { type: "episode", id: "ep1", name: "Episode",
        uri: "spotify:episode:ep1", description: "Talk", duration_ms: 3600000,
        images: [{ url: "https://i.scdn.co/image/episode", width: 64 }],
        show: { type: "show", id: "sh1", name: "Show", publisher: "Host",
          images: [{ url: "https://i.scdn.co/image/show", width: 64 }] } } }]
    var extra = Api.normalizePage({ items: odd }, function(value) {
      var track = Api.normalizeTrack(value, 96)
      if (track) track.playlistPosition = offset++
      return track
    }).items
    // Shapes the codec does not know are stored as they are.
    extra.push({ id: "bare", uri: "spotify:track:bare", playlistPosition: offset++ })
    var unusual = Api.shallowCopy(rows[0]); unusual.n = "clashes with a short name"; extra.push(unusual)
    rows = rows.concat(extra)
    var next = "https://api.spotify.com/v1/playlists/mix/items?offset=" + offset + "&limit=50"
    var c = cache([owned("mix")]); verify(c.keep({ item: owned("mix"), items: rows, next: next }))
    var raw = c.serialize()
    verify(raw.length * 4 < JSON.stringify(rows).length, "stored rows are a quarter of their normalized size")
    var restored = cache([owned("mix")]); restored.diskRaw = raw; restored.restore()
    compare(JSON.stringify(restored.read("mix").items), JSON.stringify(rows))
    compare(restored.read("mix").next, next)
    compare(restored.read("mix").items[0].albumItem.artists[0].name, rows[0].artists[0].name)
  }
  function test_measuredLibraryCapacity() {
    var c = cache([]); c.maxRows = 1000000
    var rows = 0
    var lists = 0
    for (var list = 0; list < c.maxEntries && !c.budgetFull; list++) {
      var item = owned("list" + list)
      var data = { item: item, items: realisticRows(list, 400), next: "" }
      if (c.keep(data)) { rows += data.items.length; lists++ }
    }
    console.log("Library song cache: " + rows + " realistic rows in " + lists
      + " playlists fit the " + c.maxBytes + "-byte budget")
    verify(rows >= 40000, "32 MiB holds only " + rows + " realistic rows")
  }
  function test_fileAtTheBudgetRestoresWhole() {
    var c = cache([])
    var lists = []
    for (var i = 0; i < 40; i++) {
      lists.push({ item: owned("list" + i), items: realisticRows(i, 30), next: "" })
      verify(c.keep(lists[i]))
    }
    var used = 2 * c.frame("").length
    for (var id in c.sizes) used += c.sizes[id]
    var raw = c.serialize()
    verify(raw.length * 2 <= used, "the file is never larger than the budget counted for it")
    var restored = cache([]); restored.maxBytes = used; restored.diskRaw = raw; restored.restore()
    compare(Object.keys(restored.entries).length, 40, "a file filled to the budget restores whole")
    verify(!restored.budgetFull)
    compare(JSON.stringify(restored.read("list7").items), JSON.stringify(lists[7].items))
    var tight = cache([]); tight.maxBytes = used - 2; tight.diskRaw = raw; tight.restore()
    compare(Object.keys(tight.entries).length, 39, "one entry over the budget is refused, not the file")
    verify(tight.budgetFull)
  }
  function test_unchangedRecheckOnlyRecordsTheCheck() {
    var c = cache(); finish(c)
    changedSpy.target = c; recheckedSpy.target = c
    changedSpy.clear(); recheckedSpy.clear()
    clock += c.recheckMs + 1
    compare(step(c).path, "/playlists/a"); answer({ snapshot_id: "v1" })
    compare(changedSpy.count, 0, "a confirmed version must not rewrite the song file")
    compare(recheckedSpy.count, 1)
    compare(c.freshness("a"), "fresh")
    c.keep(snapshot("a", 2))
    compare(changedSpy.count, 1, "new rows are a content change")
  }
  function test_checksFileCarriesConfirmationsAcrossRestart() {
    var c = cache(); finish(c); var raw = c.serialize()
    var longer = cache(); longer.keep(snapshot("a", 2)); var otherRows = longer.serialize()
    clock += c.maxAgeMs - 10000
    compare(step(c).path, "/playlists/a"); answer({ snapshot_id: "v1" })
    var checks = c.serializeChecks()
    clock += 10000
    var restored = cache(); restored.checksRaw = checks; restored.diskRaw = raw; restored.restore()
    compare(restored.read("a").items[0].id, "one", "a list confirmed this week outlives its week-old rows")
    compare(restored.freshness("a"), "fresh")
    var unchecked = cache(); unchecked.diskRaw = raw; unchecked.restore()
    compare(unchecked.read("a"), null)
    var other = cache(); other.checksRaw = checks; other.diskRaw = otherRows; other.restore()
    compare(other.read("a"), null, "a check of other rows does not refresh these")
  }
  function test_offKeepsSavedRowsReadableButAddsNone() {
    var c = cache([playlist("a"), playlist("b")]); verify(c.keep(snapshot("a", 2)))
    var raw = c.serialize()
    c.warmingEnabled = false
    verify(!c.keep(snapshot("b", 2)), "Off must not fill the cache from opened pages")
    compare(c.read("a").items.length, 2)
    compare(c.status, "Idle caching off · 1 saved lists stay readable")
    var restored = cache(); restored.warmingEnabled = false
    restored.diskRaw = raw; restored.restore()
    compare(restored.read("a").items.length, 2, "Off still reads what was saved")
    c.drop("a"); compare(c.read("a"), null, "edits still forget rows while Off")
  }
  function test_hiddenSongsAreNotCachedAsAnEmptyList() {
    var c = cache(); start(c); answer({ items: [], next: null })
    compare(c.read("a"), null)
    verify(c.retryAt.a >= clock + 3500000)
    verify(c.lastResult.indexOf("hides the songs") >= 0)
    verify(!c.keep({ item: playlist("a"), items: [], next: "" }))
    var count = requests.length; step(c); compare(requests.length, count)
    verify(c.keep({ item: owned("a"), items: [], next: "" }), "your own empty playlist is a real answer")
  }
  function test_progressCountsOnlyLibraryPlaylists() {
    var c = cache(); c.keep(snapshot("a", 1)); c.keep(snapshot("opened-from-search", 1))
    compare(c.cachedCount, 1); compare(c.completeCount, 1)
    compare(c.progress, "1/1 lists complete · 1 available locally")
  }
  function test_statusExplainsWhatItWaitsFor() {
    var c = cache(); c.signedIn = false
    compare(c.status, "Waiting for Spotify sign-in")
    c.signedIn = true; c.owner = ""
    compare(c.status, "Waiting for your Spotify account")
  }
}
