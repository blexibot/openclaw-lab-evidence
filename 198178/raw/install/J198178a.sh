#!/bin/bash
{ /usr/local/bin/bench new ubuntu/24.04 r198178 && /usr/local/bin/bench openclaw r198178 2026.11.4; } > ~/jobs/J198178a.log 2>&1
echo $? > ~/jobs/J198178a.exit
