#!/bin/bash
# d194166.sh (macOS host, as the lab user; started detached by s194166.sh with J and HARD_STOP_EPOCH set): T194166.
# Builds PR #194166's base and head (and a second head package, "head2", used as the update TARGET) from source on a
# throwaway Linux container, then runs the same macOS backup and update kit against: shipped 2026.11.3 (release
# reference), base and head. All decisions about outcomes are mechanical and printed as V194166/SUMMARY lines.
# The controller (this script, outside every bench) generates the nonces and compares what comes back.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); J=${J:?}; HSE=${HARD_STOP_EPOCH:?}; OUT=$J/out; P=$J/pkgs; mkdir -p "$OUT" "$P"
BASE=8dd41fc95291553e5885fec09992bd41c3038004; HEAD=5438a832520be89cde6799215b99a711fc039950
LX=(ssh -i "$HOME/.ssh/<KEY>" -o BatchMode=yes -o ServerAliveInterval=30 <LAB-USER>@<LAB-LINUX-HOST>)
TART=<VM-TOOL>; MAC=t194166-mac; LIN=t194166-bld; GK='~/k194166'
# Offline test hooks only (offline stub run). Never set these in the lab.
[ -n "${D194166_TEST_TART:-}" ] && TART=$D194166_TEST_TART; [ -n "${D194166_TEST_LX:-}" ] && LX=("$D194166_TEST_LX")
ts() { date -u +%FT%TZ; }
V() { echo "V194166 $(ts) $*" | tee -a "$J/verdicts.txt"; }
left() { echo $(( (HSE - $(date -u +%s)) / 60 )); }
need() { [ "$(left)" -ge "$1" ] || { V "SKIP $2 reason=time-box left_min=$(left) need_min=$1"; return 1; }; }
nonce() { od -An -tx1 -N8 /dev/urandom | tr -d ' \n'; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
kv() { grep -m1 "^$1" "$2" 2>/dev/null | tr ' ' '\n' | sed -n "s/^$3=//p" | head -n 1; }
mx() { "$TART" exec "$MAC" "$1"; }   # one argument = one shell string in the guest
mpush() { # mpush <local file> <guest path>: copy by stdin, then prove the bytes with sha256 on both sides
  mx "cat > $2" < "$1"; local g; g=$(mx "shasum -a 256 $2" | cut -d' ' -f1)
  [ "$g" = "$(sha "$1")" ] && { V "PUSH $(basename "$1") sha256=$g ok"; return 0; }
  V "PUSH $(basename "$1") MISMATCH local=$(sha "$1") guest=$g"; mx "rm -f $2"; return 1
}
inst_ok() { # inst_ok <outname> <label>: the runner really is the build we meant (rc 0 and the banner's commit)
  local f="$OUT/m-$1.txt" v want
  case "$2" in base) want="(8dd41fc)" ;; head) want="(5438a83)" ;; *) want="2026.11.3" ;; esac
  v=$(grep -m1 '^INSTALL ' "$f" | tr ' ' '\n' | sed -n 's/^version=//p')
  [ "$(kv "INSTALL $2 " "$f" rc)" = 0 ] && case "$v" in *"$want"*) true ;; *) false ;; esac &&
    { V "RUNNER $1 ok version=$v"; return 0; }
  V "RUNNER $1 WRONG version=$v want=$want"; return 1
}
mstep() { # mstep <outname> <guest args...>: run one guest step, output to out/m-<outname>.txt
  local o="$OUT/m-$1.txt"; shift
  mx "bash $GK/m194166.sh $*" > "$o" 2>&1; echo "host-rc=$?" >> "$o"
  grep -E '^(STEP|INSTALL|SETUP|PLAN|BLOCKED|ATTACH|DETACH|TRIGGER|DRY|BK|ARCH|UP|CFGSET|CLEAN|N5PROBE|PREP|PACK|REFUSE|NPMW)' "$o" |
    sed "s/^/[$(basename "$o" .txt)] /" >> "$J/verdicts.txt"
}
lpush() { # lpush <file>: into the Linux container as /home/lab/<file>, then compare sha256
  "${LX[@]}" "bench exec $LIN -- tee /home/lab/$1" < "$HERE/$1" > /dev/null
  local g; g=$("${LX[@]}" "bench exec $LIN -- sha256sum /home/lab/$1" | cut -d' ' -f1)
  [ "$g" = "$(sha "$HERE/$1")" ] && { echo "LPUSH $1 ok"; return 0; }; echo "LPUSH $1 MISMATCH"; return 1
}
linux_build() { # background job: one container, three packages; the container is destroyed on every path
  linux_build_inner; local rc=$?
  "${LX[@]}" "bench destroy $LIN"; "${LX[@]}" "bench list" | sed 's/^/LBENCH-END /'
  return $rc
}
linux_build_inner() { # base, head, head2 packages; pull each and check its sha256
  "${LX[@]}" "bench list" | sed 's/^/LBENCH-START /'
  "${LX[@]}" "bench new ubuntu/24.04 $LIN" || { echo "LBUILD blocked reason=bench-new"; return 10; }
  "${LX[@]}" "bench openclaw $LIN 2026.11.3" || { echo "LBUILD blocked reason=node-install"; return 11; }
  "${LX[@]}" "bench exec $LIN -- useradd -m -s /bin/bash lab"
  lpush l194166-prep.sh && lpush l194166-build.sh || return 12
  "${LX[@]}" "bench exec $LIN -- bash /home/lab/l194166-prep.sh" > "$OUT/l-prep.txt" 2>&1
  grep -q '^PREP_DONE' "$OUT/l-prep.txt" || { echo "LBUILD blocked reason=prep"; return 13; }
  local spec l s src r t
  for spec in "base $BASE base" "head $HEAD head" "head2 $HEAD head"; do
    set -- $spec; l=$1; s=$2; src=$3
    [ "$(left)" -ge 45 ] || { echo "LBUILD $l skipped reason=time-box"; continue; }
    "${LX[@]}" "bench exec $LIN -- su - lab -c \"bash /home/lab/l194166-build.sh $l $s $src\"" > "$OUT/l-build-$l.txt" 2>&1
    r=$(grep -m1 '^BUILD_RESULT' "$OUT/l-build-$l.txt"); echo "LBUILD $l $r"
    "${LX[@]}" "bench exec $LIN -- cat /home/lab/out-$l/stderr.txt" > "$OUT/l-pack-$l.stderr.txt" 2>&1
    [ "$(echo "$r" | tr ' ' '\n' | sed -n 's/^rc=//p')" = 0 ] || continue
    "${LX[@]}" "bench exec $LIN -- cat /home/lab/pkgs/openclaw-$l.tgz" > "$P/openclaw-$l.tgz"
    t=$(echo "$r" | tr ' ' '\n' | sed -n 's/^sha256=//p')
    if [ "$(sha "$P/openclaw-$l.tgz")" = "$t" ]; then echo "LPULL $l sha256=$t ok"
    else echo "LPULL $l MISMATCH local=$(sha "$P/openclaw-$l.tgz") remote=$t"; rm -f "$P/openclaw-$l.tgz"; fi
  done
  return 0
}
pbid() { tar -xOzf "$1" package/dist/build-info.json 2>/dev/null | /usr/bin/python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("buildId","none").replace(" ","_"))
except Exception: print("none")'; }

V "START hard_stop_epoch=$HSE left_min=$(left) base=$BASE head=$HEAD"
"$TART" list > "$OUT/bench-list-start-mac.txt" 2>&1
( linux_build > "$OUT/linux-build.txt" 2>&1; echo $? > "$OUT/linux.exit" ) &
LPID=$!
V "LINUX_BUILD started pid=$LPID (base, head, head2; expect 25-50 min)"

# --- macOS bench and the release reference (runs while the Linux builds run)
if "$TART" new "$MAC" > "$OUT/mac-new.txt" 2>&1 && "$TART" openclaw "$MAC" 2026.11.3 >> "$OUT/mac-new.txt" 2>&1; then
  MACOK=1; V "MAC_BENCH up $(tail -n 1 "$OUT/mac-new.txt")"
else
  MACOK=0; V "MAC_BENCH blocked $(tail -n 2 "$OUT/mac-new.txt" | tr '\n' ' ')"
fi
if [ "$MACOK" = 1 ]; then
  mx "mkdir -p $GK/pkgs $GK/ev"
  mpush "$HERE/m194166.sh" "$GK/m194166.sh" && mpush "$HERE/j194166.mjs" "$GK/j194166.mjs" || MACOK=0
fi
NS=$(nonce); NK=$(nonce); NX=$(nonce)
V "NONCES sentinel=$NS keep=$NK x=$NX"
if [ "$MACOK" = 1 ]; then
  mstep info info; mstep prep prep
  need 15 bk-rel && mstep bk-rel bk rel "$NS" "$NK" "$NX"
  need 20 up-rel-att && mstep up-rel-att up rel-att 2026.11.4 1 "$NS" "$NK" "$NX"
fi

# --- wait for the builds
wait "$LPID"; V "LINUX_BUILD exit=$(cat "$OUT/linux.exit" 2>/dev/null) $(grep -E '^(LBUILD|LPULL)' "$OUT/linux-build.txt" | tr '\n' ' ')"
PRNOW=$(sed -n 's/^LSREMOTE \([0-9a-f]*\)[[:space:]]*refs\/pull\/194166\/head$/\1/p' "$OUT/l-prep.txt" 2>/dev/null)
V "PR_HEAD now=${PRNOW:-unknown} pinned=$HEAD moved=$([ "${PRNOW:-}" = "$HEAD" ] && echo no || echo yes-or-unknown)"
for l in base head head2; do [ -f "$P/openclaw-$l.tgz" ] && V "PKG $l sha256=$(sha "$P/openclaw-$l.tgz") buildid=$(pbid "$P/openclaw-$l.tgz")"; done
B2=$( [ -f "$P/openclaw-head2.tgz" ] && pbid "$P/openclaw-head2.tgz" ); B1=$( [ -f "$P/openclaw-head.tgz" ] && pbid "$P/openclaw-head.tgz" )
if [ "$MACOK" = 1 ]; then
  for l in base head head2; do [ -f "$P/openclaw-$l.tgz" ] && mpush "$P/openclaw-$l.tgz" "$GK/pkgs/openclaw-$l.tgz"; done
  TGT="/Users/admin/k194166/pkgs/openclaw-head2.tgz"
  # Backup matrix on base and head (same kit, same guest, fresh home each, made by that runner).
  for l in base head; do
    [ -f "$P/openclaw-$l.tgz" ] || { V "SKIP bk-$l reason=no-package"; continue; }
    need 15 "bk-$l" && mstep "install-$l-bk" install "$l" "$l-bk" && inst_ok "install-$l-bk" "$l" && mstep "bk-$l" bk "$l" "$NS" "$NK" "$NX"
  done
  # Update rows: every runner is an INSTALLED npm-mode package; the target is the same head2 package for all
  # candidate rows, so only the runner differs between base-att and head-att.
  V "TARGET head2 buildid=${B2:-none} (head buildid=${B1:-none}; must differ or the update may be a no-op)"
  if [ -f "$P/openclaw-head2.tgz" ]; then
    for row in "head-att head 1" "base-att base 1" "base-det base 0" "head-det head 0"; do
      set -- $row
      [ -f "$P/openclaw-$2.tgz" ] || { V "SKIP up-$1 reason=no-package"; continue; }
      need 20 "up-$1" || continue
      mstep "install-$1" install "$2" "$1" && inst_ok "install-$1" "$2" && mstep "up-$1" up "$1" "$TGT" "$3" "$NS" "$NK" "$NX"
    done
  else
    V "SKIP update-rows reason=no-head2-package"
  fi
  mstep pack pack
  GSHA=$(kv "PACK " "$OUT/m-pack.txt" sha256)
  mx "cat $GK/ev.tgz" > "$J/guest-ev.tgz"
  [ "$(sha "$J/guest-ev.tgz")" = "$GSHA" ] && V "PULL guest-ev.tgz sha256=$GSHA ok" || V "PULL guest-ev.tgz MISMATCH local=$(sha "$J/guest-ev.tgz") guest=$GSHA"
fi
"$TART" destroy "$MAC" > "$OUT/mac-destroy.txt" 2>&1; V "MAC_DESTROY rc=$?"
"$TART" list > "$OUT/bench-list-end-mac.txt" 2>&1
grep -q "^$MAC," "$OUT/bench-list-end-mac.txt" && V "LEFTOVER $MAC" || V "NO_LEFTOVER $MAC"
"${LX[@]}" "bench list" > "$OUT/bench-list-end-lin.txt" 2>&1
grep -q "^$LIN," "$OUT/bench-list-end-lin.txt" && V "LEFTOVER $LIN" || V "NO_LEFTOVER $LIN"

# --- mechanical outcomes (LAB-EVIDENCE-RULES §2 vocabulary)
bk_outcome() { # bk_outcome <label>
  local L=$1 f="$OUT/m-bk-$1.txt" T="bk-$1" t rc rf bad=""
  rc=$(kv "BK $T B1 " "$f" rc); t=$(kv "TRIGGER $T-B1 " "$f" eacces)
  [ -n "$rc" ] || { echo "inconclusive / harness failure|no B1 result"; return; }
  [ "${t:-0}" -ge 1 ] || { echo "blocked|trigger not reached (no EACCES on the marker inside .fseventsd)"; return; }
  rf=$(kv "BK $T B1 " "$f" refusal)
  if [ "$L" != head ]; then
    if [ "$rc" != 0 ] && [ "$rf" = unreadable ]; then echo "reproduced|B1 rc=$rc refusal=$rf"
    elif [ "$rc" = 0 ]; then echo "not reproduced under these conditions|B1 rc=0 with the trigger reached"
    else echo "inconclusive / harness failure|B1 rc=$rc refusal=$rf"; fi
    return
  fi
  local c miss=""
  for c in B0 B1 B2 N1 N2 N3 N4 N5; do [ -n "$(kv "BK $T $c " "$f" rc)" ] || miss="$miss $c"; done
  [ "$rc" != 0 ] || [ -n "$(kv "ARCH $T B1 " "$f" fse_entries)" ] || miss="$miss ARCH-B1"
  [ -z "$miss" ] || { echo "inconclusive / harness failure|missing results:$miss"; return; }
  [ "$(kv "BK $T B0 " "$f" rc)" = 0 ] || bad="$bad B0"
  [ "$rc" = 0 ] || bad="$bad B1.rc=$rc/$rf"
  [ "$(kv "BK $T B1 " "$f" skipwarn)" -ge 1 ] 2>/dev/null || bad="$bad B1.no-skip-warning"
  [ "$(kv "ARCH $T B1 " "$f" fse_entries)" = 0 ] || bad="$bad B1.fseventsd-in-archive"
  [ "$(kv "ARCH $T B1 " "$f" keep)" = "$NK" ] || bad="$bad B1.sibling-keep"
  [ "$(kv "ARCH $T B1 " "$f" x)" = "$NX" ] || bad="$bad B1.volume-sibling-x"
  [ "$(kv "ARCH $T B1 " "$f" sentinel)" = "$NS" ] || bad="$bad B1.sentinel"
  [ "$(kv "ARCH $T B1 " "$f" manifest_foreign_fse)" -ge 1 ] 2>/dev/null || bad="$bad B1.no-manifest-entry"
  [ "$(kv "BK $T B2 " "$f" rc)" = 0 ] || bad="$bad B2"
  [ "$(kv "BK $T N1 " "$f" refusal)" = unreadable ] || bad="$bad N1"
  [ "$(kv "BK $T N2 " "$f" refusal)" = invalid ] || bad="$bad N2"
  [ "$(kv "BK $T N3 " "$f" refusal)" = invalid ] || bad="$bad N3"
  [ "$(kv "BK $T N4 " "$f" rc)" = 0 ] && [ "$(kv "ARCH $T N4 " "$f" priv_entries)" = 0 ] || bad="$bad N4"
  [ "$(kv "BK $T N5 " "$f" refusal)" = invalid ] || bad="$bad N5"
  if [ -z "$bad" ]; then echo "candidate passes this scenario|all 13 checks passed"
  else echo "reproduced|on the candidate, failed:$bad"; fi
}
up_outcome() { # up_outcome <row>
  local R=$1 f="$OUT/m-up-$1.txt" rc t cu bad=""
  rc=$(kv "UP $R " "$f" rc); t=$(kv "UP $R " "$f" trigger); cu=$(kv "UP $R " "$f" capture_unavailable)
  [ -n "$rc" ] || { echo "inconclusive / harness failure|no UP line"; return; }
  case "$R" in *-att) [ "${t:-0}" -ge 1 ] 2>/dev/null || { echo "blocked|trigger not reached"; return; } ;; esac
  case "$R" in
    rel-att|base-att)
      if [ "${cu:-0}" -ge 1 ]; then echo "reproduced|original-state capture unavailable; update rc=$rc"
      else echo "not reproduced under these conditions|capture_unavailable=0; update rc=$rc"; fi
      return ;;
    base-det)
      [ "$rc" = 0 ] && [ "${cu:-0}" = 0 ] && echo "control passed|rc=0 capture_unavailable=0" ||
        echo "control failed|rc=$rc capture_unavailable=$cu"
      return ;;
  esac
  [ -n "$(kv "BK up-$R POST " "$f" rc)" ] || { echo "inconclusive / harness failure|no POST backup line"; return; }
  [ "$(kv "UP $R " "$f" bi_after)" != "$(kv "UP $R " "$f" bi_before)" ] || [ "$rc" != 0 ] ||
    { echo "blocked|update exited 0 without changing the build identity (no-op)"; return; }
  [ "$rc" = 0 ] || bad="$bad rc=$rc"
  [ "${cu:-0}" = 0 ] || bad="$bad capture-unavailable"
  [ "$(kv "UP $R " "$f" bi_after)" = "$B2" ] || bad="$bad not-head2-after"
  [ "$(kv "UP $R " "$f" sentinel)" = "$NS" ] || bad="$bad sentinel"
  [ "$(kv "UP $R " "$f" keep)" = "$NK" ] || bad="$bad keep"
  [ "$(kv "UP $R " "$f" cfg)" = true ] || bad="$bad cfg"
  [ "$(kv "BK up-$R POST " "$f" rc)" = 0 ] || bad="$bad post-backup"
  if [ "$R" = head-att ]; then
    [ "$(kv "UP $R " "$f" capture_manifests)" -ge 1 ] 2>/dev/null || bad="$bad no-capture-manifest"
    [ "$(kv "UP $R " "$f" excluded_fse)" -ge 1 ] 2>/dev/null || bad="$bad fseventsd-not-in-excludedRoots"
  fi
  if [ -z "$bad" ]; then echo "candidate passes this scenario|all checks passed"
  else echo "reproduced|on the candidate, failed:$bad"; fi
}
for l in rel base head; do [ -f "$OUT/m-bk-$l.txt" ] && V "SUMMARY bk-$l outcome=\"$(bk_outcome "$l" | cut -d'|' -f1)\" detail=\"$(bk_outcome "$l" | cut -d'|' -f2)\"" || V "SUMMARY bk-$l outcome=\"not run\""; done
for r in rel-att head-att base-att base-det head-det; do [ -f "$OUT/m-up-$r.txt" ] && V "SUMMARY up-$r outcome=\"$(up_outcome "$r" | cut -d'|' -f1)\" detail=\"$(up_outcome "$r" | cut -d'|' -f2)\"" || V "SUMMARY up-$r outcome=\"not run\""; done
BB=$(bk_outcome base | cut -d'|' -f1); BH=$(bk_outcome head | cut -d'|' -f1)
UB=$(up_outcome base-att | cut -d'|' -f1); UD=$(up_outcome base-det | cut -d'|' -f1); UH=$(up_outcome head-att | cut -d'|' -f1)
A1=no; [ "$BB" = reproduced ] && [ "$BH" = "candidate passes this scenario" ] && A1=yes
A2=no; [ "$UB" = reproduced ] && [ "$UD" = "control passed" ] && [ "$UH" = "candidate passes this scenario" ] && A2=yes
V "ATTRIBUTION backup=$A1 update=$A2 (yes = fails at base $BASE, passes at $HEAD, same kit and guest)"
RES=stopped
if [ "$A1" = yes ] && [ "$A2" = yes ]; then RES=passed
else
  definite=1
  for o in "$BB" "$BH" "$UB" "$UH"; do
    case "$o" in reproduced|"not reproduced under these conditions"|"candidate passes this scenario") ;; *) definite=0 ;; esac
  done
  [ "$definite" = 1 ] && RES=failed
fi
V "RESULT_SUGGESTED=$RES left_min=$(left)"
exit 0
