#!/bin/bash
export OPENCLAW_HOME=/home/lab/t191855
set -x
date -u +%FT%TZ
STATE=/home/lab/t191855/.openclaw
W=/home/lab/t191855/.openclaw/workspace/state
openclaw backup create --verify --json --output /home/lab/t191855-out; echo "backup rc=$?"
date -u +%FT%TZ