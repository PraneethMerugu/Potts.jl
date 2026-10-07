#!/bin/bash
# P6.1h launcher (remote PC): every line of jobs.txt is one single-threaded replicate process.
# At most 7 run at once (the agent's cap is ~8 threads on the shared PC; one is kept for probes),
# under a 16 GB memory scope, pinned to logical CPUs 0-11,16-27 (cores 12-15/28-31 stay free).
#     WT=<worktree> OUT=<outdir> run_all.sh
set -u
export WT OUT
cd "$WT"
mkdir -p "$OUT"
date -Is > "$OUT/started"
systemd-run --user --scope -q -p MemoryMax=16G taskset -c 0-11,16-27 \
  xargs -P 7 -L 1 bash -c 'test -f "$OUT/$0.tsv" || nice -n 5 ~/.juliaup/bin/julia -t 1 --project=docs "$WT/lib/PottsModels/reproductions/data/09/vpre7-2026-10-07/scripts/replicate.jl" "$OUT/$0.tsv" "$@" > "$OUT/$0.log" 2>&1' \
  < "$WT/lib/PottsModels/reproductions/data/09/vpre7-2026-10-07/scripts/jobs.txt"
date -Is > "$OUT/finished"
