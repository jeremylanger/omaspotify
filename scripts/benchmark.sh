#!/usr/bin/env bash
set -euo pipefail

state=${1:-}
duration=${2:-10}

if [[ -z $state || ! $state =~ ^[A-Za-z0-9._-]+$ || ! $duration =~ ^[0-9]+$ ||
      $duration -lt 2 || $duration -gt 60 ]]; then
  echo "Usage: scripts/benchmark.sh <state-label> [seconds: 2-60]" >&2
  exit 2
fi

shell_pid=""
while IFS= read -r candidate; do
  [[ -r /proc/$candidate/cmdline ]] || continue
  command_line=$(tr '\0' ' ' <"/proc/$candidate/cmdline")
  if [[ $command_line == *"quickshell -n -p /usr/share/omarchy/shell"* ]]; then
    if [[ -n $shell_pid ]]; then
      echo "benchmark.sh: more than one Omarchy quickshell process is running" >&2
      exit 1
    fi
    shell_pid=$candidate
  fi
done < <(pgrep -x quickshell || true)

[[ -n $shell_pid ]] || {
  echo "benchmark.sh: the Omarchy quickshell process is not running" >&2
  exit 1
}

mapfile -t playback_pids < <(
  {
    for process_dir in /proc/[0-9]*; do
      executable=$(readlink -f -- "$process_dir/exe" 2>/dev/null || true)
      if [[ $executable == */omaspotify-backend ]]; then
        printf '%s\n' "${process_dir##*/}"
      fi
    done
  } | sort -nu
)
all_pids=("$shell_pid" "${playback_pids[@]}")
clock_ticks=$(getconf CLK_TCK)

cpu_ticks() {
  local pid=$1
  [[ -r /proc/$pid/stat ]] || { printf '0\n'; return; }
  awk '{ print $14 + $15 }' "/proc/$pid/stat"
}

context_switches() {
  local pid=$1
  [[ -r /proc/$pid/status ]] || { printf '0\n'; return; }
  awk '
    $1 == "voluntary_ctxt_switches:" || $1 == "nonvoluntary_ctxt_switches:" {
      total += $2
    }
    END { print total + 0 }
  ' "/proc/$pid/status"
}

rollup_value() {
  local pid=$1
  local field=$2
  [[ -r /proc/$pid/smaps_rollup ]] || { printf '0\n'; return; }
  awk -v wanted="$field:" \
    '$1 == wanted { print $2; found = 1 } END { if (!found) print 0 }' \
    "/proc/$pid/smaps_rollup"
}

ticks_before=0
switches_before=0
for pid in "${all_pids[@]}"; do
  ticks_before=$((ticks_before + $(cpu_ticks "$pid")))
  switches_before=$((switches_before + $(context_switches "$pid")))
done

start_ns=$(date +%s%N)
sleep "$duration"
end_ns=$(date +%s%N)

ticks_after=0
switches_after=0
for pid in "${all_pids[@]}"; do
  ticks_after=$((ticks_after + $(cpu_ticks "$pid")))
  switches_after=$((switches_after + $(context_switches "$pid")))
done

elapsed_seconds=$(awk -v start="$start_ns" -v end="$end_ns" \
  'BEGIN { printf "%.6f", (end - start) / 1000000000 }')
cpu_percent=$(awk -v ticks="$((ticks_after - ticks_before))" \
  -v hz="$clock_ticks" -v elapsed="$elapsed_seconds" \
  'BEGIN { printf "%.3f", (ticks / hz) * 100 / elapsed }')
wakeups_per_second=$(awk -v switches="$((switches_after - switches_before))" \
  -v elapsed="$elapsed_seconds" \
  'BEGIN { printf "%.3f", switches / elapsed }')

shell_pss=$(rollup_value "$shell_pid" Pss)
shell_rss=$(rollup_value "$shell_pid" Rss)
playback_pss=0
playback_rss=0
runtime_kind=none
for pid in "${playback_pids[@]}"; do
  playback_pss=$((playback_pss + $(rollup_value "$pid" Pss)))
  playback_rss=$((playback_rss + $(rollup_value "$pid" Rss)))
  executable=$(readlink -f -- "/proc/$pid/exe" 2>/dev/null || true)
  kind=backend
  if [[ $runtime_kind == none ]]; then
    runtime_kind=$kind
  elif [[ $runtime_kind != "$kind" ]]; then
    runtime_kind=mixed
  fi
done

playback_pid_list=none
if (( ${#playback_pids[@]} > 0 )); then
  playback_pid_list=$(IFS=+; echo "${playback_pids[*]}")
fi

printf '%s\n' \
  'state,seconds,shell_pid,playback_runtime,playback_pid,shell_pss_kib,shell_rss_kib,playback_pss_kib,playback_rss_kib,total_pss_kib,total_rss_kib,cpu_percent,scheduler_switches_per_second'
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$state" "$elapsed_seconds" "$shell_pid" "$runtime_kind" "$playback_pid_list" \
  "$shell_pss" "$shell_rss" "$playback_pss" "$playback_rss" \
  "$((shell_pss + playback_pss))" "$((shell_rss + playback_rss))" \
  "$cpu_percent" "$wakeups_per_second"
