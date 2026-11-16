#!/bin/bash
# run192790.sh: lab runner for openclaw/openclaw#192790 (heartbeat monitor scratch). Synthetic only.
# Runs INSIDE bench b192790 as root, from /root/r192790 (next to hb_mock.py). No argument needs quoting.
#   bash run192790.sh prep                     python3 present? versions; installed heartbeat docs and CLI help
#   bash run192790.sh start <mock|qwen|beta> [CTX]
#                                              (re)write that home's config, start the kit and the
#                                              gateway detached, check the config was read, print `cron list`
#   bash run192790.sh oc <mock|qwen|beta> <openclaw args...>   run openclaw against that home (and binary)
#   bash run192790.sh part1 <JOB>              A1-A5, detached, about 25 min; writes p1/
#   bash run192790.sh qwen <JOB>               Part 2, detached, at most 45 min; writes p2/
#   bash run192790.sh install-beta             npm install of 2026.11.5-beta.4 into beta/, detached
#   bash run192790.sh beta <JOB>               B1-B3, detached, about 12 min; writes p3/
#   bash run192790.sh status                   one STATE line per part, plus the last steps
#   bash run192790.sh stop                     stop every gateway and kit process in this bench
#   bash run192790.sh pack                     redacted copy of everything into L192790-bench.tgz; prints sha256
# Optional environment: EVERY (tick for mock/beta, default 1m), GW_FLAGS (extra `gateway run` flags),
# CFG_REL (config path inside a home, default .openclaw/openclaw.json).
set -u
R=/root/r192790
NOTE='No active heartbeat tasks. HEARTBEAT.md is comment-only; keep future wakes quiet unless new scratch context or tasks are provided.'
COMMENT='<!-- idle: nothing to check -->'
CFG_REL="${CFG_REL:-.openclaw/openclaw.json}"
GW_FLAGS="${GW_FLAGS:-}"
BETA_VER=2026.11.5-beta.4
cd "$R" || { echo "no $R"; exit 1; }

ts() { date -u +%FT%TZ; }
home_of() { echo "$R/home-$1"; }
bin_of() { if [ "$1" = beta ]; then echo "$R/beta/node_modules/.bin/openclaw"; else echo openclaw; fi; }
kitport() { if [ "$1" = qwen ]; then echo 11436; else echo 11434; fi; }
token() { cat "$R/token" 2>/dev/null; }
oc() { local h=$1; shift; OPENCLAW_HOME="$(home_of "$h")" OPENCLAW_GATEWAY_TOKEN="$(token)" "$(bin_of "$h")" "$@"; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
wait_port() { local i; for i in $(seq 1 "$2"); do port_open "$1" && return 0; sleep 1; done; return 1; }
secs_of() { case "$1" in *s) echo "${1%s}";; *m) echo $(( ${1%m} * 60 ));; *h) echo $(( ${1%h} * 3600 ));; *) echo $(( $1 * 60 ));; esac; }

write_cfg() { # home ctx every
  python3 -I - "$1" "$2" "$3" "$(token)" <<'PY'
import json, sys
h, ctx, every, tok = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
if h == "qwen":
    base, mid = "http://127.0.0.1:11436", "qwen3.8:27b-q4_K_M"
    model = {"id": mid, "name": mid, "contextWindow": ctx, "params": {"num_ctx": ctx, "keep_alive": "30m"}}
    hb = {"every": every, "target": "none", "timeoutSeconds": 600}
else:
    base, mid = "http://127.0.0.1:11434", "mock:latest"
    model = {"id": mid, "name": mid, "contextWindow": 65536, "params": {"keep_alive": "30m"}}
    hb = {"every": every, "target": "none"}
cfg = {
    "gateway": {"mode": "local", "port": 18789, "bind": "loopback", "auth": {"mode": "token", "token": tok}},
    "models": {"providers": {"ollama": {"apiKey": "ollama-local", "baseUrl": base, "api": "ollama", "models": [model]}}},
    "agents": {"defaults": {"model": {"primary": "ollama/" + mid}, "workspace": "/root/r192790/ws-" + h, "heartbeat": hb}},
    "messages": {"visibleReplies": "message_tool"},
}
print(json.dumps(cfg, indent=1))
PY
}

start_kit() { # home
  local h=$1
  case "$h" in
    qwen) (setsid nohup env PORT=11436 UPSTREAM=http://<RELAY> LOG="$R/requests-qwen.jsonl" \
            python3 -I "$R/hb_mock.py" serve >> "$R/relay.out" 2>&1 < /dev/null &) ;;
    *)    (setsid nohup env PORT=11434 LOG="$R/requests-$h.jsonl" MODE_FILE="$R/mode" \
            python3 -I "$R/hb_mock.py" serve >> "$R/kit-$h.out" 2>&1 < /dev/null &) ;;
  esac
  wait_port "$(kitport "$h")" 15 && echo "kit up on $(kitport "$h")" || { echo "FAILED: kit did not listen on $(kitport "$h")"; return 1; }
}

start_gw() { # home
  local h=$1
  [ -z "$GW_FLAGS" ] && [ -f "$R/gw-flags-$h" ] && GW_FLAGS="$(cat "$R/gw-flags-$h")"
  echo "$(ts) gateway start ($h) flags='$GW_FLAGS'" >> "$R/gateway-$h.log"
  # shellcheck disable=SC2086
  (setsid nohup env OPENCLAW_HOME="$(home_of "$h")" OPENCLAW_GATEWAY_TOKEN="$(token)" "$(bin_of "$h")" gateway run \
     --port 18789 $GW_FLAGS >> "$R/gateway-$h.log" 2>&1 < /dev/null &)
  if wait_port 18789 120; then echo "gateway up on 18789"; else echo "FAILED: gateway did not listen within 120 s"; tail -n 30 "$R/gateway-$h.log"; return 1; fi
}

stop_all() {
  pkill -f 'gateway run --port 18789' 2>/dev/null; pkill -f 'openclaw-gateway' 2>/dev/null; pkill -f 'hb_mock.py serve' 2>/dev/null
  local i; for i in $(seq 1 30); do port_open 18789 || port_open 11434 || port_open 11436 || break; sleep 1; done
  for p in 18789 11434 11436; do port_open "$p" && echo "WARNING: port $p still open after stop"; done
  echo "stopped ($(ts))"
}

read_scratch() { # home job label outfile
  { echo "=== $3 $(ts)"; oc "$1" cron scratch "$2" --json 2>&1; echo "--- (plain)"; oc "$1" cron scratch "$2" 2>&1; } >> "$4"
}

STATS="$R/p_stats.py"
write_stats() {
cat > "$STATS" <<'PY'
import json, sys, datetime as dt
def T(s): return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
def text(m):
    c = m.get("content")
    if isinstance(c, list): return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
    return c or ""
def load(f):
    try: return [json.loads(l) for l in open(f) if l.strip()]
    except OSError: return []
def args_of(c):
    a = (c.get("function") or {}).get("arguments") or {}
    if isinstance(a, str):
        try: a = json.loads(a)
        except Exception: a = {"_raw": a}
    return a
cmd, f = sys.argv[1], sys.argv[2]
E = [e for e in load(f) if e.get("path", "").startswith("/api/chat")]
HB = [e for e in E if e.get("hb_poll") and e.get("last_role") != "tool"]
if cmd == "phase":
    t0 = T(sys.argv[3])
    late = [e for e in HB if (T(e["t"]) - t0).total_seconds() > 15]
    print(f"chat_requests={len(E)} hb_calls={len(HB)} hb_calls_after_15s={len(late)} "
          f"chat_without_hb_poll={sum(1 for e in E if not e.get('hb_poll'))}")
    print("hb_tool_offered=" + (",".join(str(e.get("hb_tool")) for e in HB) or "-"))
    print("scratch_in_prompt=" + (",".join(str(e.get("scratch_in_prompt")) for e in HB) or "-"))
    for e in HB:
        ex = e.get("scratch_excerpt")
        print(f"  hb #{e['seq']} {e['t']} kind={e.get('kind') or e.get('status')} pe={e.get('prompt_eval_count')} "
              f"secs={e.get('secs', '')} excerpt={ex[:120]!r}" if ex else
              f"  hb #{e['seq']} {e['t']} kind={e.get('kind') or e.get('status')} pe={e.get('prompt_eval_count')} secs={e.get('secs', '')} excerpt=None")
        for c in e.get("reply_tool_calls") or (e.get("reply") or {}).get("tool_calls") or []:
            print(f"     model tool call: {(c.get('function') or {}).get('name')} args={json.dumps(args_of(c), ensure_ascii=False)}")
        if e.get("mode") == "relay" and e.get("reply_text"):
            print(f"     model text: {e['reply_text'][:300]!r}")
    for e in E:
        if e.get("last_role") == "tool" and e.get("body"):
            m = (e["body"].get("messages") or [{}])[-1]
            print(f"  tool result seen by model #{e['seq']} {e['t']}: {text(m)[:400]!r}")
    bad = [e for e in E if e.get("status") not in (None, 200)]
    print(f"non_200={len(bad)}")
    for e in bad: print(f"  non-200 #{e['seq']} {e['t']} status={e.get('status')} error={(e.get('error') or '')[:300]!r}")
elif cmd == "watch":   # Part 2: hb count, ticks since the first hb call that passed scratch, non-200 count
    first = None
    for i, e in enumerate(HB):
        if any("scratch" in args_of(c) for c in e.get("reply_tool_calls") or []):
            first = i; break
    after = (len(HB) - 1 - first) if first is not None else -1
    bad = sum(1 for e in E if e.get("status") not in (None, 200))
    print(len(HB), after, bad)
elif cmd == "tools":   # tool names in the first heartbeat request (mock mode only)
    for e in E:
        if e.get("body") and e.get("hb_poll"):
            print(sorted((t.get("function") or {}).get("name") for t in e["body"].get("tools") or [])); break
    else:
        print("no heartbeat request with a body yet")
PY
}

phase() { # home job outdir name mode action half_ticks ; action = unset|comment|note|none ; mode = plain|note|text|-
  local h=$1 job=$2 out=$3 name=$4 mode=$5 action=$6 secs tick m0 g0 start i n rc
  tick=$(cat "$R/every-secs-$h"); secs=$(( $7 * tick / 2 ))
  m0=$(wc -l < "$R/requests-$h.jsonl" 2>/dev/null || echo 0); g0=$(wc -l < "$R/gateway-$h.log" 2>/dev/null || echo 0)
  m0=${m0// /}; g0=${g0// /}
  start=$(ts); echo "$start $name start: mode=$mode action=$action wait=${secs}s tick=${tick}s" >> "$out/steps.log"
  [ "$mode" != - ] && echo "$mode" > "$R/mode"
  read_scratch "$h" "$job" "$name before-action" "$out/scratch-reads.txt"
  case "$action" in
    unset)   oc "$h" cron scratch "$job" --unset ;;
    comment) oc "$h" cron scratch "$job" --set "$COMMENT" ;;
    note)    oc "$h" cron scratch "$job" --set "$NOTE" ;;
    none)    true ;;
  esac > "$out/$name-action.txt" 2>&1; rc=$?
  echo "exit=$rc" >> "$out/$name-action.txt"; echo "$(ts) $name action $action exit=$rc" >> "$out/steps.log"
  if [ "$rc" != 0 ] && [ "$action" != unset ]; then echo "$(ts) $name: scratch $action FAILED (see $name-action.txt)" >> "$out/steps.log"; return 3; fi
  read_scratch "$h" "$job" "$name after-action" "$out/scratch-reads.txt"
  n=$(( (secs + tick - 1) / tick ))
  for i in $(seq 1 "$n"); do
    sleep "$tick"
    read_scratch "$h" "$job" "$name +$((i * tick))s" "$out/scratch-reads.txt"
    if [ "${PHASE_WATCH:-}" = qwen ]; then
      set -- $(python3 -I "$STATS" watch <(tail -n +"$((m0 + 1))" "$R/requests-$h.jsonl") 2>/dev/null)
      [ $# = 3 ] || { echo "$(ts) $name watch: stats helper gave no answer" >> "$out/steps.log"; continue; }
      echo "$(ts) $name watch: hb_calls=$1 ticks_after_first_note=$2 non_200=$3" >> "$out/steps.log"
      if [ "$3" != 0 ]; then echo "$(ts) $name: model request failed, ending Part 2 (blocked-on-model?)" >> "$out/steps.log"; touch "$out/MODEL-ERROR"; break; fi
      if [ "$1" -ge 6 ] || [ "$2" -ge 2 ]; then break; fi
    fi
  done
  echo "$(ts) $name end" >> "$out/steps.log"
  tail -n +"$((m0 + 1))" "$R/requests-$h.jsonl" > "$out/$name-requests.jsonl" 2>/dev/null
  tail -n +"$((g0 + 1))" "$R/gateway-$h.log" > "$out/$name-gateway-window.log" 2>/dev/null
  grep -Ei 'heartbeat|scratch|empty-heartbeat-file' "$out/$name-gateway-window.log" > "$out/$name-gateway.txt"
  python3 -I "$R/hb_mock.py" summary "$out/$name-requests.jsonl" > "$out/$name-summary.txt" 2>&1
  python3 -I "$STATS" phase "$out/$name-requests.jsonl" "$start" > "$out/$name-stats.txt" 2>&1
  oc "$h" system heartbeat last --json > "$out/$name-hblast.txt" 2>&1
  { echo "## $name  start=$start end=$(ts) mode=$mode action=$action(exit $rc) wait=${secs}s"
    cat "$out/$name-stats.txt"
    echo "empty-heartbeat-file lines in gateway log: $(grep -c 'empty-heartbeat-file' "$out/$name-gateway-window.log")"
    echo "heartbeat last: $(tr '\n' ' ' < "$out/$name-hblast.txt" | cut -c1-400)"
    echo; } >> "$out/table.txt"
}

hb_calls_of() { sed -n '1s/.* hb_calls=\([0-9]*\).*/\1/p' "$1"; }
late_count() { sed -n '1s/.*hb_calls_after_15s=\([0-9]*\).*/\1/p' "$1"; }
chat_count() { sed -n '1s/.*chat_requests=\([0-9]*\).*/\1/p' "$1"; }
skip_count() { grep -c 'empty-heartbeat-file' "$1"; }

detach() { # outdir subcommand args... : re-run this script detached (once), then return in the child
  local dir=$1 sub=$2; shift 2
  if [ -z "${R192790_DETACHED:-}" ]; then
    [ -d "$R/$dir" ] && { echo "FAILED: $R/$dir already exists (this part already ran); nothing started"; exit 1; }
    mkdir -p "$R/$dir"
    (R192790_DETACHED=1 setsid nohup bash "$R/run192790.sh" "$sub" "$@" > "$R/$dir.console" 2>&1 < /dev/null &)
    echo "started $sub detached at $(ts). Check with: bash $R/run192790.sh status"
    exit 0
  fi
  echo $$ > "$R/$dir/pid"
}

finish_part() { # out state
  stop_all >> "$1/steps.log" 2>&1; touch "$1/$2"; echo "$(ts) FINISHED $2" >> "$1/steps.log"; exit 0
}

cmd="${1:-}"; shift || true
case "$cmd" in
  prep)
    command -v python3 >/dev/null || { (apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y python3) >/dev/null 2>&1; }
    echo "== versions"; openclaw --version; node --version; python3 --version
    D="$(npm root -g)/openclaw/docs/gateway/heartbeat.md"
    echo "== installed docs: $D"; grep -n 'scratch\|every\|empty-heartbeat-file' "$D" | head -40
    for c in "cron scratch" "cron list" "system heartbeat" "system heartbeat last" "gateway run" "config get"; do
      echo "== openclaw $c --help"; OPENCLAW_HOME=$R/home-help openclaw $c --help 2>&1 | head -40; done ;;
  start)
    h="${1:?home: mock, qwen or beta}"; ctx="${2:-65536}"
    case "$h" in mock|beta) ev="${EVERY:-1m}";; qwen) ev=4m;; *) echo "unknown home $h"; exit 2;; esac
    [ "$h" = beta ] && [ ! -x "$(bin_of beta)" ] && { echo "FAILED: beta not installed; run install-beta first"; exit 1; }
    for p in 18789 "$(kitport "$h")"; do port_open "$p" && { echo "FAILED: port $p busy. Run: bash $R/run192790.sh stop"; exit 1; }; done
    [ -s "$R/token" ] || python3 -I -c 'import secrets; print("lab-" + secrets.token_hex(12))' > "$R/token"
    H="$(home_of "$h")"; C="$H/$CFG_REL"
    mkdir -p "$(dirname "$C")" "$R/ws-$h"; write_cfg "$h" "$ctx" "$ev" > "$C"; echo "wrote $C (every=$ev ctx=$ctx)"
    secs_of "$ev" > "$R/every-secs-$h"; echo "$GW_FLAGS" > "$R/gw-flags-$h"; echo "$CFG_REL" > "$R/cfg-rel-$h"
    [ "$h" != qwen ] && [ ! -f "$R/mode" ] && echo plain > "$R/mode"
    write_stats
    start_kit "$h" || exit 1
    start_gw "$h" || exit 1
    echo "== config read back (must show the kit port $(kitport "$h"), then the heartbeat block)"
    oc "$h" config get models.providers.ollama.baseUrl 2>&1 | tail -3
    oc "$h" config get agents.defaults.heartbeat 2>&1 | tail -8
    oc "$h" config get messages.visibleReplies 2>&1 | tail -3
    echo "== state dirs"; ls -la "$H" "$H/.openclaw" 2>&1 | head -30; ls -d /root/.openclaw 2>&1
    echo "== gateway log (last 25 lines)"; tail -n 25 "$R/gateway-$h.log"
    echo "== cron list --all"; oc "$h" cron list --all 2>&1 | head -40
    echo "== cron list --json"; oc "$h" cron list --all --json 2>&1 | head -80 ;;
  oc)
    h="${1:?home}"; shift; oc "$h" "$@" ;;
  part1)
    JOB="${1:?JOB id}"; detach p1 part1 "$@"; O=$R/p1; write_stats
    echo "$(ts) part1 JOB=$JOB" >> "$O/steps.log"
    phase mock "$JOB" "$O" A1 plain unset 7 || finish_part "$O" FAILED-cli
    a1=$(chat_count "$O/A1-stats.txt"); a1hb=$(hb_calls_of "$O/A1-stats.txt"); [ -z "$a1" ] && finish_part "$O" FAILED-stats
    [ "${a1:-0}" = 0 ] && finish_part "$O" FAILED-no-ticks
    [ "${a1hb:-0}" = 0 ] && finish_part "$O" FAILED-poll-not-detected
    phase mock "$JOB" "$O" A2 plain comment 8 || finish_part "$O" FAILED-cli
    a2=$(late_count "$O/A2-stats.txt"); [ -z "$a2" ] && finish_part "$O" FAILED-stats
    [ "$a2" != 0 ] && finish_part "$O" FAILED-controls
    phase mock "$JOB" "$O" A3a note unset 9 || finish_part "$O" FAILED-cli
    phase mock "$JOB" "$O" A3b plain none 7 || finish_part "$O" FAILED-cli
    phase mock "$JOB" "$O" A4 note comment 8 || finish_part "$O" FAILED-cli
    echo "$(ts) A5: restarting the gateway without the messages block" >> "$O/steps.log"
    stop_all >> "$O/steps.log" 2>&1
    C="$(home_of mock)/$(cat "$R/cfg-rel-mock")"; cp "$C" "$O/config-before-A5.json"
    python3 -I -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); c.pop("messages", None); json.dump(c, open(p, "w"), indent=1)' "$C"
    cp "$C" "$O/config-A5.json"
    { start_kit mock && start_gw mock; } >> "$O/steps.log" 2>&1 || finish_part "$O" FAILED-A5-restart
    phase mock "$JOB" "$O" A5 note unset 7 || finish_part "$O" FAILED-cli
    finish_part "$O" DONE ;;
  qwen)
    JOB="${1:?JOB id}"; detach p2 qwen "$@"; O=$R/p2; write_stats
    echo "$(ts) part2 JOB=$JOB" >> "$O/steps.log"
    curl -s -m 20 http://<RELAY>/lab/stats > "$O/labstats-before.json" 2>&1
    PHASE_WATCH=qwen phase qwen "$JOB" "$O" Q - unset 21 || finish_part "$O" FAILED-cli
    curl -s -m 20 http://<RELAY>/lab/stats > "$O/labstats-after.json" 2>&1
    [ -f "$O/MODEL-ERROR" ] && finish_part "$O" BLOCKED-model
    finish_part "$O" DONE ;;
  install-beta)
    detach beta-install install-beta; O=$R/beta-install
    echo "$(ts) npm install openclaw@$BETA_VER" >> "$O/steps.log"
    npm i --prefix "$R/beta" "openclaw@$BETA_VER" --no-fund --no-audit >> "$O/steps.log" 2>&1; rc=$?
    "$(bin_of beta)" --version >> "$O/steps.log" 2>&1
    [ "$rc" = 0 ] && { touch "$O/DONE"; } || { touch "$O/FAILED-npm"; }; echo "$(ts) exit=$rc" >> "$O/steps.log" ;;
  beta)
    JOB="${1:?JOB id}"; detach p3 beta "$@"; O=$R/p3; write_stats
    echo "$(ts) part3 JOB=$JOB version=$("$(bin_of beta)" --version 2>&1)" >> "$O/steps.log"
    phase beta "$JOB" "$O" B1 plain unset 7 || finish_part "$O" FAILED-cli
    python3 -I "$STATS" tools "$R/requests-beta.jsonl" > "$O/tools-first-hb.txt" 2>&1
    phase beta "$JOB" "$O" B2 plain note 7 || finish_part "$O" FAILED-cli
    phase beta "$JOB" "$O" B3 plain comment 7 || finish_part "$O" FAILED-cli
    finish_part "$O" DONE ;;
  status)
    for p in p1 p2 beta-install p3; do
      [ -d "$R/$p" ] || { echo "STATE $p=not-started"; continue; }
      s=$(cd "$R/$p" && ls -1 DONE FAILED-* BLOCKED-* 2>/dev/null | head -1)
      if [ -z "$s" ]; then if kill -0 "$(cat "$R/$p/pid" 2>/dev/null || echo none)" 2>/dev/null; then s=running; else s=DEAD-no-runner; fi; fi
      echo "STATE $p=$s"
    done
    for p in p1 p2 beta-install p3; do [ -f "$R/$p/steps.log" ] && { echo "== $p (last 6 steps)"; tail -n 6 "$R/$p/steps.log"; }; done
    echo "== listening: 18789=$(port_open 18789 && echo yes || echo no) 11434=$(port_open 11434 && echo yes || echo no) 11436=$(port_open 11436 && echo yes || echo no)" ;;
  stop)
    stop_all ;;
  pack)
    P=$R/pack/L192790; rm -rf "$R/pack"; mkdir -p "$P/configs"
    for f in hb_mock.py run192790.sh p_stats.py requests-*.jsonl gateway-*.log kit-*.out relay.out ./*.console mode every-secs-* gw-flags-* cfg-rel-*; do
      [ -e "$R/$f" ] && cp "$R/$f" "$P/"; done
    for d in p1 p2 p3 beta-install; do [ -d "$R/$d" ] && cp -r "$R/$d" "$P/"; done
    for h in mock qwen beta; do c="$(home_of "$h")/$(cat "$R/cfg-rel-$h" 2>/dev/null || echo "$CFG_REL")"
      [ -f "$c" ] && cp "$c" "$P/configs/openclaw-$h.json"; done
    tok="$(token)"; [ -n "$tok" ] && grep -rlF "$tok" "$P" | while read -r f; do sed -i "s/$tok/REDACTED/g" "$f"; done
    left=$(grep -rlF "${tok:-NO-TOKEN-SET}" "$P" | wc -l); echo "files still holding the token: $left"
    (cd "$P" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
    tar -C "$R/pack" -czf "$R/L192790-bench.tgz" L192790
    sha256sum "$R/L192790-bench.tgz"; du -h "$R/L192790-bench.tgz" ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
