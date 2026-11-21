#!/bin/bash
# run_matrix.sh <tag> <model> <num_ctx> <mode: footprint|suite|trim> <rungs e.g. "R0 R1 R2 R3"> <seeds e.g. "1 2 3 4 5">
# Env: APX (work dir, default ~/apx), KIT, OLLAMA_URL (default http://127.0.0.1:11434), PY (python3).
# Lab Mac mini, user space (~/apx): stock non-interactive Ollama onboarding of OpenClaw 2026.11.5 into a throwaway
# OPENCLAW_HOME, then per rung x seed: write the rung config, start the recording proxy and a gateway, and run either
# one "Reply with one word: ok." turn (footprint: the backend's own prompt_eval_count of the assembled first request)
# or the task suite. v1.0: the workspace is prepared (prep_ws.py) and snapshotted BEFORE any gateway starts, and restored
# from that snapshot before every rung/seed, so no run inherits an earlier run's edits. v1.2 (2026-11-20): every cell
# starts from a byte-identical copy of the whole post-onboarding home (no sessions, automation state or resumed turns
# carried between cells); the gateway runs in its own process group and is stopped only after the wire is quiet; the
# model is loaded by one untimed request first; suite tasks found invalid (another session's request in the window) or
# incomplete (watchdog) are rerun once in a fresh cell; an invalid first cell aborts the run. PAUSE_BUILTINS=1 disables
# OpenClaw's built-in automations in each cell (used for the long tasks3 cells only). Synthetic data only. Writes ~/apx/runs/<tag>/.
set -u
TAG=$1; MODEL=$2; CTX=$3; MODE=$4; RUNGS=$5; SEEDS=$6
B=${APX:-$HOME/apx}; K=${KIT:-$B/kit}; OLL=${OLLAMA_URL:-http://127.0.0.1:11434}; PY=${PY:-/usr/bin/python3}; R=$B/runs/$TAG; [ -e "$R" ] && { echo "tag used"; exit 3; }
mkdir -p "$R"; export PATH=${OC_BIN_DIR:+$OC_BIN_DIR:}$B/node/bin:$B/oc/bin:$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin  # OC_BIN_DIR: another openclaw build (e.g. a PR branch)
up() { (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null; }
export OPENCLAW_HOME=$R/home; mkdir -p "$OPENCLAW_HOME"
PXP=${PXPORT:-11535}; GWP=${GWPORT:-18989}
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$R/steps.log"; }
log "tag=$TAG model=$MODEL ctx=$CTX mode=$MODE rungs=[$RUNGS] seeds=[$SEEDS] openclaw=$(openclaw --version) node=$(node --version) ollama=$(curl -s -m 5 $OLL/api/version)"
log "model digest: $(curl -s -m 10 $OLL/api/tags | $PY -c "import json,sys; print([m['digest'] for m in json.load(sys.stdin)['models'] if m['name']=='$MODEL'])")"
LISTEN=127.0.0.1:$PXP UPSTREAM=${OLL#http://} LOG=$R/onboard-wire.jsonl nohup $PY -I $K/logproxy.py > $R/proxy-onboard.log 2>&1 < /dev/null & PX=$!
sleep 1
openclaw onboard --non-interactive --accept-risk --skip-health --no-install-daemon --auth-choice ollama \
  --custom-base-url http://127.0.0.1:$PXP --custom-model-id "$MODEL" > $R/onboard.log 2>&1; log "onboard rc=$?"
kill $PX 2>/dev/null; sleep 1
C=$OPENCLAW_HOME/.openclaw/openclaw.json; cp $C $R/base-openclaw.json
$PY -I -c "import json,sys; c=json.load(open(sys.argv[1])); c.setdefault('gateway',{})['port']=$GWP; json.dump(c,open(sys.argv[1],'w'),indent=2)" $R/base-openclaw.json
WS=$($PY -I -c "import json,sys,os; c=json.load(open(sys.argv[1])); print(((c.get('agents') or {}).get('defaults') or {}).get('workspace') or os.path.join(os.environ['OPENCLAW_HOME'],'.openclaw','workspace'))" $R/base-openclaw.json)
log "workspace $WS"; ls -la "$WS" >> $R/steps.log 2>&1
case "$WS" in "$OPENCLAW_HOME"/?*) ;; *) log "workspace outside the throwaway home, refusing"; exit 4;; esac
if [ -n "${LIVEDIN:-}" ]; then  # synthetic lived-in install: post-first-run workspace, 40 skills, one MCP server (15 tools)
  log "$($PY -I $K/livedin.py "$WS")"
  openclaw mcp add labtools --command $PY --arg -I --arg $K/mcpfake.py --approval approve >> $R/steps.log 2>&1; log "mcp add rc=$?"
  cp $C $R/base-openclaw.json
  $PY -I -c "import json,sys; c=json.load(open(sys.argv[1])); c.setdefault('gateway',{})['port']=$GWP; json.dump(c,open(sys.argv[1],'w'),indent=2)" $R/base-openclaw.json
fi
log "$($PY -I $K/prep_ws.py "$WS")"   # post-first-run state; never delete BOOTSTRAP.md while a gateway runs
rm -rf "$R/ws-pristine"; cp -a "$WS" "$R/ws-pristine"
rm -rf "$R/home-pristine"; cp -a "$OPENCLAW_HOME" "$R/home-pristine"   # v1.2: each cell starts from this
curl -s -m 600 $OLL/api/generate -d "{\"model\":\"$MODEL\",\"prompt\":\"ok\",\"stream\":false,\"options\":{\"num_predict\":1,\"num_ctx\":$CTX}}" > /dev/null; log "model preloaded (untimed)"
wire_quiet() {  # wire_quiet <wire> <quiet s> <limit s>: wait until the wire file has not grown for <quiet> s
  local w=$1 q=$2 lim=$3 t0=$(date +%s) last=-1 lt=$(date +%s) n
  while [ $(( $(date +%s) - t0 )) -lt $lim ]; do
    n=$(wc -c < "$w" 2>/dev/null || echo 0); [ "$n" != "$last" ] && { last=$n; lt=$(date +%s); }
    [ $(( $(date +%s) - lt )) -ge $q ] && return 0; sleep 2
  done; return 1
}
WSR=$OPENCLAW_HOME/.openclaw/workspace-restricted   # RESTRICTED=1: a second agent with exec/process denied (T12 control)
agent_turn() {  # agent_turn <out> <openclaw agent args...>: retry only while the gateway reports it is still starting
  local out=$1; shift
  local rc=1; for a in $(seq 1 60); do openclaw agent "$@" > "$out" 2>&1; rc=$?; grep -q 'during gateway startup' "$out" || return $rc; sleep 2; done; return $rc
}
FIRST=1
run_cell() {  # run_cell <rung> <seed> <attempt> [<only tasks>]
  local rung=$1 seed=$2 att=$3 only=${4:-}
  L=$rung-s$seed; [ "$att" -gt 1 ] && L=$L-a$att; mkdir -p $R/$L
  rm -rf "$OPENCLAW_HOME"; cp -a "$R/home-pristine" "$OPENCLAW_HOME"   # fresh, identical home for every cell
  rm -rf "$WS"; cp -a "$R/ws-pristine" "$WS"
  $PY -I $K/rungs.py $R/base-openclaw.json $C $rung $seed $CTX
  if [ -n "${RESTRICTED:-}" ]; then
    rm -rf "$WSR"; cp -a "$R/ws-pristine" "$WSR"
    $PY -I -c "import json,sys; c=json.load(open(sys.argv[1])); c['agents']['ownership']='explicit'; c['agents'].setdefault('entries',{})['restricted']={'name':'restricted','workspace':sys.argv[2],'tools':{'deny':['exec','process']}}; json.dump(c,open(sys.argv[1],'w'),indent=2)" $C "$WSR"
  fi
  cp $C $R/$L/openclaw.json
  V=$(openclaw config validate 2>&1); log "[$L] validate: $(echo "$V" | head -3 | tr '\n' ' ')"
  case "$V" in *"Config valid"*) ;; *) log "[$L] SKIPPED: config invalid, no gateway started"; return 0;; esac
  if up $GWP || up $PXP; then log "ABORT [$L]: port $GWP or $PXP already in use (a stale gateway/proxy); refusing to run against it"; exit 6; fi
  LISTEN=127.0.0.1:$PXP UPSTREAM=${OLL#http://} LOG=$R/$L/wire.jsonl nohup $PY -I $K/logproxy.py > $R/$L/proxy.log 2>&1 < /dev/null & PX=$!
  # own process group, so the stop below also ends anything the gateway started (exec sessions such as `sleep 600`)
  nohup $PY -I -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' openclaw gateway run --port $GWP > $R/$L/gw.log 2>&1 < /dev/null & GW=$!
  for i in $(seq 1 120); do up $GWP && break; sleep 1; done
  if [ -n "${PAUSE_BUILTINS:-}" ]; then
    for id in $(openclaw automations list --all --json 2>/dev/null | $PY -I -c "import json,sys
o=json.load(sys.stdin); o=o.get('jobs') or o.get('automations') or [] if isinstance(o,dict) else o
print(' '.join(j['id'] for j in o if j.get('id')))" 2>/dev/null); do
      openclaw automations disable "$id" > /dev/null 2>&1; log "[$L] built-in automation $id disable rc=$?"
    done
  fi
  if [ "$MODE" = footprint ]; then
    agent_turn $R/$L/turn.json --agent main --session-key fp-$L -m "Reply with one word: ok." --timeout 1700 --json
    log "[$L] footprint turn rc=$? $($PY -I $K/suite/footprint.py $R/$L/wire.jsonl $R/$L/turn.json)"
    # /context is not captured here: sent through `openclaw agent -m "/context json"` it reaches the model as an
    # ordinary message (checked 2026-11-19 on 2026.11.5). OpenClaw's own budget fields come from the --json turn above.
  elif [ "$MODE" = trim ]; then
    $PY -I $K/trim_test.py --ws "$WS" --wire $R/$L/wire.jsonl --out $R/$L/trim --turns ${TRIM_TURNS:-40} >> $R/steps.log 2>&1
    log "[$L] trim test done: $(cat $R/$L/trim/summary.txt 2>/dev/null)"
  else
    $PY -I $K/suite/suite.py --tasks $K/suite/${TASKS:-tasks.json} --ws "$WS" --wire $R/$L/wire.jsonl --out $R/results.jsonl --label $rung/s$seed \
      --pristine $R/ws-pristine ${RESTRICTED:+--ws-restricted "$WSR"} --cap ${TASK_CAP:-900} --attempt $att ${only:+--only $only} >> $R/steps.log 2>&1
    log "[$L] suite done rc=$?"
  fi
  wire_quiet $R/$L/wire.jsonl 20 600 || log "[$L] wire not quiet after 600 s; stopping anyway"
  kill -TERM -- -$GW 2>/dev/null; kill $PX 2>/dev/null; sleep 3; kill -9 -- -$GW 2>/dev/null; kill -9 $PX 2>/dev/null
  rm -rf "$R/$L/home-after"; mv "$OPENCLAW_HOME" "$R/$L/home-after"   # archived for inspection (scheduler state etc.)
}
redo_tasks() {  # redo_tasks <label> <attempt>: task ids of that cell's attempt whose verdict is invalid or incomplete
  $PY -I -c "import json,sys
ids=[d['task'] for d in map(json.loads,open(sys.argv[1])) if d.get('label')==sys.argv[2] and d.get('attempt',1)==int(sys.argv[3]) and d['verdict'] in ('invalid','incomplete')]
print(','.join(ids))" $R/results.jsonl "$1" "$2" 2>/dev/null
}
for rung in $RUNGS; do for seed in $SEEDS; do
  run_cell $rung $seed 1
  if [ "$MODE" = suite ]; then
    bad=$(redo_tasks "$rung/s$seed" 1)
    if [ -n "$bad" ] && [ "$FIRST" = 1 ] && grep -q '"verdict": "invalid"' $R/results.jsonl; then log "ABORT: first cell invalid ($bad)"; exit 5; fi
    if [ "$FIRST" = 1 ] && grep -q '"verdict": "error"' $R/results.jsonl; then log "ABORT: first cell has OpenClaw errors (no model run); see error_tails"; exit 5; fi
    if [ -n "$bad" ]; then log "[$rung-s$seed] rerun once: $bad"; run_cell $rung $seed 2 "$bad"; fi
  fi
  FIRST=0
done; done
log DONE
