#!/bin/bash
set -x
date -u +%FT%TZ
mkdir -p /home/lab/t191855/.openclaw/workspace/state
chown lab:lab /home/lab/t191855/.openclaw/workspace/state
mkdir -m 700 /home/lab/t191855/.openclaw/workspace/state/foreign
ls -ld /home/lab/t191855/.openclaw/workspace/state/foreign
date -u +%FT%TZ