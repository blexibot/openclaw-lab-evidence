#!/bin/zsh
export OPENCLAW_HOME=$HOME/t191855
set -x
date -u +%FT%TZ
STATE=/Users/admin/t191855/.openclaw
W=/Users/admin/t191855/.openclaw/workspace/state
openclaw --version
# U2 control: no volume attached
touch ~/u2-marker
openclaw update --tag 2026.11.4 --yes --no-restart --json
echo "update rc=$?"
openclaw --version
find $STATE $HOME/.openclaw -newer ~/u2-marker -type f 2>/dev/null | head -20
npm config list
ls -leOd "$(npm prefix -g)/lib/node_modules"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"
date -u +%FT%TZ
