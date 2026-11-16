#!/bin/bash
# partB.sh KITDIR OUTDIR : #182520 Part B, the reporter's shape: the official managed llama.cpp provider with local
# memory embeddings (embedding-only setup, CPU, EmbeddingGemma ~0.3 GB downloaded inside this bench), and two CLI
# `memory index` processes. The owner CLI starts the managed llama-server; the borrower CLI starts once it is healthy
# (so it reuses it); the owner finishes and exits while the borrower is still indexing.
# Runs INSIDE the Linux bench as root. Prints B_* lines; key lines also go to OUTDIR/B/summary.txt; the last is
# RESULT_B. Synthetic content only (corpus.mjs). One fresh OPENCLAW_HOME: /root/t182520/B.
set -u
K=${1:-/root/kit}; OUT=${2:-/root/t182520/out}; O=$OUT/B; mkdir -p "$O"; : > "$O/summary.txt"
for d in "$HOME/.npm-global/bin" /usr/local/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done; export PATH
PLUGIN=${PLUGIN:-@openclaw/llama-cpp-provider@2026.11.4}
H=${BASE:-/root/t182520}/B; export OPENCLAW_HOME=$H; CFG=$H/.openclaw/openclaw.json
ts() { date -u +%FT%TZ; }
say() { echo "$*"; echo "$*" >> "$O/summary.txt"; }
red() { sed -E 's/(token|apiKey|password|secret|authorization)("?[[:space:]]*[:=][[:space:]]*"?)[^",[:space:]}]+/\1\2<redacted>/Ig'; }
LS='llama-server'
snap() { echo "--- procs $1 $(ts)"; node "$K/procs.mjs" "$LS"; }
finish() { say "RESULT_B=$1 ($2)"; echo "B_END $(ts)"; exit 0; }
step() { # NAME TIMEOUT CMD... : run, capture redacted output to $O/NAME.txt, say rc and seconds
  local name=$1 to=$2 t0 rc; shift 2; t0=$(date +%s)
  echo "=== $name $(ts): $*"
  timeout "$to" "$@" > "$O/$name.raw" 2>&1; rc=$?
  red < "$O/$name.raw" > "$O/$name.txt"; rm -f "$O/$name.raw"
  tail -40 "$O/$name.txt"
  say "B_STEP $name rc=$rc secs=$(( $(date +%s) - t0 ))"
  return $rc
}

if [ -e "$H" ]; then finish blocked "$H already exists (use a fresh bench)"; fi
mkdir -p "$H"
say "B_START $(ts) openclaw=$(openclaw --version 2>&1 | tail -1) node=$(node --version) arch=$(uname -m) nproc=$(nproc)"
say "B_HOST mem_kb=$(sed -n 's/^MemTotal: *\([0-9]*\).*/\1/p' /proc/meminfo) glibc=$(ldd --version 2>&1 | head -1 | awk '{print $NF}') disk_free=$(df -h /root | awk 'NR==2{print $4}')"
for u in https://huggingface.co https://github.com https://registry.npmjs.org; do
  say "B_EGRESS $u http=$(curl -s -o /dev/null -w '%{http_code}' -m 20 "$u" 2>/dev/null || echo fail)"
done

# B1 plugin
if ! step b1-plugin-install 900 openclaw plugins install "$PLUGIN"; then
  if grep -qi capabilit "$O/b1-plugin-install.txt"; then
    step b1-plugin-install-accept 900 openclaw plugins install "$PLUGIN" --accept-capabilities \
      || finish blocked "plugin install failed (see b1-plugin-install-accept.txt)"
  else finish blocked "plugin install failed (see b1-plugin-install.txt)"; fi
fi
step b1-plugin-list 120 openclaw plugins list
grep -i llama "$O/b1-plugin-list.txt" | head -3 | sed 's/^/B_PLUGIN /'

# B2 memory settings (as the reporter: local provider, no fallback; cache off so reruns embed again)
step b2-set-provider 120 openclaw config set memory.search.provider local
step b2-set-fallback 120 openclaw config set memory.search.fallback none
step b2-set-cache 120 openclaw config set memory.search.cache.enabled false || say "B_NOTE cache.enabled not set; corpora are salted per run anyway"

# B3 embedding-only managed setup (downloads the pinned llama.cpp build and EmbeddingGemma)
step b3-onboard 1800 openclaw onboard --non-interactive --accept-risk --skip-health \
  --auth-choice llama-cpp --llama-cpp-embedding-only || finish blocked "embedding-only onboarding failed (see b3-onboard.txt)"
node "$K/cfg.mjs" dump "$CFG" | red > "$O/b3-config.json"; cat "$O/b3-config.json"
HURL=$(node "$K/cfg.mjs" health "$CFG") || finish blocked "no models.providers.llama-cpp.localService after onboarding"
say "B_HEALTH_URL $HURL"
# clear_server LABEL : the experiments need "no server up" before an owner starts. If one still answers, record it,
# give it 20 s to go, then stop the llama-server processes (throwaway bench; recorded as B_NOTE lines).
clear_server() {
  node "$K/hc.mjs" "$HURL" 0 > /dev/null || return 0
  say "B_NOTE $1: a server still answers with no OpenClaw command running"; snap "$1"
  sleep 20; node "$K/hc.mjs" "$HURL" 0 > /dev/null || return 0
  for p in $(node "$K/procs.mjs" "$LS" | sed -n 's/^pid=\([0-9]*\).*/\1/p'); do say "B_NOTE $1: kill $p"; kill "$p" 2>/dev/null; done
  sleep 3; node "$K/hc.mjs" "$HURL" 0 > /dev/null && finish blocked "$1: a server keeps answering after its processes were stopped"
  return 0
}
snap after-onboard
clear_server after-onboard

# B4 two agents with their own workspaces (same global memory settings, same managed service)
for a in owner borrower; do
  step "b4-agent-$a" 300 openclaw agents add "$a" --workspace "$H/ws-$a" --non-interactive \
    || { node "$K/cfg.mjs" set "$CFG" "agents.entries.$a" "{\"workspace\":\"$H/ws-$a\"}"; say "B_NOTE agents add $a failed; config fallback used"; }
  mkdir -p "$H/ws-$a/memory"
done
step b4-status-owner 900 openclaw memory status --deep --agent owner --json
clear_server after-status

# wait_ready PID MAXSECS : probe the health URL once a second until it answers, PID exits, or MAXSECS pass
wait_ready() {
  local pid=$1 max=$2 t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "$max" ]; do
    if node "$K/hc.mjs" "$HURL" 0 > /dev/null; then echo "READY after $(( $(date +%s) - t0 ))s"; return 0; fi
    kill -0 "$pid" 2>/dev/null || { echo "NOTREADY process $pid exited after $(( $(date +%s) - t0 ))s"; return 1; }
    sleep 1
  done
  echo "NOTREADY after ${max}s"; return 1
}

# run_index ROLE NFILES SALT TAG : start `memory index --force` for agent ROLE in the background; sets IPID
run_index() {
  local role=$1 n=$2 salt=$3 tag=$4
  node "$K/corpus.mjs" "$H/ws-$role/memory" "$n" "$salt" 900 | sed "s/^/B_${tag}_/"
  date +%s > "$O/$tag-$role.start"
  ( OPENCLAW_DEBUG_MEMORY_EMBEDDINGS=1 timeout 1500 openclaw memory index --agent "$role" --force --verbose \
      > "$O/$tag-$role.raw" 2>&1
    echo "rc=$? end=$(date +%s)" > "$O/$tag-$role.rc" ) &
  IPID=$!
  echo "B_${tag}_${role}_STARTED pid=$IPID $(ts) files=$n"
}
idx_line() { # TAG ROLE -> rc, secs, error lines
  local tag=$1 role=$2 s e rc
  red < "$O/$tag-$role.raw" > "$O/$tag-$role.txt"; rm -f "$O/$tag-$role.raw"
  s=$(cat "$O/$tag-$role.start"); rc=$(sed -n 's/^rc=\([0-9]*\).*/\1/p' "$O/$tag-$role.rc")
  e=$(sed -n 's/.*end=\([0-9]*\).*/\1/p' "$O/$tag-$role.rc")
  say "B_${tag}_${role} rc=${rc:-none} secs=$(( ${e:-0} - s )) start=$s end=${e:-0}" \
    "errlines=$(grep -ciE 'UND_ERR|other side closed|ECONNRESET|ECONNREFUSED|fetch failed|terminated|socket hang up|retry|exited|failed|error' "$O/$tag-$role.txt")"
  grep -m8 -iE 'UND_ERR|other side closed|ECONNRESET|ECONNREFUSED|fetch failed|terminated|socket hang up|retry|exited|failed|error' \
    "$O/$tag-$role.txt" | cut -c1-300 | sed "s/^/B_${tag}_${role}_ERRLINE /" | tee -a "$O/summary.txt"
}

# B5 calibration: the borrower alone (also the no-overlap control)
NCAL=${NCAL:-40}
run_index borrower "$NCAL" "cal-$RANDOM$RANDOM" cal; P=$IPID
RDY=$(wait_ready "$P" 900); echo "B_CAL_$RDY"; snap cal-ready
wait "$P"; idx_line cal borrower
CRC=$(sed -n 's/^rc=\([0-9]*\).*/\1/p' "$O/cal-borrower.rc")
[ "$CRC" = 0 ] || finish blocked "calibration index (borrower alone) failed rc=$CRC; see cal-borrower.txt"
TCAL=$(( $(sed -n 's/.*end=\([0-9]*\).*/\1/p' "$O/cal-borrower.rc") - $(cat "$O/cal-borrower.start") ))
RS=$(echo "$RDY" | sed -n 's/^READY after \([0-9]*\)s.*/\1/p'); RS=${RS:-0}
PERFILE=$(awk -v t="$TCAL" -v r="$RS" -v n="$NCAL" 'BEGIN{x=(t-r)/n; if (x<0.01) x=0.01; printf "%.3f", x}')
NO=$(awk -v c="$PERFILE" 'BEGIN{n=int(30/c)+1; if(n<8)n=8; if(n>3000)n=3000; print n}')
NB=$(awk -v c="$PERFILE" -v o="$NO" 'BEGIN{n=int(240/c)+1; if(n<4*o)n=4*o; if(n>6000)n=6000; print n}')
say "B_CAL total_secs=$TCAL ready_secs=$RS secs_per_file=$PERFILE -> owner_files=$NO borrower_files=$NB"
clear_server after-calibration

# B6 overlap attempts (a second attempt only when the first could not create the overlap)
RES=; WHY=
for k in 1 2; do
  T=ov$k
  echo "=== overlap attempt $k $(ts)"
  clear_server "before-$T"
  run_index owner "$NO" "o$k-$RANDOM$RANDOM" "$T"; P1=$IPID
  echo "B_${T}_OWNER_$(wait_ready "$P1" 900)"; snap "$T-owner-ready"
  sleep 2
  run_index borrower "$NB" "b$k-$RANDOM$RANDOM" "$T"; P2=$IPID; B2S=$(date +%s)
  ( while kill -0 "$P2" 2>/dev/null; do
      echo "t=$(( $(date +%s) - B2S )) owner_alive=$(kill -0 "$P1" 2>/dev/null && echo 1 || echo 0)"
      node "$K/procs.mjs" "$LS"; sleep 1
    done ) > "$O/$T-monitor.txt" 2>&1 &
  MON=$!
  wait "$P1"; P1E=$(date +%s); echo "B_${T}_OWNER_EXITED $(ts)"
  wait "$P2"; P2E=$(date +%s); echo "B_${T}_BORROWER_EXITED $(ts)"
  wait "$MON" 2>/dev/null
  idx_line "$T" owner; idx_line "$T" borrower
  step "$T-status-borrower" 900 openclaw memory status --deep --agent borrower --json
  # Who owned the llama-server processes, from the monitor (chain = parent chain, comma-wrapped).
  M=$O/$T-monitor.txt
  first=$(awk '/^t=/{ if (got) exit; inblk=(substr($1,3)+0 >= 3); if (inblk) got=1; next } inblk && /^pid=/{print}' "$M")
  srv_owner_first=$(echo "$first" | grep -c ",$P1,"); srv_borrower_first=$(echo "$first" | grep -c ",$P2,")
  respawn=$(grep -c ",$P2," "$M")
  reused=no; [ "$srv_owner_first" -ge 1 ] && [ "$srv_borrower_first" = 0 ] && reused=yes
  # Overlap = the borrower started before the owner exited and was still running when it exited. The end times come
  # from the .rc files (each written the moment its process ended; whole seconds), so a borrower that dies in the same
  # second as the owner (the bug's fast-failure shape) still counts. (P2E is taken after `wait P1`, so it can't be used.)
  oend=$(sed -n 's/.*end=\([0-9]*\).*/\1/p' "$O/$T-owner.rc"); bend=$(sed -n 's/.*end=\([0-9]*\).*/\1/p' "$O/$T-borrower.rc")
  overlap=no; [ "$B2S" -lt "${oend:-0}" ] && [ "${bend:-0}" -ge "${oend:-0}" ] && overlap=yes
  ownerdead=$(grep -c 'owner_alive=0' "$M")
  brc=$(sed -n 's/^rc=\([0-9]*\).*/\1/p' "$O/$T-borrower.rc"); orc=$(sed -n 's/^rc=\([0-9]*\).*/\1/p' "$O/$T-owner.rc")
  berr=$(grep -ciE 'UND_ERR|other side closed|ECONNRESET|ECONNREFUSED|fetch failed|terminated|socket hang up' "$O/$T-borrower.txt")
  bretry=$(grep -ciE 'retry' "$O/$T-borrower.txt")
  say "B_${T}_FACTS owner_rc=$orc borrower_rc=$brc reused=$reused overlap=$overlap owner_exit_to_borrower_exit_secs=$(( ${bend:-0} - ${oend:-0} ))" \
    "monitor_samples_owner_gone=$ownerdead" \
    "first_sample_servers_under_owner=$srv_owner_first first_sample_servers_under_borrower=$srv_borrower_first" \
    "monitor_lines_server_under_borrower=$respawn borrower_transport_err_lines=$berr borrower_retry_lines=$bretry"
  if [ "$reused" = yes ] && [ "$overlap" = yes ]; then
    if [ "$berr" -gt 0 ] || [ "$respawn" -gt 0 ]; then
      RES=reproduced
      WHY="owner exit stopped the server the borrower was using; borrower rc=$brc, transport-error lines=$berr, retry lines=$bretry, borrower started its own server afterwards=$([ "$respawn" -gt 0 ] && echo yes || echo no)"
    elif [ "$brc" != 0 ]; then
      RES=inconclusive; WHY="borrower failed (rc=$brc) without a transport error or a new server; see its ERRLINEs"
    else
      RES="not reproduced"; WHY="borrower reused the owner's server, outlived the owner by $(( ${bend:-0} - ${oend:-0} )) s, rc=0, no transport error, no new server"
    fi
    break
  fi
  RES=inconclusive; WHY="attempt $k: reused=$reused overlap=$overlap (see B_${T}_FACTS)"
  NO=$(( NO * 2 )); NB=$(( NB * 2 ))
done
finish "$RES" "$WHY"
