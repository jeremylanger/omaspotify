# Technical notes

This document keeps implementation, development, and deep troubleshooting
details out of the user-facing README.

## Architecture

OmaSpotify runs as a plugin inside Omarchy's existing `omarchy-shell`
Quickshell process. It provides a shared service, a bar widget, and a lazy-loaded
panel. There is no embedded website, browser engine, second shell process, or
resident helper process.

Local playback state and ordinary controls use MPRIS. Starting playback on this
computer uses the backend's private Unix socket (`load`, `add_to_queue`) when
that process is running. Active playback on another Spotify Connect device
comes from the Spotify Web API, refreshed while a UI is visible and at a slower
rate while that device is playing. Fast `/me/player` polling is reserved for
remote or unknown targets. Spotify data and other user actions also use the
Web API.

Local audio runs in the plugin-owned `omaspotify-backend` Rust process,
supervised by a static systemd user unit that is never enabled at login. The
backend embeds a commit-pinned librespot revision rather than duplicating its
private-protocol implementation. It owns configuration, cache/authentication,
MPRIS, lifecycle, and a stable private Unix-socket boundary. The app starts the
unit whenever its full player or mini-player is open, when you play on this
computer, or when you choose it in Devices. Once every player surface closes,
it stops after the configured idle period; 0 keeps it available indefinitely.
This backend is the only playback engine; there is no second daemon.

The unit sets `PULSE_LATENCY_MSEC=250` only for local playback and caps
librespot's private player runtime at two Tokio workers. That buffer is what
stands between a stall anywhere in the decoder and a hole in the audio, and
librespot drains it before it pauses. Measured on the sink monitor: 250 ms
rides out a 140 ms stall, and the audio already queued plays for about 150 ms
after Pause is pressed. The backend's own control runtime is single-threaded;
keeping two player workers still allows network fetching, preloading, and
blocking decoder work to overlap. Quickshell interpolates MPRIS position
locally, so the backend publishes one authoritative position update per second
instead of four.

Pause and Play from this app fade over 200 ms. The backend wraps librespot's
audio output and ramps the volume of what it writes: a pause first fades the
next 200 ms of audio to silence and only then asks librespot to pause, so the
sound goes quiet about 350 ms after the press. A resume ramps up from
silence. Pauses and resumes started from another Spotify device are not faded.
If a pause never lands, the sound comes back after two seconds of silence
rather than playing on muted.

MPRIS uses a PID-qualified instance bus name, as required by the server library.
Quickshell discovers the backend by its `librespot` identity and desktop entry.
This lets diagnostic instances coexist without replacing the supervised
player's bus ownership or making the app lose local playback state.

The pinned librespot revision also applies an endpoint-continuous 20 ms fade
out/in around manual track replacement. Natural end-of-track gapless
transitions, seeks, and passthrough are unchanged. This fixes both the queued
tail and the smaller waveform discontinuity without changing PipeWire routing
or speaker tuning.

Volume sliders apply while the knob moves; the seek slider still commits on
release so a drag cannot make the player re-buffer per frame. A drag emits a
command per input event, so `Service` coalesces them: the first value is sent
immediately and later ones are queued and flushed at a per-backend interval,
`Api.volumeFlushInterval` — 80 ms for a local MPRIS property write, 250 ms for
the rate-limited Web API, and 120 ms for Sonos. The queued value is only cleared
once a backend accepts the command, so the position the knob was released at is
always the one that lands. The optimistic slider value is held until the player
reports it, and playback state is refetched once the drag settles rather than
after every command.

Web API requests use a SpotifyTransport queue per authorized app, with four
running at a time per queue. Each request
carries a priority: a button you pressed first, then a page you opened, then
ordinary work, then background work such as the library crawl. Background work
is capped at two of the four slots, spaced apart, and stands aside for three
seconds after anything you open, so a page you are waiting on is never behind
the crawl.

Known foreign playlist metadata and item pages opened by the user go directly
to the already-authorized catalog transport when a personal app is configured.
New personal apps cannot read these playlists, and waiting for a 403 first
fails when their playlist bucket instead returns `QUOTA_EXCEEDED`. Routing
requires known account and owner IDs and excludes owned/collaborative playlists,
unknown ownership, non-GET requests and account library endpoints. Pagination
and snapshot checks retain the chosen catalog route, and detail continuations
keep their ordinary queue priority. Track radio candidate probes and the reads
behind "make this playlist your own" choose the same way from the playlist they
already hold; the copy's writes stay on the personal app. Without an authorized
catalog session the existing personal path remains. Idle warming still never
uses the catalog fallback. Failure messages preserve the redacted API reason;
a development quota refusal is not presented as a short transient wait.
`PlaylistCatalog.qml` executes both transports and checks routing, continuation,
cache reuse and version checks, detail pages, radio and copy reads, absent
identities, quota and ordinary refusal messages and Client ID cancellation with
synthetic sessions.

The shipped developer app is shared across installations, so a refusal can
arrive without this user having sent much at all. Development-mode quota is
counted per developer account. On a 429 the affected transport honours
`Retry-After`, and the gap between background
requests doubles and stays wide for the rest of the run. One page you are
waiting on may try once during a cooldown, in case the refusal has slack in it;
after being refused itself it waits its turn. Personal and fallback transports
never share cooldown or pacing state. That state follows the Client ID rather
than the transport, so when Settings move the shipped app between the primary
and fallback transports its live `Retry-After` moves with it. Fallback attempts retain the original
request deadline and cancellation handle; the shared queue reports the expiry of
an attempt it holds, so a shared cooldown is named as such. Removing or changing
the fallback identity cancels requests it is still carrying, without callbacks,
as signing out does. Cancelling empties the shared queue before any of its
slots is freed, so a queued action cannot be sent during cancellation. Every request logs where its time
went — queueing, token refresh, or the network — and ends with the app that sent
it (`personal` or `catalog`), since both transports log into one stream and a
quota refusal has to be pinned on one of them. That is what makes a slow call
diagnosable at all. See `docs/LIBRARY-DATA.md` for the measurements.

After a rate-limit response, optional library work and automatic checks of
cached pages, including the pages that restore a remembered scroll depth, stand
aside for at least a minute, or longer if `Retry-After` requires it. Background
requests do not silently retry a 429 by default. Failed background library
refreshes preserve the cached collection and stop that crawl without replacing
the visible action status; a crawl that lost pages keeps the cached rows and is
not saved as fresh, so it is retried next time. Automatic checks of a page
already on screen are still background work, but they run ahead of queued
library pages so they are not starved by a long crawl. A cached-page check gives
up after the same 15 seconds as an opened page and never holds the list in a
loading state; opening, reloading or loading more replaces it. A playlist that
failed to load stays failed until it is opened again rather than being reloaded
automatically. Foreground requests, including an explicit Load More, have a
15-second total deadline, including time spent in the queue and retries; search
keeps its shorter deadline. A refused foreground request whose `Retry-After`
cannot fit inside its remaining deadline reports the rate limit at once instead
of waiting to time out. Expired requests are removed before freed slots can send
queued commands, so an old Play action cannot execute after timing out.

While the local player is up, every playlist read (`GET /playlists/{id}` and
`GET /playlists/{id}/items`, from an opened page, a version check, Load More,
a continuation cursor or the idle warmer) goes to its socket first as a
`playlist_items` command, and the Web API only when it is down or refuses the
read. The player's Connect session lists every playlist the account can see,
including the ones a personal Web API app is answered 403 for, and spends no
developer quota. `Service.playlistSourceRequest` translates the answer into
the Web API's own shapes (`Api.backendPlaylistPayload`): a version check gets
`snapshot_id` (the Web API spelling of the same revision) and `images`; a
rows page gets `items`, `offset`, `total` and a `next` that is the Web API
path for the following rows, so a cursor kept in the cache still works if the
player has gone away by the time it is followed. A page read this way also
names its version, which is published to the open list and its library entry
at once. Backend handles abort and chain like transport handles; a refusal
chains a Web API request with the caller's original options, catalog routing
included. A receiver set never to sleep (`idleShutdownMinutes` 0) is started
when the panel opens and when idle warming becomes able to run, so the rows
come from it rather than the Web API; a receiver that sleeps is not started
for reading alone, since it would flap on and off every sleep period.
While the player is up (`PlaylistCache.localReads`), the idle warmer ignores
the refusals and quota pauses it remembered from the Web API: those were the
Web API's answers, and the lists it was refused are exactly the ones the
player reads. `PlaylistBackendRows.qml` opens lists against a stand-in socket
and checks the rows, the cursor, the version and the fall-through.

Cached playlist pages retain their `snapshotId`. A stale page first requests
`GET /playlists/{id}?fields=snapshot_id` with revalidation priority. Matching
versions refresh the cache timestamp without fetching tracks. The open playlist
is always labelled with the version of the rows on screen, so an edit made
before replacement rows arrive is sent against the version it was made on.
Adding, removing or reordering stops any check, refetch or detail read of that
playlist already in flight, and a successful edit does so again, so a reply
read before the edit cannot replace the edited rows or the version it returned.
A successful add or removal always empties the open playlist and reloads it
from the top at its depth, so rows from before the edit are never shown under
the version it returned. A view whose read was stopped then reads again at the
depth it had: after a successful edit it reloads from the top, so rows from
before an outside change are never kept or cached under the edit's version;
after a failed edit the
moved rows are restored and stay on screen, cached or not, while their version
is checked again; rows that were only on screen are never written to the cache. A
changed or newly known version is published to the open playlist and its
library entry only after its first page of rows has replaced the old ones, so
reopening it from the sidebar trusts those rows; a restore it wakes then pages
on from the new rows. If that refetch fails or expires, the old rows, label and
stale cache stay, and the next visit checks again. A playlist cut to the 200-row
cache cap keeps a cursor just after the last kept Spotify position, so Load
More and deeper restores still reach the rest, in the opened playlist and in a
playlist detail page alike; pages without known positions lose their cursor.
A library version that differs from the cached rows bypasses the fresh-cache
shortcut but is settled by the same `snapshot_id` check, because `library.json`
is saved apart from the songs and can name the older version; a confirmed match
keeps the rows and corrects the library entry. Unknown versions fetch
content. Metadata
failures leave the visible rows and stale timestamp intact. Switching pages or
explicitly loading more cancels an outstanding version check.

The optional ClientSetupPopup presents the dashboard link, live redirect URI,
copy action, validated ID field and authorization status without a scroll view.
Its status line shows the latest action result next to the live connection state.
It uses the existing persisted `clientId` setting and PKCE authentication; no
client secret is collected. Saving there also updates the Settings Client ID
draft, leaving the other unsaved Settings drafts alone.

## Runtime requirements

- Omarchy 4 with the Quickshell shell enabled
- Spotify Premium
- the exact-commit attested plugin backend, or a local source build
- Omarchy base tools: `secret-tool`, `openssl`, `xdg-open`, `wl-copy`,
  `avahi-browse`, `systemctl`, and Python 3

The verified-release fast path also uses `curl` and GitHub CLI when available;
neither is trusted as a bypass when provenance verification cannot complete.

Omarchy's plugin installer deliberately clones and validates plugins without
running install hooks or privileged code. The enabled plugin therefore prepares
local playback on first load. It downloads the raw backend for the current
architecture from the matching version tag, checks the release checksum, then
requires GitHub's signed build provenance to match this repository, the pinned
release workflow, the exact tag and tagged commit, and a GitHub-hosted runner.
The tagged commit must be an ancestor of the checkout, and the backend source
and Rust toolchain must be unchanged between them. This permits later UI and
documentation commits without weakening the backend source binding. A
same-release checksum alone is never accepted as provenance.

If `gh` is unavailable or any download, checksum, identity, or attestation
check fails, the artifact is not executed. Setup instead builds `Cargo.lock`
from the reviewed source with the available Cargo. Configuration, verified
downloads, local builds, and user units themselves need no privilege.

Omarchy treats any write inside a plugin directory as a change to the plugin and
hot-reloads it, so the backend is compiled to
`$XDG_CACHE_HOME/omaspotify/target` (override with `CARGO_TARGET_DIR`),
never to the plugin directory itself. This keeps the recursive file watcher
from reloading the plugin — and killing the build — mid-setup. A stale
`backend/target/` left by an older build can be removed; the backend ignores it.

## Authentication

Web API access uses Spotify's Authorization Code with PKCE flow and the public
application identity also used by `spotify-player` and ncspot. The fixed callback
is `http://127.0.0.1:8989/login`. The playback backend performs its independent
browser authorization on loopback port `8000`. Receivers that advertise the
`accesstoken` or `authorization_code` token type use a separate, on-demand,
streaming-only PKCE grant on port `8990`.

No client secret or Spotify password enters the plugin. OAuth refresh tokens
are written to GNOME Keyring over stdin and separated by client identity.
Reusable local-playback authorization is stored with owner-only permissions in
`$XDG_STATE_HOME/omaspotify`; older credentials under `$XDG_CACHE_HOME`
are accepted once and migrated so clearing disposable caches cannot deauthorize
this computer. Player restore state (last tab, filters, search history, and
similar) is written to `$XDG_STATE_HOME/omaspotify/session.json` so it
does not pollute Omarchy's `shell.json`. Older copies kept as plugin settings
are read once and removed from `shell.json` after that file is written.
Short-lived access tokens and PKCE values remain in the shell process. OAuth
state is checked, callback listeners bind explicitly to IPv4 loopback, API URLs
are restricted to
`https://api.spotify.com/v1`, and sensitive credential patterns are redacted
before an error can reach the interface.

The app requests only the library, follow, listening-history, playlist,
playback-position, and playback-control permissions used by visible features.
It does not request profile or email permissions.

The Spotify account grant unlocks search, library, and remote control. Local
playback remains a separate approval. The full player and mini-player stay
usable after the account connects, even while that second step is unfinished.

## Local Spotify Connect

An active receiver already shown in the UI can accept a song click while an
unrelated playback-status refresh is still running. Only the initial refresh,
when no active receiver is known and local fallback could steal playback,
holds the click. Status reads have a two-second total deadline without
rate-limit retries. A click that waits replaces a queued status poll with its
own interactive read, so a background rate-limit pause cannot hold it. If that
read fails, the click reports the error instead of playing on this computer. A
ready local socket remains preferred. A running local receiver that Spotify
has reported since its current start can use the Web API immediately when
that socket is unavailable, instead of first waiting five seconds for it. A
connected socket that is not ready means the receiver is registering its
session again, so Connect is not used. Clicks during that, a start or a socket
wait stay pending, and the newest song plays once the socket is ready. A song
that is sent or dropped ends its socket wait, so the next click is not held
by it.

New playback keeps Spotify's currently active device. An explicit
choice in the Devices view takes priority, and the app's local device is used
only when no active target is available. Restricted active devices are kept as
the target rather than silently moving playback locally; Spotify may reject the
new selection when it does not allow Web API control. The app can perform a
one-shot `_spotify-connect._tcp` lookup for nearby receivers omitted from
Spotify's device response. It also resolves opaque Web API device names against
the matching locally advertised alias. For ordinary receivers, the helper
re-encrypts local playback's owner-only reusable credential for the receiver's
ephemeral ZeroConf key. Access-token receivers such as JBL receive the
short-lived streaming token as the ZeroConf blob, with a device-scoped mint
and the reusable credential as fallbacks; authorization-code receivers such
as Sonos receive a receiver-scoped code exchanged from that grant.
It then waits for Spotify to report the genuine device before transferring
playback when needed. It never asks for or stores the user's password.

An album or playlist in its unfiltered Original order starts Spotify's native
context, preserving the complete server-side collection. Sorting or filtering
switches row, context-menu, and collection-level playback to the displayed URI
sequence instead. Spotify accepts at most 100 URIs in one custom play request,
so the interface reports that limit when a longer visible sequence is started.

Once a restricted Sonos is active, the Web API rejects its player commands.
The app therefore resolves that same receiver on the LAN and sends fixed UPnP
AVTransport or RenderingControl actions for play, pause, previous, next, seek,
shuffle/repeat mode, and volume. Targets still come only from validated local
Spotify Connect discovery. Discovery also reads the current Sonos master volume
from RenderingControl because Spotify's `volume_percent` field is nullable.
That reading only stands in while Spotify reports none: whichever reading
arrived last, from Spotify, a discovery sweep or a volume command, is shown.
Shuffle and repeat travel as one Sonos play mode, mapped both ways through a
single table in `Api.js`. A command issued while an earlier one is still running
waits and runs next; a newer volume, seek, mode or play/pause replaces a waiting
one of the same kind, while skips are kept. When playback has moved elsewhere,
a local Play wake is attempted first;
the OAuth activation flow remains the fallback for a Sonos that has actually
lost its Spotify session. Receiver discovery and requests are retried briefly
because Sonos can sleep its endpoint during a handoff.

The current-playback response is also merged into the device list. This matters
for models that Spotify omits from `/me/player/devices`, or whose active device
id is null. A matching nearby receiver is recognized by name and type in that
case. Restricted devices remain visible with their current item. Controls stay
disabled unless the app has a supported local-control path such as Sonos.

Spotify changed development-mode endpoints and fields in 2026. This client uses
`/playlists/{id}/items`, `/me/library`, and search limits of 10. Some non-owned
playlist contents are no longer returned. Artist pages use artist-scoped catalog
search for the two ranked release/song columns because Spotify removed the
artist-top-tracks endpoint. Followed-playlist conversion fetches every available
page before creating a private copy, writes items in batches of 100, and removes
the original from the library only after all writes succeed.

## Local development

From a checkout on Omarchy 4:

```bash
./scripts/install-local.sh
```

The command validates the manifest, installs the user-level playback files,
links the checkout at
`~/.config/omarchy/plugins/io.github.jeremylanger.omaspotify`, and enables the bar widget. It
refuses to replace an existing plugin.

To install only the playback integration:

```bash
./scripts/setup.sh
```

Neither path enables or starts the playback unit at login.

## Verification

```bash
./scripts/test.sh
```

The suite runs Omarchy manifest validation, Qt 6 QML lint, offline Qt tests with
mocked authentication responses, shell-script tests, configuration checks, and a
forbidden-heavyweight-dependency scan.

Resource sampling:

```bash
./scripts/benchmark.sh idle 10
```

See [Benchmark](BENCHMARK.md) for methodology and recorded results.

## Complete removal

Run the bundled uninstaller from outside the plugin directory:

```bash
cd "$HOME" && "$HOME/.config/omarchy/plugins/io.github.jeremylanger.omaspotify/scripts/uninstall.sh"
```

This removes the plugin and all plugin-owned services, binaries, config, state,
caches, sockets, backups, and keyring entries. See the README's
**Remove it completely** section for the equivalent commands and legacy
keybinding check.

## Upstream projects

- [Omarchy](https://github.com/basecamp/omarchy)
- [librespot](https://github.com/librespot-org/librespot)
- [spotify-player](https://github.com/aome510/spotify-player)
- [ncspot](https://github.com/hrkfdn/ncspot)
- [Spotify Web API](https://developer.spotify.com/documentation/web-api)

### Idle playlist song cache

`PlaylistCache.qml` owns a separate account-scoped `playlist-songs.json` cache.
The opt-in `cachePlaylistsOnIdle` setting lets a one-request scheduler work only
while the panel is closed. It fills missing first pages before round-robin deep
paging, at least 3 s apart, with background priority and a 15 s request deadline.
No personal-to-shared fallback is allowed for warming. Foreground use, edits,
identity changes and logout cancel its current handle and invalidate callbacks.
Rows are kept per account, so while the setting is on and a session is signed in
(or not yet checked), the service loads the profile in the background with the
same 15 s deadline, retrying each minute, and fetches the playlist list if none
is on disk. A profile answer for an older identity or account is discarded.

Every write goes through `PlaylistCache.keep()`. It refuses everything while the
setting is off (rows already saved stay readable), and it refuses an empty song
list for a playlist the account neither owns nor collaborates on: Spotify hides
those songs, and the detail page explains that instead of showing an empty list.
Library playlist rows also carry `coverUrl`, the 256 px cover from the same
listing, because the detail page draws a cached list's header at that size. A
list saved from the Playlists page keeps the cover already held for the same
version, otherwise the listed `coverUrl`, otherwise the cover held before. A
version check whose new cover no longer fits the budget still confirms the
unchanged rows, so the list is not asked about again until its next daily check.

The idle scheduler checks completed playlists at most once a day unless the
library reports a changed version (foreground freshness remains five minutes;
an opened list checks itself, and the six-hourly library listing names changed
versions, so an hourly sweep of every held list only spent quota).
It compares `snapshot_id` (asking for `snapshot_id,images`, so each list keeps the
address of its cover at the detail page's 256 px size; no image is downloaded),
resumes matching partial pages, and
verifies the version after the final page. A changed version restarts fetching;
a changed final version discards the mixed copy. Duplicate and unavailable
track positions are retained through normalization/cursors. Empty playlists you
own or collaborate on can be cached. A refusal retries later (403 and hidden
songs after a week, since a personal app is never shown those lists; 404 after a
day; budget refusals after an hour; other failures after five minutes). Week-long
waits are written to `playlist-songs-checked.json` under `refused` and restored
with it, so a restart does not ask about every unreadable list again. 429
pauses the whole warmer for five minutes, or six hours when the body names
`QUOTA_EXCEEDED`, or until the refusal's own `Retry-After` when that is longer
(a development quota refusal can name many hours). A missing or unreadable
header keeps those pauses. Changing
the Client ID lifts the pause for the new app.
Cache failures never change foreground status.

`Api.encodePlaylistSongs` stores each normalized row with only the fields that
cannot be rebuilt (links from ids, album name, artwork and date from the album,
subtitle from the artists, empty defaults), under short keys, and lists each
artist or album once per playlist. `decodePlaylistSongs` returns rows identical
to the normalized ones; rows of any other shape are stored unchanged. A typical
row drops from about 2,200 JSON characters to about 340–400.

Budgets are 512 entries, 50,000 total normalized rows, 10,000 per playlist,
and 32 MiB estimated serialized data (two bytes per JavaScript string character),
counted on the stored form including each entry's key and frame and the file
envelope, so a file written at the budget always restores whole. Measured with
realistic playlist payloads, 32 MiB holds about 50,000 rows (about 40,000 when no
album repeats). At the budget no new playlist is added, but held ones are still
rechecked and refreshed; entries older than seven days give their room back.

`playlist-songs.json` is rewritten only when rows, versions or cursors change,
at most every 10 seconds and deferred while the panel is visible. Each entry's
stored form is kept, so a checkpoint joins strings instead of re-encoding rows.
A version check that only confirms a list updates its time in
`playlist-songs-checked.json`, a few kilobytes written at most once a minute;
on restore it applies only to the same version and row count. Cached playlists
render immediately; their version/freshness checks run behind the rows. The
existing small page cache remains available when this cache is absent.
