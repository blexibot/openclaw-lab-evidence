#!/bin/bash
/usr/local/bin/bench exec r198373 -- sh -c 'npm install -g openclaw@2026.11.4 --no-fund --no-audit && openclaw --version' > ~/jobs/J198373b.log 2>&1
echo $? > ~/jobs/J198373b.exit
