#!/usr/bin/env bash
# job.sh [AB|A|B] : the long job ON the lab Linux host (<user>). Runs the kit in bench b182520, then copies the bench's
# output folder out as a tarball. Writes run.exit LAST, so the watcher fires only after the evidence is out.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
J=$HOME/worker/jobs/T182520
date -u +%FT%TZ > "$J/run.started"
bench exec b182520 -- bash /root/kit/run.sh "${1:-AB}" > "$J/run.log" 2>&1
rc=$?
bench exec b182520 -- tar -czf - -C /root/t182520 out > "$J/out.tgz" 2> "$J/out-tar.err"
date -u +%FT%TZ > "$J/run.ended"
echo "$rc" > "$J/run.exit"
