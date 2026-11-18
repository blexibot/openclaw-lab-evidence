#!/bin/bash
# hostrelay198178.sh: runs ON <LAB-LINUX-HOST> as <LAB-USER> (never in a bench). Two uses:
#   bash ~/jobs/k198178/hostrelay198178.sh selftest
#       <LAB-LINUX-HOST> -> lab proxy GET /v1/models with <LAB-LINUX-HOST>'s own token (read from the file by python, never printed).
#   bash ~/jobs/k198178/hostrelay198178.sh start <bench-name> <hard-stop-epoch>
#       finds the bench bridge address (incusbr-1002) and the bench's IPv4, then starts relay198178.py in tmux session
#       J198178r, listening on <bridge-ip>:18178 and accepting only <bench-ip>/32. Prints RELAY_LISTEN=<ip>:18178.
#   bash ~/jobs/k198178/hostrelay198178.sh stop     (idempotent; prints the relay's exit code and whether :18178 is closed)
# Logs: ~/jobs/J198178r/relay.jsonl (requests), ~/jobs/J198178r/relay.log (stdout/stderr), ~/jobs/J198178r.exit.
set -u
K="$HOME/jobs/k198178"; J="$HOME/jobs/J198178r"; BR="${BRIDGE:-incusbr-1002}"; PORT=18178
TOKEN_FILE="$HOME/.config/lab-proxy/token"; UPSTREAM="<LAB-PROXY>"
case "${1:-}" in
  selftest)
    [ -r "$TOKEN_FILE" ] || { echo "SELFTEST token-file-missing"; exit 2; }
    UPSTREAM=$UPSTREAM TOKEN_FILE=$TOKEN_FILE python3 -I "$K/relay198178.py" selftest; exit $? ;;
  start)
    name="${2:?bench name}"; hse="${3:?hard-stop epoch}"
    [ "$(date -u +%s)" -lt "$hse" ] || { echo "RELAY refused past-hard-stop"; exit 2; }
    tmux has-session -t J198178r 2>/dev/null && { echo "RELAY refused already-running (tmux J198178r)"; exit 2; }
    bip=$(ip -4 -o addr show dev "$BR" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
    [ -n "$bip" ] || { echo "RELAY refused no-bridge-address dev=$BR"; exit 2; }
    vip=$(/usr/local/bin/bench list | awk -F, -v n="$name" '$1==n {print $3}' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    [ -n "$vip" ] || { echo "RELAY refused no-bench-ip bench=$name"; exit 2; }
    [ "${vip%.*}" = "${bip%.*}" ] || { echo "RELAY refused bench-ip-not-on-bridge bench=$vip bridge=$bip"; exit 2; }
    mkdir -p "$J"; rm -f "$HOME/jobs/J198178r.exit"
    tmux new -d -s J198178r "LISTEN=$bip:$PORT ALLOW=$vip/32 UPSTREAM=$UPSTREAM TOKEN_FILE=$TOKEN_FILE LOG=$J/relay.jsonl HARD_STOP=$hse MAX_POSTS=16 MAX_BODY=16384 OUT_CAP=256 python3 -I $K/relay198178.py > $J/relay.log 2>&1; echo \$? > $HOME/jobs/J198178r.exit"
    for i in 1 2 3 4 5 6 7 8 9 10; do (exec 3<>"/dev/tcp/$bip/$PORT") 2>/dev/null && break; sleep 1; done
    (exec 3<>"/dev/tcp/$bip/$PORT") 2>/dev/null || { echo "RELAY not-listening"; cat "$J/relay.log" 2>/dev/null; exit 1; }
    echo "RELAY_LISTEN=$bip:$PORT allow=$vip/32 hard_stop=$hse"; head -n 1 "$J/relay.log" ;;
  stop)   # SIGTERM to the relay itself (its tmux shell then writes the exit file and the session ends), then the session
    pkill -TERM -f "[r]elay198178.py" 2>/dev/null
    for i in 1 2 3 4 5; do tmux has-session -t J198178r 2>/dev/null || break; sleep 1; done
    if tmux has-session -t J198178r 2>/dev/null; then tmux kill-session -t J198178r; echo "RELAY stopped (session killed)"
    else echo "RELAY stopped exit=$(cat "$HOME/jobs/J198178r.exit" 2>/dev/null || echo none)"; fi
    ss -ltn 2>/dev/null | grep -q ":$PORT " && echo "RELAY WARNING port $PORT still listening" || echo "RELAY port $PORT closed" ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
