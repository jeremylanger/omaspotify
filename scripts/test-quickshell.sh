#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
# Every stage gets a runtime dir of its own. With the host's, a Service under
# test finds the developer's live backend socket and reads playlists through
# it, and then the Web API queue the checks inspect is empty.
mkdir -p "$test_root/runtime"
export XDG_RUNTIME_DIR="$test_root/runtime"
cp "$source_root/"{AuthManager.qml,Api.js,OAuth.js} "$test_root/"
sed 's|import "../.." as Plugin|import "." as Plugin|' \
  "$source_root/tests/integration/AuthIdentity.qml" > "$test_root/shell.qml"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen timeout 15s \
  qs --no-color -p "$test_root" > "$test_root/output" 2>&1 || {
  cat "$test_root/output"
  exit 1
}
rg -q AUTH_IDENTITY_PASS "$test_root/output" || {
  cat "$test_root/output"
  exit 1
}
echo 'Quickshell authorization integration passed.'

mkdir -p "$test_root/app/plugin" "$test_root/state"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/app/plugin/"
cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_root/app/"
cp "$source_root/tests/integration/AppSmoke.qml" "$test_root/app/shell.qml"
if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  # Service/authentication tests still use real Quickshell without a compositor.
  sed -i '/Plugin.Panel {/d; /Plugin.BarWidget {/d; /panel.primaryNavigationItems()/,+1d' "$test_root/app/shell.qml"
  app_platform=offscreen
else
  app_platform=wayland
fi
env QT_QPA_PLATFORM="$app_platform" QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/app-output" 2>&1 || {
  cat "$test_root/app-output"
  exit 1
}
rg -q APP_SMOKE_PASS "$test_root/app-output" || {
  cat "$test_root/app-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/app-output"; then
  exit 1
fi
echo 'Quickshell app smoke test passed.'

cp "$source_root/tests/integration/ClientIdentity.qml" "$test_root/app/shell.qml"
# The identity fixture uses synthetic access tokens; its startup lookup must
# never read the user's keyring or initiate a real token refresh.
mkdir -p "$test_root/identity-bin"
printf '#!/bin/sh\nexit 1\n' > "$test_root/identity-bin/secret-tool"
chmod +x "$test_root/identity-bin/secret-tool"
env PATH="$test_root/identity-bin:$PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/identity-output" 2>&1 || {
  cat "$test_root/identity-output"
  exit 1
}
rg -q CLIENT_IDENTITY_PASS "$test_root/identity-output" || {
  cat "$test_root/identity-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/identity-output"; then
  exit 1
fi
echo 'Quickshell Settings client identity checks passed.'

cp "$source_root/tests/integration/PlaylistVersions.qml" "$test_root/app/shell.qml"
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/versions-output" 2>&1 || {
  cat "$test_root/versions-output"
  exit 1
}
rg -q PLAYLIST_VERSIONS_PASS "$test_root/versions-output" || {
  cat "$test_root/versions-output"
  exit 1
}
echo 'Quickshell playlist version checks passed.'

cp "$source_root/tests/integration/PlaylistWarming.qml" "$test_root/app/shell.qml"
env PATH="$test_root/identity-bin:$PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/warming-output" 2>&1 || {
  cat "$test_root/warming-output"
  exit 1
}
rg -q PLAYLIST_WARMING_PASS "$test_root/warming-output" || {
  cat "$test_root/warming-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/warming-output"; then
  exit 1
fi
echo 'Quickshell playlist warming checks passed.'

cp "$source_root/tests/integration/PlaylistBootstrap.qml" "$test_root/app/shell.qml"
env PATH="$test_root/identity-bin:$PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/bootstrap-state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/bootstrap-output" 2>&1 || {
  cat "$test_root/bootstrap-output"
  exit 1
}
rg -q PLAYLIST_BOOTSTRAP_PASS "$test_root/bootstrap-output" || {
  cat "$test_root/bootstrap-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/bootstrap-output"; then
  exit 1
fi
echo 'Quickshell playlist cache startup checks passed.'

cp "$source_root/tests/integration/PlaylistCacheLayout.qml" "$test_root/app/shell.qml"
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/cache-layout-output" 2>&1 || {
  cat "$test_root/cache-layout-output"
  exit 1
}
rg -q PLAYLIST_CACHE_LAYOUT_PASS "$test_root/cache-layout-output" || {
  cat "$test_root/cache-layout-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/cache-layout-output"; then
  exit 1
fi
echo 'Quickshell playlist cache layout checks passed.'

cp "$source_root/tests/integration/ClientSetup.qml" "$test_root/app/shell.qml"
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/setup-output" 2>&1 || {
  cat "$test_root/setup-output"
  exit 1
}
rg -q CLIENT_SETUP_PASS "$test_root/setup-output" || {
  cat "$test_root/setup-output"
  exit 1
}
echo 'Quickshell client setup checks passed.'

mkdir -p "$test_root/sonos/plugin/scripts" "$test_root/sonos-state"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/sonos/plugin/"
cp "$source_root/tests/integration/SonosControl.qml" "$test_root/sonos/shell.qml"
# Stands in for the speaker: answers each command after a short pause.
cat > "$test_root/sonos/plugin/scripts/spotify-connect-device.py" <<'HELPER'
#!/bin/sh
read -r device; read -r action; read -r value
sleep 0.2
printf '{"id":"%s","status":"controlled","action":"%s"}\n' "$device" "$action"
HELPER
chmod +x "$test_root/sonos/plugin/scripts/spotify-connect-device.py"
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/sonos-state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/sonos" > "$test_root/sonos-output" 2>&1 || {
  cat "$test_root/sonos-output"
  exit 1
}
rg -q SONOS_CONTROL_PASS "$test_root/sonos-output" || {
  cat "$test_root/sonos-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign' "$test_root/sonos-output"; then
  exit 1
fi
echo 'Quickshell Sonos control test passed.'

mkdir -p "$test_root/local/plugin" "$test_root/local-state" "$test_root/local-runtime/omaspotify"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/local/plugin/"
cp "$source_root/tests/integration/LocalPlayback.qml" "$test_root/local/shell.qml"
# Stands in for the backend socket, in a private runtime dir so the real
# backend can never receive the test's load command. Records every request.
python3 - "$test_root/local-runtime/omaspotify/backend.sock" "$test_root/local-requests" <<'BACKEND' &
import json, socket, sys
server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1])
server.listen(4)
while True:
    connection, _ = server.accept()
    for line in connection.makefile():
        with open(sys.argv[2], "a") as log:
            log.write(line)
        reply = {"type": "response", "id": json.loads(line)["id"], "ok": True, "result": {}}
        connection.sendall((json.dumps(reply) + "\n").encode())
BACKEND
backend_pid=$!
env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/local-state" \
  XDG_RUNTIME_DIR="$test_root/local-runtime" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/local" > "$test_root/local-output" 2>&1 || true
kill "$backend_pid" 2>/dev/null || true
rg -q LOCAL_PLAYBACK_SENT "$test_root/local-output" || {
  cat "$test_root/local-output"
  exit 1
}
rg -q '"command":"load".*"offset_uri":"spotify:track:clicked"' "$test_root/local-requests" || {
  echo 'The clicked song never reached the backend as the offset to start from:' >&2
  cat "$test_root/local-requests" >&2
  exit 1
}
echo 'Quickshell local playback test passed.'

mkdir -p "$test_root/rows/plugin" "$test_root/rows-state" "$test_root/rows-runtime/omaspotify"
cp "$source_root/"*.qml "$source_root/"*.js "$test_root/rows/plugin/"
cp "$source_root/tests/integration/PlaylistBackendRows.qml" "$test_root/rows/shell.qml"
# Stands in for the backend socket and answers playlist_items like the real
# one: a two-row page with a cursor for one list, a refusal for the other.
python3 - "$test_root/rows-runtime/omaspotify/backend.sock" <<'BACKEND' &
import json, socket, sys
server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1])
server.listen(4)
song = {"type": "track", "id": "s1", "uri": "spotify:track:s1", "name": "Song One",
        "duration_ms": 1000, "explicit": False, "track_number": 1, "disc_number": 1,
        "is_local": False, "external_urls": {"spotify": "https://open.spotify.com/track/s1"},
        "artists": [{"type": "artist", "id": "a1", "uri": "spotify:artist:a1", "name": "Artist"}],
        "album": {"type": "album", "album_type": "album", "id": "al1", "uri": "spotify:album:al1",
                  "name": "Album", "release_date": "2020-01-01", "images": [], "artists": []}}
while True:
    connection, _ = server.accept()
    for line in connection.makefile():
        request = json.loads(line)
        reply = {"type": "response", "v": 1, "id": request["id"], "ok": True, "result": {}}
        if request.get("command") == "playlist_items":
            if request["uri"].endswith(":refused"):
                reply = {"type": "response", "v": 1, "id": request["id"], "ok": False,
                         "error": {"code": "playlist_unavailable", "message": "no such list"}}
            else:
                reply["result"] = {"snapshot_id": "AAAAAnRld", "name": "Foreign", "owner": "someone-else",
                                   "images": [], "total": 3, "offset": 0, "limit": 2,
                                   "items": [{"added_at": "2024-01-01T00:00:00Z", "item": song},
                                             {"added_at": "", "item": None}],
                                   "next": 2}
        connection.sendall((json.dumps(reply) + "\n").encode())
BACKEND
rows_backend_pid=$!
env PATH="$test_root/identity-bin:$PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/rows-state" \
  XDG_RUNTIME_DIR="$test_root/rows-runtime" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/rows" > "$test_root/rows-output" 2>&1 || true
kill "$rows_backend_pid" 2>/dev/null || true
rg -q PLAYLIST_BACKEND_ROWS_PASS "$test_root/rows-output" || {
  cat "$test_root/rows-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign' "$test_root/rows-output"; then
  exit 1
fi
echo 'Quickshell playlist rows through the local player passed.'

cp "$source_root/tests/integration/PlaybackDispatch.qml" "$test_root/app/shell.qml"
mkdir -p "$test_root/dispatch-runtime/omaspotify"
env PATH="$test_root/identity-bin:$PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/dispatch-state" \
  XDG_RUNTIME_DIR="$test_root/dispatch-runtime" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/dispatch-output" 2>&1 || {
  cat "$test_root/dispatch-output"
  exit 1
}
rg -q PLAYBACK_DISPATCH_PASS "$test_root/dispatch-output" || {
  cat "$test_root/dispatch-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign' "$test_root/dispatch-output"; then
  exit 1
fi
echo 'Quickshell playback dispatch checks passed.'

cp "$source_root/tests/integration/PlaylistCatalog.qml" "$test_root/app/shell.qml"
env PATH="$test_root/identity-bin:$PATH" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1 XDG_STATE_HOME="$test_root/catalog-state" \
  timeout 15s dbus-run-session -- qs --no-color -p "$test_root/app" > "$test_root/catalog-output" 2>&1 || {
  cat "$test_root/catalog-output"
  exit 1
}
rg -q PLAYLIST_CATALOG_PASS "$test_root/catalog-output" || {
  cat "$test_root/catalog-output"
  exit 1
}
if rg -i 'ReferenceError|TypeError|binding loop|Cannot assign|Unable to assign|Failed to load configuration' "$test_root/catalog-output"; then
  exit 1
fi
echo 'Quickshell playlist catalog routing checks passed.'
