#!/bin/zsh
export OPENCLAW_HOME=$HOME/t191855
set -x
date -u +%FT%TZ
sw_vers; uname -m; node --version; npm --version; npm prefix -g; openclaw --version; id
grep -rl "denied path is unknown or outside the install root" "$(npm root -g)/openclaw/dist" | head -3
echo "grep194160 rc=$pipestatus[1]"