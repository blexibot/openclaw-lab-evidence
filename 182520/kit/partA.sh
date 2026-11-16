#!/bin/bash
# partA.sh KITDIR OUTDIR : #182520 Part A, the core local-service lifecycle with a deterministic stand-in server.
# Runs INSIDE the Linux bench as root. Three cases, each with its own fresh OPENCLAW_HOME:
#   solo     managed (localService), one CLI, a 90 s request              -> control: managed path works at all
#   overlap  managed, owner CLI (40 s request) starts the server, borrower CLI (90 s request) starts once it is
#            healthy; the owner exits while the borrower's request is in flight  -> the bug shape
#   external no localService; the kit starts the server itself; same two CLIs  -> control: shared server is fine
# Prints A_* lines; key lines also go to OUTDIR/A/summary.txt; last line is RESULT_A. Synthetic content only.
set -u
K=${1:-/root/kit}; OUT=${2:-/root/t182520/out}; O=$OUT/A; mkdir -p "$O"; : > "$O/summary.txt"
for d in "$HOME/.npm-global/bin" /usr/local/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done; export PATH
NODE=$(command -v node); PORT=18555; URL=http://127.0.0.1:$PORT/v1/models
ts() { date -u +%FT%TZ; }
say() { echo "$*"; echo "$*" >> "$O/summary.txt"; }
snap() { echo "--- procs $1 $(ts)"; node "$K/procs.mjs" 'slowllm\.mjs'; }
say "A_START $(ts) openclaw=$(openclaw --version 2>&1 | tail -1) node=$($NODE --version) arch=$(uname -m)"

# start_cli NAME ROLE DELAY : one `infer model run --local` in the background; sets CLIPID. Output files in $O.
start_cli() {
  local name=$1 role=$2 delay=$3
  date +%s > "$O/$name-$role.start"
  ( timeout 300 openclaw infer model run --local --model stub/slow \
      --prompt "Lab check. DELAY=$delay TAG=$role" --json > "$O/$name-$role.out" 2> "$O/$name-$role.err"
    echo "rc=$? end=$(date +%s)" > "$O/$name-$role.rc" ) &
  CLIPID=$!
  echo "A_${name}_${role}_STARTED pid=$CLIPID $(ts) delay=$delay"
}
cli_line() { # NAME ROLE DELAY -> one summary line plus up to 3 error lines
  local name=$1 role=$2 delay=$3 s e rc
  s=$(cat "$O/$name-$role.start" 2>/dev/null)
  rc=$(sed -n 's/^rc=\([0-9]*\).*/\1/p' "$O/$name-$role.rc" 2>/dev/null)
  e=$(sed -n 's/.*end=\([0-9]*\).*/\1/p' "$O/$name-$role.rc" 2>/dev/null)
  say "A_${name}_${role} rc=${rc:-none} secs=$(( ${e:-0} - ${s:-0} )) done=$(grep -c "STUB_DONE_$delay" "$O/$name-$role.out" 2>/dev/null)"
  grep -h -m3 -iE 'UND_ERR|socket|other side closed|terminated|ECONN|fetch failed|error|failed' \
    "$O/$name-$role.err" "$O/$name-$role.out" 2>/dev/null | cut -c1-300 | sed "s/^/A_${name}_${role}_ERRLINE /"
}

run_case() { # NAME MANAGED(0|1)
  local name=$1 managed=$2 H=${BASE:-/root/t182520}/A-$1 LOG=$O/$1-stub.log P1= P2= EXT=
  echo "=== case $name managed=$managed $(ts)"
  if [ -e "$H" ]; then say "A_${name}_STOP $H already exists (use a fresh bench)"; return 1; fi
  export OPENCLAW_HOME=$H; mkdir -p "$H/ws"; : > "$LOG"
  node "$K/cfg.mjs" stub "$H/.openclaw/openclaw.json" "$PORT" "$managed" "$NODE" "$K" "$LOG" "$H/ws"
  if node "$K/hc.mjs" "$URL" 0; then say "A_${name}_STOP port $PORT already answers"; snap busy; return 1; fi
  if [ "$managed" = 0 ]; then
    setsid nohup "$NODE" "$K/slowllm.mjs" "$PORT" "$LOG" > /dev/null 2>&1 < /dev/null &
    EXT=$!; node "$K/hc.mjs" "$URL" 20
  fi
  if [ "$name" = solo ]; then
    start_cli "$name" borrower 90; P2=$CLIPID
    sleep 10; snap "solo+10s"
    wait "$P2"; cli_line "$name" borrower 90
  else
    start_cli "$name" owner 40; P1=$CLIPID
    node "$K/hc.mjs" "$URL" 90; snap "owner-ready"
    sleep 2
    start_cli "$name" borrower 90; P2=$CLIPID
    sleep 10; snap "borrower+10s"
    wait "$P1"; echo "A_${name}_OWNER_EXITED $(ts)"; sleep 1; snap "owner-exited+1s"
    wait "$P2"; echo "A_${name}_BORROWER_EXITED $(ts)"; snap "borrower-exited"
    cli_line "$name" owner 40; cli_line "$name" borrower 90
    say "A_${name}_PIDS owner_cli=$P1 borrower_cli=$P2"
  fi
  node "$K/hc.mjs" "$URL" 0 | sed "s/^/A_${name}_AFTER /"
  [ -n "$EXT" ] && kill "$EXT" 2>/dev/null
  # Anything of ours still listening is stopped so the next case starts clean (and recorded).
  for p in $(node "$K/procs.mjs" 'slowllm\.mjs' | sed -n 's/^pid=\([0-9]*\).*/\1/p'); do say "A_${name}_CLEANUP kill $p"; kill "$p"; done
  sleep 1
  echo "--- stub log $name"; cat "$LOG"
  local own bor bpid bid
  own=$(grep -m1 'REQ start .*tag=owner' "$LOG" | sed -n 's/.* pid=\([0-9]*\) .*/\1/p')
  bor=$(grep -m1 'REQ start .*tag=borrower' "$LOG")
  bpid=$(echo "$bor" | sed -n 's/.* pid=\([0-9]*\) .*/\1/p'); bid=$(echo "$bor" | sed -n 's/.* id=\([0-9]*\) .*/\1/p')
  say "A_${name}_STUB servers_started=$(grep -c 'STUB start' "$LOG") owner_req_pid=${own:-none}" \
    "borrower_first_req_pid=${bpid:-none} first_req_ended=$(grep -c "pid=${bpid:-x} REQ end id=${bid:-x} tag=borrower" "$LOG")" \
    "first_req_client_closed=$(grep -c "pid=${bpid:-x} REQ client-closed id=${bid:-x} tag=borrower" "$LOG")" \
    "borrower_req_starts=$(grep -c 'REQ start .*tag=borrower' "$LOG")"
}

run_case solo 1
run_case overlap 1
run_case external 0

# ---- verdict (rules are in the ticket; this only applies them) ----
S=$O/summary.txt
g() { sed -n "s/^$1 .*$2=\([^ ]*\).*/\1/p" "$S" | head -1; }
solo_ok=no;  [ "$(g A_solo_borrower rc)" = 0 ] && [ "$(g A_solo_borrower done)" -ge 1 ] 2>/dev/null && solo_ok=yes
ext_ok=no;   [ "$(g A_external_owner rc)" = 0 ] && [ "$(g A_external_owner done)" -ge 1 ] 2>/dev/null \
  && [ "$(g A_external_borrower rc)" = 0 ] && [ "$(g A_external_borrower done)" -ge 1 ] 2>/dev/null && ext_ok=yes
owner_ok=no; [ "$(g A_overlap_owner rc)" = 0 ] && [ "$(g A_overlap_owner done)" -ge 1 ] 2>/dev/null && owner_ok=yes
own=$(g A_overlap_STUB owner_req_pid); bpid=$(g A_overlap_STUB borrower_first_req_pid)
ended=$(g A_overlap_STUB first_req_ended); closed=$(g A_overlap_STUB first_req_client_closed)
starts=$(g A_overlap_STUB borrower_req_starts); brc=$(g A_overlap_borrower rc); bdone=$(g A_overlap_borrower done)
reused=no; [ -n "$own" ] && [ "$own" != none ] && [ "$own" = "$bpid" ] && reused=yes
killed=no; [ "$reused" = yes ] && [ "$ended" = 0 ] && [ "$closed" = 0 ] && killed=yes
after="borrower rc=$brc"; [ "$brc" = 0 ] && [ "${bdone:-0}" -ge 1 ] && [ "${starts:-0}" -ge 2 ] && after="borrower recovered by a retry on a new server (rc=0)"
if [ "$solo_ok" != yes ]; then R="blocked"; WHY="solo control failed: the managed stand-in did not answer through infer --local"
elif [ "$reused" != yes ]; then R="inconclusive"; WHY="borrower did not reuse the owner's server (own=$own borrower=$bpid)"
elif [ "$killed" = yes ] && [ "$ext_ok" = yes ] && [ "$owner_ok" = yes ]; then R="reproduced"; WHY="owner exit killed the server under the borrower's in-flight request; $after"
elif [ "$ended" = 1 ] && [ "$brc" = 0 ] && [ "$ext_ok" = yes ]; then R="not reproduced"; WHY="borrower's request finished on the owner's server"
else R="inconclusive"; WHY="solo=$solo_ok external=$ext_ok owner=$owner_ok reused=$reused ended=$ended client_closed=$closed borrower_rc=$brc"
fi
say "A_FACTS solo_ok=$solo_ok external_ok=$ext_ok owner_ok=$owner_ok reused=$reused killed_inflight=$killed"
say "RESULT_A=$R ($WHY)"
echo "A_END $(ts)"
