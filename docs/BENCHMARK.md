# Resource benchmark

Measured on 2026-08-12 on Omarchy 4 (`4.0.0.r1658.g0820484`),
Quickshell `0.3.0.r20.g28771c7`, Qt 6.11.1, and Linux 7.1.5. The host has an
Intel Core Ultra X7 358H, 31.0 GiB RAM, and a 3200×2000 display at 120 Hz and
2× scale. The UI and desktop-client comparison was repeated from fresh starts
after unrelated high-activity software was closed, with the Matte Black theme
active.

## Results

Each reported value is the median of three consecutive 10-second samples after
a 20-second settle period. `spotifyd` and the official desktop client were not
running in these three UI-overhead states.

| State | Total PSS | Total RSS | CPU | Scheduler switches/s |
|---|---:|---:|---:|---:|
| Omarchy shell, plugin disabled | 307.9 MiB | 499.2 MiB | 1.199% | 28.486 |
| Plugin enabled, all Spotify UI closed | 309.6 MiB | 501.0 MiB | 1.100% | 27.487 |
| Spotify full window open on populated Discover | 362.8 MiB | 560.7 MiB | 1.299% | 24.088 |

The useful comparison is the same-process delta, because this plugin lives in
the existing Omarchy shell:

- Closed plugin versus disabled baseline: **+1.6 MiB PSS**, **+1.8 MiB RSS**.
- Populated full window versus disabled baseline: **+54.8 MiB PSS**,
  **+61.5 MiB RSS**.
- Opening the populated window added **53.2 MiB PSS** over the closed plugin.
- CPU moved by at most 0.1 percentage points, which is indistinguishable from
  normal desktop noise in this short sample.

The open-window sample was logged in on Discover with personalized rows and
artwork loaded. Loaded rows remain bounded to 200 per view, delegates are
recycled, and list artwork pixmaps are released with those delegates.

## Official Spotify comparison

Spotify 1.2.92.147 was then launched from a fresh start, allowed to settle, and
left paused on its populated Home screen. All nine `/opt/spotify/spotify`
processes were included. The plugin window was closed and `spotifyd` was not
running.

| Ready-to-use UI | PSS | RSS |
|---|---:|---:|
| OmaSpotify, incremental over Omarchy shell | **54.8 MiB** | **61.5 MiB** |
| Official Spotify desktop client, all processes | **912.2 MiB** | **1,672.6 MiB** |

On this host, the populated plugin window therefore used **857.4 MiB less
PSS**, or **94.0% less incremental memory**, than the official client. Put
another way, the official client used **16.6×** as much PSS. The plugin figure
is deliberately an incremental same-process delta because Omarchy's shell was
already running; the official client figure is its complete standalone process
set. PSS is the primary comparison—summed RSS double-counts shared pages across
the official client's processes.

## Genuine playback

Playback was also measured with the UI closed and a real Premium-account track
streaming through spotifyd 0.4.2 and PulseAudio. The official Spotify desktop
client was closed before sampling. The daemon had been restarted with the exact
shipped configuration, including `disable_discovery = true`, and restored an
isolated credential provisioned for this test with the account owner's consent.

These paired samples use the same Omarchy shell PID before and after stopping
spotifyd, which removes most shell-startup variability:

| Paired state | Total PSS | Total RSS | CPU | Scheduler switches/s |
|---|---:|---:|---:|---:|
| Plugin idle, all Spotify UI closed | 389.5 MiB | 621.7 MiB | 0.700% | 40.583 |
| Track playing, all Spotify UI closed | 414.7 MiB | 656.9 MiB | 1.000% | 42.092 |

Genuine playback therefore added **25.2 MiB PSS**, **35.2 MiB RSS**, and
**0.3 percentage points of sampled CPU** in this run. spotifyd itself accounted
for a median **26.3 MiB PSS / 35.6 MiB RSS**; the small difference from the
total delta is ordinary shared-page and measurement noise. Context switches
rose by 1.509/s.

The playback sample validates the shipped audio configuration and real decoder,
network, PulseAudio, and MPRIS costs. Automatic local-device selection is
covered separately by offline routing tests because exercising the Web API
would mutate the tester's real Spotify playback state.

## Plugin backend migration check

On 2026-08-16, the same host was switched live from the patched spotifyd
prototype to `omaspotify-backend` while a real track was playing. After the
backend optimization audit, three 10-second live samples reported a stable
backend median of **16.77 MiB PSS / 26.09 MiB RSS**. The documented spotifyd
playback median above was 26.3 MiB PSS / 35.6 MiB RSS, so the plugin-owned
process was about **36% smaller by PSS** and **27% smaller by RSS** in this
migration check.

This is supporting evidence rather than a new controlled UI-baseline run: the
shell and Omarchy revision changed between measurements, and plugin UI was open
during the final samples. A process-only 15-second audit found five backend
threads, 15 intentional state generations, and 22 scheduler context switches.
The pre-audit process used 35 threads and emitted position state four times per
second. CPU varied with track decoding, so no CPU-reduction claim is based on
those short samples.

A direct manual switch on the two-worker candidate remained continuously in
the `Playing` state—there was no intermediate stop or pause—and produced no
decoder underrun. The promoted service then passed a natural track transition
with no error or restart.

To reproduce the playing state, complete both browser authorizations, select a
track, wait for it to play steadily for at least 30 seconds, and keep all plugin
UI closed:

```bash
for sample in 1 2 3; do
  ./scripts/benchmark.sh "playing-$sample" 10
done
```

The script reports shell and playback-runtime memory separately as well as their
total. Do not use a sample in which the backend or spotifyd starts, stops, or
changes PID during the 10-second window.

## Method

`scripts/benchmark.sh` identifies exactly one Omarchy Quickshell process and
the plugin backend or all spotifyd processes at sample start.
`scripts/benchmark-spotify-desktop.sh`
includes every process whose executable resolves to `/opt/spotify/spotify` and
rejects a sample if that process set changes during the window. Both scripts
read:

- PSS and RSS from `/proc/PID/smaps_rollup` at the end of the window;
- user plus system CPU ticks from `/proc/PID/stat` before and after; and
- voluntary plus non-voluntary context switches from `/proc/PID/status`
  before and after.

PSS is the better memory figure for comparisons because shared mappings are
proportionally attributed. RSS is included because it is widely recognized,
but summing RSS across processes double-counts shared pages.

Scheduler context switches are only a non-privileged wakeup proxy. They are
not literal hardware wakeups, and the shell values include every other
Omarchy plugin in the same process. This host exposed no readable RAPL energy
counter, while PowerTOP requires elevated privileges, so no wall-energy claim
is made.

To reproduce the baseline, disable only this plugin, restart the shell, wait 20
seconds, and take three samples. Then enable the plugin, restart once more, keep
all Spotify surfaces closed, and repeat. Open Discover, wait another 20 seconds,
and take the populated-window samples. Use supported Omarchy commands so the
comparison exercises the same production loading path. For the desktop-client
comparison, launch Spotify from a fresh start, wait for Home and its artwork to
load, then run:

```bash
for sample in 1 2 3; do
  ./scripts/benchmark-spotify-desktop.sh "official-home-$sample" 10
done
```

## Raw samples used

```text
clean-baseline-disabled-1,10.004234,315373,511244,1.199,32.586
clean-baseline-disabled-2,10.004853,315157,511036,1.299,25.188
clean-baseline-disabled-3,10.004751,315320,511192,1.199,28.486
clean-plugin-closed-1,10.004792,317267,513192,1.299,27.487
clean-plugin-closed-2,10.004420,316864,512788,1.100,33.085
clean-plugin-closed-3,10.004482,316992,513008,1.100,24.089
clean-plugin-open-1,10.006516,371465,574204,1.299,24.784
clean-plugin-open-2,10.005164,371502,574240,1.299,24.088
clean-plugin-open-3,10.006247,371437,573848,1.099,17.689
clean-official-home-1,10.004527,9,918340,1696188,12.994,5.498
clean-official-home-2,10.004446,9,934135,1712776,16.193,18.992
clean-official-home-3,10.004297,9,934704,1713616,10.495,32.786
production-playing-closed-1,10.001784,398536,637380,26946,36432,425482,673812,2.600,43.592
production-playing-closed-2,10.001968,397684,636208,26947,36432,424631,672640,1.000,42.092
production-playing-closed-3,10.001878,397677,636204,26947,36432,424624,672636,1.000,38.393
production-idle-paired-1,10.002032,398800,636572,0,0,398800,636572,0.400,37.392
production-idle-paired-2,10.004134,398679,636448,0,0,398679,636448,0.700,40.583
production-idle-paired-3,10.001837,398812,636584,0,0,398812,636584,1.000,47.191
```

The baseline/UI rows omit zero-valued spotifyd columns for readability and are
`state,seconds,total_pss_kib,total_rss_kib,cpu_percent,switches_per_second`.
The official-client rows are
`state,seconds,process_count,pss_kib,rss_kib,cpu_percent,switches_per_second`.
The paired playback rows are
`state,seconds,shell_pss_kib,shell_rss_kib,spotifyd_pss_kib,spotifyd_rss_kib,`
`total_pss_kib,total_rss_kib,cpu_percent,switches_per_second`. The full CSV
outputs also record the involved PID lists.

The current script labels the runtime explicitly and uses generic
`playback_pss_kib` / `playback_rss_kib` columns. The migration samples were:

```text
backend-playing-1,10.002018,1776938,backend,1764497,376717,605040,20077,29500,396794,634540,5.999,139.672
backend-playing-2,10.001963,1776938,backend,1764497,377428,605628,20089,29500,397517,635128,5.499,139.273
backend-playing-3,10.002512,1776938,backend,1764497,378205,606404,20089,29500,398294,635904,6.098,141.364
backend-optimized-playing-1,10.001856,1804726,backend,1832381,434985,669752,17165,26708,452150,696460,7.099,134.275
backend-optimized-playing-2,10.002266,1804726,backend,1832381,434569,669336,17169,26712,451738,696048,7.298,136.869
backend-optimized-playing-3,10.002246,1804726,backend,1832381,434660,669428,17169,26712,451829,696140,7.598,135.470
```

## Disk footprint

The stripped plugin backend built on this host is 9.12 MiB. Arch's spotifyd
0.4.2 package reports an 11.34 MiB installed size; both use audio and TLS
libraries already present on Omarchy. For scale only, the installed proprietary
Spotify desktop package on the same host reports 368.51 MiB. Disk footprint is
not a substitute for runtime measurement, but it illustrates why the plugin
avoids shipping a browser runtime.
