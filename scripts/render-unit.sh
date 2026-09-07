#!/usr/bin/env bash
set -euo pipefail

# The playback unit is installed for whichever runtime and config directory
# setup chose, so its paths are filled in here rather than assumed.
source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime_dir=${OMASPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omaspotify"}
config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}

unit=$(<"$source_root/systemd/omaspotify.service")
unit=${unit//@BACKEND_BINARY@/$runtime_dir/omaspotify-backend}
unit=${unit//@CONFIG_FILE@/$config_root/omaspotify/playback.conf}
printf '%s\n' "$unit"
