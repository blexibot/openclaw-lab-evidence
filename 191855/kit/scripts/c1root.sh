#!/bin/bash
W=/home/lab/t191855/.openclaw/workspace/state
set -x
date -u +%FT%TZ
mkdir -p "$W"
chown lab:lab "$W"
mkdir -m 700 "$W/foreign"
ls -ld "$W/foreign"
date -u +%FT%TZ