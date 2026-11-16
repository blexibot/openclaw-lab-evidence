#!/bin/zsh
export OPENCLAW_HOME=$HOME/t191855
set -x
date -u +%FT%TZ
STATE=/Users/admin/t191855/.openclaw
W=/Users/admin/t191855/.openclaw/workspace/state
openclaw --version
mkdir -p $W/labvol
hdiutil attach -owners on -mountpoint $W/labvol ~/labvol1.dmg
echo "attach rc=$?"
touch ~/u1-marker
openclaw update --tag 2026.11.4 --yes --no-restart --json
echo "update rc=$?"
openclaw --version
find $STATE $HOME/.openclaw -newer ~/u1-marker -type f 2>/dev/null | head -20
npm config list
ls -leOd "$(npm prefix -g)/lib/node_modules"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"
hdiutil detach $W/labvol; echo "detach rc=$?"
date -u +%FT%TZ