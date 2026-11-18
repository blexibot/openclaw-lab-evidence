#!/bin/bash
# s198830.sh JOBDIR HARD_STOP_EPOCH: start the HOST SUPERVISOR (h198830.sh) and then the DRIVER (d198830.sh), each
# fully detached in its own session and process group (they survive the caller's turn ending, and stopping one never
# stops the other). ALLOW_TART_SET from the environment is passed to the driver (1 = it may `tart set` the disposable
# clone t198830-mac to 4 vCPU / 16384 MB if bench made it otherwise; golden-macos26 is never touched). MODE from the
# environment is passed too: MODE=qualify (supervisor qualification on real Tart, run first, in its own run dir) or
# MODE=run (default, the experiment). JOBDIR must be fresh: no earlier supervisor or driver files in it.
# Files: JOBDIR/sup.log, sup.jsonl, sup.pid (supervisor); drive.log, drive.pid, drive.exit, verdicts.txt, out/ (driver).
# No tmux on <LAB-HOST>, hence the python double fork.
J=${1:?job dir}; HSE=${2:?hard stop epoch (UTC seconds)}; HERE=$(cd "$(dirname "$0")" && pwd)
case "$HSE" in *[!0-9]*) echo "bad epoch"; exit 2 ;; esac
for f in drive.pid sup.pid sup.log sup.jsonl sup.launcher.pid verdicts.txt; do
  [ -e "$J/$f" ] && { echo "refusing: $J already has $f from an earlier start (use a fresh run dir)"; exit 2; }
done
case "${MODE:-run}" in run|qualify) ;; *) echo "bad MODE=${MODE:-}"; exit 2 ;; esac
mkdir -p "$J/out"; rm -f "$J/drive.exit" "$J/sup.exit" "$J/driver.done" "$J/SUPERVISOR_STOPPED" "$J/halt" "$J/sup.force"
start() { # start <script> <log> <pidfile> <exitfile> <args...>
  /usr/bin/python3 -I - "$@" <<'PY'
import os, sys
scr, logf, pidf, exitf = sys.argv[1:5]; args = sys.argv[5:]
if os.fork(): sys.exit(0)
os.setsid()
if os.fork(): os._exit(0)
os.setpgid(0, 0)
log = os.open(logf, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
nul = os.open(os.devnull, os.O_RDONLY)
os.dup2(nul, 0); os.dup2(log, 1); os.dup2(log, 2)
open(pidf, "w").write(str(os.getpid()))
q = " ".join("'" + a.replace("'", "'\\''") + "'" for a in [scr] + args)
os.execvpe("/bin/bash", ["/bin/bash", "-c", f'bash {q}; echo $? > "{exitf}"'], os.environ)
PY
}
start "$HERE/h198830.sh" "$J/sup.stdout.txt" "$J/sup.launcher.pid" "$J/sup.exit" "$J" "$HSE" t198830-mac
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$J/sup.pid" ] && break; sleep 1; done
[ -s "$J/sup.pid" ] || { echo "supervisor did not start; driver NOT started"; exit 3; }
J="$J" HARD_STOP_EPOCH="$HSE" ALLOW_TART_SET="${ALLOW_TART_SET:-0}" MODE="${MODE:-run}" start "$HERE/d198830.sh" "$J/drive.log" "$J/drive.pid" "$J/drive.exit"
sleep 1; echo "mode ${MODE:-run}: started supervisor pid $(cat "$J/sup.pid") (group $(cat "$J/sup.launcher.pid")), driver pid $(cat "$J/drive.pid" 2>/dev/null)"
