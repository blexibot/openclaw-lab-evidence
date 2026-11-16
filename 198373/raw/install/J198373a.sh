#!/bin/bash
{ /usr/local/bin/bench new ubuntu/24.04 r198373 && /usr/local/bin/bench openclaw r198373 2026.11.3; } > ~/jobs/J198373a.log 2>&1
echo $? > ~/jobs/J198373a.exit
