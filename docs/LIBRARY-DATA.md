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

**Playlists remain the weak spot.** Spotify's top lists cover tracks and artists
only, so a playlist gets a date solely from the 50-play window. Beyond that it
has nothing: no save date, no listening signal. Playlists you have not played in
the last day or two will sink, and no endpoint fixes it.

What still differs, and why it cannot be fixed: the native client knows the exact
last play of everything. We know exact times for 50 plays, a four-week yes/no for
the rest, and nothing at all beyond that. So an album saved three weeks ago and
never played can still outrank one listened to last week, because the save has a
real date and the listen only has "sometime in the last four weeks".

## What this means for sorting

- **Library order** (default) — free, and matches Spotify
- **Alphabetical** — free
- **Recently added** — honest for albums, shows, episodes and tracks. Playlists
  and artists have no date, so they sort last rather than being interleaved
  wrongly
- **Recently played** — ranks whatever appears in the last 50 plays; everything
  else keeps library order beneath. Not a deep history, and cannot be made one
