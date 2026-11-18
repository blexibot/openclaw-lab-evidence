#!/bin/bash
# m194166.sh <step> [args] (macOS Tart guest, user admin, /bin/bash 3.2): the guest side of T194166.
#   info | prep | install <label> <tag> | bk <label> <NS> <NK> <NX> | up <row> <target> <attach 0|1> <NS> <NK> <NX>
#   | pack
# Rules: openclaw never runs as root; sudo (guest password supplied at run time as GUEST_SUDO_PW) is used ONLY to create and remove
# the root-owned N5 fixture. Every step prints its verdict lines (TRIGGER/BK/ARCH/UP/INSTALL) BEFORE any raw dump;
# raw outputs stay in ~/k194166/ev and are pulled whole by the driver ("pack").
set -u
K=$HOME/k194166; E=$K/ev; JH=$K/j194166.mjs; mkdir -p "$E"
MARK=.openclaw-private-update-capture; MARKC=openclaw-private-update-capture-v1
ts() { date -u +%FT%TZ; }
tmo() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec failed: $!"' "$s" "$@"; }
asroot() { printf '%s\n' "${GUEST_SUDO_PW:?}" | sudo -S -p '' "$@"; }
oc() { # oc <outfile> <seconds> <openclaw args...>: run openclaw, output to file, echo the exit code
  local f=$1 s=$2; shift 2
  { echo "+ openclaw $* [$(ts)]"; tmo "$s" openclaw "$@"; echo "rc=$?"; } > "$f" 2>&1
  sed -n 's/^rc=//p' "$f" | tail -n 1
}
refusal() { # refusal <file> <rc>
  if grep -q 'Private update capture marker is unreadable; export refused' "$1"; then echo unreadable
  elif grep -q 'Private update capture marker is invalid or unreadable; export refused' "$1"; then echo invalid
  elif [ "$2" != 0 ]; then echo other
  else echo none; fi
}
one() { tr -s ' \t\n' '___' | sed 's/_$//'; }  # make a value safe for key=value lines
detach_all() {
  local m
  for m in $(mount | awk '$3 ~ /\/k194166\/.*\/labvol$/ {print $3}'); do
    hdiutil detach "$m" > /dev/null 2>&1 || hdiutil detach -force "$m" > /dev/null 2>&1
    echo "DETACH_STALE $m rc=$?"
  done
}
attach() { # attach <W> <tag> <NX>
  mkdir -p "$1/labvol"
  hdiutil attach -owners on -mountpoint "$1/labvol" "$K/labvol.dmg" > "$E/attach.$2.txt" 2>&1
  local rc=$? i
  echo "ATTACH $2 rc=$rc"
  [ "$rc" = 0 ] || return "$rc"
  printf '%s\n' "$3" > "$1/labvol/x.txt"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do [ -e "$1/labvol/.fseventsd" ] && break; sleep 2; done
  ls -leOd "$1/labvol" "$1/labvol/.fseventsd" 2>&1 | sed 's/^/LS /'
  ls -la "$1/labvol" 2>&1 | sed 's/^/LSVOL /'
  diskutil info "$1/labvol" 2>&1 | grep -iE 'owners|file system personality|mount point' | sed 's/^/DISKUTIL /'
  mount | grep labvol | sed 's/^/MOUNT /'
}
detach() { # detach <W> <tag>
  hdiutil detach "$1/labvol" > "$E/detach.$2.txt" 2>&1 || hdiutil detach -force "$1/labvol" >> "$E/detach.$2.txt" 2>&1
  echo "DETACH $2 rc=$?"
}
probe() { # probe <W> <tag>: the trigger, observed directly as this user
  stat "$1/labvol/.fseventsd/$MARK" > "$E/probe.$2.txt" 2>&1
  local rc=$?
  echo "TRIGGER $2 stat_rc=$rc eacces=$(grep -c 'Permission denied' "$E/probe.$2.txt") owner=$(stat -f '%Su:%Sg:%Sp' "$1/labvol/.fseventsd" 2>&1 | one)"
}
mkhome() { # mkhome <name>: fresh OPENCLAW_HOME created by the installed runner itself; sets H STATE WORKSPACE W
  detach_all
  H=$K/h-$1; rm -rf "$H"; mkdir -p "$H"; export OPENCLAW_HOME=$H
  echo "SETUP $1 rc=$(oc "$E/$1.setup.txt" 300 setup --baseline)"
  local prc; prc=$(oc "$E/$1.plan.txt" 300 backup create --dry-run --json)
  node "$JH" plan "$E/$1.plan.txt" > "$E/$1.plan.parsed"
  STATE=$(sed -n 's/^STATE=//p' "$E/$1.plan.parsed"); WORKSPACE=$(sed -n 's/^WORKSPACE=//p' "$E/$1.plan.parsed")
  echo "PLAN $1 rc=$prc OPENCLAW_HOME=$H STATE=${STATE:-UNPARSED} WORKSPACE=${WORKSPACE:-UNPARSED}"
  [ -n "$STATE" ] && [ -n "$WORKSPACE" ] || { echo "BLOCKED $1 reason=plan-unparsed"; return 1; }
  W=$WORKSPACE/state; mkdir -p "$W"
}
fixture() { # fixture <NS> <NK>: the sentinel (settings-adjacent user file) and a readable sibling directory
  printf '%s\n' "$1" > "$WORKSPACE/SENTINEL-194166.txt"
  mkdir -p "$W/sibling"; printf '%s\n' "$2" > "$W/sibling/keep.txt"
}
bk_run() { # bk_run <tag> <case>
  local f="$E/$1.$2.backup.txt" rc
  rm -rf "$H/out"; mkdir -p "$H/out"
  rc=$(oc "$f" 600 backup create --verify --json --output "$H/out")
  echo "BK $1 $2 rc=$rc refusal=$(refusal "$f" "$rc") skipwarn=$(grep -c 'Skipped unreadable foreign entry' "$f")"
}
arch() { # arch <tag> <case>: list the archive and read back the fixture from it
  local A l trc kp xp sp mp k x s mf pc
  A=$(ls "$H"/out/*.tar.gz 2>/dev/null | head -n 1)
  [ -n "$A" ] || { echo "ARCH $1 $2 archive=missing"; return; }
  l="$E/$1.$2.list"; tar -tzf "$A" > "$l" 2> "$l.err"; trc=$?
  kp=$(grep -m1 '/state/sibling/keep\.txt$' "$l"); xp=$(grep -m1 '/state/labvol/x\.txt$' "$l")
  sp=$(grep -m1 '/SENTINEL-194166\.txt$' "$l"); mp=$(grep -m1 -E '^[^/]+/manifest\.json$' "$l")
  k=ABSENT; [ -n "$kp" ] && k=$(tar -xOzf "$A" "$kp" | one)
  x=ABSENT; [ -n "$xp" ] && x=$(tar -xOzf "$A" "$xp" | one)
  s=ABSENT; [ -n "$sp" ] && s=$(tar -xOzf "$A" "$sp" | one)
  mf=0
  if [ -n "$mp" ]; then
    tar -xOzf "$A" "$mp" > "$E/$1.$2.manifest.json"
    node "$JH" scan "$E/$1.$2.manifest.json" > "$E/$1.$2.manifest.scan"
    mf=$(grep -c '^FOUND_REASON unreadable-foreign .*\.fseventsd$' "$E/$1.$2.manifest.scan")
  fi
  pc=$(grep -c '/state/priv/' "$l")
  echo "ARCH $1 $2 tar_rc=$trc entries=$(wc -l < "$l" | tr -d ' ') fse_entries=$(grep -c '/labvol/\.fseventsd' "$l") keep=$k x=$x sentinel=$s manifest=$([ -n "$mp" ] && echo present || echo absent) manifest_foreign_fse=$mf priv_entries=$pc archive=$(basename "$A")"
}
gone() { [ ! -e "$1" ] && echo "CLEAN $2 ok" || { echo "CLEAN $2 FAILED $1"; return 1; }; }

step=${1:-}; shift || true
[ "$(id -u)" != 0 ] || { echo "REFUSE running as root"; exit 99; }
echo "STEP $step $* start=$(ts)"
case "$step" in
  info)
    sw_vers; uname -m; id; node --version; npm --version; npm prefix -g; npm root -g; command -v openclaw
    openclaw --version 2>&1 | tail -n 1; perl -v | sed -n 2p; df -h "$HOME" | tail -n 1
    grep -rl "denied path is unknown or outside the install root" "$(npm root -g)/openclaw/dist" 2>/dev/null | head -n 3
    echo "grep194160 done" ;;
  prep)
    detach_all; rm -f "$K/labvol.dmg"
    hdiutil create -size 64m -fs APFS -volname labvol "$K/labvol.dmg" > "$E/prep.dmg.txt" 2>&1
    echo "PREP dmg rc=$? sha256=$(shasum -a 256 "$K/labvol.dmg" | cut -d' ' -f1)" ;;
  install)
    L=$1; T=$2; detach_all
    npm uninstall -g openclaw > "$E/install-$T.uninstall.txt" 2>&1
    if [ "$L" = rel ]; then spec=openclaw@2026.11.3
    else spec=$K/pkgs/openclaw-$L.tgz; [ -f "$spec" ] || { echo "INSTALL $L $T rc=98 reason=missing-$spec"; exit 98; }; fi
    { echo "+ npm install -g $spec [$(ts)]"; tmo 1200 npm install -g "$spec" --no-fund --no-audit; echo "rc=$?"; } > "$E/install-$T.txt" 2>&1
    rc=$(sed -n 's/^rc=//p' "$E/install-$T.txt" | tail -n 1)
    echo "INSTALL $L $T rc=$rc version=$(openclaw --version 2>/dev/null | tail -n 1 | one) buildid=$(node "$JH" buildid "$(npm root -g)") which=$(command -v openclaw)"
    npm ls -g openclaw 2>&1 | sed 's/^/NPMLS /' ;;
  bk)
    L=$1; NS=$2; NK=$3; NX=$4; T=bk-$L
    mkhome "$T" || exit 3
    fixture "$NS" "$NK"
    bk_run "$T" B0; arch "$T" B0
    attach "$W" "$T-B1" "$NX" || { echo "BLOCKED $T reason=attach"; exit 4; }
    probe "$W" "$T-B1"
    rc=$(oc "$E/$T.B1.dryrun.txt" 300 backup create --dry-run --json)
    echo "DRY $T B1 rc=$rc refusal=$(refusal "$E/$T.B1.dryrun.txt" "$rc") skipwarn=$(grep -c 'Skipped unreadable foreign entry' "$E/$T.B1.dryrun.txt")"
    bk_run "$T" B1; arch "$T" B1
    detach "$W" "$T-B1"
    bk_run "$T" B2
    # Refusal controls: each alone, volume detached, cleaned up before the next. Never weakened, never bypassed.
    mkdir -m 000 "$W/owned"; bk_run "$T" N1; chmod 700 "$W/owned"; rmdir "$W/owned"; gone "$W/owned" N1 || exit 5
    mkdir "$W/owned2"; printf '%s\n' "$MARKC" > "$W/owned2/$MARK"; chmod 000 "$W/owned2/$MARK"
    bk_run "$T" N2; chmod 600 "$W/owned2/$MARK"; rm -rf "$W/owned2"; gone "$W/owned2" N2 || exit 5
    mkdir "$W/bad"; printf 'not-a-valid-marker\n' > "$W/bad/$MARK"
    bk_run "$T" N3; rm -rf "$W/bad"; gone "$W/bad" N3 || exit 5
    mkdir "$W/priv"; printf '%s\n' "$MARKC" > "$W/priv/$MARK"; printf 'synthetic-private\n' > "$W/priv/secret.txt"
    bk_run "$T" N4; arch "$T" N4; rm -rf "$W/priv"; gone "$W/priv" N4 || exit 5
    asroot mkdir -m 755 "$W/fmark"
    asroot /bin/sh -c "printf '%s\n' $MARKC > '$W/fmark/$MARK' && chmod 600 '$W/fmark/$MARK'"
    ls -leOd "$W/fmark" "$W/fmark/$MARK" 2>&1 | sed 's/^/LS N5 /'
    cat "$W/fmark/$MARK" > /dev/null 2> "$E/$T.N5.cat.txt"; echo "N5PROBE read_rc=$? eacces=$(grep -c 'Permission denied' "$E/$T.N5.cat.txt")"
    bk_run "$T" N5; asroot rm -rf "$W/fmark"; gone "$W/fmark" N5 || exit 5
    for c in B0 B1 B2 N1 N2 N3 N4 N5; do echo "--- tail $T $c"; tail -n 25 "$E/$T.$c.backup.txt"; done ;;
  up)
    R=$1; TGT=$2; ATT=$3; NS=$4; NK=$5; NX=$6; T=up-$R
    mkhome "$T" || exit 3
    fixture "$NS" "$NK"
    echo "CFGSET $T rc=$(oc "$E/$T.cfgset.txt" 120 config set logging.audit.executionIdentity true)"
    vb=$(openclaw --version 2>/dev/null | tail -n 1 | one); bb=$(node "$JH" buildid "$(npm root -g)")
    oc "$E/$T.status.txt" 180 update status --json > /dev/null
    trig=na
    if [ "$ATT" = 1 ]; then
      attach "$W" "$T" "$NX" || { echo "BLOCKED $T reason=attach"; exit 4; }
      probe "$W" "$T"; trig=$(grep -c 'Permission denied' "$E/probe.$T.txt")
    fi
    NR=$(npm root -g); echo "NPMW $T root=$NR $(ls -ld "$NR" | one) which=$(command -v openclaw) touch_rc=$(touch "$NR/.w194166" 2>/dev/null; echo $?)"; rm -f "$NR/.w194166"
    rc=$(oc "$E/$T.update.txt" 1500 update --tag "$TGT" --yes --no-restart --json)
    f="$E/$T.update.txt"
    va=$(openclaw --version 2>/dev/null | tail -n 1 | one); ba=$(node "$JH" buildid "$(npm root -g)")
    CR="$STATE.update-captures"; nman=0; exf=0
    for m in $(find "$CR" -name manifest.json -type f 2>/dev/null); do
      nman=$((nman + 1)); node "$JH" scan "$m" > "$E/$T.capture$nman.scan"
      cp "$m" "$E/$T.capture$nman.manifest.json"
      exf=$((exf + $(grep -c '^FOUND_EXCLUDED .*\.fseventsd$' "$E/$T.capture$nman.scan")))
    done
    s=$(cat "$WORKSPACE/SENTINEL-194166.txt" 2>&1 | one); k=$(cat "$W/sibling/keep.txt" 2>&1 | one)
    cfg=$(tmo 120 openclaw config get logging.audit.executionIdentity 2>/dev/null | tail -n 1 | one)
    echo "UP $R rc=$rc trigger=$trig target=$TGT ver_before=$vb ver_after=$va bi_before=$bb bi_after=$ba capture_unavailable=$(grep -ci 'original state capture is unavailable' "$f") nosnap_space=$(grep -c 'NO ORIGINAL-STATE SNAPSHOT: insufficient disk space' "$f") skipwarn=$(grep -c 'Skipped unreadable foreign entry' "$f") perm_denied=$(grep -c 'global-install-permission-denied' "$f") cannot_write=$(grep -c 'cannot write' "$f") capture_manifests=$nman excluded_fse=$exf sentinel=$s keep=$k cfg=$cfg"
    bk_run "$T" POST
    [ "$ATT" = 1 ] && { arch "$T" POST; detach "$W" "$T"; }
    ls -la "$CR" 2>&1 | sed 's/^/CAPDIR /'
    echo "--- tail $T update"; tail -n 60 "$f"; echo "--- tail $T POST"; tail -n 25 "$E/$T.POST.backup.txt" ;;
  pack)
    detach_all; rm -f "$K/ev.tgz"; tar -czf "$K/ev.tgz" -C "$K" ev
    echo "PACK rc=$? sha256=$(shasum -a 256 "$K/ev.tgz" | cut -d' ' -f1) bytes=$(stat -f %z "$K/ev.tgz")" ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
echo "STEP $step end=$(ts)"
