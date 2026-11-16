#!/bin/bash
export OPENCLAW_HOME=/home/lab/t191855
W=/home/lab/t191855/.openclaw/workspace/state
set -x
date -u +%FT%TZ
echo "=== N1: owned dir, mode 000 ==="
mkdir -m 000 "$W/owned"; echo "mkdir rc=$?"
ls -ld "$W/owned"
stat "$W/owned/.openclaw-private-update-capture"; echo "stat rc=$?"
node /home/lab/pr/openclaw.mjs backup create --verify --json --output /home/lab/t191855-out; echo "N1 backup rc=$?"
chmod 700 "$W/owned"; rmdir "$W/owned"; echo "n1 cleanup rc=$?"
echo "=== N2: owned marker unreadable ==="
mkdir "$W/owned2"; echo "mkdir rc=$?"
printf 'openclaw-private-update-capture-v1\n' > "$W/owned2/.openclaw-private-update-capture"; echo "write rc=$?"
chmod 000 "$W/owned2/.openclaw-private-update-capture"; echo "chmod rc=$?"
node /home/lab/pr/openclaw.mjs backup create --verify --json --output /home/lab/t191855-out; echo "N2 backup rc=$?"
chmod 600 "$W/owned2/.openclaw-private-update-capture"; rm -r "$W/owned2"; echo "n2 cleanup rc=$?"
date -u +%FT%TZ