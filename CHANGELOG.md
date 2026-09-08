# Changelog

## Unreleased

OmaSpotify is a fork of [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify).
Changes below start from the fork point. For the history of the original plugin, see
[its changelog](https://github.com/stappmus/Omarchy-Spotify/blob/main/CHANGELOG.md).

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
