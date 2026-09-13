#!/usr/bin/env bash
# Streams cava spectrum frames for the plugin's own playback stream only.
#
# cava is pointed at the PipeWire object serial of the backend's output
# stream, so other applications never show up in the equalizer. While no
# local stream exists (nothing playing here, or playback on another Connect
# device) the script prints "idle" once a second instead of frames. When the
# stream disappears cava is restarted so a new stream is linked again.
#
# Usage: equalizer.sh <config-path> [bars] [backend-binary-name]
set -u

config_path=$1
bars=${2:-48}
backend_binary=${3:-omaspotify-backend}

command -v cava >/dev/null 2>&1 || exit 127
command -v pw-dump >/dev/null 2>&1 || exit 126
command -v python3 >/dev/null 2>&1 || exit 126
mkdir -p "$(dirname "$config_path")"

find_stream() {
  pw-dump 2>/dev/null | python3 -c '
import json, sys
binary = sys.argv[1]
try:
    objects = json.load(sys.stdin)
except Exception:
    objects = []
for item in objects:
    props = ((item.get("info") or {}).get("props") or {})
    if props.get("media.class") != "Stream/Output/Audio":
        continue
    if props.get("application.process.binary") != binary:
        continue
    print(item.get("id", ""), props.get("object.serial", ""))
    break
' "$backend_binary"
}

stream_alive() {
  pw-dump "$1" 2>/dev/null | grep -q "\"object.serial\": $2,"
}

write_config() {
  printf '%s\n' \
    "[general]" "bars = $bars" "framerate = 40" "autosens = 1" \
    "[input]" "method = pipewire" "source = $1" \
    "[output]" "method = raw" "raw_target = /dev/stdout" \
    "data_format = ascii" "ascii_max_range = 1000" \
    "bar_delimiter = 59" "frame_delimiter = 10" \
    "[smoothing]" "noise_reduction = 72" "monstercat = 1" \
    > "$config_path"
}

cava_pid=""
cleanup() {
  [[ -n $cava_pid ]] && kill "$cava_pid" 2>/dev/null
  exit 0
}
trap cleanup TERM INT HUP

while true; do
  read -r node serial <<<"$(find_stream)"
  if [[ -z ${serial:-} ]]; then
    printf 'idle\n'
    sleep 1
    continue
  fi
  write_config "$serial"
  cava -p "$config_path" &
  cava_pid=$!
  while kill -0 "$cava_pid" 2>/dev/null; do
    sleep 2
    if ! stream_alive "$node" "$serial"; then
      kill "$cava_pid" 2>/dev/null
      wait "$cava_pid" 2>/dev/null
      cava_pid=""
      break
    fi
  done
  if [[ -n $cava_pid ]]; then
    wait "$cava_pid" 2>/dev/null
    cava_pid=""
  fi
  sleep 0.5
done
