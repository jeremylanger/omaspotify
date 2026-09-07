# What Spotify actually gives us for the library

Findings from testing every relevant endpoint against a real account, not from
reading documentation. Written so nobody has to repeat this.

Method: pulled the stored refresh token from GNOME Keyring, exchanged it for an
access token, and called endpoints directly. The full endpoint surface came from
Spotify's own OpenAPI document rather than memory — **96 operations, 60 of them
GET**. Everything library-related was checked.

## The short version

| Want | Possible? |
| --- | --- |
| Alphabetical sort | Yes, any type |
| Recently added — albums, shows, episodes, tracks | Yes, `added_at` is returned |
| Recently added — **playlists, artists** | **No.** Neither endpoint returns any timestamp |
| Recently played | Partly. Last **50 plays only**, no deeper history |
| Mixed media in one list | Yes, by merging four endpoints |
| Your Spotify pins | **No.** Not exposed anywhere |
| Default order = your real library order | **Yes** — verified identical to Spotify's own |

## Per endpoint, measured

- `GET /me/playlists` — no timestamp field of any kind. Items carry
  `collaborative, description, external_urls, href, id, images, items, name,
  owner, primary_color, public, snapshot_id, tracks, type, uri`
- `GET /me/albums` — has `added_at` (e.g. `2026-09-06T19:06:40Z`)
- `GET /me/shows` — has `added_at`
- `GET /me/episodes` — has `added_at`
- `GET /me/tracks` — has `added_at`
- `GET /me/audiobooks` — account had none, so untested; same shape as shows
- `GET /me/following?type=artist` — cursor paged, **no timestamp**
- `GET /me/top/artists|tracks` — a real listening ranking, three windows
  (`short_term` ≈ 4 weeks, `medium_term` ≈ 6 months, `long_term` ≈ years).
  Returned live data
- `GET /me/player/recently-played` — `played_at` plus the `context` (the playlist
  or album it came from). **Hard capped at the last 50 plays.** Paging backwards
  with the `before` cursor returns zero items, and an explicit timestamp seven
  days back also returns zero. On the test account those 50 plays spanned two
  days and contained only **four distinct contexts**
- `GET /me/library` — **405 Method Not Allowed**. The path exists but only for
  `PUT`/`DELETE`. `GET /me/library/contains` is a membership check, not a listing

## Pinned items are not reachable

Three independent checks, all negative:

1. Nothing in the 60 GET endpoints exposes pins
2. Spotify's internal API was tried directly. The backend embeds librespot, whose
   `SpClient` speaks the private protocol, so a probe was built to call internal
   paths with real credentials. `/playlist/v2/user/{user}/rootlist` **works** and
   returns 56 KB covering 133 playlists — but decoding every attribute in it
   turns up only playlist decoration (`madeFor.username`, `isAlgotorial`,
   `image_url`, `primary_color`, `autoplay`, `recs.hasArtists`,
   `wrapped.isEligible`). No pin state. Guesses at
   `/your-library/v1/entities` and similar all returned 404
3. librespot ships `pin_request.proto` (`PinRequest`, `MovePinRequest`,
   `PinResponse` with `PINNED`/`NOT_PINNED`), so the feature is real — but its
   package is `spotify.your_library.esperanto.proto`. Esperanto is Spotify's
   **in-client** RPC framework, and librespot implements no pin call at all.
   Pinning appears never to cross the network in a form we can read

So mirroring your Spotify pins is not possible. Local pinning stored in
`session.json` is, and would work — it simply would not match the Spotify app.

## The useful surprise

`GET /me/playlists` returns playlists in **your actual library order**. The first
eight URIs it returned are byte-identical to the first eight in Spotify's own
internal rootlist. So the default sort already reflects the order you arranged in
Spotify, for free, over the public API.

## The internal API as a fallback, and why it is not used

The rootlist probe proves we *could* read playlist add times that the Web API
withholds — `ItemAttributes.timestamp` and `YourLibraryRootlistEntity.add_time`
both exist in the schema. It is deliberately not used:

- It is a private protocol that can change without notice
- `docs/TECHNICAL.md` states the plugin does not duplicate private-protocol work
  beyond what librespot already does for playback
- It would make "recently added" work for playlists while every other sort still
  came from the public API — two sources of truth for one list

The probe was removed after this research. To repeat it, add a hidden subcommand
that calls `session.spclient().get_rootlist(0, Some(200))` and dump the bytes.

## What Spotify's own "Recents" actually is

Compared our sidebar against the native client's Recents list on the same
account. Native's order after its four pinned rows was: Ambient Cinematic
(playlist), The Dark Wizard, Baekdudaegan, Prehistoric Planet, Ashley, Owen,
The Outrun, Everlight — almost entirely **albums**, and their `added_at` dates
line up with that order.

So Spotify's Recents is **last touched, not last played**: saving an album counts
as an interaction. Ranking only on plays left the top of the list filled with
long-standing playlists, which was the visible bug. The sort now takes whichever
is newer, a play time or the save time.

Two gaps remain, both from the 50-play ceiling:

- A playlist played recently but saved long ago can still rank below a freshly
  saved album, because its play may have fallen outside the 50-play window
- Native put Prehistoric Planet above Ashley and Owen despite an older save date,
  so it knows that album was played more recently than we can see

Partly closed since. `GET /me/top/tracks` and `/me/top/artists` with
`time_range=short_term` cover roughly four weeks, far past the 50-play ceiling —
50 tracks spanning 37 distinct albums on the test account. Anything appearing
there was listened to inside that window, so it is dated at the window's far edge:
enough to lift it above older saves, without inventing a precise moment.

Measured effect: "Everlight", saved eleven months ago but in current top tracks,
moved from roughly 40th to 12th. The native client places it 8th.

The rank within those top lists spreads the estimate across the window rather
than stamping everything at one instant. A flat stamp made every top-list item
tie, and ties fall back to library order, which visibly clumped all the artists
together. The rank measures how much something was played rather than when, so
the whole estimated range sits at least a week back — real plays and fresh saves
still lead it.

Two bugs found by comparing against the native client, both worth remembering:

- **Sorting a partly loaded library puts the wrong things on top and hides the
  rest.** The sidebar fetched one page per collection and sorted that. Release
  Radar sits at index 31 of 107 playlists, so it was never loaded at all — it
  appeared only after scrolling paged more in. The sidebar now pages every
  collection to completion before the sort means anything
- **The play times only arrived via the Home tab.** `recentContextPlays` was
  filled by `loadHome()`, so opening straight to the library left the Recents
  sort with no play data whatsoever. The sidebar now fetches recently-played
  itself

**Playlists remain the weak spot.** Spotify's top lists cover tracks and artists
only, so a playlist gets a date solely from the 50-play window. Beyond that it
has nothing: no save date, no listening signal. Playlists you have not played in
the last day or two will sink, and no endpoint fixes it.

What still differs, and why it cannot be fixed: the native client knows the exact
last play of everything. We know exact times for 50 plays, a four-week yes/no for
the rest, and nothing at all beyond that. So an album saved three weeks ago and
never played can still outrank one listened to last week, because the save has a
real date and the listen only has "sometime in the last four weeks".

## Getting past the 50-play ceiling

Spotify will not page back past the last 50 plays, but nothing stops us from
remembering the ones it has already shown us. The app now keeps its own record
in `$XDG_STATE_HOME/omaspotify/plays.json`:

```json
{ "version": 1, "plays": { "spotify:playlist:37i9dQZEVXbmqJmlMor6TM": 1757210160000 } }
```

Each time recently-played is fetched, that batch is folded in — newest time per
context wins, and nothing is ever removed however large the record
grows. Fetches happen when the panel opens and every five minutes
while it is open, so a normal day of use captures far more than 50 plays.

Verified by seeding a play from months ago, restarting, and letting a fresh
fetch of the current four contexts run: the old entry was still there
afterwards. Spotify had forgotten it; we had not.

This does not help on day one — the record starts empty and only holds what
Spotify happened to be showing at the time. It gets better every day it runs,
and it is the only thing that closes the Discover Weekly style gap, where a
playlist is played weekly but falls outside any single 50-play window.

## Dating the rows Spotify refuses to date

Playlists and artists carry no timestamp of their own, which left 372 of 1020
sidebar rows with nothing to sort on. Four sources fixed most of that. All were
measured against the real account.

| Source | What it dates | Coverage |
| --- | --- | --- |
| A played track dates its **album and artists**, not just the playlist it came from | albums, artists | free, from data already fetched |
| Newest **liked song** by an artist | artists | 242 of 265 followed artists |
| Newest **saved album** by an artist | artists | 163 of 265, overlapping the above |
| Last track added to a playlist **you own** | playlists | 46 of 107 playlists |
| Both artist sources combined | artists | **252 of 265** |

Result: **372 undated rows fell to 73** — 60 followed playlists and 13 artists
you follow but have never liked a song or saved an album by. Nothing in the API
reaches those.

Details worth keeping:

- Only playlists **you own** are dated this way. A stranger editing their
  playlist is not you touching it, and following one has no timestamp anywhere.
  Discover Weekly would otherwise read as "edited today" every week
- Playlist tracks come back in the order they were added, so the **last item is
  the newest edit** — one request with `limit=1&offset=total-1`. Checked against
  a full scan of every track's `added_at` on four playlists: exact each time
- `snapshot_id` is not a date. It decodes to a 4-byte revision counter plus a
  hash. It is a perfect **cache key** though, so a playlist is only asked about
  again once it actually changes
- Liked songs come back **newest first**, so after the first pass a watermark
  stops the crawl as soon as it reaches what we already had. The first run reads
  ~105 pages in the background; later runs read one
- `cacheLimit` was silently truncating the sidebar at 200 items, so 448 of 648
  saved albums never loaded at all. Sidebar collections now have their own
  2000-item headroom

## Your liked songs, per artist

Spotify has no "my liked songs by this artist" endpoint. The crawl that already
reads every liked song builds the index as it goes, storing **track ids only**
under each artist. Opening an artist page turns those ids into tracks with a
single `/tracks?ids=` request for most artists.

Measured on the real account: **2,455 artists, 7,057 liked-song links**, and the
whole record file is 407 KB.

A record written before a field existed cannot have that field filled in by an
incremental crawl, so `parsePlayHistoryRecord` drops the watermark whenever the
stored version is older than the current one. The next crawl then reads
everything once. Without this the index silently stalled at 72 artists.

## Why the library used to take so long to appear

Three things, all fixed:

- **Two requests at a time.** `API_MAX_IN_FLIGHT` was 2, so ~190 startup
  requests queued up behind each other. It is now 4 — 6 was tried first and
  turned out to trip Spotify's rate limit
- **Pages were walked one at a time.** Each page waited for the one before it.
  The first reply already carries the `total`, so every remaining page is now
  asked for at once. Dropped pages are retried by offset, because resuming from
  the end would leave a hole in the middle
- **Nothing was kept.** The whole library was refetched on every launch. The
  four sidebar collections are now cached in
  `$XDG_STATE_HOME/omaspotify/library.json` (784 KB) and drawn from disk
  immediately, then quietly replaced when Spotify answers

One surprise while measuring: `/me/albums` reports `total: 598`, but following
`next` to the end yields 648 rows. Pages repeat entries. The app dedupes by uri,
so 598 is the honest count — worth knowing before chasing a "missing pages" bug
that is not there.

## The artist page was slow because it was guessing

It searched Spotify by the artist's *name*, then filtered the results down to
that artist, then searched again when fewer than ten matched — up to **six
sequential round-trips** for a top-songs list. Albums worked the same way.

Spotify answers both questions directly:

- `GET /artists/{id}/top-tracks` — already that artist, already ranked
- `GET /artists/{id}/albums?include_groups=album,single` — their own releases

Measured on the real account: **4,676 ms to 584 ms**.

The other half was contention. Opening a page put its requests behind ~190
background requests from the library crawl. The request queue now has a
**background tier** that yields to anything you asked for.

That was not the whole story either — see the next section.

Also confirmed while testing, since none of it is in the documentation clearly:

- `/artists/{id}/related-artists` still works on this client ID, though it is
  deprecated for newly registered apps
- `/artists/{id}` returns followers, genres and popularity — but **no bio**.
  There is no artist biography anywhere in the Web API
- `/browse/new-releases` works and is what the Home page's new tab uses

## The artist page that took fifteen seconds

The background tier above fixed the queueing, and the page was still taking
15-23 seconds. Splitting the request log into `queue`, `auth` and `wire` is what
found it:

```
GET /artists/3AA28KZ… 14020 ms (queue 13936, auth 0, wire 84)
```

**Wire time 84 ms.** Spotify answered immediately every single time; the
measured wire range across all of this was 27-300 ms. The time was always
`queue`, and `queue` was always a 429 cooldown. One refusal pauses every
request for whatever `Retry-After` says, which was 10-24 seconds.

Two causes, and they are not the same size.

**Not ours.** We use ncspot's client ID, so the rate limit is shared with every
other app built on it. Restarting with the panel closed, waiting for **seven
minutes of complete silence**, then opening the panel still drew a refusal
within seconds. That traffic was not ours. No client-side scheduling fixes a
budget someone else already spent.

**Ours.** A first run makes ~163 requests, and **105 of them are one crawl** —
`/me/tracks` at 50 per page, for 5,250 liked songs. Worse, it restarted from
offset 0 on every launch, because the progress mark was only written when the
crawl finished.

What the app does now:

- The gap between background requests **doubles with every refusal** and stays
  wide for the rest of the run. The budget is shared, so it cannot be known
  ahead of time; backing off and staying backed off avoids oscillating into the
  next refusal
- The liked-songs crawl **resumes from where it stopped**, carrying the newest
  date it had seen so the incremental mark can still advance
- Background work **stands aside for three seconds** after anything you open
- Pages you are waiting on are marked interactive. During a cooldown **one of
  them gets an early try** — one, however many are waiting — in case the refusal
  has slack in it. After being refused itself it waits its turn instead of
  hammering

Measured on a brand-new artist page, against 14-23 seconds before:

| Conditions | Time to the page |
| --- | --- |
| Quiet account | 50-225 ms |
| Nine refusals in seventy seconds | three of six in 76-225 ms, three in 2.2-6.9 s |

Nothing reached fifteen seconds again. The refusals land on background work
now instead of on the page someone opened.

One bug found on the way: an aborted background request never gave its slot
back, because `handle.job` was cleared before the slot was released. Enough
cancellations and the crawl would stall for good.

## Will the play count ever pass 50?

Yes. The 50 is what Spotify hands back **per fetch**, not a ceiling on what we
keep. Each fetch counts only plays newer than a stored watermark, so nothing is
counted twice and nothing already counted is lost. Play something new and the
total goes up and stays up.

It sat at exactly 50 during development only because the record file was being
deleted between test runs, so just one batch had ever been counted.

The one way to lose plays is to listen to more than 50 tracks between fetches —
roughly three hours of music. Fetching used to happen only while the panel was
open, which made that easy to hit. It now also polls every five minutes
**whenever something is playing**, panel open or shut, so the window closes long
before 50 plays can fall off the end.

## Every list, not just the sidebar

The same rebuild-flicker applies anywhere a model is a computed array. Discover
was the visible one: every library page arriving re-ran `discoveryPlaylists`,
replacing every row. That is coalesced now, the same way the sidebar is.

Row artwork across all lists (`MediaRow`) now reads through the on-disk cache
too, so a delegate rebuilt mid-load redraws from a local file instead of
fetching Spotify's CDN again. `MediaCollection` also tells the service what it
is showing, so those images get kept on disk in the first place — the cache grew
from 993 files to 1,021 once the other lists started contributing.

`MediaRow` deliberately still does **not** retain pixmaps, unlike `SidebarRow`:
its lists are unbounded (thousands of tracks), while the sidebar is a fixed
library-sized set.

## Two things that looked fixed and were not

Both were called done after a measurement that did not reproduce the real case.
Worth recording so the same mistake is not repeated.

**Artist pages still stalled for five seconds, intermittently.** The earlier
560 ms figure came from reopening an artist already loaded in the session. A
harness that opened five artists never viewed before found four at ~300 ms and
one at **5,786 ms**. The request log showed why: `/me/library/contains` calls
taking **14 seconds**. Marking the library page fetches as background was not
enough — each page also triggers a saved-state check, and *those* were still at
normal priority. Twenty of them filled all six slots and anything you opened
queued behind. With the checks moved to background too, six cold artists loaded
in **216–439 ms** with no outlier, and only five requests in the whole boot
exceeded two seconds, all of them background `/me/albums`.

**The sidebar still flickered.** Counting rebuilds during a cold load showed
**eleven**, six of them with content, as pages arrived over three seconds.
Replacing the model array destroys and recreates every row, so the artwork
reloaded each time. Three changes: show the first page immediately then wait for
the burst to settle (2 content rebuilds instead of 6), skip rebuilds when there
is nothing on either side, and let the sidebar keep its decoded thumbnails —
they are a small bounded set read from local files, and dropping them was
trading the flicker back for ~18 MiB.

There was also a real bug in the artwork cache: `keepArtwork` returned early
while a fetch was running, so any artwork that arrived during a download was
never marked, never fetched, and never retried. It now marks what is already on
disk regardless, and continues to the next batch when a fetch finishes.

## Memory, measured

Taken on the running shell, which also hosts other plugins, so only the deltas
mean anything:

| Moment | Shell PSS |
| --- | ---: |
| Panel never opened | 422.4 MiB |
| 3 seconds after opening | 591.0 MiB |
| 90 seconds later, whole library and crawl done | 617.2 MiB |

The jump is **+169 MiB in the first three seconds, before any library data
loads** — that is the panel window's own surface and scene graph, not the data.
Everything this app then loads (full library, play record, liked-song index,
993 cached artworks) costs **+26 MiB** on top.

So the thing to optimise, if this ever needs optimising, is the window itself,
not the data model. A like-for-like comparison against `BENCHMARK.md` needs a
shell with no third-party plugins loaded, which has not been done.

Artwork is now kept on disk at `$XDG_CACHE_HOME/omaspotify/art` — 993 files,
7.5 MiB — so a second launch draws from local files instead of the CDN. Row
artwork deliberately does **not** stay in Qt's pixmap cache: coalescing the
sidebar rebuild is what stopped the flicker, and retaining every pixmap on top
of that only cost memory.

## Ties, and why the order used to jump around

Rows sharing a date traded places between renders. Three causes, all fixed:

- The sidebar model was rebuilt on every arriving page, and rebuilding it
  replaces every row. Library pages and the liked-song crawl both arrive in
  bursts, so the rebuild is now coalesced and artwork is no longer discarded
- The comparator returned `0` for equal dates, so the sort had nothing to fall
  back on and the order was whatever that pass happened to produce. It now
  answers with library position, which makes the ordering total
- The listening estimate read `Date.now()` inside a binding, so every redraw
  moved every estimated timestamp. The clock is now frozen when the top lists
  arrive
- Dates were compared at full precision but only shown to the minute, so genuine
  ties and near-ties looked identical. The debug caption now shows seconds and
  the library position, which is the whole key

## What this means for sorting

- **Library order** (default) — free, and matches Spotify
- **Alphabetical** — free
- **Recently added** — honest for albums, shows, episodes and tracks. Playlists
  and artists have no date, so they sort last rather than being interleaved
  wrongly
- **Recently played** — ranks on our own accumulated play record, topped up from
  Spotify's last 50 plays each time the panel opens, plus a four-week estimate
  from the top lists. Everything with no signal at all keeps library order
  beneath
