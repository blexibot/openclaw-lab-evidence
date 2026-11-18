#!/bin/bash
# run198373v1.sh <tag> : openclaw/openclaw#198373 on the OpenAI-compatible route (api "openai-completions",
# POST /v1/chat/completions), with the openclaw now installed in this bench. Synthetic prompts only.
# Run detached inside the bench as root:
#   setsid nohup bash /root/r198373/kit-198373v1/run198373v1.sh v114 > /root/r198373/v114.console 2>&1 < /dev/null &
# Writes everything to $ROOT/<tag>/ and finally $ROOT/<tag>/DONE (or FAILED-<reason>).
# Sequence: preflight (one direct streamed /v1 request with a tool, to qualify streaming + structured tool calls +
# usage through the filter), gateway, warm turn (session "warm"), run 1 (tool turn), run 2 (next user turn, the pair
# that matters), run 3 (a no-tool control turn: run 2 -> run 3 shows what a stable append looks like on this route).
# ROOT and RELAY may be overridden for a local dry run; in the lab they keep their defaults.
set -u
TAG=$1; ROOT=${ROOT:-/root/r198373}; RELAY=${RELAY:-<RELAY>:11435}
K=$ROOT/kit-198373v1; W=$ROOT/$TAG
MODEL=qwen3.8:27b-q4_K_M
[ -e "$W/wire-$TAG.jsonl" ] && { echo "tag $TAG was already used; pick a new tag (e.g. ${TAG}r)"; exit 3; }
mkdir -p "$W" "$ROOT/ws"
export OPENCLAW_HOME=$W/home; mkdir -p "$OPENCLAW_HOME/.openclaw"
export OPENCLAW_GATEWAY_TOKEN="lab-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
GWPID=; PXPID=
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$W/steps.log"; }
stop_all() {
  for p in $GWPID $PXPID; do kill "$p" 2>/dev/null; done
  for i in $(seq 1 15); do
    alive=; for p in $GWPID $PXPID; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
    [ -z "$alive" ] && break; sleep 1
  done
  for p in $GWPID $PXPID; do kill -0 "$p" 2>/dev/null && { kill -9 "$p" 2>/dev/null; log "STOP pid $p needed SIGKILL"; }; done
  log "STOP gateway pid=${GWPID:-none} proxy pid=${PXPID:-none}; left: $(pgrep -af '[o]penclaw gateway|[l]ogproxy' | tr '\n' ';' || true)"
}
fail() { log "FAILED: $1"; stop_all; touch "$W/FAILED-$1"; exit 1; }
OCLOG_BEFORE=$(ls /tmp/openclaw/*.log 2>/dev/null | tr '\n' ' ')
log "tag=$TAG version: $(openclaw --version 2>&1 | tr '\n' ' ')"
command -v python3 >/dev/null || fail no-python3
for p in 11434 18789; do (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && fail "port-$p-busy"; done
sed -e "s/REPLACE_ME/$OPENCLAW_GATEWAY_TOKEN/" -e "s#/root/r198373/ws#$ROOT/ws#" "$K/openclaw.json" > "$OPENCLAW_HOME/.openclaw/openclaw.json"
echo "lab-198373 synthetic note" > "$ROOT/ws/note.txt"
B=$(openclaw config get models.providers.lab-qwen.baseUrl 2>&1 | tail -1); log "config baseUrl read back: $B"
case "$B" in *127.0.0.1:11434/v1*) ;; *) fail config-not-read ;; esac
log "config api read back: $(openclaw config get models.providers.lab-qwen.api 2>&1 | tail -1)"
log "config compat read back: $(openclaw config get models.providers.lab-qwen.models 2>&1 | tr -d ' \n' | grep -o '"compat":{[^}]*}')"
log "config validate: $(openclaw config validate 2>&1 | tail -1)"
log "cacheTrace read back: $(openclaw config get diagnostics.cacheTrace.enabled 2>&1 | tail -1)"
LISTEN=127.0.0.1:11434 UPSTREAM=$RELAY LOG=$W/wire-$TAG.jsonl setsid nohup python3 "$K/logproxy.py" > "$W/proxy.log" 2>&1 < /dev/null &
PXPID=$!
for i in $(seq 1 20); do (exec 3<>/dev/tcp/127.0.0.1/11434) 2>/dev/null && break; sleep 1; done
(exec 3<>/dev/tcp/127.0.0.1/11434) 2>/dev/null || fail proxy-not-listening
log "proxy listening (pid $PXPID); backend version via proxy: $(curl -s -m 20 http://127.0.0.1:11434/api/version)"
# Preflight: one direct streamed /v1 request with one tool. Qualifies streaming, structured tool calls and the usage
# chunk through the filter before OpenClaw is involved. Not part of the pair.
cat > "$W/preflight-req.json" <<EOF
{"model":"$MODEL","messages":[{"role":"system","content":"You are a test assistant. Use tools when asked."},{"role":"user","content":"Call the read tool with path note.txt. Do not answer in text."}],"tools":[{"type":"function","function":{"name":"read","description":"Read a file from the workspace","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}}],"tool_choice":"auto","stream":true,"stream_options":{"include_usage":true},"max_tokens":4096}
EOF
pre() { curl -s -m 900 -o "$W/preflight-$1.sse" -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @"$W/preflight-req.json" http://127.0.0.1:11434/v1/chat/completions; }
pf() { python3 -I - "$W/preflight-$1.sse" <<'PY'
import json, sys
tc = usage = False; n = 0; fin = None
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("data:") or line[5:].strip() == "[DONE]":
        continue
    try: o = json.loads(line[5:])
    except Exception: continue
    n += 1
    usage = usage or isinstance(o.get("usage"), dict)
    for ch in o.get("choices") or []:
        tc = tc or bool(((ch or {}).get("delta") or {}).get("tool_calls"))
        fin = (ch or {}).get("finish_reason") or fin
print(f"chunks={n} tool_calls={tc} usage={usage} finish={fin}")
PY
}
s=$(pre a); r=$(pf a); log "PREFLIGHT v1 stream+tool attempt a: http=$s $r"
case "$s $r" in "200 "*"tool_calls=True usage=True"*) ;; *)
  sleep 20; s=$(pre b); r=$(pf b); log "PREFLIGHT v1 stream+tool attempt b: http=$s $r"
  case "$s $r" in "200 "*"tool_calls=True usage=True"*) ;; *) fail preflight-v1-not-qualified ;; esac ;; esac
setsid nohup openclaw gateway run --port 18789 > "$W/gw-$TAG.log" 2>&1 < /dev/null &
GWPID=$!
for i in $(seq 1 120); do (exec 3<>/dev/tcp/127.0.0.1/18789) 2>/dev/null && break; sleep 1; done
(exec 3<>/dev/tcp/127.0.0.1/18789) 2>/dev/null || fail gateway-not-listening
log "gateway listening (pid $GWPID)"
turn() { log "turn session=$1 msg=$2"; timeout 1500 openclaw agent --agent main --session-key "$1" -m "$2" --timeout 1400 --json > "$W/$3.json" 2>&1; log "turn exit=$? ($3)"; }
toolresult_seen() { python3 -I - "$W/wire-$TAG.jsonl" <<'PY'
import json, os, sys
n = 0
for l in (open(sys.argv[1]) if os.path.exists(sys.argv[1]) else []):
    o = json.loads(l)
    if o.get("path") == "/v1/chat/completions" and o.get("status") == 200:
        try: m = json.loads(o["req"]).get("messages") or []
        except Exception: continue
        n += any(isinstance(x, dict) and x.get("role") == "tool" for x in m)
print(n)
PY
}
turn warm "Reply with one word: warm." warm
SK=cache-repro
turn $SK "Use the read tool to read note.txt in your workspace, then reply with its first word only." run1
if [ "$(toolresult_seen)" = "0" ]; then
  log "no tool result reached the model; retry once with the exec tool"
  SK=cache-repro-b
  turn $SK "Run date via exec and reply with the time only." run1b
  [ "$(toolresult_seen)" = "0" ] && fail no-tool-call
fi
log "tool result seen in $(toolresult_seen) /v1 request(s); runs 2 and 3 use session $SK"
turn $SK "Reply with one word: ready." run2
turn $SK "Reply with one word: again." run3
sleep 3
find "$OPENCLAW_HOME" -name 'cache-trace*.jsonl' -exec cp {} "$W/" \;
for f in /tmp/openclaw/*.log; do [ -f "$f" ] && [ "$f" -nt "$W/preflight-req.json" ] && cp "$f" "$W/oclog-$(basename "$f")"; done  # logs written during this run (before: $OCLOG_BEFORE)
curl -s -m 30 "http://$RELAY/lab/stats" > "$W/lab-stats-$TAG.json"
stop_all
ls -la "$W" >> "$W/steps.log"
python3 -I "$K/analyze198373v1.py" wire "$W/wire-$TAG.jsonl" "$W/lab-stats-$TAG.json" > "$W/analysis-wire-$TAG.txt" 2>&1
for t in "$W"/cache-trace*.jsonl; do [ -f "$t" ] && python3 -I "$K/analyze198373v1.py" trace "$t" > "$W/analysis-trace-$TAG.txt" 2>&1; done
grep -a -n 'prompt-cache\|differs from the previous request\|content\[' "$W/gw-$TAG.log" > "$W/gw-promptcache-$TAG.txt"
log "DONE"
(cd "$W" && sha256sum wire-*.jsonl cache-trace*.jsonl gw-*.log oclog-*.log analysis-*.txt lab-stats-*.json run*.json warm.json preflight-* proxy.log steps.log 2>/dev/null > evidence-$TAG.sha256)
touch "$W/DONE"
