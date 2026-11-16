#!/bin/bash
export OPENCLAW_HOME=/home/lab/t191855
W=/home/lab/t191855/.openclaw/workspace/state
set -x
date -u +%FT%TZ
node /home/lab/pr/openclaw.mjs --version; echo "version rc=$?"
stat "$W/foreign/.openclaw-private-update-capture"; echo "stat rc=$?"
node /home/lab/pr/openclaw.mjs backup create --dry-run --json; echo "dryrun rc=$?"
node /home/lab/pr/openclaw.mjs backup create --verify --json --output /home/lab/t191855-out; echo "backup rc=$?"
date -u +%FT%TZ