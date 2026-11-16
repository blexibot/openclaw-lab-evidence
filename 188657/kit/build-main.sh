#!/usr/bin/env bash
# build-main.sh [ref]: build OpenClaw from source inside the bench, for the #188657 fix check.
# Default ref: bf0b8002c2b9741ecadeda9b4219e1cb633b508a (PR #198100, merged to main 2026-11-13).
# Result: /root/src/openclaw/openclaw.mjs runnable with `node`. Prints timings and the final version line.
set -euxo pipefail
REF="${1:-bf0b8002c2b9741ecadeda9b4219e1cb633b508a}"
date -u +%FT%TZ
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update && apt-get -qq install -y git build-essential python3 ca-certificates > /dev/null
node --version; free -g; nproc
if [ ! -d /root/src/openclaw/.git ]; then
  mkdir -p /root/src && git clone --filter=blob:none https://github.com/openclaw/openclaw.git /root/src/openclaw
fi
cd /root/src/openclaw
git fetch --quiet origin "$REF" || true
git checkout --quiet --detach "$REF"
git log -1 --format='HEAD %H %cI %s'
grep -n 'appendOnlyRuntimeContext' src/agents/transcript-policy.ts | head -5
corepack enable 2>/dev/null && pnpm --version || { npm install -g pnpm@12.15.0 --no-fund --no-audit && pnpm --version; }
date -u +%FT%TZ; pnpm install --frozen-lockfile
date -u +%FT%TZ; NODE_OPTIONS=--max-old-space-size=8192 pnpm build
date -u +%FT%TZ; node openclaw.mjs --version
