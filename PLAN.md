# OmaSpotify — Development Plan

> Fork of [stappmus/Omarchy-Spotify](https://github.com/stappmus/Omarchy-Spotify) →
> **[jeremylanger/omaspotify](https://github.com/jeremylanger/omaspotify)**
> Full Spotify player for Omarchy: local playback engine, library, playlists, search — not just an MPRIS popup.

Local clone: `~/jeremy/omaspotify` (origin = our fork, upstream = stappmus, kept for cherry-picks)
Project config: `CLAUDE.md` is the source of truth; `AGENTS.md` is a one-line pointer to it.
(It cannot be a symlink — `omarchy plugin validate` rejects any symlink inside a plugin folder.)

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
   and `Service.qml`. Splitting them first makes that work faster and — per `CLAUDE.md`'s
   red/green TDD rule — actually testable. Splitting after means doing the UI work twice.

**A → B → C → D → then E and F interleave → G whenever.**

---

## Phase A — Housekeeping

Zero behavior change. Establishes a clean base and a green baseline.

- [ ] Commit `CLAUDE.md`, `AGENTS.md`, `PLAN.md` (all currently untracked)
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

`SleepPopup.qml` is the one surface not driven by hand: its timer button sits in the footer
and the keyboard cursor would not reach it. Its logic lives in `SleepTimer.qml`, which has
20 unit tests, and the popup itself loads without error.

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

The actual reason for the fork. Depends on Phase D.

- [ ] Theme engine: `appearance` enum (Omarchy default / Custom / Dynamic);
      Custom = JSON palette loaded via FileView; intercept the 5 root color properties
      in `Panel.qml`
- [ ] Dynamic mode: derive palette from current album art (art URLs already in the API)
- [ ] Grid view + thumbnails for playlists/albums (GridView + Image delegates) —
      the single biggest fix for "too text-heavy"
- [ ] Fix the horizontal dead space. Every list row puts the title and artist hard left
      and the controls hard right, leaving roughly half the row empty. It is the main
      reason the app reads as sparse and terminal-like
- [ ] Reconsider the all-monospace type. Album art is already present in every list, so
      the "text heavy" feeling comes from the typeface and spacing, not missing images.
      A proportional face for titles with monospace kept for durations and metadata would
      change the character of the app more than any other single edit
- [ ] Raise contrast between primary and secondary text. The palette is currently one
      muted green at slightly different opacities, so nothing leads the eye
- [ ] Rows are tall and lists show only four or five items in a half-height window;
      tighten row height or make it a setting
- [ ] Redesign the login screen (`LoginPage.qml`) — first thing a new user sees.
      Observed on the running app: the same instruction appears three times
      (header, card heading, button); the lower third of the page is empty because
      the card is top-aligned rather than centred; everything is one weight and one
      muted colour, so the primary button reads no louder than body text; the
      explanatory paragraph is too low-contrast to read comfortably; the two icon
      rows look interactive but are not; and the wordmark has no brand presence.
      Screenshot taken during Phase D verification
- [ ] Full Now Playing view: large art, dynamic background
- [ ] Reorganize Settings into real sections: Account / Playback / Appearance / Connect
- [ ] Sorting on collections (title, artist, recently added)
- [ ] Right-click context menus (add to playlist, radio, copy link)
- [ ] Queue drag-to-reorder
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

We depend on one person's fork of librespot for two patches. Per `CLAUDE.md` — *all code is
a liability, lean towards having someone else maintain that liability* — the goal is to get
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
