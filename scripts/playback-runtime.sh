#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:-}
if (( $# != 1 )); then
  echo "Usage: scripts/playback-runtime.sh check|credentials|start|stop|status|unit" >&2
  exit 2
fi

runtime_dir=${OMASPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omaspotify"}
backend_binary="$runtime_dir/omaspotify-backend"
backend_source_id_file="$runtime_dir/backend-source.sha256"
backend_binary_hash_file="$runtime_dir/backend-binary.sha256"
backend_unit=omaspotify.service
config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
installed_backend_unit="$config_root/systemd/user/omaspotify.service"
source_backend_unit="$source_root/systemd/omaspotify.service"
state_root=${XDG_STATE_HOME:-"$HOME/.local/state"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}

unit_exists() {
  systemctl --user cat "$1" >/dev/null 2>&1
}

backend_install_is_current() {
  local current_source_id expected_source_id expected_binary_hash actual_binary_hash

  [[ -x $backend_binary && -s $backend_source_id_file \
    && -s $backend_binary_hash_file ]] || return 1
  command -v sha256sum >/dev/null 2>&1 || return 1
  current_source_id=$("$source_root/scripts/backend-source-id.sh") || return 1
  expected_source_id=$(<"$backend_source_id_file")
  [[ $expected_source_id == "$current_source_id" ]] || return 1
  expected_binary_hash=$(<"$backend_binary_hash_file")
  [[ $expected_binary_hash =~ ^[0-9a-f]{64}$ ]] || return 1
  actual_binary_hash=$(sha256sum -- "$backend_binary") || return 1
  [[ ${actual_binary_hash%% *} == "$expected_binary_hash" ]] || return 1
  [[ ! -f $source_backend_unit ]] \
    || { [[ -f $installed_backend_unit ]] \
      && "$source_root/scripts/render-unit.sh" \
        | cmp -s -- - "$installed_backend_unit"; }
}

preferred_unit() {
  backend_install_is_current && unit_exists "$backend_unit" || return 1
  printf '%s\n' "$backend_unit"
}

case $action in
  check)
    preferred_unit >/dev/null
    ;;
  credentials)
    credential_paths=(
      "$state_root/omaspotify/oauth/credentials.json"
      "$state_root/omaspotify/zeroconf/credentials.json"
      "$cache_root/spotifyd/oauth/credentials.json"
      "$cache_root/spotifyd/zeroconf/credentials.json"
    )
    for path in "${credential_paths[@]}"; do
      [[ -s $path ]] && exit 0
    done
    exit 1
    ;;
  start)
    unit=$(preferred_unit) || {
      echo "playback-runtime.sh: no installed playback runtime is available" >&2
      exit 1
    }
    systemctl --user start "$unit"
    ;;
  stop)
    systemctl --user stop "$backend_unit" 2>/dev/null || true
    ;;
  status)
    unit=$(preferred_unit) || exit 1
    systemctl --user is-active "$unit"
    ;;
  unit)
    preferred_unit
    ;;
  *)
    echo "playback-runtime.sh: unknown action: $action" >&2
    exit 2
    ;;
esac
