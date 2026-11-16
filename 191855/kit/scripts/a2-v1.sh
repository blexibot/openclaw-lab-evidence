#!/bin/zsh
export OPENCLAW_HOME=$HOME/t191855
set -x
date -u +%FT%TZ
STATE=/Users/admin/t191855/.openclaw
W=/Users/admin/t191855/.openclaw/workspace/state
mkdir -p $HOME/t191855-out
# --- V1 APFS, owners on ---
rm -f ~/labvol1.dmg
hdiutil create -size 64m -fs APFS -volname labvol1 ~/labvol1.dmg
echo "create rc=$?"
mkdir -p $W/labvol
hdiutil attach -owners on -mountpoint $W/labvol ~/labvol1.dmg
echo "attach rc=$?"
echo x > $W/labvol/x.txt
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do [ -e $W/labvol/.fseventsd ] && break; sleep 2; done
mount | grep labvol
diskutil info $W/labvol | grep -iE 'owners|file system|mount point'
ls -leOd $W/labvol $W/labvol/.fseventsd
stat $W/labvol/.fseventsd/.openclaw-private-update-capture; echo "stat rc=$?"
openclaw backup create --dry-run --json; echo "dryrun rc=$?"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"
hdiutil detach $W/labvol; echo "detach rc=$?"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "control-backup rc=$?"
date -u +%FT%TZ