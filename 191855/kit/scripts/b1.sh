#!/bin/bash
export OPENCLAW_HOME=/home/lab/t191855
set -x
date -u +%FT%TZ
head -2 /etc/os-release
node --version
openclaw --version
id
mkdir -p $OPENCLAW_HOME /home/lab/t191855-out
openclaw setup --baseline; echo "setup rc=$?"
openclaw backup create --dry-run --json; echo "dryrun rc=$?"
openclaw backup create --verify --json --output /home/lab/t191855-out; echo "backup rc=$?"
ls -la $OPENCLAW_HOME $OPENCLAW_HOME/.openclaw
date -u +%FT%TZ