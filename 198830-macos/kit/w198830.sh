#!/bin/bash
# w198830.sh RUNDIR: the watcher's check (<LAB-HOST>). Prints one line: FIRE ... or WAIT ... It never starts, stops or
# changes anything. FIRE when: the driver finished (done); the host supervisor is gone while the driver still runs
# (supervisor-dead: no host guard, roll back now); the supervisor stopped the VM and the driver has not finished
# 10 min later (supervisor-stop-stuck); 10 min past the kit's hard stop; or nothing in RUNDIR changed for 45 min.
# A supervisor that ended because its pre-gate failed is not "dead": that fires as "FIRE pregate" (no VM was made).
R=${1:?run dir}
[ -d "$R" ] || { echo "FIRE missing-run-dir $R"; exit 0; }
[ -f "$R/drive.exit" ] && { echo "FIRE done exit=$(cat "$R/drive.exit") $(grep -m1 RESULT_SUGGESTED "$R/drive.log" | cut -c1-200)"; exit 0; }
[ -f "$R/drive.log" ] || { echo "FIRE no-drive-log"; exit 0; }
now=$(date -u +%s)
if grep -q 'SUP_END pregate-failed' "$R/sup.log" 2>/dev/null; then
  echo "FIRE pregate $(grep -m1 'SUP_PREGATE' "$R/sup.log" | cut -c1-200)"; exit 0; fi
if [ ! -f "$R/driver.done" ] && ! kill -0 "$(cat "$R/sup.pid" 2>/dev/null)" 2>/dev/null; then
  echo "FIRE supervisor-dead $(tail -n 1 "$R/sup.log" 2>/dev/null | cut -c1-200)"; exit 0; fi
if [ -f "$R/SUPERVISOR_STOPPED" ] && [ $(( now - $(stat -f %m "$R/SUPERVISOR_STOPPED") )) -gt 600 ]; then
  echo "FIRE supervisor-stop-stuck $(cat "$R/SUPERVISOR_STOPPED")"; exit 0; fi
hse=$(sed -n 's/.*START hard_stop_epoch=\([0-9][0-9]*\).*/\1/p' "$R/verdicts.txt" 2>/dev/null | head -n 1)
hse=${hse:-1794921600}
[ "$now" -gt $(( hse + 600 )) ] && { echo "FIRE past-hard-stop hse=$hse now=$now last=$(tail -n 1 "$R/verdicts.txt" 2>/dev/null | cut -c1-200)"; exit 0; }
newest=$(stat -f %m "$R/drive.log" "$R/verdicts.txt" "$R/sup.log" "$R"/out/* 2>/dev/null | sort -n | tail -n 1)
age=$(( now - ${newest:-0} ))
[ "$age" -gt 2700 ] && { echo "FIRE stale age_s=$age last=$(tail -n 1 "$R/verdicts.txt" 2>/dev/null | cut -c1-200)"; exit 0; }
echo "WAIT age_s=$age last=$(tail -n 1 "$R/verdicts.txt" 2>/dev/null | cut -c1-200)"
