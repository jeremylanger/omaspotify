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

## Phase B — Engine consolidation

The plugin ships two playback engines. See the appendix for why. Deleting the legacy one
is the single largest simplification available and removes a whole class of
"which engine is playing / why does it sound different" bugs.

- [ ] Make the Rust backend the only engine
- [ ] Delete `systemd/omarchy-spotifyd.service`, `config/spotifyd.conf`,
      `scripts/configure-spotifyd.sh`, `scripts/spotifyd-auth.sh`, `scripts/spotifyd-logout.sh`
- [ ] Delete fallback paths: `DaemonManager.usingFallbackRuntime`, `Service.spotifydPlayer()`,
      `Service.isSpotifyd()`, `Api.spotifydVolumeToSlider`
- [ ] Simplify unit detection in `DaemonManager.qml` — no more probing which unit exists
- [ ] Drop `--install-spotifyd` from `setup.sh` and `install-local.sh`
- [ ] Strip spotifyd from `tests/test-scripts.sh` (48 references) and `tests/tst_api.qml`
- [ ] Rename the config file away from `spotifyd.conf` — the backend reads it but it is
      no longer a spotifyd config

## Phase C — Rebrand, identity & release pipeline

Identity is threaded through systemd, state paths, and IPC. All of it renames so OmaSpotify
installs **alongside** the original without collision.

- [ ] `manifest.json`: `id` → `io.github.jeremylanger.omaspotify`, `name` → `OmaSpotify`,
      `author`, bar widget `displayName`
- [ ] `systemd/omarchy-spotify.service` → `omaspotify.service`
- [ ] Config path `~/.config/omarchy-spotify/` → `~/.config/omaspotify/`
- [ ] Binary install path `~/.local/lib/omarchy-spotify/` → `~/.local/lib/omaspotify/`
- [ ] State/session dir references in `Service.qml` (`stateDir`, session file paths)
- [ ] IPC target string in `Panel.qml` (`ipcTarget`)
- [ ] Connect `device_name` → `"OmaSpotify"` (must stay distinct from the original's
      "Omarchy Spotify" or the two engines fight over playback)
- [ ] `DaemonManager.qml`: `unitName` default
- [ ] Backend Cargo package `omarchy-spotify-backend` → `omaspotify-backend`
- [ ] **Fix the release pipeline.** `scripts/build-backend.sh` → `repository=jeremylanger/omaspotify`;
      update `.github/workflows/release-backend.yml` accordingly; cut a real tagged release
      so users get an attested binary instead of a local Rust build
- [ ] README rewrite: positioning vs the original and vs MPRIS popups
- [ ] Bump version to `2.0.0`

## Phase D — Decomposition & test safety net

The prerequisite for everything visual. Nothing here changes behavior.

- [ ] Extract the 10 inline page Components out of `Panel.qml` into their own files
      (home, discover, detail, search, library, playlists, queue, devices, login, settings —
      note `setupPage` is actually the settings screen and should be renamed)
- [ ] Extract the 6 popups out of `Panel.qml`
- [ ] Extract the shared keyboard/shortcut-hint state machine into one component,
      deleting the 17 duplicated functions across `Panel.qml` and `BarWidget.qml`
- [ ] Split `Service.qml` along its real seams: settings/session, playback state,
      library, playlists, search, devices/Connect, sleep timer, auth
- [ ] Add tests as each piece comes out — this is where red/green TDD becomes possible
- [ ] Target: no file over ~800 lines

## Phase E — Audio & playback

Lossless is out (see Verified facts). These are the wins that are actually available.

- [ ] **Volume normalization** toggle + pregain + Album/Track/Auto mode.
      Headline audio feature: fixes the loudness gap vs the native app, ~5 config fields,
      fully supported upstream, currently off by default
- [ ] Expose `autoplay` in settings (already parsed, never surfaced)
- [ ] Expose audio cache size + a Clear Cache action (backend already manages 1 GB)
- [ ] Selectable audio backend — pipewire/alsa alongside pulseaudio (currently hardcoded)
- [ ] Keep the 96/160/320 quality setting exactly as-is and stop describing it as a cap;
      it is everything librespot offers
- [ ] Decide on the librespot pin (see appendix). Recommended: hold the pin, track PR #1740,
      re-pin onto upstream `dev` once it merges
- [ ] Crossfade — parked. Not in librespot; would mean hand-writing audio pipeline code

## Phase F — UI/UX overhaul

The actual reason for the fork. Depends on Phase D.

- [ ] Theme engine: `appearance` enum (Omarchy default / Custom / Dynamic);
      Custom = JSON palette loaded via FileView; intercept the 5 root color properties
      in `Panel.qml`
- [ ] Dynamic mode: derive palette from current album art (art URLs already in the API)
- [ ] Grid view + thumbnails for playlists/albums (GridView + Image delegates) —
      the single biggest fix for "too text-heavy"
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
