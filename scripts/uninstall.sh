#!/usr/bin/env bash
set -euo pipefail

if (( $# > 0 )); then
  echo "Usage: scripts/uninstall.sh" >&2
  exit 2
fi

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugins_dir="$HOME/.config/omarchy/plugins"
plugin_dir="$plugins_dir/quickshell.spotify"

[[ $HOME == /* && $HOME != / ]] || {
  echo "uninstall.sh: refusing an unsafe home path" >&2
  exit 3
}
command -v omarchy >/dev/null 2>&1 || {
  echo "uninstall.sh: Omarchy is not installed" >&2
  exit 1
}

# Disable first so the shell drops its widget and service before the runtime
# files and plugin checkout disappear. This is intentionally safe to repeat.
omarchy plugin disable quickshell.spotify >/dev/null 2>&1 || true
"$source_root/scripts/remove-runtime.sh" --purge

if [[ -e $plugin_dir || -L $plugin_dir ]]; then
  omarchy plugin remove quickshell.spotify --yes
fi

# Omarchy backs up unmanaged plugin folders instead of deleting them. A full
# uninstall explicitly removes only backups bearing this plugin's exact ID.
for backup in "$plugins_dir"/.quickshell.spotify.bak.*; do
  [[ -e $backup ]] || continue
  rm -rf -- "$backup"
done

omarchy restart shell

hypr_config="$HOME/.config/hypr"
if command -v rg >/dev/null 2>&1 && [[ -d $hypr_config ]] \
    && rg -q 'quickshell\.spotify|Omarchy Spotify' "$hypr_config"; then
  echo >&2
  echo "Legacy Omarchy Spotify references remain in Hyprland config:" >&2
  rg -n 'quickshell\.spotify|Omarchy Spotify' "$hypr_config" >&2 || true
  echo "Remove those custom lines (and their dotfiles source), then run hyprctl reload." >&2
fi

echo "Omarchy Spotify's plugin data and runtime have been completely uninstalled."
echo "External source checkouts and other plugins were left alone."
