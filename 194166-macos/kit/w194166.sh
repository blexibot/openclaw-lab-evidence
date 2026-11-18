#!/bin/bash
# w194166.sh RUNDIR: the watcher's check (macOS host). Prints one line: FIRE ... (driver finished; or 10 min past the kit's
# hard stop; or no file in RUNDIR, RUNDIR/out changed for 45 min; or the run dir is missing) or WAIT ...
# It never starts, stops or changes anything. drive.log alone is quiet during the Linux builds and long guest steps,
# so staleness uses the newest of drive.log, verdicts.txt and out/*.
R=${1:?run dir}
[ -d "$R" ] || { echo "FIRE missing-run-dir $R"; exit 0; }
[ -f "$R/drive.exit" ] && { echo "FIRE done exit=$(cat "$R/drive.exit") $(grep -m1 RESULT_SUGGESTED "$R/drive.log")"; exit 0; }
[ -f "$R/drive.log" ] || { echo "FIRE no-drive-log"; exit 0; }
now=$(date -u +%s)
hse=$(sed -n 's/.*START hard_stop_epoch=\([0-9][0-9]*\).*/\1/p' "$R/verdicts.txt" 2>/dev/null | head -n 1)
hse=${hse:-1794869400}
[ "$now" -gt $(( hse + 600 )) ] && { echo "FIRE past-hard-stop hse=$hse now=$now last=$(tail -n 1 "$R/verdicts.txt" 2>/dev/null | cut -c1-200)"; exit 0; }
newest=$(stat -f %m "$R/drive.log" "$R/verdicts.txt" "$R"/out/* 2>/dev/null | sort -n | tail -n 1)
age=$(( now - ${newest:-0} ))
[ "$age" -gt 2700 ] && { echo "FIRE stale age_s=$age last=$(tail -n 1 "$R/verdicts.txt" 2>/dev/null | cut -c1-200)"; exit 0; }
echo "WAIT age_s=$age last=$(tail -n 1 "$R/verdicts.txt" 2>/dev/null | cut -c1-200)"
