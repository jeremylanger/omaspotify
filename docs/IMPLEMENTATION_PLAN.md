# Omarchy Spotify implementation plan

Prepared 7 September 2026 from all 34 issues and 34 pull requests in [stappmus/Omarchy-Spotify](https://github.com/stappmus/Omarchy-Spotify). The snapshot contains 15 open issues, 19 closed issues, 21 open PRs, 11 merged PRs, and 2 PRs closed without merging. Every item has a disposition in the inventory below.

The recommended order is: ship focused reliability fixes, complete search and library behavior, then add optional presentation features. Reuse contributor work with the corrections below. A clean merge status is not evidence that a PR is ready to ship.

## Baseline and evidence

- The installed development checkout is at `ab572726`. GitHub main is two commits ahead at [`6024f3109080691821ad51d11b38d17ac610dc54`](https://github.com/stappmus/Omarchy-Spotify/commit/6024f3109080691821ad51d11b38d17ac610dc54).
- Main already includes [PR #38](https://github.com/stappmus/Omarchy-Spotify/pull/38): request priorities, FIFO within priorities, terminal cancellation, an eight-second search deadline, immediate search rate-limit errors, and transport tests. The earlier local review's search-priority finding is therefore already addressed upstream. Long cooldown truncation, all-category searching, and stale pagination remain relevant.
- The full QML suite on an isolated checkout of main passed: **140 passed, 0 failed**. The earlier installed-checkout API-only run passed 98 cases. Rust, Python, installer, and live playback suites were not rerun for this planning review; contributor validation claims remain separate from these checks.
- Reproduced locally during review: `Retry-After: 120` becomes 30 seconds; an old search pagination callback can add results to a new query; Python timeout output is bytes even with `text=True`, exposing a blocker in #54.
- Read issue bodies, discussion, PR descriptions, review decisions, changed-file inventories, and implementation patches relevant to the plan. Inspected the screenshot in #63: it shows a generic local-playback failure alongside an account-connected status. It does not establish the backend failure cause.
- This is a planning deliverable. No implementation PR was merged, no GitHub comment was posted, and no runtime or personal configuration was deliberately changed.

## Decisions carried forward

1. Preserve the lightweight Quickshell service, lazy panel, recycled rows, local MPRIS controls, and bounded caches. Measure before increasing polling, image retention, or background fetches.
2. Follow the maintainer's [#22 review](https://github.com/stappmus/Omarchy-Spotify/pull/22): transport, search caching, navigation, and filter pagination remain separate changes. Preserve Home, Discover, Queue, and artist-scoped filters.
3. Follow the [#26 review](https://github.com/stappmus/Omarchy-Spotify/pull/26): land discography correctness separately from configurable columns and unrelated row actions.
4. Follow the artwork reviews: #20 is the global artwork master switch; #25 follows it. Artwork Off also disables retries, zoom, and any future image surfaces while retaining their saved preferences.
5. Keep Omasing as the default lyrics integration. Treat #50 as a proposal for optional built-in lyrics and a separate artwork-zoom feature, not an automatic replacement.
6. Keep Pause resumable, as established by #30. Implement explicit local shutdown separately from hiding paused bar text or dismissing a window.
7. Distinguish account authorization, local playback authorization, device ownership, media availability, network failures, and Spotify restrictions. A generic reconnect instruction is not a recovery strategy for all of them.

## Delivery sequence

Effort is relative: S is a focused change, M spans components and integration tests, L needs a new state model or dependency work. These are scope estimates, not calendar commitments. Work in each row should remain separate reviewable PRs where listed.

| Order | Work package | Priority / effort | Depends on | Shipping outcome |
| --- | --- | --- | --- | --- |
| 0 | Baseline and test automation | P1 / M | Current main | Repeatable validation and preservation of existing fixes |
| 1 | Rate limits and search completion | P1 / M | 0; #64 before combined validation | Correct waits, useful failures, cached result categories |
| 2 | Terminal failures and authorization | P0 / L | 0; OAuth dependency approval for #67 | No permanent retry loops; actionable setup failures |
| 3 | Playback, device discovery, and IPC | P1 / L | 0; failure-state contract from 2 | Working local controls, reliable receiver discovery, one IPC owner |
| 4 | Large collections, discography, and likes | P1 / L | 1; data part of #26 | Complete browsing and predictable collection actions |
| 5 | Responsive UI and artwork preferences | P2 / M | 4 where layouts overlap | Usable narrow windows, coherent text-only mode |
| 6 | Explicit shutdown and resume | P2 / M | 2, 3; corrected #55 | Clear stop/reopen behavior without breaking Pause |
| 7 | Optional features and backend research | P3 / L | Relevant contracts above | Queue launcher, optional lyrics/vinyl, evaluated Soloist support |

P0 failure work should begin as soon as the baseline is captured; it need not wait for the search work. Independent small documentation and contrast changes can ship earlier. Rebase overlapping PRs one at a time rather than integrating every branch together.

## 0. Establish the implementation baseline

Use an isolated integration checkout of current main. Preserve the user's untracked `AGENTS.md`. Keep build and test output outside the registered plugin directory, following #7. Recheck all PR heads and review states when implementation begins.

Add a pull-request validation workflow; the repository currently has a backend release workflow but no PR test workflow. Run locked Rust formatting/tests/Clippy, Qt tests, Python helper tests, script checks, and plugin validation in a reproducible environment. Match the supported Qt/Quickshell/Omarchy imports; do not replace integration validation with permissive mocks that hide missing runtime APIs. Pin workflow dependencies consistently with the release workflow.

Expand tests at the service boundary where asynchronous state crosses requests. Existing pure API helpers and transport tests do not prove that page state, account changes, or receiver selection remain correct.

Acceptance: the same documented commands validate the reviewed commit locally and in CI; CI leaves no build output under the installed plugin; fixture-based tests require no real credentials.

## 1. Rate limits and search completion

**Adopt #64 and #66 first.** Preserve the server's full `Retry-After`, cap only the client-generated backoff, and chunk timers within QML's integer interval. Keep the shared cooldown and existing concurrency limits. Explain a search deadline spent in the cooldown queue differently from an HTTP request that was sent and stalled. This follows [Spotify's rate-limit guidance](https://developer.spotify.com/documentation/web-api/concepts/rate-limits).

**Then integrate #49 with service-level fixes.** Fetch only the selected result category; cache successes and empty results for the current normalized query; retain cached categories when switching tabs; make Refresh invalidate only the intended category. Retain generation checks for initial search, pagination, clear, logout, and query/type changes. Also store and abort the pagination handle: #49 rejects stale callbacks but still lets an obsolete pagination request occupy a slot and consume quota. Repeated Enter or tab clicks for the same pending query/type should reuse the request rather than cancel and restart it. Preserve an explicit retry target for first-page versus next-page failures. Add the inline Retry action to keyboard navigation and test its narrow layout with #48.

**Add structured request state and diagnostics.** Distinguish queued, refreshing authorization, waiting for Spotify, fetching, empty, and failed states. While a view is visible, show a cooldown countdown and enable Retry at expiry; do not silently resubmit expired search commands. Record route name without query strings, queue wait, token wait, HTTP duration, retry count, and HTTP/error category. Keep a bounded diagnostic buffer; never include tokens, authorization URLs, raw search terms, or account names. Extend #38's cumulative timing rather than adding a second logging system.

Add finite active-request and token-refresh watchdogs for ordinary reads, measuring their timeout separately from planned cooldown waiting. Most callers currently supply no deadline, so stalled background calls can retain both slots even though search itself eventually times out. Release those slots exactly once and retain explicit retry state. Treat an interrupted mutation as having an uncertain outcome; do not blindly replay a potentially completed queue addition or playlist write.

**Handle developer quota separately.** Spotify also documents a `QUOTA_EXCEEDED` reason in 429 responses for development-mode quota limits. Do not present this as a known short cooldown or repeatedly retry it as ordinary transient throttling. Preserve the structured reason and provide appropriate guidance. [Quota documentation](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)

**Revise #58 before adoption.** A personal client ID is an advanced option, with the shipped identity remaining the default. The current patch changes the effective ID without resetting in-memory tokens or invalidating pending keyring/refresh/OAuth operations. Bind every operation to an immutable client identity and generation. On an applied change, cancel old requests and auth operations, clear account-derived UI caches and in-memory tokens, and load only the new identity's keyring entry. A late refresh from identity A must never be stored under identity B. Preserve the separate streaming-only Connect identity. Make invalid input visible; do not silently claim the custom app was selected when falling back to the default. Cover switching back, logout, and removal of plugin-owned credentials across identities.

Document Premium and allowlist requirements, separate developer quotas, and possible endpoint restrictions. Do not advertise a personal app as unlimited quota or guaranteed access to all playlists. An extended-quota application is an external eligibility decision, not a deliverable this plan can promise. [Spotify quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)

Code: `Api.js`, `SpotifyApi.qml`, `AuthManager.qml`, search/settings paths in `Service.qml` and `Panel.qml`, and auth/transport/service tests.

Acceptance: no HTTP dispatch before a 120-second server cooldown expires; cached category revisits issue zero search requests; stale pagination never changes a newer view; clearing or closing search releases its requests; retry is keyboard accessible; account A's delayed work cannot affect account B. A simulated hung search ends within the existing deadline, and a known cooldown is identified accurately. Measure live time-to-results without asserting a latency guarantee for Spotify's servers.

## 2. Terminal failures and authorization

**Fix #39 independently of a new OAuth scope.** Add typed startup/runtime failure categories for unsupported account, missing credentials, invalid configuration, authentication rejection, transient network failure, audio-key rejection, and exhausted reconnect budget. Reserve distinct exit codes for terminal daemon failures. Add `RestartPreventExitStatus` and a meaningful start-rate limit to the user unit, for example a five-minute window with five starts; verify the actual configured restart cadence cannot loop indefinitely. Apply bounded behavior to the fallback unit where its exit information permits it. Avoid requiring `user-read-private` merely to solve this: a typed backend rejection is sufficient.

The current socket is created only after engine startup succeeds. Therefore a startup failure cannot be surfaced solely by a socket event. Publish a small, atomic, owner-only diagnostic record containing a safe error code and timestamp, or an equally explicit startup-status channel, and read it through `DaemonManager`. Clear stale failures on successful startup and appropriate explicit recovery. Keep the first actionable cause while terminal failures are latched. Prevent a visible panel or automatic activation loop from immediately starting the same permanently failed receiver again.

**Complete #67 after its dependency lands.** [stappmus/librespot#1](https://github.com/stappmus/librespot/pull/1) is still open. It must bind and retain the callback listener before publishing the authorization URL. Replace #67's temporary OAuth-only third-party fork override with an approved immutable dependency revision. Preserve typed port-conflict reporting through the wrapper and QML. Track the packaged spotifyd path separately; the PR does not fix it. Do not use a port check followed by closing and rebinding, which reintroduces the race. Dynamic ports are a later option only after verifying the registered app and runtime support the required flow. [Spotify redirect rules](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)

**Use these states to triage #28 and #63.** The #28 reporter confirmed a Free account; direct them to the supported-account message when shipped. #63 needs runtime version, active unit, and redacted failure classification before assigning a cause. Its screenshot alone does not justify resetting credentials. #16 and #45 remain separate audio-key compatibility tracking: the dependency issue [librespot#1649](https://github.com/librespot-org/librespot/issues/1649) is still open. Preserve the existing stop-on-rejected-key behavior and offer selection of another Connect device; do not claim that setup or ownership patches obtain missing audio keys.

Code: `backend/src/main.rs`, `engine.rs`, `protocol.rs`, dependency pins, systemd units, `DaemonManager.qml`, `Service.qml`, and setup/error UI.

Acceptance: unsupported accounts and missing credentials do not restart indefinitely; a network failure has bounded recovery; the UI names the actual failure rather than always saying reconnect. An occupied OAuth port yields the specific error before any browser launch or authorization URL output. Tests isolate credentials and browser launching. Premium login and legacy credential migration still work.

## 3. Playback, device discovery, and IPC

**Integrate #65 as an ownership fix.** Keep activation and Play/Toggle/Next/Previous in the same command FIFO for socket and MPRIS. Pause must not acquire ownership. Verify rapid Play/Pause ends paused, repeated skips are not dropped, enqueue failures reach callers, and local commands do not unexpectedly redirect controls intended for another selected device. Do not describe this as complete network recovery: #37 separately owns context restoration.

**Revise #40 around explicit playback intent.** Address a known receiver by ID and bound any transfer/retry to one attempt for the same still-current command. The patch hooks generic `apiAction`; narrow recovery so an obsolete command, Pause, or a remote-device failure cannot silently start playback locally or change the selected output. Preserve the selected remote/restricted target and Sonos routing. Give pending resume a generation, expiry, and clear-on-logout/device-change behavior. Resolve callbacks exactly once, including the path waiting for a local device ID.

**Fix #54's timeout-output handling before merging.** Its current `isinstance(error.stdout, str)` drops real timeout output because Python supplies bytes even with `text=True`. Decode bytes with a defined encoding and replacement policy, also accept strings, retain resolved records, and reject empty/invalid output. Keep validated local addresses and deduplication. Add a real short subprocess timeout regression, not only a mocked string. Measure the eight-second timeout on a multi-speaker LAN; expose discovery progress and retain already known devices while it runs.

**Split #53 into device state and IPC ownership.** Diagnose the phone-initiated activation race separately from locally dispatched commands; #65 does not necessarily repair an incoming remote handshake. Model receiver starting, ready, reconnecting, active, and failed states explicitly. Move the global player IPC handler out of per-monitor `BarWidget` instances into the shared service or a single shared controller. Register UI surfaces with that controller; route opening/toggling to the focused monitor, with a stable fallback when a monitor disappears. Preserve existing command names and volume semantics. This is a prerequisite for #59's extra launcher command.

**Keep #37 blocked until its recovery contract is complete.** It is a draft and explicitly cannot recover shuffled order exactly. The snapshot must preserve original context order, duplicate occurrences, cursor/continuation, manual queue, shuffle state, repeat, position, volume, and paused state. Confirm restoration through actual player events rather than treating successful command enqueueing as completed playback. Restore only when ownership and later user actions permit it; a phone taking over during the outage must not lose playback to stale restoration. If exact recovery is unavailable, retain an explicit resume path and explain the limitation rather than silently rearranging the queue.

Acceptance: local socket and MPRIS controls work after ownership loss; fallback wake never overrides a newer user choice; one IPC target exists with two monitors; timeout discovery retains real partial output. Induced reconnect tests cover playing, paused, duplicate tracks, shuffle/repeat, a changed remote target, and exhausted recovery budget. Keep #61 open for any context-restoration portion not demonstrated by #65; #60 is its closed duplicate.

## 4. Complete collections, discography, and likes

**Separate browsing limits from memory limits.** Sidebar playlist pagination already continues beyond 200 items after #14. Generic library collections, search categories, and parts of the detail/artist paths still truncate at the shared cap. Audit those paths individually rather than reopening the already-fixed playlist issue wholesale. Preserve continuation URLs until exhausted; bound cached collections and images independently. Start with on-demand metadata pagination and profile large lists before introducing a more complex page-backed model.

**Implement the remaining filter-pagination split from #22.** Keep existing filters and shortcuts. While a filter is active, scan one next page at a time with a cancellable generation, request budget, and visible progress such as “Searching 300 loaded songs”. Pause at the budget with Continue and Cancel actions; preserve continuation and never represent partial results as an exhaustive search. Stop on authentication failures, quota restrictions, cooldowns, or navigation changes. Manual Load more must continue past any automatic scan budget. Reuse identical in-flight collection pages instead of requesting them twice.

**Take the navigation split as its own UI change after #49.** Make global Search directly discoverable in the sidebar, clearly label global search versus a collection filter, and preserve Home, Discover, Queue, and artist-scoped searching. Resume an interrupted uncached search on return and retain scroll/focus for cached results. Specify the complete shortcut map before changing handlers: global-search focus, local-filter focus, category switching, Escape, and tab traversal. Test numeric-category shortcuts on AZERTY as well as QWERTY, and preserve the current documented shortcuts or provide an explicit migration. Include the Search destination in #48's narrow navigation strip. This work must not be bundled into transport or artist-data fixes.

**Split and fix #26.** First replace unfiltered artist-album text search with the stable artist-ID discography endpoint, preserving the current layout and artist-scoped text search. Verify endpoint parameters against current official documentation when implementing. Preserve variants when deduplicating across pages; name/type/track-count alone can collapse genuinely different editions. Test release precision, EP/single/compilation behavior, same-name artists, pagination, and QVariantList input. Replace `Array.isArray(sections)` at the cross-component boundary with `Api.arrayValues(sections)`. Configurable columns and Personalize follow only after the data behavior and responsive layout settle; unrelated row actions are their own patch.

**Investigate #51 as a surface-specific problem.** The reporter can like/unlike from the bar widget, so do not assume all library writes are broken. Reproduce saved/unsaved rows at compact widths, hover and keyboard focus; trace `showSave`, action collapsing, saved-state lookup, and endpoint errors independently. Keep a discoverable save action in the row or accessible menu, synchronize all surfaces, and show failures rather than treating a failed saved-state lookup as confidently unsaved. Reuse the row-action portion of #26 only after review.

**Handle restricted data explicitly.** Keep empty, failed, and inaccessible playlists distinct. Preserve the ability to play a Spotify context when its track list cannot be fetched, and never promise a custom client ID restores withheld content. Preserve duplicate playlist occurrences and displayed playback order from #23, plus depth/scroll restoration from #35.

Acceptance: manually reach item 701 in a 700-plus collection; find a match beyond page one and beyond 200 items with honest scan progress; cancel mid-scan without a late UI update. Preserve duplicate tracks, original-context playback, sorted/filtered playback, and restored scroll. Likes remain discoverable and consistent across rows, mini-player, and footer.

## 5. Responsive UI and artwork preferences

**Adopt #48 and #57 in focused changes.** Validate wrapping category controls, compact navigation, actual available content width, and essential footer controls at 300, 360, 440, 760, and normal desktop widths. Test both sides of breakpoints with shell scaling and larger fonts. Retained controls need valid keyboard targets; hidden controls must leave the focus order. Include #49's error row and any artist columns. Keep in-panel menus readable on translucent themes without changing separate compositor-blurred popup windows.

**Introduce #36, then rebase #20 on the shared image component.** Bound retries, stop them when artwork is disabled or the surface is inactive, and reset safely when a recycled row receives a new item. Check retry URL behavior with actual supported artwork URLs. #20 must remove artwork tiles and reclaim spacing everywhere, not just hide the image. Add the missing default/schema coverage requested by the maintainer. Audit rectangular art, footer art, artist/detail art, rows, and future launcher/zoom surfaces. Retain Omasing's handoff contract.

**Then #25, #46, #56, and #62.** Vinyl remains opt-in and its animation stops while paused, hidden, or artwork-disabled. The hide-lyrics preference applies consistently to buttons, shortcuts, and help. Fixed bar width remains opt-in and has coherent behavior with unlimited width and icon-only mode. For #62, validate a small glyph-size adjustment across supported fonts and scales; preserve #29's standard hit target and optical alignment.

Acceptance: no essential control clips at the supported minimum width; text-only mode triggers no artwork downloads or retry timers; hidden/paused animation produces no continuous rendering work; settings survive reload; opaque and translucent themes remain readable. Use visual checks for geometry changes rather than implementation-mirroring tests.

## 6. Explicit shutdown and resume

**Correct and integrate #55.** Keep the most recently playable item available when an empty receiver has no context. Its current throttle applies only when a non-null candidate exists, so empty history can trigger repeated requests. Cache empty success and back off failures; clear request state safely across logout/account changes. Prefer the existing local/history cache before another network request. Mark the candidate as ready to resume without inventing live playback metadata, and distinguish restarting a recent track from resuming its exact previous position.

**Address #68 through a deliberate stop action.** Keep the current paused-text setting as the simplest way to hide the bar title. For actual shutdown, follow the [#10 discussion](https://github.com/stappmus/Omarchy-Spotify/pull/10): a bar context-menu action labeled “Stop playback on this computer”, plus an accessible equivalent in the full player. Closing the popup continues to dismiss only the UI. Stop the plugin-owned local runtime without logging out or deleting history; suppress automatic restart until a new explicit local-play request. Remote playback on another device continues unless the user explicitly controls that target. Reopening the player and choosing Play must start the receiver again predictably.

The earlier review also requested an easy reopening path. Provide and verify one through the existing bar/IPC path and, if a launcher entry is added, include it in uninstall coverage. Keep shutdown, hiding paused text, and removing the plugin separate actions.

Acceptance: Pause retains metadata and queue; explicit local stop removes the local session and stays stopped; window close preserves playback; reopening and Play works; phone/Sonos playback is unaffected by stopping this computer; custom-client and remembered-resume state remain isolated.

## 7. Optional features and dependency research

**#59 queue launcher: revise after search and IPC stabilize.** Give the launcher its own cancellable search state or a shared request broker with separate consumers, so opening it does not replace full-panel results. Its current `nextBurst` can enqueue up to 100 remote Next commands and ignores individual failures. Replace this with a supported target-selection operation where available, or a bounded, sequential, cancellable skip operation that stops on error and device change. Respect Sonos routing and duplicate occurrence identity. Roll back failed optimistic additions, clear account-specific state, stop refreshes when closed, and honor theme colors and artwork settings. Validate simultaneous panel and launcher use.

**#50 built-in lyrics and zoom: split before consideration.** Preserve Omasing by default; make any built-in provider an explicit option. Add request deadlines, cancellation, response-size limits, plain-text rendering, bounded caches, and accurate song matching. Gate fetching and interpolation on an open lyrics surface. The current service timer runs every 100 ms once lyrics have been requested while playback is active, even after the view closes; fix that before a performance claim. Separate artwork zoom, initially using Spotify's available image, from any optional external artwork lookup. Preserve #20/#36/#46 contracts. The PR's live test checklist is still unchecked, so its functionality is not release-validated.

**#41 Soloist: evaluate a supported external receiver path now.** A commenter reports lossless playback with a separately installed Soloist selected through Connect. Spotify's official docs confirm a Linux headless client with a WebSocket API; that makes a compatibility prototype worthwhile. It does not prove lossless quality on this machine. Keep the built-in librespot quality ceiling unchanged until demonstrated otherwise. [Issue #41](https://github.com/stappmus/Omarchy-Spotify/issues/41), [official Soloist documentation](https://developer.spotify.com/documentation/soloist)

Start by documenting and testing an independently installed Soloist as a selected Connect target. Verify actual quality, controls, authentication, device naming, restart behavior, and resource use. A managed adapter is a later product decision: users require their own API key, Spotify prohibits redistributing its binaries, and builds expire after 90 days. Any integration must account for supported installation and updates. [Official download/update rules](https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates)

**#13 remains deferred.** The closed request asks for recommendation feedback rather than ordinary Next. Preserve that distinction; do not present local hiding/skipping as changing Spotify recommendations. Reconsider only with a verified supported API or a separately requested local feature.

## Integration and release gates

1. **Initial patch candidates:** rebase and validate #64, #66, #44, and #57. These are small, focused fixes; adoption still requires current-head review and combined tests.
2. **Reliability release:** add corrected #49, #39 terminal handling, #65 ownership, corrected #54, and the IPC part of #53. Include #67 only after its approved dependency and authentication checks are ready. A smaller search/UI release can ship while backend work proceeds.
3. **Completion release:** corrected #58, #40, and #55; collection/filter work; #26's data split; #51; #48; #36 and #20. Coordinate overlapping `Service.qml`, `Panel.qml`, and manifest changes by rebasing each successor on the accepted predecessor.
4. **Optional release:** #25, #46, #56, #62, explicit local stop, and any accepted optional feature. #37 exact recovery, #50, and a managed Soloist adapter remain separately gated. Do not hold completed reliability work for them.

For every integrated group, run `scripts/test.sh` and verify locked dependency resolution. Add race tests only where they assert meaningful behavior: account switch during refresh; stale page after new search; timeout releasing a slot exactly once; receiver change during recovery; paused state across reconnect; raw bytes on a real subprocess timeout. Run relevant live scenarios once the automated checks pass. A contributor's earlier passing test count is not sufficient after rebase.

Use the existing benchmark harness for an identical baseline/candidate sequence: idle closed, local playback closed, mini-player, full panel, repeated search/type switches, large-list scrolling, sleep/wake, and optional artwork off/on. Report plugin-related deltas against the same shell and theme; total Quickshell RSS includes unrelated plugins. Capture HTTP counts, queue/token/network time, CPU, resident memory, wakeups, and frame stalls. Proposed gates: no requests for a cached category revisit; no artwork traffic when disabled; no periodic feature timers for closed optional views; no unbounded growth after repeated view cycles. Investigate any material baseline regression rather than promising an unmeasured memory figure.

Preserve regression coverage from closed work: theme contrast (#2/#21), bar sizing (#3/#17/#29), sliders (#5/#31), likes (#6), socket connection after install (#8), paused sessions (#30), playlist order/pagination/restoration (#14/#15/#23/#35), durable session state (#18), backend reconnection (#19), provenance and source update checks (#27/#34), and complete uninstall (#32).

For a backend release, update the plugin/backend versions, lockfile, and changelog together; produce new attested x86_64 and aarch64 artifacts from an immutable tag using `docs/RELEASING.md`. Test stale-backend replacement, UI-only commits after a tag, unavailable attestation, source-build fallback, credential migration, and packaged spotifyd selection. Ensure setup reports verification/build progress and the active runtime accurately, so compilation is not mistaken for a playback CPU regression. Do not reuse or move a published tag. Keep rollback to an earlier compatible release possible without clearing credentials; follow-up changes to a bad release receive a new version.

Coordinate backend merges with the release window: once main's backend inputs differ from the last attested tag, new installs can legitimately fall back to local compilation. Stage integration checks before merging and publish the matching artifacts promptly. Keep UI-only reliability work independently releasable while a dependency-backed change waits.

Issue closures require the specific reported behavior to be fixed and published. In particular, an ownership-dispatch test does not close full reconnect recovery, and an OAuth fix for the built-in backend does not close the packaged fallback path. Future contributor-facing review messages should begin with a brief thank you and remain concise, following `AGENTS.md`.

## Complete issue and PR inventory

The dispositions below are implementation recommendations, not new GitHub reviews. Status and head identifiers are from the 7 September snapshot. “Candidate” means suitable for the stated validation/revision path, not approved to merge.

### Open issues

| Item | Snapshot state | Disposition |
| --- | --- | --- |
| [#16: Songs not playing](https://github.com/stappmus/Omarchy-Spotify/issues/16) | Open | Keep open for audio-key compatibility. Earlier stale-binary/cache-loss subcase was fixed; package 2 diagnoses remaining cases without conflating them. |
| [#28: Playback not working, maybe signup issue](https://github.com/stappmus/Omarchy-Spotify/issues/28) | Open | Reporter confirmed Free account. Resolve through precise unsupported-account handling in package 2, then close with applicable guidance. |
| [#39: Free-account failure is retried forever, degrading a clear error into a misleading "Bad credentials"](https://github.com/stappmus/Omarchy-Spotify/issues/39) | Open | P0 new implementation: classify terminal failures, stop restart loops, surface startup reason; package 2. |
| [#41: Plans to integrate Lossless?](https://github.com/stappmus/Omarchy-Spotify/issues/41) | Open | Prototype independently installed Soloist as a Connect target; verify quality and lifecycle before optional managed integration; package 7. |
| [#42: Playback OAuth silently fails when port 8000 is already in use](https://github.com/stappmus/Omarchy-Spotify/issues/42) | Open | P0 setup ordering issue. Built-in fix is draft #67 plus dependency PR; packaged spotifyd remains separate, package 2. |
| [#43: Super+Shift+M player setting is not wired to Omarchy's stock Music keybinding](https://github.com/stappmus/Omarchy-Spotify/issues/43) | Open | Take #44 documentation first; preserve manual-binding truth in UI. IPC reliability then improves in package 3. |
| [#45: Local playback fails when Spotify audio key is unavailable](https://github.com/stappmus/Omarchy-Spotify/issues/45) | Open | Track with #16 for rejected audio keys, retaining per-report evidence. Preserve explicit error and no rapid skip loop; package 2. |
| [#47: Fix responsive layout overflow and compact navigation alignment](https://github.com/stappmus/Omarchy-Spotify/issues/47) | Open | Implement through #48; test narrow widths, scaling and keyboard access after search changes, package 5. |
| [#51: Likes not being displayed.](https://github.com/stappmus/Omarchy-Spotify/issues/51) | Open | Diagnose row-specific visibility/state first: bar likes work according to follow-up. Separate row-action fix from #26; package 4. |
| [#52: Shared client ID causes API rate-limit errors independent of per-user usage](https://github.com/stappmus/Omarchy-Spotify/issues/52) | Open | Primary shared-quota tracker. #64/#66/#49 reduce mishandling/work; corrected #58 provides an advanced alternative with limitations; package 1. |
| [#53: Bar widget stays blank on Spotify Connect activation race; duplicate IpcHandler on multi-monitor bars](https://github.com/stappmus/Omarchy-Spotify/issues/53) | Open | Split into phone-initiated Connect activation diagnosis and single shared IPC owner. #65 covers only local command dispatch; package 3. |
| [#61: Transport controls are dropped after a librespot reconnect (SpircCommand::Play ignored while Not Active)](https://github.com/stappmus/Omarchy-Spotify/issues/61) | Open | #65 repairs inactive local commands; full context/ownership recovery still needs #37 and live tests. Keep unresolved subcases open; package 3. |
| [#62: Bar icon (fa-spotify U+F1BC) renders taller than the rest of the Omarchy bar icons](https://github.com/stappmus/Omarchy-Spotify/issues/62) | Open | Focused visual adjustment after #29. Validate glyph size across font/scale while preserving standard hit target; package 5. |
| [#63: not working after reconnecting maybe needs an update](https://github.com/stappmus/Omarchy-Spotify/issues/63) | Open | Needs current runtime/version and redacted failure classification. Screenshot proves contradictory readiness/error presentation, not root cause; package 2. |
| [#68: Quit omarchy-spotify?](https://github.com/stappmus/Omarchy-Spotify/issues/68) | Open | Package 6: document existing paused-title setting, add explicit local stop with a reliable reopen path; preserve Pause and remote playback. |

### Open PRs

| Item | Snapshot state | Disposition |
| --- | --- | --- |
| [#20: Add settings option to disable artwork download and display](https://github.com/stappmus/Omarchy-Spotify/pull/20) | Open; conflicts; `79f62329` | Changes requested; conflicts. Rebase after shared artwork component, add missing schema/default tests, ensure true text-only layout. Global master switch before #25; package 5. |
| [#25: Add optional spinning vinyl artwork to the mini-player](https://github.com/stappmus/Omarchy-Spotify/pull/25) | Open; conflicts; `a34bf639` | Changes requested; conflicts. Rebase after #20, repair stale version assertion, gate both surfaces and animation by artwork master; package 5. |
| [#26: Fetch the real artist discography, and let the artist page be personalized](https://github.com/stappmus/Omarchy-Spotify/pull/26) | Open; conflicts; `5d7700fb` | Changes requested; conflicts. Split data, customization, and row actions; fix QVariantList pagination; package 4. |
| [#36: Retry artwork downloads after transient network failures](https://github.com/stappmus/Omarchy-Spotify/pull/36) | Open; mergeable; `7f06e7a2` | Candidate with lifecycle validation. Use one retrying image component, suspend inactive/off retries, verify recycled rows; before rebased #20, package 5. |
| [#37: Restore playback state after session reconnects](https://github.com/stappmus/Omarchy-Spotify/pull/37) | Draft; mergeable; `ea6939bc` | Draft; hold. Exact shuffled queue restoration and dependency-owned snapshot contract are incomplete; package 3. |
| [#40: Wake idle local playback instead of sending NO_ACTIVE_DEVICE](https://github.com/stappmus/Omarchy-Spotify/pull/40) | Open; mergeable; `699fc8fb` | Revise. Restrict recovery to still-current playback intent, preserve output selection, and bound callback/retry lifetime; package 3. |
| [#44: Restore the bindings.lua instructions for Super+Shift+M](https://github.com/stappmus/Omarchy-Spotify/pull/44) | Open; mergeable; `63842cc1` | Small candidate. Validate the documented binding and manifest copy; no automatic personal-dotfile edits. |
| [#46: Add a setting to hide the lyrics button](https://github.com/stappmus/Omarchy-Spotify/pull/46) | Open; mergeable; `59784a54` | Candidate after settings/layout integration. Keep buttons, shortcut handlers and help consistent; default On, package 5. |
| [#48: Fix responsive layout at narrow panel widths](https://github.com/stappmus/Omarchy-Spotify/pull/48) | Open; mergeable; `37f3ca5e` | Candidate with combined visual QA. Integrate search error row and later artist/text-only changes; package 5. |
| [#49: Cache Spotify search results by type](https://github.com/stappmus/Omarchy-Spotify/pull/49) | Open; mergeable; `e033ff92` | Candidate with revisions. Add actual pagination cancellation, pending-query deduplication, keyboard Retry, and service race tests; package 1. |
| [#50: feat: built-in synced lyrics and album art zoom](https://github.com/stappmus/Omarchy-Spotify/pull/50) | Open; mergeable; `14fb6d80` | Split and defer default replacement. Optional built-in lyrics plus separate zoom; preserve Omasing, add lifecycle/timeouts, finish live tests; package 7. |
| [#54: Keep nearby Connect speakers when Avahi resolve is slow](https://github.com/stappmus/Omarchy-Spotify/pull/54) | Open; mergeable; `7372dcd7` | Revise before merge. Decode TimeoutExpired.stdout bytes; prove partial-result retention with a real subprocess test; package 3. |
| [#55: Keep the last played song loaded for Play](https://github.com/stappmus/Omarchy-Spotify/pull/55) | Open; mergeable; `6c48da66` | Revise. Throttle empty history and failures, isolate account generations, distinguish recent-track restart from exact resume; package 6. |
| [#56: Add a fixed bar width setting](https://github.com/stappmus/Omarchy-Spotify/pull/56) | Open; mergeable; `c2c690e7` | Candidate. Default Off, disable with unlimited cap, preserve icon-only sizing and test scaling; package 5. |
| [#57: Keep in-panel popups opaque on translucent themes](https://github.com/stappmus/Omarchy-Spotify/pull/57) | Open; mergeable; `ac00fb47` | Small candidate. Validate readable in-panel surfaces on transparent/light/dark themes without altering external popup blur. |
| [#58: feat: allow per-user Spotify client ID to opt out of shared rate limits](https://github.com/stappmus/Omarchy-Spotify/pull/58) | Open; mergeable; `687c82e8` | Revise before merge. Atomic identity transition, immutable auth operation identity, token/keyring isolation and accurate quota guidance; package 1. |
| [#59: Add keyboard-first Spotify queue launcher](https://github.com/stappmus/Omarchy-Spotify/pull/59) | Open; mergeable; `9c644f2b` | Revise after #49/#53. Isolate launcher search, replace blind Next burst, respect selected/Sonos target and artwork master; package 7. |
| [#64: Honor server Retry-After delays above 30 seconds](https://github.com/stappmus/Omarchy-Spotify/pull/64) | Open; mergeable; `d1b6b756` | First patch candidate. Full server cooldown, safe timer range and transport boundary tests; package 1. |
| [#65: Activate the local receiver before backend transport controls](https://github.com/stappmus/Omarchy-Spotify/pull/65) | Open; mergeable; `c9318a28` | Backend patch candidate. Review FIFO and ownership semantics, smoke-test MPRIS/socket, and release an attested binary; package 3. |
| [#66: Explain search deadlines blocked by Spotify cooldowns](https://github.com/stappmus/Omarchy-Spotify/pull/66) | Open; mergeable; `190d158d` | First patch candidate with #64. Accurate queued-cooldown deadline message; retain sent-request timeout semantics; package 1. |
| [#67: Report playback OAuth port conflicts before authorization](https://github.com/stappmus/Omarchy-Spotify/pull/67) | Draft; mergeable; `da29a91f` | Draft; dependency-blocked. Adopt approved retained-listener change from stappmus/librespot#1 and replace temporary OAuth fork override; package 2. |

### Closed issues and retained behavior

| Item | Snapshot state | Disposition |
| --- | --- | --- |
| [#1: Spotify Premium](https://github.com/stappmus/Omarchy-Spotify/issues/1) | Closed | Closed requirement question. Preserve clear Premium requirement; package 2 adds runtime enforcement. |
| [#4: Keyboard shortcuts for opening mini/full player?](https://github.com/stappmus/Omarchy-Spotify/issues/4) | Closed | Closed shortcut request, with a remaining wiring gap tracked by #43/#44; packages 3 and 5. |
| [#5: Volume and Playback slider visual position resets to original position after changing volume or playback](https://github.com/stappmus/Omarchy-Spotify/issues/5) | Closed | Closed slider fix. Regression gate for optimistic position and volume with local and remote playback. |
| [#6: The "Like" button should also be included in the mini widget and the now-playing bar.](https://github.com/stappmus/Omarchy-Spotify/issues/6) | Closed | Closed as implemented. Preserve current-track save controls; investigate the distinct row problem in #51. |
| [#8: Backend socket never connects after fresh install :  track playback falls back to Web API and takes ~10s](https://github.com/stappmus/Omarchy-Spotify/issues/8) | Closed | Closed socket retry fix. Fresh-install socket connection remains a release smoke test. |
| [#9: Multiple errors](https://github.com/stappmus/Omarchy-Spotify/issues/9) | Closed | Closed initial throttling/playlist-state fix. Follow-on work is #52/#64/#66 and package 1. |
| [#11: Not playing songs](https://github.com/stappmus/Omarchy-Spotify/issues/11) | Closed | Closed playback-setup report. Preserve two-stage authorization guidance and credential migration. |
| [#13: Skip/Ban button feature request](https://github.com/stappmus/Omarchy-Spotify/issues/13) | Closed | Closed unsupported recommendation-feedback request. Deferred unless a supported API becomes available; package 7. |
| [#14: Playlist does not load all songs](https://github.com/stappmus/Omarchy-Spotify/issues/14) | Closed | Closed sidebar playlist pagination fix. Protect browsing beyond 200; address remaining caps in other paths in package 4. |
| [#15: Sort from new to old date added feature request](https://github.com/stappmus/Omarchy-Spotify/issues/15) | Closed | Closed date-sort fix. Preserve newest/oldest order and unknown-date placement. |
| [#18: session state stored in shell.json](https://github.com/stappmus/Omarchy-Spotify/issues/18) | Closed | Closed XDG-state migration. New transient state belongs outside shell.json; preserve migration and uninstall. |
| [#19: api disconnects and music stops.](https://github.com/stappmus/Omarchy-Spotify/issues/19) | Closed | Closed session-supervisor fix. Preserve it; #61 and draft #37 cover incomplete ownership/context recovery. |
| [#23: Playlist playback ignores the displayed sort order](https://github.com/stappmus/Omarchy-Spotify/issues/23) | Closed | Closed displayed-order playback fix. Preserve native Original context, duplicate occurrences, and explicit custom-play batch limits. |
| [#24: "Stop Music" Button](https://github.com/stappmus/Omarchy-Spotify/issues/24) | Closed | Closed bar-visibility request. Existing showPausedTrack and title/artist preferences handle hiding; actual shutdown is distinct #68/package 6. |
| [#27: High CPU usage after latest update](https://github.com/stappmus/Omarchy-Spotify/issues/27) | Closed | Closed source-build CPU report. Explain verification/build stages, preserve attested binary path, benchmark playback separately; release gates. |
| [#33: Install command???](https://github.com/stappmus/Omarchy-Spotify/issues/33) | Closed | Closed README install-command placement. Keep install entry point prominent. |
| [#34: build-backend.sh pins --source-digest to HEAD, so attested release never verifies when main is ahead of the version tag](https://github.com/stappmus/Omarchy-Spotify/issues/34) | Closed | Closed tag-digest attestation fix. Guard UI-only updates, backend-source changes and clean provenance rules in release tests. |
| [#35: [Bug] Spotify doesn't remember playlist state after closing - have to click "Show more" every time](https://github.com/stappmus/Omarchy-Spotify/issues/35) | Closed | Closed playlist depth/scroll restoration. Preserve sidebar and detail entry paths during pagination work. |
| [#60: Transport controls are dropped after a librespot reconnect (SpircCommand::Play ignored while Not Active)](https://github.com/stappmus/Omarchy-Spotify/issues/60) | Closed | Closed duplicate. All remaining investigation and closure evidence belongs with #61. |

### Merged and closed PR history

| Item | Snapshot state | Disposition |
| --- | --- | --- |
| [#2: Use theme accent for bar icon while playing](https://github.com/stappmus/Omarchy-Spotify/pull/2) | Merged | Merged. Preserve theme-accent playback state in all bar changes. |
| [#3: Add configurable artist and scrolling text to Spotify bar](https://github.com/stappmus/Omarchy-Spotify/pull/3) | Merged | Merged. Preserve independent title/artist settings, scrolling and speed normalization. |
| [#7: Build plugin backend outside the plugin directory to stop hot-reload crashes](https://github.com/stappmus/Omarchy-Spotify/pull/7) | Merged | Merged. Keep all Cargo/build output outside the registered plugin directory. |
| [#10: Add a Quit action to the mini player](https://github.com/stappmus/Omarchy-Spotify/pull/10) | Closed, unmerged | Closed without merge. Reuse the discussion, not the rejected popup-footer placement; package 6. |
| [#12: Expose Spotify volume controls over shell IPC](https://github.com/stappmus/Omarchy-Spotify/pull/12) | Merged | Merged. Preserve existing volume IPC names and step behavior while fixing single ownership in #53. |
| [#17: Fix bar label clipping and make the bar text width adjustable](https://github.com/stappmus/Omarchy-Spotify/pull/17) | Merged | Merged. Preserve clipping fix and width normalization; validate interactions with #56 and #62. |
| [#21: Fix Spotify widget colors on transparent bar](https://github.com/stappmus/Omarchy-Spotify/pull/21) | Merged | Merged. Preserve contrast-aware bar text on transparent themes. |
| [#22: Improve Spotify search reliability and navigation](https://github.com/stappmus/Omarchy-Spotify/pull/22) | Closed, unmerged | Closed without merge after requested split. #38 is merged, #49 is open; navigation and filter pagination remain separately planned in packages 1 and 4. |
| [#29: Align Spotify controls with the Omarchy icon grid](https://github.com/stappmus/Omarchy-Spotify/pull/29) | Merged | Merged. Preserve shared transport targets and optical layout; #62 is a separate remaining glyph-size issue. |
| [#30: Keep paused Spotify sessions advertised and resumable](https://github.com/stappmus/Omarchy-Spotify/pull/30) | Merged | Merged. Preserve paused session metadata and resumability; do not undo to implement #68. |
| [#31: Apply volume live while dragging the slider](https://github.com/stappmus/Omarchy-Spotify/pull/31) | Merged | Merged. Preserve coalesced live volume, final-value delivery and release-only seek. |
| [#32: Make Omarchy Spotify fully uninstallable](https://github.com/stappmus/Omarchy-Spotify/pull/32) | Merged | Merged. Expand complete-uninstall inventory for any new owned files, launchers, settings, or credential identities. |
| [#38: Harden Spotify API request transport](https://github.com/stappmus/Omarchy-Spotify/pull/38) | Merged | Merged into current main, absent from installed checkout. Use as baseline; do not rewrite priority/timeout machinery. |
