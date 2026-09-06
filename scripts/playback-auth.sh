#!/bin/sh
set -eu

# Local playback owns a credential separate from the Web API refresh token.
# Force a private creation mode even when omarchy-shell inherited umask 0022.
umask 077

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
backend="$HOME/.local/lib/omaspotify/omaspotify-backend"
[ -x "$backend" ] || {
  echo "playback-auth.sh: the playback backend is not installed" >&2
  exit 1
}

exec "$backend" authenticate \
  --config-path "$config_root/omaspotify/playback.conf" \
  --oauth-port 8000
