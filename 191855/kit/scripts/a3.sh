#!/bin/zsh
export OPENCLAW_HOME=$HOME/t191855
set -x
date -u +%FT%TZ
STATE=/Users/admin/t191855/.openclaw
W=/Users/admin/t191855/.openclaw/workspace/state
mkdir -p $HOME/t191855-out
openclaw --version
# recreate V1 shape: same dmg, owners on
mkdir -p $W/labvol
hdiutil attach -owners on -mountpoint $W/labvol ~/labvol1.dmg
echo "attach rc=$?"
ls -leOd $W/labvol/.fseventsd
stat $W/labvol/.fseventsd/.openclaw-private-update-capture; echo "stat rc=$?"
openclaw backup create --dry-run --json; echo "dryrun rc=$?"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"
hdiutil detach $W/labvol; echo "detach rc=$?"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "control-backup rc=$?"
date -u +%FT%TZ