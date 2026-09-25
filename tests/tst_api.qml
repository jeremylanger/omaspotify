import QtQuick
import QtTest

import "../Api.js" as Api

TestCase {
  name: "SpotifyApiLogic"

  function test_isCursorNavigationKey_coversMovingAndActivatingOnly() {
    verify(Api.isCursorNavigationKey(Qt.Key_Tab, false, ""))
    verify(Api.isCursorNavigationKey(Qt.Key_Backtab, false, ""))
    verify(Api.isCursorNavigationKey(Qt.Key_Return, true, ""))
    verify(Api.isCursorNavigationKey(Qt.Key_Left, true, ""))
    verify(Api.isCursorNavigationKey(Qt.Key_End, true, ""))
    verify(Api.isCursorNavigationKey(Qt.Key_J, true, "j"))
    verify(!Api.isCursorNavigationKey(Qt.Key_Left, false, ""))
    verify(!Api.isCursorNavigationKey(Qt.Key_Space, true, " "))
    verify(!Api.isCursorNavigationKey(Qt.Key_M, true, "m"))
  }

  function test_queryString_isStableAndEncoded() {
    compare(Api.queryString({ z: "last", q: "AC/DC & friends", empty: "" }),
      "q=AC%2FDC%20%26%20friends&z=last")
  }

  function test_barTrackText_respectsIndependentTitleAndArtistSettings() {
    compare(Api.barTrackText("Blue in Green", "Miles Davis", true, false,
      true, true),
      "Blue in Green")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", false, true,
      true, true),
      "Miles Davis")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", true, true,
      true, true),
      "Miles Davis - Blue in Green")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", false, false,
      true, true), "")
    compare(Api.barTrackText("  Blue in Green  ", "  Miles Davis  ", true,
      true, true, true),
      "Miles Davis - Blue in Green")
    compare(Api.barTrackText("Blue in Green", "", true, true, true, true),
      "Blue in Green")
    compare(Api.barTrackText("", "Miles Davis", true, true, true, true),
      "Miles Davis")
  }

  function test_barTrackText_pausedVisibilityIsConfigurable() {
    compare(Api.barTrackText("Blue in Green", "Miles Davis", true, true,
      false, true),
      "Miles Davis - Blue in Green")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", true, true,
      false, false), "")
  }

  function test_idleShutdown_onlyRunsForAnEmptyReceiver() {
    verify(Api.idleShutdownShouldRun(true, false, false, 15))
    verify(!Api.idleShutdownShouldRun(true, true, false, 15))
    verify(!Api.idleShutdownShouldRun(true, false, true, 15))
    verify(!Api.idleShutdownShouldRun(false, false, false, 15))
    verify(!Api.idleShutdownShouldRun(true, false, false, 0))
  }

  function test_scrollAvailability_requiresAtLeastOneBarLabel() {
    verify(Api.canScrollBarText(true, true))
    verify(Api.canScrollBarText(true, false))
    verify(Api.canScrollBarText(false, true))
    verify(!Api.canScrollBarText(false, false))
  }

  function test_normalizedMaxBarTextWidth_defaultsClampsAndSnaps() {
    compare(Api.normalizedMaxBarTextWidth(undefined), 240)
    compare(Api.normalizedMaxBarTextWidth(null), 240)
    compare(Api.normalizedMaxBarTextWidth(""), 240)
    compare(Api.normalizedMaxBarTextWidth("nonsense"), 240)
    compare(Api.normalizedMaxBarTextWidth(-40), 240)
    // 0 is the uncapped sentinel and must survive normalization untouched.
    compare(Api.normalizedMaxBarTextWidth(0), 0)
    compare(Api.normalizedMaxBarTextWidth("0"), 0)
    compare(Api.normalizedMaxBarTextWidth(240), 240)
    compare(Api.normalizedMaxBarTextWidth(247), 240)
    compare(Api.normalizedMaxBarTextWidth(265), 280)
    compare(Api.normalizedMaxBarTextWidth(10), 160)
    compare(Api.normalizedMaxBarTextWidth(9999), 560)
  }

  function test_barTextWidthSlider_notchesCoverEveryNormalizedWidth() {
    var slider = Api.barTextWidthSlider()
    // The uncapped notch must sit past every real width, so no stored value can
    // normalize onto it and be mistaken for "unlimited".
    for (var i = 0; i < slider.ticks; i++) {
      var stop = slider.min + i * slider.step
      if (stop === slider.unlimited) continue
      compare(Api.normalizedMaxBarTextWidth(stop), stop)
    }
    compare(slider.min + (slider.ticks - 1) * slider.step, slider.unlimited)
    verify(Api.normalizedMaxBarTextWidth(slider.unlimited) < slider.unlimited)
    compare(Api.normalizedMaxBarTextWidth(240), 240)
  }

  function test_normalizedScrollSpeed_defaultsClampsAndSnaps() {
    compare(Api.normalizedScrollSpeed(undefined), 1)
    compare(Api.normalizedScrollSpeed("not-a-speed"), 1)
    compare(Api.normalizedScrollSpeed(0), 0.25)
    compare(Api.normalizedScrollSpeed(4), 3)
    compare(Api.normalizedScrollSpeed(1), 1)
    compare(Api.normalizedScrollSpeed(1.12), 1)
    compare(Api.normalizedScrollSpeed(1.13), 1.25)
  }

  function test_cacheFreshnessAndSleepDeadline_boundaries() {
    verify(Api.timestampIsFresh(1000, 5999, 5000))
    verify(!Api.timestampIsFresh(1000, 6000, 5000))
    verify(!Api.timestampIsFresh(1000, 999, 5000))
    verify(!Api.timestampIsFresh(0, 1000, 5000))

    compare(Api.deadlineRemainingSeconds(2501, 1000), 2)
    compare(Api.deadlineRemainingSeconds(2000, 1000), 1)
    compare(Api.deadlineRemainingSeconds(999, 1000), 0)
    compare(Api.deadlineRemainingSeconds("invalid", 1000), 0)
  }

  function test_boundedOrder_mutatesInPlaceAndEvictsOldestKeys() {
    var order = ["one", "two", "three"]
    var sameOrder = order
    compare(Api.touchBoundedOrder(order, "two", 3), "")
    verify(order === sameOrder)
    compare(order, ["one", "three", "two"])

    compare(Api.touchBoundedOrder(order, "four", 3), "one")
    compare(order, ["three", "two", "four"])
    compare(Api.touchBoundedOrder(order, "", 3), "")
  }

  function test_filteredSorted_reusesTheUnchangedDefaultList() {
    var rows = [{ name: "One" }, { name: "Two" }]
    verify(Api.filteredSorted(rows, "", "default") === rows)
    verify(Api.filteredSorted(rows, " two ", "default") !== rows)
    compare(Api.filteredSorted(rows, " two ", "default"), [rows[1]])
    compare(Api.filteredSorted([rows[0], null, rows[1]], "", "default"), rows)
  }

  function test_engineVolumeCurve_hasStableEndpointsAndRoundTrips() {
    compare(Api.engineVolumeToSlider(0), 0)
    compare(Api.engineVolumeToSlider(1), 1)
    compare(Api.sliderToEngineVolume(0), 0)
    compare(Api.sliderToEngineVolume(1), 1)

    var positions = [0.01, 0.1, 0.25, 0.5, 0.75, 0.9]
    for (var i = 0; i < positions.length; i++) {
      var slider = positions[i]
      var backend = Api.sliderToEngineVolume(slider)
      verify(Math.abs(Api.engineVolumeToSlider(backend) - slider) < 0.000001)
    }
  }

  function test_engineVolumeCurve_usesGentlerCubicTaper() {
    var backendMidpoint = Api.sliderToEngineVolume(0.5)
    verify(backendMidpoint > 0.73 && backendMidpoint < 0.75)
    verify(Api.engineVolumeToSlider(0.5) < 0.25)
  }

  function test_normalizeVolumePercent_preservesUnknownAndValidMute() {
    compare(Api.normalizeVolumePercent(null), null)
    compare(Api.normalizeVolumePercent(undefined), null)
    compare(Api.normalizeVolumePercent(""), null)
    compare(Api.normalizeVolumePercent("not-a-volume"), null)
    compare(Api.normalizeVolumePercent(0), 0)
    compare(Api.normalizeVolumePercent(47), 47)
    compare(Api.normalizeVolumePercent(120), 100)
  }

  function test_catalogSearchText_scopesResultsToArtist() {
    compare(Api.sanitizeSearchTerm("AC/DC \"Live\""), "AC/DC Live")
    compare(Api.catalogSearchText("Miles Davis", "blue in green"),
      "blue in green artist:\"Miles Davis\"")
    compare(Api.catalogSearchText("AC/DC \"Live\"", ""),
      "artist:\"AC/DC Live\"")
    compare(Api.artistPlaylistSearchText("Miles Davis", "blue in green"),
      "blue in green Miles Davis")
  }

  function test_volumeAndSeekHelpers_clampMuteAndRemember() {
    compare(Api.nextVolume(0.5, 0.1), 0.6)
    compare(Api.nextVolume(0.98, 0.1), 1)
    compare(Api.nextVolume(0.02, -0.1), 0)
    verify(Api.shouldRememberVolume(0.05))
    verify(!Api.shouldRememberVolume(0.001))
    compare(Api.unmuteVolume(0.4), 0.4)
    compare(Api.unmuteVolume(0), 0.05)
    compare(Api.seekPosition(10, 10, 183), 20)
    compare(Api.seekPosition(180, 10, 183), 183)
    compare(Api.seekPosition(5, -10, 183), 0)
    compare(Api.seekPosition(40, 10, 0), 50)
  }

  function test_volumeFlushInterval_slowsDownForNetworkBackends() {
    compare(Api.volumeFlushInterval("local"), Api.VOLUME_FLUSH_MS)
    compare(Api.volumeFlushInterval("remote"), Api.VOLUME_FLUSH_REMOTE_MS)
    compare(Api.volumeFlushInterval("sonos"), Api.VOLUME_FLUSH_SONOS_MS)
    compare(Api.volumeFlushInterval("SONOS"), Api.VOLUME_FLUSH_SONOS_MS)
    compare(Api.volumeFlushInterval(""), Api.VOLUME_FLUSH_MS)
    compare(Api.volumeFlushInterval(null), Api.VOLUME_FLUSH_MS)
    compare(Api.volumeFlushInterval("unknown"), Api.VOLUME_FLUSH_MS)
    verify(Api.VOLUME_FLUSH_REMOTE_MS > Api.VOLUME_FLUSH_SONOS_MS)
    verify(Api.VOLUME_FLUSH_SONOS_MS > Api.VOLUME_FLUSH_MS)
  }

  function test_sonosPlayModeCarriesShuffleAndRepeatBothWays() {
    // Bare SHUFFLE also repeats the queue; shuffle alone is SHUFFLE_NOREPEAT.
    var modes = [
      ["NORMAL", false, "off"],
      ["REPEAT_ALL", false, "context"],
      ["REPEAT_ONE", false, "track"],
      ["SHUFFLE_NOREPEAT", true, "off"],
      ["SHUFFLE", true, "context"],
      ["SHUFFLE_REPEAT_ONE", true, "track"]
    ]
    for (var i = 0; i < modes.length; i++) {
      var mode = modes[i]
      compare(Api.sonosPlayMode(mode[2], mode[1]), mode[0], mode[0])
      compare(Api.sonosPlayModeState(mode[0]),
        { shuffle: mode[1], repeatMode: mode[2] }, mode[0])
    }
    compare(Api.sonosPlayModeState("shuffle_repeat_one"),
      { shuffle: true, repeatMode: "track" })
    compare(Api.sonosPlayModeState("PARTY"), null)
  }

  function test_pendingSliderVolumeHoldsUntilPlayerAcknowledgesIt() {
    var pending = { slider: 0.55, expiresAt: 9000 }
    verify(Api.pendingSliderVolumeShouldHold(0.5, pending, 2000))
    verify(!Api.pendingSliderVolumeShouldHold(0.55, pending, 2000))
    verify(!Api.pendingSliderVolumeShouldHold(0.5, pending, 9000))
    verify(!Api.pendingSliderVolumeShouldHold(0.5, null, 2000))
    compare(Api.SEARCH_DEBOUNCE_MS, 300)
    compare(Api.SEARCH_REQUEST_TIMEOUT_MS, 8000)
    compare(Api.VOLUME_FLUSH_MS, 80)
  }

  function test_recentContextPlayTimes_keepsTheLatestPlayPerContext() {
    var payload = { items: [
      { played_at: "2026-09-06T22:26:58.502Z",
        context: { uri: "spotify:playlist:a", type: "playlist" } },
      { played_at: "2026-09-06T20:00:00.000Z",
        context: { uri: "spotify:playlist:a", type: "playlist" } },
      { played_at: "2026-09-06T21:00:00.000Z",
        context: { uri: "spotify:album:b", type: "album" } }
    ] }
    var out = Api.recentContextPlayTimes(payload)
    verify(out["spotify:playlist:a"] > out["spotify:album:b"],
      "the newest play for a context wins")
  }

  function test_recentContextPlayTimes_skipsPlaysWithoutAContext() {
    var out = Api.recentContextPlayTimes({ items: [
      { played_at: "2026-09-06T22:00:00.000Z", context: null },
      { played_at: "2026-09-06T22:00:00.000Z" }
    ] })
    compare(Object.keys(out).length, 0)
  }

  function test_recentContextPlayTimes_toleratesJunk() {
    compare(Object.keys(Api.recentContextPlayTimes(null)).length, 0)
    compare(Object.keys(Api.recentContextPlayTimes({})).length, 0)
    compare(Object.keys(Api.recentContextPlayTimes({ items: "no" })).length, 0)
  }

  // Spotify only hands us the last 50 plays, but top tracks and top artists
  // reveal what has actually been listened to over roughly four weeks. Those
  // count as a play inside that window, dated at the far edge of it so a
  // genuinely newer save still wins.
  // Every top-list item used to get the same timestamp, so they all tied and
  // fell back to library order — which visibly clumped artists together. Spread
  // them across the window by rank so they interleave with dated items.
  function test_recentListenWindow_spreadsItemsByRank() {
    var now = 100000000000
    var out = Api.recentListenWindow({
      items: [
        { album: { uri: "spotify:album:first" } },
        { album: { uri: "spotify:album:second" } },
        { album: { uri: "spotify:album:third" } }
      ]
    }, null, now, 28)
    verify(out["spotify:album:first"] > out["spotify:album:second"],
      "a higher ranked album reads as more recent")
    verify(out["spotify:album:second"] > out["spotify:album:third"])
  }

  // Even the top of the list stays below genuinely fresh activity, because the
  // rank tells us how much something was played, not exactly when.
  function test_recentListenWindow_staysBelowTodaysActivity() {
    var now = 100000000000
    var day = 24 * 3600 * 1000
    var out = Api.recentListenWindow({
      items: [{ album: { uri: "spotify:album:top" } }]
    }, null, now, 28)
    verify(out["spotify:album:top"] <= now - 7 * day,
      "the freshest listening signal is still at least a week old")
    verify(out["spotify:album:top"] >= now - 28 * day)
  }

  function test_recentListenWindow_rankBothTracksAndArtists() {
    var out = Api.recentListenWindow(
      { items: [{ album: { uri: "spotify:album:a" } }] },
      { items: [{ uri: "spotify:artist:b" }] }, 100000000000, 28)
    verify(out["spotify:album:a"] > 0)
    verify(out["spotify:artist:b"] > 0)
  }

  function test_recentListenWindow_toleratesJunk() {
    compare(Object.keys(Api.recentListenWindow(null, null, 0, 28)).length, 0)
    compare(Object.keys(Api.recentListenWindow({}, {}, 0, 28)).length, 0)
    compare(Object.keys(Api.recentListenWindow(
      { items: [{ album: null }, {}] }, { items: [{}] }, 1, 28)).length, 0)
  }

  function test_mergedPlayTimes_prefersTheNewerSignal() {
    var exact = { "a": 500 }
    var window = { "a": 100, "b": 100 }
    var out = Api.mergedPlayTimes(exact, ({}), window)
    compare(Api.playTimeOf(out["a"]), 500, "a precise play beats the window estimate")
    compare(Api.playTimeOf(out["b"]), 100)
  }

  function test_librarySortModes_areTheFourWeSupport() {
    compare(Api.librarySortModes(), ["library", "recent", "added", "alpha"])
    compare(Api.normalizedLibrarySort("alpha"), "alpha")
    compare(Api.normalizedLibrarySort("nonsense"), "library")
    compare(Api.normalizedLibrarySort(null), "library")
  }

  function test_libraryViewModes_areTheFourWeSupport() {
    compare(Api.libraryViewModes(),
      ["compact-list", "list", "compact-grid", "grid"])
    compare(Api.normalizedLibraryView("grid"), "grid")
    compare(Api.normalizedLibraryView("nonsense"), "list")
  }

  readonly property var sortFixture: [
    { uri: "spotify:playlist:b", name: "Beta", addedAt: 0 },
    { uri: "spotify:album:a", name: "alpha", addedAt: 3000 },
    { uri: "spotify:artist:c", name: "Gamma", addedAt: 1000 }
  ]

  function test_librarySort_libraryKeepsSpotifysOwnOrder() {
    var out = Api.sortedLibraryItems(sortFixture, "library", ({}), [])
    compare([out[0].name, out[1].name, out[2].name], ["Beta", "alpha", "Gamma"])
  }

  function test_librarySort_alphaIgnoresCase() {
    var out = Api.sortedLibraryItems(sortFixture, "alpha", ({}), [])
    compare([out[0].name, out[1].name, out[2].name], ["alpha", "Beta", "Gamma"])
  }

  function test_librarySort_addedPutsNewestFirst() {
    var out = Api.sortedLibraryItems(sortFixture, "added", ({}), [])
    compare([out[0].name, out[1].name], ["alpha", "Gamma"])
  }

  // Playlists and artists carry no added date, so they must fall to the bottom
  // in library order rather than be interleaved as if they were ancient.
  function test_librarySort_addedKeepsUndatedItemsInLibraryOrderAtTheEnd() {
    var items = [
      { uri: "u:1", name: "No date one" },
      { uri: "u:2", name: "Dated", addedAt: 500 },
      { uri: "u:3", name: "No date two" }
    ]
    var out = Api.sortedLibraryItems(items, "added", ({}), [])
    compare([out[0].name, out[1].name, out[2].name],
      ["Dated", "No date one", "No date two"])
  }

  function test_librarySort_recentUsesPlayTimesThenLibraryOrder() {
    var played = { "spotify:artist:c": 900, "spotify:playlist:b": 100 }
    var out = Api.sortedLibraryItems(sortFixture, "recent", played, [])
    compare([out[0].name, out[1].name],
      ["alpha", "Gamma"], "a newer save outranks an older play")
  }

  // Spotify's own Recents is last-touched, not last-played: a freshly saved
  // album outranks a playlist played a while ago. Rank on whichever is newer.
  function test_librarySort_recentTreatsSavingAsInteraction() {
    var items = [
      { uri: "u:played", name: "Played", addedAt: 0 },
      { uri: "u:saved", name: "Saved", addedAt: 5000 },
      { uri: "u:stale", name: "Stale" }
    ]
    var out = Api.sortedLibraryItems(items, "recent", { "u:played": 1000 }, [])
    compare([out[0].name, out[1].name, out[2].name],
      ["Saved", "Played", "Stale"])
  }

  // The service stores added_at exactly as Spotify sends it, an ISO string,
  // so the sort has to parse rather than assume a number.
  function test_librarySort_understandsIsoAddedDates() {
    var items = [
      { uri: "u:old", name: "Older", addedAt: "2026-08-10T00:00:00Z" },
      { uri: "u:new", name: "Newer", addedAt: "2026-09-06T19:06:40Z" },
      { uri: "u:none", name: "Undated", addedAt: "" }
    ]
    var byAdded = Api.sortedLibraryItems(items, "added", ({}), [])
    compare([byAdded[0].name, byAdded[1].name, byAdded[2].name],
      ["Newer", "Older", "Undated"])
    var byRecent = Api.sortedLibraryItems(items, "recent", ({}), [])
    compare([byRecent[0].name, byRecent[1].name], ["Newer", "Older"])
  }

  function test_librarySort_recentPrefersAPlayOverAnOlderSave() {
    var items = [
      { uri: "u:a", name: "Saved long ago", addedAt: 100 },
      { uri: "u:b", name: "Played just now", addedAt: 50 }
    ]
    var out = Api.sortedLibraryItems(items, "recent", { "u:b": 9000 }, [])
    compare([out[0].name, out[1].name], ["Played just now", "Saved long ago"])
  }

  // Concurrency alone still lets background work fire in a burst. Spacing the
  // dispatches is what keeps a cold start under Spotify's rate limit.
  function test_backgroundPacing_spacesDispatches() {
    compare(Api.backgroundStartDelay(0, 1000, 500), 0, "first one goes now")
    compare(Api.backgroundStartDelay(1000, 1000, 500), 500, "too soon, wait")
    compare(Api.backgroundStartDelay(1000, 1300, 500), 200)
    compare(Api.backgroundStartDelay(1000, 1500, 500), 0, "spacing satisfied")
    compare(Api.backgroundStartDelay(1000, 9000, 500), 0)
  }

  // The library index can wait a few seconds. Whatever someone just opened
  // should have the whole budget until it has had a moment to load.
  function test_backgroundStandsAsideAfterSomethingIsOpened() {
    compare(Api.backgroundDispatchDelay(0, 9500, 10000, 500), 2500,
      "opened half a second ago, so background holds off")
    compare(Api.backgroundDispatchDelay(0, 6000, 10000, 500), 0,
      "the moment has passed")
    compare(Api.backgroundDispatchDelay(9800, 0, 10000, 500), 300,
      "its own spacing still applies")
    compare(Api.backgroundDispatchDelay(9800, 9500, 10000, 500), 2500,
      "whichever wait is longer wins")
    compare(Api.backgroundDispatchDelay(0, 0, 10000, 500), 0)
  }

  // One early try is worth it in case the refusal has slack in it. Five in a
  // row just spends the retries and shows an error instead of the page.
  function test_openedPageGetsOneEarlyTryThenWaitsItsTurn() {
    var opened = { method: "GET", priority: "interactive", rateLimitRetries: 0 }
    verify(Api.jobMayRunDuringCooldown(opened, false))
    verify(!Api.jobMayRunDuringCooldown(opened, true),
      "one try per refusal, however many pages are waiting")
    verify(!Api.jobMayRunDuringCooldown(
      { method: "GET", priority: "interactive", rateLimitRetries: 1 }, false),
      "refused once, so it stops pushing")
    verify(!Api.jobMayRunDuringCooldown({ method: "GET" }, false),
      "ordinary work waits")
    verify(Api.jobMayRunDuringCooldown({ method: "PUT" }, false),
      "a button someone pressed is not background")
    verify(!Api.jobMayRunDuringCooldown(null, false))
  }

  // A personal client id has its own quota but loses the catalog endpoints a
  // grandfathered app still reaches, so what it refuses is tried once through
  // the shared one.
  function test_sharedClientFallback_onlyForRefusalsItCanAnswer() {
    var catalog = "/artists/abc/related-artists"
    verify(Api.shouldFallBackToSharedClient(403, false, true, "GET", catalog))
    verify(Api.shouldFallBackToSharedClient(400, false, true, "GET", catalog),
      "catalog refusals arrive as a bogus parameter error")
    verify(Api.shouldFallBackToSharedClient(404, false, true, "GET", catalog))

    verify(!Api.shouldFallBackToSharedClient(401, false, true, "GET", catalog),
      "a token to refresh, not a permission problem")
    verify(!Api.shouldFallBackToSharedClient(429, false, true, "GET", catalog),
      "slow down rather than spend someone else's quota")
    verify(!Api.shouldFallBackToSharedClient(200, false, true, "GET", catalog))
    verify(!Api.shouldFallBackToSharedClient(500, false, true, "GET", catalog))

    verify(!Api.shouldFallBackToSharedClient(403, true, true, "GET", catalog),
      "only once")
    verify(!Api.shouldFallBackToSharedClient(403, false, false, "GET", catalog),
      "nothing to fall back to")
  }

  // The shared quota is the thing we are trying to stop spending, so only the
  // requests a personal client genuinely cannot answer are sent to it.
  function test_sharedClientFallback_staysOffAnythingItCannotHelpWith() {
    verify(!Api.shouldFallBackToSharedClient(404, false, true, "PUT",
      "/me/player/play"), "never repeat something that changes state")
    verify(!Api.shouldFallBackToSharedClient(403, false, true, "POST",
      "/playlists/abc/tracks"))
    verify(!Api.shouldFallBackToSharedClient(400, false, true, "DELETE",
      "/playlists/abc/tracks"))

    verify(!Api.shouldFallBackToSharedClient(403, false, true, "GET",
      "/me/tracks"), "your own library reads fine on your own client")
    verify(!Api.shouldFallBackToSharedClient(404, false, true, "GET",
      "https://api.spotify.com/v1/me/albums?offset=50"),
      "including when it arrives as a paging cursor")

    verify(Api.shouldFallBackToSharedClient(403, false, true, "GET",
      "https://api.spotify.com/v1/artists/abc/albums"),
      "a catalog cursor still falls back")
    verify(Api.shouldFallBackToSharedClient(400, false, true, "GET", "/tracks"))
    verify(Api.shouldFallBackToSharedClient(403, false, true, "GET",
      "/browse/new-releases"))
  }

  // Spotify's own playlists arrive in a list of their own, so they replace the old copies.
  function test_withSpotifyPlaylists_replacesOnlySpotifysOwn() {
    var mine = { id: "m", uri: "spotify:playlist:m", ownerId: "jeremy" }
    var stale = { id: "r", uri: "spotify:playlist:r", ownerId: "spotify", name: "old" }
    var unfollowed = { id: "u", uri: "spotify:playlist:u", ownerId: "spotify" }
    var fresh = { id: "r", uri: "spotify:playlist:r", ownerId: "spotify", name: "new" }
    var merged = Api.withSpotifyPlaylists([mine, stale, unfollowed], [fresh])
    compare(merged.map(function(p) { return p.id + ":" + (p.name || "") }),
      ["m:", "r:new"])
  }

  // A refusal aimed at the library crawl must not freeze the page someone just
  // opened. Only their own request being refused holds them back.
  function test_apiCooldown_keepsBackgroundRefusalsOffTheOpenPage() {
    var opened = { method: "GET", priority: "interactive" }
    var crawl = { method: "GET", priority: "background" }
    var poll = { method: "GET" }
    var save = { method: "PUT" }

    compare(Api.jobCooldownMs(opened, 1000, 20000, 0), 0,
      "the page someone opened goes now")
    compare(Api.jobCooldownMs(save, 1000, 20000, 0), 0,
      "so does something they just clicked")
    compare(Api.jobCooldownMs(crawl, 1000, 20000, 0), 19000, "the crawl waits")
    compare(Api.jobCooldownMs(poll, 1000, 20000, 0), 19000,
      "so does polling, which nobody is waiting on")

    compare(Api.jobCooldownMs(opened, 1000, 20000, 6000), 5000,
      "their own refusal does hold them back")
    compare(Api.jobCooldownMs(null, 1000, 20000, 6000), 0)
  }

  // A refusal often comes from the shared budget rather than from us, and it
  // can last twenty seconds. Waiting all of that out leaves an opened page
  // blank, so a page someone is watching pauses briefly and then tries.
  function test_openedPageWaitsAMomentRatherThanTheWholeCooldown() {
    compare(Api.foregroundCooldownMs(1000, 21000, 1000, 1500), 1500,
      "a pause, not nothing")
    compare(Api.foregroundCooldownMs(2000, 21000, 1000, 1500), 500)
    compare(Api.foregroundCooldownMs(2500, 21000, 1000, 1500), 0,
      "then it goes, even though Spotify is still cross")
    compare(Api.foregroundCooldownMs(1000, 1200, 1000, 1500), 200,
      "a short pause is honoured in full")
    compare(Api.foregroundCooldownMs(30000, 21000, 1000, 1500), 0,
      "no pause left to serve")
  }

  // The budget is shared with every other app using this client ID, so it
  // cannot be known ahead of time. Each refusal costs about twenty seconds of
  // everything stopping, so the gap only ever widens within a run.
  function test_backgroundSpacing_widensWithEveryRefusal() {
    compare(Api.backgroundSpacingForRefusals(0), 500)
    compare(Api.backgroundSpacingForRefusals(1), 1000)
    compare(Api.backgroundSpacingForRefusals(2), 2000)
    compare(Api.backgroundSpacingForRefusals(4), 8000)
    compare(Api.backgroundSpacingForRefusals(9), 8000, "there is a ceiling")
    compare(Api.backgroundSpacingForRefusals(-3), 500, "nonsense starts over")
  }

  // Reading every liked song is a hundred requests. Starting that over on each
  // launch is a bill the shared budget cannot pay.
  function test_savedTrackCrawl_resumesWhereItStopped() {
    var text = Api.encodePlayHistory({
      savedTracksOffset: 2500, savedTracksNewest: 1700 })
    var back = Api.parsePlayHistoryRecord(text)
    compare(back.savedTracksOffset, 2500)
    compare(back.savedTracksNewest, 1700,
      "the newest date seen so far survives, or the mark cannot move")
    compare(Api.parsePlayHistoryRecord("{}").savedTracksOffset, 0,
      "an unknown record starts at the beginning")
  }

  // Refetching the whole library on every launch is ~30 requests nobody needs.
  function test_libraryCache_isTrustedWhileItIsStillFresh() {
    var hour = 3600000
    verify(Api.libraryCacheIsFresh(1000, 1000 + hour, 6 * hour))
    verify(!Api.libraryCacheIsFresh(1000, 1000 + 7 * hour, 6 * hour))
    verify(!Api.libraryCacheIsFresh(0, 1000, 6 * hour), "no stamp means refetch")
    verify(!Api.libraryCacheIsFresh(9999999, 1000, 6 * hour),
      "a stamp from the future is not trusted")
  }

  function test_libraryCache_carriesWhenItWasFetched() {
    var text = Api.encodeLibraryCache([{ uri: "p" }], [], [], [], 4242)
    compare(Api.parseLibraryCache(text).fetchedAt, 4242)
    compare(Api.parseLibraryCache("nonsense").fetchedAt, 0)
  }

  // Ordering the queue is not enough: background work can still hold every
  // slot, so some are kept back for whatever the person does next.
  function test_backgroundQuota_leavesSlotsForForegroundWork() {
    compare(Api.backgroundInFlightLimit(4), 2,
      "background stays narrow so the whole burst does not trip Spotify's limit")
    compare(Api.backgroundInFlightLimit(2), 1)
    compare(Api.backgroundInFlightLimit(1), 1, "never zero, or nothing loads")
  }

  function test_dequeue_skipsBackgroundWhenItsQuotaIsFull() {
    var queue = [
      { id: "bg1", method: "GET", priority: "background" },
      { id: "bg2", method: "GET", priority: "background" },
      { id: "page", method: "GET" }
    ]
    compare(Api.dequeueApiJob(queue, true).job.id, "bg1", "normally first wins")
    compare(queue.length, 3, "the caller's queue is left alone")

    var limited = Api.dequeueApiJob(queue, false)
    compare(limited.job.id, "page", "background is passed over when full")
    compare(limited.queue.length, 2)
    compare(limited.queue[0].id, "bg1", "the skipped work stays queued")

    var onlyBackground = Api.dequeueApiJob([
      { id: "bg", method: "GET", priority: "background" }], false)
    compare(onlyBackground.job, null, "nothing runnable rather than a wrong pick")
  }

  // A single "finished in N ms" hides where the time went. Split it so a slow
  // call can be blamed on the queue, the token refresh, or the network.
  function test_requestTimingLine_showsWhereTheTimeWent() {
    var line = Api.requestTimingLine("GET", "/artists/abc",
      { queuedMs: 120, authMs: 22600, wireMs: 264 },
      { inFlight: 6, background: 4, queued: 3, priority: "background" })
    verify(line.indexOf("GET /artists/abc") >= 0)
    verify(line.indexOf("22984 ms") >= 0, "the total is the sum")
    verify(line.indexOf("queue 120") >= 0)
    verify(line.indexOf("auth 22600") >= 0)
    verify(line.indexOf("wire 264") >= 0)
    verify(line.indexOf("in-flight 6") >= 0)
    verify(line.indexOf("bg 4") >= 0, "background slots in use are visible too")
    verify(line.indexOf("queued 3") >= 0)
    verify(line.indexOf("background") >= 0)
  }

  function test_requestTimingLine_copesWithMissingParts() {
    var line = Api.requestTimingLine("GET", "/me", ({}), ({}))
    verify(line.indexOf("0 ms") >= 0)
    verify(line.indexOf("normal") >= 0, "no priority reads as normal")
  }

  function test_requestTimingLine_hidesSecrets() {
    var line = Api.requestTimingLine("GET", "/me?access_token=abc123",
      { wireMs: 1 }, ({}))
    verify(line.indexOf("abc123") < 0)
  }

  // The sidebar mixes four kinds of thing, so it can be narrowed to one.
  function test_libraryTypeFilter_narrowsToOneKind() {
    var rows = [
      { uri: "p", type: "playlist", name: "P" },
      { uri: "a", type: "artist", name: "A" },
      { uri: "b", type: "album", name: "B" },
      { uri: "s", type: "show", name: "S" }
    ]
    compare(Api.filterLibraryType(rows, "all").length, 4)
    compare(Api.filterLibraryType(rows, "playlist").length, 1)
    compare(Api.filterLibraryType(rows, "playlist")[0].name, "P")
    compare(Api.filterLibraryType(rows, "show")[0].name, "S")
    compare(Api.filterLibraryType(rows, "nonsense").length, 4,
      "an unknown filter shows everything rather than nothing")
    compare(Api.filterLibraryType(null, "artist").length, 0)
  }

  function test_libraryTypeFilter_normalizesAndCycles() {
    compare(Api.normalizedLibraryFilter("album"), "album")
    compare(Api.normalizedLibraryFilter("bogus"), "all")
    compare(Api.normalizedLibraryFilter(undefined), "all")
    compare(Api.libraryFilterModes().length, 5)
    compare(Api.libraryFilterModes()[0], "all")
  }

  // Spotify has no artist bio, but it does say how many followers and which
  // genres, which is worth showing.
  function test_artist_carriesFollowersAndGenres() {
    var artist = Api.normalizeContext({ type: "artist", id: "a", uri: "ar:a",
      name: "Someone", followers: { total: 11745879 },
      genres: ["french house", "electronic"], popularity: 84 }, 96)
    compare(artist.followers, 11745879)
    compare(artist.genres.join(", "), "french house, electronic")
    compare(artist.popularity, 84)
  }

  function test_artistSubtitle_readsFollowersAndGenres() {
    compare(Api.artistDetailLine({ followers: 11745879,
      genres: ["french house", "electronic", "electro", "extra"] }),
      "11.7M followers · french house, electronic, electro")
    compare(Api.artistDetailLine({ followers: 1200, genres: [] }), "1,200 followers")
    compare(Api.artistDetailLine({ followers: 0, genres: ["ambient"] }), "ambient")
    compare(Api.artistDetailLine(null), "")
  }

  // Some builds hand back a number already grouped for the locale, and
  // grouping that again gives "1,,200".
  function test_thousands_groupsDigitsWhateverTheEngineHandsBack() {
    compare(Api.groupedDigits("1200"), "1,200")
    compare(Api.groupedDigits("1,200"), "1,200")
    compare(Api.groupedDigits("1 200"), "1,200")
    compare(Api.groupedDigits("999"), "999")
    compare(Api.groupedDigits("1234567"), "1,234,567")
    compare(Api.groupedDigits(""), "0")
  }

  function test_followerCount_readsAtAGlance() {
    compare(Api.compactCount(999), "999")
    compare(Api.compactCount(1200), "1,200")
    compare(Api.compactCount(11745879), "11.7M")
    compare(Api.compactCount(1500000000), "1.5B")
    compare(Api.compactCount(45300), "45.3K")
  }

  // The play record keeps only the newest time per thing, so day counts are
  // tallied separately as plays arrive, with a watermark to avoid double
  // counting the same play on the next fetch.
  function test_playDays_countsEachPlayOnce() {
    var page = { items: [
      { played_at: "2026-09-06T19:56:00Z" },
      { played_at: "2026-09-06T18:01:00Z" },
      { played_at: "2026-09-05T16:30:00Z" }
    ] }
    var first = Api.countedPlayDays(page, 0)
    compare(first.newest, Date.parse("2026-09-06T19:56:00Z"))
    var total = 0
    for (var k in first.days) total += first.days[k]
    compare(total, 3)

    var again = Api.countedPlayDays(page, first.newest)
    compare(JSON.stringify(again.days), "{}", "nothing is counted twice")
  }

  function test_playDays_mergeAddsRatherThanReplaces() {
    var merged = Api.mergeDayCounts({ "2026-09-06": 3 }, { "2026-09-06": 2, "2026-09-07": 1 })
    compare(merged["2026-09-06"], 5)
    compare(merged["2026-09-07"], 1)
    compare(JSON.stringify(Api.mergeDayCounts(null, null)), "{}")
  }

  // The heatmap is a grid of whole weeks ending on the week you are in.
  function test_heatmap_buildsWholeWeeksEndingToday() {
    var end = Date.parse("2026-09-09T12:00:00Z")
    var grid = Api.heatmapWeeks({ }, end, 4)
    compare(grid.length, 4)
    compare(grid[0].length, 7, "every column is a full week")
    for (var w = 0; w < grid.length; w++)
      for (var d = 0; d < 7; d++)
        compare(grid[w][d].count, 0)
  }

  function test_heatmap_shadesByHowMuchYouListened() {
    compare(Api.heatmapLevel(0), 0)
    compare(Api.heatmapLevel(1), 1)
    compare(Api.heatmapLevel(3), 2)
    compare(Api.heatmapLevel(8), 3)
    compare(Api.heatmapLevel(40), 4)
  }

  function test_heatmap_putsCountsOnTheRightDay() {
    var days = {}
    days[Api.playDayKey(Date.parse("2026-09-08T10:00:00"))] = 5
    var grid = Api.heatmapWeeks(days, Date.parse("2026-09-09T12:00:00"), 3)
    var found = 0
    for (var w = 0; w < grid.length; w++)
      for (var d = 0; d < 7; d++)
        if (grid[w][d].count === 5) found++
    compare(found, 1, "the day with plays is the only shaded cell")
  }

  // A finished episode should start again from the beginning, not from its end.
  function test_podcastResume_ignoresAFinishedEpisode() {
    compare(Api.podcastResumeMs({ resumeMs: 42000, fullyPlayed: false }), 42000)
    compare(Api.podcastResumeMs({ resumeMs: 42000, fullyPlayed: true }), 0)
    compare(Api.podcastResumeMs({ resumeMs: 0 }), 0)
    compare(Api.podcastResumeMs(null), 0)
  }

  function test_playbackBody_doesNotResumeAFinishedEpisode() {
    var done = { kind: "item", type: "episode", uri: "spotify:episode:e",
      resumeMs: 42000, fullyPlayed: true }
    compare(Api.playbackBody(done, [], "").position_ms, undefined)
    var part = { kind: "item", type: "episode", uri: "spotify:episode:e",
      resumeMs: 42000, fullyPlayed: false }
    compare(Api.playbackBody(part, [], "").position_ms, 42000)
  }

  // Podcast jumps clamp to the episode rather than running off either end.
  function test_podcastSkip_staysInsideTheEpisode() {
    compare(Api.skipToSeconds(100, 30, 600), 130)
    compare(Api.skipToSeconds(100, -15, 600), 85)
    compare(Api.skipToSeconds(5, -15, 600), 0, "never before the start")
    compare(Api.skipToSeconds(590, 30, 600), 600, "never past the end")
    compare(Api.skipToSeconds(100, 30, 0), 130, "unknown length does not clamp")
  }

  // Every column can be reversed, the way a playlist sorts in the real client.
  function test_filteredSorted_reversesAnyColumn() {
    var rows = [
      { name: "b", subtitle: "z", durationMs: 300 },
      { name: "a", subtitle: "y", durationMs: 100 },
      { name: "c", subtitle: "x", durationMs: 200 }
    ]
    compare(Api.filteredSorted(rows, "", "name", false).map(function(i) {
      return i.name }).join(""), "abc")
    compare(Api.filteredSorted(rows, "", "name", true).map(function(i) {
      return i.name }).join(""), "cba")
    compare(Api.filteredSorted(rows, "", "duration", false).map(function(i) {
      return i.durationMs }).join(","), "100,200,300")
    compare(Api.filteredSorted(rows, "", "duration", true).map(function(i) {
      return i.durationMs }).join(","), "300,200,100")
  }

  function test_filteredSorted_datesStillDefaultToNewestFirst() {
    var rows = [{ name: "old", addedAt: "2020-01-01" }, { name: "new", addedAt: "2024-01-01" }]
    compare(Api.filteredSorted(rows, "", "date", false)[0].name, "new")
    compare(Api.filteredSorted(rows, "", "date", true)[0].name, "old")
    compare(Api.filteredSorted(rows, "", "date-asc", false)[0].name, "old",
      "the old key still means oldest first")
  }

  function test_filteredSorted_keepsUndatedRowsLastBothWays() {
    var rows = [{ name: "none" }, { name: "dated", addedAt: "2024-01-01" }]
    compare(Api.filteredSorted(rows, "", "date", false)[0].name, "dated")
    compare(Api.filteredSorted(rows, "", "date", true)[0].name, "dated")
  }

  // Artwork is fetched from Spotify's CDN on every launch. A stable name per
  // URL lets it be kept on disk instead.
  function test_artworkCache_namesAreStableAndSafe() {
    var a = Api.artworkCacheName("https://i.scdn.co/image/ab67616d0000b273abc")
    var b = Api.artworkCacheName("https://i.scdn.co/image/ab67616d0000b273abc")
    var c = Api.artworkCacheName("https://i.scdn.co/image/ab67616d0000b273abd")
    compare(a, b, "the same url always gives the same file name")
    verify(a !== c)
    verify(/^[0-9a-z]+\.img$/.test(a), "safe to use as a file name")
    compare(Api.artworkCacheName(""), "")
    compare(Api.artworkCacheName(null), "")
  }

  function test_artworkCache_collectsTheUrlsWorthKeeping() {
    var one = "https://i.scdn.co/image/one"
    var two = "https://i.scdn.co/image/two"
    var items = [{ imageUrl: one }, { imageUrl: "" }, null, { imageUrl: two },
      { imageUrl: one }]
    compare(Api.artworkUrls(items, ({})).join(","), one + "," + two,
      "each url once")
    var have = ({})
    have[one] = true
    compare(Api.artworkUrls(items, have).join(","), two,
      "already-kept artwork is not fetched again")
    compare(Api.artworkUrls(null, ({})).length, 0)
  }

  // Library crawling must never make a page you just opened wait.
  function test_apiPriority_backgroundWorkYieldsToAnythingYouAskedFor() {
    compare(Api.apiJobPriority({ method: "GET", priority: "background" }), -1)
    compare(Api.apiJobPriority({ method: "GET" }), 0)
    compare(Api.apiJobPriority({ method: "GET", priority: "interactive" }), 1)
    compare(Api.apiJobPriority({ method: "PUT", priority: "background" }), 2,
      "a mutation is still a mutation")

    var queue = Api.enqueueApiJob([], { method: "GET", id: "crawl", priority: "background" })
    queue = Api.enqueueApiJob(queue, { method: "GET", id: "crawl2", priority: "background" })
    queue = Api.enqueueApiJob(queue, { method: "GET", id: "artist" })
    compare(queue[0].id, "artist", "opening a page jumps every background job")
    compare(queue[1].id, "crawl")
    compare(queue[2].id, "crawl2")
  }

  // Searching by artist name returns other artists' work, so it had to be
  // filtered and re-paged. Spotify answers both questions directly.
  function test_artistCatalog_usesTheDirectEndpointsInsteadOfSearch() {
    var artist = { id: "a1", type: "artist", name: "Someone" }
    compare(Api.artistTopTracksRequest(artist).path, "/artists/a1/top-tracks")
    // Spotify takes the country off the signed-in account. "from_token" is an
    // old spelling of that and is no longer a country code it accepts.
    compare(Api.artistTopTracksRequest(artist).query, null)
    compare(Api.artistTopTracksRequest(null), null)

    var albums = Api.artistAlbumsRequest(artist)
    compare(albums.path, "/artists/a1/albums")
    compare(albums.query.market, undefined)
    compare(albums.query.limit, 50)
    verify(albums.query.include_groups.indexOf("album") >= 0)
    verify(albums.query.include_groups.indexOf("single") >= 0)
  }

  function test_artistCatalog_readsTheTopTracksReply() {
    var payload = { tracks: [
      { id: "t1", type: "track", name: "One", uri: "spotify:track:t1",
        duration_ms: 1000, artists: [{ name: "Someone", uri: "ar:1" }],
        album: { name: "Album", uri: "al:1", images: [] } }
    ] }
    var out = Api.normalizeArtistTopTracks(payload, 96)
    compare(out.length, 1)
    compare(out[0].name, "One")
    compare(JSON.stringify(Api.normalizeArtistTopTracks(null, 96)), "[]")
  }

  // Paging one request at a time is slow when the first reply already tells us
  // how many pages there are.
  function test_pageOffsets_askForEveryRemainingPageAtOnce() {
    compare(JSON.stringify(Api.pageOffsets(130, 50, 50)), "[50,100]")
    compare(JSON.stringify(Api.pageOffsets(50, 50, 50)), "[]", "one page is the whole thing")
    compare(JSON.stringify(Api.pageOffsets(0, 50, 0)), "[]")
    compare(Api.pageOffsets(9000, 50, 50).length, 40, "a runaway total is still bounded")
  }

  // A new field in the record cannot be filled by an incremental crawl, so an
  // older record has to be read from the top once.
  function test_playHistory_reReadsEverythingAfterTheRecordGrows() {
    var older = JSON.stringify({ version: 3, plays: {}, savedTracksThrough: 999 })
    compare(Api.parsePlayHistoryRecord(older).savedTracksThrough, 0,
      "an older record forgets its watermark so the crawl runs in full")
    var current = Api.encodePlayHistory({ savedTracksThrough: 999,
      likedByArtist: { "ar:a": ["t1"] } })
    compare(Api.parsePlayHistoryRecord(current).savedTracksThrough, 999)
    compare(Api.parsePlayHistoryRecord(current).likedByArtist["ar:a"].join(","), "t1")
  }

  // The sidebar is the same library every launch, so it is kept on disk and
  // shown before Spotify answers.
  function test_libraryCache_survivesARoundTrip() {
    var text = Api.encodeLibraryCache([{ uri: "p1" }], [{ uri: "al1" }],
      [{ uri: "ar1" }], [{ uri: "s1" }])
    var back = Api.parseLibraryCache(text)
    compare(back.playlists[0].uri, "p1")
    compare(back.savedAlbums[0].uri, "al1")
    compare(back.followedArtists[0].uri, "ar1")
    compare(back.savedShows[0].uri, "s1")
  }

  function test_libraryCache_ignoresRubbish() {
    var empty = Api.parseLibraryCache("not json")
    compare(empty.playlists.length, 0)
    compare(empty.savedAlbums.length, 0)
    compare(Api.parseLibraryCache('{"playlists":"nope"}').playlists.length, 0)
  }

  // The artist page grows a third column only when there is something to put
  // in it, and never squeezes a column below a usable width.
  function test_artistColumns_splitEvenlyAndKeepAFloor() {
    compare(Api.evenColumnWidth(620, 10, 3), 200)
    compare(Api.evenColumnWidth(310, 10, 2), 150)
    compare(Api.evenColumnWidth(10, 10, 3), 80, "never narrower than the floor")
    compare(Api.evenColumnWidth(620, 10, 0), 620)
  }

  // Spotify has no "my liked songs by this artist" endpoint, so the crawl that
  // already reads every liked song builds the index as it goes.
  function test_likedIndex_groupsLikedTrackIdsUnderEachArtist() {
    var page = { items: [
      { track: { id: "t1", artists: [{ uri: "ar:a" }, { uri: "ar:b" }] } },
      { track: { id: "t2", artists: [{ uri: "ar:a" }] } }
    ] }
    var out = Api.likedTrackIdsByArtist(page)
    compare(out["ar:a"].join(","), "t1,t2")
    compare(out["ar:b"].join(","), "t1")
  }

  function test_likedIndex_skipsRowsWithNoTrackOrNoArtist() {
    compare(JSON.stringify(Api.likedTrackIdsByArtist(null)), "{}")
    compare(JSON.stringify(Api.likedTrackIdsByArtist(
      { items: [{ track: { artists: [{ uri: "ar:a" }] } }, { track: { id: "t" } }] })), "{}")
  }

  function test_likedIndex_mergesWithoutDuplicatingOrGrowingForever() {
    var merged = Api.mergeLikedIndex({ "ar:a": ["t1", "t2"] },
      { "ar:a": ["t2", "t3"], "ar:b": ["t9"] }, 10)
    compare(merged["ar:a"].join(","), "t1,t2,t3", "already-known ids are not repeated")
    compare(merged["ar:b"].join(","), "t9")
    compare(Api.mergeLikedIndex({ "ar:a": ["t1", "t2", "t3"] }, ({}), 2)["ar:a"].join(","),
      "t1,t2", "the cap keeps the oldest known ids rather than churning")
  }

  function test_likedIndex_dropsATrackYouUnlike() {
    var out = Api.withoutLikedTrack({ "ar:a": ["t1", "t2"], "ar:b": ["t1"] }, "t1")
    compare(out["ar:a"].join(","), "t2")
    compare(out["ar:b"].length, 0)
  }

  function test_likedIndex_batchesIdsIntoRequestSizedGroups() {
    compare(JSON.stringify(Api.idBatches(["a", "b", "c"], 2)), '[["a","b"],["c"]]')
    compare(JSON.stringify(Api.idBatches([], 2)), "[]")
    compare(JSON.stringify(Api.idBatches(["a"], 0)), '[["a"]]')
  }

  // Playlists and artists carry no date of their own, so we work one out from
  // the rest of the library: a liked song, a saved album, a playlist edit.
  function test_touchDates_datesArtistsByTheNewestSongYouLiked() {
    var page = { items: [
      { added_at: "2020-01-01T00:00:00Z", track: { album: { uri: "spotify:album:old" },
        artists: [{ uri: "spotify:artist:a" }] } },
      { added_at: "2024-06-01T00:00:00Z", track: { album: { uri: "spotify:album:new" },
        artists: [{ uri: "spotify:artist:a" }, { uri: "spotify:artist:b" }] } }
    ] }
    var out = Api.touchDatesFromSavedTracks(page)
    compare(Api.playTimeOf(out["spotify:artist:a"]), Date.parse("2024-06-01T00:00:00Z"))
    compare(Api.playSourceOf(out["spotify:artist:a"]), "liked")
    compare(Api.playTimeOf(out["spotify:artist:b"]), Date.parse("2024-06-01T00:00:00Z"))
    compare(Api.playTimeOf(out["spotify:album:old"]), Date.parse("2020-01-01T00:00:00Z"))
  }

  function test_touchDates_datesArtistsByTheAlbumsYouSaved() {
    var page = { items: [{ added_at: "2023-03-03T00:00:00Z",
      album: { uri: "spotify:album:x", artists: [{ uri: "spotify:artist:c" }] } }] }
    var out = Api.touchDatesFromSavedAlbums(page)
    compare(Api.playTimeOf(out["spotify:artist:c"]), Date.parse("2023-03-03T00:00:00Z"))
    compare(Api.playSourceOf(out["spotify:artist:c"]), "saved")
  }

  function test_touchDates_ignoreRowsWithNoDateOrNoUri() {
    compare(JSON.stringify(Api.touchDatesFromSavedTracks(null)), "{}")
    compare(JSON.stringify(Api.touchDatesFromSavedAlbums({ items: [{ album: {} }] })), "{}")
    compare(JSON.stringify(Api.touchDatesFromSavedTracks(
      { items: [{ added_at: "nonsense", track: { artists: [{ uri: "u" }] } }] })), "{}")
  }

  // A played track also dates its album and everyone on it, not just the
  // playlist it came from.
  function test_recentPlays_dateTheAlbumAndArtistsToo() {
    var page = { items: [{ played_at: "2026-01-02T03:04:05Z",
      context: { uri: "spotify:playlist:p" },
      track: { album: { uri: "spotify:album:al" }, artists: [{ uri: "spotify:artist:ar" }] } }] }
    var out = Api.recentContextPlayTimes(page)
    var at = Date.parse("2026-01-02T03:04:05Z")
    compare(out["spotify:playlist:p"], at)
    compare(out["spotify:album:al"], at)
    compare(out["spotify:artist:ar"], at)
  }

  // Only playlists you own can be dated this way: a stranger editing their
  // playlist is not you touching it.
  function test_playlistEdit_onlyLooksAtPlaylistsYouOwn() {
    var mine = { id: "p1", uri: "spotify:playlist:p1", ownerId: "me", snapshotId: "s1", total: 40 }
    var theirs = { id: "p2", uri: "spotify:playlist:p2", ownerId: "you", snapshotId: "s2", total: 40 }
    var q = Api.playlistEditRequest(mine, "me", ({}))
    compare(q.path, "/playlists/p1/tracks")
    compare(q.query.offset, 39, "the last track added is the newest edit")
    compare(q.query.limit, 1)
    compare(Api.playlistEditRequest(theirs, "me", ({})), null)
    compare(Api.playlistEditRequest(mine, "me", { "p1": { snapshot: "s1", at: 5 } }), null,
      "an unchanged playlist is not asked about twice")
    compare(Api.playlistEditRequest({ id: "p3", ownerId: "me", total: 0 },
      "me", ({})), null, "an empty playlist has nothing to date")
  }

  function test_playlistEdit_readsTheDateOutOfTheReply() {
    compare(Api.playlistEditDate({ items: [{ added_at: "2024-03-23T21:13:24Z" }] }),
      Date.parse("2024-03-23T21:13:24Z"))
    compare(Api.playlistEditDate({ items: [] }), 0)
    compare(Api.playlistEditDate(null), 0)
  }

  // Liked songs come back newest first, so a watermark stops us re-reading
  // thousands of them on every launch.
  function test_savedTrackWatermark_stopsOnceWeReachWhatWeAlreadyHad() {
    var page = { items: [{ added_at: "2026-05-05T00:00:00Z" },
      { added_at: "2026-04-04T00:00:00Z" }] }
    compare(Api.newestAddedAt(page), Date.parse("2026-05-05T00:00:00Z"))
    compare(Api.pageReachesWatermark(page, Date.parse("2026-04-20T00:00:00Z")), true)
    compare(Api.pageReachesWatermark(page, Date.parse("2026-01-01T00:00:00Z")), false)
    compare(Api.pageReachesWatermark(page, 0), false)
  }

  // The watermark is what we had before this run started. Moving it as pages
  // arrive would stop the run on its own second page.
  function test_savedTrackCrawl_doesNotStopItselfOnFreshPages() {
    var page1 = { next: "u", items: [{ added_at: "2026-05-05T00:00:00Z" }] }
    var page2 = { next: "u", items: [{ added_at: "2026-04-04T00:00:00Z" }] }
    var run = Api.savedTrackCrawlStep(page1, 0, 0)
    compare(run.done, false)
    compare(run.nextOffset, 50)
    compare(run.newest, Date.parse("2026-05-05T00:00:00Z"))
    compare(Api.savedTrackCrawlStep(page2, 50, 0).done, false,
      "page one's own dates must not end the run")
  }

  function test_savedTrackCrawl_stopsAtWhatWeAlreadyHadOrTheLastPage() {
    var page = { next: "u", items: [{ added_at: "2026-04-04T00:00:00Z" }] }
    compare(Api.savedTrackCrawlStep(page, 50, Date.parse("2026-04-20T00:00:00Z")).done, true)
    compare(Api.savedTrackCrawlStep({ items: [] }, 50, 0).done, true, "no next page")
  }

  function test_libraryDates_preferARealPlayOverAnInferredDate() {
    var merged = Api.mergedPlayTimes({ "u": 500 },
      { "u": { at: 900, source: "liked" } }, ({}))
    compare(Api.playTimeOf(merged["u"]), 900, "the newer date wins whichever it is")
    compare(Api.playSourceOf(merged["u"]), "liked")

    var tie = Api.mergedPlayTimes({ "u": 900 }, { "u": { at: 900, source: "liked" } }, ({}))
    compare(Api.playSourceOf(tie["u"]), "played", "a real play settles a tie")
  }


  // Spotify only ever hands back the last 50 plays, so we keep our own running
  // record and add each fresh batch to it.
  function test_playHistory_keepsOlderPlaysSpotifyNoLongerReturns() {
    var stored = { "a": 100, "b": 200 }
    var fresh = { "b": 900, "c": 300 }
    var out = Api.mergePlayHistory(stored, fresh)
    compare(out["a"], 100, "a play Spotify has forgotten is still remembered")
    compare(out["b"], 900, "a newer play replaces the older one")
    compare(out["c"], 300)
  }

  function test_playHistory_neverGoesBackwards() {
    var out = Api.mergePlayHistory({ "a": 900 }, { "a": 100 })
    compare(out["a"], 900)
  }

  function test_playHistory_keepsEverythingItHasEverSeen() {
    var out = Api.mergePlayHistory({ "old": 1, "mid": 2 }, { "new": 3 })
    compare(out["old"], 1, "nothing is ever thrown away")
    compare(out["mid"], 2)
    compare(out["new"], 3)
  }

  function test_playHistory_ignoresJunkEntries() {
    var out = Api.mergePlayHistory({ "a": 0, "b": "nope", "c": 5 }, null)
    compare(out["a"], undefined)
    compare(out["b"], undefined)
    compare(out["c"], 5)
  }

  function test_playHistory_survivesAFileRoundTrip() {
    var text = Api.encodePlayHistory({ plays: { "a": 100 } })
    compare(Api.parsePlayHistory(text)["a"], 100)
    compare(JSON.stringify(Api.parsePlayHistory("not json")), "{}")
    compare(JSON.stringify(Api.parsePlayHistory("")), "{}")
    compare(JSON.stringify(Api.parsePlayHistory('{"plays":[1,2]}')), "{}")
  }

  function test_mergedPlayTimes_saysWhetherATimeWasMeasuredOrEstimated() {
    var merged = Api.mergedPlayTimes({ "a": 900 }, ({}), { "a": 100, "b": 200 })
    compare(Api.playTimeOf(merged["a"]), 900)
    compare(Api.playSourceOf(merged["a"]), "played")
    compare(Api.playTimeOf(merged["b"]), 200)
    compare(Api.playSourceOf(merged["b"]), "listened")
  }

  function test_librarySort_stillAcceptsPlainNumbersForPlayTimes() {
    var out = Api.sortedLibraryItems(sortFixture, "recent", { "spotify:playlist:b": 9000 }, [])
    compare(out[0].name, "Beta")
    compare(out[0].sortSource, "played")
  }

  function test_librarySort_marksEstimatedListensApart() {
    var merged = Api.mergedPlayTimes(({}), ({}), { "spotify:playlist:b": 9000 })
    var out = Api.sortedLibraryItems(sortFixture, "recent", merged, [])
    compare(out[0].name, "Beta")
    compare(out[0].sortSource, "listened")
  }


  // Each row carries the number it was ranked on, so the sidebar can show it.
  // Two rows sharing a date must not trade places between renders. The
  // comparator has to answer with library order, never with nothing.
  function test_librarySort_isDeterministicWhenDatesTie() {
    var tied = [
      { uri: "u:a", name: "A", addedAt: 5000 },
      { uri: "u:b", name: "B", addedAt: 5000 },
      { uri: "u:c", name: "C", addedAt: 5000 }
    ]
    var first = Api.sortedLibraryItems(tied, "added", ({}), [])
    compare(first.map(function(i) { return i.name }).join(","), "A,B,C")
    for (var pass = 0; pass < 5; pass++) {
      var again = Api.sortedLibraryItems(tied, "added", ({}), [])
      compare(again.map(function(i) { return i.name }).join(","), "A,B,C",
        "the same input always gives the same order")
    }
    compare(first[1].sortIndex, 1, "library position is part of the key")
  }

  function test_librarySort_tiedRecentsFallBackToLibraryOrderToo() {
    var tied = [{ uri: "u:a", name: "A" }, { uri: "u:b", name: "B" }]
    var plays = { "u:a": 900, "u:b": 900 }
    var out = Api.sortedLibraryItems(tied, "recent", plays, [])
    compare(out.map(function(i) { return i.name }).join(","), "A,B")
  }

  function test_librarySort_reportsTheValueItRankedOn() {
    var played = { "spotify:playlist:b": 4242 }
    var out = Api.sortedLibraryItems(sortFixture, "recent", played, [])
    var beta = out.filter(function(i) { return i.name === "Beta" })[0]
    compare(beta.sortValue, 4242)
    compare(beta.sortSource, "played")

    var byAdded = Api.sortedLibraryItems(sortFixture, "added", ({}), [])
    var alpha = byAdded.filter(function(i) { return i.name === "alpha" })[0]
    compare(alpha.sortValue, 3000)
    compare(alpha.sortSource, "added")
  }

  function test_librarySort_marksRowsWithNothingToRankOn() {
    var out = Api.sortedLibraryItems([{ uri: "u", name: "N" }], "recent", ({}), [])
    compare(out[0].sortValue, 0)
    compare(out[0].sortSource, "none")
  }

  function test_librarySort_pinnedItemsComeFirstInPinOrder() {
    var pinned = ["spotify:artist:c", "spotify:album:a"]
    var out = Api.sortedLibraryItems(sortFixture, "alpha", ({}), pinned)
    compare([out[0].name, out[1].name, out[2].name],
      ["Gamma", "alpha", "Beta"])
    verify(out[0].pinned === true)
    verify(out[2].pinned !== true)
  }

  function test_librarySort_toleratesJunkInput() {
    compare(Api.sortedLibraryItems(null, "alpha", ({}), []), [])
    compare(Api.sortedLibraryItems([], "alpha", null, null), [])
    var out = Api.sortedLibraryItems([{ uri: "x" }], "alpha", ({}), [])
    compare(out.length, 1)
  }

  function test_itemIsPlaying_matchesOnlyTheTrackNowPlaying() {
    var playing = { uri: "spotify:track:abc" }
    var other = { uri: "spotify:track:xyz" }
    verify(Api.itemIsPlaying("spotify:track:abc", playing))
    verify(!Api.itemIsPlaying("spotify:track:abc", other))
    // Nothing playing, no row, or a row with no uri never matches.
    verify(!Api.itemIsPlaying("", playing))
    verify(!Api.itemIsPlaying("spotify:track:abc", null))
    verify(!Api.itemIsPlaying("spotify:track:abc", {}))
    verify(!Api.itemIsPlaying("", {}))
  }

  function test_togglePinned_addsRemovesAndCaps() {
    var list = Api.togglePinned([], "a", 3)
    compare(list, ["a"])
    list = Api.togglePinned(list, "b", 3)
    compare(list, ["a", "b"])
    list = Api.togglePinned(list, "a", 3)
    compare(list, ["b"], "pinning an already pinned item unpins it")
    list = Api.togglePinned(["a", "b", "c"], "d", 3)
    compare(list, ["b", "c", "d"], "oldest pin drops when the cap is reached")
  }

  function test_normalizedNormalizeVolume_defaultsToOn() {
    compare(Api.normalizedNormalizeVolume("On"), "On")
    compare(Api.normalizedNormalizeVolume("Off"), "Off")
    compare(Api.normalizedNormalizeVolume(""), "On")
    compare(Api.normalizedNormalizeVolume(null), "On")
    compare(Api.normalizedNormalizeVolume("nonsense"), "On")
  }

  function test_normalizedVolumeLevel_acceptsOnlyTheThreeLevels() {
    compare(Api.normalizedVolumeLevel("Loud"), "Loud")
    compare(Api.normalizedVolumeLevel("Normal"), "Normal")
    compare(Api.normalizedVolumeLevel("Quiet"), "Quiet")
    compare(Api.normalizedVolumeLevel(""), "Normal")
    compare(Api.normalizedVolumeLevel(null), "Normal")
    compare(Api.normalizedVolumeLevel("Very Loud"), "Normal")
  }

  // Spotify publishes its targets as -11, -14 and -19 LUFS. librespot
  // normalises to its own target, so the level is expressed as a pregain
  // offset from Normal.
  function test_normalizationPregainDb_matchesSpotifysLoudnessTargets() {
    compare(Api.normalizationPregainDb("Normal"), 0)
    compare(Api.normalizationPregainDb("Loud"), 3)
    compare(Api.normalizationPregainDb("Quiet"), -5)
  }

  function test_normalizationPregainDb_fallsBackToNormal() {
    compare(Api.normalizationPregainDb(""), 0)
    compare(Api.normalizationPregainDb(null), 0)
    compare(Api.normalizationPregainDb("Deafening"), 0)
  }

  function test_pendingRemoteDeviceMatches_onlyWhileTheHoldIsStillValid() {
    var device = { id: "abc", name: "Kitchen", type: "Speaker" }
    var pending = { device: device, expiresAt: 5000 }

    verify(Api.pendingRemoteDeviceMatches(pending, device, 4999))
    verify(!Api.pendingRemoteDeviceMatches(pending, device, 5000),
      "the hold must not survive its own expiry")
    verify(!Api.pendingRemoteDeviceMatches(pending, device, 6000))
  }

  function test_pendingRemoteDeviceMatches_rejectsMissingOrOddValues() {
    var device = { id: "abc", name: "Kitchen", type: "Speaker" }
    verify(!Api.pendingRemoteDeviceMatches(null, device, 0))
    verify(!Api.pendingRemoteDeviceMatches({ expiresAt: 5000 }, device, 0))
    verify(!Api.pendingRemoteDeviceMatches({ device: device, expiresAt: 5000 },
      null, 0))
    verify(!Api.pendingRemoteDeviceMatches({ device: device, expiresAt: "soon" },
      device, 0))
    verify(!Api.pendingRemoteDeviceMatches({ device: device, expiresAt: 5000 },
      device, "now"))
  }

  function test_pendingRemoteDeviceMatches_needsTheSameDevice() {
    var pending = { device: { id: "abc", type: "Speaker" }, expiresAt: 5000 }
    verify(!Api.pendingRemoteDeviceMatches(pending,
      { id: "different", type: "Speaker" }, 0))
  }

  function test_searchTypeLoading_normalizesAndCachesEachCategory() {
    compare(Api.normalizedSearchType("album"), "album")
    compare(Api.normalizedSearchType("episode"), "episode")
    compare(Api.normalizedSearchType("unknown"), "track")
    compare(Api.normalizedSearchType(""), "track")
    verify(Api.searchNeedsLoad("miles", "", false))
    verify(Api.searchNeedsLoad(" miles ", "coltrane", true))
    verify(Api.searchNeedsLoad("miles", "miles", false))
    verify(!Api.searchNeedsLoad("miles", "miles", true))
    verify(!Api.searchNeedsLoad("   ", "", false))
  }

  function test_shallowCopyAndAssign_copyWithoutSharingIdentity() {
    var source = { name: "Work", volume: 12 }
    var copy = Api.shallowCopy(source)
    compare(copy.name, "Work")
    verify(copy !== source)
    source.name = "Kitchen"
    compare(copy.name, "Work")
    compare(Api.assign({ a: 1 }, { b: 2, a: 3 }).a, 3)
    compare(Api.rateLimitSuffix("4"), ". Try again in 4 seconds.")
    compare(Api.rateLimitSuffix("1"), ". Try again in 1 second.")
    compare(Api.rateLimitSuffix(""), "")
    compare(Api.rateLimitMessage("1"), "Spotify is busy. Try again in 1 second.")
    compare(Api.rateLimitMessage(""), "Spotify is busy. Try again in a moment.")
    compare(Api.rateLimitRetryMs("4"), 4400)
    compare(Api.rateLimitRetryMs("0"), 1400)
    compare(Api.rateLimitRetryMs("1"), 1400)
    compare(Api.rateLimitRetryMs("1", 2), 4400)
    compare(Api.rateLimitRetryMs("120"), 120400)
    compare(Api.rateLimitRetryMs(""), 10000)
    compare(Api.rateLimitRetryMs("Wed, 21 Oct 2015 07:28:00 GMT"), 10000)
    compare(Api.apiCooldownMs(1000, 1500), 500)
    compare(Api.apiCooldownMs(1500, 1000), 0)
    compare(Api.nextRateLimitedUntil(1000, "2", 0), 3400)
    compare(Api.nextRateLimitedUntil(1000, "1", 4000), 4000)
    compare(Api.nextRateLimitedUntil(1000, "1", 0, 3), 9400)
    compare(Api.responseRetryAfter({
      getResponseHeader: function(name) {
        return name === "Retry-After" ? "10" : ""
      }
    }), "10")
    verify(Api.localSocketFallbackMessage().indexOf("local player") >= 0)
  }

  function test_rateLimitRetryMs_data() {
    return [
      { tag: "below-cap", header: "29", attempt: 0, expected: 29400 },
      { tag: "at-cap", header: "30", attempt: 0, expected: 30400 },
      { tag: "above-cap", header: "31", attempt: 0, expected: 31400 },
      { tag: "two-minutes", header: "120", attempt: 0, expected: 120400 },
      { tag: "one-hour", header: "3600", attempt: 0, expected: 3600400 },
      { tag: "backoff-capped", header: "1", attempt: 10, expected: 30400 },
      { tag: "header-exceeds-backoff", header: "120", attempt: 10, expected: 120400 },
      { tag: "zero", header: "0", attempt: 0, expected: 1400 },
      { tag: "missing", header: "", attempt: 0, expected: 10000 },
      { tag: "invalid", header: "invalid", attempt: 0, expected: 10000 },
      { tag: "negative", header: "-1", attempt: 0, expected: 10000 },
      { tag: "nonfinite", header: "Infinity", attempt: 0, expected: 10000 }
    ]
  }

  function test_rateLimitRetryMs(data) {
    compare(Api.rateLimitRetryMs(data.header, data.attempt), data.expected)
  }

  function test_longRateLimitDoesNotShortenExistingDeadline() {
    compare(Api.nextRateLimitedUntil(1000, "120", 200000), 200000)
    compare(Api.nextRateLimitedUntil(1000, "120", 4000), 121400)
  }

  function test_apiRequestQueue_ordersMutationsAndSkipsAborted() {
    compare(Api.API_MAX_IN_FLIGHT, 4)
    compare(Api.API_MAX_RATE_LIMIT_RETRIES, 4)
    compare(Api.apiInFlightLimit(false), 4)
    compare(Api.apiInFlightLimit(true), 1, "a rate limited account drops to one")
    verify(Api.shouldRetryRateLimit(0))
    verify(Api.shouldRetryRateLimit(3))
    verify(!Api.shouldRetryRateLimit(4))
    verify(Api.apiRequestIsMutating("PUT"))
    verify(Api.apiRequestIsMutating("POST"))
    verify(!Api.apiRequestIsMutating("GET"))
    var queued = Api.enqueueApiJob([], { method: "GET", id: "one" })
    queued = Api.enqueueApiJob(queued, { method: "GET", id: "two" })
    queued = Api.enqueueApiJob(queued,
      { method: "GET", id: "search", priority: "interactive" })
    queued = Api.enqueueApiJob(queued, { method: "PUT", id: "play" })
    compare(queued[0].id, "play")
    compare(queued[1].id, "search")
    compare(queued[2].id, "one")
    compare(queued[3].id, "two")
    compare(Api.apiJobPriority(queued[0]), 2)
    compare(Api.apiJobPriority(queued[1]), 1)
    compare(Api.apiJobPriority(queued[2]), 0)
    queued = Api.enqueueApiJob(queued,
      { method: "GET", id: "search-two", priority: "interactive" })
    queued = Api.enqueueApiJob(queued, { method: "POST", id: "pause" })
    compare(queued[1].id, "pause")
    compare(queued[2].id, "search")
    compare(queued[3].id, "search-two")
    var skipped = Api.dequeueApiJob([
      { id: "stale", handle: { aborted: true } },
      { id: "live", handle: { aborted: false } }
    ])
    compare(skipped.job.id, "live")
    compare(skipped.queue.length, 0)
    compare(Api.dequeueApiJob([]).job, null)
  }

  function test_playlistItemsEmptyMessage_distinguishesHiddenAndFailedLists() {
    var own = { id: "own", ownerId: "user-1", collaborative: false }
    var followed = { id: "weekly", ownerId: "spotify", collaborative: false }
    compare(Api.playlistOwnedByUser(own, "user-1"), true)
    compare(Api.playlistOwnedByUser(followed, "user-1"), false)
    compare(Api.playlistItemsEmptyMessage(null, 0, "", 0, "user-1"), "")
    compare(Api.playlistItemsEmptyMessage(own, 3, "", 200, "user-1"), "")
    compare(Api.playlistItemsEmptyMessage(own, 0, "", 200, "user-1"),
      "This playlist has no visible items.")
    compare(Api.playlistItemsEmptyMessage(followed, 0, "", 200, "user-1"),
      Api.playlistItemsHiddenMessage())
    compare(Api.playlistItemsEmptyMessage(followed, 0, "Forbidden", 403, "user-1"),
      Api.playlistItemsHiddenMessage())
    compare(Api.playlistItemsEmptyMessage(own, 0,
      "API rate limit exceeded. Try again in 10 seconds.", 429, "user-1"),
      "Couldn't load this playlist. Try again in a moment.")
    compare(Api.playlistItemsEmptyMessage(followed, 0, "", 200, ""),
      "This playlist has no visible items.")
  }

  function test_responsiveMediaRowsAndSearchColumnsUseMeasuredWidth() {
    verify(Api.mediaRowShouldCompact(220, 180, 4))
    verify(!Api.mediaRowShouldCompact(180, 220, 4))
    verify(!Api.mediaRowShouldCompact(220, 180, 0))
    compare(Api.responsiveResultColumns(1000, 760), 2)
    compare(Api.responsiveResultColumns(500, 760), 1)
  }

  function test_sectionedMediaRows_flattensGroupsForOneVirtualizedView() {
    var songs = [{ id: "one" }, { id: "two" }, { id: "three" }]
    var rows = Api.sectionedMediaRows([
      { id: "songs", heading: "SONGS", items: songs, loading: false, hasMore: true },
      { id: "albums", heading: "ALBUMS", items: [], loading: false, hasMore: false },
      { id: "playlists", heading: "PLAYLISTS", items: [], loading: true, hasMore: false }
    ], 2)

    compare(rows.length, 6)
    compare(rows[0].kind, "heading")
    compare(rows[0].sectionId, "songs")
    compare(rows[1].kind, "items")
    compare(rows[1].items.length, 2)
    compare(rows[1].startIndex, 0)
    compare(rows[2].items.length, 1)
    compare(rows[2].startIndex, 2)
    compare(rows[3].kind, "more")
    compare(rows[4].kind, "heading")
    compare(rows[4].sectionId, "playlists")
    compare(rows[5].kind, "more")
  }

  function test_artistSubtitleSuffix_keepsNonArtistAlbumDetails() {
    compare(Api.artistSubtitleSuffix({
      subtitle: "Jimi Hendrix · Album · 1967",
      artists: [{ name: "Jimi Hendrix" }]
    }), " · Album · 1967")
    compare(Api.artistSubtitleSuffix({ subtitle: "Playlist", artists: [] }), "")
  }

  function test_artistForName_prefersAnExactArtist() {
    var artists = [
      { id: "tribute", type: "artist", name: "The Jimi Hendrix Experience Tribute" },
      { id: "jimi", type: "artist", name: "Jimi Hendrix" }
    ]
    compare(Api.artistForName(artists, "jimi hendrix").id, "jimi")
    compare(Api.artistForName(artists, "unknown").id, "tribute")
    compare(Api.artistForName([{ type: "album", name: "Jimi Hendrix" }],
      "Jimi Hendrix"), null)
  }

  function test_artistContextAvailable_onlyLinksTrackPerformers() {
    verify(Api.artistContextAvailable("track", "", []))
    verify(Api.artistContextAvailable("", "track-id", []))
    verify(Api.artistContextAvailable("", "", [{ name: "Björk" }]))
    verify(!Api.artistContextAvailable("episode", "", []))
    verify(!Api.artistContextAvailable("chapter", "", []))
  }

  function test_lyricsSong_requiresATrackAndPreservesPlaybackMetadata() {
    compare(Api.lyricsSong("", "Episode", "Podcast", "Show", 120, ""), null)
    compare(Api.lyricsSong("track-id", "", "Artist", "Album", 180, ""), null)

    var song = Api.lyricsSong("track-id", " Song ", " Artist ", " Album ",
      183.5, "https://images.example/cover.jpg", 91.75)
    compare(song.id, "spotify:track:track-id")
    compare(song.title, "Song")
    compare(song.artist, "Artist")
    compare(song.album, "Album")
    compare(song.duration, 183.5)
    compare(song.coverUrl, "https://images.example/cover.jpg")
    compare(song.positionSeconds, 91.75)

    compare(Api.lyricsSong("track-id", "Song", "Artist", "", 180, "", -5)
      .positionSeconds, 0)
    compare(Api.lyricsSong("track-id", "Song", "Artist", "", 180, "", 200)
      .positionSeconds, 180)
  }

  function test_optionalLyricsPluginRequiresConfirmationBeforeSetup() {
    compare(Api.optionalPluginState(false, false), "missing")
    compare(Api.optionalPluginState(true, false), "disabled")
    compare(Api.optionalPluginState(true, true), "ready")

    compare(Api.optionalPluginSetupCommand("missing", "stappmus.lyrics",
      "https://github.com/stappmus/Omasing.git"), [
        "/usr/bin/omarchy", "plugin", "add",
        "https://github.com/stappmus/Omasing.git", "--enable", "--yes"
      ])
    compare(Api.optionalPluginSetupCommand("disabled", "stappmus.lyrics",
      "https://github.com/stappmus/Omasing.git"), [
        "/usr/bin/omarchy", "plugin", "enable", "stappmus.lyrics",
        "--section", "center"
      ])
    compare(Api.optionalPluginSetupCommand("ready", "stappmus.lyrics",
      "https://github.com/stappmus/Omasing.git"), [])

    var song = { id: "spotify:track:one", title: "Song", artist: "Artist" }
    var intent = Api.lyricsInstallIntent(song, "spotify-panel-lyrics", 1000)
    compare(intent.surface, "spotify-panel-lyrics")
    compare(intent.song.title, "Song")
    verify(Api.lyricsInstallIntentIsFresh(intent, 1000, 180000))
    verify(Api.lyricsInstallIntentIsFresh(intent, 180999, 180000))
    verify(!Api.lyricsInstallIntentIsFresh(intent, 181000, 180000))
    compare(Api.lyricsInstallIntent(null, "surface", 1000), null)
    compare(Api.sessionWithoutLyricsInstall({
      lastRadioPlaylist: "keep",
      pendingLyricsInstall: intent
    }).lastRadioPlaylist, "keep")
    compare(Api.sessionWithoutLyricsInstall({
      pendingLyricsInstall: intent
    }).pendingLyricsInstall, undefined)
  }

  function test_sessionRecord_roundTripsAndMigratesPluginSettings() {
    compare(Api.sessionRecordIsEmpty(Api.emptySessionRecord()), true)
    compare(Api.sessionRecordIsEmpty(Api.parseSessionRecord("")), true)
    compare(Api.sessionRecordIsEmpty(Api.parseSessionRecord("{")), true)
    compare(Api.sessionRecordIsEmpty(Api.parseSessionRecord("[]")), true)
    compare(Api.pluginSettingsHaveSessionKeys(null), false)
    compare(Api.pluginSettingsHaveSessionKeys({ deviceName: "OmaSpotify" }), false)
    compare(Api.pluginSettingsHaveSessionKeys({ sessionState: "{}" }), true)
    compare(Api.pluginSettingsHaveSessionKeys({ searchHistory: "[]" }), true)

    var encoded = Api.encodeSessionRecord({
      tab: "playlists",
      searchText: "radiohead",
      selectedPlaylist: {
        kind: "context", type: "playlist", id: "playlist-one",
        uri: "spotify:playlist:playlist-one", name: "Long playlist"
      },
      selectedPlaylistItemCount: 150,
      detailItemCount: 100
    }, ["radiohead", "bjork"])
    compare(JSON.parse(encoded).version, 1)
    var restored = Api.parseSessionRecord(encoded)
    compare(restored.sessionState.tab, "playlists")
    compare(restored.sessionState.searchText, "radiohead")
    compare(restored.sessionState.selectedPlaylist.id, "playlist-one")
    compare(restored.sessionState.selectedPlaylistItemCount, 150)
    compare(restored.sessionState.detailItemCount, 100)
    compare(JSON.stringify(restored.searchHistory),
      JSON.stringify(["radiohead", "bjork"]))
    compare(Api.sessionRecordIsEmpty(restored), false)

    var fromPlugin = Api.sessionRecordFromPluginSettings({
      deviceName: "Office",
      sessionState: "{\"tab\":\"library\",\"libraryType\":\"albums\"}",
      searchHistory: "[\"kid a\", \"kid a\", \"\"]"
    })
    compare(fromPlugin.sessionState.tab, "library")
    compare(fromPlugin.sessionState.libraryType, "albums")
    compare(JSON.stringify(fromPlugin.searchHistory), JSON.stringify(["kid a"]))

    var oversized = { tab: "detail", blob: Array(16001).join("x") }
    compare(JSON.stringify(Api.normalizedSessionState(oversized)), "{}")
    compare(Api.sessionRecordIsEmpty(Api.sessionRecord(oversized, [])), true)
  }

  function test_spotifyTrackId_acceptsUrisUrlsAndEngineObjectPaths() {
    compare(Api.spotifyTrackId("spotify:track:14XWXWv5FoCbFzLksawpEe"),
      "14XWXWv5FoCbFzLksawpEe")
    compare(Api.spotifyTrackId("https://open.spotify.com/track/14XWXWv5FoCbFzLksawpEe"),
      "14XWXWv5FoCbFzLksawpEe")
    compare(Api.spotifyTrackId("/spotify/track/14XWXWv5FoCbFzLksawpEe"),
      "14XWXWv5FoCbFzLksawpEe")
    compare(Api.spotifyTrackId("/spotify/episode/not-a-track"), "")
  }

  function test_currentPlaybackTrack_reusesRemoteTracksAndSynthesizesMprisTracks() {
    var remote = {
      id: "remote-id", uri: "spotify:track:remote-id", type: "track",
      name: "Remote song"
    }
    compare(Api.currentPlaybackTrack("remote-id", remote, "", "", "", "", 0, ""),
      remote)

    var local = Api.currentPlaybackTrack("local-id", remote, "Local song",
      "Local artist", "Local album", "cover", 183.5, "web-url")
    compare(local.type, "track")
    compare(local.uri, "spotify:track:local-id")
    compare(local.name, "Local song")
    compare(local.subtitle, "Local artist")
    compare(local.durationMs, 183500)
    compare(local.externalUrl, "web-url")

    compare(Api.currentPlaybackTrack("episode-id", {
      id: "episode-id", uri: "spotify:episode:episode-id", type: "episode"
    }, "Episode", "", "", "", 120, ""), null)
    compare(Api.currentPlaybackTrack("", remote, "", "", "", "", 0, ""), null)
  }

  function test_arrayValues_acceptsQmlSequenceShape() {
    var sequence = ({ length: 2 })
    sequence[0] = { name: "One" }
    sequence[1] = { name: "Two" }

    verify(!Array.isArray(sequence))
    compare(Api.arrayValues(sequence).length, 2)
    compare(Api.artistNames(sequence), "One, Two")
  }

  function test_searchScope_tracksTheOpenAreaAndSearchMode() {
    var artist = Api.searchScope("detail", {
      id: "artist-id", uri: "spotify:artist:artist-id",
      type: "artist", name: "Björk"
    }, null, "recent", "tracks")
    verify(artist.available)
    compare(artist.key, "detail:spotify:artist:artist-id")
    compare(artist.label, "Björk")
    compare(artist.mode, "artist")

    var playlist = Api.searchScope("playlists", null, {
      id: "playlist-id", type: "playlist", name: "Night drive"
    }, "recent", "tracks")
    verify(playlist.available)
    compare(playlist.key, "playlist:playlist-id")
    compare(playlist.label, "Night drive")
    compare(playlist.mode, "filter")

    compare(Api.searchScope("home", null, null, "artists", "tracks").label,
      "Top artists")
    compare(Api.searchScope("library", null, null, "recent", "albums").label,
      "Saved albums")
    verify(!Api.searchScope("search", null, null, "recent", "tracks").available)
    verify(!Api.searchScope("devices", null, null, "recent", "tracks").available)
  }

  function test_universalSearchVisibility_isExplicitAndHiddenFromDevices() {
    verify(Api.universalSearchVisible("search", false))
    verify(!Api.universalSearchVisible("setup", true))
    verify(!Api.universalSearchVisible("setup", false))
    verify(!Api.universalSearchVisible("devices", true))
    verify(!Api.universalSearchVisible("login", true))
  }

  function test_previousContentTab_skipsSettingsAndDevices() {
    compare(Api.previousContentTab("setup", "home"), "home")
    compare(Api.previousContentTab("devices", "library"), "library")
    compare(Api.previousContentTab("devices", "setup"), "home")
    compare(Api.previousContentTab("setup", "devices"), "home")
    compare(Api.previousContentTab("setup", ""), "home")
    compare(Api.previousContentTab("home", "library"), "")
    compare(Api.rememberContentTab("setup"), "")
    compare(Api.rememberContentTab("playlists"), "playlists")
  }

  function test_tracksForArtist_filtersBroadSearchByStableArtistId() {
    var rows = Api.tracksForArtist([
      { id: "solo", type: "track", artists: [{ id: "target", name: "Artist" }] },
      { id: "feature", type: "track", artists: [
        { id: "guest", name: "Guest" }, { id: "target", name: "Artist" }
      ] },
      { id: "tribute", type: "track", artists: [{ id: "other", name: "Artist" }] },
      { id: "album", type: "album", artists: [{ id: "target", name: "Artist" }] }
    ], { id: "target", name: "Artist" })

    compare(rows.length, 2)
    compare(rows[0].id, "solo")
    compare(rows[1].id, "feature")
  }

  function test_findThisIsPlaylist_requiresExactTitleAndPrefersSpotify() {
    var result = Api.findThisIsPlaylist([
      { id: "lookalike", type: "playlist", name: "This Is Nearly Björk", ownerName: "Spotify" },
      { id: "fan", type: "playlist", name: "THIS IS BJÖRK!", ownerName: "A listener" },
      { id: "official", type: "playlist", name: "This Is Björk", ownerId: "spotify" }
    ], "Björk")

    verify(result !== null)
    compare(result.id, "official")
    compare(Api.findThisIsPlaylist([
      { id: "wrong", type: "playlist", name: "Best of Björk", ownerName: "Spotify" }
    ], "Björk"), null)
  }

  function test_trackRadioPlaylists_onlyKeepsExactSpotifyContexts() {
    var result = Api.trackRadioPlaylists([
      { id: "official", uri: "spotify:playlist:official", type: "playlist",
        name: "Dreams - 2004 Remaster Radio", ownerId: "spotify" },
      { id: "copy", uri: "spotify:playlist:copy", type: "playlist",
        name: "Dreams - 2004 Remaster Radio", ownerName: "A listener" },
      { id: "other", uri: "spotify:playlist:other", type: "playlist",
        name: "Sunset Dreams - 2004 Remaster Radio", ownerName: "Spotify" }
    ], "Dreams - 2004 Remaster")

    compare(result.length, 1)
    compare(result[0].id, "official")
  }

  function test_radioSeedMatches_acceptsRelinkedTrackFromSameArtist() {
    verify(Api.radioSeedMatches({
      id: "market-version", uri: "spotify:track:market-version",
      name: "Love The Way You Lie",
      artists: [{ id: "eminem", name: "Eminem" }, { id: "rihanna", name: "Rihanna" }]
    }, {
      id: "original", uri: "spotify:track:original",
      name: "Love The Way You Lie",
      artists: [{ id: "eminem", name: "Eminem" }]
    }))
    verify(!Api.radioSeedMatches({
      id: "cover", name: "Love The Way You Lie",
      artists: [{ id: "cover-band", name: "Cover Band" }]
    }, {
      id: "original", name: "Love The Way You Lie",
      artists: [{ id: "eminem", name: "Eminem" }]
    }))
  }

  function test_uniqueRadioTracks_keepsSeedFirstAndDropsDuplicateUris() {
    var seed = { uri: "spotify:track:seed", name: "Seed" }
    var radio = Api.uniqueRadioTracks(seed, [
      { uri: "spotify:track:seed", name: "Duplicate seed" },
      { uri: "spotify:track:two", name: "Two" },
      { uri: "", name: "Missing" },
      { uri: "spotify:track:two", name: "Two again" },
      { uri: "spotify:track:three", name: "Three" }
    ])
    compare(radio.length, 3)
    compare(radio[0], seed)
    compare(radio[1].name, "Two")
    compare(radio[2].name, "Three")
  }

  function test_discoveryPlaylists_keepsOfficialRelevantResultsInUsefulOrder() {
    var rows = Api.discoveryPlaylists([
      { id: "fan", type: "playlist", name: "Discover Weekly", ownerName: "A listener" },
      { id: "fresh", uri: "spotify:playlist:fresh", type: "playlist",
        name: "Fresh Finds Indie", ownerName: "Spotify" },
      { id: "mix", uri: "spotify:playlist:mix", type: "playlist",
        name: "Daily Mix 2", ownerId: "spotify" },
      { id: "radar", uri: "spotify:playlist:radar", type: "playlist",
        name: "Release Radar", ownerName: "Spotify" },
      { id: "weekly", uri: "spotify:playlist:weekly", type: "playlist",
        name: "Discover Weekly", ownerName: "Spotify" },
      { id: "weekly", uri: "spotify:playlist:weekly", type: "playlist",
        name: "Discover Weekly", ownerName: "Spotify" },
      { id: "unrelated", type: "playlist", name: "Party Hits", ownerName: "Spotify" }
    ])

    compare(rows.length, 4)
    compare(rows[0].id, "weekly")
    compare(rows[1].id, "radar")
    compare(rows[2].id, "mix")
    compare(rows[3].id, "fresh")
  }

  function test_scopes_followLeastPrivilege() {
    verify(Api.SCOPES.indexOf("user-modify-playback-state") >= 0)
    verify(Api.SCOPES.indexOf("user-library-read") >= 0)
    verify(Api.SCOPES.indexOf("user-follow-read") >= 0)
    verify(Api.SCOPES.indexOf("user-read-recently-played") >= 0)
    verify(Api.SCOPES.indexOf("user-top-read") >= 0)
    verify(Api.SCOPES.indexOf("playlist-modify-private") >= 0)
    verify(Api.SCOPES.indexOf("playlist-modify-public") >= 0)
    verify(Api.SCOPES.indexOf("user-read-private") === -1)
    verify(Api.SCOPES.indexOf("user-read-email") === -1)
    verify(Api.SCOPES.indexOf("user-read-currently-playing") === -1)
  }

  function test_safeApiUrl_rejectsForeignHosts() {
    compare(Api.safeApiUrl("/me"), Api.API_BASE + "/me")
    compare(Api.safeApiUrl(Api.API_BASE + "/me/tracks"), Api.API_BASE + "/me/tracks")
    compare(Api.safeApiUrl("https://api.spotify.com.evil.example/v1/me"), "")
    compare(Api.safeApiUrl("https://example.com/v1/me"), "")
  }

  function test_normalizeTrack_supportsCurrentPlaylistItems() {
    var normalized = Api.normalizeTrack({
      item: {
        id: "track-id",
        uri: "spotify:track:track-id",
        type: "track",
        name: "A track",
        duration_ms: 123000,
        explicit: true,
        artists: [{ name: "One" }, { name: "Two" }],
        album: {
          name: "An album",
          images: [
            { url: "large", width: 640 },
            { url: "small", width: 64 },
            { url: "right-sized", width: 96 }
          ]
        },
        external_urls: { spotify: "https://open.spotify.com/track/track-id" }
      }
    }, 96)

    verify(normalized !== null)
    compare(normalized.name, "A track")
    compare(normalized.subtitle, "One, Two")
    compare(normalized.album, "An album")
    compare(normalized.imageUrl, "right-sized")
    compare(normalized.durationMs, 123000)
    compare(normalized.explicit, true)
    compare(normalized.artists.length, 2)
    compare(normalized.albumItem.name, "An album")
    compare(normalized.albumItem.type, "album")
  }

  function test_normalizeTrack_supportsEpisodesAndResumePosition() {
    var episode = Api.normalizeTrack({
      played_at: "2026-08-11T10:00:00Z",
      item: {
        id: "episode-id",
        uri: "spotify:episode:episode-id",
        type: "episode",
        name: "Episode one",
        duration_ms: 3600000,
        resume_point: { resume_position_ms: 42000, fully_played: false },
        show: {
          id: "show-id",
          uri: "spotify:show:show-id",
          type: "show",
          name: "A show",
          images: [{ url: "show-art", width: 128 }]
        }
      }
    }, 96)

    compare(episode.type, "episode")
    compare(episode.subtitle, "A show")
    compare(episode.parentContext.type, "show")
    compare(episode.resumeMs, 42000)
    compare(episode.fullyPlayed, false)
    compare(episode.playedAt, "2026-08-11T10:00:00Z")
  }

  function test_searchGroups_normalizeEverySupportedType() {
    var groups = Api.searchGroups({
      tracks: { items: [{ id: "t", uri: "spotify:track:t", type: "track", name: "Track" }], total: 1 },
      artists: { items: [{ id: "a", uri: "spotify:artist:a", type: "artist", name: "Artist" }], total: 1 },
      albums: { items: [{ id: "b", uri: "spotify:album:b", type: "album", name: "Album" }], total: 1 },
      playlists: { items: [{ id: "p", uri: "spotify:playlist:p", type: "playlist", name: "Playlist" }], total: 1 },
      shows: { items: [{ id: "s", uri: "spotify:show:s", type: "show", name: "Show" }], total: 1 },
      episodes: { items: [{ id: "e", uri: "spotify:episode:e", type: "episode", name: "Episode" }], total: 1 },
      audiobooks: { items: [{ id: "book", uri: "spotify:audiobook:book", type: "audiobook", name: "Book" }], total: 1 }
    })

    compare(groups.track.items[0].type, "track")
    compare(groups.artist.items[0].type, "artist")
    compare(groups.album.items[0].type, "album")
    compare(groups.playlist.items[0].type, "playlist")
    compare(groups.show.items[0].type, "show")
    compare(groups.episode.items[0].type, "episode")
    compare(groups.audiobook.items[0].type, "audiobook")
  }

  function test_normalizeContext_labelsAlbumsAndEps() {
    var album = Api.normalizeContext({
      id: "album", uri: "spotify:album:album", type: "album",
      album_type: "album", name: "Full length", release_date: "2025-04-10",
      total_tracks: 12, artists: [{ name: "Artist" }]
    })
    var ep = Api.normalizeContext({
      id: "ep", uri: "spotify:album:ep", type: "album",
      album_type: "single", name: "Short release", release_date: "2026",
      total_tracks: 5, artists: [{ name: "Artist" }]
    })

    compare(album.subtitle, "Artist · Album · 2025")
    compare(album.releaseType, "album")
    compare(ep.subtitle, "Artist · EP / Single · 2026")
  }

  function test_playlistItemUris_keepsOrderAndDuplicates() {
    var uris = Api.playlistItemUris([
      { type: "track", uri: "spotify:track:one" },
      { type: "track", uri: "spotify:track:one" },
      { type: "album", uri: "spotify:album:nope" },
      { type: "episode", uri: "spotify:episode:two" },
      { type: "track", uri: "" }
    ])
    compare(JSON.stringify(uris), JSON.stringify([
      "spotify:track:one", "spotify:track:one", "spotify:episode:two"
    ]))
  }

  function test_playlistBackingItems_matchesStableIdsOnly() {
    var selectedItems = [{ name: "Selected song" }]
    var detailItems = [{ name: "Detail song" }]
    var refreshedContext = { id: "selected" }

    verify(Api.playlistBackingItems(refreshedContext,
      { id: "selected" }, selectedItems,
      { id: "detail", type: "playlist" }, detailItems) === selectedItems)
    verify(Api.playlistBackingItems({ id: "detail" },
      { id: "selected" }, selectedItems,
      { id: "detail", type: "playlist" }, detailItems) === detailItems)
    compare(Api.playlistBackingItems({ id: "unrelated" },
      { id: "selected" }, selectedItems,
      { id: "detail", type: "playlist" }, detailItems).length, 0)
    compare(Api.playlistBackingItems({ id: "detail" },
      { id: "selected" }, selectedItems,
      { id: "detail", type: "album" }, detailItems).length, 0)
  }

  function test_playlistReorderBody_translatesFinalIndexesForSpotify() {
    compare(JSON.stringify(Api.playlistReorderBody(1, 3, 4, "snapshot")),
      JSON.stringify({
        range_start: 1,
        insert_before: 4,
        range_length: 1,
        snapshot_id: "snapshot"
      }))
    compare(JSON.stringify(Api.playlistReorderBody(3, 1, 4, "")),
      JSON.stringify({ range_start: 3, insert_before: 1, range_length: 1 }))
    compare(Api.playlistReorderBody(1, 1, 4, "snapshot"), null)
    compare(Api.playlistReorderBody(-1, 2, 4, "snapshot"), null)
    compare(Api.playlistReorderBody(0, 4, 4, "snapshot"), null)
  }

  function test_playlistReorder_preservesRawPositionsAcrossHiddenItems() {
    var rows = [
      { name: "one", playlistPosition: 0 },
      { name: "two", playlistPosition: 2 },
      { name: "three", playlistPosition: 3 },
      { name: "four", playlistPosition: 4 }
    ]
    compare(JSON.stringify(Api.playlistReorderBodyForItems(
      rows, 1, 3, 5, "snapshot")), JSON.stringify({
        range_start: 2,
        insert_before: 5,
        range_length: 1,
        snapshot_id: "snapshot"
      }))

    var movedDown = Api.reorderedPlaylistItemsAtPositions(rows, 2, 4)
    compare(movedDown.map(function(item) { return item.name }).join(","),
      "one,three,four,two")
    compare(movedDown.map(function(item) { return item.playlistPosition }).join(","),
      "0,2,3,4")

    var movedUp = Api.reorderedPlaylistItemsAtPositions(rows, 4, 2)
    compare(movedUp.map(function(item) { return item.name }).join(","),
      "one,four,two,three")
    compare(movedUp.map(function(item) { return item.playlistPosition }).join(","),
      "0,2,3,4")
    compare(rows[1].playlistPosition, 2)

    var duplicates = [
      { name: "one", playlistPosition: 0 },
      { name: "duplicate", playlistPosition: 1 },
      { name: "two", playlistPosition: 2 },
      { name: "duplicate", playlistPosition: 3 }
    ]
    var oneOccurrence = Api.reorderedPlaylistItemsAtPositions(duplicates, 1, 3)
    compare(oneOccurrence.map(function(item) { return item.name }).join(","),
      "one,two,duplicate,duplicate")
    compare(duplicates[1].playlistPosition, 1)
  }

  function test_mergeSearchGroups_keepsUnchangedCategories() {
    var first = Api.searchGroups({
      tracks: { items: [{ id: "one", uri: "spotify:track:one", type: "track", name: "One" }], total: 2 },
      artists: { items: [{ id: "artist", uri: "spotify:artist:artist", type: "artist", name: "Artist" }], total: 1 }
    })
    var more = Api.searchGroups({
      tracks: { items: [{ id: "two", uri: "spotify:track:two", type: "track", name: "Two" }], total: 2 }
    })
    var merged = Api.mergeSearchGroups(first, more)

    compare(merged.track.items.length, 2)
    compare(merged.artist.items.length, 1)
  }

  function test_filteredSorted_filtersAndSortsWithoutMutatingSource() {
    var source = [
      { name: "Zulu", subtitle: "Someone", addedAt: "2026-01-01" },
      { name: "Alpha", subtitle: "Target artist", addedAt: "2026-08-01" },
      { name: "Unknown", subtitle: "No date" }
    ]
    var filtered = Api.filteredSorted(source, "target", "name")
    compare(filtered.length, 1)
    compare(filtered[0].name, "Alpha")

    var newest = Api.filteredSorted(source, "", "date")
    compare(newest[0].name, "Alpha")
    compare(newest[1].name, "Zulu")
    compare(newest[2].name, "Unknown")

    var oldest = Api.filteredSorted(source, "", "date-asc")
    compare(oldest[0].name, "Zulu")
    compare(oldest[1].name, "Alpha")
    compare(oldest[2].name, "Unknown")
    compare(source[0].name, "Zulu")
  }

  function test_touchHistory_deduplicatesAndCaps() {
    var history = Api.touchHistory(["old", "same", "older"], " same ", 3)
    compare(JSON.stringify(history), JSON.stringify(["same", "old", "older"]))
    history = Api.touchHistory(history, "new", 3)
    compare(JSON.stringify(history), JSON.stringify(["new", "same", "old"]))
  }

  function test_normalizePage_filtersMalformedRowsAndNextHost() {
    var page = Api.normalizePage({
      items: [
        { type: "track", id: "one", uri: "spotify:track:one", name: "One" },
        { type: "unsupported", id: "bad" }
      ],
      next: Api.API_BASE + "/me/tracks?offset=1",
      previous: "https://attacker.example/steal",
      total: 2
    }, function(value) { return Api.normalizeTrack(value, 64) })

    compare(page.items.length, 1)
    compare(page.items[0].id, "one")
    compare(page.next, Api.API_BASE + "/me/tracks?offset=1")
    compare(page.previous, "")
    compare(page.total, 2)
  }

  function test_playlistPageState_keepsLoadingPastSharedCacheLimit() {
    var existing = []
    var incoming = []
    for (var i = 0; i < 200; i++) existing.push({ playlistPosition: i })
    for (var j = 200; j < 250; j++) incoming.push({ playlistPosition: j })
    var nextUrl = Api.API_BASE + "/playlists/list/items?offset=250"

    var page = Api.playlistPageState(existing, incoming, true, nextUrl)
    compare(page.items.length, 250)
    compare(page.items[0].playlistPosition, 0)
    compare(page.items[249].playlistPosition, 249)
    compare(page.next, nextUrl)

    var refreshed = Api.playlistPageState(existing, incoming, false, "")
    verify(refreshed.items === incoming)
    compare(refreshed.items.length, 50)
    compare(refreshed.next, "")
  }

  function test_playlistRestoreCount_isBoundedAndContinuesOnlyWithNextPage() {
    compare(Api.normalizedPlaylistRestoreCount(undefined), 0)
    compare(Api.normalizedPlaylistRestoreCount(-10), 0)
    compare(Api.normalizedPlaylistRestoreCount(149.9), 149)
    compare(Api.normalizedPlaylistRestoreCount(999999), 10000)

    var nextUrl = Api.API_BASE + "/playlists/list/items?offset=50"
    verify(Api.playlistRestorePending(50, 150, true, ""))
    verify(Api.playlistRestorePending(50, 150, false, nextUrl))
    verify(!Api.playlistRestorePending(150, 150, true, nextUrl))
    verify(!Api.playlistRestorePending(50, 150, false, ""))
    verify(Api.playlistRestoreShouldContinue(50, 150, nextUrl))
    verify(!Api.playlistRestoreShouldContinue(150, 150, nextUrl))
    verify(!Api.playlistRestoreShouldContinue(50, 150,
      "https://attacker.example/items?offset=50"))
  }

  function test_playbackBodies() {
    compare(JSON.stringify(Api.playbackBody({
      kind: "context", type: "playlist", uri: "spotify:playlist:abc"
    })), JSON.stringify({ context_uri: "spotify:playlist:abc" }))
    compare(JSON.stringify(Api.playbackBody({
      kind: "item", type: "track", uri: "spotify:track:def"
    })), JSON.stringify({ uris: ["spotify:track:def"] }))

    var rows = [
      { kind: "item", uri: "spotify:track:a" },
      { kind: "item", uri: "spotify:track:b" },
      { kind: "context", uri: "spotify:album:ignored" },
      { kind: "item", uri: "spotify:track:c" }
    ]
    compare(JSON.stringify(Api.playbackBody(rows[1], rows, "")), JSON.stringify({
      uris: ["spotify:track:b", "spotify:track:c", "spotify:track:a"]
    }))
    rows[1].playlistPosition = 7
    compare(JSON.stringify(Api.playbackBody(rows[1], rows, "spotify:playlist:list")),
      JSON.stringify({
        context_uri: "spotify:playlist:list",
        offset: { position: 7 }
      }))

    var epRows = [
      { kind: "item", uri: "spotify:track:first", discNumber: 1, trackNumber: 1 },
      { kind: "item", uri: "spotify:track:second", discNumber: 1, trackNumber: 2 },
      { kind: "item", uri: "spotify:track:third", discNumber: 1, trackNumber: 3 }
    ]
    compare(JSON.stringify(Api.playbackBody(epRows[2], epRows,
      "spotify:album:ep")), JSON.stringify({
        context_uri: "spotify:album:ep",
        offset: { position: 2 }
      }))

    var multiDiscRows = [
      { kind: "item", uri: "spotify:track:d1t1", discNumber: 1, trackNumber: 1 },
      { kind: "item", uri: "spotify:track:d1t2", discNumber: 1, trackNumber: 2 },
      { kind: "item", uri: "spotify:track:d2t1", discNumber: 2, trackNumber: 1 }
    ]
    compare(JSON.stringify(Api.playbackBody(multiDiscRows[2], multiDiscRows,
      "spotify:album:multi")), JSON.stringify({
        context_uri: "spotify:album:multi",
        offset: { position: 2 }
      }))
    compare(Api.playbackBody(null), null)
    compare(Api.playbackBody({
      kind: "context", type: "show", uri: "spotify:show:podcast"
    }), null)
    compare(JSON.stringify(Api.playbackBody({
      kind: "item", type: "episode", uri: "spotify:episode:one", resumeMs: 9000
    }, [], "spotify:show:podcast")), JSON.stringify({
      uris: ["spotify:episode:one"], position_ms: 9000
    }))
  }

  function test_playbackContext_followsTheDisplayedOrderOnlyWhenCustomized() {
    var playlist = "spotify:playlist:list"
    var album = "spotify:album:record"
    compare(Api.playbackContextForView(playlist, "", "default"), playlist)
    compare(Api.playbackContextForView(playlist, "miles", "default"), "")
    compare(Api.playbackContextForView(playlist, "", "name"), "")
    compare(Api.playbackContextForView(album, "", "date"), "")
    compare(Api.playbackContextForView("spotify:show:podcast", "", "name"),
      "spotify:show:podcast")
    verify(Api.playbackUsesVisibleOrder(playlist, "miles", "default"))
    verify(!Api.playbackUsesVisibleOrder(playlist, "", "default"))
    compare(Api.visibleOrderPlaybackMessage(12), "Playing the displayed order")
    verify(Api.visibleOrderPlaybackMessage(114).indexOf("100 items") >= 0)
    compare(Api.PLAYBACK_URI_LIMIT, 100)
  }

  function test_visibleOrderPlayback_preservesOccurrencesAndCapsLongLists() {
    var duplicateRows = [
      { kind: "item", uri: "spotify:track:duplicate", playlistPosition: 0 },
      { kind: "item", uri: "spotify:track:middle", playlistPosition: 1 },
      { kind: "item", uri: "spotify:track:duplicate", playlistPosition: 2 },
      { kind: "item", uri: "spotify:track:last", playlistPosition: 3 }
    ]
    compare(JSON.stringify(Api.playbackBody(duplicateRows[2], duplicateRows, "")),
      JSON.stringify({ uris: ["spotify:track:duplicate", "spotify:track:last",
        "spotify:track:duplicate", "spotify:track:middle"] }))

    var longRows = []
    for (var i = 0; i < 114; i++)
      longRows.push({ kind: "item", uri: "spotify:track:" + i,
        playlistPosition: i })
    var body = Api.playbackBody(longRows[110], longRows, "")
    compare(body.uris.length, Api.PLAYBACK_URI_LIMIT)
    compare(body.uris[0], "spotify:track:110")
    compare(body.uris[3], "spotify:track:113")
    compare(body.uris[4], "spotify:track:0")
    compare(body.uris[99], "spotify:track:95")
  }

  function test_playbackPreservesActiveDeviceAndFallsBackToLocal() {
    var external = { id: "desktop", local: false, active: true, restricted: false }
    var local = { id: "omarchy", local: true, active: false, restricted: false }
    var devices = [external, local]

    compare(Api.preferredPlaybackDevice(devices, "", false).id, "desktop")
    compare(Api.preferredPlaybackDevice(devices, "omarchy", false).id, "desktop")
    compare(Api.preferredPlaybackDevice(devices, "desktop", true).id, "desktop")

    external.active = false
    compare(Api.preferredPlaybackDevice(devices, "", false).id, "omarchy")
  }

  function test_automaticLocalPlaybackDevice_selectsAnActiveLocalReceiver() {
    var activeLocal = {
      id: "omarchy", local: true, active: true, restricted: false
    }
    var inactiveLocal = {
      id: "fallback", local: true, active: false, restricted: false
    }
    var activeRemote = {
      id: "phone", local: false, active: true, restricted: false
    }

    compare(Api.automaticLocalPlaybackDevice("", activeLocal, activeLocal).id,
      "omarchy")
    compare(Api.automaticLocalPlaybackDevice("", inactiveLocal, inactiveLocal).id,
      "fallback")
    compare(Api.automaticLocalPlaybackDevice("", activeRemote, inactiveLocal), null)
    compare(Api.automaticLocalPlaybackDevice("chosen", activeLocal, activeLocal), null)
    compare(Api.automaticLocalPlaybackDevice("", null, {
      id: "restricted", local: true, restricted: true
    }), null)
  }

  function test_visibleUiStartsAndRefreshesLocalReceiver() {
    compare(Api.visibleLocalReceiverAction(false, true, false, false), "idle")
    compare(Api.visibleLocalReceiverAction(true, false, false, false), "idle")
    compare(Api.visibleLocalReceiverAction(true, true, false, true), "wait")
    compare(Api.visibleLocalReceiverAction(true, true, false, false), "start")
    compare(Api.visibleLocalReceiverAction(true, true, true, false), "refresh")
  }

  // Polling the Web API is the largest single source of traffic on a quota
  // shared with every other app on this client id, and most of it asks about
  // playback MPRIS already told us about for free.
  function test_remotePlaybackPoll_leansOnMprisAndSlowsWhenIdle() {
    // Playing on a Connect device: the Web API is the only source of position.
    compare(Api.remotePlaybackPollInterval(true, true, false, true), 5000)
    // Paused there, nothing is moving.
    compare(Api.remotePlaybackPollInterval(true, true, false, false), 15000)
    // Playing on this computer: MPRIS pushes every change, so the only reason
    // to ask at all is to notice a Connect device taking over.
    compare(Api.remotePlaybackPollInterval(true, false, true, true), 60000)
    // But the engine merely running and idle is not MPRIS telling us anything,
    // and someone may be about to start playing on their phone.
    compare(Api.remotePlaybackPollInterval(true, false, true, false), 15000)
    // Nothing playing anywhere, panel open: slow enough to be cheap, quick
    // enough to notice a phone starting something.
    compare(Api.remotePlaybackPollInterval(true, false, false, false), 15000)
    // Panel shut, unchanged.
    compare(Api.remotePlaybackPollInterval(false, true, false, true), 15000)
  }

  function test_remotePlaybackPoll_skipsBackgroundLocalPlayback() {
    verify(Api.remotePlaybackPollShouldRun(true, false, true, false, true))
    verify(Api.remotePlaybackPollShouldRun(true, false, false, true, true))
    verify(!Api.remotePlaybackPollShouldRun(true, false, false, false, true))
    verify(!Api.remotePlaybackPollShouldRun(true, true, true, true, true))
    verify(!Api.remotePlaybackPollShouldRun(false, false, true, true, true))
  }

  function test_normalizedShortcutPlayer_mapsLegacyDefault() {
    compare(Api.normalizedShortcutPlayer("Omarchy default"), "Omarchy Music app")
    compare(Api.normalizedShortcutPlayer("Full player"), "Full player")
    compare(Api.normalizedShortcutPlayer("Mini player"), "Mini player")
    compare(Api.normalizedShortcutPlayer(""), "Omarchy Music app")
  }

  function test_repeatAndSearchLabels_areHumanReadable() {
    compare(Api.repeatModeLabel("off"), "Off")
    compare(Api.repeatModeLabel("track"), "This song")
    compare(Api.repeatModeLabel("context"), "All")
    compare(Api.searchTypeLabel("track"), "Songs")
    compare(Api.searchTypeLabel("audiobook"), "Books")
    compare(Api.spotifyTypeLabel("track"), "Song")
    compare(Api.spotifyTypeLabel("playlist"), "Playlist")
  }

  function test_backendLoadFields_mapsWebApiBodies() {
    compare(JSON.stringify(Api.backendLoadFields({
      context_uri: "spotify:album:abc",
      offset: { position: 3 }
    })), JSON.stringify({
      play: true,
      context_uri: "spotify:album:abc",
      offset_index: 3
    }))
    compare(JSON.stringify(Api.backendLoadFields({
      uris: ["spotify:track:one", "spotify:track:two"],
      position_ms: 1500
    })), JSON.stringify({
      play: true,
      uris: ["spotify:track:one", "spotify:track:two"],
      position_ms: 1500
    }))
    compare(Api.backendLoadFields(null), null)
    compare(Api.backendLoadFields({}), null)
  }

  function test_currentPlaybackDeviceWorksBeforeDeviceListLoads() {
    var current = {
      id: "phone", name: "Phone", type: "Smartphone",
      local: false, active: true, restricted: false
    }

    compare(Api.preferredPlaybackDevice([], "", false, current).id, "phone")
  }

  function test_explicitDeviceOverridesCurrentPlaybackDevice() {
    var selected = { id: "speaker", local: false, active: false, restricted: false }
    var current = { id: "phone", local: false, active: true, restricted: false }

    compare(Api.preferredPlaybackDevice([selected], "speaker", true, current).id,
      "speaker")
  }

  function test_activePlaybackTargetOmitsDeviceId() {
    var active = { id: "phone", active: true }
    var fallback = { id: "omarchy", active: false }

    compare(Api.playbackTargetDeviceId(active, false), "phone")
    compare(Api.playbackTargetDeviceId(active, true), "phone")
    compare(Api.playbackTargetDeviceId(fallback, false), "omarchy")
    compare(Api.playbackTargetDeviceId(null, false), "")
  }

  function test_restrictedActiveDeviceDoesNotSilentlyFallBackToLocal() {
    var speaker = {
      id: "speaker", local: false, active: true, restricted: true
    }
    var local = {
      id: "omarchy", local: true, active: false, restricted: false
    }

    compare(Api.preferredPlaybackDevice([speaker, local], "", false).id,
      "speaker")
    compare(Api.playbackTargetDeviceId(speaker, false), "speaker")
  }

  function test_unavailableExplicitDeviceFallsBackToLocal() {
    var local = { id: "omarchy", local: true, restricted: false }
    compare(Api.preferredPlaybackDevice([local], "gone", true).id, "omarchy")
    compare(Api.preferredPlaybackDevice([], "gone", true), null)
  }

  function test_localPlaybackDevice_survivesAConfiguredRename() {
    verify(Api.isLocalPlaybackDevice({ id: "local", name: "Old desk" },
      "New desk", "Old desk", ""))
    verify(Api.isLocalPlaybackDevice({ id: "local", name: "Unexpected API label" },
      "New desk", "", "local"))
    verify(!Api.isLocalPlaybackDevice({ id: "speaker", name: "Kitchen" },
      "New desk", "Old desk", "local"))
  }

  function test_playbackDeviceMatch_fallsBackToNameWhenCurrentIdIsMissing() {
    verify(Api.playbackDevicesMatch({ id: "", name: "Work", type: "Speaker" },
      { id: "sonos-id", name: "work", type: "speaker" }))
    verify(!Api.playbackDevicesMatch({ id: "api-id", name: "Work", type: "Speaker" },
      { id: "different-id", name: "Work", type: "Speaker" }))
    verify(!Api.playbackDevicesMatch({ id: "", name: "Work", type: "Speaker" },
      { id: "sonos-id", name: "Work", type: "Computer" }))
  }

  function test_remoteSeekHoldsRequestedPositionUntilSpotifyCatchesUp() {
    var device = { id: "speaker", name: "Speaker", type: "Speaker" }
    var playback = {
      device: device,
      item: { uri: "spotify:track:one" },
      progressSeconds: 20,
      receivedAt: 1000,
      playing: true
    }
    var pending = {
      device: device,
      uri: "spotify:track:one",
      positionSeconds: 90,
      requestedAt: 1500,
      playing: true,
      expiresAt: 9500
    }

    verify(Api.pendingRemoteSeekShouldHold(playback, pending, 2000))
    compare(Api.displayedRemotePosition(playback, pending, 2000), 90.5)

    playback.progressSeconds = 90.4
    playback.receivedAt = 1900
    verify(!Api.pendingRemoteSeekShouldHold(playback, pending, 2000))
    compare(Api.displayedRemotePosition(playback, pending, 2000), 90.5)
  }

  function test_remoteSeekStopsHoldingForExpiryOrTrackChange() {
    var device = { id: "speaker", name: "Speaker", type: "Speaker" }
    var playback = {
      device: device,
      item: { uri: "spotify:track:two" },
      progressSeconds: 20,
      receivedAt: 1000,
      playing: false
    }
    var pending = {
      device: device,
      uri: "spotify:track:one",
      positionSeconds: 90,
      requestedAt: 1500,
      playing: false,
      expiresAt: 9500
    }

    verify(!Api.pendingRemoteSeekShouldHold(playback, pending, 2000))
    playback.item.uri = "spotify:track:one"
    verify(!Api.pendingRemoteSeekShouldHold(playback, pending, 9500))
  }

  function test_remoteVolumeHoldsUntilMatchingDeviceAcknowledgesIt() {
    var device = {
      id: "speaker", name: "Speaker", type: "Speaker", volumePercent: 25
    }
    var pending = {
      device: device,
      volumePercent: 60,
      expiresAt: 9000
    }

    verify(Api.pendingRemoteVolumeShouldHold(device, pending, 2000))
    device.volumePercent = 60
    verify(!Api.pendingRemoteVolumeShouldHold(device, pending, 2000))
    device.volumePercent = 25
    verify(!Api.pendingRemoteVolumeShouldHold(device, pending, 9000))
    verify(!Api.pendingRemoteVolumeShouldHold({
      id: "other", name: "Other", type: "Speaker", volumePercent: 25
    }, pending, 2000))
  }

  function test_playbackSliderFeedbackWaitsForAuthoritativeValue() {
    verify(!Api.playbackSliderFeedbackComplete(
      0.2, 0.8, false, 100, 0.01, 300, 8000))
    verify(!Api.playbackSliderFeedbackComplete(
      0.8, 0.8, true, 500, 0.01, 300, 8000))
    verify(Api.playbackSliderFeedbackComplete(
      0.8, 0.8, false, 500, 0.01, 300, 8000))
    verify(Api.playbackSliderFeedbackComplete(
      0.2, 0.8, true, 8000, 0.01, 300, 8000))
  }

  function test_playbackDeviceDisplayName_prefersMatchedLocalAlias() {
    var deviceId = "0123456789abcdef0123456789abcdef01234567"
    var current = { id: deviceId, name: deviceId, type: "Speaker" }
    var receivers = [{
      id: deviceId, name: "Living room soundbar", type: "Speaker",
      brand: "JBL", model: "BAR_800"
    }]

    verify(Api.spotifyDeviceNameNeedsDiscovery(current))
    compare(Api.playbackDeviceDisplayName(current, receivers), "Living room soundbar")
    compare(Api.playbackDeviceDisplayName(current, []), deviceId)
    verify(!Api.spotifyDeviceNameNeedsDiscovery({
      id: deviceId, name: "Living room", type: "Speaker"
    }))
  }

  function test_spotifyConnectTokenType_preservesSupportedReceiverFlows() {
    compare(Api.spotifyConnectTokenType("accesstoken"), "accesstoken")
    compare(Api.spotifyConnectTokenType("authorization_code"), "authorization_code")
    compare(Api.spotifyConnectTokenType("default"), "default")
    compare(Api.spotifyConnectTokenType("unexpected"), "default")
    verify(Api.isSpotifyConnectDeviceId("abcdEFGH1234"))
    verify(!Api.isSpotifyConnectDeviceId("short"))
    verify(!Api.isSpotifyConnectDeviceId("bad id"))
  }

  function test_normalizePlaybackState_keepsRemoteTrackAndNullableDeviceId() {
    var state = Api.normalizePlaybackState({
      is_playing: true,
      progress_ms: 42000,
      repeat_state: "context",
      shuffle_state: true,
      device: {
        id: null, name: "Work", type: "Speaker", is_active: true,
        is_restricted: true, volume_percent: 33, supports_volume: true
      },
      item: {
        id: "track", uri: "spotify:track:track", type: "track",
        name: "A song", duration_ms: 180000,
        artists: [{ name: "An artist" }], album: { name: "An album" }
      }
    }, 192)

    verify(state !== null)
    compare(state.device.id, "")
    compare(state.device.name, "Work")
    compare(state.device.restricted, true)
    compare(state.device.volumePercent, 33)
    compare(state.item.name, "A song")
    compare(state.item.subtitle, "An artist")
    compare(state.progressSeconds, 42)
    compare(state.repeatMode, "context")
    compare(state.shuffle, true)
    compare(state.contextUri, "")
    compare(state.contextHref, "")
    compare(state.contextType, "")
  }

  function test_normalizePlaybackState_keepsRadioContextFields() {
    var state = Api.normalizePlaybackState({
      is_playing: true,
      progress_ms: 1000,
      device: { id: "phone", name: "Phone", type: "Smartphone", is_active: true },
      context: {
        uri: "spotify:playlist:radio",
        href: "https://api.spotify.com/v1/playlists/radio",
        type: "playlist"
      },
      item: {
        id: "track", uri: "spotify:track:track", type: "track",
        name: "A song", duration_ms: 180000
      }
    }, 192)

    compare(state.contextUri, "spotify:playlist:radio")
    compare(state.contextHref, "https://api.spotify.com/v1/playlists/radio")
    compare(state.contextType, "playlist")
  }

  function test_normalizePlaybackState_preservesUnknownRemoteVolume() {
    var state = Api.normalizePlaybackState({
      device: {
        id: "phone", name: "Phone", type: "Smartphone", is_active: true,
        is_restricted: false, volume_percent: null, supports_volume: true
      }
    }, 192)

    verify(state !== null)
    compare(state.device.volumePercent, null)
    compare(state.device.supportsVolume, true)
  }

  function test_normalizePlaybackState_rejectsEmptyPlaybackResponse() {
    compare(Api.normalizePlaybackState(null, 192), null)
    compare(Api.normalizePlaybackState({}, 192), null)
    compare(Api.normalizePlaybackState([], 192), null)
  }

  function test_mergeUnique_preservesOrder() {
    var merged = Api.mergeUnique([
      { uri: "spotify:track:a" },
      { uri: "spotify:track:b" }
    ], [
      { uri: "spotify:track:b" },
      { uri: "spotify:track:c" }
    ])
    compare(merged.length, 3)
    compare(merged[0].uri, "spotify:track:a")
    compare(merged[2].uri, "spotify:track:c")
  }

  function test_redact_coversHeadersFormsUrlsAndJson() {
    var raw = [
      "Authorization: Bearer access-value",
      "refresh_token=refresh-value&code=authorization-value",
      "?code_verifier=verifier-value&client_secret=secret-value",
      "{\"access_token\":\"json-token\",\"password\":\"nope\"}"
    ].join("\n")
    var safe = Api.redact(raw)

    verify(safe.indexOf("access-value") === -1)
    verify(safe.indexOf("refresh-value") === -1)
    verify(safe.indexOf("authorization-value") === -1)
    verify(safe.indexOf("verifier-value") === -1)
    verify(safe.indexOf("secret-value") === -1)
    verify(safe.indexOf("json-token") === -1)
    verify(safe.indexOf("\"nope\"") === -1)
    verify(safe.indexOf("<redacted>") >= 0)
  }

  function test_clockFormatting() {
    compare(Api.millisecondsToClock(0), "0:00")
    compare(Api.millisecondsToClock(61000), "1:01")
    compare(Api.millisecondsToClock(-100), "0:00")
  }

  function test_quotaErrorIncludesMachineReason() {
    compare(Api.responseError(429, {
      error: { status: 429, message: "Too many requests", reason: "QUOTA_EXCEEDED" }
    }, ""), "Too many requests (QUOTA_EXCEEDED)")
  }

  function test_shortcutHints_matchRequiredModifiersAndKeycaps() {
    compare(Api.normalizedShortcutHints(undefined), "On")
    compare(Api.normalizedShortcutHints("On"), "On")
    compare(Api.normalizedShortcutHints("Off"), "Off")
    compare(Api.normalizedShortcutHints("off"), "On")

    var none = { ctrl: false, shift: false, alt: false }
    var ctrl = { ctrl: true, shift: false, alt: false }
    var shift = { ctrl: false, shift: true, alt: false }
    var ctrlShift = { ctrl: true, shift: true, alt: false }
    var altShift = { ctrl: false, shift: true, alt: true }

    compare(Api.shortcutHintCaption("Space", none, true), "Space")
    compare(Api.shortcutHintCaption("Space", ctrl, true), "")
    compare(Api.shortcutHintCaption("Ctrl+S", ctrl, true), "S")
    compare(Api.shortcutHintCaption("Ctrl+S", none, true), "")
    compare(Api.shortcutHintCaption("Ctrl+S", ctrlShift, true), "")
    compare(Api.shortcutHintCaption("Ctrl+Shift+L", ctrl, true), "")
    compare(Api.shortcutHintCaption("Ctrl+Shift+L", ctrlShift, true), "L")
    compare(Api.shortcutHintCaption("Shift+F10", ctrlShift, true), "")
    compare(Api.shortcutHintCaption("Ctrl+Shift+A", ctrlShift, true), "A")
    compare(Api.shortcutHintCaption("Alt+Shift+H", altShift, true), "H")
    compare(Api.shortcutHintCaption("Ctrl+Shift+A", altShift, true), "")
    compare(Api.shortcutHintCaption("Ctrl+Shift+B", ctrlShift, true), "B")
    compare(Api.shortcutHintCaption("Ctrl+Shift+A", ctrl, true), "")
    compare(Api.shortcutHintCaption("Alt+Left", { ctrl: false, shift: false, alt: true }, true), "←")
    compare(Api.shortcutHintCaption(["Ctrl+Up", "Ctrl+Down"], ctrl, true), "↑ ↓")
    compare(Api.shortcutHintCaption(["/", "Ctrl+F"], none, true), "/")
    compare(Api.shortcutHintCaption(["/", "Ctrl+F"], ctrl, true), "F")
    compare(Api.shortcutHintCaption("Shift+Right", shift, true), "→")
    compare(Api.shortcutHintCaption("Shift+F10", shift, true), "F10")
    compare(Api.shortcutHintCaption("Shift+F10", none, true), "")
    compare(Api.shortcutHintCaption("Menu", none, true), "Menu")
    compare(Api.shortcutOverlayLabel("Shift+F10", shift, true, "↵"), "↵ F10")
    compare(Api.shortcutOverlayLabel("Shift+F10", shift, true, ""), "F10")
    compare(Api.shortcutHintCaption("C", none, true), "C")
    compare(Api.shortcutOverlayLabel("C", none, true, "↵"), "↵ C")
    compare(Api.shortcutHintCaption("Ctrl+,", ctrl, true), ",")
    compare(Api.shortcutHintCaption("Ctrl+/", ctrl, true), "/")
    compare(Api.shortcutHintCaption("Esc", none, true), "Esc")
    compare(Api.shortcutHintCaption("Space", none, false), "")
    compare(Api.shortcutOverlayLabel("Space", none, true, "Tab"), "Tab Space")
    compare(Api.shortcutOverlayLabel(["/", "Ctrl+F"], none, true, "Tab"), "Tab /")
    compare(Api.shortcutOverlayLabel("Space", none, true, ""), "Space")
    compare(Api.shortcutOverlayLabel("Space", none, true, "↵"), "↵ Space")
    compare(Api.shortcutOverlayLabel("Ctrl+S", none, true, ""), "")
    compare(Api.shortcutOverlayLabel("Space", none, false, "Tab"), "")
    compare(Api.shortcutModifierFlagsAfterEvent(0, false, 3, 0), 3)
    compare(Api.shortcutModifierFlagsAfterEvent(3, true, 0, 1), 3)
    compare(Api.shortcutModifierFlagsAfterEvent(3, false, 3, 1), 2)
    compare(Api.shortcutModifierFlagsAfterEvent(1, false, 1, 1), 0)
    compare(Api.shortcutModifierFlagsAfterEvent(3, true, 0, 0), 3)
  }

  function test_searchShortcutAction_startsGlobalThenTogglesScope() {
    compare(Api.searchShortcutAction(false, true, true), "enter-global")
    compare(Api.searchShortcutAction(false, true, false), "focus")
    compare(Api.searchShortcutAction(true, true, true), "toggle-scope")
    compare(Api.searchShortcutAction(true, true, false), "toggle-scope")
    compare(Api.searchShortcutAction(false, false, true), "focus")
    compare(Api.searchShortcutAction(true, false, false), "focus")
  }

  function test_cursorNavigation_wrapsAndLeavesLists() {
    compare(Api.ensureCursorAction(["play", "next"], "shuffle", "play"), "play")
    compare(Api.ensureCursorAction(["play", "next"], "next", "play"), "next")
    compare(Api.moveCursorAction(["shuffle", "play", "next"], "play", 1), "next")
    compare(Api.moveCursorAction(["shuffle", "play", "next"], "next", 1), "shuffle")
    compare(Api.moveCursorAction(["shuffle", "play", "next"], "shuffle", -1), "next")
    compare(Api.listIndexAfterMove(3, 0, 1), 1)
    compare(Api.listIndexAfterMove(3, 2, 1), -1)
    compare(Api.listIndexAfterMove(3, 0, -1), -1)
    compare(Api.listIndexAfterMove(3, -1, 1), 0)
  }

  function test_cursorNavHint_marksTabAndArrowDestinations() {
    var query = {
      currentRegion: "footer",
      currentAction: "play",
      regionActions: ["previous", "play", "next"],
      tabRegion: "sidebar",
      tabAction: "nav-home",
      backtabRegion: "page",
      backtabAction: "list",
      modifiersHeld: false
    }
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "footer", action: "play"
    })), "↵")
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "footer", action: "next"
    })), "↓")
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "footer", action: "previous"
    })), "↑")
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "sidebar", action: "nav-home"
    })), "Tab")
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "page", action: "list"
    })), "⇧Tab")
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "footer", action: "next", modifiersHeld: true
    })), "")
    compare(Api.cursorNavHint(Api.assign(Api.assign({}, query), {
      region: "sidebar", action: "nav-home", modifiersHeld: true
    })), "Tab")
    compare(Api.cursorNavHint({
      region: "popup",
      action: "sleep-30",
      currentRegion: "popup",
      currentAction: "sleep-15",
      regionActions: ["sleep-15", "sleep-30", "sleep-cancel"],
      tabRegion: "popup",
      tabAction: "sleep-30"
    }), "Tab")
    compare(Api.cursorNavHint({
      region: "footer",
      action: "play",
      currentRegion: "footer",
      currentAction: "play",
      tabRegion: "footer",
      tabAction: "play",
      cursorActive: false
    }), "Tab")
  }

  function test_cursorListRowHint_marksTheRowsArrowsWouldPress() {
    var list = {
      count: 5,
      currentIndex: 3,
      atList: true,
      modifiersHeld: false
    }
    compare(Api.cursorListRowHint(Api.assign({ rowIndex: 3 }, list)), "↵")
    compare(Api.cursorListRowHint(Api.assign({ rowIndex: 2 }, list)), "↑")
    compare(Api.cursorListRowHint(Api.assign({ rowIndex: 4 }, list)), "↓")
    compare(Api.cursorListRowHint(Api.assign({ rowIndex: 0 }, list)), "")
    compare(Api.cursorListRowHint({
      rowIndex: 0, count: 5, currentIndex: 3, previousIsCurrent: true
    }), "↓")
    compare(Api.cursorListRowHint({
      rowIndex: 4, count: 5, currentIndex: 3, nextIsCurrent: true
    }), "↑")
    compare(Api.cursorNavHint({
      region: "sidebar",
      action: "nav-settings",
      currentRegion: "sidebar",
      currentAction: "sidebar-playlists",
      regionActions: ["nav-playlists", "sidebar-playlists", "nav-settings"],
      listAction: "sidebar-playlists",
      listIndex: 3,
      listCount: 8
    }), "")
    compare(Api.cursorNavHint({
      region: "sidebar",
      action: "nav-settings",
      currentRegion: "sidebar",
      currentAction: "sidebar-playlists",
      regionActions: ["nav-playlists", "sidebar-playlists", "nav-settings"],
      listAction: "sidebar-playlists",
      listIndex: 7,
      listCount: 8
    }), "↓")
    compare(Api.cursorListRowHint({
      rowIndex: 3, count: 8, currentIndex: 3, tabIsList: true, tabRowIndex: 1
    }), "")
    compare(Api.cursorListRowHint({
      rowIndex: 1, count: 8, currentIndex: 3, tabIsList: true, tabRowIndex: 1
    }), "Tab")
    compare(Api.cursorListRowHint({
      rowIndex: 1, count: 8, currentIndex: 3, tabIsList: true, tabRowIndex: 1,
      modifiersHeld: true
    }), "Tab")
    compare(Api.cursorListRowHint({
      rowIndex: 3, count: 5, currentIndex: 3, atList: true, tabIsList: true
    }), "↵")
    compare(Api.listHintRowIndex(8, 1), 1)
    compare(Api.listHintRowIndex(8, -1), 0)
    compare(Api.listHintRowIndex(0, 0), -1)
  }

  function test_tabCursorDestination_entersTheSongListThenLeaves() {
    var regions = ["sidebar", "header", "page", "footer"]
    var actionsByRegion = {
      sidebar: ["nav-home", "nav-playlists", "sidebar-playlists", "nav-settings"],
      header: ["search", "help", "close"],
      page: ["playlist-play", "playlist-more", "sort", "list", "more"],
      footer: ["shuffle", "play", "next"]
    }
    var base = {
      regions: regions,
      actionsByRegion: actionsByRegion,
      pageActions: actionsByRegion.page,
      listCount: 12
    }
    function dest(region, action, back) {
      return Api.tabCursorDestination(Api.assign(Api.assign({}, base), {
        currentRegion: region,
        currentAction: action,
        back: back === true
      }))
    }
    var next = dest("header", "search")
    compare(next.region, "page")
    compare(next.action, "list")
    next = dest("page", "playlist-play")
    compare(next.region, "page")
    compare(next.action, "list")
    next = dest("page", "sort")
    compare(next.region, "page")
    compare(next.action, "list")
    next = dest("page", "list")
    compare(next.region, "footer")
    compare(next.action, "play")
    next = dest("page", "more")
    compare(next.region, "footer")
    compare(next.action, "play")
    next = dest("footer", "play")
    compare(next.region, "sidebar")
    compare(next.action, "nav-home")
    next = dest("footer", "play", true)
    compare(next.region, "page")
    compare(next.action, "list")
    next = dest("page", "list", true)
    compare(next.region, "page")
    compare(next.action, "sort")
    next = dest("page", "more", true)
    compare(next.region, "page")
    compare(next.action, "list")
    next = dest("page", "playlist-play", true)
    compare(next.region, "header")
    compare(next.action, "search")
    next = dest("header", "search", true)
    compare(next.region, "sidebar")
    compare(next.action, "nav-settings")
    next = Api.tabCursorDestination(Api.assign(Api.assign({}, base), {
      currentRegion: "footer",
      currentAction: "play",
      cursorActive: false
    }))
    compare(next.region, "footer")
    compare(next.action, "play")
    var searchPage = ["search-track", "search-artist", "search-album", "list"]
    next = Api.tabCursorDestination({
      regions: regions,
      currentRegion: "header",
      currentAction: "scope",
      pageActions: searchPage,
      actionsByRegion: {
        sidebar: actionsByRegion.sidebar,
        header: actionsByRegion.header,
        page: searchPage,
        footer: actionsByRegion.footer
      },
      listCount: 8,
      pageLanding: "search-track"
    })
    compare(next.region, "page")
    compare(next.action, "search-track")
    next = Api.tabCursorDestination({
      regions: regions,
      currentRegion: "page",
      currentAction: "search-track",
      pageActions: searchPage,
      actionsByRegion: {
        sidebar: actionsByRegion.sidebar,
        header: actionsByRegion.header,
        page: searchPage,
        footer: actionsByRegion.footer
      },
      listCount: 8,
      pageLanding: "search-track"
    })
    compare(next.region, "page")
    compare(next.action, "list")
    var artistPage = ["detail-play", "list-albums", "list-songs", "detail-thisis"]
    next = Api.tabCursorDestination({
      regions: regions,
      currentRegion: "header",
      currentAction: "search",
      pageActions: artistPage,
      actionsByRegion: {
        sidebar: actionsByRegion.sidebar,
        header: actionsByRegion.header,
        page: artistPage,
        footer: actionsByRegion.footer
      },
      listCount: 6
    })
    compare(next.region, "page")
    compare(next.action, "list-albums")
    next = Api.tabCursorDestination({
      regions: regions,
      currentRegion: "page",
      currentAction: "list-albums",
      pageActions: artistPage,
      actionsByRegion: {
        sidebar: actionsByRegion.sidebar,
        header: actionsByRegion.header,
        page: artistPage,
        footer: actionsByRegion.footer
      },
      listCount: 6
    })
    compare(next.region, "page")
    compare(next.action, "list-songs")
    next = Api.tabCursorDestination({
      regions: regions,
      currentRegion: "page",
      currentAction: "list-songs",
      pageActions: artistPage,
      actionsByRegion: {
        sidebar: actionsByRegion.sidebar,
        header: actionsByRegion.header,
        page: artistPage,
        footer: actionsByRegion.footer
      },
      listCount: 6
    })
    compare(next.region, "footer")
    compare(next.action, "play")
    verify(Api.isCursorListAction("list"))
    verify(Api.isCursorListAction("list-songs"))
    verify(!Api.isCursorListAction("sort"))
  }

  function test_tabCursorDestination_skipsEmptyListsAndCyclesPopups() {
    var empty = Api.tabCursorDestination({
      regions: ["header", "page", "footer"],
      currentRegion: "header",
      currentAction: "search",
      pageActions: ["sort", "list"],
      actionsByRegion: {
        header: ["search"],
        page: ["sort", "list"],
        footer: ["play"]
      },
      listCount: 0
    })
    compare(empty.region, "page")
    compare(empty.action, "sort")
    var popup = Api.tabCursorDestination({
      regions: ["popup"],
      currentRegion: "popup",
      currentAction: "sleep-15",
      actionsByRegion: { popup: ["sleep-15", "sleep-30", "sleep-cancel"] }
    })
    compare(popup.region, "popup")
    compare(popup.action, "sleep-30")
  }

  function test_searchEscapeAction_clearsThenReleasesFocus() {
    compare(Api.searchEscapeAction(true, true, "query", false), "dismiss")
    compare(Api.searchEscapeAction(true, false, "query", false), "dismiss")
    compare(Api.searchEscapeAction(true, false, "", true), "dismiss")
    compare(Api.searchEscapeAction(true, true, "", false), "blur")
    compare(Api.searchEscapeAction(true, true, "   ", false), "blur")
    compare(Api.searchEscapeAction(true, false, "", false), "")
    compare(Api.searchEscapeAction(false, true, "query", true), "")
  }


  // These records reach hundreds of kilobytes. Comparing two of them by
  // stringifying both costs more than the merge that produced them.
  function test_recordCompare_spotsAChangeWithoutStringifyingTheRecord() {
    verify(Api.sameTimeMap({ "a": 1, "b": 2 }, { "b": 2, "a": 1 }))
    verify(!Api.sameTimeMap({ "a": 1 }, { "a": 2 }))
    verify(!Api.sameTimeMap({ "a": 1 }, { "a": 1, "b": 2 }))
    verify(!Api.sameTimeMap({ "a": 1, "b": 2 }, { "a": 1 }))
    verify(Api.sameTimeMap(null, ({})))

    verify(Api.sameTouchDates({ "a": { at: 1, source: "liked" } },
      { "a": { at: 1, source: "liked" } }))
    verify(!Api.sameTouchDates({ "a": { at: 1, source: "liked" } },
      { "a": { at: 1, source: "saved" } }))
    verify(!Api.sameTouchDates({ "a": { at: 1, source: "liked" } },
      { "a": { at: 2, source: "liked" } }))

    verify(Api.sameLikedIndex({ "ar": ["t1", "t2"] }, { "ar": ["t1", "t2"] }))
    verify(!Api.sameLikedIndex({ "ar": ["t1", "t2"] }, { "ar": ["t2", "t1"] }))
    verify(!Api.sameLikedIndex({ "ar": ["t1"] }, { "ar": ["t1", "t2"] }))
    verify(!Api.sameLikedIndex({ "ar": ["t1"] }, ({})))
  }

  // Artwork urls come back inside Spotify's answers and are handed straight to
  // curl. Anything that is not a plain https address is not artwork.
  function test_artworkCache_onlyFetchesOverHttps() {
    var items = [{ imageUrl: "https://i.scdn.co/image/one" },
      { imageUrl: "http://i.scdn.co/image/two" },
      { imageUrl: "file:///etc/passwd" },
      { imageUrl: "-o/tmp/owned" },
      { imageUrl: "https://i.scdn.co/image/three" }]
    compare(Api.artworkUrls(items, ({})).join(","),
      "https://i.scdn.co/image/one,https://i.scdn.co/image/three")
  }

  // A page you have already opened is drawn from the last answer while a
  // fresh one is fetched behind it.
  function test_queryCache_saysWhetherAnEntryCanBeDrawnOrMustBeFetched() {
    compare(Api.queryCacheState(null, 1000, 500), "missing")
    compare(Api.queryCacheState({ updatedAt: 900 }, 1000, 500), "missing",
      "an entry with no data is nothing to draw")
    compare(Api.queryCacheState({ updatedAt: 900, data: ({}) }, 1000, 500), "fresh")
    compare(Api.queryCacheState({ updatedAt: 100, data: ({}) }, 1000, 500), "stale")
    compare(Api.queryCacheState({ updatedAt: 0, data: ({}) }, 1000, 500), "stale")
  }

  function test_queryCache_keyIsStableAcrossTheSamePage() {
    compare(Api.queryCacheKey(["detail", "album", "abc"]), "detail:album:abc")
    compare(Api.queryCacheKey(["playlist", null, undefined]), "playlist::")
    compare(Api.queryCacheKey("plain"), "plain")
  }

  function test_queryCache_dropsTheLeastRecentlyWrittenPageOverTheLimit() {
    var state = { entries: ({}), order: [] }
    state = Api.putQueryEntry(state.entries, state.order, "a", { n: 1 }, 10, 2)
    state = Api.putQueryEntry(state.entries, state.order, "b", { n: 2 }, 20, 2)
    state = Api.putQueryEntry(state.entries, state.order, "c", { n: 3 }, 30, 2)
    compare(state.order.join(","), "b,c")
    compare(state.entries["a"], undefined, "the oldest page is forgotten")
    compare(state.entries["c"].data.n, 3)
    compare(state.entries["c"].updatedAt, 30)

    var again = Api.putQueryEntry(state.entries, state.order, "b", { n: 9 }, 40, 2)
    compare(again.order.join(","), "c,b", "writing again moves it to the front")
    compare(again.entries["b"].data.n, 9)

    var dropped = Api.dropQueryEntry(again.entries, again.order, "c")
    compare(dropped.order.join(","), "b")
    compare(dropped.entries["c"], undefined)
  }

  function test_queryCache_survivesAFileRoundTrip() {
    var state = Api.putQueryEntry(({}), [], "detail:album:one", { items: [1, 2] },
      5000, 10)
    var back = Api.parseQueryCache(Api.encodeQueryCache(state.entries, state.order),
      6000, 10000)
    compare(back.order.join(","), "detail:album:one")
    compare(back.entries["detail:album:one"].data.items.length, 2)
    compare(back.entries["detail:album:one"].updatedAt, 5000)

    var expired = Api.parseQueryCache(
      Api.encodeQueryCache(state.entries, state.order), 60000, 10000)
    compare(expired.order.length, 0, "an answer this old is not worth drawing")
    compare(JSON.stringify(Api.parseQueryCache("not json", 1, 10)),
      JSON.stringify({ entries: ({}), order: [] }))
    compare(Api.parseQueryCache('{"version":99,"order":["a"],"entries":{"a":{}}}',
      1, 10).order.length, 0, "a record written by another version is ignored")
  }

  // Half a page is not worth putting away, and a page kept forever is not
  // worth the disk it sits on.
  function test_queryCache_onlyKeepsAPageThatHasSomethingOnIt() {
    verify(!Api.pageSnapshotHasContent(null))
    verify(!Api.pageSnapshotHasContent({ items: [1] }))
    verify(Api.pageSnapshotHasContent({ item: { id: "a" }, items: [1] }))
    verify(Api.pageSnapshotHasContent({ item: { id: "a" }, songs: [1] }))
    verify(!Api.pageSnapshotHasContent({ item: { id: "a" }, items: [] }))
  }

  function test_queryCache_trimsALongPageBeforeKeepingIt() {
    var snapshot = { item: { id: "a" }, items: [1, 2, 3, 4], songs: [1, 2, 3],
      next: "cursor" }
    var capped = Api.cappedPageSnapshot(snapshot, 2)
    compare(capped.items.length, 2)
    compare(capped.songs.length, 2)
    compare(capped.next, "", "a trimmed page cannot page on from where it stopped")
    compare(capped.item.id, "a")
    compare(snapshot.items.length, 4, "the page on screen is left alone")
    compare(Api.cappedPageSnapshot({ item: { id: "a" }, items: [1], next: "c" },
      5).next, "c", "an untrimmed page keeps its cursor")

    // Only the list that was cut loses its place.
    var mixed = Api.cappedPageSnapshot({ item: { id: "a" }, songs: [1, 2, 3],
      songsNext: "more-songs", albums: [1], albumsNext: "more-albums" }, 2)
    compare(mixed.songsNext, "")
    compare(mixed.albumsNext, "more-albums")
  }

  function test_opaqueSurface_floorsAlphaAndKeepsHue() {
    var glass = Qt.rgba(0.95, 0.95, 0.97, 0.3)
    var floored = Api.opaqueSurface(glass, 0.96)
    fuzzyCompare(floored.a, 0.96, 0.001)
    fuzzyCompare(floored.r, 0.95, 0.001)
    fuzzyCompare(floored.b, 0.97, 0.001)
    var solid = Qt.rgba(0.1, 0.1, 0.1, 1)
    compare(Api.opaqueSurface(solid, 0.96), solid)
    compare(Api.opaqueSurface(null, 0.96), null)
  }

  function test_barSlotWidth_fixedReservesTheCapAndCappedTrimsOnly() {
    compare(Api.barSlotWidth(false, 240, 180, 32), 180)
    compare(Api.barSlotWidth(false, 240, 400, 32), 240)
    compare(Api.barSlotWidth(true, 240, 180, 32), 240)
    compare(Api.barSlotWidth(true, 240, 400, 32), 240)
    compare(Api.barSlotWidth(true, 0, 180, 32), 180)
    compare(Api.barSlotWidth(false, 0, 400, 32), 400)
    compare(Api.barSlotWidth(true, 240, 0, 32), 240)
    compare(Api.barSlotWidth(false, 240, 10, 32), 32)
    compare(Api.barSlotWidth(false, "240", "180", "32"), 180)
  }

  function test_resumeCandidateFromRecentlyPlayed_keepsPlaylistContext() {
    var candidate = Api.resumeCandidateFromRecentlyPlayed({
      items: [{
        played_at: "2026-09-05T09:00:00Z",
        context: { type: "playlist", uri: "spotify:playlist:abc" },
        track: {
          id: "t1", uri: "spotify:track:t1", name: "Blue in Green",
          type: "track", artists: [{ name: "Miles Davis" }],
          album: { name: "Kind of Blue", images: [] }
        }
      }]
    }, 96)
    compare(candidate.item.uri, "spotify:track:t1")
    compare(candidate.item.name, "Blue in Green")
    compare(candidate.item.subtitle, "Miles Davis")
    compare(candidate.contextUri, "spotify:playlist:abc")
    compare(candidate.playedAt, "2026-09-05T09:00:00Z")
  }

  function test_resumeCandidateFromRecentlyPlayed_dropsUnplayableContexts() {
    var artist = Api.resumeCandidateFromRecentlyPlayed({
      items: [{
        context: { type: "artist", uri: "spotify:artist:x" },
        track: { id: "t2", uri: "spotify:track:t2", name: "So What", type: "track" }
      }]
    }, 96)
    compare(artist.item.uri, "spotify:track:t2")
    compare(artist.contextUri, "")
    var collection = Api.resumeCandidateFromRecentlyPlayed({
      items: [{
        context: { type: "collection", uri: "spotify:user:me:collection" },
        track: { id: "t3", uri: "spotify:track:t3", name: "Freddie", type: "track" }
      }]
    }, 96)
    compare(collection.contextUri, "")
  }

  function test_resumeCandidateFromRecentlyPlayed_skipsBrokenEntries() {
    compare(Api.resumeCandidateFromRecentlyPlayed(null, 96), null)
    compare(Api.resumeCandidateFromRecentlyPlayed({ items: [] }, 96), null)
    var candidate = Api.resumeCandidateFromRecentlyPlayed({
      items: [
        null,
        { track: { name: "No uri", type: "track" } },
        { track: { id: "t4", uri: "spotify:track:t4", name: "Ok", type: "track" } }
      ]
    }, 96)
    compare(candidate.item.uri, "spotify:track:t4")
  }

  function test_resumePlaybackAvailable_needsIdleReceiverAndCandidate() {
    var candidate = { item: { uri: "spotify:track:t1", name: "x" } }
    compare(Api.resumePlaybackAvailable(false, candidate), true)
    compare(Api.resumePlaybackAvailable(true, candidate), false)
    compare(Api.resumePlaybackAvailable(false, null), false)
    compare(Api.resumePlaybackAvailable(false, { item: null }), false)
    compare(Api.resumePlaybackAvailable(false, { item: { uri: "" } }), false)
  }

  function test_idleMediaText_prefersLiveThenLastPlayedThenLabel() {
    var item = { name: "Blue in Green", subtitle: "Miles Davis", imageUrl: "" }
    compare(Api.idleMediaText("Live", item, "name", "Nothing playing"), "Live")
    compare(Api.idleMediaText("", item, "name", "Nothing playing"), "Blue in Green")
    compare(Api.idleMediaText("", item, "imageUrl", ""), "")
    compare(Api.idleMediaText("", null, "name", "Nothing playing"), "Nothing playing")
    compare(Api.idleMediaText("", item, "missing", ""), "")
  }
}
