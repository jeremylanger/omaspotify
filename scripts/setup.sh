#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
force_config=0
skip_backend_build=${OMASPOTIFY_SKIP_BACKEND_BUILD:-0}
device_name="OmaSpotify"

usage() {
  cat <<'EOF'
Usage: scripts/setup.sh [--skip-backend-build] [--force-config] [--device-name NAME]

Verify or build the plugin-owned playback backend and install its user unit.
The unit is not enabled at login.
EOF
}

while (( $# > 0 )); do
  case $1 in
    --force-config)
      force_config=1
      shift
      ;;
    --skip-backend-build)
      skip_backend_build=1
      shift
      ;;
    --device-name)
      [[ $# -ge 2 ]] || { echo "setup.sh: --device-name requires a value" >&2; exit 2; }
      device_name=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "setup.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command_name in secret-tool openssl socat xdg-open systemctl awk cmp install python3 avahi-browse sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "setup.sh: required Omarchy base command is missing: $command_name" >&2
    exit 1
  }
done

"$source_root/scripts/spotify-connect-device.py" self-test >/dev/null || {
  echo "setup.sh: the local Spotify Connect encryption helper failed its self-test" >&2
  exit 1
}

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
config_dir="$config_root/omaspotify"
config_file="$config_dir/playback.conf"
unit_dir="$config_root/systemd/user"
backend_unit_file="$unit_dir/omaspotify.service"

backend_binary=${OMASPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omaspotify"}/omaspotify-backend
runtime_dir=$(dirname -- "$backend_binary")
backend_source_id_file="$runtime_dir/backend-source.sha256"
backend_binary_hash_file="$runtime_dir/backend-binary.sha256"
backend_ready=0
backend_changed=0
unit_changed=0

backend_install_is_current() {
  local current_source_id expected_source_id expected_binary_hash actual_binary_hash

  [[ -x $backend_binary && -s $backend_source_id_file \
    && -s $backend_binary_hash_file ]] || return 1
  current_source_id=$("$source_root/scripts/backend-source-id.sh") || return 1
  expected_source_id=$(<"$backend_source_id_file")
  [[ $expected_source_id == "$current_source_id" ]] || return 1
  expected_binary_hash=$(<"$backend_binary_hash_file")
  [[ $expected_binary_hash =~ ^[0-9a-f]{64}$ ]] || return 1
  actual_binary_hash=$(sha256sum -- "$backend_binary") || return 1
  [[ ${actual_binary_hash%% *} == "$expected_binary_hash" ]]
}

backend_was_active=0
if systemctl --user is-active --quiet omaspotify.service 2>/dev/null; then
  backend_was_active=1
fi

if backend_install_is_current; then
  backend_ready=1
elif (( ! skip_backend_build )); then
  if "$source_root/scripts/build-backend.sh"; then
    backend_ready=1
    backend_changed=1
  fi
fi

if (( ! backend_ready )); then
  echo "setup.sh: the plugin backend is not available" >&2
  echo "Install Rust so the backend can be built from source." >&2
  exit 30
fi

install -d -m 700 -- "$config_dir"
install -d -m 700 -- "$unit_dir"

if [[ -f $config_file && $force_config -eq 0 ]]; then
  echo "Keeping existing configuration: $config_file"
else
  if [[ -f $config_file ]]; then
    backup="${config_file}.bak.$(date -u +%Y%m%d%H%M%S)"
    cp -p -- "$config_file" "$backup"
    echo "Backed up previous configuration to: $backup"
  fi
  install -m 600 -- "$source_root/config/playback.conf" "$config_file"
fi

printf '%s\n' "$device_name" | "$source_root/scripts/configure-playback.sh"
if (( backend_ready )); then
  if [[ ! -f $backend_unit_file ]] \
      || ! cmp -s -- "$source_root/systemd/omaspotify.service" "$backend_unit_file"; then
    unit_changed=1
  fi
  install -m 644 -- "$source_root/systemd/omaspotify.service" "$backend_unit_file"
fi
systemctl --user daemon-reload

if (( backend_ready && backend_was_active && (backend_changed || unit_changed) )); then
  systemctl --user restart omaspotify.service
fi

unit_state=$(systemctl --user is-enabled omaspotify.service 2>/dev/null || true)
if [[ $unit_state == "enabled" || $unit_state == "enabled-runtime" ]]; then
  echo "Warning: omaspotify.service was already enabled at login." >&2
  echo "For on-demand behavior, run: systemctl --user disable omaspotify.service" >&2
fi

if (( backend_ready )); then
  echo "Installed plugin playback unit: $backend_unit_file"
fi
echo "Installed private config: $config_file"
echo "Playback remains stopped and will be started on demand by the plugin."
