#!/bin/bash
# l194166-build.sh <label> <full sha> <srcname> (Linux build container, AS USER lab): fetch one exact commit, install
# its locked dependencies, and pack it with the repository's own self-contained source packager
# (scripts/package-openclaw-for-docker.mjs, identical blob at base and head). Prints one BUILD_RESULT line.
# A second call with the same <srcname> reuses the checkout and rebuilds (new build timestamp = new build identity).
set -u
L=$1; SHA=$2; SRC=/home/lab/src-$3; OUT=/home/lab/out-$1
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
echo "BUILD_START label=$L sha=$SHA src=$SRC $(date -u +%FT%TZ)"
# r2 (11-16): r1's head fetch crawled ~45 KB/s for 69 min then died (early EOF), and head2 then reused the empty
# checkout. Now: a checkout without the pinned commit is discarded; each fetch attempt aborts if it stays under
# 50 KB/s for 120 s or exceeds 20 min; up to 3 attempts, each from a clean dir, each logged with its elapsed time.
if [ -d "$SRC/.git" ] && [ "$(git -C "$SRC" rev-parse -q --verify HEAD 2>/dev/null)" != "$SHA" ]; then
  echo "SRC_DISCARD src=$SRC reason=no-pinned-commit"; rm -rf "$SRC"
fi
if [ ! -d "$SRC/.git" ]; then
  ok=0
  for a in 1 2 3; do
    rm -rf "$SRC"; mkdir -p "$SRC"; cd "$SRC" || break
    git init -q && git remote add origin https://github.com/openclaw/openclaw.git
    t0=$(date +%s)
    timeout 1200 git -c http.lowSpeedLimit=51200 -c http.lowSpeedTime=120 fetch -q --depth 1 origin "$SHA"; frc=$?
    echo "FETCH_ATTEMPT label=$L n=$a rc=$frc secs=$(( $(date +%s) - t0 ))"
    if [ "$frc" -eq 0 ] && git checkout -q FETCH_HEAD; then ok=1; break; fi
  done
  [ "$ok" = 1 ] || { rm -rf "$SRC"; echo "BUILD_RESULT label=$L rc=80 stage=fetch"; exit 80; }
  if ! pnpm install --frozen-lockfile > "/home/lab/install-$3.log" 2>&1; then
    tail -n 40 "/home/lab/install-$3.log"; echo "BUILD_RESULT label=$L rc=81 stage=install"; exit 81
  fi
  echo "INSTALL_DONE src=$3 $(date -u +%FT%TZ)"
fi
cd "$SRC" || { echo "BUILD_RESULT label=$L rc=84 stage=cd"; exit 84; }
got=$(git rev-parse HEAD)
[ "$got" = "$SHA" ] || { echo "BUILD_RESULT label=$L rc=82 stage=sha got=$got"; exit 82; }
echo "DIRTY_BEFORE_PACK label=$L lines=$(git status --porcelain | wc -l)"
rm -rf "$OUT"; mkdir -p "$OUT" /home/lab/pkgs
node scripts/package-openclaw-for-docker.mjs --allow-unreleased-changelog --output-dir "$OUT" \
  > "$OUT/stdout.txt" 2> "$OUT/stderr.txt"
rc=$?
T=$(tail -n 1 "$OUT/stdout.txt")
if [ "$rc" -ne 0 ] || [ ! -f "$T" ]; then
  tail -n 60 "$OUT/stderr.txt"; echo "BUILD_RESULT label=$L rc=$rc stage=package tgz=missing"; exit 83
fi
P=/home/lab/pkgs/openclaw-$L.tgz
cp "$T" "$P"
S=$(sha256sum "$P" | cut -d' ' -f1)
B=$(tar -xOzf "$P" package/dist/build-info.json 2>/dev/null |
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).buildId||"none")}catch{console.log("none")}})')
echo "BUILD_RESULT label=$L rc=0 sha=$SHA tgz=$(basename "$T") bytes=$(stat -c %s "$P") sha256=$S buildid=$B"
date -u +%FT%TZ
