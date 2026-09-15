.pragma library

var API_BASE = "https://api.spotify.com/v1"
var TOKEN_URL = "https://accounts.spotify.com/api/token"
var AUTH_URL = "https://accounts.spotify.com/authorize"

// Deliberately omit profile and email scopes. The remaining scopes correspond
// directly to visible library, history, playlist, and playback controls.
var SCOPES = [
  "user-library-read",
  "user-library-modify",
  "user-follow-read",
  "user-follow-modify",
  "user-read-recently-played",
  "user-read-playback-position",
  "user-top-read",
  "playlist-read-private",
  "playlist-read-collaborative",
  "playlist-modify-private",
  "playlist-modify-public",
  "user-read-playback-state",
  "user-modify-playback-state"
]

var SEARCH_TYPES = ["track", "artist", "album", "playlist", "show", "episode", "audiobook"]
var DISCOVERY_SEARCHES = [
  "Discover Weekly",
  "Release Radar",
  "daylist",
  "Daily Mix",
  "New Music Friday",
  "Fresh Finds"
]

// The playback engine's software mixer spreads its volume over a 60 dB
// logarithmic range. Convert that to a cubic slider over the same range,
// matching the gentler taper used by common desktop audio mixers.
// Zero remains a true mute in both directions.
var ENGINE_CUBIC_FLOOR = 0.1

function clampUnit(value) {
  return Math.max(0, Math.min(1, Number(value) || 0))
}

function normalizeVolumePercent(value) {
  if (value === null || value === undefined || value === "") return null
  var volume = Number(value)
  return isFinite(volume) ? Math.max(0, Math.min(100, volume)) : null
}

function engineVolumeToSlider(value) {
  var volume = clampUnit(value)
  if (volume <= 0) return 0
  var cubicRoot = Math.pow(10, volume - 1)
  return clampUnit((cubicRoot - ENGINE_CUBIC_FLOOR)
    / (1 - ENGINE_CUBIC_FLOOR))
}

function sliderToEngineVolume(value) {
  var slider = clampUnit(value)
  if (slider <= 0) return 0
  var cubicRoot = ENGINE_CUBIC_FLOOR
    + (1 - ENGINE_CUBIC_FLOOR) * slider
  return clampUnit(1 + Math.log(cubicRoot) / Math.LN10)
}

function encode(value) {
  return encodeURIComponent(String(value === undefined || value === null ? "" : value))
}

function queryString(values) {
  if (!values) return ""
  var pairs = []
  var keys = Object.keys(values).sort()
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var value = values[key]
    if (value === undefined || value === null || value === "") continue
    if (Array.isArray(value)) value = value.join(",")
    pairs.push(encode(key) + "=" + encode(value))
  }
  return pairs.join("&")
}

function appendQuery(path, values) {
  var query = queryString(values)
  if (!query) return String(path || "")
  return String(path || "") + (String(path || "").indexOf("?") >= 0 ? "&" : "?") + query
}

function formBody(values) {
  return queryString(values)
}

function shallowCopy(value) {
  var copy = ({})
  if (!value || typeof value !== "object" || Array.isArray(value)) return copy
  for (var key in value) copy[key] = value[key]
  return copy
}

function assign(target, source) {
  var next = target && typeof target === "object" && !Array.isArray(target)
    ? target : ({})
  if (!source || typeof source !== "object" || Array.isArray(source)) return next
  for (var key in source) next[key] = source[key]
  return next
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed === null ? fallback : parsed
  } catch (e) {
    return fallback
  }
}

function barTrackText(title, artist, showTitle, showArtist, playing, showPaused) {
  if (playing !== true && showPaused === false) return ""
  var cleanTitle = String(title || "").trim()
  var cleanArtist = String(artist || "").trim()
  var parts = []
  if (showArtist && cleanArtist) parts.push(cleanArtist)
  if (showTitle && cleanTitle) parts.push(cleanTitle)
  return parts.join(" - ")
}

function canScrollBarText(showTitle, showArtist) {
  return showTitle === true || showArtist === true
}

var BAR_TEXT_WIDTH_MIN = 160
var BAR_TEXT_WIDTH_MAX = 560
var BAR_TEXT_WIDTH_STEP = 40

// Slider geometry for the bar label cap. The uncapped notch sits one step past
// the widest real width, so 0 has somewhere to live without a second control.
function barTextWidthSlider() {
  return {
    min: BAR_TEXT_WIDTH_MIN,
    step: BAR_TEXT_WIDTH_STEP,
    unlimited: BAR_TEXT_WIDTH_MAX + BAR_TEXT_WIDTH_STEP,
    ticks: (BAR_TEXT_WIDTH_MAX - BAR_TEXT_WIDTH_MIN) / BAR_TEXT_WIDTH_STEP + 2
  }
}

// Cap in unscaled px, snapped to the slider's notches. 0 means no cap;
// anything unparseable falls back to the historical 240px bound.
function normalizedMaxBarTextWidth(value) {
  if (value === undefined || value === null || String(value).trim() === "")
    return 240
  var width = Number(value)
  if (!isFinite(width) || width < 0) return 240
  if (width === 0) return 0
  var clamped = Math.max(BAR_TEXT_WIDTH_MIN, Math.min(BAR_TEXT_WIDTH_MAX, width))
  return BAR_TEXT_WIDTH_MIN + Math.round(
    (clamped - BAR_TEXT_WIDTH_MIN) / BAR_TEXT_WIDTH_STEP) * BAR_TEXT_WIDTH_STEP
}

function normalizedScrollSpeed(value) {
  var speed = Number(value)
  if (!isFinite(speed)) speed = 1
  return Math.round(Math.max(0.25, Math.min(3, speed)) * 4) / 4
}

function timestampIsFresh(timestamp, now, lifetimeMs) {
  var checkedAt = Number(timestamp)
  var current = Number(now)
  var lifetime = Number(lifetimeMs)
  if (!isFinite(checkedAt) || !isFinite(current) || !isFinite(lifetime)
      || checkedAt <= 0 || lifetime <= 0) return false
  var age = current - checkedAt
  return age >= 0 && age < lifetime
}

function deadlineRemainingSeconds(deadline, now) {
  var end = Number(deadline)
  var current = Number(now)
  if (!isFinite(end) || !isFinite(current)) return 0
  return Math.max(0, Math.ceil((end - current) / 1000))
}

// Maintain a small least-recently-touched key order without replacing the
// caller's array. One touch can add at most one key, so a single returned key
// lets callers evict the matching map entry without replacement collections.
function touchBoundedOrder(order, key, limit) {
  if (!Array.isArray(order)) return ""
  var name = String(key || "")
  if (!name) return ""
  var maximum = Math.max(0, Math.floor(Number(limit) || 0))
  var oldIndex = order.indexOf(name)
  if (oldIndex >= 0) order.splice(oldIndex, 1)
  order.push(name)
  return order.length > maximum ? String(order.shift() || "") : ""
}

// Nested arrays become array-like QML sequences after passing through a
// ListView model. Preserve them instead of relying on Array.isArray(), which
// returns false for that representation.
function arrayValues(values) {
  if (Array.isArray(values)) return values
  if (!values || typeof values === "string") return []
  var length = Number(values.length)
  if (!isFinite(length) || length <= 0) return []
  var result = []
  for (var i = 0; i < Math.floor(length); i++) result.push(values[i])
  return result
}

function safeApiUrl(path) {
  var value = String(path || "")
  if (value.charAt(0) === "/") return API_BASE + value
  if (value === API_BASE || value.indexOf(API_BASE + "/") === 0) return value
  return ""
}

function redact(value) {
  var text = String(value || "")
  text = text.replace(/(authorization\s*:\s*bearer\s+)[^\s]+/ig, "$1<redacted>")
  text = text.replace(/(^|[?&\s])((?:code|access_token|refresh_token|code_verifier|client_secret|password)=)[^&#\s]+/ig, "$1$2<redacted>")
  text = text.replace(/("(?:access_token|refresh_token|code|code_verifier|client_secret|password)"\s*:\s*")[^"]+/ig, "$1<redacted>")
  return text
}

function responseError(status, payload, fallback) {
  var message = ""
  if (payload && typeof payload === "object") {
    if (typeof payload.error === "object" && payload.error) {
      message = payload.error.message || payload.error.status || ""
      if (payload.error.reason && String(payload.error.reason) !== String(message))
        message += (message ? " (" : "") + String(payload.error.reason) + (message ? ")" : "")
    }
    else if (typeof payload.error === "string")
      message = payload.error_description || payload.error
    else
      message = payload.message || ""
  }
  if (!message) message = fallback || "Spotify could not complete this request"
  return redact(message)
}

function rateLimitSuffix(retryAfter) {
  var seconds = Number(String(retryAfter || "").trim())
  if (!isFinite(seconds) || seconds <= 0) return ""
  seconds = Math.max(1, Math.round(seconds))
  return ". Try again in " + seconds + (seconds === 1 ? " second" : " seconds") + "."
}

function rateLimitMessage(retryAfter) {
  var suffix = rateLimitSuffix(retryAfter)
  return suffix ? "Spotify is busy" + suffix
    : "Spotify is busy. Try again in a moment."
}

var API_MAX_IN_FLIGHT = 4
var API_MAX_RATE_LIMIT_RETRIES = 4

function rateLimitRetryMs(retryAfter, attempt) {
  var value = String(retryAfter || "").trim()
  var seconds = Number(value)
  if (!value || !isFinite(seconds) || seconds < 0) return 10000
  var headerMs = Math.round(seconds * 1000)
  var retry = Math.max(0, Math.floor(Number(attempt) || 0))
  var backoffMs = 1000 * Math.pow(2, retry)
  // Spotify often 429s again if we retry at exactly Retry-After, especially
  // when the header is 1 second. Cap our backoff, never the server delay.
  return Math.max(1000, headerMs, Math.min(30000, backoffMs)) + 400
}

function shouldRetryRateLimit(retriesSoFar) {
  return (Number(retriesSoFar) || 0) < API_MAX_RATE_LIMIT_RETRIES
}

function apiInFlightLimit(restricted) {
  return restricted === true ? 1 : API_MAX_IN_FLIGHT
}

function responseRetryAfter(xhr) {
  if (!xhr || typeof xhr.getResponseHeader !== "function") return ""
  var value = xhr.getResponseHeader("Retry-After")
  if (!value) value = xhr.getResponseHeader("retry-after")
  return value ? String(value) : ""
}

function apiRequestIsMutating(method) {
  var value = String(method || "GET").toUpperCase()
  return value !== "GET" && value !== "HEAD"
}

function apiJobPriority(job) {
  if (!job) return 0
  if (apiRequestIsMutating(job.method)) return 2
  var priority = String(job.priority || "")
  if (priority === "interactive") return 1
  // Library crawling waits behind anything the person actually asked for.
  return priority === "background" ? -1 : 0
}

function enqueueApiJob(queue, job) {
  var next = arrayValues(queue)
  if (!job) return next
  var priority = apiJobPriority(job)
  var index = 0
  while (index < next.length && apiJobPriority(next[index]) >= priority) index++
  next.splice(index, 0, job)
  return next
}

// Background work never takes the last slots, so a page you open has somewhere
// to run even while the library is loading.
// Background dispatches are spaced apart. A burst of them is what trips
// Spotify's limit on a cold start.
var API_BACKGROUND_SPACING_MS = 500
var API_BACKGROUND_SPACING_MAX_MS = 8000

// We share a client ID with every other app built on it, so the leftover
// budget is unknowable. A refusal stops every request for about twenty
// seconds, so the gap doubles each time and never narrows again this run.
function backgroundSpacingForRefusals(refusals) {
  var count = Math.max(0, Math.floor(Number(refusals) || 0))
  if (count > 8) count = 8
  return Math.min(API_BACKGROUND_SPACING_MAX_MS,
    API_BACKGROUND_SPACING_MS * Math.pow(2, count))
}

function backgroundStartDelay(lastStartedAt, nowMs, spacingMs) {
  var last = Number(lastStartedAt) || 0
  if (last <= 0) return 0
  var gap = (Number(nowMs) || 0) - last
  var spacing = Number(spacingMs) || 0
  return gap >= spacing ? 0 : Math.ceil(spacing - gap)
}

// Background work also stands aside for a moment after anything the person
// opened, so a click gets the whole of a budget it may be sharing.
var API_BACKGROUND_YIELD_MS = 3000

function backgroundDispatchDelay(lastBackgroundAt, lastInteractiveAt, nowMs, spacingMs) {
  return Math.max(
    backgroundStartDelay(lastBackgroundAt, nowMs, spacingMs),
    backgroundStartDelay(lastInteractiveAt, nowMs, API_BACKGROUND_YIELD_MS))
}

function backgroundInFlightLimit(limit) {
  var total = Math.max(1, Math.floor(Number(limit) || 1))
  return Math.max(1, Math.min(2, total - 2))
}

function dequeueApiJob(queue, allowBackground) {
  // Copy first: shifting the caller's own array is a nasty surprise.
  var next = arrayValues(queue).slice()
  var skipped = []
  while (next.length) {
    var job = next.shift()
    if (!job || (job.handle && job.handle.aborted === true)) continue
    if (allowBackground === false && apiJobPriority(job) < 0) {
      skipped.push(job)
      continue
    }
    return { job: job, queue: skipped.concat(next) }
  }
  return { job: null, queue: skipped }
}

function apiCooldownMs(now, until) {
  var wait = (Number(until) || 0) - (Number(now) || 0)
  return wait > 0 ? Math.ceil(wait) : 0
}

// A refusal usually comes from the shared budget rather than from us, so
// waiting the whole of it out leaves an opened page blank for that long.
// Whatever the person is watching pauses this much and then tries anyway.
var API_FOREGROUND_COOLDOWN_CAP_MS = 1500

// Which pause applies to a job. A refusal is nearly always the shared budget
// running dry on background work, and freezing the page someone just opened
// because the library crawl was told to wait is the whole of why a page took
// twenty seconds. Their own request being refused is the only thing that
// holds them back.
function jobCooldownMs(job, nowMs, backgroundUntil, interactiveUntil) {
  if (!job) return 0
  return apiJobPriority(job) >= 1
    ? apiCooldownMs(nowMs, interactiveUntil)
    : apiCooldownMs(nowMs, backgroundUntil)
}

// One early try per refusal, in case it has slack in it. Only for a page
// someone is watching, only once however many are waiting, and never again for
// a request that has already been refused itself.
function jobMayRunDuringCooldown(job, probeUsed) {
  if (!job || probeUsed === true) return false
  return apiJobPriority(job) >= 1 && (Number(job.rateLimitRetries) || 0) === 0
}

function foregroundCooldownMs(nowMs, until, since, capMs) {
  var wait = apiCooldownMs(nowMs, until)
  if (wait <= 0) return 0
  var cap = Number(capMs)
  if (!isFinite(cap) || cap < 0) cap = API_FOREGROUND_COOLDOWN_CAP_MS
  var waited = (Number(nowMs) || 0) - (Number(since) || 0)
  var remaining = cap - waited
  return remaining > 0 ? Math.ceil(Math.min(wait, remaining)) : 0
}

// A personal client id gets its own quota, but Spotify stopped giving new apps
// the catalog endpoints, so it answers 403 for related artists and a bogus
// "Invalid limit" 400 for an artist's albums. The shipped id predates that
// change and still reaches them, so what the personal one refuses is tried
// once through it. 401 is a token to refresh, and 429 means slow down rather
// than go spend the shared quota instead.
function shouldFallBackToSharedClient(status, alreadyFellBack, hasFallback,
    method, path) {
  if (hasFallback !== true || alreadyFellBack === true) return false
  // Never repeat something that changes state, and never send your own library
  // to the shared quota: a personal client reads /me perfectly well, so a
  // refusal there is a real error rather than a closed endpoint.
  if (String(method || "GET").toUpperCase() !== "GET") return false
  if (apiRequestPath(path).indexOf("/me") === 0) return false
  var code = Number(status) || 0
  if (code === 401 || code === 429) return false
  return code >= 400 && code < 500
}

function isSpotifyPlaylist(playlist) {
  return !!playlist && String(playlist.ownerId || "") === "spotify"
}

// Newer apps get a playlist list without Spotify's own, so those are fetched apart and swapped in.
function withSpotifyPlaylists(playlists, spotifyOwn) {
  var mine = (Array.isArray(playlists) ? playlists : []).filter(function(playlist) {
    return !isSpotifyPlaylist(playlist)
  })
  return mergeUnique(mine, spotifyOwn)
}

// Paging cursors come back as absolute urls, so compare the path either way.
function apiRequestPath(path) {
  var value = String(path || "")
  return value.indexOf(API_BASE) === 0 ? value.slice(API_BASE.length) : value
}

function nextRateLimitedUntil(now, retryAfter, currentUntil, attempt) {
  var proposed = (Number(now) || 0) + rateLimitRetryMs(retryAfter, attempt)
  var existing = Number(currentUntil) || 0
  return proposed > existing ? proposed : existing
}

function playlistOwnedByUser(playlist, userId) {
  var user = String(userId || "")
  return !!playlist && !!user && String(playlist.ownerId || "") === user
}

function playlistItemsHiddenByApi(status, owned, collaborative, knownUser) {
  if (owned === true || collaborative === true || knownUser !== true) return false
  var code = Number(status) || 0
  return code === 403 || code === 200
}

function playlistItemsHiddenMessage() {
  return "Spotify does not expose the contents of this playlist unless you own or collaborate on it. You can still play it as a Spotify context."
}

function playlistItemsEmptyMessage(playlist, itemCount, error, status, userId) {
  if (!playlist) return ""
  var count = Number(itemCount) || 0
  var owned = playlistOwnedByUser(playlist, userId)
  var collaborative = !!(playlist && playlist.collaborative === true)
  var knownUser = String(userId || "") !== ""
  if (error) {
    if (playlistItemsHiddenByApi(status, owned, collaborative, knownUser))
      return playlistItemsHiddenMessage()
    return "Couldn't load this playlist. Try again in a moment."
  }
  if (count > 0) return ""
  if (playlistItemsHiddenByApi(200, owned, collaborative, knownUser))
    return playlistItemsHiddenMessage()
  return "This playlist has no visible items."
}

function localSocketFallbackMessage() {
  return "The local player was not ready, so this track is starting through Spotify."
}

// While a player surface is open, keep this computer registered as a Spotify
// Connect receiver. The configured idle timeout begins only after every player
// surface closes.
function visibleLocalReceiverAction(uiVisible, fullyConnected, running, busy) {
  if (uiVisible !== true || fullyConnected !== true) return "idle"
  if (busy === true) return "wait"
  if (running === true) return "refresh"
  return "start"
}

// A paused item is still an active media session: keep its MPRIS metadata and
// resume controls alive after the UI closes. Only an empty/stopped receiver is
// eligible for the configured background shutdown timeout.
function idleShutdownShouldRun(daemonRunning, hasMedia, uiVisible, idleMinutes) {
  return daemonRunning === true && hasMedia !== true && uiVisible !== true
    && Number(idleMinutes) > 0
}

function remotePlaybackPollShouldRun(loggedIn, loading, uiVisible, useRemote,
    playing) {
  if (loggedIn !== true || loading === true) return false
  if (uiVisible === true) return true
  return useRemote === true && playing === true
}

// How often to ask Spotify what is playing. This is the largest single source
// of traffic on a client id shared with every other app built on it, and most
// of what it asked for was already known: MPRIS pushes local playback changes
// as they happen and costs nothing. So the Web API is only hurried when it is
// the sole source of truth, and only while something is actually moving.
function remotePlaybackPollInterval(uiVisible, useRemote, hasLocal, playing) {
  if (uiVisible !== true) return 15000
  if (hasLocal === true && playing === true) return 60000
  if (useRemote === true && playing === true) return 5000
  return 15000
}

function normalizedShortcutPlayer(value) {
  var text = String(value || "")
  if (text === "Full player") return "Full player"
  if (text === "Mini player") return "Mini player"
  return "Omarchy Music app"
}

// Spotify's own loudness targets are -11, -14 and -19 LUFS. librespot
// normalises to its own target, so a level is a pregain offset from Normal.
var VOLUME_LEVEL_PREGAIN_DB = { Loud: 3, Normal: 0, Quiet: -5 }

// How the library sidebar can be ordered. "library" is Spotify's own order,
// which /me/playlists returns verbatim, so it is the default.
var LIBRARY_SORT_MODES = ["library", "recent", "added", "alpha"]
var LIBRARY_VIEW_MODES = ["compact-list", "list", "compact-grid", "grid"]

// Rank contexts by the newest play seen for each. Spotify only returns the last
// 50 plays, so this is a shallow window by design.
// A played track dates its album and everyone on it, not just the playlist it
// came from.
function recentContextPlayTimes(payload) {
  var items = payload && Array.isArray(payload.items) ? payload.items : []
  var times = {}
  for (var i = 0; i < items.length; i++) {
    var row = items[i]
    if (!row) continue
    var at = Date.parse(String(row.played_at || ""))
    if (!isFinite(at)) continue
    var track = row.track || {}
    var uris = artistUris(track)
    if (row.context && row.context.uri) uris.push(String(row.context.uri))
    if (track.album && track.album.uri) uris.push(String(track.album.uri))
    for (var j = 0; j < uris.length; j++) {
      var uri = uris[j]
      if (!uri) continue
      if (!times[uri] || at > times[uri]) times[uri] = at
    }
  }
  return times
}

// Spotify caps recently-played at 50 plays, which is often only a day or two.
// Top tracks and top artists cover roughly four weeks, so anything in them was
// listened to inside that window. Date those at the far edge of the window: it
// lifts them above older saves without pretending we know the exact moment.
function recentListenWindow(topTracks, topArtists, nowMs, windowDays) {
  var now = Number(nowMs) || 0
  var days = Math.max(1, Number(windowDays) || 28)
  var day = 24 * 3600 * 1000
  // The rank says how much something was played, not when, so the whole range
  // sits at least a week back: fresh saves and real plays still lead.
  var newest = now - 7 * day
  var oldest = now - days * day

  var times = {}
  function place(uri, rank, total) {
    if (!uri) return
    var span = Math.max(1, total - 1)
    var at = newest - (newest - oldest) * (Math.min(rank, span) / span)
    if (!times.hasOwnProperty(uri) || at > times[uri]) times[uri] = at
  }

  var tracks = topTracks && Array.isArray(topTracks.items) ? topTracks.items : []
  for (var i = 0; i < tracks.length; i++) {
    var album = tracks[i] && tracks[i].album
    place(album ? String(album.uri || "") : "", i, tracks.length)
  }
  var artists = topArtists && Array.isArray(topArtists.items) ? topArtists.items : []
  for (var j = 0; j < artists.length; j++) {
    place(artists[j] ? String(artists[j].uri || "") : "", j, artists.length)
  }
  return times
}

// An exact play time always beats the window estimate.
// Spotify only returns the last 50 plays and will not page back further, so we
// keep our own record and fold each new batch into it. It deepens with use.
function mergePlayHistory(stored, fresh) {
  var out = {}

  function take(source) {
    if (!source || typeof source !== "object") return
    for (var k in source) {
      if (!source.hasOwnProperty(k)) continue
      var at = playTimeOf(source[k])
      if (!(at > 0)) continue
      if (!out.hasOwnProperty(k) || at > out[k]) out[k] = at
    }
  }

  take(stored)
  take(fresh)
  return out
}

// Records this big cost more to compare by stringifying than they cost to
// build, and they are rebuilt on every page of the library crawl.
function sameTimeMap(left, right) {
  return sameKeys(left, right, function(a, b) { return a === b })
}

function sameTouchDates(left, right) {
  return sameKeys(left, right, function(a, b) {
    return playTimeOf(a) === playTimeOf(b) && playSourceOf(a) === playSourceOf(b)
  })
}

function sameLikedIndex(left, right) {
  return sameKeys(left, right, function(a, b) {
    var one = Array.isArray(a) ? a : []
    var two = Array.isArray(b) ? b : []
    if (one.length !== two.length) return false
    for (var i = 0; i < one.length; i++)
      if (String(one[i]) !== String(two[i])) return false
    return true
  })
}

function sameKeys(left, right, equal) {
  var a = left && typeof left === "object" ? left : ({})
  var b = right && typeof right === "object" ? right : ({})
  var count = 0
  for (var k in a) {
    if (!a.hasOwnProperty(k)) continue
    if (!b.hasOwnProperty(k) || !equal(a[k], b[k])) return false
    count++
  }
  for (var other in b) if (b.hasOwnProperty(other)) count--
  return count === 0
}

// Spotify has no "my liked songs by this artist" endpoint, so the crawl that
// already reads every liked song builds the index as it goes. Only ids are
// kept; the tracks themselves are fetched when an artist page opens.
function likedTrackIdsByArtist(payload) {
  var rows = payload && Array.isArray(payload.items) ? payload.items : []
  var out = {}
  for (var i = 0; i < rows.length; i++) {
    var track = rows[i] && rows[i].track ? rows[i].track : null
    if (!track || !track.id) continue
    var uris = artistUris(track)
    for (var j = 0; j < uris.length; j++) {
      if (!out.hasOwnProperty(uris[j])) out[uris[j]] = []
      out[uris[j]].push(String(track.id))
    }
  }
  return out
}

function mergeLikedIndex(stored, fresh, limit) {
  var cap = Math.max(1, Number(limit) || 200)
  var out = {}
  var key

  function take(source) {
    if (!source || typeof source !== "object") return
    for (var k in source) {
      if (!source.hasOwnProperty(k)) continue
      var ids = Array.isArray(source[k]) ? source[k] : []
      if (!out.hasOwnProperty(k)) out[k] = []
      for (var i = 0; i < ids.length; i++) {
        var id = String(ids[i] || "")
        if (id && out[k].indexOf(id) === -1) out[k].push(id)
      }
    }
  }

  take(stored)
  take(fresh)
  for (key in out) if (out.hasOwnProperty(key)) out[key] = out[key].slice(0, cap)
  return out
}

function withoutLikedTrack(index, trackId) {
  var id = String(trackId || "")
  var out = {}
  for (var k in index) {
    if (!index.hasOwnProperty(k)) continue
    var ids = Array.isArray(index[k]) ? index[k] : []
    out[k] = ids.filter(function(value) { return String(value) !== id })
  }
  return out
}

function idBatches(ids, size) {
  var list = Array.isArray(ids) ? ids : []
  var step = Math.max(1, Number(size) || 50)
  var out = []
  for (var i = 0; i < list.length; i += step) out.push(list.slice(i, i + step))
  return out
}

// Playlists and artists carry no date of their own. These work one out from the
// rest of the library instead: a liked song, a saved album, a playlist edit.
function collectTouchDates(items, source, urisOf) {
  var rows = items && Array.isArray(items.items) ? items.items : []
  var out = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row) continue
    var at = Date.parse(String(row.added_at || ""))
    if (!isFinite(at) || !(at > 0)) continue
    var uris = urisOf(row)
    for (var j = 0; j < uris.length; j++) {
      var uri = uris[j]
      if (!uri) continue
      if (!out.hasOwnProperty(uri) || at > out[uri].at)
        out[uri] = { at: at, source: source }
    }
  }
  return out
}

function artistUris(holder) {
  var list = holder && Array.isArray(holder.artists) ? holder.artists : []
  var out = []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].uri) out.push(String(list[i].uri))
  return out
}

function touchDatesFromSavedTracks(payload) {
  return collectTouchDates(payload, "liked", function(row) {
    var track = row.track || {}
    var uris = artistUris(track)
    if (track.album && track.album.uri) uris.push(String(track.album.uri))
    return uris
  })
}

function touchDatesFromSavedAlbums(payload) {
  return collectTouchDates(payload, "saved", function(row) {
    return artistUris(row.album)
  })
}

function mergeTouchDates(stored, fresh) {
  var out = {}

  function take(source) {
    if (!source || typeof source !== "object") return
    for (var k in source) {
      if (!source.hasOwnProperty(k)) continue
      var at = playTimeOf(source[k])
      if (!(at > 0)) continue
      if (!out.hasOwnProperty(k) || at > out[k].at)
        out[k] = { at: at, source: playSourceOf(source[k]) }
    }
  }

  take(stored)
  take(fresh)
  return out
}

// Only playlists you own: a stranger editing theirs is not you touching it.
// Tracks come back in the order they were added, so the last one is the newest.
function playlistEditRequest(playlist, userId, cached) {
  if (!playlist || !playlist.id) return null
  var owner = String(playlist.ownerId || "")
  if (!owner || !userId || owner !== String(userId)) return null
  var total = Number(playlist.total) || 0
  if (!(total > 0)) return null
  var seen = cached && cached[playlist.id]
  if (seen && seen.snapshot && seen.snapshot === String(playlist.snapshotId || ""))
    return null
  return {
    id: String(playlist.id),
    uri: String(playlist.uri || ""),
    snapshot: String(playlist.snapshotId || ""),
    path: "/playlists/" + playlist.id + "/tracks",
    query: { fields: "items(added_at)", limit: 1, offset: total - 1 }
  }
}

function playlistEditDate(payload) {
  var rows = payload && Array.isArray(payload.items) ? payload.items : []
  if (rows.length === 0) return 0
  var at = Date.parse(String(rows[0].added_at || ""))
  return isFinite(at) && at > 0 ? at : 0
}

// Liked songs arrive newest first, so a watermark stops us re-reading thousands
// of them on every launch.
function newestAddedAt(payload) {
  var rows = payload && Array.isArray(payload.items) ? payload.items : []
  var best = 0
  for (var i = 0; i < rows.length; i++) {
    var at = Date.parse(String(rows[i] && rows[i].added_at || ""))
    if (isFinite(at) && at > best) best = at
  }
  return best
}

// The watermark passed here is what we had before this run started; moving it
// as pages arrive would stop the run on its own second page.
function savedTrackCrawlStep(payload, offset, watermark) {
  var hasNext = !!(payload && payload.next)
  return {
    done: !hasNext || pageReachesWatermark(payload, watermark),
    nextOffset: (Number(offset) || 0) + 50,
    newest: newestAddedAt(payload)
  }
}

function pageReachesWatermark(payload, watermark) {
  var mark = Number(watermark) || 0
  if (!(mark > 0)) return false
  var rows = payload && Array.isArray(payload.items) ? payload.items : []
  for (var i = 0; i < rows.length; i++) {
    var at = Date.parse(String(rows[i] && rows[i].added_at || ""))
    if (isFinite(at) && at <= mark) return true
  }
  return false
}

function encodePlayHistory(record) {
  var value = record || ({})
  return JSON.stringify({
    version: PLAY_RECORD_VERSION,
    plays: value.plays || ({}),
    touched: value.touched || ({}),
    playlistEdits: value.playlistEdits || ({}),
    savedTracksThrough: Number(value.savedTracksThrough) || 0,
    savedTracksOffset: Number(value.savedTracksOffset) || 0,
    savedTracksNewest: Number(value.savedTracksNewest) || 0,
    likedByArtist: value.likedByArtist || ({}),
    playDays: value.playDays || ({}),
    playsCountedThrough: Number(value.playsCountedThrough) || 0
  })
}

function plainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : ({})
}

var PLAY_RECORD_VERSION = 4

function parsePlayHistoryRecord(raw) {
  var record = plainObject(parseJson(raw, ({})))
  // An older record predates fields an incremental crawl cannot backfill, so
  // its watermark is dropped and the next crawl reads everything again.
  var current = Number(record.version) === PLAY_RECORD_VERSION
  return {
    plays: mergePlayHistory(plainObject(record.plays), null),
    touched: mergeTouchDates(plainObject(record.touched), null),
    playlistEdits: plainObject(record.playlistEdits),
    savedTracksThrough: current ? Number(record.savedTracksThrough) || 0 : 0,
    savedTracksOffset: current ? Number(record.savedTracksOffset) || 0 : 0,
    savedTracksNewest: current ? Number(record.savedTracksNewest) || 0 : 0,
    likedByArtist: mergeLikedIndex(plainObject(record.likedByArtist), null, 200),
    playDays: mergeDayCounts(plainObject(record.playDays), null),
    playsCountedThrough: Number(record.playsCountedThrough) || 0
  }
}

// The sidebar is the same library on every launch, so it is kept on disk and
// shown before Spotify answers.
function encodeLibraryCache(playlists, savedAlbums, followedArtists, savedShows,
    fetchedAt) {
  return JSON.stringify({
    version: 1,
    playlists: playlists || [],
    savedAlbums: savedAlbums || [],
    followedArtists: followedArtists || [],
    savedShows: savedShows || [],
    fetchedAt: Number(fetchedAt) || 0
  })
}

// A page you have already opened is drawn from the answer we kept while a
// fresh one is fetched behind it, the way a query cache works on the web.
// Entries carry when they were written so the page can say whether what it is
// showing still counts as current.
var QUERY_CACHE_VERSION = 1

function queryCacheKey(parts) {
  var list = Array.isArray(parts) ? parts : [parts]
  var out = []
  for (var i = 0; i < list.length; i++)
    out.push(list[i] === null || list[i] === undefined ? "" : String(list[i]))
  return out.join(":")
}

// missing: there is nothing to draw, so the page has to wait for Spotify.
// fresh: draw it and ask for nothing. stale: draw it and refetch behind it.
function queryCacheState(entry, nowMs, staleMs) {
  if (!entry || entry.data === undefined || entry.data === null) return "missing"
  return timestampIsFresh(entry.updatedAt, nowMs, staleMs) ? "fresh" : "stale"
}

function putQueryEntry(entries, order, key, data, nowMs, limit) {
  var name = String(key || "")
  var nextEntries = shallowCopy(entries)
  var nextOrder = Array.isArray(order) ? order.slice() : []
  if (!name) return { entries: nextEntries, order: nextOrder }
  nextEntries[name] = { updatedAt: Number(nowMs) || 0, data: data }
  var evicted = touchBoundedOrder(nextOrder, name, limit)
  if (evicted) delete nextEntries[evicted]
  return { entries: nextEntries, order: nextOrder }
}

function dropQueryEntry(entries, order, key) {
  var name = String(key || "")
  var nextEntries = shallowCopy(entries)
  var nextOrder = []
  var source = Array.isArray(order) ? order : []
  delete nextEntries[name]
  for (var i = 0; i < source.length; i++)
    if (String(source[i]) !== name) nextOrder.push(String(source[i]))
  return { entries: nextEntries, order: nextOrder }
}

function encodeQueryCache(entries, order) {
  return JSON.stringify({
    version: QUERY_CACHE_VERSION,
    order: Array.isArray(order) ? order : [],
    entries: entries || ({})
  })
}

// Anything older than the given age is dropped on the way in: showing a page
// from last month before the fresh one lands is worse than showing nothing.
function parseQueryCache(raw, nowMs, maxAgeMs) {
  var record = plainObject(parseJson(raw, ({})))
  var empty = { entries: ({}), order: [] }
  if (Number(record.version) !== QUERY_CACHE_VERSION) return empty
  var stored = plainObject(record.entries)
  var order = Array.isArray(record.order) ? record.order : []
  var out = { entries: ({}), order: [] }
  for (var i = 0; i < order.length; i++) {
    var key = String(order[i] || "")
    var entry = stored[key]
    if (!key || !entry || entry.data === undefined || entry.data === null) continue
    if (!timestampIsFresh(entry.updatedAt, nowMs, maxAgeMs)) continue
    out.entries[key] = { updatedAt: Number(entry.updatedAt) || 0, data: entry.data }
    out.order.push(key)
  }
  return out
}

// A page with a header and no rows is half an answer; drawing it from the
// cache would only replace one empty page with another.
function pageSnapshotHasContent(snapshot) {
  if (!snapshot || !snapshot.item) return false
  for (var key in snapshot) {
    if (!snapshot.hasOwnProperty(key)) continue
    if (Array.isArray(snapshot[key]) && snapshot[key].length > 0) return true
  }
  return false
}

// Long pages are trimmed before being kept, because the whole cache is written
// to disk. A trimmed list loses its cursor: paging on from where the untrimmed
// list stopped would skip every row that was cut.
function cappedPageSnapshot(snapshot, limit) {
  var cap = Math.max(1, Math.floor(Number(limit) || 1))
  var out = ({})
  var cut = []
  for (var key in snapshot) {
    if (!snapshot.hasOwnProperty(key)) continue
    var value = snapshot[key]
    if (Array.isArray(value) && value.length > cap) {
      out[key] = value.slice(0, cap)
      cut.push(key)
    } else out[key] = value
  }
  for (var i = 0; i < cut.length; i++) {
    var cursor = cut[i] === "items" ? "next" : cut[i] + "Next"
    if (out.hasOwnProperty(cursor)) out[cursor] = ""
  }
  return out
}

// The library changes rarely, so a recent copy is trusted rather than
// refetched. That is about thirty requests saved on every launch.
function libraryCacheIsFresh(fetchedAt, nowMs, maxAgeMs) {
  var at = Number(fetchedAt) || 0
  var now = Number(nowMs) || 0
  var age = now - at
  return at > 0 && age >= 0 && age <= (Number(maxAgeMs) || 0)
}

function parseLibraryCache(raw) {
  var record = plainObject(parseJson(raw, ({})))
  function list(value) { return Array.isArray(value) ? value : [] }
  return {
    playlists: list(record.playlists),
    savedAlbums: list(record.savedAlbums),
    followedArtists: list(record.followedArtists),
    savedShows: list(record.savedShows),
    fetchedAt: Number(record.fetchedAt) || 0
  }
}

function parsePlayHistory(raw) {
  return parsePlayHistoryRecord(raw).plays
}

// A play time is either a real timestamp we read from the history, or a guess
// from the top lists. Each entry keeps which one it was so the sort can say so.
function playTimeOf(entry) {
  if (entry && typeof entry === "object") return libraryTimestamp(entry.at)
  return libraryTimestamp(entry)
}

function playSourceOf(entry) {
  if (entry && typeof entry === "object" && entry.source) return String(entry.source)
  return "played"
}

function mergedPlayTimes(exact, touched, estimated) {
  var out = {}

  function take(source, label) {
    if (!source || typeof source !== "object") return
    for (var k in source) {
      if (!source.hasOwnProperty(k)) continue
      var at = playTimeOf(source[k])
      if (!(at > 0)) continue
      if (!out.hasOwnProperty(k) || at >= out[k].at)
        out[k] = { at: at, source: label || playSourceOf(source[k]) }
    }
  }

  take(estimated, "listened")
  take(touched, null)
  take(exact, "played")
  return out
}

function twoDigits(value) {
  return (value < 10 ? "0" : "") + value
}

function shortDate(ms) {
  var d = new Date(Number(ms) || 0)
  return d.getFullYear() + "-" + twoDigits(d.getMonth() + 1) + "-" + twoDigits(d.getDate())
    + " " + twoDigits(d.getHours()) + ":" + twoDigits(d.getMinutes())
    + ":" + twoDigits(d.getSeconds())
}


function librarySortModes() {
  return LIBRARY_SORT_MODES.slice()
}

function libraryViewModes() {
  return LIBRARY_VIEW_MODES.slice()
}

function normalizedLibrarySort(value) {
  var mode = String(value || "")
  return LIBRARY_SORT_MODES.indexOf(mode) >= 0 ? mode : "library"
}

function normalizedLibraryView(value) {
  var mode = String(value || "")
  return LIBRARY_VIEW_MODES.indexOf(mode) >= 0 ? mode : "list"
}

// Order the sidebar. Pinned items lead, in the order they were pinned; the rest
// follow the chosen mode. Items the mode cannot rank — a playlist has no added
// date, an artist never played has no play time — keep Spotify's order at the
// bottom rather than being interleaved as though they were oldest.
// added_at arrives as an ISO string from Spotify but a play time is already a
// number, so accept either.
function libraryTimestamp(value) {
  if (value === null || value === undefined || value === "") return 0
  var numeric = Number(value)
  if (isFinite(numeric) && numeric > 0) return numeric
  var parsed = Date.parse(String(value))
  return isFinite(parsed) ? parsed : 0
}

function sortedLibraryItems(items, mode, playedAt, pinned) {
  var source = Array.isArray(items) ? items : []
  var order = normalizedLibrarySort(mode)
  var plays = playedAt && typeof playedAt === "object" ? playedAt : {}
  var pins = Array.isArray(pinned) ? pinned : []

  var decorated = []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    if (!item) continue
    var uri = String(item.uri || "")
    decorated.push({
      item: item,
      index: i,
      uri: uri,
      pinRank: pins.indexOf(uri),
      name: String(item.name || "").toLowerCase(),
      addedAt: libraryTimestamp(item.addedAt),
      playedAt: playTimeOf(plays[uri]),
      playSource: playSourceOf(plays[uri])
    })
  }

  function rankedFirst(a, b, valueOf) {
    var av = valueOf(a)
    var bv = valueOf(b)
    var aHas = isFinite(av) && av > 0
    var bHas = isFinite(bv) && bv > 0
    if (aHas && bHas && av !== bv) return bv - av
    if (aHas !== bHas) return aHas ? -1 : 1
    return a.index - b.index
  }

  decorated.sort(function(a, b) {
    if (a.pinRank >= 0 || b.pinRank >= 0) {
      if (a.pinRank >= 0 && b.pinRank >= 0) return a.pinRank - b.pinRank
      return a.pinRank >= 0 ? -1 : 1
    }
    if (order === "alpha") {
      if (a.name !== b.name) return a.name < b.name ? -1 : 1
      return a.index - b.index
    }
    if (order === "added") return rankedFirst(a, b, function(v) { return v.addedAt })
    // Recents means last touched, the way Spotify's own list behaves: saving an
    // album counts just as much as playing something.
    if (order === "recent") return rankedFirst(a, b, function(v) {
      return Math.max(isFinite(v.playedAt) ? v.playedAt : 0,
        isFinite(v.addedAt) ? v.addedAt : 0)
    })
    return a.index - b.index
  })

  var result = []
  for (var j = 0; j < decorated.length; j++) {
    var entry = decorated[j]
    var copy = shallowCopy(entry.item)
    if (entry.pinRank >= 0) copy.pinned = true
    copy.sortIndex = entry.index
    if (order === "added") {
      copy.sortValue = entry.addedAt
      copy.sortSource = entry.addedAt > 0 ? "added" : "none"
    } else if (order === "recent") {
      copy.sortValue = Math.max(entry.playedAt, entry.addedAt)
      copy.sortSource = entry.playedAt >= entry.addedAt && entry.playedAt > 0
        ? entry.playSource : (entry.addedAt > 0 ? "added" : "none")
    } else {
      copy.sortValue = entry.index
      copy.sortSource = order
    }
    result.push(copy)
  }
  return result
}

// Spotify allows four pins; pinning a fifth drops the oldest.
function togglePinned(pinned, uri, limit) {
  var list = Array.isArray(pinned) ? pinned.slice() : []
  var value = String(uri || "")
  if (!value) return list
  var cap = Math.max(1, Math.floor(Number(limit) || 4))
  var at = list.indexOf(value)
  if (at >= 0) {
    list.splice(at, 1)
    return list
  }
  list.push(value)
  while (list.length > cap) list.shift()
  return list
}

function normalizedNormalizeVolume(value) {
  return String(value || "On") === "Off" ? "Off" : "On"
}

function normalizedVolumeLevel(value) {
  var level = String(value || "")
  return VOLUME_LEVEL_PREGAIN_DB.hasOwnProperty(level) ? level : "Normal"
}

function normalizationPregainDb(level) {
  return VOLUME_LEVEL_PREGAIN_DB[normalizedVolumeLevel(level)]
}

function normalizedShortcutHints(value) {
  return String(value || "On") === "Off" ? "Off" : "On"
}

function shortcutSequenceList(value) {
  if (value === undefined || value === null || value === "") return []
  return Array.isArray(value) ? value : [value]
}

function parseShortcutSequence(sequence) {
  var raw = String(sequence || "").replace(/^\s+|\s+$/g, "")
  var result = { ctrl: false, shift: false, alt: false, key: "" }
  if (!raw) return result
  var parts = raw.split("+")
  for (var i = 0; i < parts.length; i++) {
    var part = String(parts[i] || "").replace(/^\s+|\s+$/g, "")
    if (!part) continue
    var lower = part.toLowerCase()
    if (lower === "ctrl" || lower === "control") result.ctrl = true
    else if (lower === "shift") result.shift = true
    else if (lower === "alt") result.alt = true
    else if (lower === "meta" || lower === "super") continue
    else result.key = part
  }
  return result
}

function shortcutModifiersMatch(sequence, held) {
  var parsed = parseShortcutSequence(sequence)
  var flags = held && typeof held === "object" ? held : {}
  var ctrl = flags.ctrl === true
  var shift = flags.shift === true
  var alt = flags.alt === true
  return parsed.ctrl === ctrl && parsed.shift === shift && parsed.alt === alt
}

function shortcutModifierFlagsAfterEvent(reportedFlags, pressed, previousFlags,
    changedModifierFlag) {
  var reported = Number(reportedFlags) || 0
  var previous = Number(previousFlags) || 0
  var changed = Number(changedModifierFlag) || 0
  if (changed !== 0)
    return pressed === true ? (reported | changed) : (reported & ~changed)
  // Some Qt key-release events omit modifiers that are still physically held.
  // A non-modifier release cannot change that state, so retain the last value.
  return pressed === true ? reported : previous
}

function shortcutKeycap(sequence) {
  var key = String(parseShortcutSequence(sequence).key || "")
  var lower = key.toLowerCase()
  if (lower === "left") return "←"
  if (lower === "right") return "→"
  if (lower === "up") return "↑"
  if (lower === "down") return "↓"
  if (lower === "space") return "Space"
  if (lower === "esc" || lower === "escape") return "Esc"
  if (lower === "tab") return "Tab"
  if (lower === "menu") return "Menu"
  return key
}

function shortcutHintCaption(sequences, held, active) {
  if (active === false) return ""
  var list = shortcutSequenceList(sequences)
  var labels = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    if (!shortcutModifiersMatch(list[i], held)) continue
    var label = shortcutKeycap(list[i])
    if (!label || seen[label]) continue
    seen[label] = true
    labels.push(label)
  }
  return labels.join(" ")
}

function shortcutOverlayLabel(sequences, held, active, navHint) {
  if (active === false) return ""
  var nav = String(navHint || "")
  var chord = shortcutHintCaption(sequences, held, true)
  if (nav && chord && nav !== chord) return nav + " " + chord
  if (nav) return nav
  return chord
}

function repeatModeLabel(mode) {
  var value = String(mode || "off")
  if (value === "track") return "This song"
  if (value === "context") return "All"
  return "Off"
}

var TYPE_LABELS = {
  track: { singular: "Song", plural: "Songs" },
  artist: { singular: "Artist", plural: "Artists" },
  album: { singular: "Album", plural: "Albums" },
  playlist: { singular: "Playlist", plural: "Playlists" },
  show: { singular: "Podcast", plural: "Podcasts" },
  episode: { singular: "Episode", plural: "Episodes" },
  audiobook: { singular: "Audiobook", plural: "Books" }
}

function typeLabel(type, plural) {
  var entry = TYPE_LABELS[String(type || "")]
  if (!entry) return plural ? "results" : "Spotify item"
  return plural ? entry.plural : entry.singular
}

function searchTypeLabel(type) {
  return typeLabel(type, true)
}

function spotifyTypeLabel(type) {
  return typeLabel(type, false)
}

var MUTE_THRESHOLD = 0.001
var UNMUTE_FLOOR = 0.05
var SEARCH_DEBOUNCE_MS = 300
var SEARCH_REQUEST_TIMEOUT_MS = 8000

function normalizedSearchType(value) {
  var type = String(value || "")
  return SEARCH_TYPES.indexOf(type) >= 0 ? type : "track"
}

function searchNeedsLoad(query, activeQuery, typeLoaded) {
  var term = String(query || "").trim()
  return term !== "" && (String(activeQuery || "").trim() !== term
    || typeLoaded !== true)
}

var VOLUME_FLUSH_MS = 80
var VOLUME_FLUSH_REMOTE_MS = 250
var VOLUME_FLUSH_SONOS_MS = 120
var SLIDER_VOLUME_ACK_TOLERANCE = 0.04

function volumeFlushInterval(target) {
  var backend = String(target || "").trim().toLowerCase()
  if (backend === "remote") return VOLUME_FLUSH_REMOTE_MS
  if (backend === "sonos") return VOLUME_FLUSH_SONOS_MS
  return VOLUME_FLUSH_MS
}

function nextVolume(current, delta) {
  return clampUnit((Number(current) || 0) + (Number(delta) || 0))
}

function pendingSliderVolumeShouldHold(reportedSlider, pending, now) {
  if (!pending) return false
  if ((Number(now) || 0) >= (Number(pending.expiresAt) || 0)) return false
  var requested = Number(pending.slider)
  if (!isFinite(requested)) return false
  return Math.abs(clampUnit(reportedSlider) - clampUnit(requested))
    > SLIDER_VOLUME_ACK_TOLERANCE
}

function shouldRememberVolume(value) {
  return clampUnit(value) > MUTE_THRESHOLD
}

function unmuteVolume(previous) {
  return Math.max(UNMUTE_FLOOR, Number(previous) || 0)
}

function seekPosition(position, delta, length) {
  var next = Math.max(0, (Number(position) || 0) + (Number(delta) || 0))
  var maximum = Math.max(0, Number(length) || 0)
  return maximum > 0 ? Math.min(maximum, next) : next
}

function backendLoadFields(body) {
  var source = body || null
  if (!source || typeof source !== "object") return null
  var fields = { play: true }
  var contextUri = String(source.context_uri || "")
  if (contextUri) {
    fields.context_uri = contextUri
    var offset = source.offset || null
    if (offset && offset.uri) fields.offset_uri = String(offset.uri)
    if (offset && offset.position !== undefined && offset.position !== null) {
      var index = Math.floor(Number(offset.position))
      if (isFinite(index) && index >= 0) fields.offset_index = index
    }
  } else if (Array.isArray(source.uris) && source.uris.length) {
    var uris = []
    for (var i = 0; i < source.uris.length; i++) {
      var uri = String(source.uris[i] || "")
      if (uri) uris.push(uri)
    }
    if (!uris.length) return null
    fields.uris = uris
  } else {
    return null
  }
  var positionMs = Math.floor(Number(source.position_ms) || 0)
  if (positionMs > 0) fields.position_ms = positionMs
  return fields
}

// Popups drawn inside the panel (shortcut help, menus, pickers) sit over the
// panel's own content with no compositor blur of their own. Glass themes set
// the popup colour to a low alpha meant for separate blurred windows, which
// leaves these unreadable. Keep the hue, floor the alpha.
function opaqueSurface(color, minimumAlpha) {
  var floor = Math.max(0, Math.min(1, Number(minimumAlpha) || 0))
  if (!color || color.a === undefined) return color
  return color.a >= floor ? color : Qt.rgba(color.r, color.g, color.b, floor)
}

// Width of the bar slot for a label that measures `fitted` px. A cap trims
// long titles; a fixed slot also pads short ones so the widget, and everything
// laid out after it, keeps its place when the song changes.
function barSlotWidth(fixed, cap, fitted, minimum) {
  var capped = Number(cap) || 0
  var natural = Math.max(0, Number(fitted) || 0)
  var width = capped > 0
    ? (fixed === true ? capped : Math.min(capped, natural))
    : natural
  return Math.max(Number(minimum) || 0, width)
}

// The desktop app keeps the last play loaded in its footer, so Play always has
// somewhere to go. Spotify's play endpoint only resumes while the receiver
// still holds a context, which spotifyd loses once it idles out or restarts.
// Pick the most recent play, with the playlist or album it came from, so an
// idle receiver can continue there instead of leaving Play dead.
function resumeCandidateFromRecentlyPlayed(payload, imageWidth) {
  var source = payload || {}
  var values = Array.isArray(source.items) ? source.items : []
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || typeof entry !== "object") continue
    var item = normalizeTrack(entry, imageWidth || 192)
    if (!item || !item.uri) continue
    var context = entry.context && typeof entry.context === "object"
      ? entry.context : null
    var contextUri = context && context.uri ? String(context.uri) : ""
    return {
      item: item,
      // The play endpoint accepts album and playlist contexts. Artist and
      // collection contexts fall back to the single track.
      contextUri: /^spotify:(album|playlist):/.test(contextUri) ? contextUri : "",
      playedAt: String(entry.played_at || "")
    }
  }
  return null
}

function resumePlaybackAvailable(hasMedia, candidate) {
  return hasMedia !== true && !!candidate && !!candidate.item
    && !!candidate.item.uri
}

// Footer text while nothing is loaded: the live value, else the matching field
// of the last played item, else the idle label.
function idleMediaText(current, item, key, fallback) {
  var value = String(current || "")
  if (value) return value
  if (item && typeof item === "object" && item[key]) return String(item[key])
  return String(fallback || "")
}

// Preserve Spotify's current playback target unless the user explicitly chose
// another device in this app. The local engine player is only the fallback
// when Spotify has no active device. Keeping a restricted device here avoids
// silently moving playback locally; Spotify can report the unsupported action.
function preferredPlaybackDevice(devices, selectedId, explicitSelection, currentDevice) {
  var values = Array.isArray(devices) ? devices : []
  var key = String(selectedId || "")
  if (explicitSelection && key) {
    for (var i = 0; i < values.length; i++)
      if (String(values[i].id || "") === key && values[i].restricted !== true)
        return values[i]
  }
  var current = currentDevice || null
  if (current && current.active === true) {
    for (var j = 0; j < values.length; j++)
      if (playbackDevicesMatch(values[j], current))
        return values[j]
    return current
  }
  for (var k = 0; k < values.length; k++)
    if (values[k].active === true)
      return values[k]
  for (var l = 0; l < values.length; l++)
    if (values[l].local === true && values[l].restricted !== true && values[l].id)
      return values[l]
  return null
}

// Keep an active remote receiver untouched, but remember an active local
// receiver as the implicit selection so the UI and subsequent playback agree.
function automaticLocalPlaybackDevice(selectedId, preferredDevice, localDevice) {
  if (String(selectedId || "")) return null
  var current = preferredDevice || null
  if (current && current.active === true && current.local !== true) return null
  var candidate = current && current.local === true ? current : (localDevice || null)
  return candidate && candidate.local === true && candidate.id
      && candidate.restricted !== true ? candidate : null
}

// Freeze the chosen receiver for this playback intent. A missing ID remains
// valid for hardware players exposed only through current playback.
function playbackTargetDeviceId(device, explicitSelection) {
  var item = device || null
  if (!item) return ""
  return String(item.id || "")
}

function isLocalPlaybackDevice(device, configuredName, runtimeName, knownId) {
  var item = device || {}
  var id = String(item.id || "")
  var rememberedId = String(knownId || "")
  if (id && rememberedId && id === rememberedId) return true
  var name = String(item.sourceName || item.name || "")
  var configured = String(configuredName || "")
  var runtime = String(runtimeName || "")
  return !!name && (name === configured || (!!runtime && name === runtime))
}

// Spotify may expose an active hardware player through /me/player while
// omitting it from /me/player/devices (Sonos is a common example). Device ids
// are authoritative when both endpoints provide one; otherwise fall back to
// the user-visible name and device type.
function playbackDevicesMatch(left, right) {
  var first = left || {}
  var second = right || {}
  var firstId = String(first.id || "")
  var secondId = String(second.id || "")
  if (firstId && secondId) return firstId === secondId
  var firstName = String(first.name || first.sourceName || "").trim().toLowerCase()
  var secondName = String(second.name || second.sourceName || "").trim().toLowerCase()
  if (!firstName || firstName !== secondName) return false
  var firstType = String(first.type || "").trim().toLowerCase()
  var secondType = String(second.type || "").trim().toLowerCase()
  return !firstType || !secondType || firstType === secondType
}

function pendingRemoteDeviceMatches(pending, device, now) {
  if (!pending || !pending.device || !device) return false
  var expiresAt = Number(pending.expiresAt)
  var current = Number(now)
  if (!isFinite(expiresAt) || !isFinite(current) || current >= expiresAt)
    return false
  return playbackDevicesMatch(pending.device, device)
}

function playbackPositionAt(positionSeconds, receivedAt, playing, now) {
  var value = Math.max(0, Number(positionSeconds) || 0)
  var anchor = Number(receivedAt)
  var current = Number(now)
  if (playing === true && isFinite(anchor) && isFinite(current))
    value += Math.max(0, current - anchor) / 1000
  return value
}

// Spotify can briefly return the pre-command playback state after accepting a
// seek. Keep the requested anchor until the active device reports a position
// close enough to acknowledge it, or until the bounded grace period expires.
function pendingRemoteSeekShouldHold(playback, pending, now) {
  var state = playback || null
  if (!state || !pendingRemoteDeviceMatches(pending, state.device, now))
    return false
  var currentUri = String((state.item && state.item.uri) || "")
  var requestedUri = String(pending.uri || "")
  if (!currentUri || (requestedUri && currentUri !== requestedUri)) return false

  var reported = playbackPositionAt(state.progressSeconds, state.receivedAt,
    state.playing, now)
  var requested = playbackPositionAt(pending.positionSeconds,
    pending.requestedAt, pending.playing, now)
  return Math.abs(reported - requested) > 2
}

function displayedRemotePosition(playback, pending, now) {
  var state = playback || {}
  if (pendingRemoteSeekShouldHold(state, pending, now))
    return playbackPositionAt(pending.positionSeconds, pending.requestedAt,
      pending.playing, now)
  return playbackPositionAt(state.progressSeconds, state.receivedAt,
    state.playing, now)
}

// Volume has no timestamp in Spotify's response. An exact percentage is
// therefore the acknowledgement; null or a different value remains stale for
// the same bounded grace period.
function pendingRemoteVolumeShouldHold(device, pending, now) {
  if (!pendingRemoteDeviceMatches(pending, device, now)) return false
  var requested = normalizeVolumePercent(pending.volumePercent)
  var reported = normalizeVolumePercent((device || {}).volumePercent)
  return requested !== null
    && (reported === null || Math.abs(reported - requested) > 0.5)
}

function playbackSliderFeedbackComplete(sourceValue, pendingValue, sourcePending,
    elapsedMs, tolerance, minimumMs, timeoutMs) {
  var elapsed = Math.max(0, Number(elapsedMs) || 0)
  var timeout = Math.max(1, Number(timeoutMs) || 1)
  if (elapsed >= timeout) return true
  var minimum = Math.max(0, Number(minimumMs) || 0)
  var difference = Math.abs((Number(sourceValue) || 0)
    - (Number(pendingValue) || 0))
  return elapsed >= minimum && sourcePending !== true
    && difference <= Math.max(0, Number(tolerance) || 0)
}

function spotifyConnectTokenType(value) {
  var tokenType = String(value || "default").trim().toLowerCase()
  return ["default", "accesstoken", "authorization_code"].indexOf(tokenType) >= 0
    ? tokenType : "default"
}

function isSpotifyConnectDeviceId(value) {
  return /^[A-Za-z0-9_.:-]{8,160}$/.test(String(value || ""))
}

// Some hardware receivers expose their device id as their Web API name. Local
// ZeroConf discovery has the user-facing alias and can safely relabel the same
// receiver because playbackDevicesMatch requires equal ids when both exist.
function spotifyDeviceNameNeedsDiscovery(device) {
  var item = device || {}
  var name = String(item.name || "").trim()
  var id = String(item.id || "").trim()
  return !name || (!!id && name.toLowerCase() === id.toLowerCase())
    || /^[a-f0-9]{40}$/i.test(name)
}

function playbackDeviceDisplayName(device, discoveredDevices) {
  var item = device || {}
  var receivers = Array.isArray(discoveredDevices) ? discoveredDevices : []
  for (var i = 0; i < receivers.length; i++) {
    var receiver = receivers[i]
    if (!receiver || !playbackDevicesMatch(receiver, item)) continue
    var discoveredName = String(receiver.name || "").trim()
    if (discoveredName) return discoveredName
  }
  return String(item.name || "").trim()
}

function normalizePlaybackState(value, imageWidth) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var source = value
  var rawDevice = source.device || null
  var device = rawDevice && typeof rawDevice === "object" ? {
    id: String(rawDevice.id || ""),
    name: String(rawDevice.name || "Spotify device"),
    type: String(rawDevice.type || "unknown"),
    active: rawDevice.is_active === true,
    restricted: rawDevice.is_restricted === true,
    // Spotify explicitly permits this field to be null. Preserve that as
    // "unknown" instead of making a missing reading look like a real mute.
    volumePercent: normalizeVolumePercent(rawDevice.volume_percent),
    supportsVolume: rawDevice.supports_volume === true
  } : null
  var item = source.item && typeof source.item === "object"
    ? normalizeTrack(source.item, imageWidth || 192) : null
  if (!device && !item) return null
  return {
    device: device,
    item: item,
    playing: source.is_playing === true,
    progressSeconds: Math.max(0, Number(source.progress_ms) || 0) / 1000,
    receivedAt: Date.now(),
    repeatMode: ["off", "track", "context"].indexOf(String(source.repeat_state)) >= 0
      ? String(source.repeat_state) : "off",
    shuffle: source.shuffle_state === true,
    contextUri: source.context && source.context.uri
      ? String(source.context.uri) : "",
    contextHref: source.context && source.context.href
      ? String(source.context.href) : "",
    contextType: source.context && source.context.type
      ? String(source.context.type) : "",
    disallows: source.actions && source.actions.disallows
      && typeof source.actions.disallows === "object"
      ? source.actions.disallows : ({})
  }
}

function imageFor(images, targetWidth) {
  if (!Array.isArray(images) || images.length === 0) return ""
  var target = Math.max(1, Number(targetWidth) || 128)
  var best = null
  var bestScore = Number.MAX_VALUE
  for (var i = 0; i < images.length; i++) {
    var image = images[i]
    if (!image || !image.url) continue
    var width = Number(image.width) || target
    // Prefer the smallest image that is still large enough. Undersized images
    // get a larger penalty so artwork is not visibly upscaled.
    var score = width >= target ? width - target : (target - width) * 4
    if (score < bestScore) {
      best = image
      bestScore = score
    }
  }
  return best ? String(best.url) : ""
}

function artistNames(artists) {
  var source = arrayValues(artists)
  var names = []
  for (var i = 0; i < source.length; i++)
    if (source[i] && source[i].name) names.push(String(source[i].name))
  return names.join(", ")
}

function artistSubtitleSuffix(item) {
  var source = item || {}
  var prefix = artistNames(source.artists)
  var subtitle = String(source.subtitle || "")
  return prefix && subtitle.indexOf(prefix) === 0
    ? subtitle.substring(prefix.length) : ""
}

function artistForName(items, name) {
  var rows = arrayValues(items)
  var expected = String(name || "").trim().toLowerCase()
  var fallback = null
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    if (!item || item.type !== "artist" || !item.name) continue
    if (!fallback) fallback = item
    if (expected && String(item.name).trim().toLowerCase() === expected) return item
  }
  return fallback
}

function artistContextAvailable(mediaType, trackId, artists) {
  return String(mediaType || "") === "track"
    || String(trackId || "") !== "" || arrayValues(artists).length > 0
}

function spotifyTrackId(value) {
  var match = String(value || "").match(
    /(?:spotify:track:|spotify\/track\/|open\.spotify\.com\/track\/)([A-Za-z0-9]+)/)
  return match ? match[1] : ""
}

// Playback from another Spotify Connect device already carries a normalized
// item. Local playback may expose only MPRIS metadata, so synthesize
// the small track shape needed by library actions in that case. A matching
// episode must not be mistaken for a track when the engine's object-path
// fallback supplied its id.
function currentPlaybackTrack(trackId, remoteTrack, title, artist, album,
    coverUrl, durationSeconds, externalUrl) {
  var id = String(trackId || "").trim()
  if (!id) return null

  var remote = remoteTrack && typeof remoteTrack === "object"
    ? remoteTrack : null
  var remoteId = remote
    ? String(remote.id || spotifyTrackId(remote.uri)).trim() : ""
  if (remote && remoteId === id) {
    if (String(remote.type || "track") !== "track") return null
    if (remote.uri) return remote
  }

  return {
    kind: "item",
    type: "track",
    id: id,
    uri: "spotify:track:" + id,
    name: String(title || "Untitled"),
    subtitle: String(artist || ""),
    album: String(album || ""),
    artists: [],
    albumItem: null,
    parentContext: null,
    imageUrl: String(coverUrl || ""),
    durationMs: Math.max(0, Number(durationSeconds) || 0) * 1000,
    externalUrl: String(externalUrl || "")
  }
}

function lyricsSong(trackId, title, artist, album, duration, coverUrl,
    positionSeconds) {
  var id = String(trackId || "").trim()
  var songTitle = String(title || "").trim()
  var songArtist = String(artist || "").trim()
  if (!id || !songTitle || !songArtist) return null
  var songDuration = Math.max(0, Number(duration) || 0)
  var songPosition = Math.max(0, Number(positionSeconds) || 0)
  if (songDuration > 0) songPosition = Math.min(songPosition, songDuration)
  return {
    id: "spotify:track:" + id,
    title: songTitle,
    artist: songArtist,
    album: String(album || "").trim(),
    duration: songDuration,
    coverUrl: String(coverUrl || "").trim(),
    positionSeconds: songPosition
  }
}

function optionalPluginState(installed, enabled) {
  if (installed !== true) return "missing"
  return enabled === true ? "ready" : "disabled"
}

// Installation runs non-interactively only after the app's own confirmation
// prompt. Keep the repository and plugin id as separate argv entries so no
// user-controlled text is ever interpreted by a shell.
function optionalPluginSetupCommand(state, pluginId, repositoryUrl) {
  var availability = String(state || "")
  var id = String(pluginId || "").trim()
  var url = String(repositoryUrl || "").trim()
  // Use the absolute binary so a Quickshell Process/execDetached does not
  // depend on the shell's PATH. --yes keeps add non-interactive.
  if (availability === "missing" && url)
    return ["/usr/bin/omarchy", "plugin", "add", url, "--enable", "--yes"]
  if (availability === "disabled" && id)
    return ["/usr/bin/omarchy", "plugin", "enable", id, "--section", "center"]
  return []
}

function lyricsInstallIntent(song, surface, now) {
  if (!song || typeof song !== "object") return null
  return {
    song: song,
    surface: String(surface || ""),
    startedAt: Number(now) || Date.now()
  }
}

function lyricsInstallIntentIsFresh(intent, now, lifetimeMs) {
  if (!intent || typeof intent !== "object" || !intent.song) return false
  return timestampIsFresh(intent.startedAt, now,
    lifetimeMs === undefined ? 180000 : lifetimeMs)
}

function sessionWithoutLyricsInstall(session) {
  var next = shallowCopy(session)
  delete next.pendingLyricsInstall
  return next
}

var SESSION_STATE_LIMIT = 16000

function normalizedSessionState(value) {
  var session = value
  if (typeof session === "string") session = parseJson(session, ({}))
  if (!session || typeof session !== "object" || Array.isArray(session)) session = ({})
  return JSON.stringify(session).length <= SESSION_STATE_LIMIT ? session : ({})
}

function sessionRecord(sessionState, searchHistory) {
  return {
    sessionState: normalizedSessionState(sessionState),
    searchHistory: parseStringList(searchHistory, 12)
  }
}

function emptySessionRecord() {
  return sessionRecord(({}), [])
}

function parseSessionRecord(raw) {
  var parsed = parseJson(String(raw || ""), null)
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return emptySessionRecord()
  return sessionRecord(parsed.sessionState, parsed.searchHistory)
}

function encodeSessionRecord(sessionState, searchHistory) {
  var record = sessionRecord(sessionState, searchHistory)
  record.version = 1
  return JSON.stringify(record, null, 2) + "\n"
}

function sessionRecordIsEmpty(record) {
  var value = record && typeof record === "object" ? record : emptySessionRecord()
  var session = value.sessionState
  var history = value.searchHistory
  var hasSession = !!session && typeof session === "object" && !Array.isArray(session)
    && Object.keys(session).length > 0
  var hasHistory = Array.isArray(history) && history.length > 0
  return !hasSession && !hasHistory
}

function pluginSettingsHaveSessionKeys(source) {
  if (!source || typeof source !== "object") return false
  return source.sessionState !== undefined || source.searchHistory !== undefined
}

function sessionRecordFromPluginSettings(source) {
  var values = source && typeof source === "object" ? source : ({})
  return sessionRecord(values.sessionState, values.searchHistory)
}

function searchShortcutAction(searchFocused, scopeAvailable, searchInContext) {
  if (searchFocused === true)
    return scopeAvailable === true ? "toggle-scope" : "focus"
  if (scopeAvailable === true && searchInContext === true) return "enter-global"
  return "focus"
}

function cursorActionList(actions) {
  var list = Array.isArray(actions) ? actions : []
  var result = []
  for (var i = 0; i < list.length; i++) {
    var action = String(list[i] || "")
    if (action) result.push(action)
  }
  return result
}

function ensureCursorAction(actions, current, fallback) {
  var list = cursorActionList(actions)
  if (!list.length) return ""
  var value = String(current || "")
  if (list.indexOf(value) >= 0) return value
  var preferred = String(fallback || "")
  if (preferred && list.indexOf(preferred) >= 0) return preferred
  return list[0]
}

function moveCursorAction(actions, current, delta) {
  var list = cursorActionList(actions)
  if (!list.length) return ""
  var index = list.indexOf(String(current || ""))
  if (index < 0) index = 0
  var step = delta < 0 ? -1 : 1
  return list[(index + step + list.length) % list.length]
}

function cursorNavHint(query) {
  var spec = query && typeof query === "object" ? query : {}
  var region = String(spec.region || "")
  var action = String(spec.action || "")
  if (!region || !action) return ""
  if (region === String(spec.tabRegion || "")
      && action === String(spec.tabAction || ""))
    return "Tab"
  if (region === String(spec.backtabRegion || "")
      && action === String(spec.backtabAction || ""))
    return "⇧Tab"
  if (spec.cursorActive === false) return ""
  if (spec.modifiersHeld === true) return ""
  var currentRegion = String(spec.currentRegion || "")
  var current = String(spec.currentAction || "")
  var listAction = String(spec.listAction || "")
  var listIndex = Math.floor(Number(spec.listIndex))
  var listCount = Math.max(0, Math.floor(Number(spec.listCount) || 0))
  var atList = listAction !== "" && current === listAction
  if (region === currentRegion && action === current) {
    if (atList) return ""
    return "↵"
  }
  if (region === currentRegion) {
    var neighbors = cursorActionList(spec.regionActions)
    if (action === moveCursorAction(neighbors, current, -1)) {
      if (atList && listIndex > 0) return ""
      return "↑"
    }
    if (action === moveCursorAction(neighbors, current, 1)) {
      if (atList && listIndex >= 0 && listIndex < listCount - 1) return ""
      return "↓"
    }
  }
  return ""
}

function isCursorListAction(action) {
  var value = String(action || "")
  return value === "list" || value.indexOf("list-") === 0
}

function pageListActions(actions) {
  var list = cursorActionList(actions)
  var result = []
  for (var i = 0; i < list.length; i++) {
    if (isCursorListAction(list[i])) result.push(list[i])
  }
  return result
}

function listHintRowIndex(count, firstVisible) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  if (n <= 0) return -1
  var row = Math.floor(Number(firstVisible))
  if (row >= 0 && row < n) return row
  return 0
}

function regionTabLanding(region, actions, query) {
  var spec = query && typeof query === "object" ? query : {}
  var list = cursorActionList(actions)
  if (!list.length) return ""
  var area = String(region || "")
  if (area === "footer")
    return ensureCursorAction(list, "play", list[0])
  if (area === "header")
    return ensureCursorAction(list, "search", list[0])
  if (area === "page") {
    var preferred = String(spec.pageLanding || "")
    if (preferred && list.indexOf(preferred) >= 0) return preferred
    var lists = pageListActions(list)
    var count = Math.floor(Number(spec.listCount))
    var listEmpty = isFinite(count) && count === 0
    if (lists.length) {
      if (lists[0] !== "list" || !listEmpty) return lists[0]
    }
    var chrome = []
    for (var i = 0; i < list.length; i++) {
      if (!isCursorListAction(list[i])) chrome.push(list[i])
    }
    if (chrome.length)
      return spec.back === true ? chrome[chrome.length - 1] : chrome[0]
    return ""
  }
  if (spec.back === true) return list[list.length - 1]
  return list[0]
}

function tabCursorDestination(query) {
  var spec = query && typeof query === "object" ? query : {}
  var regions = cursorActionList(spec.regions)
  if (!regions.length) return { region: "", action: "" }
  var back = spec.back === true
  var currentRegion = String(spec.currentRegion || "")
  var currentAction = String(spec.currentAction || "")
  var byRegion = spec.actionsByRegion && typeof spec.actionsByRegion === "object"
    ? spec.actionsByRegion : {}
  var pageActions = cursorActionList(spec.pageActions || byRegion.page)
  var lists = pageListActions(pageActions)

  if (spec.cursorActive === false) {
    var footer = cursorActionList(byRegion.footer)
    var play = ensureCursorAction(footer, "play", footer[0] || "")
    if (play) return { region: "footer", action: play }
    if (regions.length) {
      var first = regions[0]
      return {
        region: first,
        action: regionTabLanding(first, cursorActionList(byRegion[first]), spec)
      }
    }
    return { region: "", action: "" }
  }

  if (regions.length === 1) {
    var only = regions[0]
    return {
      region: only,
      action: moveCursorAction(cursorActionList(byRegion[only]), currentAction,
        back ? -1 : 1)
    }
  }

  if (currentRegion === "page" && lists.length) {
    var actionIndex = pageActions.indexOf(currentAction)
    var currentList = lists.indexOf(currentAction)
    var firstListAt = pageActions.indexOf(lists[0])
    var lastListAt = pageActions.indexOf(lists[lists.length - 1])
    if (!back) {
      if (currentList >= 0 && currentList < lists.length - 1)
        return { region: "page", action: lists[currentList + 1] }
      if (currentList < 0 && (actionIndex < 0 || actionIndex < firstListAt))
        return { region: "page", action: lists[0] }
    } else if (currentList > 0) {
      return { region: "page", action: lists[currentList - 1] }
    } else if (currentList === 0) {
      if (firstListAt > 0)
        return { region: "page", action: pageActions[firstListAt - 1] }
    } else if (actionIndex > lastListAt) {
      return { region: "page", action: lists[lists.length - 1] }
    }
  }

  var nextRegion = moveCursorAction(regions, currentRegion, back ? -1 : 1)
  return {
    region: nextRegion,
    action: regionTabLanding(nextRegion, cursorActionList(byRegion[nextRegion]), {
      back: back,
      listCount: spec.listCount,
      pageLanding: spec.pageLanding
    })
  }
}

function cursorListRowHint(query) {
  var spec = query && typeof query === "object" ? query : {}
  var row = Math.floor(Number(spec.rowIndex))
  var count = Math.max(0, Math.floor(Number(spec.count) || 0))
  var current = Math.floor(Number(spec.currentIndex))
  if (count <= 0 || row < 0 || row >= count) return ""
  if (!(current >= 0 && current < count)) current = 0
  var tabRow = listHintRowIndex(count, spec.tabRowIndex)
  if (spec.atList !== true) {
    if (spec.tabIsList === true && row === tabRow) return "Tab"
    if (spec.backtabIsList === true && row === tabRow) return "⇧Tab"
  }
  if (spec.modifiersHeld === true) return ""
  if (spec.atList === true) {
    if (row === current) return "↵"
    if (row === current - 1) return "↑"
    if (row === current + 1) return "↓"
    return ""
  }
  if (spec.previousIsCurrent === true && row === 0) return "↓"
  if (spec.nextIsCurrent === true && row === count - 1) return "↑"
  return ""
}

function listIndexAfterMove(count, current, delta) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  if (n <= 0) return -1
  var index = Math.floor(Number(current))
  var step = delta < 0 ? -1 : 1
  if (!(index >= 0 && index < n)) return step < 0 ? n - 1 : 0
  var next = index + step
  if (next < 0 || next >= n) return -1
  return next
}

function searchEscapeAction(barVisible, searchFocused, queryText,
    universalOverlay) {
  if (barVisible !== true) return ""
  if (String(queryText || "").trim() !== "" || universalOverlay === true)
    return "dismiss"
  if (searchFocused === true) return "blur"
  return ""
}

function universalSearchVisible(tab, active) {
  var area = String(tab || "")
  return area === "search"
    || (active === true && area !== "login" && area !== "devices"
      && area !== "setup")
}

function isUtilityTab(tab) {
  var area = String(tab || "")
  return area === "setup" || area === "devices" || area === "login"
}

function rememberContentTab(tab) {
  var area = String(tab || "")
  return !area || isUtilityTab(area) ? "" : area
}

// Settings and Devices sit on top of the last real page. Esc returns there
// and skips any intervening Settings/Devices visit so two Esc presses cannot
// close the window from those menus.
function previousContentTab(currentTab, lastContentTab) {
  if (currentTab !== "setup" && currentTab !== "devices") return ""
  var previous = rememberContentTab(lastContentTab)
  return previous || "home"
}

function searchScope(tab, detailItem, selectedPlaylist, homeType, libraryType) {
  var area = String(tab || "")
  var item = null
  var label = ""
  var key = ""
  var mode = "filter"

  if (area === "detail" && detailItem) {
    item = detailItem
    label = String(item.name || "").trim()
    key = "detail:" + String(item.uri || item.id || "")
    mode = item.type === "artist" ? "artist" : "filter"
  } else if (area === "playlists" && selectedPlaylist) {
    item = selectedPlaylist
    label = String(item.name || "").trim()
    key = "playlist:" + String(item.uri || item.id || "")
  } else if (area === "home") {
    var homeLabels = {
      recent: "Recently played",
      tracks: "Top songs",
      artists: "Top artists"
    }
    var selectedHome = String(homeType || "recent")
    label = homeLabels[selectedHome] || "For you"
    key = "home:" + selectedHome
  } else if (area === "discover") {
    label = "Discover"
    key = "discover"
  } else if (area === "library") {
    var libraryLabels = {
      tracks: "Liked Songs",
      albums: "Saved albums",
      artists: "Followed artists",
      shows: "Saved podcasts",
      episodes: "Saved episodes",
      audiobooks: "Saved books"
    }
    var selectedLibrary = String(libraryType || "tracks")
    label = libraryLabels[selectedLibrary] || "Your Library"
    key = "library:" + selectedLibrary
  } else if (area === "queue") {
    label = "Queue"
    key = "queue"
  }

  return {
    available: label !== "" && key !== "",
    key: key,
    label: label,
    mode: mode,
    item: item
  }
}

function sanitizeSearchTerm(value) {
  return String(value || "").replace(/["\\]/g, " ").replace(/\s+/g, " ").trim()
}

function catalogSearchText(artistName, term) {
  var artist = sanitizeSearchTerm(artistName)
  var query = sanitizeSearchTerm(term)
  var filter = artist ? "artist:\"" + artist + "\"" : ""
  return query && filter ? query + " " + filter : (query || filter)
}

function artistPlaylistSearchText(artistName, term) {
  var artist = sanitizeSearchTerm(artistName)
  var query = sanitizeSearchTerm(term)
  return query && artist ? query + " " + artist : (query || artist)
}

function mediaRowShouldCompact(titleWidth, availableWidth, actionCount) {
  var title = Math.max(0, Number(titleWidth) || 0)
  var available = Math.max(0, Number(availableWidth) || 0)
  var actions = Math.max(0, Math.floor(Number(actionCount) || 0))
  return actions > 0 && title > available
}

// Artwork comes from Spotify's CDN on every launch. A stable name per URL lets
// it be kept on disk instead, which is what makes a second launch quick.
function artworkCacheName(url) {
  var text = String(url || "")
  if (!text) return ""
  var hash = 5381
  for (var i = 0; i < text.length; i++)
    hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0
  return hash.toString(36) + text.length.toString(36) + ".img"
}

// These are handed straight to curl, which reads a leading dash as an option
// and will happily fetch a scheme that is not the web. Artwork is https.
function artworkUrls(items, cached) {
  var rows = Array.isArray(items) ? items : []
  var have = cached && typeof cached === "object" ? cached : {}
  var seen = {}
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var url = rows[i] && rows[i].imageUrl ? String(rows[i].imageUrl) : ""
    if (url.indexOf("https://") !== 0) continue
    if (seen[url] || have[url]) continue
    seen[url] = true
    out.push(url)
  }
  return out
}

// Searching by artist name returns other artists' work, so results had to be
// filtered and the search re-paged until enough matched. These ask Spotify the
// question directly, in one request each.
function artistTopTracksRequest(artist) {
  if (!artist || !artist.id || artist.type !== "artist") return null
  // No market: with a signed-in account Spotify uses that account's country,
  // which is what we want and one less thing to get wrong.
  return {
    path: "/artists/" + encodeURIComponent(String(artist.id)) + "/top-tracks",
    query: null
  }
}

function artistAlbumsRequest(artist) {
  if (!artist || !artist.id || artist.type !== "artist") return null
  return {
    path: "/artists/" + encodeURIComponent(String(artist.id)) + "/albums",
    query: { include_groups: "album,single", limit: 50 }
  }
}

function normalizeArtistTopTracks(payload, imageWidth) {
  var rows = payload && Array.isArray(payload.tracks) ? payload.tracks : []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var track = normalizeTrack(rows[i], imageWidth || 96)
    if (track) out.push(track)
  }
  return out
}

// The first reply carries the total, so every remaining page can be asked for
// at once instead of one after another.
function pageOffsets(total, limit, loaded) {
  var size = Math.max(1, Number(limit) || 50)
  var have = Math.max(0, Number(loaded) || 0)
  var count = Math.max(0, Number(total) || 0)
  var out = []
  for (var at = have; at < count && out.length < 40; at += size) out.push(at)
  return out
}

function evenColumnWidth(total, spacing, count) {
  var columns = Math.max(0, Math.floor(Number(count) || 0))
  if (columns < 1) return Math.max(0, Number(total) || 0)
  var gaps = Math.max(0, Number(spacing) || 0) * (columns - 1)
  return Math.max(80, (Math.max(0, Number(total) || 0) - gaps) / columns)
}

function responsiveResultColumns(width, twoColumnWidth) {
  var available = Math.max(0, Number(width) || 0)
  var breakpoint = Math.max(1, Number(twoColumnWidth) || 1)
  return available >= breakpoint ? 2 : 1
}

// Flatten grouped search results into rows for one virtualized ListView. Each
// media row contains at most `columnCount` items, so the view creates only the
// rows around its viewport instead of every result in several nested grids.
function sectionedMediaRows(sections, columnCount) {
  var groups = Array.isArray(sections) ? sections : []
  var columns = Math.max(1, Math.min(4, Math.floor(Number(columnCount) || 1)))
  var rows = []
  for (var sectionIndex = 0; sectionIndex < groups.length; sectionIndex++) {
    var section = groups[sectionIndex] || {}
    var items = arrayValues(section.items)
    var loading = section.loading === true
    var hasMore = section.hasMore === true
    if (!items.length && !loading && !hasMore) continue

    var id = String(section.id || sectionIndex)
    rows.push({
      kind: "heading",
      sectionId: id,
      heading: String(section.heading || "RESULTS"),
      count: items.length,
      loading: loading
    })
    for (var start = 0; start < items.length; start += columns) {
      rows.push({
        kind: "items",
        sectionId: id,
        startIndex: start,
        items: items.slice(start, start + columns)
      })
    }
    if (loading || hasMore) rows.push({
      kind: "more",
      sectionId: id,
      loading: loading,
      hasMore: hasMore
    })
  }
  return rows
}

function tracksForArtist(items, artist) {
  var rows = arrayValues(items)
  var target = artist || {}
  var targetId = String(target.id || "")
  var targetName = String(target.name || "").toLowerCase()
  var result = []
  for (var i = 0; i < rows.length; i++) {
    var track = rows[i]
    if (!track || track.type !== "track") continue
    var performers = arrayValues(track.artists)
    var matched = false
    for (var a = 0; a < performers.length; a++) {
      var performer = performers[a] || {}
      if ((targetId && String(performer.id || "") === targetId)
          || (!targetId && targetName
            && String(performer.name || "").toLowerCase() === targetName)) {
        matched = true
        break
      }
    }
    if (matched) result.push(track)
  }
  return result
}

function comparablePlaylistTitle(value) {
  return String(value || "").toLowerCase()
    .replace(/[’‘`]/g, "'")
    .replace(/[-–—_:.,!?()[\]{}"'\/\\]+/g, " ")
    .replace(/\s+/g, " ").trim()
}

function findThisIsPlaylist(items, artistName) {
  var expected = comparablePlaylistTitle("This Is " + String(artistName || ""))
  if (!expected || !String(artistName || "").trim()) return null
  var rows = Array.isArray(items) ? items : []
  var best = null
  var bestScore = -1
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    if (!item || item.type !== "playlist" || !item.id
        || comparablePlaylistTitle(item.name) !== expected) continue
    var ownerId = String(item.ownerId || "").toLowerCase()
    var ownerName = String(item.ownerName || "").toLowerCase()
    var score = ownerId === "spotify" || ownerName === "spotify" ? 2 : 0
    if (item.imageUrl) score++
    if (score > bestScore) {
      best = item
      bestScore = score
    }
  }
  return best
}

function trackRadioPlaylists(items, trackName) {
  var expected = comparablePlaylistTitle(String(trackName || "") + " Radio")
  if (!expected || !String(trackName || "").trim()) return []
  var rows = Array.isArray(items) ? items : []
  var result = []
  var seen = ({})
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    if (!item || item.type !== "playlist" || !item.id || !item.uri
        || comparablePlaylistTitle(item.name) !== expected) continue
    var ownerId = String(item.ownerId || "").toLowerCase()
    var ownerName = String(item.ownerName || "").toLowerCase()
    var key = String(item.uri || item.id)
    if ((ownerId !== "spotify" && ownerName !== "spotify") || seen[key]) continue
    seen[key] = true
    result.push(item)
  }
  return result
}

function radioSeedMatches(candidate, seed) {
  var item = candidate || {}
  var target = seed || {}
  var itemId = String(item.id || "")
  var targetId = String(target.id || "")
  var itemUri = String(item.uri || "")
  var targetUri = String(target.uri || "")
  if ((itemId && targetId && itemId === targetId)
      || (itemUri && targetUri && itemUri === targetUri)) return true
  if (comparablePlaylistTitle(item.name) !== comparablePlaylistTitle(target.name))
    return false

  var itemArtists = arrayValues(item.artists)
  var targetArtists = arrayValues(target.artists)
  for (var i = 0; i < itemArtists.length; i++) {
    var itemArtist = itemArtists[i] || {}
    var itemArtistId = String(itemArtist.id || "")
    var itemArtistName = comparablePlaylistTitle(itemArtist.name)
    for (var j = 0; j < targetArtists.length; j++) {
      var targetArtist = targetArtists[j] || {}
      var targetArtistId = String(targetArtist.id || "")
      var targetArtistName = comparablePlaylistTitle(targetArtist.name)
      if ((itemArtistId && targetArtistId && itemArtistId === targetArtistId)
          || (itemArtistName && targetArtistName && itemArtistName === targetArtistName))
        return true
    }
  }
  return false
}

function discoveryPlaylistRank(item) {
  if (!item || item.type !== "playlist" || !item.id) return -1
  var ownerId = String(item.ownerId || "").toLowerCase()
  var ownerName = String(item.ownerName || "").toLowerCase()
  if (ownerId !== "spotify" && ownerName !== "spotify") return -1
  var title = comparablePlaylistTitle(item.name)
  if (title === "discover weekly") return 0
  if (title === "release radar") return 1
  if (title === "daylist") return 2
  if (title === "daily mix") return 9
  var daily = title.match(/^daily mix ([0-9]+)$/)
  if (daily) return 10 + Math.max(0, Number(daily[1]) || 0)
  if (title === "new music friday") return 30
  if (title.indexOf("new music friday ") === 0) return 31
  if (title === "fresh finds") return 40
  if (title.indexOf("fresh finds ") === 0) return 41
  return -1
}

function discoveryPlaylists(items, maximum) {
  var rows = Array.isArray(items) ? items : []
  var ranked = []
  var seen = ({})
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    var rank = discoveryPlaylistRank(item)
    var key = String((item && (item.uri || item.id)) || "")
    if (rank < 0 || !key || seen[key]) continue
    seen[key] = true
    ranked.push({ item: item, rank: rank, index: i })
  }
  ranked.sort(function(left, right) {
    if (left.rank !== right.rank) return left.rank - right.rank
    var leftName = String(left.item.name || "").toLowerCase()
    var rightName = String(right.item.name || "").toLowerCase()
    if (leftName < rightName) return -1
    if (leftName > rightName) return 1
    return left.index - right.index
  })
  var limit = Math.max(1, Number(maximum) || 24)
  var result = []
  for (var j = 0; j < ranked.length && result.length < limit; j++)
    result.push(ranked[j].item)
  return result
}

function albumKind(item) {
  var source = item || {}
  var type = String(source.album_type || source.album_group || "").toLowerCase()
  if (type === "single") return Number(source.total_tracks) > 1 ? "EP / Single" : "Single"
  if (type === "compilation") return "Compilation"
  return type === "album" ? "Album" : "Release"
}

function playlistItemUris(items) {
  var rows = Array.isArray(items) ? items : []
  var uris = []
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i] || {}
    if (item.uri && ["track", "episode"].indexOf(String(item.type || "")) >= 0)
      uris.push(String(item.uri))
  }
  return uris
}

// Playlist objects are replaced when their snapshots refresh. Resolve the
// backing collection by stable ID and never fall through to an unrelated
// detail page.
function playlistBackingItems(contextPlaylist, selectedPlaylist, selectedItems,
    detailPlaylist, detailItems) {
  var contextId = contextPlaylist
    ? String(contextPlaylist.id || "") : ""
  if (!contextId) return []
  if (selectedPlaylist
      && String(selectedPlaylist.id || "") === contextId)
    return arrayValues(selectedItems)
  if (detailPlaylist && String(detailPlaylist.type || "") === "playlist"
      && String(detailPlaylist.id || "") === contextId)
    return arrayValues(detailItems)
  return []
}

// Spotify's insert_before index is measured against the playlist before the
// selected range is removed. The UI works with the item's final index, so a
// downward move needs to step over the source item once.
function playlistReorderBody(sourceIndex, destinationIndex, itemCount, snapshotId) {
  var sourceNumber = Number(sourceIndex)
  var destinationNumber = Number(destinationIndex)
  var countNumber = Number(itemCount)
  if (!isFinite(sourceNumber) || !isFinite(destinationNumber) || !isFinite(countNumber))
    return null
  var source = Math.floor(sourceNumber)
  var destination = Math.floor(destinationNumber)
  var count = Math.floor(countNumber)
  if (count < 2 || source < 0 || source >= count || destination < 0
      || destination >= count || source === destination) return null
  var body = {
    range_start: source,
    insert_before: source < destination ? destination + 1 : destination,
    range_length: 1
  }
  var snapshot = String(snapshotId || "")
  if (snapshot) body.snapshot_id = snapshot
  return body
}

// Playlist payloads can contain unavailable entries that normalize out of the
// visible list. Prefer the raw API position retained by Service in that case.
function playlistPositionAt(items, index) {
  var rows = Array.isArray(items) ? items : []
  var visibleIndex = Math.floor(Number(index))
  if (!isFinite(visibleIndex) || visibleIndex < 0 || visibleIndex >= rows.length)
    return -1
  var explicitValue = rows[visibleIndex]
    ? rows[visibleIndex].playlistPosition : undefined
  var explicitPosition = Number(explicitValue)
  return explicitValue !== null && explicitValue !== undefined
    && isFinite(explicitPosition) && explicitPosition >= 0
    ? Math.floor(explicitPosition) : visibleIndex
}

function playlistReorderBodyForItems(items, sourceIndex, destinationIndex,
    itemCount, snapshotId) {
  var rows = Array.isArray(items) ? items : []
  var sourcePosition = playlistPositionAt(rows, sourceIndex)
  var destinationPosition = playlistPositionAt(rows, destinationIndex)
  if (sourcePosition < 0 || destinationPosition < 0) return null
  var requestedCount = Number(itemCount)
  var count = isFinite(requestedCount) ? Math.floor(requestedCount) : rows.length
  count = Math.max(count, rows.length, sourcePosition + 1, destinationPosition + 1)
  return playlistReorderBody(sourcePosition, destinationPosition, count, snapshotId)
}

function reorderedPlaylistItemsAtPositions(items, sourcePosition,
    destinationPosition) {
  var rows = Array.isArray(items) ? items.slice() : []
  var source = Math.floor(Number(sourcePosition))
  var destination = Math.floor(Number(destinationPosition))
  if (!isFinite(source) || !isFinite(destination) || source < 0
      || destination < 0 || source === destination) return rows
  var sourceIndex = -1
  var destinationIndex = -1
  for (var i = 0; i < rows.length; i++) {
    var position = playlistPositionAt(rows, i)
    if (position === source) sourceIndex = i
    if (position === destination) destinationIndex = i
  }
  if (sourceIndex < 0 || destinationIndex < 0) return rows

  var positioned = []
  for (var r = 0; r < rows.length; r++) {
    var item = rows[r]
    var oldPosition = playlistPositionAt(rows, r)
    var newPosition = oldPosition
    if (oldPosition === source) newPosition = destination
    else if (source < destination && oldPosition > source
        && oldPosition <= destination) newPosition = oldPosition - 1
    else if (source > destination && oldPosition >= destination
        && oldPosition < source) newPosition = oldPosition + 1
    if (item && typeof item === "object" && newPosition !== oldPosition) {
      var copy = ({})
      for (var propertyName in item) copy[propertyName] = item[propertyName]
      copy.playlistPosition = newPosition
      positioned.push(copy)
    } else {
      positioned.push(item)
    }
  }
  var moved = positioned.splice(sourceIndex, 1)
  positioned.splice(destinationIndex, 0, moved[0])
  return positioned
}

function normalizedArtists(artists, imageWidth) {
  var sourceArtists = arrayValues(artists)
  var rows = []
  for (var i = 0; i < sourceArtists.length; i++) {
    var source = sourceArtists[i] || {}
    // Spotify's simplified artist object normally carries `type`, but some
    // playlist and cached payloads omit it. Artist links should still work.
    var artist = normalizeContext({
      id: source.id,
      uri: source.uri,
      type: source.type || "artist",
      name: source.name,
      images: source.images,
      external_urls: source.external_urls
    }, imageWidth)
    if (artist && artist.type === "artist") rows.push(artist)
  }
  return rows
}

function normalizeTrack(value, imageWidth, parentContext) {
  var source = value || {}
  var item = source.item || source.track || source.episode || source.chapter || source
  if (!item || typeof item !== "object") return null
  var album = item.album || {}
  var type = String(item.type || "track")
  if (["track", "episode", "chapter"].indexOf(type) === -1) return null
  var subtitle = type === "episode"
    ? String((item.show && item.show.name) || item.description || "Podcast")
    : (type === "chapter"
      ? String((item.audiobook && item.audiobook.name) || item.description || "Audiobook")
      : artistNames(item.artists))
  var images = type === "track" ? album.images : item.images
  var albumItem = type === "track" && album && album.name
    ? normalizeContext({
      id: album.id,
      uri: album.uri,
      type: album.type || "album",
      name: album.name,
      artists: album.artists,
      images: album.images,
      release_date: album.release_date,
      total_tracks: album.total_tracks,
      external_urls: album.external_urls
    }, imageWidth || 96) : null
  if (!albumItem && type === "track" && parentContext && parentContext.type === "album")
    albumItem = parentContext
  var parentItem = type === "episode" && item.show
    ? normalizeContext(item.show, imageWidth || 96)
    : (type === "chapter" && item.audiobook
      ? normalizeContext(item.audiobook, imageWidth || 96) : null)
  if (!parentItem && parentContext
      && ((type === "episode" && parentContext.type === "show")
        || (type === "chapter" && parentContext.type === "audiobook")))
    parentItem = parentContext
  if ((type === "episode" || type === "chapter") && parentItem)
    subtitle = String(parentItem.name || subtitle)
  var resume = item.resume_point || {}
  return {
    kind: "item",
    type: type,
    id: String(item.id || ""),
    uri: String(item.uri || ""),
    name: String(item.name || "Untitled"),
    subtitle: subtitle,
    album: String(album.name || (albumItem && albumItem.name) || ""),
    artists: normalizedArtists(item.artists, imageWidth || 96),
    albumItem: albumItem,
    parentContext: parentItem,
    imageUrl: imageFor(images, imageWidth || 96)
      || String((parentContext && parentContext.imageUrl) || ""),
    durationMs: Number(item.duration_ms) || 0,
    trackNumber: Number(item.track_number || item.chapter_number) || 0,
    discNumber: Number(item.disc_number) || 0,
    releaseDate: String(item.release_date || album.release_date || ""),
    addedAt: String(source.added_at || ""),
    playedAt: String(source.played_at || ""),
    resumeMs: Math.max(0, Number(resume.resume_position_ms) || 0),
    fullyPlayed: resume.fully_played === true,
    explicit: item.explicit === true,
    externalUrl: item.external_urls && item.external_urls.spotify
      ? String(item.external_urls.spotify) : ""
  }
}

function normalizeContext(value, imageWidth) {
  var source = value || {}
  var item = source.album || source.artist || source.playlist || source.show
    || source.audiobook || source
  var type = String(item.type || "")
  if (["album", "artist", "playlist", "show", "audiobook"].indexOf(type) === -1) return null
  var subtitle = ""
  if (type === "album") {
    var albumDetails = []
    var albumArtists = artistNames(item.artists)
    if (albumArtists) albumDetails.push(albumArtists)
    albumDetails.push(albumKind(item))
    if (item.release_date) albumDetails.push(String(item.release_date).slice(0, 4))
    subtitle = albumDetails.join(" · ")
  }
  else if (type === "playlist") subtitle = String((item.owner && item.owner.display_name) || "Playlist")
  else if (type === "artist") subtitle = "Artist"
  else if (type === "show") subtitle = String(item.publisher || "Podcast")
  else {
    var authors = []
    var sourceAuthors = Array.isArray(item.authors) ? item.authors : []
    for (var a = 0; a < sourceAuthors.length; a++)
      if (sourceAuthors[a] && sourceAuthors[a].name) authors.push(String(sourceAuthors[a].name))
    subtitle = authors.length ? authors.join(", ") : String(item.publisher || "Audiobook")
  }
  var total = Number(item.total_tracks || item.total_episodes || item.total_chapters) || 0
  if (type === "playlist") total = Number((item.items && item.items.total)
    || (item.tracks && item.tracks.total)) || 0
  return {
    kind: "context",
    type: type,
    id: String(item.id || ""),
    uri: String(item.uri || ""),
    name: String(item.name || "Untitled"),
    subtitle: subtitle,
    description: String(item.description || ""),
    artists: normalizedArtists(item.artists, imageWidth || 128),
    imageUrl: imageFor(item.images, imageWidth || 128),
    total: total,
    releaseType: type === "album" ? String(item.album_type || item.album_group || "") : "",
    releaseDate: String(item.release_date || ""),
    ownerId: String((item.owner && (item.owner.account_id || item.owner.id)) || ""),
    ownerName: String((item.owner && item.owner.display_name) || ""),
    followers: Number(item.followers && item.followers.total) || 0,
    genres: Array.isArray(item.genres) ? item.genres.slice(0, 6) : [],
    popularity: Number(item.popularity) || 0,
    collaborative: item.collaborative === true,
    public: item.public === true,
    snapshotId: String(item.snapshot_id || ""),
    addedAt: String(source.added_at || ""),
    externalUrl: item.external_urls && item.external_urls.spotify
      ? String(item.external_urls.spotify) : ""
  }
}

function normalizePlaylist(value, imageWidth) {
  var normalized = normalizeContext(value, imageWidth)
  if (!normalized || normalized.type !== "playlist") return null
  return normalized
}

function normalizePage(page, mapper) {
  var source = page || {}
  var values = Array.isArray(source.items) ? source.items : []
  var items = []
  for (var i = 0; i < values.length; i++) {
    var mapped = mapper(values[i])
    if (mapped) items.push(mapped)
  }
  return {
    items: items,
    next: safeApiUrl(source.next),
    previous: safeApiUrl(source.previous),
    total: Number(source.total) || items.length
  }
}

// Playlist rows are loaded explicitly a page at a time. Keep every requested
// page, including duplicate tracks, and let Spotify's continuation URL decide
// when the collection is complete instead of applying the shared UI cache cap.
function playlistPageState(existing, incoming, append, next) {
  var current = arrayValues(existing)
  var page = arrayValues(incoming)
  return {
    items: append === true ? current.concat(page) : page,
    next: safeApiUrl(next)
  }
}

var PLAYLIST_RESTORE_ITEM_LIMIT = 10000

function normalizedPlaylistRestoreCount(value) {
  var count = Math.floor(Number(value) || 0)
  return Math.max(0, Math.min(PLAYLIST_RESTORE_ITEM_LIMIT, count))
}

function playlistRestorePending(itemCount, targetCount, loading, next) {
  var loaded = Math.max(0, Math.floor(Number(itemCount) || 0))
  var target = normalizedPlaylistRestoreCount(targetCount)
  if (target <= loaded) return false
  return loading === true || safeApiUrl(next) !== ""
}

function playlistRestoreShouldContinue(itemCount, targetCount, next) {
  return playlistRestorePending(itemCount, targetCount, false, next)
}

function searchTypeKey(type) {
  var value = String(type || "track")
  if (value === "artist") return "artists"
  if (value === "album") return "albums"
  if (value === "playlist") return "playlists"
  if (value === "show") return "shows"
  if (value === "episode") return "episodes"
  if (value === "audiobook") return "audiobooks"
  return "tracks"
}

function normalizeSearchPage(payload, type, imageWidth) {
  var key = searchTypeKey(type)
  var page = payload && payload[key] ? payload[key] : {}
  return normalizePage(page, function(value) {
    return type === "track" || type === "episode"
      ? normalizeTrack(value, imageWidth || 128)
      : normalizeContext(value, imageWidth || 128)
  })
}

function searchGroups(payload, imageWidth) {
  var result = ({})
  for (var i = 0; i < SEARCH_TYPES.length; i++) {
    var type = SEARCH_TYPES[i]
    result[type] = normalizeSearchPage(payload, type, imageWidth || 128)
  }
  return result
}

function mergeSearchGroups(existing, incoming) {
  var result = ({})
  var oldGroups = existing || {}
  var newGroups = incoming || {}
  for (var i = 0; i < SEARCH_TYPES.length; i++) {
    var type = SEARCH_TYPES[i]
    var oldPage = oldGroups[type] || { items: [], next: "", total: 0 }
    if (!newGroups[type]) {
      result[type] = oldPage
      continue
    }
    var nextPage = newGroups[type]
    result[type] = {
      items: mergeUnique(oldPage.items, nextPage.items),
      next: nextPage.next,
      previous: nextPage.previous,
      total: Math.max(Number(oldPage.total) || 0, Number(nextPage.total) || 0)
    }
  }
  return result
}

function normalizeCursorPage(container, mapper) {
  var page = container || {}
  var values = Array.isArray(page.items) ? page.items : []
  var items = []
  for (var i = 0; i < values.length; i++) {
    var mapped = mapper(values[i])
    if (mapped) items.push(mapped)
  }
  return {
    items: items,
    next: safeApiUrl(page.next),
    total: Number(page.total) || items.length,
    after: String((page.cursors && page.cursors.after) || "")
  }
}

function filteredSorted(items, filterText, sortKey, descending) {
  var source = Array.isArray(items) ? items : []
  var term = String(filterText || "").trim().toLowerCase()
  var key = String(sortKey || "default")
  if (!term && key === "default") {
    var complete = true
    for (var candidate = 0; candidate < source.length; candidate++) {
      if (!source[candidate]) {
        complete = false
        break
      }
    }
    if (complete) return source
  }

  var rows = []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    if (!item) continue
    if (term) {
      var haystack = [item.name, item.subtitle, item.album, item.description,
        item.releaseDate, item.addedAt].join(" ").toLowerCase()
      if (haystack.indexOf(term) < 0) continue
    }
    rows.push({ item: item, index: i })
  }
  if (key !== "default") {
    // Dates read newest first by default; every other column reads A to Z.
    var dateKey = key === "date" || key === "date-asc"
    var flip = descending === true
    if (key === "date-asc") flip = !flip
    var direction = dateKey ? (flip ? 1 : -1) : (flip ? -1 : 1)
    rows.sort(function(a, b) {
      var left
      var right
      if (key === "duration") {
        left = Number(a.item.durationMs) || 0
        right = Number(b.item.durationMs) || 0
      } else if (dateKey) {
        left = String(a.item.addedAt || a.item.playedAt || a.item.releaseDate || "")
        right = String(b.item.addedAt || b.item.playedAt || b.item.releaseDate || "")
        // Unknown dates stay at the end whichever way the column reads.
        if (!left && right) return 1
        if (left && !right) return -1
      } else {
        left = String(key === "artist" ? a.item.subtitle
          : (key === "album" ? a.item.album : a.item.name) || "").toLowerCase()
        right = String(key === "artist" ? b.item.subtitle
          : (key === "album" ? b.item.album : b.item.name) || "").toLowerCase()
      }
      if (left < right) return -direction
      if (left > right) return direction
      return a.index - b.index
    })
  }
  var result = []
  for (var r = 0; r < rows.length; r++) result.push(rows[r].item)
  return result
}

function parseStringList(value, maximum) {
  var source = value
  if (typeof source === "string") source = parseJson(source, [])
  if (!Array.isArray(source)) return []
  var limit = Math.max(1, Number(maximum) || 50)
  var result = []
  var seen = ({})
  for (var i = 0; i < source.length && result.length < limit; i++) {
    var entry = String(source[i] || "").trim()
    if (!entry || seen[entry]) continue
    seen[entry] = true
    result.push(entry)
  }
  return result
}

function touchHistory(values, term, maximum) {
  var normalized = String(term || "").trim()
  var source = parseStringList(values, maximum || 12)
  if (!normalized) return source
  var result = [normalized]
  for (var i = 0; i < source.length && result.length < (maximum || 12); i++)
    if (source[i].toLowerCase() !== normalized.toLowerCase()) result.push(source[i])
  return result
}

var PLAYBACK_URI_LIMIT = 100

function playbackUsesVisibleOrder(contextUri, filterText, sortKey) {
  var context = String(contextUri || "")
  if (!/^spotify:(album|playlist):/.test(context)) return false
  return String(filterText || "").trim() !== ""
    || String(sortKey || "default") !== "default"
}

function playbackContextForView(contextUri, filterText, sortKey) {
  return playbackUsesVisibleOrder(contextUri, filterText, sortKey)
    ? "" : String(contextUri || "")
}

function visibleOrderPlaybackMessage(itemCount) {
  var count = Math.max(0, Math.floor(Number(itemCount) || 0))
  return count > PLAYBACK_URI_LIMIT
    ? "Playing the displayed order for 100 items; Spotify limits custom playback to 100"
    : "Playing the displayed order"
}

function playbackContextOffsetPosition(item, sourceItems, contextUri) {
  var context = String(contextUri || "")
  var values = Array.isArray(sourceItems) ? sourceItems : []
  var itemUri = String((item && item.uri) || "")
  var visibleIndex = -1
  for (var i = 0; i < values.length; i++) {
    if (values[i] && String(values[i].uri || "") === itemUri) {
      visibleIndex = i
      break
    }
  }

  if (/^spotify:playlist:/.test(context)) {
    var rawPosition = item ? item.playlistPosition : undefined
    var playlistPosition = Number(rawPosition)
    if (rawPosition !== null && rawPosition !== undefined
        && isFinite(playlistPosition) && playlistPosition >= 0)
      return Math.floor(playlistPosition)
    return visibleIndex
  }

  if (!/^spotify:album:/.test(context)) return -1
  var trackNumber = Math.floor(Number((item && item.trackNumber) || 0))
  var discNumber = Math.max(1,
    Math.floor(Number((item && item.discNumber) || 1)))
  if (trackNumber <= 0) return visibleIndex
  if (discNumber === 1) return trackNumber - 1

  // Album track numbers restart on each disc. Derive the absolute context
  // offset from the greatest track number seen on every preceding disc.
  var tracksPerDisc = ({})
  for (var row = 0; row < values.length; row++) {
    var candidate = values[row] || {}
    var candidateDisc = Math.max(1,
      Math.floor(Number(candidate.discNumber) || 1))
    var candidateTrack = Math.floor(Number(candidate.trackNumber) || 0)
    if (candidateTrack > 0)
      tracksPerDisc[candidateDisc] = Math.max(
        Number(tracksPerDisc[candidateDisc]) || 0, candidateTrack)
  }
  var position = trackNumber - 1
  for (var disc = 1; disc < discNumber; disc++) {
    if (!tracksPerDisc[disc]) return -1
    position += tracksPerDisc[disc]
  }
  return position
}

// One line per slow request, split so it can be blamed on the queue, the token
// refresh, or the network.
function requestTimingLine(method, path, timings, context) {
  var t = timings || ({})
  var c = context || ({})
  var queued = Math.max(0, Number(t.queuedMs) || 0)
  var auth = Math.max(0, Number(t.authMs) || 0)
  var wire = Math.max(0, Number(t.wireMs) || 0)
  return String(method || "GET") + " " + redact(String(path || ""))
    + " " + (queued + auth + wire) + " ms"
    + " (queue " + queued + ", auth " + auth + ", wire " + wire + ")"
    + " in-flight " + (Number(c.inFlight) || 0)
    + " bg " + (Number(c.background) || 0)
    + " queued " + (Number(c.queued) || 0)
    + " " + (String(c.priority || "") || "normal")
}

var LIBRARY_FILTER_MODES = ["all", "playlist", "artist", "album", "show"]

function libraryFilterModes() {
  return LIBRARY_FILTER_MODES.slice()
}

function normalizedLibraryFilter(value) {
  var text = String(value || "all")
  return LIBRARY_FILTER_MODES.indexOf(text) >= 0 ? text : "all"
}

// The sidebar mixes playlists, artists, albums and podcasts.
function filterLibraryType(items, filter) {
  var rows = Array.isArray(items) ? items : []
  var want = normalizedLibraryFilter(filter)
  if (want === "all") return rows
  var out = []
  for (var i = 0; i < rows.length; i++)
    if (rows[i] && String(rows[i].type || "") === want) out.push(rows[i])
  return out
}

// Big numbers read better shortened; small ones read better in full.
function compactCount(value) {
  var n = Math.max(0, Math.floor(Number(value) || 0))
  if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
  if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
  if (n >= 10000) return (n / 1000).toFixed(1) + "K"
  return groupedDigits(String(n))
}

// Turning a number into text is the engine's business, and some builds have
// already grouped it for the locale by the time we see it. So take the digits
// and nothing else, then group those.
function groupedDigits(text) {
  var digits = String(text || "").replace(/[^0-9]/g, "")
  if (!digits) return "0"
  var out = ""
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ","
    out += digits.charAt(i)
  }
  return out
}

// Spotify has no artist bio. Followers and genres are what it does tell us.
function artistDetailLine(artist) {
  if (!artist) return ""
  var parts = []
  var followers = Number(artist.followers) || 0
  if (followers > 0) parts.push(compactCount(followers) + " followers")
  var genres = Array.isArray(artist.genres) ? artist.genres.slice(0, 3) : []
  if (genres.length) parts.push(genres.join(", "))
  return parts.join(" · ")
}

// The play record keeps only the newest time per thing, so days are tallied
// separately as plays arrive. The watermark stops the same play being counted
// again on the next fetch.
function playDayKey(ms) {
  var d = new Date(Number(ms) || 0)
  return d.getFullYear() + "-" + twoDigits(d.getMonth() + 1) + "-"
    + twoDigits(d.getDate())
}

function countedPlayDays(payload, watermark) {
  var rows = payload && Array.isArray(payload.items) ? payload.items : []
  var mark = Number(watermark) || 0
  var days = {}
  var newest = mark
  for (var i = 0; i < rows.length; i++) {
    var at = Date.parse(String(rows[i] && rows[i].played_at || ""))
    if (!isFinite(at) || at <= mark) continue
    var key = playDayKey(at)
    days[key] = (days[key] || 0) + 1
    if (at > newest) newest = at
  }
  return { days: days, newest: newest }
}

function mergeDayCounts(stored, fresh) {
  var out = {}
  function take(source) {
    if (!source || typeof source !== "object") return
    for (var k in source) {
      if (!source.hasOwnProperty(k)) continue
      var n = Number(source[k]) || 0
      if (n > 0) out[k] = (out[k] || 0) + n
    }
  }
  take(stored)
  take(fresh)
  return out
}

// Five shades, the way a contribution grid reads at a glance.
function heatmapLevel(count) {
  var n = Number(count) || 0
  if (n <= 0) return 0
  if (n <= 2) return 1
  if (n <= 5) return 2
  if (n <= 12) return 3
  return 4
}

// Whole weeks, oldest first, ending with the week the given day falls in.
function heatmapWeeks(days, endMs, weeks) {
  var counts = days && typeof days === "object" ? days : {}
  var span = Math.max(1, Math.floor(Number(weeks) || 26))
  var end = new Date(Number(endMs) || 0)
  end.setHours(12, 0, 0, 0)
  // Walk back to the Sunday that starts the final week.
  var lastWeekStart = new Date(end.getTime())
  lastWeekStart.setDate(lastWeekStart.getDate() - lastWeekStart.getDay())
  var grid = []
  for (var w = span - 1; w >= 0; w--) {
    var column = []
    for (var d = 0; d < 7; d++) {
      var cell = new Date(lastWeekStart.getTime())
      cell.setDate(cell.getDate() - w * 7 + d)
      var key = playDayKey(cell.getTime())
      var count = Number(counts[key]) || 0
      column.push({
        key: key,
        count: count,
        level: heatmapLevel(count),
        future: cell.getTime() > end.getTime()
      })
    }
    grid.push(column)
  }
  return grid
}

// A finished episode starts again from the beginning, not from its end.
function podcastResumeMs(item) {
  if (!item || item.fullyPlayed === true) return 0
  var at = Math.floor(Number(item.resumeMs) || 0)
  return at > 0 ? at : 0
}

function skipToSeconds(fromSeconds, bySeconds, lengthSeconds) {
  var at = (Number(fromSeconds) || 0) + (Number(bySeconds) || 0)
  var length = Number(lengthSeconds) || 0
  if (at < 0) return 0
  return length > 0 ? Math.min(at, length) : at
}

function playbackBody(item, sourceItems, contextUri) {
  if (!item || !item.uri) return null
  // Spotify's playback endpoint accepts only album, artist, and playlist
  // contexts. Podcast episodes and audiobook chapters are sent as items.
  if (["album", "artist", "playlist"].indexOf(item.type) >= 0)
    return { context_uri: String(item.uri) }
  if (item.kind === "context") return null

  var itemUri = String(item.uri)
  var sourceContext = String(contextUri || "")
  if (/^spotify:(album|playlist):/.test(sourceContext)) {
    // Some librespot-based receivers accept the context but ignore a URI
    // offset and restart its first track. Prefer Spotify's numeric offset.
    var contextPosition = playbackContextOffsetPosition(item, sourceItems,
      sourceContext)
    return contextPosition >= 0
      ? { context_uri: sourceContext, offset: { position: contextPosition } }
      : { context_uri: sourceContext, offset: { uri: itemUri } }
  }

  // A lone URI creates a one-track Spotify playback context. That makes Next
  // reach the end immediately, so carry the visible list into playback. Start
  // at the clicked row and wrap once; Spotify accepts at most 100 URIs.
  var values = Array.isArray(sourceItems) ? sourceItems : []
  var start = -1
  // Prefer the exact row object so a playlist containing the same track more
  // than once starts from the occurrence the user actually selected.
  for (var i = 0; i < values.length; i++) {
    if (values[i] === item) {
      start = i
      break
    }
  }
  if (start < 0 && item.playlistPosition !== undefined) {
    var wantedPosition = Number(item.playlistPosition)
    for (var positionIndex = 0; positionIndex < values.length; positionIndex++) {
      var positioned = values[positionIndex]
      if (positioned && Number(positioned.playlistPosition) === wantedPosition
          && String(positioned.uri || "") === itemUri) {
        start = positionIndex
        break
      }
    }
  }
  if (start < 0) {
    for (var uriIndex = 0; uriIndex < values.length; uriIndex++) {
      if (values[uriIndex] && String(values[uriIndex].uri || "") === itemUri) {
        start = uriIndex
        break
      }
    }
  }
  if (start < 0) {
    var single = { uris: [itemUri] }
    var singleResume = podcastResumeMs(item)
    if (singleResume > 0) single.position_ms = singleResume
    return single
  }

  var uris = []
  for (var step = 0; step < values.length
      && uris.length < PLAYBACK_URI_LIMIT; step++) {
    var candidate = values[(start + step) % values.length]
    if (!candidate || candidate.kind !== "item") continue
    var uri = String(candidate.uri || "")
    if (!uri) continue
    uris.push(uri)
  }
  var body = { uris: uris.length ? uris : [itemUri] }
  var resumeAt = podcastResumeMs(item)
  if (resumeAt > 0) body.position_ms = resumeAt
  return body
}

function millisecondsToClock(milliseconds) {
  var seconds = Math.max(0, Math.floor((Number(milliseconds) || 0) / 1000))
  var minutes = Math.floor(seconds / 60)
  var remainder = seconds % 60
  return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
}

function uniqueRadioTracks(seed, extras) {
  var item = seed || null
  if (!item) return []
  var radio = [item]
  var seen = ({})
  seen[String(item.uri || "")] = true
  var values = Array.isArray(extras) ? extras : []
  for (var i = 0; i < values.length; i++) {
    var track = values[i]
    var uri = String((track && track.uri) || "")
    if (!uri || seen[uri]) continue
    seen[uri] = true
    radio.push(track)
  }
  return radio
}

function mergeUnique(existing, incoming) {
  var result = Array.isArray(existing) ? existing.slice() : []
  var seen = {}
  var i
  for (i = 0; i < result.length; i++) {
    var oldKey = String((result[i] && (result[i].uri || result[i].id)) || "")
    if (oldKey) seen[oldKey] = true
  }
  var values = Array.isArray(incoming) ? incoming : []
  for (i = 0; i < values.length; i++) {
    var key = String((values[i] && (values[i].uri || values[i].id)) || "")
    if (key && seen[key]) continue
    if (key) seen[key] = true
    result.push(values[i])
  }
  return result
}
