#!/bin/bash
# m198830.sh <step> [args] (macOS Tart guest, user admin, /bin/bash 3.2): the guest side of T198830.
#   info | wd-start | wd-run | wd-stop | lmsinst | lmssetup | model | estimate | probe1024 | proxy-start
#   | cell <tag> <openclaw-version> <catalog none|N> <ws-full|ws-prose> <maxfwd 0|N> | pack <label>
# LM Studio (127.0.0.1:1234), the recording proxy (127.0.0.1:1235) and OpenClaw all run inside this VM, on loopback.
# No step uses sudo. openclaw never runs as root. Every step prints its verdict lines BEFORE any raw dump; raw files
# stay in ~/k198830/ev and are pulled whole by the driver after every step ("pack"). The driver also tails proxy.jsonl
# and the LM Studio logs from the host while a cell runs, so a VM kill does not lose the load evidence.
# STEP_BUDGET (seconds, set by the driver) caps every tmo in this step, so the step ends before the host's own limit.
set -u
K=$HOME/k198830; E=$K/ev; JH=$K/j198830.mjs; API=http://127.0.0.1:1234; PXP=1235
mkdir -p "$E" "$K/dl"
DMG_URL=https://installers.lmstudio.ai/darwin/arm64/0.4.28-2/LM-Studio-0.4.28-2-arm64.dmg; DMG_BYTES=572548100
GGUF_URL=https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/370f27d7550e0def9b39c1f16d3fbaa13aa67728/Qwen3-Embedding-0.6B-Q8_0.gguf
GGUF_BYTES=639150592; GGUF_SHA=06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439
RT_PIN=llama.cpp-mac-arm64-apple-metal-advsimd@2.73.0
# The OpenClaw npm tarballs the Maintainer read (npm dist.integrity / dist.shasum) and the sha256 of the two dist files
# on the LM Studio preload path. INTEGRITY lines compare the registry and the guest's installed files with these.
OC_113_INT=sha512-FBq/q0TCaoA2b7qfdV0q81fHhI6RBB1zAQfJQREc1u2TlK5khVgCUsAlXskLWthyVqRz5PWEj+oOmfYgK58dHg==
OC_113_SHA1=d7db24ae086448184e328ff69a39cbea3e43d4b6
OC_113_MF="models.fetch-CvwY-pH2.mjs fe32460060ffad7e6442d437575c5bc041bf2689f1b452baa918f792a661b135"
OC_113_AD="memory-embedding-adapter-BArecCfm.mjs e38cd3d36e50df3d6ad03c0f43f3a204632e02222fc3dd96cac2b554c023a6ed"
OC_114_INT=sha512-kSMzBc0fIWrW4DqneFEXL9FRboCZCQV22Edm6iFPqRaBexUeZp9huWNPVWLXmuSAQRezorPfrABkODqq65NOmw==
OC_114_SHA1=71eeeac4e4b95a0d2bb6c80fb1e0463ac7ec79b9
OC_114_MF="models.fetch-P3jSgbJH.mjs 9770c1cd5a85502960ca7c311488c1e2f50abae173fe2ad1a33ec50c61696fe6"
OC_114_AD="memory-embedding-adapter-D6Ok5oZE.mjs 112aaba7a1bed68a47761a829eb7754018bdc772768383a3fae74da9b68b231f"
# 16 GB Apple Silicon reference for the Metal working-set budget (recommendedMaxWorkingSetSize, MB = 10^6 bytes as
# llama.cpp prints it): 2/3 of 16 GiB = 11453.25 MB = 10.67 GiB. Accepted band for "matched-16gb": 10.0-12.0 GiB.
RMWS_LO_GIB=10.0; RMWS_HI_GIB=12.0
DL=0; case "${STEP_BUDGET:-}" in ''|*[!0-9]*) ;; *) DL=$(( $(date +%s) + STEP_BUDGET )) ;; esac
ts() { date -u +%FT%TZ; }
tmo() { # tmo <secs> <cmd...>: own process group, killed WHOLE at the limit (rc 142); the limit is capped by STEP_BUDGET
  local s=$1 r; shift
  if [ "$DL" -gt 0 ]; then r=$(( DL - $(date +%s) )); [ "$r" -lt 5 ] && r=5; [ "$s" -gt "$r" ] && s=$r; fi
  perl -MPOSIX=:sys_wait_h -e '
    my $s = shift; my $pid = fork(); die "fork: $!\n" unless defined $pid;
    if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec failed: $!\n"; }
    $SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { kill "KILL", -$pid, $pid; exit 143 };
    my $end = time + $s;
    while (1) { my $r = waitpid($pid, WNOHANG); if ($r == $pid) { exit(($? & 127) ? 128 + ($? & 127) : $? >> 8) }
      last if time >= $end; select(undef, undef, undef, 0.5); }
    print STDERR "tmo: limit ${s}s reached, killing process group $pid\n"; kill "KILL", -$pid, $pid; waitpid($pid, 0); exit 142;' "$s" "$@"
}
one() { tr -s ' \t\n' '___' | sed 's/_$//' | cut -c1-${1:-300}; }
detach() { # detach <logfile> <pidfile> <cmd...>: own session, no tty, survives the ssh session
  local lf=$1 pf=$2; shift 2
  env -u STEP_BUDGET perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec failed: $!"' "$@" > "$lf" 2>&1 < /dev/null &
  echo $! > "$pf"
}
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
lmsbin() { cat "$K/lms.path" 2>/dev/null; }
oc() { # oc <outfile> <seconds> <openclaw args...>: output to file, echo the exit code
  local f=$1 s=$2; shift 2
  { echo "+ openclaw $* [$(ts)]"; tmo "$s" openclaw "$@" < /dev/null; echo "rc=$?"; } > "$f" 2>&1
  sed -n 's/^rc=//p' "$f" | tail -n 1
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
logfiles() { # every LM Studio log file we know of (tab-separated: size path)
  { echo "$E/lms-runtime.log"; echo "$E/lms-server.log"
    find "$HOME/.lmstudio/server-logs" "$HOME/.lmstudio/logs" "$HOME/Library/Logs/LM Studio" -type f 2>/dev/null; } |
    while read -r p; do [ -f "$p" ] && printf '%s\t%s\n' "$(stat -f %z "$p")" "$p"; done
}
logmark() { logfiles > "$K/mark.$1"; }
logslice() { # logslice <mark> <out>: bytes written to any log file since the mark
  : > "$2"
  logfiles | while IFS="$(printf '\t')" read -r sz p; do
    old=$(awk -F'\t' -v p="$p" '$2==p{print $1}' "$K/mark.$1" 2>/dev/null | head -n 1); old=${old:-0}
    [ "$sz" -gt "$old" ] && { echo "=== $p (+$((sz - old)) bytes)"; tail -c +$((old + 1)) "$p"; } >> "$2"
  done
}
rtgrep() { # rtgrep <slice> <tag>: llama.cpp / Metal lines and a one-line summary
  local f=$1 t=$2 nctx nub nb af mtl cpu mi mb cb mx ob br rm gr
  grep -a -i -E 'ggml_metal|recommendedMaxWorkingSetSize|simdgroup|GPU family|has unified|hasUnifiedMemory|n_ctx|n_batch|n_ubatch|buffer size|failed to allocate|failed to initialize|Resetting batch size|truncat|MTL0|CPU_Mapped|out of memory|guardrail|insufficient|context length' "$f" |
    head -n 80 | cut -c1-300 | sed "s/^/RTL $t /"
  # n_ctx / n_ubatch / n_batch: values IN LOG ORDER (consecutive repeats collapsed), one per load in this slice; pair
  # them with the proxy's load rows (PX load_results, same order) rather than reading them as one value per cell.
  nctx=$(grep -a -o -E 'n_ctx(_seq)? *= *[0-9]+' "$f" | grep -o -E '[0-9]+$' | uniq | tr '\n' ',' | sed 's/,$//')
  nub=$(grep -a -o -E 'n_ubatch *= *[0-9]+' "$f" | grep -o -E '[0-9]+$' | uniq | tr '\n' ',' | sed 's/,$//')
  nb=$(grep -a -o -E 'n_batch *= *[0-9]+' "$f" | grep -o -E '[0-9]+$' | uniq | tr '\n' ',' | sed 's/,$//')
  br=$(grep -a -o -E 'context length \([0-9]+\)\. Resetting batch size' "$f" | grep -o -E '[0-9]+' | tr '\n' ',' | sed 's/,$//')
  rm=$(grep -a -o -E 'recommendedMaxWorkingSetSize *= *[0-9]+(\.[0-9]+)? *MB' "$f" | head -n 1 | grep -o -E '[0-9]+(\.[0-9]+)?' | head -n 1)
  gr=$(grep -a -c -i -E 'guardrail|insufficient' "$f")
  af=$(grep -a -c -i 'failed to allocate' "$f"); mtl=$(grep -a -c 'MTL0' "$f"); mi=$(grep -a -c -i 'ggml_metal' "$f")
  cpu=$(grep -a -c -E 'CPU[A-Za-z_]* (compute )?buffer size' "$f")
  mb=unknown
  if grep -a -i 'model buffer size' "$f" | grep -q -i -E 'MTL|Metal'; then mb=MTL0
  elif grep -a -q -i 'model buffer size' "$f"; then mb=CPU; fi
  cb=unknown
  if grep -a -i 'compute buffer size' "$f" | grep -q -i -E 'MTL|Metal'; then cb=MTL0
  elif grep -a -q -i 'compute buffer size' "$f"; then cb=CPU; fi
  mx=$(grep -a -o -E '[0-9]+(\.[0-9]+)? MiB' "$f" | awk '{print $1}' | sort -n | tail -n 1)
  ob=$(grep -a -o -E 'of size [0-9]+' "$f" | awk '{print $3}' | sort -n | tail -n 1)
  echo "RTSUM $t bytes=$(wc -c < "$f" | tr -d ' ') n_ctx=${nctx:-none} n_ubatch=${nub:-none} n_batch=${nb:-none} batch_reset_to=${br:-none} metal_lines=$mi model_buf=$mb compute_buf=$cb mtl0_lines=$mtl cpu_buf_lines=$cpu alloc_fail=$af max_mib=${mx:-none} max_fail_bytes=${ob:-none} rmws_mb=${rm:-none} guardrail_lines=$gr"
}
gmem() { # gmem <t0> <t1> <tag>: guest memory peaks from the watchdog log
  awk -v a="$1" -v b="$2" -v t="$3" '
    { for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } }
    v["t"] >= a && v["t"] <= b { n++; if (n == 1 || v["avail_mib"] < mn) mn = v["avail_mib"]; if (v["swap_mib"] > sw) sw = v["swap_mib"]
      if (v["level"] > lv) lv = v["level"]; if (v["lms_rss_mib"] > rss) rss = v["lms_rss_mib"]; if (v["comp_mib"] > cp) cp = v["comp_mib"] }
    END { printf "GMEM %s samples=%d guest_min_avail_mib=%d guest_swap_peak_mib=%d guest_max_level=%d guest_max_comp_mib=%d lms_rss_peak_mib=%d\n", t, n, mn, sw, lv, cp, rss }' "$E/wd.log" 2>/dev/null
}
memsample() { # one line of guest memory facts
  local pg av cp sw lv rss
  pg=$(sysctl -n hw.pagesize)
  read -r av cp <<EOF
$(vm_stat | awk -v pg="$pg" '{gsub(/\./, "", $NF)} /^Pages free/ {f=$NF} /^Pages inactive/ {i=$NF} /^Pages speculative/ {s=$NF} /^Pages purgeable/ {p=$NF} /occupied by compressor/ {c=$NF} END {printf "%d %d\n", (f+i+s+p)*pg/1048576, c*pg/1048576}')
EOF
  sw=$(sysctl -n vm.swapusage | awk '{for (i = 1; i <= NF; i++) if ($i == "used") v = $(i+2)} END {n = v + 0; if (v ~ /G$/) n *= 1024; printf "%d", n}')
  lv=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
  rss=$(ps -axo rss=,command= | awk 'tolower($0) ~ /lm studio|lmstudio|llmster/ {s += $1} END {printf "%d", s/1024}')
  echo "t=$(date +%s) avail_mib=$av comp_mib=$cp swap_mib=$sw level=$lv lms_rss_mib=$rss"
}

step=${1:-}; shift || true
[ "$(id -u)" != 0 ] || { echo "REFUSE running as root"; exit 99; }
echo "STEP $step $* start=$(ts)"
case "$step" in
  info)
    echo "HW memsize=$(sysctl -n hw.memsize) ncpu=$(sysctl -n hw.ncpu) model=$(sysctl -n hw.model | one) arch=$(uname -m) os=$(sw_vers -productVersion)_$(sw_vers -buildVersion)"
    echo "SW node=$(node --version) npm=$(npm --version) openclaw=$(openclaw --version 2>/dev/null | tail -n 1 | one) npm_prefix=$(npm prefix -g)"
    system_profiler SPDisplaysDataType 2>/dev/null | grep -i -E 'chipset|metal|vendor|cores|VRAM' | sed 's/^ */GPUINFO /'
    df -h "$HOME" | tail -n 1 | sed 's/^/DISK /'; memsample | sed 's/^/GUESTMEM /'
    pgrep -l -i -f 'lm studio|lmstudio|llmster' | sed 's/^/PRE_LMS_PROC /'; ls -la "$HOME/.lmstudio" 2>&1 | head -n 5 | sed 's/^/PRE_LMS_DIR /' ;;
  wd-start)
    rm -f "$K/wd.stop"; alive "$K/wd.pid" && { echo "WD already running pid=$(cat "$K/wd.pid")"; exit 0; }
    detach "$E/wd.stderr.txt" "$K/wd.pid" /bin/bash "$K/m198830.sh" wd-run
    sleep 3; alive "$K/wd.pid" && echo "WD started pid=$(cat "$K/wd.pid") $(tail -n 1 "$E/wd.log" 2>/dev/null)" || echo "WD FAILED" ;;
  wd-run) # in-guest watchdog (second safety layer; the host supervisor is the first)
    base=""; while [ ! -f "$K/wd.stop" ]; do
      l=$(memsample); echo "$l" >> "$E/wd.log"
      sw=$(echo "$l" | tr ' ' '\n' | sed -n 's/^swap_mib=//p'); lv=$(echo "$l" | tr ' ' '\n' | sed -n 's/^level=//p')
      sw=${sw:-0}; lv=${lv:-0}; [ -n "$base" ] || base=$sw
      if [ ! -f "$E/BOUNDED_REJECT" ] && { [ "$sw" -gt $((base + 2048)) ] || [ "$lv" -ge 4 ]; }; then
        echo "BOUNDED_REJECT t=$(date +%s) at=$(ts) reason=$([ "$lv" -ge 4 ] && echo guest-pressure-critical || echo guest-swap-over-2GiB) swap_base_mib=$base sample=[$l]" > "$E/BOUNDED_REJECT"
        L=$(lmsbin); [ -n "$L" ] && tmo 20 "$L" unload --all >> "$E/BOUNDED_REJECT" 2>&1
        pkill -9 -i -f 'lm studio|lmstudio|llmster'; echo "pkill rc=$? at=$(ts)" >> "$E/BOUNDED_REJECT"
      fi
      sleep 2
    done ;;
  wd-stop) touch "$K/wd.stop"; sleep 3; echo "WD stopped alive=$(alive "$K/wd.pid" && echo yes || echo no)" ;;
  lmsinst)
    { echo "+ curl $DMG_URL [$(ts)]"; tmo 1800 curl -fL --retry 3 --connect-timeout 30 -sS -o "$K/dl/lmstudio.dmg" "$DMG_URL"; echo "rc=$?"; } > "$E/dmg-download.txt" 2>&1
    by=$(stat -f %z "$K/dl/lmstudio.dmg" 2>/dev/null || echo 0)
    echo "DMG rc=$(sed -n 's/^rc=//p' "$E/dmg-download.txt") bytes=$by expected_bytes=$DMG_BYTES sha256=$(sha "$K/dl/lmstudio.dmg" 2>/dev/null) url=$DMG_URL"
    [ "$by" = "$DMG_BYTES" ] || { echo "BLOCKED lmsinst reason=dmg-size-mismatch"; exit 4; }
    mkdir -p "$K/dmgmnt"
    echo Y | hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$K/dmgmnt" "$K/dl/lmstudio.dmg" > "$E/dmg-attach.txt" 2>&1
    echo "DMG attach rc=$?"
    APPSRC=$(ls -d "$K/dmgmnt"/*.app 2>/dev/null | head -n 1)
    rm -rf "/Applications/LM Studio.app"; [ -n "$APPSRC" ] && cp -R "$APPSRC" "/Applications/LM Studio.app"
    hdiutil detach "$K/dmgmnt" > /dev/null 2>&1 || hdiutil detach -force "$K/dmgmnt" > /dev/null 2>&1
    APP="/Applications/LM Studio.app"   # r4: /Applications + plain open (probe 11-17: lms bootstraps in seconds; ~/Applications + open -g -j never did)
    AV=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null); AB=$(defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null)
    echo "APP src=$(basename "${APPSRC:-none}" | one) installed=$([ -d "$APP" ] && echo yes || echo no) version=${AV:-none} build=${AB:-none} quarantine=$(xattr -p com.apple.quarantine "$APP" 2>/dev/null | one 80)"
    ROUTE=none
    if [ -d "$APP" ]; then
      open -a "$APP" > "$E/app-open.txt" 2>&1; echo "APP open rc=$?"
      for i in $(seq 1 60); do [ -x "$HOME/.lmstudio/bin/lms" ] && break; sleep 5; done
      if [ -x "$HOME/.lmstudio/bin/lms" ]; then ROUTE=app; echo "$HOME/.lmstudio/bin/lms" > "$K/lms.path"
      else
        B=$(find "$APP/Contents" -type f -name lms -perm -u+x 2>/dev/null | head -n 1)
        [ -n "$B" ] && { ROUTE=app-bundled-cli; echo "$B" > "$K/lms.path"; }
      fi
    fi
    if [ "$ROUTE" != none ] && ! tmo 90 "$(lmsbin)" version > "$E/lms-version.txt" 2>&1; then ROUTE=none; fi
    if [ "$ROUTE" = none ]; then  # route 2: headless llmster (the core version it lands on is not pinned; recorded)
      pkill -i -f 'LM Studio.app'; sleep 2
      curl -fsSL --connect-timeout 30 -o "$K/dl/install.sh" https://lmstudio.ai/install.sh; echo "LLMSTER script rc=$? sha256=$(sha "$K/dl/install.sh" 2>/dev/null)"
      { LMS_NO_MODIFY_PATH=1 tmo 1200 bash "$K/dl/install.sh"; echo "rc=$?"; } > "$E/llmster-install.txt" 2>&1 < /dev/null
      echo "LLMSTER install rc=$(sed -n 's/^rc=//p' "$E/llmster-install.txt" | tail -n 1)"
      [ -x "$HOME/.lmstudio/bin/lms" ] && { ROUTE=llmster; echo "$HOME/.lmstudio/bin/lms" > "$K/lms.path"; tmo 120 "$(lmsbin)" daemon up > "$E/lms-daemon-up.txt" 2>&1; echo "LLMSTER daemon_up rc=$?"; }
      [ "$ROUTE" = llmster ] && tmo 90 "$(lmsbin)" version > "$E/lms-version.txt" 2>&1
    fi
    LP=no; case "$ROUTE:${AV:-}" in app:0.4.28*|app-bundled-cli:0.4.28*) LP=yes ;; esac
    echo "LMS route=$ROUTE lms_pinned=$LP app_version=${AV:-none} app_build=${AB:-none} cli=$(lmsbin | one) version=$(grep -v '^ *$' "$E/lms-version.txt" 2>/dev/null | tail -n 3 | one 200) (lms_pinned=no = premise changed: LM Studio is not the reporter's 0.4.28 app build)"
    [ "$ROUTE" != none ] || { echo "BLOCKED lmsinst reason=no-lms-cli"; exit 4; }
    pgrep -l -i -f 'lm studio|lmstudio|llmster' | sed 's/^/LMS_PROC /' ;;
  lmssetup)
    L=$(lmsbin); [ -n "$L" ] || { echo "BLOCKED lmssetup reason=no-lms"; exit 4; }
    tmo 120 "$L" server start --bind 127.0.0.1 --port 1234 > "$E/server-start.txt" 2>&1; r=$?
    [ "$r" = 0 ] || { LMS_SERVER_HOST=127.0.0.1 tmo 120 "$L" server start --port 1234 >> "$E/server-start.txt" 2>&1; r=$?; echo "SERVER retry_without_bind_flag rc=$r"; }
    up=no; for i in $(seq 1 30); do curl -s -m 5 "$API/api/v1/models" > /dev/null 2>&1 && { up=yes; break; }; sleep 2; done
    lsof -nP -iTCP:1234 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print "LISTEN " $1 " " $9}'
    nl=$(lsof -nP -iTCP:1234 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && $9 !~ /^(127\.0\.0\.1|\[::1\]|localhost):/' | wc -l | tr -d ' ')
    echo "SERVER start_rc=$r api_up=$up nonloopback_listeners=$nl"
    [ "$up" = yes ] || { echo "BLOCKED lmssetup reason=api-not-up"; exit 4; }
    [ "$nl" = 0 ] || { tmo 60 "$L" server stop > /dev/null 2>&1; echo "BLOCKED lmssetup reason=not-loopback-only"; exit 4; }
    tmo 120 "$L" runtime ls > "$E/runtime-ls-1.txt" 2>&1; echo "RUNTIME ls1 rc=$?"
    tmo 120 "$L" runtime --help > "$E/runtime-help.txt" 2>&1
    tmo 900 "$L" runtime get "$RT_PIN" --yes > "$E/runtime-get.txt" 2>&1 < /dev/null; g=$?
    [ "$g" = 0 ] || { tmo 900 "$L" runtime get "$RT_PIN" >> "$E/runtime-get.txt" 2>&1 < /dev/null; g=$?; }
    tmo 120 "$L" runtime select "$RT_PIN" > "$E/runtime-select.txt" 2>&1 < /dev/null; sl=$?
    tmo 120 "$L" runtime ls > "$E/runtime-ls-2.txt" 2>&1
    sed 's/^/RTLS /' "$E/runtime-ls-2.txt" | cut -c1-200 | head -n 25
    l273=$(grep -c '2\.73\.0' "$E/runtime-ls-2.txt"); RP=no; [ "$g" = 0 ] && [ "$sl" = 0 ] && [ "$l273" -ge 1 ] && RP=yes
    echo "RUNTIME pin=$RT_PIN get_rc=$g select_rc=$sl listed_2_73_0=$l273 runtime_pinned=$RP selected_line=$(grep -i -E 'metal' "$E/runtime-ls-2.txt" | grep -i -E '✓|\*|select|active|current' | head -n 1 | one 160) (runtime_pinned=no = premise changed; the run goes on, but an allocation non-reproduction is then inconclusive)"
    for f in "$HOME"/.lmstudio/*.json "$HOME"/.lmstudio/.internal/*.json; do [ -f "$f" ] &&
      grep -o -i -E '"[^"]*(guardrail|jit|ttl|evict|autoUnload|loadModelGuard)[^"]*" *: *("[^"]*"|[^,}]*)' "$f" | sed "s|^|SETTINGS $(basename "$f") |" | head -n 20; done
    tmo 60 "$L" server status > "$E/server-status.txt" 2>&1; sed 's/^/SERVERSTATUS /' "$E/server-status.txt" | head -n 10
    for s in runtime server; do
      detach "$E/lms-$s.log" "$K/log-$s.pid" "$L" log stream --source "$s"; sleep 3
      alive "$K/log-$s.pid" || { detach "$E/lms-$s.log" "$K/log-$s.pid" "$L" log stream; sleep 3; echo "LOGSTREAM $s fallback=plain"; }
      echo "LOGSTREAM $s alive=$(alive "$K/log-$s.pid" && echo yes || echo no) head=$(head -c 200 "$E/lms-$s.log" | one 200)"
    done ;;
  model)
    L=$(lmsbin); D=$HOME/.lmstudio/models/Qwen/Qwen3-Embedding-0.6B-GGUF; F=$D/Qwen3-Embedding-0.6B-Q8_0.gguf; mkdir -p "$D"
    { echo "+ curl $GGUF_URL [$(ts)]"; tmo 1800 curl -fL --retry 3 --connect-timeout 30 -sS -o "$F.part" "$GGUF_URL"; echo "rc=$?"; } > "$E/gguf-download.txt" 2>&1
    by=$(stat -f %z "$F.part" 2>/dev/null || echo 0); gs=$(sha "$F.part" 2>/dev/null)
    echo "GGUF rc=$(sed -n 's/^rc=//p' "$E/gguf-download.txt") bytes=$by expected_bytes=$GGUF_BYTES sha256=$gs expected_sha256=$GGUF_SHA"
    [ "$gs" = "$GGUF_SHA" ] || { rm -f "$F.part"; echo "BLOCKED model reason=sha-mismatch"; exit 4; }
    mv "$F.part" "$F"; tmo 120 "$L" ls > "$E/lms-ls.txt" 2>&1
    KEY=NONE; for i in $(seq 1 24); do
      node "$JH" models "$API" "$E/models-0.json" qwen3-embedding-0.6b > "$K/models.out" 2>&1
      KEY=$(sed -n 's/^KEY //p' "$K/models.out"); [ "$KEY" != NONE ] && [ -n "$KEY" ] && break; sleep 5; done
    cat "$K/models.out"
    [ -n "$KEY" ] && [ "$KEY" != NONE ] || { echo "BLOCKED model reason=model-not-listed"; exit 4; }
    echo "$KEY" > "$K/key"
    mc=$(grep "^MODEL key=$KEY " "$K/models.out" | tr ' ' '\n' | sed -n 's/^max_ctx=//p' | head -n 1)
    echo "MODELCHK key=$KEY max_ctx=$mc expected_max_ctx=32768 match=$([ "$mc" = 32768 ] && echo yes || echo no) reporter_key=text-embedding-qwen3-embedding-0.6b same_as_reporter=$([ "$KEY" = text-embedding-qwen3-embedding-0.6b ] && echo yes || echo no)" ;;
  estimate) # memory estimates WITHOUT loading; only if this lms documents --estimate-only (otherwise skipped). Runs
    # before the Metal gate and outside the proxy, so only the small contexts: an lms build whose flag misbehaves must
    # not be able to start a large load here.
    L=$(lmsbin); KEY=$(cat "$K/key")
    tmo 60 "$L" load --help > "$E/load-help.txt" 2>&1
    if grep -q -- '--estimate-only' "$E/load-help.txt"; then
      for c in 1024 2048; do
        tmo 180 "$L" load "$KEY" --estimate-only --context-length "$c" > "$E/estimate-$c.txt" 2>&1 < /dev/null
        echo "EST ctx=$c rc=$? out=$(grep -v '^ *$' "$E/estimate-$c.txt" | tail -n 4 | one 260)"
      done
    else echo "EST skipped reason=no-estimate-only-flag"; fi
    node "$JH" models "$API" "$E/models-est.json" > "$K/models-est.out"; grep '^LOADED' "$K/models-est.out" | sed 's/^/AFTER_EST /'
    grep -q '^LOADED n=0 ' "$K/models-est.out" || { node "$JH" unloadall "$API"; echo "BLOCKED estimate reason=estimate-loaded-a-model"; exit 4; } ;;
  probe1024) # direct 1024 load: Metal gate + direct truncation probe
    KEY=$(cat "$K/key"); [ -f "$K/alt.txt" ] || { echo "BLOCKED probe1024 reason=no-alt.txt"; exit 4; }
    node "$JH" unloadall "$API" | tee "$K/p1024.pre"
    grep -q 'remaining=0$' "$K/p1024.pre" || { echo "BLOCKED probe1024 reason=instances-still-loaded"; exit 4; }
    logmark p1024; t0=$(date +%s)
    node "$JH" load "$API" "$KEY" 1024 "$E/load-1024.json" | tee "$K/p1024.out"; sleep 6
    node "$JH" models "$API" "$E/models-p1024.json" > "$K/models-p1024.out"; grep '^LOADED' "$K/models-p1024.out" | sed 's/^/P1024 /'
    INST=$(sed -n 's/.* instance=\([^ ]*\).*/\1/p' "$K/p1024.out"); [ "$INST" = - ] && INST=$KEY
    grep -q 'http=2' "$K/p1024.out" && node "$JH" probe "$API" "$INST" "$K/alt.txt" direct-1024
    sleep 2; logslice p1024 "$E/p1024.rt"; rtgrep "$E/p1024.rt" p1024 > "$K/p1024.rtg"
    mb=$(grep '^RTSUM' "$K/p1024.rtg" | tr ' ' '\n' | sed -n 's/^model_buf=//p')
    mi=$(grep -a -c -i 'ggml_metal' "$E/p1024.rt"); rb=$(wc -c < "$E/p1024.rt" | tr -d ' ')
    me=$(grep -a -c -i -E 'ggml_metal[a-z_]*: *error|failed to (create|initiali[sz]e|init)[a-z ]*metal|metal[a-z ]*not supported|no metal device' "$E/p1024.rt")
    # matched     = llama.cpp logged a ggml_metal init line AND a model buffer line that names MTL/Metal.
    # not-matched = a model buffer line exists and names only the CPU, OR the Metal init logged an explicit error.
    # unknown     = everything else (no runtime log, server-only text, no model buffer line): NOT a claim either way.
    if [ "$mi" -gt 0 ] && [ "$mb" = MTL0 ]; then g=matched; why=metal-init+metal-model-buffer
    elif [ "$mb" = CPU ]; then g=not-matched; why=model-buffer-cpu-only
    elif [ "$me" -gt 0 ]; then g=not-matched; why=metal-init-error
    else g=unknown; why=$([ "$rb" -lt 50 ] && echo no-runtime-log || echo no-model-buffer-line); fi
    # Metal working-set budget: does the guest's Metal device look like a 16 GB Apple Silicon Mac's?
    rm=$(grep '^RTSUM' "$K/p1024.rtg" | tr ' ' '\n' | sed -n 's/^rmws_mb=//p'); bud=unknown; rg=none
    if [ -n "$rm" ] && [ "$rm" != none ]; then
      rg=$(awk -v m="$rm" 'BEGIN {printf "%.2f", m * 1e6 / 1073741824}')
      bud=$(awk -v g="$rg" -v lo="$RMWS_LO_GIB" -v hi="$RMWS_HI_GIB" 'BEGIN {print (g >= lo && g <= hi) ? "matched-16gb" : "not-16gb"}')
    fi
    echo "METALGATE metal=$g why=$why metal_lines=$mi metal_err_lines=$me model_buf=${mb:-unknown} rmws_mb=${rm:-none} rmws_gib=$rg metal_budget=$bud (16 GB ref 10.67 GiB, band $RMWS_LO_GIB-$RMWS_HI_GIB) runtime_log_bytes=$rb"
    grep '^RTSUM' "$K/p1024.rtg"; gmem "$t0" "$(date +%s)" p1024
    node "$JH" unloadall "$API"
    grep '^RTL' "$K/p1024.rtg" ;;
  proxy-start)
    echo 0 > "$K/proxy.mode"; touch "$E/proxy.jsonl"
    alive "$K/proxy.pid" || detach "$E/proxy.stdout.txt" "$K/proxy.pid" node "$JH" proxy "$PXP" 1234 "$E/proxy.jsonl" "$K/proxy.mode"
    up=no; for i in $(seq 1 15); do curl -s -m 5 "http://127.0.0.1:$PXP/api/v1/models" > /dev/null 2>&1 && { up=yes; break; }; sleep 1; done
    echo "PROXYUP up=$up pid=$(cat "$K/proxy.pid") listen=$(lsof -nP -iTCP:$PXP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | head -n 1)"
    [ "$up" = yes ] || { echo "BLOCKED proxy reason=not-up"; exit 4; } ;;
  cell)
    T=$1; VER=$2; CAT=$3; WS=$4; MAXFWD=$5; KEY=$(cat "$K/key"); L=$(lmsbin)
    alive "$K/proxy.pid" || { echo "BLOCKED $T reason=proxy-dead"; exit 4; }
    alive "$K/wd.pid" || { echo "BLOCKED $T reason=watchdog-dead"; exit 4; }
    cur=$(openclaw --version 2>/dev/null | tail -n 1); irc=skip
    case "$cur" in *"$VER"*) ;; *) { tmo 1200 npm install -g "openclaw@$VER" --no-fund --no-audit; echo "rc=$?"; } > "$E/$T.install.txt" 2>&1; irc=$(sed -n 's/^rc=//p' "$E/$T.install.txt" | tail -n 1) ;; esac
    now=$(openclaw --version 2>/dev/null | tail -n 1 | one)
    echo "INSTALL $T want=$VER rc=$irc version=$now"
    case "$now" in *"$VER"*) ;; *) echo "BLOCKED $T reason=wrong-openclaw-version"; exit 5 ;; esac
    case "$VER" in 2026.11.3) EI=$OC_113_INT ES=$OC_113_SHA1 MF=$OC_113_MF AD=$OC_113_AD ;; 2026.11.4) EI=$OC_114_INT ES=$OC_114_SHA1 MF=$OC_114_MF AD=$OC_114_AD ;; *) EI=- ES=- MF="- -" AD="- -" ;; esac
    ni=$(tmo 60 npm view "openclaw@$VER" dist.integrity 2>/dev/null | tail -n 1 | tr -d ' '); ns=$(tmo 60 npm view "openclaw@$VER" dist.shasum 2>/dev/null | tail -n 1 | tr -d ' ')
    DD=$(npm prefix -g)/lib/node_modules/openclaw/dist
    mh=$(sha "$DD/${MF%% *}" 2>/dev/null); ah=$(sha "$DD/${AD%% *}" 2>/dev/null)
    io=no; [ "$mh" = "${MF##* }" ] && [ "$ah" = "${AD##* }" ] && io=yes
    echo "INTEGRITY $T version=$VER installed_ok=$io dist_models_fetch=$([ "$mh" = "${MF##* }" ] && echo match || echo "mismatch:${mh:-missing}") dist_lmstudio_adapter=$([ "$ah" = "${AD##* }" ] && echo match || echo "mismatch:${ah:-missing}") npm_integrity=$([ "$ni" = "$EI" ] && echo match || echo "mismatch:${ni:-none}") npm_shasum=$([ "$ns" = "$ES" ] && echo match || echo "mismatch:${ns:-none}") (installed_ok=no = premise changed: not the package the Maintainer read)"
    H=$K/h-$T; rm -rf "$H"; mkdir -p "$H/.openclaw"
    export OPENCLAW_HOME=$H OPENCLAW_STATE_DIR=$H/.openclaw OPENCLAW_CONFIG_PATH=$H/.openclaw/openclaw.json
    node "$JH" cfg "$OPENCLAW_CONFIG_PATH" "$KEY" "$CAT" "http://127.0.0.1:$PXP/v1" "$K/$WS"
    cp "$OPENCLAW_CONFIG_PATH" "$E/$T.config.json"; echo "$MAXFWD" > "$K/proxy.mode"
    node "$JH" unloadall "$API" | sed "s/^/PRE /" | tee "$K/$T.pre"
    grep -q 'remaining=0$' "$K/$T.pre" || { echo "0" > "$K/proxy.mode"; echo "BLOCKED $T reason=instances-still-loaded"; exit 4; }
    PXFROM=$(wc -l < "$E/proxy.jsonl" | tr -d ' '); logmark "$T"; t0=$(date +%s)
    echo "CELLSTART $T t0=$t0 catalog=$CAT ws=$WS maxfwd=$MAXFWD proxy_from_line=$PXFROM"
    echo "RUN $T gateway_status rc=$(oc "$E/$T.gateway.txt" 60 gateway status) first=$(grep -v '^+' "$E/$T.gateway.txt" | head -n 2 | one 160)"
    echo "RUN $T reset rc=$(oc "$E/$T.reset.txt" 180 memory reset --yes)"
    PXI0=$(wc -l < "$E/proxy.jsonl" | tr -d ' ')
    s0=$(date +%s); irc=$(OPENCLAW_DEBUG_MEMORY_EMBEDDINGS=1 oc "$E/$T.index.txt" 900 memory index --force --verbose)
    PXI1=$(wc -l < "$E/proxy.jsonl" | tr -d ' ')
    echo "RUN $T index rc=$irc secs=$(( $(date +%s) - s0 )) proxy_lines=$PXI0-$PXI1"
    echo "RUN $T status rc=$(oc "$E/$T.status.json.txt" 300 memory status --deep --json)"
    if [ "$irc" = 0 ] || [ "$CAT" != none ]; then
      while IFS="$(printf '\t')" read -r q qf qt; do
        echo "RUN $T search-$q rc=$(oc "$E/$T.search.$q.txt" 180 memory search --query "$qt" --max-results 6 --min-score 0 --json)"
      done < "$K/queries.tsv"
    else echo "RUN $T searches skipped reason=index-failed-without-catalog (avoids further large preload attempts)"; fi
    t1=$(date +%s)
    node "$JH" models "$API" "$E/$T.models-after.json" > "$K/$T.models.out"
    tmo 60 "$L" ps > "$E/$T.lms-ps.txt" 2>&1; tmo 60 "$L" ps --json > "$E/$T.lms-ps.json.txt" 2>&1
    INST=$(sed -n 's/^LOADED n=[1-9][0-9]* \([^ ]*\).*/\1/p' "$K/$T.models.out" | cut -d'|' -f2)
    [ "$CAT" != none ] && [ -n "$INST" ] && node "$JH" probe "$API" "$INST" "$K/alt.txt" "insitu-$T" > "$K/$T.probe.out" 2>&1
    sleep 2; logslice "$T" "$E/$T.rt"
    # ---- verdict lines (before any raw dump)
    echo "CELLEND $T t1=$t1 secs=$((t1 - t0))"
    grep '^LOADED' "$K/$T.models.out" | sed "s/^LOADED/EFF $T/"
    sed "s/^/LMSPS $T /" "$E/$T.lms-ps.txt" | cut -c1-200 | head -n 8
    cat "$K/$T.probe.out" 2>/dev/null
    node "$JH" pxsum "$E/proxy.jsonl" "$PXFROM"
    node "$JH" pxidx "$E/proxy.jsonl" "$PXI0" "$PXI1" "$T"
    rtgrep "$E/$T.rt" "$T" | grep '^RTSUM'
    gmem "$t0" "$t1" "$T"
    [ -f "$E/BOUNDED_REJECT" ] && echo "BOUNDED $(cat "$E/BOUNDED_REJECT" | head -n 1)"
    ok=$(grep -m1 -o 'Memory index updated[^.]*\.' "$E/$T.index.txt" | one 160); fl=$(grep -m1 'Memory index failed' "$E/$T.index.txt" | one 400)
    ww=$(cat "$E/$T".*.txt | grep -c 'lmstudio embeddings warmup failed')
    echo "INDEX $T rc=$irc updated=${ok:--} warmup_warn=$ww chunks_vec_warn=$(grep -c 'chunks_vec not updated' "$E/$T.index.txt") failed=${fl:--}"
    node "$JH" status "$E/$T.status.json.txt" | sed "s/^STATUSJ/STATUSJ $T/"
    while IFS="$(printf '\t')" read -r q qf qt; do [ -f "$E/$T.search.$q.txt" ] && node "$JH" search "$E/$T.search.$q.txt" "$q"; done < "$K/queries.tsv"
    node "$JH" unloadall "$API" | sed "s/^/POST /"; echo 0 > "$K/proxy.mode"
    # ---- raw tails
    rtgrep "$E/$T.rt" "$T" | grep '^RTL' | head -n 60
    echo "--- tail $T index"; grep -v '^ *$' "$E/$T.index.txt" | tail -n 40 | cut -c1-400
    echo "--- grep $T warmup"; cat "$E/$T".*.txt | grep -i 'warmup\|lmstudio' | head -n 20 | cut -c1-400 ;;
  pack)
    rm -f "$K/ev-$1.tgz"; tar -czf "$K/ev-$1.tgz" -C "$K" ev
    echo "PACK $1 rc=$? sha256=$(sha "$K/ev-$1.tgz") bytes=$(stat -f %z "$K/ev-$1.tgz")" ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
echo "STEP $step end=$(ts)"
