# OmaSpotify

**Spotify in Quickshell—not Chromium.**

OmaSpotify brings the Spotify experience you already know into a fast,
beautiful Omarchy plugin. It uses about **60 MB of RAM** instead of roughly
**950 MB** for the Spotify desktop client, follows your active Omarchy theme,
and keeps your music close with an integrated mini player.

Pair it with **Omasing** and lyrics for the song you are playing are fetched
for you, ready when you want them.

## Install

```bash
omarchy plugin add https://github.com/jeremylanger/omaspotify.git --enable
```

Requires Omarchy 4 and a personal Spotify Premium account.

## Why you will love it

- **Lightweight by design.** Enjoy your music without keeping a browser-sized
  desktop client running.
- **Made for Omarchy.** Every color follows your current theme automatically,
  including light themes.
- **Always within reach.** Play, pause, skip, seek, change volume, or open
  lyrics from the mini player in your bar. Your last song stays loaded, so
  Play picks up where you left off even after the player has gone idle.
- **Your full music library.** Search Spotify, browse artists and albums,
  manage playlists and the queue, and move playback between Spotify Connect
  devices.
- **Lyrics with Omasing.** Open the current song in Omasing and let it find the
  right lyrics and playback position automatically.

## Familiar from the first click

The layout is inspired by the Spotify client, so there is almost nothing new
to learn. Your library and playlists live in the sidebar, search stays at the
top, the player stays at the bottom, and artist and album names take you
straight to their pages.

Prefer to keep your hands on the keyboard? The whole app is designed for that
too.

| Shortcut | What it does |
| --- | --- |
| `Ctrl+F` or `/` | Search all of Spotify |
| `Ctrl+F` or `/` again | Toggle current area / all of Spotify |
| `Tab` / `F6` | Move between sidebar, search, the song list, and the player |
| `Arrow keys` | Move to a control; Enter activates |
| `C` | Row actions; arrows or Enter choose |
| `Space` | Play or pause |
| `Ctrl+Left` / `Ctrl+Right` | Previous or next song |
| `Shift+Left` / `Shift+Right` | Seek 10 seconds |
| `Ctrl+Up` / `Ctrl+Down` | Change volume |
| `M` | Mute or restore volume |
| `Ctrl+Shift+A` | Open the current song's artist |
| `Ctrl+Shift+B` | Open the current song's album |
| `Ctrl+/` | See every keyboard shortcut |
| `Ctrl+H` | Hide visible shortcut hints |

The first shortcut, Tab, or opening the player from the keyboard lights
matching controls with the next key. Hold Ctrl, Shift, or Alt to see those
chords; the matching hints remain until you release the held modifiers. While
hints are visible, the header keeps a **Ctrl+H · Hide hints** action in reach.
It turns hints off until you enable them again in Settings.

![Shortcut hints lighting up the sidebar, search and transport on the For you page](docs/screenshots/shortcut-hints.png)

The mini-player takes keyboard focus when it is opened from a shortcut. Use
`Tab` or the arrow keys to select every control, `Enter` to activate buttons,
left/right to adjust a selected slider, and `Esc` to close. The playback
shortcuts above work there too; `Ctrl+S` toggles shuffle, `Ctrl+R` cycles
repeat, `Ctrl+Shift+L` opens lyrics, `Ctrl+Shift+A` and `Ctrl+Shift+B` open the
current artist or album in the full player, and `O` expands the full player.

## See it in action

### Your playlists, instantly familiar

Everything is where you expect it to be—just faster, lighter, and dressed in
your Omarchy theme. Your whole library lives in the sidebar: playlists,
albums, artists and podcasts together, sorted however you like.

![The Ambient Space Soundscapes playlist open in OmaSpotify](docs/screenshots/library-playlist.png)

### Everything from an artist, in one view

Followers and genres, top albums and EPs, the artist's ten biggest songs, every
liked song you already have by them, and who else they sit next to—one page, no
digging.

![The Lane 8 artist page, with top releases, top songs and liked songs side by side](docs/screenshots/artist-page.png)

### What you actually listened to

Spotify keeps your last fifty plays and shows you none of it. OmaSpotify keeps
its own record from the day you install it, so the heatmap fills in as you
listen, and top artists and songs sit underneath it across three ranges.

![The Your listening screen: a day-by-day heatmap above top artists and top songs](docs/screenshots/your-listening.png)

### The song, full size

`E` or `Alt+Shift+N` gives the current track the whole window—artwork, title,
and a live equalizer drawn in your theme's colours. `V` switches between bars,
pixels, scope and matrix. The equalizer listens only to OmaSpotify's own audio
and needs `cava` (`sudo pacman -S cava`).

![The Now playing screen with album artwork above a live equalizer](docs/screenshots/now-playing.png)

### Everything you were just listening to

Recently played, your top songs and artists, and new releases from the artists
you follow—each one a tab away.

![The For you screen listing recently played songs](docs/screenshots/for-you.png)

### A mini player that belongs in your desktop

The essentials are always one click away, without reopening the full app.

![The OmaSpotify mini player over the desktop](docs/screenshots/mini-player.png)

### Lyrics, already matched to the song

One click sends the current track to Omasing, where the lyrics are fetched and
lined up with your playback position—ready to auto-scroll as you listen.

![Omasing showing lyrics for Disappear over the OmaSpotify player](docs/screenshots/omasing-lyrics.png)

## Set it up

To replace Omarchy's existing **Super+Shift+M · Music** binding, add this to
`~/.config/hypr/bindings.lua`:

```lua
  hl.unbind("SUPER + SHIFT + M") -- previously: Music
  o.bind("SUPER + SHIFT + M", "OmaSpotify",
    "omarchy shell -q io.github.jeremylanger.omaspotify.player togglePlayer")
```

Run `hyprctl reload` and check `hyprctl configerrors` after saving. Until the
binding is replaced, Omarchy's stock Music binding stays active and the
Settings choice below has no effect on the shortcut.

In OmaSpotify's Settings, choose whether that shortcut launches Omarchy's
Music app, toggles the full player, or toggles the mini-player. Separate
bindings can call `toggleMiniPlayer` or `toggleFullPlayer` on the same
`io.github.jeremylanger.omaspotify.player` target.

Raise or lower Spotify volume from a keybinding without opening the player:

```bash
omarchy shell -q io.github.jeremylanger.omaspotify.player volumeUp
omarchy shell -q io.github.jeremylanger.omaspotify.player volumeDown
```

Each step is 5%, the same as Ctrl+Up / Ctrl+Down. This changes Spotify's own
volume, including speakers, not the computer's output level.

### Connect your Spotify account

1. Click the Spotify icon in your bar (on the left by default; your layout may
   place it elsewhere).
2. Click **Set up and continue**, or **Continue with Spotify** if playback is
   already installed.
3. Sign in on Spotify's own page in your browser and approve access.
4. To listen on this computer, complete the separate playback authorization
   in your browser. If prompted, choose **Finish playback setup**.

You need a Spotify Premium account. You do not need to create a Spotify
Developer app or enter a client ID, client secret, or password in OmaSpotify.
Account access and playback on this computer use separate authorizations.

Local playback installs an exact-version backend only after its GitHub build
provenance matches this plugin version's tag and the checkout's backend inputs
still match that tagged source. If verification is unavailable, setup builds
the locked Rust source locally instead of executing an unverified download.

## Seeing "Spotify is busy." or slow searches?

The plugin's Spotify Web API client ID is shared by every install worldwide,
and Spotify rate-limits requests **per app**, not per user. When the shared
app is rate-limited you see `Spotify is busy. Try again in N seconds.` and
searches that stall even though nothing is wrong on your side.

You can use a personal [Spotify Developer app](https://developer.spotify.com/dashboard),
which has a rate limit of its own that nobody else is spending.

1. Create the app, and tick **Web API** under "Which API/SDKs are you planning to
   use?". Nothing else is needed.
2. Add `http://127.0.0.1:8989/login` as the app's redirect URI, exactly.
3. Open **Settings → Personal Spotify app → Setup guide**. The same optional
   guide is offered on the login page and after shared-app quota errors. It
   links to the developer dashboard and can copy the exact Redirect URI. Paste
   the **Client ID**, then choose **Save app**. Never enter the Client Secret.
   Leave the field empty to use the shipped app; malformed IDs cannot be saved.
4. Choose **Authorize** in the guide. Changing the ID clears the current session; stored
   sessions are kept separate per client ID.

**Keep the shipped app authorized as well.** Spotify
[closed several endpoints to apps registered after November 2024](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api),
and a personal app cannot reach an artist's albums, an artist's top songs,
related artists, new releases, or several tracks at once, and it cannot read
playlists that belong to other people. Spotify also leaves its own playlists,
like On Repeat and Your Top Songs, out of your playlist list. The shipped app
predates that change, so the work is split between the two apps:

- **Your app** handles your account and library, playlists you own or
  collaborate on, every change you make, and idle caching.
- **The shipped app** is asked for a closed endpoint after your app is refused
  it, and for Spotify's own playlists. It also reads other people's playlists
  directly, without trying your app first: opening one, loading its further
  pages and checking its version, the candidate playlists track radio looks
  at, and the songs read when you make a followed playlist your own. Your app
  still writes the copy. These reads count against the shipped app's shared
  rate limit.

If you have never signed in with the shipped app, those parts of the artist page
and the Home tab stay empty, Spotify's playlists are missing from your library,
and other people's playlists are read through your app, which Spotify refuses.

This is a power-user option, not a recommendation for everyone. A
development-mode app allows [five authorized users](https://developer.spotify.com/documentation/web-api/concepts/quota-modes),
so it cannot be handed out to the people who install your fork, and it requires
a Premium account. Since
[July 2026](https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates)
a developer account may hold up to 25 client IDs, but the quota is counted per
developer account rather than per ID, so making more of them does not buy more
requests.

Spotify refuses requests in two different ways. A rate limit is a short pause
for one app; you see `Spotify is busy. Try again in N seconds.` A development
quota refusal applies to every app on that developer account and can last for
hours. OmaSpotify shows it as a developer quota message rather than advice to
try again soon. Neither refusal is worked around: OmaSpotify chooses which app
to use from the request itself, never retries a rate-limited or quota-refused
request on the other app, and never switches client IDs for you.

The local Connect authorization remains separate. The personal and shipped apps
have separate request queues, cooldowns, and concurrency limits: a refusal from
the shipped app cannot stall requests through your personal app.
Changing the Client ID in Settings cancels the previous app's requests without
restarting the shell. A different app does not inherit the previous app's delay,
but an app you return to keeps any `Retry-After` it is still serving. Refreshing a
token keeps that app's quota.

Playlists you open are cached on disk (up to 200 loaded rows per page, 16 pages);
Load More continues after the cached rows of a longer playlist.
Reopening draws cached rows immediately. After five minutes, a small
`snapshot_id` check establishes whether the playlist changed; unchanged versions
keep their rows without downloading tracks again. Changed or unknown versions
refresh the visible depth, and explicit reloads always fetch again. A failed
check preserves the visible cache and leaves it stale for the next visit.
For a library-wide cache, open **Playlists → Cache** and turn **Idle caching** on
(or enable “Cache playlist songs while idle” in the plugin settings). Close the
panel to let it work: it fills first pages before deeper pages, one request at a
time, with at least three seconds between requests. It caches song lists and
the address of each list's cover, not audio or artwork; accessible lists resume
after restart. Spotify version checks skip unchanged lists; changed lists need a
new download because Spotify has no incremental song-diff endpoint. A held list
is checked once a day, or sooner when your playlist list names a new version. A
rate limit pauses warming for at least five minutes, a spent daily quota for six
hours, or for as long as Spotify's `Retry-After` asks when that is longer;
personal apps do not fall back to the shared app during warming. A list Spotify
will not show your app is left alone for a week, restarts included.

While playback on this computer is running, playlists are read through it
instead of the Web API: its Spotify session lists every playlist you can see,
including the ones a personal app is refused, and nothing it reads counts
against a developer quota. Set **Sleep empty local receiver** to 0 to keep it
running; it is then started when you open the panel and whenever idle caching
has work, so the whole library can be cached locally without touching the
Web API. The Web API is used only while it is off or for a list it cannot read.
After a restart it looks up your account by itself, without the panel being
opened.

The separate library cache holds up to 512 playlists, 50,000 rows in total,
10,000 per playlist and 32 MiB of estimated data. Rows are stored compactly: in
testing with realistic Spotify playlists, about 50,000 songs fit in 32 MiB when
albums and artists repeat within a playlist, and about 40,000 when every song is
from a different album. At the budget it stops adding playlists rather than
evicting and redownloading the library, but it keeps checking the ones it holds.
Longer lists still have Load More. Cache data expires after seven days without a
version check and is scoped to the signed-in account; logging out removes it.
Spotify hides the songs of playlists you neither own nor collaborate on, so
those are not cached.

This option is off by default. While it is on, playlists you open are added to
the library cache too. Turning it off stops downloading and updating; song lists
already saved stay readable until they are a week old or you log out.

### If playback setup fails

If the verified backend release is unavailable, the fallback build needs
Rust and Cargo. They are not installed by the plugin. On Omarchy, install
Rustup (which supplies Rust and Cargo), then rerun setup from the plugin
directory so Rustup uses the version in `rust-toolchain.toml`:

```bash
omarchy pkg add rustup
cd "$HOME/.config/omarchy/plugins/io.github.jeremylanger.omaspotify"
./scripts/setup.sh
```

If you already have a working Rustup installation, skip the first command.
The first build downloads the toolchain and dependencies and may take several
minutes. After it succeeds, restart the shell with `omarchy restart shell`,
open OmaSpotify, and continue signing in.

**Playback setup could not be completed** is a general setup error, not a
Spotify password error. Running `./scripts/setup.sh` in a terminal shows the
underlying error. Missing Rust/Cargo is one possible cause; see the
[technical prerequisites](docs/TECHNICAL.md) for the other requirements.

## Remove it completely

Run the bundled uninstaller from outside the plugin directory:

```bash
cd "$HOME" && "$HOME/.config/omarchy/plugins/io.github.jeremylanger.omaspotify/scripts/uninstall.sh"
```

It disables and removes the plugin, stops and removes its user service,
restarts the shell, and deletes all plugin-owned configuration, cached audio,
backend build files, installed binaries, playback state, runtime sockets, old
configuration backups, and matching GNOME Keyring entries.

If you prefer to inspect and paste the main steps individually:

```bash
plugin_dir="$HOME/.config/omarchy/plugins/io.github.jeremylanger.omaspotify"
cd "$HOME"
omarchy plugin disable io.github.jeremylanger.omaspotify 2>/dev/null || true
"$plugin_dir/scripts/remove-runtime.sh" --purge
omarchy plugin remove io.github.jeremylanger.omaspotify --yes
omarchy restart shell
```

The cleanup deliberately leaves unrelated software alone. A source checkout
outside Omarchy's plugin directory and separate plugins such as Omasing remain
in place.

Very old installation instructions may also have added a custom Hyprland
shortcut. The uninstaller reports any such references without rewriting your
personal configuration. Check both the live config and, when applicable, its
chezmoi source:

```bash
rg -in 'quickshell\.spotify|omaspotify' \
  "$HOME/.config/hypr" "$HOME/.local/share/chezmoi" 2>/dev/null
```

Remove only the matching custom lines, apply the dotfiles change, and run
`hyprctl reload`. Omarchy's stock **Super+Shift+M** Music shortcut will then be
used again.

## More music, less app

- Discover Weekly, Release Radar, Daily Mixes, daylist, and more in **Discover**.
- Browse Liked Songs, saved albums, followed artists, podcasts, and books.
- Create playlists, add songs, reorder tracks, and turn followed playlists
  into your own editable copies when Spotify makes their contents available.
- Build a queue, start track radio, use shuffle and repeat, or set a sleep timer.
- Listen on this computer or switch to another Spotify Connect speaker or player.
- Choose the mini-player or full player independently for the bar icon and
  keyboard shortcut, use optional spinning vinyl artwork in the mini-player,
  show the title, artist, or both, and softly scroll overflowing text at an
  adjustable speed.
- Choose up to 320 kbps for local playback.

Your Spotify password is entered only on Spotify's own page. OmaSpotify
stores your saved session in GNOME Keyring and clears it when you log out.

Want the details? Read the [technical notes](docs/TECHNICAL.md) or see the
[memory benchmark](docs/BENCHMARK.md).

OmaSpotify is an independent project and is not affiliated with Spotify.
Spotify is a trademark of Spotify AB.

Licensed under the [MIT License](LICENSE).
