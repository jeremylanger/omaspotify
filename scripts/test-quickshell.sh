#!/usr/bin/env bash
set -euo pipefail
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
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
