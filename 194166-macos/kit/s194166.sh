#!/bin/bash
# s194166.sh JOBDIR HARD_STOP_EPOCH: start d194166.sh fully detached (own session; survives the caller's turn ending).
# Writes JOBDIR/drive.log, JOBDIR/drive.exit (exit code, when done), JOBDIR/drive.pid; per-step files in JOBDIR/out/.
# Prints the pid, which is also the process group id. No tmux on the macOS host, hence the python double fork.
J=${1:?job dir}; HSE=${2:?hard stop epoch (UTC seconds)}; HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$J/out"; rm -f "$J/drive.exit"
/usr/bin/python3 -I - "$HERE/d194166.sh" "$J" "$HSE" <<'PY'
import os, sys
drv, j, hse = sys.argv[1], sys.argv[2], sys.argv[3]
if os.fork(): sys.exit(0)
os.setsid()
if os.fork(): os._exit(0)
os.setpgid(0, 0)  # own process group: kill -TERM -- -$(cat drive.pid) stops the driver and all its children
log = os.open(os.path.join(j, "drive.log"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
nul = os.open(os.devnull, os.O_RDONLY)
os.dup2(nul, 0); os.dup2(log, 1); os.dup2(log, 2)
open(os.path.join(j, "drive.pid"), "w").write(str(os.getpid()))
env = dict(os.environ, J=j, HARD_STOP_EPOCH=hse)
cmd = f'bash "{drv}"; echo $? > "{j}/drive.exit"'
os.execvpe("/bin/bash", ["/bin/bash", "-c", cmd], env)
PY
sleep 1; echo "started pid $(cat "$J/drive.pid" 2>/dev/null)"
