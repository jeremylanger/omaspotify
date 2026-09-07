#!/usr/bin/env bash
set -euo pipefail

# The playback helper owns its loopback response page, so it cannot ask the browser to
# close itself. Close only an unmistakable, currently selected callback tab;
# if the user already changed tabs or identification is ambiguous, do nothing.
close_playback_callback_tab() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local callback_address
  local -a callback_addresses=()
  mapfile -t callback_addresses < <(
    hyprctl clients -j 2>/dev/null | jq -r '
      .[]
      | select(
          ((.class // "")
            | test("(firefox|zen|chromium|chrome|brave|vivaldi|opera|edge)"; "i"))
          and ((.title // "")
            | test("^127\\.0\\.0\\.1:8000/login\\?(code|error)="))
        )
      | .address
    '
  )

  (( ${#callback_addresses[@]} == 1 )) || return 0
  callback_address=${callback_addresses[0]}
  [[ $callback_address =~ ^0x[0-9a-fA-F]+$ ]] || return 0

  hyprctl eval \
    "hl.dispatch(hl.dsp.send_shortcut({ mods = \"CTRL\", key = \"W\", window = \"address:$callback_address\" }))" \
    >/dev/null 2>&1 || true
}

return_to_spotify() {
  command -v omarchy-shell >/dev/null 2>&1 || return 0
  omarchy-shell -q shell summon io.github.jeremylanger.omaspotify '{"tab":"search"}' \
    >/dev/null 2>&1 || true

  command -v hyprctl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local attempt spotify_address
  for attempt in {1..20}; do
    spotify_address=$(
      hyprctl clients -j 2>/dev/null | jq -r '
        [.[]
          | select((.class // "") == "org.quickshell"
            and (.title // "") == "OmaSpotify")
          | .address][0] // empty
      '
    )
    if [[ $spotify_address =~ ^0x[0-9a-fA-F]+$ ]]; then
      hyprctl eval \
        "hl.dispatch(hl.dsp.focus({ window = \"address:$spotify_address\" }))" \
        >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.05
  done
}

close_playback_callback_tab
return_to_spotify
