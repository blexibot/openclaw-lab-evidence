#!/bin/zsh
export OPENCLAW_HOME=$HOME/t191855
set -x
date -u +%FT%TZ
mkdir -p $OPENCLAW_HOME $HOME/t191855-out
openclaw backup create --help; echo "help-backup rc=$?"
openclaw setup --help; echo "help-setup rc=$?"
openclaw update --help; echo "help-update rc=$?"
openclaw setup --baseline; echo "setup rc=$?"
openclaw backup create --dry-run --json; echo "dryrun rc=$?"
openclaw backup create --verify --json --output $HOME/t191855-out; echo "backup rc=$?"
ls -la $OPENCLAW_HOME $OPENCLAW_HOME/.openclaw
date -u +%FT%TZ