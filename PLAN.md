# OmaSpotify — Development Plan

> Fork of [stappmus/Omarchy-Spotify](https://github.com/stappmus/Omarchy-Spotify) →
> **[jeremylanger/omaspotify](https://github.com/jeremylanger/omaspotify)**
> Full Spotify player for Omarchy: local playback engine, library, playlists, search — not just an MPRIS popup.

Local clone: `~/jeremy/omaspotify` (origin = our fork, upstream = stappmus, kept for cherry-picks)
Working rules: `docs/DEVELOPMENT.md`. They used to live in root `CLAUDE.md` and
`AGENTS.md`; those are no longer committed, because the installed plugin directory is a
place a coding agent can wander into and read a root instruction file as trusted input.

---

## Why a fork

Upstream merges slowly: ~13 PRs merged vs 21 open, some sitting 1–2+ weeks.
We want to move fast and ship a differentiated plugin. MIT license, fork is clean.

Name "OmaSpotify": the official listing already has an unrelated `io.github.cempack.omaspotify`
(a dormant MPRIS popup, fork of an even-more-dormant markbus-ai repo, 0 stars, issues disabled,
last commit 2026-08-17). No legal collision — plugin ids are namespaced by author. Our listing
description should lead with the differentiator: full player vs popup.

Upstream author (stappmus) is active and his librespot patches are load-bearing for us.
Keep cherry-picking his transport/backend fixes; don't burn the bridge.

## The goal

Keep the performance win (~60 MB vs ~950 MB for the Electron client). Fix the thing that
actually motivated the fork: it's text-heavy and unrefined. Make it look and feel like a
first-class Omarchy app while staying tight.

---

## Verified facts

Checked against the code and upstream sources. Anything not listed here is an assumption.

**Codebase shape (~23k lines)**
- `Panel.qml` 6,636 lines and `Service.qml` 4,073 lines are **61% of all app code**
- `Panel.qml` = 10 screens + 6 popups + main window + ~2,000 lines of logic, one file
- `Service.qml` = 236 functions covering ~15 unrelated responsibilities
- 17 functions are duplicated near-verbatim between `Panel.qml` and `BarWidget.qml`
  (the whole keyboard/shortcut-hint state machine)
- Tests: 140 QML + 14 Python + shell suite, **all green**. But they only cover `Api.js`,
  OAuth, and three tiny components. `Service.qml`, `Panel.qml`, `BarWidget.qml` —
  12,000+ lines — have **zero** direct tests
- No CI runs the tests; the only workflow builds release binaries on tags
- Repo is 37 MB, of which 14 MB is screenshots. `preview.png` is a byte-identical
  duplicate of `docs/screenshots/red-hot-chili-peppers-under-the-bridge.png`
- Dead code: `ArtistSearchSection.qml` (nothing loads it), `patches/` (nothing reads it),
  `Api.displayedSliderVolume` (only its own test calls it)

**Backend / librespot**
- Backend is a Rust Cargo project built on librespot-playback, pinned to
  stappmus's librespot fork rev `6d3ecd76`
- That rev is on branch `fix/audio-key-unavailable` and carries exactly **two**
  fork-original commits on top of upstream librespot `dev` @ 2026-07-15:
  1. `playback: smooth manual track switches` (2026-08-15) — 20 ms fade out/in around
     manual track replacement, kills the audible pop when you skip.
     Submitted upstream as [PR #1740](https://github.com/librespot-org/librespot/pull/1740) — **still open**
  2. `playback: stop on rejected audio keys` (2026-08-24) — adds `PlayerEvent::AudioKeyUnavailable`
     so playback stops instead of skipping when Spotify refuses a decryption key.
     **No upstream PR exists**
- We are **locked in**: `engine.rs`, `protocol.rs` and `Service.qml` all reference
  `AudioKeyUnavailable` / `audio_key_unavailable`. Moving to stock librespot means
  losing that error handling or carrying the patch ourselves
- Upstream librespot `dev` is ~4 commits ahead of our pin's base (newest 2026-09-01),
  including `Spirc::clear_queue` (#1753) and an OAuth device authorization flow (#1745)
- `patches/librespot-0.8.0-manual-track-switch.patch` is a stale copy of commit 1.
  Nothing reads it — the pin supersedes it
- Gapless already enabled in `engine.rs` (`gapless = true`)

**Lossless — not achievable. This corrects the original plan.**
- FLAC *decoding* was merged upstream ([PR #1589](https://github.com/librespot-org/librespot/pull/1589), 2025-10-06)
  via symphonia. That is decoding only
- Spotify does **not serve lossless streams over the Spotify Connect protocol** to any
  third-party client. Connect endpoints — every third-party streamer and librespot —
  still receive legacy Ogg Vorbis 320 kbps. Lossless works only inside Spotify's own apps
- librespot's `Bitrate` enum has exactly three variants: 96, 160, 320. There is no
  lossless variant to expose. Our `config.rs` `bail!` on anything else is **not** an
  artificial cap by the plugin author — it mirrors librespot exactly
- [Issue #1580](https://github.com/librespot-org/librespot/issues/1580) closed as *not planned*.
  [Issue #1583](https://github.com/librespot-org/librespot/issues/1583) "Spotify lossless will not be supported" is open and pinned
- [Discussion #1578](https://github.com/librespot-org/librespot/discussions/1578) was **locked** 2025-11-07.
  Maintainer roderickvd: *"We've received communication from Spotify that makes it clear we
  cannot pursue development that circumvents their technical protections."*
- Maintainer position as of 2026-01 (#1685): no lossless support; anyone needing it should
  "partner with Spotify properly"
- **Conclusion:** do not promise or build toward lossless. Revisit only if Spotify opens
  FLAC to the Connect API. Pursuing it ourselves means circumventing DRM — off the table

**What the backend leaves on the table (all supported upstream, all unexposed)**
- `engine.rs` sets only `bitrate`, `position_update_interval` and `gapless`; everything
  else is `PlayerConfig::default()`
- That means `normalisation: false` — **volume normalization is completely off**.
  Five fields available: `normalisation`, `normalisation_type` (Album/Track/Auto),
  `normalisation_method`, `normalisation_pregain_db`, `normalisation_threshold_dbfs`.
  This is the real fix for the loudness gap vs the native app
- Audio backend is hardcoded `pulseaudio`; `AudioFormat::S16` is hardcoded
- `autoplay` and `max_cache_size` (1 GB) are parsed but never surfaced in the UI
- **Crossfade does not exist in librespot.** The original plan assumed it did.
  Building it ourselves means writing into the audio pipeline by hand — real work,
  real liability. Deprioritized

**Spotify app identity — we cannot register our own**
- Web API access uses ncspot's public client id `d420a117...`, so the browser consent
  screen says **"ncspot"**, not OmaSpotify. This is deliberate and inherited from upstream
- Registering our own app is not viable: Spotify cut Development Mode to **5 users** in
  February 2026, and Extended Quota is only open to organisations with 250k+ monthly
  active users. An own-app OmaSpotify would work for five people
- Every open-source Spotify client shares this constraint; spotify-player also adopted
  ncspot's client id
- Consequences to accept: a confusing consent screen, a rate limit shared with every
  ncspot and spotify-player user, and a hard dependency on that id staying alive
- [ ] Say this plainly in the README so the "ncspot" prompt does not look like a phish
- The playback backend authorises separately using librespot's own default client id

**Fork blocker**
- `scripts/build-backend.sh` hardcodes `repository=stappmus/Omarchy-Spotify` and verifies
  GitHub build attestation against *upstream's* releases. In our fork that check can never
  pass. It silently falls through to a local `cargo build`, so every user needs a full Rust
  toolchain and waits through a librespot compile. Must be fixed in the rebrand phase

**UI**
- Root colors in `Panel.qml` all route through 5 local properties
  (foreground/background/accent/muted/popupBackground) — single theme interception point

---

## Ordering

Changed from the original plan, for two reasons:

1. **Consolidation before rebrand.** The rebrand touches ~164 lines across 27 files, and a
   large share of those live in `spotifyd` files we are about to delete. Renaming things
   into the bin is wasted work.
2. **Decomposition before the UI overhaul.** Phase F is where we live inside `Panel.qml`
   and `Service.qml`. Splitting them first makes that work faster and — per the
   red/green TDD rule — actually testable. Splitting after means doing the UI work twice.

**A → B → C → D → then E and F interleave → G whenever.**

---

## Phase A — Housekeeping

Zero behavior change. Establishes a clean base and a green baseline.

- [x] Commit the working rules and `PLAN.md`. The rules ended up in
      `docs/DEVELOPMENT.md` rather than root agent-instruction files
- [x] Delete `ArtistSearchSection.qml` — dead, superseded by the inline
      `artistSearchMediaRow` component in `Panel.qml`
- [x] Delete `patches/` — nothing reads it; both patches are already in the pinned rev
- [x] Delete `preview.png` — exact duplicate of an existing screenshot; point the
      listing at the `docs/screenshots/` copy
- [x] Recompress `docs/screenshots/` and `docs/media/` (14 MB → target under 2 MB)
- [x] Delete `Api.displayedSliderVolume` and its test
- [x] Make `scripts/test.sh` lint `*.qml` by glob instead of a hand-maintained file list
- [x] Add CI that runs `scripts/test.sh` on push and PR
- [x] Reset `CHANGELOG.md` — it is 296 lines of upstream's release history

## Phase B — Engine consolidation — DONE

The plugin shipped two playback engines. See the appendix for why.

**Correction to the original plan.** It listed `Service.spotifydPlayer()`,
`Service.isSpotifyd()` and `Api.spotifydVolumeToSlider` as fallback code to delete.
They are not. `isSpotifyd()` matched `librespot` as well as `spotifyd`, so it is how the
app finds the **real** backend over MPRIS, and the volume curve converts librespot's
softvol logarithmic range for every local play. Deleting them would have killed local
playback. They were misleadingly named, so they were renamed, not removed:
`isLocalEngine()`, `localEnginePlayer()`, `Api.engineVolumeToSlider()`,
`Api.sliderToEngineVolume()`. Only `usingFallbackRuntime` was genuinely dead.

- [x] Make the Rust backend the only engine
- [x] Delete `systemd/omarchy-spotifyd.service` and its `Conflicts=` line
- [x] Rename the shared helpers off the spotifyd name: `configure-playback.sh`,
      `playback-auth.sh`, `playback-logout.sh`
- [x] Delete `DaemonManager.usingFallbackRuntime` and its two branch sites in `Service.qml`
- [x] Simplify `preferred_unit()` in `playback-runtime.sh` — no more probing which unit exists
- [x] Drop `--install-spotifyd` and the `pkexec pacman` fallback from `setup.sh`,
      `setup-playback.sh` and `install-local.sh`
- [x] Strip spotifyd from `tests/test-scripts.sh` and `tests/tst_api.qml`
- [x] Update README, TECHNICAL.md and backend/README.md
- [ ] Rename the config file away from `spotifyd.conf` — **deferred to Phase C**, because it
      also lives in `backend/src/config.rs` and this machine has no Rust toolchain to
      verify a build. Phase C renames the whole `omarchy-spotify` path anyway
- [ ] Drop the pre-1.0.3 `$XDG_CACHE_HOME/spotifyd` credential migration —
      **deferred to Phase C**, same reason: it is mirrored in `engine.rs`

## Phase C — Rebrand, identity & release pipeline — DONE

Identity was threaded through systemd, state paths, IPC and the keyring. All of it now
renames, so OmaSpotify installs **alongside** the original without collision.

- [x] `manifest.json`: `id` → `io.github.jeremylanger.omaspotify`, `name` → `OmaSpotify`,
      `author` → `jeremylanger`, bar widget `displayName`, `deviceName` default
- [x] `systemd/omarchy-spotify.service` → `systemd/omaspotify.service`
- [x] Config path `~/.config/omarchy-spotify/` → `~/.config/omaspotify/`,
      and `spotifyd.conf` → `playback.conf` (the Phase B deferral)
- [x] Binary install path `~/.local/lib/omarchy-spotify/` → `~/.local/lib/omaspotify/`
- [x] State, build-cache and runtime-socket dirs → `omaspotify`
- [x] Keyring service `quickshell-spotify` → `omaspotify`
- [x] Env vars `OMARCHY_SPOTIFY_*` → `OMASPOTIFY_*`
- [x] Backend Cargo package + binary `omarchy-spotify-backend` → `omaspotify-backend`
- [x] MPRIS identity, desktop entry and bus name. The identity keeps its `(librespot)`
      suffix — `Service.isLocalEngine()` matches on it to find the backend
- [x] Connect `device_name` → `"OmaSpotify"`, distinct from the original's "Omarchy Spotify"
- [x] **Fixed the release pipeline.** `build-backend.sh` now attests against
      `jeremylanger/omaspotify` instead of upstream
- [x] LICENSE keeps upstream's MIT copyright and adds ours
- [x] README install command points at the fork
- [x] Bump version to `2.0.0`
- [x] Made the test suite read the version from `manifest.json` rather than hardcoding it,
      so the next bump cannot silently skip the release-attestation test

**Still unverified:** this machine has no Rust toolchain, so the backend changes
(string literals in `config.rs` / `mpris.rs` / `engine.rs`, and the Cargo package rename)
compile-check only in CI. Run `cargo test --manifest-path backend/Cargo.toml` locally
before tagging a release.

**Still open, needs a toolchain:**
- [ ] Drop the pre-1.0.3 `$XDG_CACHE_HOME/spotifyd` credential migration. Nobody upgrades
      into a fresh plugin id in place, so it serves nobody. It is a structural change in
      `engine.rs` (a function parameter and its call site), not a string swap, so it waits
      for a compiler
- [ ] Cut a real `v2.0.0` tag so users get an attested binary instead of a local Rust build
- [ ] README rewrite: positioning vs the original and vs MPRIS popups

## Phase D — Decomposition & test safety net — IN PROGRESS

The prerequisite for the UI overhaul. No behavior changes.

- [x] Share the keyboard modifier rules between the full player and the mini-player
      (`ShortcutModifiers.qml`, covered by `tests/tst_shortcut_modifiers.qml`)
- [x] Turn the panel's inline `KeyHint` into a real file (`PanelKeyHint.qml`) so pages
      can use it from outside `Panel.qml`
- [x] Extract the 10 inline page Components into their own files. `setupPage` was the
      settings screen and is now `SettingsPage.qml`
- [x] Guard the new boundary with `tests/test_page_interface.py`, wired into
      `scripts/test.sh` and CI
- [x] Extract the 6 popups out of `Panel.qml` (`ShortcutHelpPopup`, `LyricsInstallPopup`,
      `MediaContextMenu`, `PlaylistPicker`, `CreatePlaylistPopup`, `SleepPopup`).
      `ContextMenuButton` moved into `MediaContextMenu.qml`, its only user
- [x] **Panel.qml: 6,636 → 3,638 lines (45% smaller)**
- [ ] Split `Service.qml` (4,073 lines) along its real seams: settings/session, playback
      state, library, playlists, search, devices/Connect, sleep timer, auth
- [ ] Target: no file over ~800 lines (`Panel.qml`, `Service.qml`, `Api.js` and
      `BarWidget.qml` are still over)

**What extraction cost, and what caught it.** Moving the pages out of `Panel.qml` broke
four things that `qmllint` did not report: three pages reached for ids that only exist
inside `Panel.qml` (`window`, `unifiedSearchField`), and three pages had their own root
id that collided with the new one. `qmllint` flagged one of the four. The rest were found
by a static check, which is now `tests/test_page_interface.py`.

**Verified in the running app.** Installed alongside the original plugin and exercised
every screen with a live Spotify session: For you, Discover, Library, Playlists, Queue,
Devices, Search, Settings, artist detail, and login. All render with real data and produce
**zero QML errors**. The shortcut-hints overlay and the keyboard-shortcuts popup both work,
which exercises the extracted `PanelKeyHint.qml` and `ShortcutModifiers.qml` directly.
Devices lists the original plugin as a separate Connect target, confirming the Phase C
identity split. Local playback runs through our own rebuilt backend — the player bar reads
"Playing on OmaSpotify" — so the Phase C rename holds end to end, binary included.

After the popups moved out, `ShortcutHelpPopup`, `MediaContextMenu` and `PlaylistPicker`
were opened in the running app and render correctly, including the key-hint badges inside
the context menu. `LyricsInstallPopup`, `CreatePlaylistPopup` and `SleepPopup` are verified
only statically so far; they are structurally identical to the three that were checked.
Screenshots captured for the Phase F redesign.

**How to make Service.qml testable — the key constraint.** Quickshell is statically linked
into its own binary; there is no loadable plugin, so `qmltestrunner` can never instantiate
`Mpris`, `Process`, `IpcHandler` or `FileView`. That is the real reason the three biggest
files have no tests, and no amount of test-writing changes it directly.

What does work: **keep Quickshell types at the edges.** `SleepTimer.qml` needed Quickshell
for exactly one thing — comparing a playback state to `MprisPlaybackState.Stopped`. Moving
that comparison up into `Service.qml` and passing a plain boolean made the whole component
pure QtQuick, and it now has **20 unit tests**. Apply the same rule to every future
extraction: the service owns the Quickshell objects, the extracted component owns the
logic and takes plain values.

Lifting pure functions into `Api.js` was considered and is not worth much on its own —
only 5 functions in `Service.qml` (about 24 lines) are free of its state. The value is in
extracting *stateful* components that avoid Quickshell types, as above.

**A bug the first guard missed.** Re-verifying against a freshly restarted shell found
`Panel.qml` still calling `contextMenuContent`, an id that moved into
`MediaContextMenu.qml`. Arrow-key navigation inside the context menu was dead — the
selection never moved — and it only surfaced as a `ReferenceError` in the shell log, never
as a visible failure. `qmllint` did not report it and neither did the interface guard,
because that guard only checked one direction: extracted files reaching into `Panel.qml`.
It now checks the reverse too, matching `name.` usage while ignoring same-named local
variables. Both directions are proven to fail the test when broken.

The lesson for the remaining work: **after extracting a block, the file it came from is as
likely to be broken as the block itself.**

**Re-verified against a restarted shell, after the fix.** All ten pages, the shortcuts
popup, the context menu (including arrow-key navigation and executing an action — the
queued track showed up in Spotify's own queue), the playlist picker, and the lyrics flow
(the Omasing window opens with the right track). Local playback runs through our backend
throughout — Spotify's own client reports "Playing on OmaSpotify". No QML errors from this
plugin since the fix landed.

`SleepPopup.qml` was confirmed by hand afterwards. Every extracted page and popup is now
verified in the running app.

**Why the page tests are static.** A runtime test that builds each page would be better,
but the pages use Quickshell UI types that cannot load in the offscreen test runner. That
is the real reason `Panel.qml`, `Service.qml` and `BarWidget.qml` have no tests upstream —
it is an environment limit, not an oversight. The static guard checks that every
`page.panel.X` a page reads exists on the panel, and that no page reaches into the panel
by id. Both failure modes are proven to fail the test.

The page/panel boundary is now an explicit interface of 71 members. Narrowing it is
worthwhile future work; it was previously unbounded scope access.

## Phase E — Audio & playback

Lossless is out (see Verified facts). These are the wins that are actually available.

- [x] **Volume normalization**, exposed as the same two controls native Spotify offers:
      **Normalize volume** (On/Off, now **on** by default) and **Volume level**
      (Loud/Normal/Quiet). The level maps to librespot's pregain using Spotify's own
      published targets — -11/-14/-19 LUFS, so Loud is +3 dB and Quiet is -5 dB from
      Normal. librespot's other five normalisation fields (type, method, threshold,
      attack/release, knee) stay at their defaults; native Spotify exposes none of them.
      Wired end to end: manifest → settings → `configure-playback.sh` → `playback.conf`
      → `config.rs` → `PlayerConfig`. Verified with `omaspotify-backend check`
- [x] Moved the audio cache out of `~/.cache/spotifyd` — a leftover from the removed
      daemon — into `~/.cache/omaspotify/audio`. A Phase C rename that was missed
- [ ] Expose `autoplay` in settings (already parsed, never surfaced)
- [ ] Expose audio cache size + a Clear Cache action (backend already manages 1 GB)
- [ ] Selectable audio backend — pipewire/alsa alongside pulseaudio (currently hardcoded)
- [ ] Keep the 96/160/320 quality setting exactly as-is and stop describing it as a cap;
      it is everything librespot offers
- [ ] Decide on the librespot pin (see appendix). Recommended: hold the pin, track PR #1740,
      re-pin onto upstream `dev` once it merges
- [ ] Crossfade — parked. Not in librespot; would mean hand-writing audio pipeline code

### Crackles and pops — first investigation

Reported as audible during playback, and **also present on the native Spotify client,
though less badly**. That points below our app. Measured on the dev machine:

- Over 30 seconds of active playback the sink recorded **zero new xruns**, so it is
  intermittent and was not reproducible during the pass
- Error counts are cumulative since each client started, not current rates:
  `voxtype` 1160 over 3 days (negligible), `wayvibes` 19 in 48 minutes (~1 per 2.5 min),
  our backend 11, the sink 30
- PipeWire is locked to 48 kHz (`clock.allowed-rates = [ 48000 ]`). **Spotify streams
  44.1 kHz**, so every track we play is resampled. Our backend's stream shows as
  `331/44100`
- `wayvibes` holds an always-on ~6 ms real-time stream for keyboard sounds. It has the
  highest xrun rate of anything on the machine and would affect the native client too,
  which matches the report
- Our unit asks for `PULSE_LATENCY_MSEC=30`. Upstream chose that for track-change
  responsiveness; it is aggressive for music and is our only lever

Next steps, cheapest first. Nothing changed yet — the fault was not reproducible, so a
speculative fix could not be measured:

- [ ] A/B with `wayvibes` stopped, since it is the highest-xrun client and is always on
- [ ] Add 44100 to PipeWire's `clock.allowed-rates` so Spotify audio is not resampled
- [ ] Only then consider raising `PULSE_LATENCY_MSEC`, ideally as a setting rather than a
      new hardcoded default, and measure xruns before and after

## Phase F — UI/UX overhaul

The reason for the fork. Ordered by how much each changes the feel per unit of work,
based on looking at every screen running with real data.

### F1 — The three things that make it feel like a terminal

These are all in shared components, so one change lands on every screen at once.

- [ ] **Close the horizontal dead space.** Every list row puts title and artist hard left
      and the controls hard right, leaving roughly half the row empty. This is the single
      biggest reason the app reads as sparse, and it is on every screen
- [ ] **Type.** Everything is monospace. Album art is already in every list, so the
      "text heavy" feeling comes from the typeface, not missing images. Proportional for
      titles and names, monospace kept for durations and other figures
- [ ] **Contrast.** The palette is one muted green at slightly different opacities, so
      nothing leads the eye. Give primary text, secondary text and disabled state real
      separation
- [ ] Row height: lists show only four or five items in a half-height window

### F2 — The first thing a new user sees

- [ ] Redesign the login screen (`LoginPage.qml`). Observed running: the same instruction
      appears three times (header, card heading, button); the lower third is empty because
      the card is top-aligned rather than centred; everything is one weight and one colour,
      so the primary button reads no louder than body text; the explanatory paragraph is
      too low-contrast to read comfortably; the two icon rows look interactive but are not;
      and the wordmark has no brand presence

### F3 — Structure

- [x] Library sidebar rebuilt. See `docs/LIBRARY-DATA.md` for what Spotify does and
      does not provide, established by testing every endpoint against a real account
  - [x] Mixed media, not just playlists: playlists, saved albums, followed artists
        and saved shows in one list
  - [x] Four view modes on a button in the sidebar, mirroring the native client:
        compact list, list (with artwork), compact grid, grid
  - [x] Sort control: library order (Spotify's own, and the default), recently
        played, recently added, alphabetical
  - [x] Local pinning, up to four, shown first with a marker. Spotify's own pins
        are **not readable** — no Web API endpoint, and the internal rootlist carries
        no pin state either. Both were checked directly
- [ ] Grid view for the main content area (the sidebar has one now)
- [ ] Full Now Playing view: large art, dynamic background
- [ ] Reorganize Settings into sections: Account / Playback / Appearance / Connect.
      It is one long scroll now, and new settings land below the fold
- [ ] Sorting on collections (title, artist, recently added)

### F4 — Theming

- [ ] Theme engine: `appearance` enum (Omarchy default / Custom / Dynamic);
      Custom = JSON palette loaded via FileView; intercept the five root color properties
      in `Panel.qml`
- [ ] Dynamic mode: derive the palette from the current album art

### F5 — Smaller wins

- [ ] Queue drag-to-reorder
- [ ] Right-click context menus (the keyboard path already works)
- [ ] Sleep timer polish

## Phase G — Differentiators

- [ ] Scrobbling (Last.fm / ListenBrainz) — backend already runs tokio
- [ ] Lyrics pane (build on the existing Omasing integration)
- [ ] Spotify Connect device switcher polish (already partially present)

---

## Appendix: the dev loop — changes do not hot-reload

`install-local.sh` links the plugin directory to this checkout as a **symlink**. Omarchy's
file watcher does not follow it, so editing a file here changes nothing in the running
shell — and `omarchy-shell shell rescanPlugins` does not recompile QML either. The app
keeps running the code it loaded at startup.

**After any edit, run `omarchy restart shell`.** Verifying against a running instance
without it means verifying stale code. This was discovered late: several live checks
earlier in the rebuild may have been against the previous build, though a full restart
afterwards loaded every extracted file with zero QML errors, which covers them.

## Appendix: two engines

The plugin today ships **two playback engines**:

1. **Rust backend** (`backend/` → `~/.local/lib/omarchy-spotify/omarchy-spotify-backend`)
   — the real one. Native librespot-based player, own systemd unit, MPRIS integration,
   protocol socket for the UI.
2. **Legacy spotifyd** — the old spotifyd daemon unit (`omarchy-spotifyd.service`)
   from earlier plugin versions.

At startup `DaemonManager.qml` probes systemd to find which unit exists and sets `unitName`;
`usingFallbackRuntime` = true means it found the legacy unit. Much of `Service.qml` then
branches: `activePlayer` picks the spotifyd MPRIS player, volume math differs
(`Api.spotifydVolumeToSlider`), position/seek handling differs.

Why it exists: users who installed early plugin versions got spotifyd, and the probe keeps
them working. `Conflicts=` between the units ensures only one runs.

**Why we delete it:** OmaSpotify is a new plugin with a fresh id. Nobody installs it
"upgrading" from the old plugin in-place, so the legacy fallback serves nobody. Its footprint
is 20 files.

## Appendix: the librespot dependency

We depend on one person's fork of librespot for two patches. Per the working rules — *all
code is a liability, lean towards having someone else maintain that liability* — the goal is to get
back onto stock librespot. Options:

- **Hold the pin (recommended for now).** Both patches are genuinely wanted: the fade fixes
  an audible pop on skip, which matters for a "refined" player; the audio-key handling is
  already wired through our backend and UI. Cost: we track a single-maintainer fork.
- **Move to stock librespot.** Frees the liability but reintroduces the skip pop and requires
  ripping `AudioKeyUnavailable` out of `engine.rs`, `protocol.rs` and `Service.qml`.
- **Carry our own fork.** Same liability, but ours, and we control the rebase cadence.
  Worth doing if stappmus goes quiet.
- **Help land PR #1740.** Best outcome. Reduces us to one patch. Cheap to nudge.

Either way: re-pin onto upstream `dev` periodically. We are ~4 commits behind, and
`Spirc::clear_queue` (#1753) is directly useful for queue management.

**Watch:** librespot discussion #1685 reports standard Ogg/Vorbis playback failing for some
accounts due to Spotify-side restrictions (#1649), affecting all librespot clients. Not ours
to fix, but it is the biggest external risk to this project.

## Appendix: side-by-side testing

All three can coexist **as long as identities don't collide**.

- Original plugin: id `quickshell.spotify`, units `omarchy-spotify*.service`,
  Connect device "Omarchy Spotify" — leave untouched at
  `~/.config/omarchy/plugins/quickshell.spotify/`
- Native app: separate Electron app, its own state — no conflicts
- OmaSpotify: new id/units/paths (Phase C) → installable via
  `omarchy plugin add https://github.com/jeremylanger/omaspotify.git --enable`
- **Watch out:** two engines with the same Connect `device_name` fight for playback;
  keep names distinct
- A/B recipe: same track, same quality; toggle normalization in each to reproduce the
  loudness-gap experiment; watch `pactl list sink-inputs` to confirm which client is audible
- Only one of the three should be *playing* at a time

## Phase H — pages, speed and the listening record

Done, all verified against the real account and the running app.

**Speed**

- Artist page **4,676 ms to 584 ms** by replacing name-searches with
  `/artists/{id}/top-tracks` and `/artists/{id}/albums`
- A **background request tier** so library crawling never delays a page you
  opened
- Requests in flight raised from 2 to 4; library pages fetched in parallel by
  offset with per-page retry
- The library is **cached to disk** and drawn before Spotify answers
- **Artwork cached to disk** (993 files, 7.5 MiB)
- Sidebar rebuilds coalesced, which is what actually stopped the flicker

**Pages**

- **Now playing** — new, `Alt+Shift+N`
- **Your listening** — new, `Alt+Shift+I`. A day-by-day heatmap built from the
  play record the app keeps itself, plus top artists and songs over three
  ranges
- **Home** — a New releases tab
- **Artist** — followers and genres, a liked-songs column, "Fans also like"
- **Playlists** — filtering enabled, and every sort column reverses

**Podcasts**

- Back 15 / forward 30 replace previous/next while an episode plays
- A finished episode no longer resumes at its own end

Playback speed is **not possible**: no Web API endpoint exists, and doing it in
the engine means resampling with time-stretching, or everything plays chipmunk.

**Rate limiting — the artist page that took 15 seconds**

Measured against the real account. Every request now logs where its time went
(`queue`, `auth`, `wire`), which is what made this findable.

- The wire time was never the problem: 27-300 ms throughout. A slow page was
  always **queue** time, and queue time was always a 429 cooldown. One refusal
  paused every request for 10-24 seconds
- We share ncspot's client id, so the budget is spent by other apps too. A
  refusal arrived within seconds of a cold start after **seven minutes of total
  silence** — that traffic was not ours
- What was ours: the liked-songs crawl is **105 of the 163 requests** a first
  run makes, and it started over from zero on every launch

Fixed:

- The gap between background requests **doubles with every refusal** and stays
  wide for the rest of the run. The budget is shared, so it cannot be guessed
  ahead of time
- The liked-songs crawl **resumes where it stopped** instead of re-reading
  everything
- Background work **stands aside for three seconds** after anything you open
- Pages someone is waiting on (a detail page, Home, the queue) are marked
  interactive. One of them gets an **early try per refusal** — one, however
  many are waiting — and then waits its turn rather than hammering
- An aborted background request now hands its slot back; it used to leak one,
  which would eventually stall the crawl for good

Result on a brand-new artist page, **14-23 s before**:

- Quiet account: **50-225 ms**
- Six opened in a row while Spotify refused nine times in seventy seconds:
  three landed in 76-225 ms, three waited 2.2-6.9 s for a real cooldown

Nothing reached fifteen seconds again. The refusals now land on background
work instead of on the page someone opened.

This is as far as client-side scheduling goes. The remaining slowness is the
shared client id, not our scheduling.

## Phase I — review of everything since the fork, and a page cache

A full read of the ~10,000 lines changed since `6024f31`, plus CodeRabbit
against the same range. Every finding was checked against the code before it
was acted on; the ones left alone are named below with the reason.

**A page you have already opened**

Pages used to be emptied and fetched from scratch on every open. They now draw
from the answer we kept and are checked behind the page, the way a query cache
works on the web. TanStack Query itself is not an option here — there is no
npm in a Quickshell plugin — so the method is what was borrowed: an entry per
page, a staleness clock, one fetch per key at a time, and eviction by age.

- `QueryCache.qml`, free of Quickshell types so it is unit tested like
  `SleepTimer`; the pure parts live in `Api.js` and are tested there
- 16 pages, 200 rows each, fresh for five minutes, dropped after a week
- Kept in `~/.local/state/omaspotify/queries.json`, so this works from a cold
  start, not just within a session
- A page drawn from the cache is never emptied first, and a failed check
  leaves what is on screen alone
- A page still on screen from the cache does not renew its own date, so it
  cannot stay "fresh" forever by being reopened
- Editing a playlist drops what we kept of it: every edit comes back with a
  new snapshot id, which is the one place that knows

**Bugs found and fixed**

- Plays were counted before `plays.json` had been read back, from a watermark
  of zero, and then counted again against the record — the listening counts
  could double
- A 600-entry limit was passed to a merge that never took one. The record is
  meant to keep everything, so the dead argument went rather than the data
- Signing out left the listening record, the library cache and every kept page
  on disk and in memory, for the next account to inherit
- Comparing the listening record stringified 690 KB twice per page of the
  liked-song crawl, 105 times
- Keyboard navigation in the library sidebar drove the list view even in grid
  view, where it is hidden; and opening a row there treated an album, artist or
  podcast as a playlist
- The compact library dropdown listed rows that could not be opened at all
- The keyboard cursor pointed at previous/next while a podcast plays, where
  back 15 / forward 30 are what is on screen
- A listening range that failed to load was kept as an empty answer, which
  stopped it ever being asked for again
- The playback unit hardcoded the default paths while every script honours
  `OMASPOTIFY_RUNTIME_DIR` and `XDG_CONFIG_HOME`
- `market=from_token` is not a country code Spotify accepts
- The device name overflowed its row instead of eliding
- `PanelKeyHint` read `Color` without importing it; `PlaylistPicker` left the
  keyboard nowhere on close
- A normalisation setting sent without its pregain was quietly dropped

**Hardening**

- Artwork is fetched over https only, and curl is told to refuse anything else.
  The urls come out of Spotify's answers and go straight into an argv, where a
  leading dash reads as an option
- The artwork scan no longer builds a shell command out of `XDG_CACHE_HOME`

**Left alone, deliberately**

- Migrating the original plugin's credentials and removing its units: the fork
  installs *alongside* it on purpose, and has never shipped a release
- The duplicate copyright line in `LICENSE`: keeping the upstream notice is
  what MIT asks of a fork
- The `omarchy-spotify` paths in the two-engines appendix: that section
  describes the state before Phase B, where those paths were correct
- A duplicated sentence in Settings, and the "Choose a playlist…" label on a
  dropdown that now lists the whole library — both are wording, which is
  Jeremy's call

## Still open

- Now playing has no lyrics surface yet
- The heatmap only goes back as far as the app has been running
- `BENCHMARK.md` predates this work; a like-for-like rerun needs a shell with
  no third-party plugins loaded
