# Backend protocol

The plugin backend listens at
`$XDG_RUNTIME_DIR/omaspotify/backend.sock`. The socket and every message
are private to the current user. Transport is UTF-8 JSON, one object per line.

Protocol version 1 requests have a caller-chosen integer id and a flattened
command:

```json
{"v":1,"id":7,"command":"pause"}
```

A successful response keeps that id:

```json
{"type":"response","v":1,"id":7,"ok":true,"result":{}}
```

Failures set `ok` to false and return a stable machine-readable error code plus
a human-readable message. An unsupported protocol version is rejected rather
than guessed.

The server pushes a complete snapshot on connection and whenever playback
state changes:

```json
{"type":"event","v":1,"event":"state_changed","state":{"lifecycle":"ready"}}
```

The abbreviated example omits the remaining state fields. A real snapshot also
contains backend and protocol versions, session status, current client,
playback status, track metadata, position in milliseconds, native 16-bit
Connect volume, shuffle/repeat state, a monotonically increasing generation,
and a redacted error string. When the account's Connect session is held by
some device, the snapshot also carries `session_holder`: `this computer`, or
the other device's name and kind as Spotify lists it (for example
`Kitchen (speaker, Sonos One)`); it is omitted while no device is active.
Spotify allows one active device per account, so a song that stops with
"device became inactive" was taken over by the device named here, and the
backend logs the same line. When the error needs dedicated UI, the snapshot
also includes an optional stable `error_code`; `audio_key_unavailable` means
Spotify refused the key required for local playback.

Version 1 commands are:

- `hello`, `ping`, and `get_state`;
- `activate`, `play`, `pause`, `toggle`, `stop`, `next`, and `previous`;
- `seek` with `position_ms` and `set_volume` with a value from 0 through 65535;
- `set_shuffle` and `set_repeat` (`off`, `context`, or `track`);
- `add_to_queue` with a Spotify URI;
- `load` with either `context_uri` or `uris`, optional `offset_uri` or
  `offset_index`, optional `position_ms`, and `play` (true by default); and
- `playlist_items` with a `spotify:playlist:` `uri`, optional `offset`
  (0 by default) and `limit` (100 by default, at most 500; 0 returns the
  version and length only). It reads the list through the Connect session,
  not the Web API, so it reaches playlists a personal Web API app is refused
  and spends no developer quota. The result is `{ snapshot_id, name, owner,
  images, total, offset, limit, items, next }`: `snapshot_id` is the Web
  API's spelling of the same revision, `items` are shaped like
  `GET /playlists/{id}/items` rows (`added_at` and an `item` that is `null`
  for a row Spotify has no track metadata for, such as an episode or a local
  file), and `next` is the offset of the following page or `null`. The
  answer is written when the fetch completes, so other commands on the same
  connection are not held behind it; replies are matched by `id`, not by
  order. Errors: `invalid_request`, `engine_reconnecting`,
  `playlist_unavailable`, `playlist_timeout`.

Adding an optional field or command is backward-compatible. Removing or
renaming a field, changing its meaning, or changing framing requires a new
protocol version. The Quickshell service uses this socket to start local playback (`load`)
and add to the local queue. Clients must retain MPRIS/Web API fallback
behavior when the socket is absent or reports an unsupported version.
