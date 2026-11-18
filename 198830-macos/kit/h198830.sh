#!/bin/bash
# h198830.sh (<LAB-HOST>, as <LAB-USER>; started detached by s198830.sh BEFORE the driver, in its own session and process
# group): the HOST SUPERVISOR for T198830. It is independent of the guest, of the driver and of the worker.
#   1. Pre-gate (before any VM exists): no bench VM RUNNING, no t198830-mac yet, host available memory >= PREGATE_GIB,
#      kernel pressure level 1 (normal). Writes SUP_READY or SUP_PREGATE fail=... to sup.log; the driver waits for it.
#   2. Every PERIOD s: one JSONL sample in sup.jsonl. avail_gib = (free + speculative + file-backed) pages x page size:
#      memory the kernel can hand out without compressing or swapping anonymous pages (idle guest RAM is anonymous).
#      Also logged: inactive and purgeable (not counted), kern.memorystatus_level (free %), swap used and its growth,
#      compressor growth, kernel pressure level, RSS of the Virtualization process(es) and of `tart run`.
#      Logs SUP_VM_SEEN pid=... whenever a new `tart run` pid for the VM appears (the driver waits for it).
#   3. Force-stop the VM (kill -KILL of its `tart run`, then `bench stop`), log SUPERVISOR_STOP with the reason and
#      the last 10 samples, and write SUPERVISOR_STOPPED, if ANY of: pressure level >= 2 on 2 consecutive samples;
#      available < FLOOR_GIB on 2 consecutive samples; swap used > baseline + SWAP_DELTA_MIB; compressor > baseline +
#      COMP_DELTA_GIB on 2 consecutive samples; Virtualization RSS > RSS_MAX_GIB (one sample: a 16 GiB guest must not
#      grow past it); HARD_STOP_EPOCH + 5 min passed with the VM still running; JOBDIR/sup.force exists (harness
#      qualification only). If a reason fires but no `tart run` pid is found while `bench list` shows the VM RUNNING,
#      it still runs `bench stop` and logs that. Never resumes anything.
#   4. After a stop: within 60 s check the VM is gone (no `tart run`, Virtualization RSS < 0.5 GiB), pressure is 1 and
#      available >= 16 GiB (SUPERVISOR_RECOVERED yes|no).
#   5. Exits when the driver wrote driver.done and the VM is gone, or 30 min after the hard stop.
# Thresholds (32 GB host, 16 GiB VM): the pre-gate of 20 GiB leaves ~4 GiB available once the guest has touched all
# 16 GiB; the 2 GiB floor is below that steady state and above the point where macOS starts compressing/swapping hard.
set -u
J=${1:?job dir}; HSE=${2:?hard stop epoch}; VM=${3:-t198830-mac}
BENCH=${H198830_TEST_BENCH:-/usr/local/bin/bench}   # test hook for the Maintainer's offline stub run only
PREGATE_GIB=18; FLOOR_GIB=2; SWAP_DELTA_MIB=256; COMP_DELTA_GIB=2; RSS_MAX_GIB=21; PERIOD=2
SJ=$J/sup.jsonl; SL=$J/sup.log
L() { echo "$(date -u +%FT%TZ) $*" >> "$SL"; }
vm_pid() { pgrep -f "tart run --no-graphics $VM\$" | head -n 1; }
vm_running_in_bench() { "$BENCH" list 2>/dev/null | grep -q "^$VM,RUNNING"; }
sample() { # sets AV CP INA PUR SW LV FP RSS VZ (GiB, GiB, GiB, GiB, MiB, level, %, GiB, GiB)
  local pg; pg=$(sysctl -n hw.pagesize)
  read -r AV CP INA PUR <<EOF
$(vm_stat | awk -v pg="$pg" '{gsub(/\./, "", $NF)} /^Pages free/ {f=$NF} /^Pages inactive/ {i=$NF} /^Pages speculative/ {s=$NF} /^Pages purgeable/ {p=$NF} /^File-backed pages/ {fb=$NF} /occupied by compressor/ {c=$NF} END {g = pg/1073741824; printf "%.3f %.3f %.3f %.3f\n", (f+s+fb)*g, c*g, i*g, p*g}')
EOF
  SW=$(sysctl -n vm.swapusage | awk '{for (i = 1; i <= NF; i++) if ($i == "used") v = $(i+2)} END {n = v + 0; if (v ~ /G$/) n *= 1024; printf "%.1f", n}')
  LV=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
  FP=$(sysctl -n kern.memorystatus_level 2>/dev/null || echo -1)
  read -r RSS VZ <<EOF
$(ps -axo rss=,command= | awk -v vm="$VM" '{vz = index($0, "Virtualization.VirtualMachine") > 0; tr = index($0, "tart run --no-graphics " vm) > 0} vz || tr {s += $1} vz {z += $1} END {printf "%.2f %.2f\n", s/1048576, z/1048576}')
EOF
}
lt() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a < b)}'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a > b)}'; }

echo $$ > "$J/sup.pid"
L "SUP_START pid=$$ vm=$VM hse=$HSE pregate_gib=$PREGATE_GIB floor_gib=$FLOOR_GIB swap_delta_mib=$SWAP_DELTA_MIB comp_delta_gib=$COMP_DELTA_GIB rss_max_gib=$RSS_MAX_GIB period_s=$PERIOD host=$(sysctl -n hw.model) memsize=$(sysctl -n hw.memsize) os=$(sw_vers -productVersion)"
sample; B_SW=$SW; B_CP=$CP
L "SUP_BASELINE avail_gib=$AV inactive_gib=$INA purgeable_gib=$PUR free_pct=$FP swap_used_mib=$SW compressor_gib=$CP level=$LV vm_rss_gib=$RSS vz_rss_gib=$VZ"
"$BENCH" list > "$J/sup-bench-list.txt" 2>&1
fail=""
grep -q ',RUNNING,' "$J/sup-bench-list.txt" && fail="$fail other-bench-running($(grep ',RUNNING,' "$J/sup-bench-list.txt" | cut -d, -f1 | tr '\n' ' '))"
grep -q "^$VM," "$J/sup-bench-list.txt" && fail="$fail $VM-exists"
lt "$AV" "$PREGATE_GIB" && fail="$fail avail_gib=$AV<$PREGATE_GIB"
[ "$LV" = 1 ] || fail="$fail pressure_level=$LV"
if [ -n "$fail" ]; then L "SUP_PREGATE fail=[$fail]"; L "SUP_END pregate-failed"; exit 0; fi
L "SUP_PREGATE ok avail_gib=$AV level=$LV"; L "SUP_READY"

nlv=0; nfl=0; ncp=0; stopped=0; lastp=""; blindlog=0
while :; do
  now=$(date -u +%s); sample
  sd=$(awk -v a="$SW" -v b="$B_SW" 'BEGIN {printf "%.1f", a - b}'); cd=$(awk -v a="$CP" -v b="$B_CP" 'BEGIN {printf "%.3f", a - b}')
  P=$(vm_pid); [ -n "$P" ] && up=1 || up=0
  [ -n "$P" ] && [ "$P" != "$lastp" ] && L "SUP_VM_SEEN pid=$P vz_rss_gib=$VZ"; lastp=$P
  echo "{\"t\":$now,\"avail_gib\":$AV,\"inactive_gib\":$INA,\"purgeable_gib\":$PUR,\"free_pct\":$FP,\"swap_mib\":$SW,\"swap_delta_mib\":$sd,\"comp_gib\":$CP,\"comp_delta_gib\":$cd,\"level\":$LV,\"vm_rss_gib\":$RSS,\"vz_rss_gib\":$VZ,\"vm_up\":$up}" >> "$SJ"
  [ "$LV" -ge 2 ] 2>/dev/null && nlv=$((nlv + 1)) || nlv=0
  lt "$AV" "$FLOOR_GIB" && nfl=$((nfl + 1)) || nfl=0
  gt "$cd" "$COMP_DELTA_GIB" && ncp=$((ncp + 1)) || ncp=0
  why=""
  [ "$nlv" -ge 2 ] && why="pressure-level-$LV-x$nlv"
  [ "$nfl" -ge 2 ] && why="${why:+$why,}avail-${AV}GiB-below-${FLOOR_GIB}-x$nfl"
  gt "$sd" "$SWAP_DELTA_MIB" && why="${why:+$why,}swap-grew-${sd}MiB"
  [ "$ncp" -ge 2 ] && why="${why:+$why,}compressor-grew-${cd}GiB-x$ncp"
  gt "$VZ" "$RSS_MAX_GIB" && why="${why:+$why,}vz-rss-${VZ}GiB-above-${RSS_MAX_GIB}"
  [ "$up" = 1 ] && [ "$now" -gt $((HSE + 300)) ] && why="${why:+$why,}hard-stop"
  [ -f "$J/sup.force" ] && why="${why:+$why,}qualification-forced"
  if [ -n "$why" ] && [ "$stopped" = 0 ]; then
    if [ "$up" = 1 ]; then
      stopped=1
      L "SUPERVISOR_STOP reason=$why vm_pid=$P (last 10 samples follow)"
      tail -n 10 "$SJ" | sed 's/^/  SAMPLE /' >> "$SL"
      echo "reason=$why at=$(date -u +%FT%TZ)" > "$J/SUPERVISOR_STOPPED"
      kill -KILL "$P" 2>/dev/null; L "SUP_KILL tart-run pid=$P rc=$?"
      "$BENCH" stop "$VM" >> "$SL" 2>&1; L "SUP_BENCH_STOP rc=$?"
    elif vm_running_in_bench; then  # the pid match failed but the VM runs: stop it anyway
      stopped=1
      L "SUPERVISOR_STOP reason=$why vm_pid=none (pgrep found no tart run, bench list says RUNNING; last 10 samples follow)"
      tail -n 10 "$SJ" | sed 's/^/  SAMPLE /' >> "$SL"
      echo "reason=$why at=$(date -u +%FT%TZ) pid=none" > "$J/SUPERVISOR_STOPPED"
      "$BENCH" stop "$VM" >> "$SL" 2>&1; L "SUP_BENCH_STOP_NO_PID rc=$?"
    elif [ "$blindlog" = 0 ]; then blindlog=1; L "SUP_REASON_NO_VM reason=$why (no tart run and bench list does not show $VM RUNNING; nothing to stop)"; fi
    if [ "$stopped" = 1 ]; then
      rec=no
      for i in $(seq 1 30); do
        sleep 2; sample
        if [ -z "$(vm_pid)" ] && lt "$VZ" 0.5 && [ "$LV" = 1 ] && ! lt "$AV" 16; then rec=yes; break; fi
      done
      L "SUPERVISOR_RECOVERED $rec vm_gone=$([ -z "$(vm_pid)" ] && echo yes || echo no) vz_rss_gib=$VZ level=$LV avail_gib=$AV swap_used_mib=$SW"
    fi
  fi
  if [ -f "$J/driver.done" ] && [ "$up" = 0 ]; then L "SUP_END driver-done vm_gone"; break; fi
  if [ "$now" -gt $((HSE + 1800)) ]; then L "SUP_END past-hard-stop-30min vm_up=$up"; break; fi
  sleep "$PERIOD"
done
awk -F'[:,}]' '{for (i = 1; i < NF; i++) {if ($i ~ /"avail_gib"/) a = $(i+1); if ($i ~ /"swap_delta_mib"/) s = $(i+1); if ($i ~ /"comp_delta_gib"/) c = $(i+1); if ($i ~ /"level"/) l = $(i+1); if ($i ~ /"vz_rss_gib"/) z = $(i+1)}
  if (NR == 1 || a < mn) mn = a; if (s > ms) ms = s; if (c > mc) mc = c; if (l > ml) ml = l; if (z > mz) mz = z}
  END {printf "SUP_PEAKS samples=%d min_avail_gib=%s max_swap_delta_mib=%s max_comp_delta_gib=%s max_level=%s max_vz_rss_gib=%s\n", NR, mn, ms + 0, mc + 0, ml + 0, mz + 0}' "$SJ" >> "$SL"
exit 0
