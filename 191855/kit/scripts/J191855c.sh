#!/bin/bash
/usr/local/bin/bench exec t191855-lin -- su - lab -c "bash /home/lab/c-build.sh" > ~/jobs/J191855c.log 2>&1
echo $? > ~/jobs/J191855c.exit