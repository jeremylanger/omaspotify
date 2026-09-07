# Changelog

## Unreleased

OmaSpotify is a fork of [Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify).
Changes below start from the fork point. For the history of the original plugin, see
[its changelog](https://github.com/stappmus/Omarchy-Spotify/blob/main/CHANGELOG.md).

- Removed dead code: the unused `ArtistSearchSection` component, the `patches/`
  directory, and a duplicate copy of a screenshot shipped as `preview.png`.
- Shrank the documentation screenshots from 3200px to 1600px wide.
- Lint every source file by glob so a new one is never missed.
- Run the test suite in CI on every push and pull request.
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
