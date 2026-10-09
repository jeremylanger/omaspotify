# Changelog

## Unreleased

- The backend names the device that holds the account's Connect session.
  Spotify allows one active device per account, and librespot logs only
  "device became inactive" when another one takes it; the backend now follows
  the same cluster stream, logs "Connect session: Kitchen (speaker, Sonos
  One)" whenever the holder changes, and publishes it as `session_holder` in
  the state snapshot (`this computer`, the other device, or omitted while no
  device is active). A song that stops is then never a mystery.

- Playlists are read through the local player while it runs. The backend
  gained a `playlist_items` command that lists a playlist through its Connect
  session and describes the songs with one batched metadata request per
  hundred rows, answered off the connection's command path so pause and play
  are never held behind it. The result uses the Web API's own row shape and
  the Web API spelling of the playlist version, so opened pages, version
  checks, Load More, cached cursors and idle warming all take it without a
  second codec, and fall back to the Web API with the caller's original
  routing when the player is off or refuses a list. This reaches the
  playlists a personal Web API app is answered 403 for and spends no developer
  quota. A receiver set never to sleep is started when the panel opens and
  when idle warming can run, so the whole library caches locally; while it
  runs, idle warming sets aside the week-long refusals and quota pauses it
  remembered from the Web API, since those are the lists it now reads.

- Idle warming spends far less of a personal app's daily quota. A held list
  is compared with Spotify once a day instead of once an hour (the library
  listing still triggers a check as soon as it names a different version, and
  an opened list still checks itself after five minutes). A list the app may
  not read (403, or an empty answer for a list you neither own nor collaborate
  on) is left alone for a week instead of being asked about every hour, and
  that is remembered across restarts in the checks file. A `QUOTA_EXCEEDED`
  refusal pauses warming for six hours when Spotify names no `Retry-After`.
  Together these were about 250 requests an hour on a 119-playlist library.
  The idle resume candidate (the song Play continues with when nothing is
  loaded) is refreshed when a play ends and at most every fifteen minutes
  otherwise, instead of on every status poll that found nothing playing, which
  was 900 requests a day from an open panel. Every logged request line now ends
  with the app that sent it (`personal` or `catalog`), and a quota refusal's
  message carries Spotify's `Retry-After` when there is one.

- Opened foreign playlists use the already-authorized catalog app directly
  when a personal app is configured. A personal app's exhausted playlist quota
  no longer blocks a catalog read the shared app can complete. Owned and
  collaborative playlists, account library reads and edits keep their existing
  app; idle warming never switches to the shared app. Track radio and "make
  this playlist your own" read foreign playlists the same way, while the copy is
  still written by the personal app. Playlist failures display the actual
  redacted error instead of generic advice to try again soon. Idle warming
  waits out a refusal's full `Retry-After`, so a long developer-quota refusal no
  longer gets retried every five minutes.

- Starting a song on the displayed active receiver no longer waits for an
  unrelated playback-status refresh. Initial device discovery still waits for
  its own short refresh, bounded to two seconds without rate-limit retries,
  and reports a failure instead of playing on this computer. A running local
  receiver that Spotify has registered also uses Connect immediately if its
  socket is unavailable, rather than waiting a fixed five seconds first. While
  that receiver reconnects its session, the newest song waits for it instead.

- Optional idle playlist caching fills first pages across the library before
  paging deeper, persists progress, and checks Spotify versions to skip unchanged
  song lists. A separate bounded cache keeps these rows ready for playlist and
  detail pages. Warming pauses for browsing, edits and rate limits and never
  falls back from a personal app to the shared app. Open Playlists → Cache.
  Rows are stored compactly, so 32 MiB holds about 40,000 to 50,000 songs, and
  confirming an unchanged playlist no longer rewrites the song file. After a
  restart it finds your account without the panel being opened. Off keeps saved
  rows readable but adds and updates nothing. Playlists whose songs Spotify
  hides keep their explanation instead of being cached as empty.

- While Spotify is limiting requests, a page you open now loads or says
  Spotify is busy within 15 seconds. It used to sit on Loading for minutes
  behind the library refresh. When Spotify asks for a wait longer than that,
  the page says so at once. After a refusal, the background library refresh
  pauses for at least a minute instead of retrying. It keeps the library you
  already had and no longer replaces the status of your last action. A Play
  pressed during a long wait can no longer go off after it has timed out.
- With your own Spotify developer app set up, its requests no longer wait out
  refusals aimed at the shared app every install uses, and the other way
  round. Each app keeps its own queue and cooldown. Changing the Client ID in
  Settings takes effect without restarting the shell, and the new app no
  longer inherits the previous app's wait.
- An optional guide to setting up your own Spotify developer app is now
  offered on the login page, in Settings, and when the shared app runs out of
  quota. It links to the developer dashboard, copies the exact redirect URI,
  checks the Client ID before saving it, and starts authorization. It never
  asks for the Client Secret, and the shared app keeps working if you skip it.
- A playlist you have opened is drawn at once when you open it again. After
  five minutes, a small check asks Spotify whether it changed, and its songs
  are only downloaded again if it did. If the check fails, the rows you had
  stay on screen.
- On a Sonos, shuffle and repeat-one can now be on together. Turning shuffle
  on during repeat-one did nothing, and switching repeat to repeat-one turned
  shuffle off.
- A press on a Sonos while it is still carrying out the last one now waits its
  turn. It used to vanish, such as a shuffle pressed right after moving the
  seek bar. If several presses pile up, only the last of each kind is sent,
  and every skip counts.
- The Sonos volume slider now picks up changes made elsewhere, such as in the
  Sonos app or with the speaker's own buttons, once Spotify passes them on. It
  used to stay at whatever the speaker said when it was last looked for on the
  network.
- Clicking a song in a playlist now plays that song. Playing on this computer
  used to go by the row number alone, which can point at a different song
  when the playlist has songs that are unavailable. From Fred Nix's
  [#11](https://github.com/jeremylanger/omaspotify/pull/11).
- When Spotify is limiting the shared app every install uses, an empty
  playlist now says so and points to setting up your own app, instead of
  asking you to try again in a moment. From Fred Nix's
  [#10](https://github.com/jeremylanger/omaspotify/pull/10).
- Reloading the shell while OmaSpotify was still starting up no longer throws
  an error in the shell log. From wtyler2505's upstream
  [#104](https://github.com/stappmus/Omarchy-Spotify/pull/104).
- If a downloaded playback backend fails its checksum or signature check,
  setup now says so and warns against installing it by hand, instead of
  reporting it the same way as having no network. It still builds from source
  either way. From robin marin's upstream
  [#79](https://github.com/stappmus/Omarchy-Spotify/pull/79).

## 2.0.1

- Fixed Play doing nothing after the player had sat paused for a while.
  Spotify drops the connection now and then, and a paused player did not
  notice until the next click, which the reconnect then lost; it also came
  back with nothing loaded. The player now reconnects within a second and
  picks up the same song at the same spot, with the rest of the album,
  playlist or song list still queued behind it. If the connection drops
  mid-song, the song pauses and Play picks it up again.
- The volume stays where you left it. Every reconnect and every restart of
  playback used to put it back to the default, which the slider shows as 77%.
- Hovering a button no longer leaves its highlight behind once the pointer
  moves on, and the volume and seek bars no longer light up on hover. Arrow
  keys and Tab still show where the keyboard is; the first key after using
  the mouse just shows it.
- Pause fades out and Play fades back in over 200 ms, instead of cutting off
  or starting abruptly.
- Your listening draws about four times faster. Every day in the grid used to
  build its own tooltip, which cost more than the whole of the rest of the
  page put together; the grid now shares one. Hovering a day still names it
  and how many plays it holds.

## 2.0.0

OmaSpotify is a fork of [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify).
Changes below start from the fork point. For the history of the original plugin, see
[its changelog](https://github.com/stappmus/Omarchy-Spotify/blob/main/CHANGELOG.md).

- Fixed the audio cutting out for a moment every so often. The output buffer
  held only about 25 ms, so any brief stall in the decoder became an audible
  hole; it now holds 250 ms, which rides out a 140 ms stall while a pause still
  goes quiet in 142 ms.
- The song playing now stands out in any list: the whole row takes an accent
  wash, its title goes accent-coloured, and three bars move over its artwork.
  They settle level when playback is paused.
- A song's heart in a list now says whether it is liked, filled when it is and
  an outline when it is not, and an unliked row only shows its heart on hover.
  It used to be a filled heart meaning "save this", which disappeared once the
  song was saved.
- The song actions menu no longer hangs off the bottom of the window. It was
  placed using the height of whatever menu opened last, so a taller list of
  actions ran off the edge; it now works out its corner from its own height.
- The sidebar's Settings button is now a cog in the title row, the Playlists
  button is gone because picking a playlist from the list below already opens
  it, and Liked Songs shares its row with Create playlist.
- The kind, sort order and view controls sit on one row. Kind and view are
  icons that name themselves in their tooltip.
- The compact grid icon was a bed and the list icon was a focus box. Both now
  look like what they do.
- Now playing lost its outer box and gained a close button, so there is a way
  out of it besides the keyboard.
- The footer's like and song-actions buttons were never drawn: the row decided
  whether to show itself by reading whether its own buttons were showing, which
  can only ever answer no. They show now, including while the now playing view
  is open, where the rest of the track details step aside for them.
- Show Spotify's own playlists, like On Repeat, in the library when a
  personal Spotify client ID is set.
- Stopped erasing the saved library and listening history when the shell
  starts or reloads, such as when a monitor sleeps, with a personal Spotify
  client ID set. Only Log out clears them now. Settings also no longer reset
  to their defaults for a moment while the shell rebuilds, from Omarchy
  Spotify [#78](https://github.com/stappmus/Omarchy-Spotify/pull/78).
- `Ctrl+F` and `/` now start a search across all of Spotify; press again to
  search the current area. From upstream.
- Now playing is a full-window view with a live equalizer in the theme's
  colours, by Peter Sønderby ([#84](https://github.com/stappmus/Omarchy-Spotify/issues/84)).
  Open it with `E`, `Alt+Shift+N`, the sidebar, or the player artwork, and
  switch styles with `V`. The equalizer needs `cava`.
- Removed dead code: the unused `ArtistSearchSection` component, the `patches/`
  directory, and a duplicate copy of a screenshot shipped as `preview.png`.
- Shrank the documentation screenshots from 3200px to 1600px wide.
- Lint every source file by glob so a new one is never missed.
- Run the test suite in CI on every push and pull request. CI installs the
  QtQuick modules that `--no-install-recommends` was leaving out, without which
  no QML test could compile at all, and the three commands `setup.sh` checks
  for that a bare runner does not have.
- Follower counts are grouped from their digits rather than from whatever the
  engine hands back, which on some builds is already grouped: 1,200 followers
  came out as "1,,200".
- Removed the legacy spotifyd playback engine. The Rust backend is now the only
  engine, so there is no unit probe, no distro package fallback, and no second
  set of volume and position handling.
- Renamed the shared playback helpers off the spotifyd name and renamed the
  engine discovery and volume helpers to say what they actually do.
- Renamed the plugin to OmaSpotify. New plugin id, service unit, config, state,
  cache, socket, keyring entry, backend binary and Spotify Connect device name,
  so it installs alongside the original instead of colliding with it.
- Playback backends are now verified against this repository's own releases.
- Added volume normalization, on by default, with a Loud/Normal/Quiet level in
  Settings. Quiet and loud tracks now play at a similar level, which closes the
  loudness gap against the official client.
- Cached audio moved from ~/.cache/spotifyd to ~/.cache/omaspotify/audio.
- Fixed arrow-key navigation in the track context menu, which stopped working
  when the menu moved into its own file.
- Renamed the sidebar heading to the app's own name.
- Flattened the sidebar and player chrome: no frames, no tinted fills, and
  consistent padding.
- The library sidebar now lists albums, artists and podcasts alongside
  playlists, with artwork, four view modes, four sort orders, and pinning.
- Moved the ten player screens out of Panel.qml into their own files, taking it
  from 6,636 to 4,421 lines. The panel and its screens now talk through one
  explicit property instead of shared file scope.
- Share the keyboard modifier rules between the full player and the mini-player.
- Moved the six popups out of Panel.qml as well, taking it from 6,636 to 3,638
  lines overall.
- Moved the sleep timer and the lyrics-plugin flow out of Service.qml into their
  own files. The sleep timer now has 20 unit tests, where that logic previously
  had none, and the last uncovered playback-decision helper is now tested too.
- Added a Now playing screen, `Alt+Shift+N`.
- Added a Your listening screen, `Alt+Shift+I`: a day-by-day heatmap built from
  the play record the app keeps itself, plus top artists and songs.
- The artist page now shows followers and genres, your liked songs by that
  artist, and who else they sit next to.
- Added a New releases tab to Home.
- The library sidebar is cached to disk and drawn before Spotify answers, and
  album artwork is kept on disk instead of refetched.
- The artist page took 15-23 seconds to show anything. Every request now logs
  where its time went, which showed the wait was never the network — it was
  Spotify refusing requests, which paused the whole app for up to 24 seconds.
  Background work now backs off further with every refusal, stands aside for a
  moment after anything you open, and the liked-songs crawl resumes where it
  stopped instead of re-reading all 5,250 songs on every launch. A page you open
  now loads in 50-225 ms on a quiet account, and stayed under 7 seconds even
  while Spotify refused nine times in seventy seconds.
- Fixed a cancelled background request never giving its slot back, which could
  stall the library crawl for good.
- A page you have already opened now draws from the answer we kept and is
  checked in the background, instead of being emptied and fetched again. The
  pages are kept on disk too, so this works from a cold start. An artist page
  costs six requests, so reopening one is now free until what we hold goes
  stale, and a failed check leaves what is on screen alone.
- Fixed plays being counted before the stored record had been read back, which
  counted the same plays twice.
- The play record keeps everything, and now says so: a limit was being passed
  to a merge that never took one.
- Signing out now clears the listening record, the library cache and the kept
  pages, from memory and from disk. They used to survive into the next account.
- Comparing the listening record no longer stringifies it twice per page of the
  liked-song crawl.
- Fixed keyboard navigation in the library sidebar doing nothing in grid view,
  and opening an album, artist or podcast there as though it were a playlist.
- Fixed the compact library dropdown listing rows that could not be opened.
- Fixed the keyboard cursor pointing at the hidden skip buttons while a podcast
  plays instead of the back and forward ones on screen.
- Fixed a listening range that failed to load being kept as an empty answer,
  which stopped it ever being asked for again.
- The playback unit now names the runtime and config directories setup actually
  used, rather than only ever the default ones.
- Artwork is only fetched over https, and the artwork scan no longer builds a
  shell command out of an environment variable.
- The artist endpoints no longer send `market=from_token`, which is not a
  country code Spotify accepts. It uses the signed-in account's country.
- Fixed the playback device name overflowing its row instead of eliding,
  without pushing its icon away from it.
- Fixed the keyboard shortcut hint failing to read its fallback colours, and
  the playlist picker leaving the keyboard nowhere when it closed.
- A normalisation setting sent without its pregain is refused rather than
  quietly dropped.
- The OAuth redirect listener no longer buffers whatever a caller sends. It was
  `socat` piping raw bytes into a newline parser, so anything local could open
  the loopback port during sign-in and stream a request line that never ended.
  It is now a helper that reads into a fixed budget, gives up the moment that is
  passed, holds a deadline over the whole wait, answers and drops anything that
  is not the redirect, and hands back exactly one line. `socat` is no longer a
  dependency. Reported by @HANCORE-linux reviewing the marketplace submission.
- The backend read requests off its socket without a size limit, so a local
  client that never sent a newline could make it allocate until it died, and
  several at once multiplied that. One request is now capped, an oversized one
  is refused and the connection closed, and the number of connected clients is
  bounded. Reported by @HANCORE-linux reviewing the marketplace submission.
- A page took twenty seconds to open while the library was still loading. A
  refusal used to pause *every* request, so the library crawl being told to
  wait also froze the page you had just clicked. The pause is now kept apart:
  background work waits it out, and only your own request being refused holds
  your page back. Measured against a live cooldown, an opened page went out
  with no queue wait at all where polling still sat at 14-18 seconds.
- The working rules moved from root `AGENTS.md` and `CLAUDE.md` into
  `docs/DEVELOPMENT.md`, and the two agent-instruction files are no longer
  committed. The plugin installs into `~/.config/omarchy/plugins/`, where a
  coding agent can wander in and read a root instruction file as though this
  project had written instructions for it.
- Every screenshot in the README is retaken on the current design, and there
  are three more of them: Your listening, Now playing, and For you. The
  shortcut-hint recording is now a still of the same thing, which is a tenth
  of the size. The lyrics shot is retaken too, with Omasing matched to the
  song the player is actually on.
### Merged from upstream

- Search pages cancel obsolete requests, reuse cached results, and bound
  stalled API and token requests, with honest queued, cooldown and quota
  messages instead of silent dead ends.
- An optional personal Spotify Developer app client ID in Settings gives your
  account its own rate-limit quota, with invalid IDs rejected visibly and
  OAuth identities kept isolated per client.
- A setting to download no artwork at all, with compact text-only lists when
  it is off, and artwork requests and animation now pause while hidden.
- Failed artwork downloads are retried after transient network failures.
- An optional spinning vinyl record for the mini-player artwork.
- A setting to hide the lyrics button, and one for a fixed bar width so
  neighbouring bar widgets stop shifting between songs.
- The bar layout adapts cleanly at narrow panel widths, and in-panel popups
  stay opaque on translucent themes.
- Manual pagination past 200 items is preserved, and collection filters scan
  five pages at a time with Continue and Cancel controls.
- Global player shortcuts route through one shared owner to the focused
  monitor, and the keyring no longer waits forever.
- Local playback bounds its backend restart loop, reports safe startup
  failures, and offers an explicit Stop action that survives reopening.
- The local receiver activates before backend transport controls, and slow
  Avahi resolves no longer drop nearby Connect speakers.
- Server Retry-After delays above 30 seconds are honoured instead of capping.
- Pinned validation CI now runs real Quickshell authorization and app smoke
  tests, and installs the native helper dependencies it needs.
