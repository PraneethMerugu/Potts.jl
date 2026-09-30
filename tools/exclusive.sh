#!/bin/sh
# Run a command while holding the machine-wide lock (AUTONOMY §7.4): GPU suites and the
# performance gate must not overlap each other, or anything else timed, across worktrees.
#     tools/exclusive.sh env POTTS_GPU=metal julia --project=test test/potts.jl
#     tools/exclusive.sh julia --project=benchmark benchmark/gate.jl metal
# The lock is a directory (atomic mkdir); a lock older than 3 hours is treated as stale.
LOCK=/tmp/potts-exclusive.lock
while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +180 2>/dev/null)" ]; then
        echo "exclusive.sh: removing stale lock $LOCK" >&2; rmdir "$LOCK"; continue
    fi
    sleep 20
done
trap 'rmdir "$LOCK"' EXIT INT TERM
"$@"
