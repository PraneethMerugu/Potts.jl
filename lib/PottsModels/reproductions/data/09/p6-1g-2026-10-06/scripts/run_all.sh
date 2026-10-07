#!/bin/bash
# P6.1g launcher (remote PC): every line of jobs.txt is one single-threaded replicate process;
# at most 24 run at once, pinned to logical CPUs 0-11,16-27 (CI runner and benchmarks keep the rest).
# (The live run was launched unpinned at 17:31 and its launcher and replicates were pinned with
# `taskset -a -p` at 18:14 EDT, per the coordinator's core policy; children inherit the mask.)
cd ~/potts-full
date -Is > ~/p61g-run/started
taskset -c 0-11,16-27 xargs -P 24 -L 1 bash -c 'test -f ~/p61g-run/out/$0.tsv || nice -n 5 ~/.juliaup/bin/julia -t 1 --project=docs ~/p61g-run/replicate.jl ~/p61g-run/out/$0.tsv "$@" > ~/p61g-run/out/$0.log 2>&1' < ~/p61g-run/jobs.txt
date -Is > ~/p61g-run/finished
