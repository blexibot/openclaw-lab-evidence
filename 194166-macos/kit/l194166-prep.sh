#!/bin/bash
# l194166-prep.sh (Linux build container, AS ROOT): git + corepack for the source builds; records the PR head as seen
# now (read-only ls-remote). No openclaw command runs here.
set -x
date -u +%FT%TZ
export DEBIAN_FRONTEND=noninteractive COREPACK_ENABLE_DOWNLOAD_PROMPT=0
command -v git || (apt-get -qq update && apt-get -qq install -y git ca-certificates)
echo "git rc=$?"
corepack enable
echo "corepack rc=$?"
git --version; node --version; npm --version; uname -m
df -h / /home
git ls-remote https://github.com/openclaw/openclaw.git refs/pull/194166/head refs/heads/main | sed 's/^/LSREMOTE /'
echo "PREP_DONE"
date -u +%FT%TZ
