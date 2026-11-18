#!/bin/bash
# d198830.sh (<LAB-HOST>, as <LAB-USER>; started detached by s198830.sh with J, HARD_STOP_EPOCH, ALLOW_TART_SET and MODE):
# T198830, openclaw/openclaw#198830 (LM Studio embedding preload asks for the model's max context). One disposable
# macOS bench (t198830-mac, 4 vCPU, exactly 16 GiB) runs LM Studio, a recording proxy and OpenClaw, all on the guest's
# loopback. The host supervisor (h198830.sh, separate process) guards host memory and may kill the VM at any time.
# This script is the CONTROLLER: it makes the nonces and the synthetic corpus, computes the expected file/chunk counts,
# and turns the guest's raw lines into CELL / SUMMARY / RESULT_SUGGESTED lines (verdicts.txt), before any raw dump.
# MODE=qualify: boot the bench, prove the supervisor sees it, force one supervisor stop (sup.force), prove the kill and
# the recovery, destroy, print QUALIFY. MODE=run (default): the experiment.
# Every guest call is bounded on the host (hx: own process group, killed whole at its budget or the moment the
# supervisor stops the VM). TERM/INT/HUP/EXIT always run the teardown (stop live tails, last pull, destroy only a VM this
# run created, NO_LEFTOVER, driver.done, summary).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); J=${J:?}; HSE=${HARD_STOP_EPOCH:?}; OUT=$J/out; mkdir -p "$OUT"
ALLOW_TART_SET=${ALLOW_TART_SET:-0}; MODE=${MODE:-run}
BENCH=/usr/local/bin/bench; TART=$HOME/.local/bin/tart; VM=t198830-mac; GK='~/k198830'; PY="/usr/bin/python3 -I"
# Offline test hooks only (the Maintainer's stub run). Never set these in the lab.
[ -n "${D198830_TEST_BENCH:-}" ] && BENCH=$D198830_TEST_BENCH; [ -n "${D198830_TEST_TART:-}" ] && TART=$D198830_TEST_TART
[ -n "${D198830_TEST_PY:-}" ] && PY=$D198830_TEST_PY
ts() { date -u +%FT%TZ; }
V() { echo "V198830 $(ts) $*" | tee -a "$J/verdicts.txt"; }
left() { echo $(( (HSE - $(date -u +%s)) / 60 )); }
need() { [ "$(left)" -ge "$1" ] || { V "SKIP $2 reason=time-box left_min=$(left) need_min=$1"; return 1; }; }
nonce() { od -An -tx1 -N8 /dev/urandom | tr -d ' \n'; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
kv() { grep -m1 "^$1" "$2" 2>/dev/null | tr ' ' '\n' | sed -n "s/^$3=//p" | head -n 1; }
hx() { # hx <secs> <stopfile|-> <cmd...>: own process group; the whole group is killed at <secs> (rc 124) or as soon as
  # <stopfile> exists (rc 125). TERM/INT/HUP to hx kill the group too. Covers ssh hanging after a VM kill.
  /usr/bin/perl -MPOSIX=:sys_wait_h -e '
    my $s = shift; my $stopf = shift; my $pid = fork(); die "fork: $!\n" unless defined $pid;
    if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127; }
    $SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { kill "KILL", -$pid, $pid; exit 143 };
    my $end = time + $s; my $why = 0;
    while (1) {
      my $r = waitpid($pid, WNOHANG); if ($r == $pid) { exit(($? & 127) ? 128 + ($? & 127) : $? >> 8) }
      if (time >= $end) { $why = 124; last } if ($stopf ne "-" && -e $stopf) { $why = 125; last }
      select(undef, undef, undef, 1);
    }
    kill "KILL", -$pid, $pid; waitpid($pid, 0); exit $why;' "$@"
}
budget() { # budget <max secs>: min(max, seconds to the hard stop - 120), at least 60
  local b=$1 r=$(( HSE - $(date -u +%s) - 120 )); [ "$r" -lt "$b" ] && b=$r; [ "$b" -lt 60 ] && b=60; echo "$b"; }
mx() { local b=$1; shift; hx "$b" "$J/SUPERVISOR_STOPPED" "$BENCH" exec "$VM" "$1"; }   # one shell string in the guest's login zsh
mpush() { # mpush <local file> <guest path>: copy by stdin, then prove the bytes with sha256 on both sides
  mx 120 "cat > $2" < "$1"; local g; g=$(mx 60 "shasum -a 256 $2" | cut -d' ' -f1)
  [ "$g" = "$(sha "$1")" ] && return 0
  V "PUSH $(basename "$1") MISMATCH local=$(sha "$1") guest=$g"; return 1
}
gate() { # nothing new starts after a supervisor stop, a halt, the hard stop, or if the supervisor is gone
  [ -f "$J/halt" ] && return 1
  if [ -f "$J/SUPERVISOR_STOPPED" ]; then V "HALT supervisor-stop $(cat "$J/SUPERVISOR_STOPPED")"; touch "$J/halt"; return 1; fi
  kill -0 "$(cat "$J/sup.pid" 2>/dev/null)" 2>/dev/null || { V "HALT supervisor-dead (no host guard; nothing more runs)"; touch "$J/halt"; return 1; }
  [ "$(left)" -ge 2 ] || { V "HALT time-box left_min=$(left)"; touch "$J/halt"; return 1; }
  return 0
}
mrun() { # mrun <outname> <max secs> <guest args...>: one guest step, output to out/m-<outname>.txt, verdict lines to verdicts.txt
  local n=$1 b o="$OUT/m-$1.txt"; b=$(budget "$2"); shift 2
  mx "$b" "STEP_BUDGET=$((b - 30)) bash $GK/m198830.sh $*" > "$o" 2>&1; echo "host-rc=$? host-budget-s=$b" >> "$o"
  grep -E '^(STEP|HW|SW |GPUINFO|GUESTMEM|WD|DMG|APP|LMS|LLMSTER|SERVER|LISTEN|RUNTIME|SETTINGS|LOGSTREAM|GGUF|MODEL|KEY|EST|AFTER_EST|LOADDIRECT|PROBE|METALGATE|RTSUM|GMEM|PROXYUP|INSTALL|INTEGRITY|CFG|CELLSTART|CELLEND|RUN|EFF|PX |PX_|PXIDX|BOUNDED|INDEX|STATUSJ|SEARCHJ|PACK|BLOCKED|REFUSE|P1024|UNLOAD|PRE |POST |host-rc)' "$o" |
    sed "s/^/[m-$n] /" >> "$J/verdicts.txt"
}
mstep() { # mstep <outname> <max secs> <guest args...>: gate, run, classify (0 ok, 2 blocked, 3 bounded reject, 1 halted)
  gate || return 1
  local n=$1 o="$OUT/m-$1.txt" rc; mrun "$@"
  rc=$(sed -n 's/^host-rc=\([0-9]*\).*/\1/p' "$o" | tail -n 1)
  grep -q '^BOUNDED ' "$o" && { V "HALT bounded-reject $(grep -m1 '^BOUNDED ' "$o" | cut -c1-300)"; touch "$J/halt"; return 3; }
  [ -f "$J/SUPERVISOR_STOPPED" ] && { gate; return 1; }
  [ "$rc" = 124 ] && { V "HALT host-timeout step=$n budget_s=$(sed -n 's/.*host-budget-s=//p' "$o" | tail -n 1)"; touch "$J/halt"; return 1; }
  grep -q '^BLOCKED .*reason=instances-still-loaded' "$o" && { V "HALT instances-still-loaded step=$n"; touch "$J/halt"; return 1; }
  grep -q '^BLOCKED' "$o" && return 2
  if [ "$rc" != 0 ] || ! grep -q '^STEP [^ ]* end=' "$o"; then
    V "HALT host-rc=${rc:-none} step=$n (no BLOCKED line, or no 'STEP ... end=' line: the guest step died)"; touch "$J/halt"; return 1
  fi
  return 0
}
pull() { # pull <label>: pack the guest's evidence dir and copy it out (custody before the VM goes away)
  [ -f "$J/SUPERVISOR_STOPPED" ] && return 1
  mrun "pack-$1" 600 pack "$1"; local g; g=$(kv "PACK $1 " "$OUT/m-pack-$1.txt" sha256)
  mx 600 "cat $GK/ev-$1.tgz" > "$J/guest-ev-$1.tgz"
  [ -n "$g" ] && [ "$(sha "$J/guest-ev-$1.tgz")" = "$g" ] && { V "PULL guest-ev-$1.tgz sha256=$g ok"; return 0; }
  V "PULL guest-ev-$1.tgz MISMATCH local=$(sha "$J/guest-ev-$1.tgz") guest=${g:-none}"; return 1
}
LIVEPID=""
live_start() { # live_start <tag>: host-side tail of the guest's proxy log and LM Studio logs into out/live-<tag>.txt
  # (evidence accumulates OUTSIDE the VM while the cell runs; a supervisor kill does not lose the load request/answer)
  /usr/bin/perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' "$BENCH" exec "$VM" \
    "cd $GK/ev && touch proxy.jsonl lms-runtime.log lms-server.log && exec tail -n 0 -F proxy.jsonl lms-runtime.log lms-server.log" \
    > "$OUT/live-$1.txt" 2>&1 < /dev/null &
  LIVEPID=$!; sleep 2
}
live_stop() { [ -n "$LIVEPID" ] || return 0; kill -TERM -- "-$LIVEPID" 2>/dev/null; sleep 1; kill -KILL -- "-$LIVEPID" 2>/dev/null; kill -KILL "$LIVEPID" 2>/dev/null; wait "$LIVEPID" 2>/dev/null; LIVEPID=""; }
vmcfg() { # vmcfg <n>: the bench's Tart config (read-only)
  "$TART" get "$VM" --format json > "$OUT/tart-get-$1.json" 2>&1
  CPU=$(plutil -extract CPU raw -o - "$OUT/tart-get-$1.json" 2>/dev/null); MEM=$(plutil -extract Memory raw -o - "$OUT/tart-get-$1.json" 2>/dev/null)
}
vm_seen() { # vm_seen <since epoch>: wait up to 30 s for a supervisor sample with vm_up=1 taken after <since>
  local i
  for i in $(seq 1 15); do
    awk -F'[:,]' -v t="$1" '$2 >= t && /"vm_up":1/ {f=1} END {exit !f}' "$J/sup.jsonl" 2>/dev/null && return 0; sleep 2
  done; return 1
}
sup_wait_ready() {
  local i; for i in $(seq 1 60); do grep -q -E 'SUP_READY|SUP_PREGATE fail|SUP_END' "$J/sup.log" 2>/dev/null && break; sleep 2; done
  V "SUPERVISOR $(grep -E 'SUP_START|SUP_BASELINE|SUP_PREGATE' "$J/sup.log" 2>/dev/null | cut -d' ' -f2- | tr '\n' ' ' | cut -c1-600)"
  grep -q SUP_READY "$J/sup.log" 2>/dev/null
}
CREATED=0
bench_new() { # creates the bench, proves the supervisor sees it, makes it 4 vCPU / 16 GiB
  local t r
  t=$(date -u +%s); CREATED=1
  if hx 900 - "$BENCH" new "$VM" > "$OUT/mac-new.txt" 2>&1; then V "MAC_BENCH up $(tail -n 1 "$OUT/mac-new.txt")"
  else V "MAC_BENCH blocked $(tail -n 2 "$OUT/mac-new.txt" | tr '\n' ' ')"; return 1; fi
  vm_seen "$t" || { V "HALT supervisor-blind (no sup.jsonl sample with vm_up=1 within 30 s of bench new; the host guard cannot see the VM)"; touch "$J/halt"; return 1; }
  V "SUPERVISOR sees VM ($(grep -m1 SUP_VM_SEEN "$J/sup.log" | cut -d' ' -f2-))"
  vmcfg 1; V "VMCONFIG before cpu=${CPU:-?} memory_mb=${MEM:-?}"
  if [ "${MEM:-}" != 16384 ] || [ "${CPU:-}" != 4 ]; then
    if [ "$ALLOW_TART_SET" = 1 ]; then  # only this disposable clone is changed, never golden-macos26
      hx 300 - "$BENCH" stop "$VM" >> "$OUT/mac-new.txt" 2>&1
      "$TART" set "$VM" --cpu 4 --memory 16384 >> "$OUT/mac-new.txt" 2>&1; r=$?
      t=$(date -u +%s); hx 900 - "$BENCH" start "$VM" >> "$OUT/mac-new.txt" 2>&1; vmcfg 2
      V "VMCONFIG set rc=$r after cpu=${CPU:-?} memory_mb=${MEM:-?}"
      vm_seen "$t" || { V "HALT supervisor-blind (after tart set + restart)"; touch "$J/halt"; return 1; }
    else V "BLOCKED vm-memory (bench made cpu=$CPU memory_mb=$MEM; ALLOW_TART_SET=0) = environment-not-matched"; return 1; fi
  fi
  [ "${MEM:-}" = 16384 ] || { V "BLOCKED vm-memory memory_mb=${MEM:-?} = environment-not-matched"; return 1; }
  return 0
}

MG=not-run; MAXFWD=2048; KEY=""; CELL_MAX=2700
run_cell() { # run_cell <tag> <openclaw version> <catalog none|N> <ws>
  local tag=$1 t0 t1 rc
  need 20 "$tag" || return 1
  gate || return 1
  live_start "$tag"
  t0=$(date -u +%s); mstep "$tag" "$CELL_MAX" cell "$tag" "$2" "$3" "$4" "$MAXFWD"; rc=$?; t1=$(date -u +%s)
  live_stop; echo "$t0 $t1" > "$OUT/t-$tag.txt"
  if ! grep -q '^PX loads=' "$OUT/m-$tag.txt" 2>/dev/null; then
    { echo "--- host live-tail fallback (c198830.py livesum on out/live-$tag.txt): the cell did not print its own PX/RTSUM lines"
      $PY "$HERE/c198830.py" livesum "$OUT/live-$tag.txt" "$tag"; } >> "$OUT/m-$tag.txt" 2>&1
    grep -E '^(PX|RTSUM|RTL)' "$OUT/m-$tag.txt" | grep -E 'src=live-tail|^PX_|^RTL .* live ' | sed "s/^/[live-$tag] /" >> "$J/verdicts.txt"
  fi
  cell_line "$tag" "$2" "$3" "$4" "$t0" "$t1"
  pull "$tag"
  return "$rc"
}
syn() { [ "$MAXFWD" != 0 ] && [ "$1" = none ] && echo "[synthetic-599]"; }
cell_line() { # the controller's one-line verdict for a cell, from the guest's lines + the host supervisor's samples
  local tag=$1 f="$OUT/m-$1.txt" ws=$4 effs eh ef ex rk host stop s
  s=$(syn "$3")
  effs=$(grep -m1 "^EFF $tag " "$f" | cut -d' ' -f4- | tr ' ' '\n' | awk -F'|' 'NF==3 {print $3}' | tr '\n' ',' | sed 's/,$//')
  eh=$(kv "PX embeds=" "$f" http | tr ',' '\n' | awk '/^2/ {a++} /^[0-9]/ && !/^2/ {b++} END {printf "2xx:%d,other:%d", a, b}')
  ef=$(kv "EXP $ws " "$J/corpus/expected.txt" files); ex=$(kv "EXP $ws " "$J/corpus/expected.txt" chunks)
  rk=$($PY "$HERE/c198830.py" ranks "$f" "$J/corpus/expected.txt")
  host=$($PY "$HERE/c198830.py" sup "$J/sup.jsonl" "$5" "$6")
  stop=none; grep -q '^BOUNDED ' "$f" && stop=bounded-reject; [ -f "$J/SUPERVISOR_STOPPED" ] && stop="supervisor:$(sed -n 's/^reason=\([^ ]*\).*/\1/p' "$J/SUPERVISOR_STOPPED")"
  V "CELL $tag oc=$(kv "INSTALL $tag " "$f" version) oc_installed_ok=$(kv "INTEGRITY $tag " "$f" installed_ok) catalog=$3 ws=$ws maxfwd=$MAXFWD$([ -n "$s" ] && echo " harness=capture-only") px_src=$(x=$(kv "PX loads=" "$f" src); echo "${x:-cell}") req_ctx=$(kv "PX loads=" "$f" first_req_ctx) loads=$(kv "PX loads=" "$f" loads) load_http=$(kv "PX loads=" "$f" first_load_http) load_status=$(kv "PX loads=" "$f" first_load_status) load_results=$(kv "PX loads=" "$f" load_results) eff_ctx=${effs:-none} n_ctx_in_log_order=$(kv "RTSUM $tag " "$f" n_ctx) n_ubatch=$(kv "RTSUM $tag " "$f" n_ubatch) batch_reset_to=$(kv "RTSUM $tag " "$f" batch_reset_to) model_buf=$(kv "RTSUM $tag " "$f" model_buf) compute_buf=$(kv "RTSUM $tag " "$f" compute_buf) alloc_fail=$(kv "RTSUM $tag " "$f" alloc_fail) max_mib=$(kv "RTSUM $tag " "$f" max_mib) max_fail_bytes=$(kv "RTSUM $tag " "$f" max_fail_bytes) embeds=$(kv "PX embeds=" "$f" embeds) embed_http=$eh$s embed_capture_only=$(kv "PX embeds=" "$f" capture_only) embed_models=$(kv "PX embeds=" "$f" models) index_embed_inputs_2xx=$(kv "PXIDX $tag " "$f" inputs_2xx)/$ex warmup_warn=$(kv "INDEX $tag " "$f" warmup_warn)$s index_rc=$(kv "INDEX $tag " "$f" rc)$s chunks_vec_warn=$(kv "INDEX $tag " "$f" chunks_vec_warn) vector_available=$(kv "STATUSJ $tag " "$f" vector_available) files=$(kv "STATUSJ $tag " "$f" files)/$ef chunks=$(kv "STATUSJ $tag " "$f" chunks)/$ex $rk insitu_trunc=$(kv "PROBE insitu-$tag " "$f" truncated) insitu_kind=$(kv "PROBE insitu-$tag " "$f" kind) tokens_C=$(kv "PROBE insitu-$tag " "$f" tokens_C) $host guest_min_avail_mib=$(kv "GMEM $tag " "$f" guest_min_avail_mib) guest_swap_peak_mib=$(kv "GMEM $tag " "$f" guest_swap_peak_mib) lms_rss_peak_mib=$(kv "GMEM $tag " "$f" lms_rss_peak_mib) stop=$stop"
  V "CELLERR $tag load_err=$(grep -m1 '^PX_LOADERR ' "$f" | cut -d' ' -f2- | cut -c1-240) embed_err=$(grep -m1 '^PX_EMBERR ' "$f" | cut -d' ' -f2- | cut -c1-240)$s index_failed=$(kv "INDEX $tag " "$f" failed | cut -c1-240)"
}

main() {
  local r i
  sup_wait_ready || { V "BLOCKED host-pregate (no VM was created)"; return; }
  bench_new || return
  mx 60 "mkdir -p $GK/ws-full/memory $GK/ws-prose/memory $GK/ev"
  mpush "$HERE/m198830.sh" "$GK/m198830.sh" && mpush "$HERE/j198830.mjs" "$GK/j198830.mjs" || { V "BLOCKED kit-push"; return; }
  V "PUSH kit ok m198830.sh=$(sha "$HERE/m198830.sh") j198830.mjs=$(sha "$HERE/j198830.mjs")"
  mstep info 180 info || return
  [ "$(kv "HW " "$OUT/m-info.txt" memsize)" = 17179869184 ] || { V "BLOCKED guest-memsize=$(kv "HW " "$OUT/m-info.txt" memsize) (need 17179869184) = environment-not-matched"; return; }
  NONCE=$(nonce); V "NONCE $NONCE"
  rm -rf "$J/corpus"; $PY "$HERE/c198830.py" corpus "$J/corpus" "$NONCE" > "$OUT/corpus.txt" 2>&1; r=$?
  sed 's/^/[corpus] /' "$OUT/corpus.txt" >> "$J/verdicts.txt"
  [ "$r" = 0 ] || { V "BLOCKED corpus rc=$r (lexical overlap or generator error)"; return; }
  for i in $(cd "$J/corpus" && find ws-full ws-prose -type f | LC_ALL=C sort) queries.tsv alt.txt alt.expect; do
    mpush "$J/corpus/$i" "$GK/$i" || { V "BLOCKED corpus-push $i"; return; }
  done
  V "PUSH corpus ok files=$(cd "$J/corpus" && find . -type f | wc -l | tr -d ' ')"
  mstep wd 120 wd-start || return; grep -q '^WD started' "$OUT/m-wd.txt" || { V "BLOCKED guest-watchdog-not-running"; return; }
  mstep lmsinst 3600 lmsinst || { pull pre; return; }
  mstep lmssetup 2700 lmssetup || { pull pre; return; }
  mstep model 2400 model || { pull pre; return; }
  KEY=$(sed -n 's/^KEY //p' "$OUT/m-model.txt" | head -n 1); V "KEY $KEY"
  mstep estimate 600 estimate || { pull pre; return; }
  mstep p1024 900 probe1024 || { pull pre; return; }
  MG=$(kv "METALGATE " "$OUT/m-p1024.txt" metal); [ "$MG" = matched ] && MAXFWD=0
  V "METAL gate=${MG:-none} why=$(kv "METALGATE " "$OUT/m-p1024.txt" why) metal_budget=$(kv "METALGATE " "$OUT/m-p1024.txt" metal_budget) rmws_gib=$(kv "METALGATE " "$OUT/m-p1024.txt" rmws_gib) proxy_maxfwd=$MAXFWD ($([ "$MAXFWD" = 0 ] && echo 'every load forwarded' || echo 'capture-only: loads above 2048 and embeddings without a loaded <=2048 instance are answered 599 by the proxy; what OpenClaw does after that is its reaction to the proxy (synthetic-599)'))"
  mstep proxy 120 proxy-start || { pull pre; return; }
  pull pre
  # Order: each 1024 control BEFORE its large-context cell, so a halt in the large cell never costs question 3.
  run_cell c2 2026.11.3 1024 ws-full
  [ -f "$OUT/m-c2.txt" ] && [ "$(kv "INDEX c2 " "$OUT/m-c2.txt" rc)" != 0 ] && run_cell c2p 2026.11.3 1024 ws-prose
  run_cell c1 2026.11.3 none ws-full
  run_cell c4 2026.11.4 1024 ws-full
  [ -f "$OUT/m-c4.txt" ] && [ "$(kv "INDEX c4 " "$OUT/m-c4.txt" rc)" != 0 ] && run_cell c4p 2026.11.4 1024 ws-prose
  # c5: one named question only. Does a budget that covers the default chunker's worst dense chunk (~1400 digit tokens
  # here) remove the C truncation, and what does it allocate? Only if c4 indexed AND its in-situ probe said truncated
  # (truncated=yes) or C's prompt_tokens fell below the controller's floor. A rank miss alone does not trigger it.
  local tc tmin; tc=$(kv "PROBE insitu-c4 " "$OUT/m-c4.txt" tokens_C); tmin=$(sed -n 's/^tokens_min=//p' "$J/corpus/alt.expect" 2>/dev/null)
  if [ -f "$OUT/m-c4.txt" ] && [ "$(kv "INDEX c4 " "$OUT/m-c4.txt" rc)" = 0 ] &&
     { [ "$(kv "PROBE insitu-c4 " "$OUT/m-c4.txt" truncated)" = yes ] || { [ "$tc" -lt "${tmin:-0}" ] 2>/dev/null; }; }; then
    run_cell c5 2026.11.4 2048 ws-full
  else V "SKIP c5 reason=c4-not-indexed-or-no-truncation-seen (truncated=$(kv "PROBE insitu-c4 " "$OUT/m-c4.txt" truncated) tokens_C=${tc:-none} floor=${tmin:-none})"; fi
  run_cell c3 2026.11.4 none ws-full
}

qualify() { # harness qualification of the host supervisor on real Tart (no LM Studio, no OpenClaw)
  local i rec
  sup_wait_ready || { V "QUALIFY supervisor=blocked reason=host-pregate"; return; }
  bench_new || { V "QUALIFY supervisor=fail reason=bench-new-or-supervisor-blind"; return; }
  V "QUALIFY forcing one supervisor stop (touch sup.force)"; touch "$J/sup.force"
  for i in $(seq 1 60); do grep -q SUPERVISOR_RECOVERED "$J/sup.log" 2>/dev/null && break; sleep 2; done
  rec=$(grep -m1 SUPERVISOR_RECOVERED "$J/sup.log" | cut -d' ' -f2-)
  "$BENCH" list > "$OUT/bench-list-qualify.txt" 2>&1
  if grep -q 'SUPERVISOR_STOP reason=.*qualification-forced' "$J/sup.log" && grep -q 'SUP_KILL .* rc=0' "$J/sup.log" &&
     grep -q 'SUPERVISOR_RECOVERED yes' "$J/sup.log" && ! grep -q "^$VM,RUNNING" "$OUT/bench-list-qualify.txt"; then
    V "QUALIFY supervisor=pass (saw VM, forced stop killed it, recovered: $rec)"
  else V "QUALIFY supervisor=fail stop=$(grep -m1 'SUPERVISOR_STOP ' "$J/sup.log" | cut -c1-160) kill=$(grep -m1 SUP_KILL "$J/sup.log" | cut -c1-120) recovered=[$rec] bench=$(grep "^$VM," "$OUT/bench-list-qualify.txt")"; fi
}

F() { echo "$OUT/m-$1.txt"; }
summary() {
  local p g m s R1 R3 A1 A3 C2 C4 q1 q2 q3
  [ "$MODE" = qualify ] && { V "RESULT_SUGGESTED=$(grep -q 'QUALIFY supervisor=pass' "$J/verdicts.txt" && echo qualified || echo stopped) mode=qualify"; return; }
  # The premise every row carries: what was actually run, vs the reporter's setup.
  PREM="metal=$MG metal_budget=$(kv "METALGATE " "$(F p1024)" metal_budget) rmws_gib=$(kv "METALGATE " "$(F p1024)" rmws_gib) lms=$(kv "LMS " "$(F lmsinst)" app_version)/$(kv "LMS " "$(F lmsinst)" route) lms_pinned=$(kv "LMS " "$(F lmsinst)" lms_pinned) runtime_pinned=$(kv "RUNTIME pin=" "$(F lmssetup)" runtime_pinned) key=${KEY:-none} key_same_as_reporter=$(kv "MODELCHK " "$(F model)" same_as_reporter)"
  GUARD=$(grep -i guardrail "$(F lmssetup)" 2>/dev/null | grep '^SETTINGS' | cut -d' ' -f2- | head -n 2 | tr ' \n' '_;' | cut -c1-160)
  R1=$(req_outcome c1); R3=$(req_outcome c3); A1=$(alloc_outcome c1); A3=$(alloc_outcome c3)
  C2=$(ctl_outcome c2 ws-full 1024); C4=$(ctl_outcome c4 ws-full 1024)
  row "req-2026.11.3 (c1)" "$R1"; row "alloc-2026.11.3 (c1)" "$A1"; row "ctl1024-2026.11.3 (c2)" "$C2"
  [ -f "$(F c2p)" ] && row "ctl1024-prose-2026.11.3 (c2p)" "$(ctl_outcome c2p ws-prose 1024)"
  row "req-2026.11.4 (c3)" "$R3"; row "alloc-2026.11.4 (c3)" "$A3"; row "ctl1024-2026.11.4 (c4)" "$C4"
  [ -f "$(F c4p)" ] && row "ctl1024-prose-2026.11.4 (c4p)" "$(ctl_outcome c4p ws-prose 1024)"
  V "COVERAGE direct-1024:[$(grep -m1 '^PROBE direct-1024 ' "$(F p1024)" 2>/dev/null | cut -d' ' -f3- | cut -c1-320)] $(cov c2) $(cov c4) $(cov c5) (truncated=yes kind=tail-dropped: the two C inputs differ only after ~1350 digit tokens and gave the same vector; kind=head-dropped: the two B inputs differ only before them and gave the same vector; truncated=no needs both pairs to differ AND prompt_tokens >= the floor)"
  [ -f "$(F c5)" ] && V "C5 2048 $(grep -m1 '^V198830 .* CELL c5 ' "$J/verdicts.txt" | cut -d' ' -f4- | cut -c1-500)"
  q1=0; q2=0; q3=0
  case "$(echo "$R1" | cut -d'|' -f1)" in reproduced|"not reproduced under these conditions") q1=1 ;; esac
  case "$(echo "$A1" | cut -d'|' -f1)" in reproduced|"not reproduced under these conditions") q2=1 ;; esac
  case "$(echo "$C2" | cut -d'|' -f1)" in "control passed"*|"control failed") q3=1 ;; esac
  if [ -f "$J/SUPERVISOR_STOPPED" ]; then s=stopped
  elif [ "$q1$q2$q3" = 111 ]; then s=passed
  elif [ "$q1$q3" = 11 ] && echo "$A1" | grep -q '^blocked|.*environment-not-matched'; then s=partial-environment-not-matched
  else s=stopped; fi
  V "RESULT_SUGGESTED=$s q1=$q1 q2=$q2 q3=$q3 $PREM left_min=$(left) (passed = all three questions have definite answers on 2026.11.3 on matched Metal; partial-environment-not-matched = q1 and q3 answered, the allocation question blocked: report it to labmail as stopped with that reason)"
}
halted_in() { # prints "<label>|<why>" when the cell was stopped or did not finish: bounded rejects are `blocked`, an
  # unfinished cell for any other reason (host timeout, guest step died, rollback) is `inconclusive / harness failure`
  grep -q '^BOUNDED ' "$(F "$1")" 2>/dev/null && { echo "blocked|bounded-reject (in-guest watchdog: $(grep -m1 '^BOUNDED ' "$(F "$1")" | tr ' ' '\n' | sed -n 's/^reason=//p'))"; return 0; }
  grep -q "CELLEND $1 " "$(F "$1")" 2>/dev/null && return 1
  [ -f "$J/SUPERVISOR_STOPPED" ] && { echo "blocked|bounded-reject (host supervisor: $(cat "$J/SUPERVISOR_STOPPED"))"; return 0; }
  echo "inconclusive / harness failure|cell did not finish ($(grep -m1 -E 'HALT|SIGNAL' "$J/verdicts.txt" | cut -d' ' -f3- | cut -c1-160))"; return 0; }
req_outcome() { local f r s; f=$(F "$1"); [ -f "$f" ] || { echo "not run|$PREM"; return; }
  r=$(kv "PX loads=" "$f" first_req_ctx); s=$(kv "PX loads=" "$f" src)
  case "$r" in
    "") echo "inconclusive / harness failure|no PX line, not even from the live tail; $PREM" ;;
    none) echo "inconclusive / harness failure|no load request captured; $PREM" ;;
    32768) echo "reproduced|with no catalog entry, OpenClaw's first POST /api/v1/models/load asked context_length=32768 for key $KEY (advertised max_context_length $(kv "MODELCHK " "$(F model)" max_ctx)); captured by the proxy${s:+ (via $s)}; oc_installed_ok=$(kv "INTEGRITY $1 " "$f" installed_ok); $PREM" ;;
    *) echo "not reproduced under these conditions|first load request context_length=$r; oc_installed_ok=$(kv "INTEGRITY $1 " "$f" installed_ok); $PREM" ;;
  esac; }
alloc_outcome() { local f h lh ls af irc eff mech gl rss bud io pc t0 t1; f=$(F "$1"); [ -f "$f" ] || { echo "not run|$PREM"; return; }
  [ -f "$OUT/t-$1.txt" ] && read -r t0 t1 < "$OUT/t-$1.txt"
  rss=$($PY "$HERE/c198830.py" sup "$J/sup.jsonl" "${t0:-0}" "${t1:-0}" | tr ' ' '\n' | sed -n 's/^host_max_vm_rss_gib=//p')
  lh=$(kv "PX loads=" "$f" first_load_http); ls=$(kv "PX loads=" "$f" first_load_status); af=$(kv "RTSUM $1 " "$f" alloc_fail)
  [ "$MG" = matched ] || { echo "blocked|environment-not-matched for the allocation claim: METALGATE metal=$MG why=$(kv "METALGATE " "$(F p1024)" why) (the not-matched/unknown rule is in the order); loads above 2048 were recorded but not forwarded (capture-only, synthetic-599). A CPU result would not be a negative repro of the Metal case. captured: load_http=${lh:-none} load_results=$(kv "PX loads=" "$f" load_results); $PREM"; return; }
  h=$(halted_in "$1") && { echo "$h; before the stop (from $(x=$(kv "PX loads=" "$f" src); echo "${x:-cell lines}")): load_http=${lh:-none} load_status=${ls:-none} load_results=$(kv "PX loads=" "$f" load_results) alloc_fail_lines=${af:-?} n_ctx_in_log_order=$(kv "RTSUM $1 " "$f" n_ctx) max_fail_bytes=$(kv "RTSUM $1 " "$f" max_fail_bytes) host_max_vm_rss_gib=${rss:-?}; $PREM"; return; }
  irc=$(kv "INDEX $1 " "$f" rc); eff=$(grep -m1 "^EFF $1 " "$f" | cut -d' ' -f3-)
  [ -n "$lh" ] && [ "$lh" != none ] || { echo "inconclusive / harness failure|no load response captured; $PREM"; return; }
  gl=$( { grep -m1 '^PX_LOADERR ' "$f"; kv "RTSUM $1 " "$f" guardrail_lines; } | grep -c -i -E 'guardrail|insufficient|^[1-9]')
  if [ "${lh#2}" = "$lh" ] || { [ "$ls" != loaded ] && [ "$ls" != - ]; } || [ "${af:-0}" -ge 1 ] 2>/dev/null; then
    if [ "${af:-0}" -ge 1 ] 2>/dev/null; then mech=llama-alloc-fail; elif [ "$gl" -ge 1 ]; then mech=lmstudio-guardrail
    elif [ "${lh#2}" = "$lh" ]; then mech=http-error; else mech="status:$ls"; fi
    echo "reproduced|mechanism=$mech match_reporter_mechanism=$([ "$mech" = llama-alloc-fail ] && echo yes || echo no) load http=$lh status=$ls alloc_fail_lines=${af:-?} n_ctx_in_log_order=$(kv "RTSUM $1 " "$f" n_ctx) n_ubatch=$(kv "RTSUM $1 " "$f" n_ubatch) batch_reset_to=$(kv "RTSUM $1 " "$f" batch_reset_to) max_fail_bytes=$(kv "RTSUM $1 " "$f" max_fail_bytes) index_rc=$irc host_max_vm_rss_gib=${rss:-?} guardrail_setting=${GUARD:-none}; $PREM"
    return
  fi
  [ "$irc" = 0 ] || { echo "inconclusive / harness failure|load ok (http=$lh status=$ls) but index_rc=$irc; $PREM"; return; }
  # The load succeeded: a non-reproduction counts only if the run matched the trigger (16 GB Metal budget, pinned
  # LM Studio / runtime, the OpenClaw package the Maintainer read). Otherwise the premise changed.
  bud=$(kv "METALGATE " "$(F p1024)" metal_budget); io=$(kv "INTEGRITY $1 " "$f" installed_ok)
  [ "$bud" = matched-16gb ] || { echo "blocked|environment-not-matched: the 32768 load succeeded, but the guest's Metal working-set budget is not a 16 GB Mac's (metal_budget=$bud rmws_gib=$(kv "METALGATE " "$(F p1024)" rmws_gib); 16 GB ref 10.67 GiB). load http=$lh status=$ls loaded_after=[$eff] index_rc=0 host_max_vm_rss_gib=${rss:-?}; $PREM"; return; }
  pc=""; [ "$(kv "LMS " "$(F lmsinst)" lms_pinned)" = yes ] || pc="$pc lms"; [ "$(kv "RUNTIME pin=" "$(F lmssetup)" runtime_pinned)" = yes ] || pc="$pc runtime"; [ "$io" = yes ] || pc="$pc openclaw-package"
  [ -z "$pc" ] || { echo "inconclusive / harness failure|premise changed ($pc ): the 32768 load succeeded on a setup that differs from the reporter's. load http=$lh status=$ls loaded_after=[$eff] index_rc=0 host_max_vm_rss_gib=${rss:-?}; $PREM"; return; }
  echo "not reproduced under these conditions|load http=$lh status=$ls alloc_fail_lines=0 loaded_after=[$eff] index_rc=0 n_ctx_in_log_order=$(kv "RTSUM $1 " "$f" n_ctx) host_max_vm_rss_gib=${rss:-?} guardrail_setting=${GUARD:-none}; $PREM"; }
ctl_outcome() { local f ws ef ex bad="" rk h tr kd tc ii lab; f=$(F "$1"); [ -f "$f" ] || { echo "not run|$PREM"; return; }
  h=$(halted_in "$1") && { echo "$h; $PREM"; return; }
  ws=$2; ef=$(kv "EXP $ws " "$J/corpus/expected.txt" files); ex=$(kv "EXP $ws " "$J/corpus/expected.txt" chunks)
  rk=$($PY "$HERE/c198830.py" ranks "$f" "$J/corpus/expected.txt")
  [ "$(kv "PX loads=" "$f" first_req_ctx)" = "$3" ] || bad="$bad req_ctx=$(kv "PX loads=" "$f" first_req_ctx)"
  case "$(kv "PX loads=" "$f" first_load_http)" in 2*) ;; *) bad="$bad load_http=$(kv "PX loads=" "$f" first_load_http)" ;; esac
  case "$(kv "PX loads=" "$f" first_load_status)" in loaded|-) ;; *) bad="$bad load_status=$(kv "PX loads=" "$f" first_load_status)" ;; esac
  grep -m1 "^EFF $1 " "$f" | tr ' ' '\n' | awk -F'|' -v c="$3" 'NF==3 && $3==c {x=1} END {exit !x}' || bad="$bad eff_ctx-not-$3"
  [ "$(kv "INDEX $1 " "$f" rc)" = 0 ] || bad="$bad index_rc=$(kv "INDEX $1 " "$f" rc)"
  [ "$(kv "INDEX $1 " "$f" chunks_vec_warn)" = 0 ] || bad="$bad chunks_vec_warn=$(kv "INDEX $1 " "$f" chunks_vec_warn)"
  [ "$(kv "STATUSJ $1 " "$f" vector_available)" = true ] || bad="$bad vector_available=$(kv "STATUSJ $1 " "$f" vector_available)"
  [ "$(kv "STATUSJ $1 " "$f" files)" = "$ef" ] || bad="$bad files=$(kv "STATUSJ $1 " "$f" files)/$ef"
  [ "$(kv "STATUSJ $1 " "$f" chunks)" = "$ex" ] || bad="$bad chunks=$(kv "STATUSJ $1 " "$f" chunks)/$ex"
  ii=$(kv "PXIDX $1 " "$f" inputs_2xx); [ "${ii:-0}" -ge "${ex:-1}" ] 2>/dev/null || bad="$bad index_embed_inputs_2xx=${ii:-none}/$ex"
  echo "$rk" | tr ' ' '\n' | grep -q '^A=1@' || bad="$bad A-not-top1"
  echo "$rk" | tr ' ' '\n' | grep -q '^D=1@' || bad="$bad D-not-top1"
  tr=$(kv "PROBE insitu-$1 " "$f" truncated); kd=$(kv "PROBE insitu-$1 " "$f" kind); tc=$(kv "PROBE insitu-$1 " "$f" tokens_C)
  if [ -z "$bad" ]; then
    case "$tr" in no) lab="control passed" ;; yes) lab="control passed (coverage: C truncated, $kd)" ;; *) lab="control passed (coverage: ${tr:-not-probed}, $kd)" ;; esac
    echo "$lab|req_ctx=$3 loaded files=$ef/$ef chunks=$ex/$ex index_embed_inputs_2xx=$ii/$ex vector_available=true chunks_vec_warn=0 $rk insitu_trunc=${tr:-none} kind=${kd:-none} tokens_C=${tc:-none} floor=$(sed -n 's/^tokens_min=//p' "$J/corpus/alt.expect" 2>/dev/null); $PREM"
  else echo "control failed|failed:$bad ($rk) insitu_trunc=${tr:-none} kind=${kd:-none} tokens_C=${tc:-none}; $PREM"; fi; }
row() { V "SUMMARY $1 outcome=\"$(echo "$2" | cut -d'|' -f1)\" detail=\"$(echo "$2" | cut -d'|' -f2-)\""; }
cov() { [ -f "$(F "$1")" ] && echo "$1:[insitu_trunc=$(kv "PROBE insitu-$1 " "$(F "$1")" truncated) kind=$(kv "PROBE insitu-$1 " "$(F "$1")" kind) tokens_B=$(kv "PROBE insitu-$1 " "$(F "$1")" tokens_B) tokens_C=$(kv "PROBE insitu-$1 " "$(F "$1")" tokens_C) cos_C=$(kv "PROBE insitu-$1 " "$(F "$1")" cos_C_vs_Calt) $($PY "$HERE/c198830.py" ranks "$(F "$1")" "$J/corpus/expected.txt" | tr ' ' '\n' | grep -E '^(B|C)=' | tr '\n' ' ')]"; }

TORN=0
finish() { # teardown + summary, exactly once, on every path (normal end, set -u abort, TERM/INT/HUP from a rollback)
  [ "$TORN" = 1 ] && return; TORN=1; trap - EXIT
  local i
  live_stop
  if [ "$CREATED" = 1 ]; then
    if [ "$MODE" = run ] && [ ! -f "$J/SUPERVISOR_STOPPED" ] && "$BENCH" list 2>/dev/null | grep -q "^$VM,RUNNING"; then
      mrun wd-stop 60 wd-stop; [ -f "$J/guest-ev-final.tgz" ] || pull final
    fi
    hx 300 - "$BENCH" destroy "$VM" > "$OUT/mac-destroy.txt" 2>&1; V "MAC_DESTROY rc=$? $(tail -n 1 "$OUT/mac-destroy.txt" | cut -c1-120)"
  else V "TEARDOWN skipped (VM not created by this run; nothing destroyed)"; fi
  "$BENCH" list > "$OUT/bench-list-end.txt" 2>&1
  if [ "$CREATED" = 1 ]; then grep -q "^$VM," "$OUT/bench-list-end.txt" && V "LEFTOVER $VM" || V "NO_LEFTOVER $VM"; fi
  touch "$J/driver.done"
  for i in $(seq 1 30); do grep -q SUP_END "$J/sup.log" 2>/dev/null && break; sleep 2; done
  grep -E 'SUP_VM_SEEN|SUPERVISOR_STOP|SUPERVISOR_RECOVERED|SUP_END|SUP_PEAKS|SUP_KILL|SUP_BENCH_STOP|SUP_RSS' "$J/sup.log" 2>/dev/null | sed 's/^/[sup] /' >> "$J/verdicts.txt"
  V "SUPERVISOR_FINAL $(grep -E 'SUP_END|SUP_PEAKS' "$J/sup.log" 2>/dev/null | cut -d' ' -f2- | tr '\n' ' ') stopped=$([ -f "$J/SUPERVISOR_STOPPED" ] && cat "$J/SUPERVISOR_STOPPED" || echo no)"
  summary
}
trap 'V "SIGNAL received: tearing down"; finish; exit 143' TERM INT HUP
trap 'finish' EXIT

V "START mode=$MODE hard_stop_epoch=$HSE left_min=$(left) vm=$VM allow_tart_set=$ALLOW_TART_SET kit_d=$(sha "$0")"
"$BENCH" list > "$OUT/bench-list-start.txt" 2>&1
case "$MODE" in qualify) qualify ;; run) main ;; *) V "BLOCKED bad MODE=$MODE" ;; esac
finish
exit 0
