#!/bin/bash
# P6.1g launcher (remote PC): every line of jobs.txt is one single-threaded replicate process;
# at most 24 run at once (the CI runner keeps 8 of the 32 hardware threads).
cd ~/potts-full
date -Is > ~/p61g-run/started
xargs -P 24 -L 1 bash -c 'test -f ~/p61g-run/out/$0.tsv || nice -n 5 ~/.juliaup/bin/julia -t 1 --project=docs ~/p61g-run/replicate.jl ~/p61g-run/out/$0.tsv "$@" > ~/p61g-run/out/$0.log 2>&1' < ~/p61g-run/jobs.txt
date -Is > ~/p61g-run/finished
