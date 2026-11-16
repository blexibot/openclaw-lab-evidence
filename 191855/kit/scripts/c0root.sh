#!/bin/bash
set -x
date -u +%FT%TZ
export DEBIAN_FRONTEND=noninteractive COREPACK_ENABLE_DOWNLOAD_PROMPT=0
command -v git || (apt-get -qq update && apt-get -qq install -y git)
corepack enable
echo "corepack rc=$?"
git --version
node --version
npm --version
date -u +%FT%TZ