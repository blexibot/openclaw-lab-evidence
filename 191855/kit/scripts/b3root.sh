#!/bin/bash
set -x
date -u +%FT%TZ
rmdir /home/lab/t191855/.openclaw/workspace/state/foreign
echo "rmdir rc=$?"
ls -ld /home/lab/t191855/.openclaw/workspace/state/foreign; echo "ls rc=$?"
date -u +%FT%TZ