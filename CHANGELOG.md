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
- Moved the ten player screens out of Panel.qml into their own files, taking it
  from 6,636 to 4,421 lines. The panel and its screens now talk through one
  explicit property instead of shared file scope.
- Share the keyboard modifier rules between the full player and the mini-player.
- Moved the six popups out of Panel.qml as well, taking it from 6,636 to 3,638
  lines overall.
