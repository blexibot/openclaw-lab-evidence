#!/bin/bash
# run198178.sh <tag> <relay ip:port> <hard-stop-epoch> : openclaw/openclaw#198178 on the openclaw installed in this bench.
# v5 (2026-11-18): target 2026.11.5 (R198178_VERSION), c3 gets its own login baseline (c3-infer0 in profile pc),
# the W5 429 rule (every refusal is an attempt; at most 3 attempts per step, then the run stops `blocked`), and
# INTEGRITY lines for the 2026.11.5 files the Maintainer read. Run inside the bench as root by host198178v5.sh:
#   bash /root/r198178/kit-198178v5/run198178.sh t1 <bridge-ip>:18178 <epoch> > /root/r198178/t1.console 2>&1 < /dev/null
# Everything goes to /root/r198178/<tag>/; at the end DONE (or FAILED-<reason>). steps.log is the timeline.
# Cells (each in its own isolated profile: HOME, OPENCLAW_HOME, OPENCLAW_STATE_DIR, OPENCLAW_CONFIG_PATH):
#   c1 pa: hand-written config (row maxTokens 8192, row contextWindow 200000, provider maxTokens 4096 and
#          timeoutSeconds 1234, sentinel diagnostics.cacheTrace.enabled + agents.defaults.workspace), one inference
#   c2 pa: non-interactive SGLang setup rerun (same endpoint/model); activation only if the CLI says it is needed; one inference
#   c3 pc: the same hand-written config, one baseline inference (c3-infer0); only if it sent 8192 with a 200: interactive
#          `models auth login --provider sglang` through a pty; one inference
#   c4 pb: fresh onboard, pin the same values with `config set`, one inference, rerun the same onboard, one inference
# No real token ever enters the bench: OpenClaw sends the dummy key below; the host relay on <LAB-LINUX-HOST> replaces it.
set -u
# 2026.11.5 `config set` refuses a state folder with a group/world-writable ancestor (seen offline with umask 002)
umask 022
TAG=${1:?tag}; RELAY=${2:?relay ip:port}; HSE=${3:?hard-stop epoch}
RT=${R198178_ROOT:-/root/r198178}   # override only for the Maintainer's offline stub test
K=$RT/kit-198178v5; W=$RT/$TAG; WANT=${R198178_VERSION:-2026.11.5}; WIRE=$W/wire.jsonl
[ -e "$W" ] && { echo "tag $TAG was already used; pick a new tag (e.g. ${TAG}r)"; exit 3; }
mkdir -p "$W" /root/r198178/ws 2>/dev/null || mkdir -p "$W"
export SGLANG_API_KEY=lab-dummy-198178   # not a secret; replaced by the host relay
URL=http://127.0.0.1:18178/v1; MID=deepseek-v4.1-flash; PROMPT="Reply with the single word OK."
AG=(--agent main); [ -n "${R198178_NOAGENT:-}" ] && AG=()   # the ORDER's one allowed fix if `--agent main` is refused
ONB=(openclaw onboard --non-interactive --accept-risk --mode local --auth-choice sglang --custom-base-url "$URL"
     --custom-model-id "$MID" --skip-channels --skip-daemon --skip-health --skip-hooks --skip-search --skip-skills
     --skip-ui --skip-bootstrap --json)
IDCHARS='A-Za-z0-9_/:=.,@%+-'   # the CLI's quoteCliArg leaves ids made of these characters unquoted
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$W/steps.log"; }
# only test processes run in this bench, so every openclaw process (onboard, infer, models, a stray gateway) goes
PROCPAT=${R198178_PROCPAT:-'[o]penclaw'}   # override only for the offline stub test (whose host runs other openclaw)
stopall() { pkill -f "$K/shim198178.py"; [ -z "${R198178_ROOT:-}" ] && pkill -f "$PROCPAT"; }
fail() {  # verdict and hashes are still written, so a stopped run keeps its evidence
  log "FAILED: $1"; stopall; python3 -I "$K/an198178.py" verdict "$W" > "$W/analysis.txt" 2>&1
  (cd "$W" && find . -type f ! -path './p?/home/*' ! -name evidence.sha256 | LC_ALL=C sort | xargs sha256sum > evidence.sha256)
  touch "$W/FAILED-$1"; exit 1; }
left() { echo $(( HSE - $(date -u +%s) )); }
wc_wire() { if [ -f "$WIRE" ]; then wc -l < "$WIRE" | tr -d ' '; else echo 0; fi; }
prof() { CUR=$1; P=$W/$1; SN=0; export HOME=$P/home OPENCLAW_HOME=$P/home OPENCLAW_STATE_DIR=$P/home/.openclaw \
  OPENCLAW_CONFIG_PATH=$P/home/.openclaw/openclaw.json; mkdir -p "$OPENCLAW_STATE_DIR"; log "PROFILE $CUR home=$HOME"; }
step() {  # step <label> <timeout-s> cmd... : stdout/stderr to <profile>/<label>.out/.err; logs the wire seq range
  local label=$1 to=$2 a b t; shift 2; a=$(wc_wire); t=$(date -u +%s)
  timeout -s KILL "$to" "$@" > "$P/$label.out" 2> "$P/$label.err" < /dev/null; LAST_RC=$?
  b=$(wc_wire); LAST_A=$((a + 1)); LAST_B=$b
  log "STEP profile=$CUR label=$label rc=$LAST_RC secs=$(( $(date -u +%s) - t )) wire=$LAST_A..$LAST_B t0=$t"
}
procs() {  # procs <after-label> : any openclaw process still alive after a step (a stray gateway or worker)
  local l n; l=$(pgrep -af "$PROCPAT" 2>/dev/null | cut -c1-160); n=$(printf '%s' "$l" | grep -c .)
  log "PROCS profile=${CUR:-none} after=$1 n=$n list=[$(printf '%s' "$l" | tr '\n' ';')]"
}
snap() {  # snap <label> : redacted copy of the active config (raw sha256 logged), plus the auth profile list
  SN=$((SN + 1)); local n f; n=$(printf %02d $SN); f=cfg-$n-$1.json
  if [ -f "$OPENCLAW_CONFIG_PATH" ]; then
    python3 -I "$K/an198178.py" redact "$OPENCLAW_CONFIG_PATH" "$P/$f"
    log "SNAP profile=$CUR n=$SN label=$1 raw_sha256=$(sha256sum < "$OPENCLAW_CONFIG_PATH" | cut -c1-64) file=$f"
  else log "SNAP profile=$CUR n=$SN label=$1 missing file=$f"; echo '{}' > "$P/$f"; fi
  timeout -s KILL 60 openclaw models auth list "${AG[@]}" --json > "$P/auth-$n-$1.txt" 2>&1 < /dev/null
}
# statuses: one token per chat POST in the last step's wire range: <http status>:<refusal reason|->:<requested cap|->:<Retry-After|->
statuses() { python3 -I "$K/an198178.py" status "$WIRE" "$LAST_A" "$LAST_B"; }
check_refusals() {  # check_refusals <statuses> : stops the run on any refusal; returns 1 only when a retry is allowed
  # W5 (LAB-IMPROVEMENT-PLAN-2026-11-18): every proxy 429 is an attempt (logged with time, status and Retry-After);
  # a transient one (lab-request-in-flight, spark-busy, metrics-*) with Retry-After <= 120 s may be retried, at most 3
  # attempts per step; any other 429 (paused, gate-busy, night-window, gate-*, longer waits) stops the run at once.
  local s=$1
  case "$s" in *503:relay-hard-stop*) fail hard-stop ;; esac
  case "$s" in *429:relay-budget*) fail relay-budget ;; esac
  case "$s" in *401:*) fail blocked-401 ;; *404:*) fail blocked-404 ;; *413:*) fail blocked-413 ;;
    *503:relay-*) fail "blocked-503-$(echo "$s" | grep -oE '503:relay-[a-z-]+' | head -n 1 | cut -d: -f2)" ;; esac
  case " $s" in *" 200:"*) return 0 ;; esac   # a step that also got a 200 is scored as it is, never re-run
  case "$s" in *429:*)
    RR=$(echo "$s" | grep -oE '429:[A-Za-z0-9._-]+' | head -n 1 | cut -d: -f2)
    RA=$(echo "$s" | grep -oE '429:[^ ]+' | head -n 1 | cut -d: -f4)
    case "$RR" in lab-request-in-flight|spark-busy|metrics-*)
      if [ "$RA" -le 120 ] 2>/dev/null; then return 1; fi ;; esac
    log "BLOCKED reason=${RR:-unknown} retry_after=${RA:-none} (not a transient 429: no retry)"
    fail "blocked-429-${RR:-unknown}" ;;
  esac
  return 0
}
attempt() {  # attempt <label> <retry-label-prefix> <cell-for-log> cmd... : one step, retried under the W5 rule
  # retry labels: "<prefix><n>" (inference: <label>-retry1, -retry2; activate: <cell>-activate1, -activate2)
  local label=$1 pre=$2 kind=$3 s n=1 lab; shift 3; lab=$label
  step "$lab" 300 "$@"; s=$(statuses)
  log "$kind profile=$CUR label=$lab rc=$LAST_RC wire=$LAST_A..$LAST_B attempt=$n chat_posts=$(echo $s | wc -w) statuses=[$s]"
  while ! check_refusals "$s"; do
    if [ "$n" -ge 3 ]; then log "BLOCKED $label attempts=$n reason=$RR retry_after=$RA (three attempts, W5)"
      fail "blocked-429-$RR-after-3-attempts"; fi
    log "SLOTWAIT $label attempt=$n status=429 reason=$RR retry_after=$RA (waiting Retry-After + 2-16 s)"
    sleep $((RA + 2 + RANDOM % 15))
    lab="$pre$n"; n=$((n + 1))
    step "$lab" 300 "$@"; s=$(statuses)
    log "$kind profile=$CUR label=$lab rc=$LAST_RC wire=$LAST_A..$LAST_B attempt=$n chat_posts=$(echo $s | wc -w) statuses=[$s]"
  done
}
infer() { attempt "$1" "$1-retry" INFER openclaw infer model run --local "${AG[@]}" --prompt "$PROMPT" --json; }
activate_if_needed() {  # activate_if_needed <cell> <file...> : runs `models auth activate` only when the CLI printed it
  local cell=$1 id staged=no; shift
  cat "$@" 2>/dev/null | grep -qi 'saved but inactive' && staged=yes
  id=$(cat "$@" 2>/dev/null | grep -oE "models auth activate [$IDCHARS]+" | head -n 1 | awk '{print $4}')
  if [ -n "$id" ]; then
    # accept the id only if it is a whole profile id in this profile's auth store (a wrapped/truncated id is not)
    timeout -s KILL 60 openclaw models auth list "${AG[@]}" --json > "$P/$cell-authlist.txt" 2>&1 < /dev/null
    if grep -oE "[$IDCHARS]+" "$P/$cell-authlist.txt" | grep -qxF -- "$id"; then
      log "ACTIVATE $cell needed profile_id=$id staged_message=$staged (id found in models auth list)"
      attempt "$cell-activate" "$cell-activate" ACTIVATE-STEP openclaw models auth activate "$id" "${AG[@]}"
      log "ACTIVATE $cell rc=$LAST_RC statuses=[$(statuses)]"; procs "$cell-activate"; snap "after-$cell-activate"
    else log "ACTIVATE $cell MISSED reason=id-not-in-auth-list id=$id staged_message=$staged"; fi
  elif [ "$staged" = yes ]; then log "ACTIVATE $cell MISSED reason=no-id-extracted (CLI said: saved but inactive)"
  else log "ACTIVATE $cell not-needed (no activation command printed)"; fi
}
need() { [ "$(left)" -ge "$1" ] || { log "SKIP $2 reason=hard-stop-near left=$(left)s"; return 1; }; }

# ---- preflight ----
hm=$(date -u +%H%M)
(( 10#$hm >= 730 && 10#$hm < 1300 )) && fail host-night-window
[ "$(left)" -gt 900 ] || fail past-hard-stop
log "WINDOW ok utc=$(date -u +%FT%TZ) left=$(left)s umask=$(umask)"
VER=$(timeout -s KILL 60 openclaw --version 2>&1 < /dev/null | tr '\n' ' ')
log "tag=$TAG agent_flag=[${AG[*]}] version: $VER"
echo "$VER" | grep -qF "$WANT" || fail "version-not-$WANT"
for c in python3 curl pkill pgrep timeout sha256sum; do command -v $c >/dev/null || fail "no-$c"; done
NR=$(timeout -s KILL 60 npm root -g 2>/dev/null < /dev/null); D="$NR/openclaw/dist"
ob=$(command -v openclaw)
log "INSTALL openclaw_bin=$ob -> $(readlink -f "$ob") npm_root=$NR package=$(python3 -I -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); print(d.get("name"), d.get("version"), "resolved=%s" % d.get("_resolved", "-"), "integrity=%s" % d.get("_integrity", "-"))
except Exception as e:
    print("unreadable", type(e).__name__)' "$NR/openclaw/package.json")"
# the installed build vs the files the Maintainer read in the 2026.11.5 npm tarball (dist.integrity sha512-mqPlsGLO...fDvxBA==,
# shasum f639a785...f471): a premise check, logged only (match=no is a recorded premise change, not a stop)
for fh in provider-setup-B98DCyPJ.mjs:be23922f1b49750c42cc8b5cdb22b999304c701ab8d4ac7a0dcc93568e5e5646 \
          defaults-BWyoTPqn.mjs:f7a65f58c356f2547e1502dfb52d1e333ac24297170fdd91d97717c1caf2376b \
          merge-patch-B7gt1grQ.mjs:64bf0130cca1926e064a44cd2b6c39f8b5ce3a7a574618299e42a6f52bd2c6ee \
          setup-inference-turn-x2uYo8LG.mjs:0c2d50b87ac8510565d48861851687d286ea0aeb817cf9b34ef536566071a833 \
          auth-choice-BFNQSl9s.mjs:7c659f0e8e20f98d0efc4db5476800267b9ba335961fa9d4b6d3292ee76fb7f5 \
          extensions/sglang/index.js:39ef8696353638185ff396ad9a51574b2110697eefa54e0ab2d0d0045845ea8b; do
  f=${fh%%:*}; want=${fh#*:}; got=$(sha256sum "$D/$f" 2>/dev/null | cut -c1-64)
  log "INTEGRITY $f match=$([ "$got" = "$want" ] && echo yes || echo no) got=${got:-missing}"
done
(exec 3<>/dev/tcp/127.0.0.1/18178) 2>/dev/null && fail port-18178-busy
(LISTEN=127.0.0.1:18178 UPSTREAM=$RELAY LOG=$WIRE setsid nohup python3 -I "$K/shim198178.py" > "$W/shim.log" 2>&1 < /dev/null &)
for i in $(seq 1 20); do (exec 3<>/dev/tcp/127.0.0.1/18178) 2>/dev/null && break; sleep 1; done
(exec 3<>/dev/tcp/127.0.0.1/18178) 2>/dev/null || fail shim-not-listening
pre=$(curl -s -m 30 -o "$W/preflight-models.json" -w '%{http_code}' -H "Authorization: Bearer $SGLANG_API_KEY" "$URL/models")
log "PREFLIGHT GET /v1/models via shim+relay+proxy status=$pre body=$(head -c 200 "$W/preflight-models.json" | tr '\n' ' ')"
[ "$pre" = 200 ] || fail "preflight-$pre"
procs preflight

# ---- c1: hand-written pinned config, one inference ----
prof pa
cp "$K/cfg-base.json" "$OPENCLAW_CONFIG_PATH"
step c1-validate 90 openclaw config validate
[ "$LAST_RC" = 0 ] || fail schema-rejected
step c1-configfile 60 openclaw config file
log "CONFIGFILE profile=pa active=$(tail -n 1 "$P/c1-configfile.out") expected=$OPENCLAW_CONFIG_PATH"
grep -qF "$OPENCLAW_CONFIG_PATH" "$P/c1-configfile.out" || fail config-path-not-isolated
for k in 'models.providers.sglang.models[0].maxTokens' 'models.providers.sglang.models[0].contextWindow' \
         'models.providers.sglang.maxTokens' 'models.providers.sglang.timeoutSeconds' 'diagnostics.cacheTrace.enabled'; do
  log "READBACK $k = $(timeout -s KILL 60 openclaw config get "$k" 2>&1 < /dev/null | tail -n 1)"
done
snap base
infer c1-infer
snap after-c1-infer
# c1 completed = exit 0 and a 200 whose request carried the pinned 8192 (the precondition every rerun cell rests on)
C1OK=no; [ "$LAST_RC" = 0 ] && statuses | grep -qE '(^| )200:[^: ]*:8192:' && C1OK=yes
log "C1OK=$C1OK statuses=[$(statuses)]"

# ---- c2: non-interactive setup rerun, same endpoint and model ----
if need 600 c2; then
  step c2-onboard 300 "${ONB[@]}"
  log "ONBOARD c2 rc=$LAST_RC statuses=[$(statuses)] stdout_tail=$(tail -c 300 "$P/c2-onboard.out" | tr '\n' ' ')"
  procs c2-onboard
  snap after-c2-onboard
  activate_if_needed c2 "$P/c2-onboard.out" "$P/c2-onboard.err"
  infer c2-infer
  snap after-c2-infer
fi

# ---- c3: own baseline on the hand-written config, then interactive login through a pty ----
if need 600 c3; then
  prof pc
  cp "$K/cfg-base.json" "$OPENCLAW_CONFIG_PATH"
  snap base
  infer c3-infer0
  snap after-c3-infer0
  C3OK=no; [ "$LAST_RC" = 0 ] && statuses | grep -qE '(^| )200:[^: ]*:8192:' && C3OK=yes
  log "C3OK=$C3OK statuses=[$(statuses)]"
fi
if [ "${C3OK:-no}" != yes ]; then log "SKIP c3 reason=c3-baseline-did-not-send-8192"
else
  step c3-login 300 env BASE_URL="$URL" MODEL_ID="$MID" python3 -I "$K/pty198178.py" "$P/c3-transcript.txt" -- \
    openclaw models auth login --provider sglang "${AG[@]}"
  log "LOGIN c3 rc=$LAST_RC $(tail -n 1 "$P/c3-login.out") statuses=[$(statuses)]"
  procs c3-login
  snap after-c3-login
  activate_if_needed c3 "$P/c3-transcript.txt"
  infer c3-infer
  snap after-c3-infer
fi

# ---- c4: Path B (a config made by onboard, then pinned with config set, then the same onboard again) ----
if need 600 c4; then
  prof pb
  step c4-onboard1 300 "${ONB[@]}"
  log "ONBOARD c4-1 rc=$LAST_RC statuses=[$(statuses)]"
  procs c4-onboard1
  snap after-c4-onboard1
  CSBAD=0
  for kv in 'models.providers.sglang.models[0].maxTokens 8192' 'models.providers.sglang.models[0].contextWindow 200000' \
            'models.providers.sglang.maxTokens 4096' 'models.providers.sglang.timeoutSeconds 1234' \
            'diagnostics.cacheTrace.enabled true' 'agents.defaults.workspace "/root/r198178/ws"'; do
    read -r ck cv <<< "$kv"
    crc=$(timeout -s KILL 60 openclaw config set "$ck" "$cv" --strict-json > /dev/null 2>> "$P/c4-configset.err" < /dev/null; echo $?)
    [ "$crc" = 0 ] || CSBAD=$((CSBAD + 1))
    log "CONFIGSET $ck $cv rc=$crc"
  done
  log "CONFIGSET_ALL profile=pb nonzero=$CSBAD"
  step c4-validate 90 openclaw config validate
  if [ "$LAST_RC" != 0 ]; then log "SKIP c4 reason=pinned-config-rejected"
  elif [ "$CSBAD" != 0 ]; then log "SKIP c4 reason=configset-failed nonzero=$CSBAD"
  else
    snap pinned
    infer c4-infer1
    snap after-c4-infer1
    c4b=$(statuses)
    if [ "$LAST_RC" != 0 ] || ! echo "$c4b" | grep -qE '(^| )200:[^: ]*:8192:'; then
      log "SKIP c4 reason=c4-baseline-did-not-send-8192 rc=$LAST_RC statuses=[$c4b]"
    else
      step c4-onboard2 300 "${ONB[@]}"
      log "ONBOARD c4-2 rc=$LAST_RC statuses=[$(statuses)] stdout_tail=$(tail -c 300 "$P/c4-onboard2.out" | tr '\n' ' ')"
      procs c4-onboard2
      snap after-c4-onboard2
      activate_if_needed c4 "$P/c4-onboard2.out" "$P/c4-onboard2.err"
      infer c4-infer2
      snap after-c4-infer2
    fi
  fi
fi

# ---- finish ----
sleep 2; procs finish; stopall
python3 -I "$K/an198178.py" verdict "$W" > "$W/analysis.txt" 2>&1
log "verdict lines: $(grep -c '^VERDICT' "$W/analysis.txt")"
log "DONE"
(cd "$W" && find . -type f ! -path './p?/home/*' ! -name evidence.sha256 | LC_ALL=C sort | xargs sha256sum > evidence.sha256)
touch "$W/DONE"
