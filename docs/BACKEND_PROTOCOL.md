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
and a redacted error string. When the error needs dedicated UI, the snapshot
also includes an optional stable `error_code`; `audio_key_unavailable` means
Spotify refused the key required for local playback.

Version 1 commands are:

- `hello`, `ping`, and `get_state`;
- `activate`, `play`, `pause`, `toggle`, `stop`, `next`, and `previous`;
- `seek` with `position_ms` and `set_volume` with a value from 0 through 65535;
- `set_shuffle` and `set_repeat` (`off`, `context`, or `track`);
- `add_to_queue` with a Spotify URI; and
- `load` with either `context_uri` or `uris`, optional `offset_uri` or
  `offset_index`, optional `position_ms`, and `play` (true by default).

Adding an optional field or command is backward-compatible. Removing or
renaming a field, changing its meaning, or changing framing requires a new
protocol version. The Quickshell service uses this socket to start local playback (`load`)
and add to the local queue. Clients must retain MPRIS/Web API fallback
behavior when the socket is absent or reports an unsupported version.
