#!/usr/bin/env bash
# drive.sh <run-name> <api: openai-responses|openai-completions> [openclaw command...]
# One isolated run for openclaw/openclaw#188657: fresh OPENCLAW_HOME, mock on 127.0.0.1:$MOCK_PORT, gateway on
# $GW_PORT, two turns in one session through `openclaw agent`, then analyze.mjs. Default command: openclaw.
# Optional env: UPSTREAM (proxy mode), MODEL_ID (default test-model), KIT (default dir of this script),
# BASE (default /root/r188657), GW_PORT (18789), MOCK_PORT (8099), TURN_TIMEOUT (180).
set -uo pipefail
RUN="$1"; API="$2"; shift 2
OC=("$@"); [ ${#OC[@]} -eq 0 ] && OC=(openclaw)
KIT="${KIT:-$(cd "$(dirname "$0")" && pwd)}"; BASE="${BASE:-/root/r188657}"
GW_PORT="${GW_PORT:-18789}"; MOCK_PORT="${MOCK_PORT:-8099}"; MODEL_ID="${MODEL_ID:-test-model}"; TT="${TURN_TIMEOUT:-180}"
export OPENCLAW_HOME="$BASE/home-$RUN"
export OPENCLAW_GATEWAY_TOKEN="<TOKEN>"
CAP="$BASE/cap-$RUN"; WS="$BASE/ws-$RUN"; LOG="$BASE/logs-$RUN"
[ -e "$OPENCLAW_HOME" ] && { echo "STOP: $OPENCLAW_HOME already exists; pick a new run name"; exit 3; }
mkdir -p "$OPENCLAW_HOME/.openclaw" "$CAP" "$WS" "$LOG"
echo "lab fixture line one." > "$WS/fixture.txt"
node -e '
const [api, port, mport, ws, model] = process.argv.slice(1);
const cfg = {
  gateway: { mode: "local", port: Number(port), bind: "loopback", auth: { mode: "token", token: "<TOKEN>" } },
  models: { providers: { myproxy: { api, baseUrl: `http://127.0.0.1:${mport}/v1`, apiKey: "dummy",
    models: [ { id: model, name: model, contextWindow: 65536, maxTokens: 4096 } ] } } },
  agents: { defaults: { model: { primary: `myproxy/${model}` }, workspace: ws } },
  diagnostics: { cacheTrace: { enabled: true } }
};
process.stdout.write(JSON.stringify(cfg, null, 2));
' "$API" "$GW_PORT" "$MOCK_PORT" "$WS" "$MODEL_ID" > "$OPENCLAW_HOME/.openclaw/openclaw.json"
echo "== run=$RUN api=$API oc='${OC[*]}' home=$OPENCLAW_HOME $(date -u +%FT%TZ)"
echo "== version: $("${OC[@]}" --version 2>&1 | tail -1)"
echo "== config check: api=$("${OC[@]}" config get models.providers.myproxy.api 2>&1 | tail -1)"
cleanup() { [ -n "${GWP:-}" ] && kill -- -"$GWP" 2>/dev/null; [ -n "${MP:-}" ] && kill -- -"$MP" 2>/dev/null; sleep 1; }
trap cleanup EXIT
CAP_DIR="$CAP" PORT="$MOCK_PORT" UPSTREAM="${UPSTREAM:-}" setsid node "$KIT/mock.mjs" > "$LOG/mock.log" 2>&1 < /dev/null & MP=$!
setsid "${OC[@]}" gateway run --port "$GW_PORT" > "$LOG/gateway.log" 2>&1 < /dev/null & GWP=$!
for i in $(seq 1 120); do (exec 3<>/dev/tcp/127.0.0.1/"$GW_PORT") 2>/dev/null && break; sleep 1; done
(exec 3<>/dev/tcp/127.0.0.1/"$GW_PORT") 2>/dev/null || { echo "STOP: gateway not listening after 120 s"; tail -40 "$LOG/gateway.log"; exit 4; }
sleep 3
mark() { curl -fsS "http://127.0.0.1:$MOCK_PORT/__mark?label=$1" > /dev/null; }
turn() { echo "== $1 $(date -u +%T)"; mark "$1"; timeout -s KILL "$TT" "${OC[@]}" agent --session-key s188657 -m "$2" --json > "$LOG/$1.json" 2>&1; echo "   exit=$? reply_tail: $(tr -d '\n' < "$LOG/$1.json" | tail -c 300)"; }
turn t1 "READFILE: please read fixture.txt with your read tool and tell me what it says."
turn t2 "Second turn: just reply ok."
mark end
echo "== mock index:"; cat "$CAP/index.jsonl"
echo "== analysis:"; node "$KIT/analyze.mjs" "$CAP" | tee "$CAP/analysis.txt"
echo "== gateway log lines about cache trace / carriers:"
sed 's/\x1b\[[0-9;]*m//g' "$LOG/gateway.log" | grep -a -i 'cachetrace\|cache-trace\|cache trace\|runtimeContextCarrier\|carrier' | cut -c1-300 | tail -20
echo "== cache trace (runtimeContextCarrierRetained values, per file):"
for f in $(find "$OPENCLAW_HOME" -iname '*trace*' -type f 2>/dev/null); do echo "  $f"; grep -o '"runtimeContextCarrierRetained":[a-z]*' "$f" | sort | uniq -c; done
echo "== done $(date -u +%FT%TZ)"
