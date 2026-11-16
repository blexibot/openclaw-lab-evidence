#!/bin/bash
set -x
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
date -u +%FT%TZ
mkdir -p /home/lab/pr && cd /home/lab/pr
git init -q && git remote add origin https://github.com/openclaw/openclaw.git
git fetch -q --depth 1 origin pull/194166/head && git checkout -q FETCH_HEAD
git rev-parse HEAD
pnpm install --frozen-lockfile && pnpm build
echo "build rc=$?"
date -u +%FT%TZ