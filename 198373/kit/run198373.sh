#!/bin/bash
# run198373.sh <tag> : one clean two-run repro of openclaw/openclaw#198373 with the openclaw now installed in this bench.
# Run detached inside the bench as root:  setsid nohup bash /root/r198373/kit-198373/run198373.sh v113 > /root/r198373/v113.console 2>&1 < /dev/null &
# Writes everything to /root/r198373/<tag>/ and finally /root/r198373/<tag>/DONE (or FAILED-<reason>). Synthetic prompts only.
set -u
TAG=$1; K=/root/r198373/kit-198373; W=/root/r198373/$TAG
[ -e "$W/wire-$TAG.jsonl" ] && { echo "tag $TAG was already used; pick a new tag (e.g. ${TAG}r)"; exit 3; }
mkdir -p "$W" /root/r198373/ws
export OPENCLAW_HOME=$W/home; mkdir -p "$OPENCLAW_HOME/.openclaw"
export OPENCLAW_GATEWAY_TOKEN="lab-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$W/steps.log"; }
fail() { log "FAILED: $1"; touch "$W/FAILED-$1"; pkill -f "openclaw gateway run" ; pkill -f logproxy.py; exit 1; }
log "tag=$TAG version: $(openclaw --version 2>&1 | tr '\n' ' ')"
command -v python3 >/dev/null || fail no-python3
for p in 11434 18789; do (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && fail "port-$p-busy"; done
sed "s/REPLACE_ME/$OPENCLAW_GATEWAY_TOKEN/" "$K/openclaw.json" > "$OPENCLAW_HOME/.openclaw/openclaw.json"
echo "lab-198373 synthetic note" > /root/r198373/ws/note.txt
B=$(openclaw config get models.providers.ollama.baseUrl 2>&1 | tail -1); log "config baseUrl read back: $B"
case "$B" in *127.0.0.1:11434*) ;; *) cp "$OPENCLAW_HOME/.openclaw/openclaw.json" "$OPENCLAW_HOME/openclaw.json"
  B=$(openclaw config get models.providers.ollama.baseUrl 2>&1 | tail -1); log "retry with \$OPENCLAW_HOME/openclaw.json: $B"
  case "$B" in *127.0.0.1:11434*) ;; *) fail config-not-read ;; esac ;; esac
log "cacheTrace read back: $(openclaw config get diagnostics.cacheTrace.enabled 2>&1 | tail -1)"
(LISTEN=127.0.0.1:11434 UPSTREAM=<RELAY>:11435 LOG=$W/wire-$TAG.jsonl setsid nohup python3 "$K/logproxy.py" > "$W/proxy.log" 2>&1 < /dev/null &)
for i in $(seq 1 20); do (exec 3<>/dev/tcp/127.0.0.1/11434) 2>/dev/null && break; sleep 1; done
(exec 3<>/dev/tcp/127.0.0.1/11434) 2>/dev/null || fail proxy-not-listening
log "proxy listening; relay version via proxy: $(curl -s -m 20 http://127.0.0.1:11434/api/version)"
(setsid nohup openclaw gateway run --port 18789 > "$W/gw-$TAG.log" 2>&1 < /dev/null &)
for i in $(seq 1 120); do (exec 3<>/dev/tcp/127.0.0.1/18789) 2>/dev/null && break; sleep 1; done
(exec 3<>/dev/tcp/127.0.0.1/18789) 2>/dev/null || fail gateway-not-listening
log "gateway listening"
turn() { log "turn session=$1 msg=$2"; timeout 1500 openclaw agent --agent main --session-key "$1" -m "$2" --timeout 1400 --json > "$W/$3.json" 2>&1; log "turn exit=$? ($3)"; }
toolresult_seen() { python3 - "$W/wire-$TAG.jsonl" <<'PY'
import json,os,sys
n=0
for l in (open(sys.argv[1]) if os.path.exists(sys.argv[1]) else []):
    o=json.loads(l)
    if o.get("path")=="/api/chat":
        try: m=json.loads(o["req"]).get("messages") or []
        except Exception: continue
        n+=any(isinstance(x,dict) and x.get("role")=="tool" for x in m)
print(n)
PY
}
SK=cache-repro
turn $SK "Use the read tool to read note.txt in your workspace, then reply with its first word only." run1
if [ "$(toolresult_seen)" = "0" ]; then
  log "no tool result reached the model; retry once with the exec tool"
  SK=cache-repro-b
  turn $SK "Run date via exec and reply with the time only." run1b
  [ "$(toolresult_seen)" = "0" ] && fail no-tool-call
fi
log "tool result seen in $(toolresult_seen) /api/chat request(s); run 2 uses session $SK"
turn $SK "Reply with one word: ready." run2
sleep 3
find "$OPENCLAW_HOME" -name 'cache-trace*.jsonl' -exec cp {} "$W/" \; ; ls -la "$W" >> "$W/steps.log"
curl -s http://<RELAY>:11435/lab/stats > "$W/lab-stats-$TAG.json"
python3 -I "$K/analyze198373.py" wire "$W/wire-$TAG.jsonl" > "$W/analysis-wire-$TAG.txt" 2>&1
for t in "$W"/cache-trace*.jsonl; do [ -f "$t" ] && python3 -I "$K/analyze198373.py" trace "$t" > "$W/analysis-trace-$TAG.txt" 2>&1; done
grep -a -n 'prompt-cache\|differs from the previous request\|content\[' "$W/gw-$TAG.log" > "$W/gw-promptcache-$TAG.txt"
pkill -f "openclaw gateway run"; pkill -f logproxy.py
(cd "$W" && sha256sum wire-*.jsonl cache-trace*.jsonl gw-*.log analysis-*.txt lab-stats-*.json run*.json steps.log 2>/dev/null > evidence-$TAG.sha256)
log "DONE"; touch "$W/DONE"
