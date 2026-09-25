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

Web API requests go through one queue with four running at a time. Each request
carries a priority: a button you pressed first, then a page you opened, then
ordinary work, then background work such as the library crawl. Background work
is capped at two of the four slots, spaced apart, and stands aside for three
seconds after anything you open, so a page you are waiting on is never behind
the crawl.

The rate limit belongs to the client ID, which we share with every other app
built on it, so a refusal can arrive without us having sent much at all. On a
429 the app honours `Retry-After` for everything, and the gap between background
requests doubles and stays wide for the rest of the run. One page you are
waiting on may try once during a cooldown, in case the refusal has slack in it;
after being refused itself it waits its turn. Every request logs where its time
went — queueing, token refresh, or the network — which is what makes a slow call
diagnosable at all. See `docs/LIBRARY-DATA.md` for the measurements.

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
