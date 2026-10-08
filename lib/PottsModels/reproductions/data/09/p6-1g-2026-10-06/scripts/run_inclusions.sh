#!/bin/bash
# P6.1g post-hoc light-inclusion re-run of the 30 dist replicates; starts after run_all.sh, ≤ 24 at once.
until test -f ~/p61g-run/finished; do sleep 30; done
cd ~/potts-full
date -Is > ~/p61g-run/incl_started
taskset -c 0-11,16-27 xargs -P 24 -L 1 bash -c 'test -f ~/p61g-run/out/$0.tsv || nice -n 5 ~/.juliaup/bin/julia -t 1 --project=docs ~/p61g-run/replicate_inclusions.jl ~/p61g-run/out/$0.tsv "$@" > ~/p61g-run/out/$0.log 2>&1' < ~/p61g-run/jobs_inclusions.txt
date -Is > ~/p61g-run/incl_finished
