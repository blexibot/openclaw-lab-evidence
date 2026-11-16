#!/bin/bash
# run.sh [AB|A|B] : #182520 kit entry point INSIDE the Linux bench (as root, kit in /root/kit).
# Part A (stand-in server, ~6 min) then Part B (managed llama.cpp, ~15-60 min). Output: /root/t182520/out/
# (A.log, B.log, A/, B/, versions.txt). The last lines are RESULT_A and RESULT_B (or "not run").
K=/root/kit; OUT=/root/t182520/out; PARTS=${1:-AB}; mkdir -p "$OUT"
for d in "$HOME/.npm-global/bin" /usr/local/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done; export PATH
{ date -u +%FT%TZ; openclaw --version; node --version; uname -a; head -2 /etc/os-release; sha256sum "$K"/*; } > "$OUT/versions.txt" 2>&1
cat "$OUT/versions.txt"
RA="RESULT_A=not run"; RB="RESULT_B=not run"
case "$PARTS" in *A*) bash "$K/partA.sh" "$K" "$OUT" > "$OUT/A.log" 2>&1; RA=$(grep -h '^RESULT_A=' "$OUT/A/summary.txt" 2>/dev/null | tail -1); RA=${RA:-RESULT_A=missing (see A.log)};; esac
echo "$RA"
case "$PARTS" in *B*) bash "$K/partB.sh" "$K" "$OUT" > "$OUT/B.log" 2>&1; RB=$(grep -h '^RESULT_B=' "$OUT/B/summary.txt" 2>/dev/null | tail -1); RB=${RB:-RESULT_B=missing (see B.log)};; esac
echo "$RB"
echo "== A summary"; cat "$OUT/A/summary.txt" 2>/dev/null
echo "== B summary"; cat "$OUT/B/summary.txt" 2>/dev/null
echo "T182520 $RA"
echo "T182520 $RB"
