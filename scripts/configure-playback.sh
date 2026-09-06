#!/usr/bin/env bash
set -euo pipefail

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
config_file="$config_root/omaspotify/playback.conf"

IFS= read -r device_name
bitrate=""
bitrate_specified=0
if IFS= read -r bitrate; then
  bitrate_specified=1
fi
normalisation=""
pregain=""
normalisation_specified=0
if IFS= read -r normalisation && IFS= read -r pregain; then
  normalisation_specified=1
fi

if [[ -z $device_name || ${#device_name} -gt 64 || $device_name == *'"'* || $device_name == *'\'* ]]; then
  exit 3
fi
if [[ $device_name =~ [^[:print:]] ]]; then
  exit 3
fi
if (( bitrate_specified )) && [[ $bitrate != 96 && $bitrate != 160 && $bitrate != 320 ]]; then
  exit 3
fi
if (( normalisation_specified )); then
  [[ $normalisation == true || $normalisation == false ]] || exit 3
  [[ $pregain =~ ^-?[0-9]{1,2}$ ]] || exit 3
  (( pregain >= -15 && pregain <= 15 )) || exit 3
fi
if [[ ! -f $config_file ]]; then
  exit 4
fi

temporary=$(mktemp "${config_file}.tmp.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
chmod 600 "$temporary"

awk -v name="$device_name" -v rate="$bitrate" -v rate_set="$bitrate_specified" \
  -v norm="$normalisation" -v gain="$pregain" -v norm_set="$normalisation_specified" '
  /^device_name[[:space:]]*=/ {
    print "device_name = \"" name "\""
    found_name = 1
    next
  }
  /^bitrate[[:space:]]*=/ {
    if (rate_set) print "bitrate = " rate
    else print
    found_rate = 1
    next
  }
  /^device[[:space:]]*=/ {
    next
    next
  }
  /^autoplay[[:space:]]*=/ {
    print "autoplay = true"
    found_autoplay = 1
    next
  }
  /^normalisation[[:space:]]*=/ {
    if (norm_set) print "normalisation = " norm
    else print
    found_norm = 1
    next
  }
  /^normalisation_pregain_db[[:space:]]*=/ {
    if (norm_set) print "normalisation_pregain_db = " gain
    else print
    found_gain = 1
    next
  }
  { print }
  END {
    if (!found_name) print "device_name = \"" name "\""
    if (!found_rate && rate_set) print "bitrate = " rate
    if (!found_autoplay) print "autoplay = true"
    if (!found_norm && norm_set) print "normalisation = " norm
    if (!found_gain && norm_set) print "normalisation_pregain_db = " gain
  }
' "$config_file" >"$temporary"

mv -f -- "$temporary" "$config_file"
trap - EXIT
