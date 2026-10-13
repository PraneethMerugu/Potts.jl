#!/bin/bash
# CI's test suites in parallel on the self-hosted PC (P6.ci; D-157 runner, 16 cores / 32
# threads). Cores 12-15 and their SMT siblings 28-31 stay free for benchmarks. The other
# twelve physical cores (0-11, siblings 16-27) are split into disjoint pairs, one pair and
# its two siblings per process, so no process shares a core with another: the in-process
# timing comparisons see the same uncontended cores they saw when the steps ran one by one.
#
#   pair  logical CPUs   process
#   0-1   0-1,16-17      PottsModels shard 1/3  (julia -t 4)
#   2-3   2-3,18-19      PottsModels shard 2/3  (julia -t 4)
#   4-5   4-5,20-21      PottsModels shard 3/3  (julia -t 4)
#   6-7   6-7,22-23      GPU group (ROCm, device-only, test/shared/device_only.jl)
#   8-9   8-9,24-25      Potts
#   10-11 10-11,26-27    CorePotts, then MakiePotts
#
# Every process writes its own log. The script waits for all of them, prints each log in a
# collapsible group with its wall time and exit code, and exits non-zero if any failed. The
# workspace is precompiled once beforehand (the CI step before this one), so the processes
# only read the shared depot's compile cache.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
LOGS=${POTTS_CI_LOGS:-${RUNNER_TEMP:-/tmp}/potts-ci-logs}
rm -rf "$LOGS"; mkdir -p "$LOGS"
JULIA=${JULIA:-julia}
BULK=${OPENVT_PACKAGE_BULK:-}
names=()

launch() { # name cpus command...
    local name=$1 cpus=$2; shift 2
    names+=("$name")
    (
        start=$(date +%s)
        taskset -c "$cpus" "$@" > "$LOGS/$name.log" 2>&1
        code=$?
        echo "$code $(( $(date +%s) - start ))" > "$LOGS/$name.exit"
    ) &
}

for k in 1 2 3; do
    cpus=$(( 2 * (k - 1) ))-$(( 2 * k - 1 )),$(( 2 * (k - 1) + 16 ))-$(( 2 * k + 15 ))
    launch "PottsModels-$k-of-3" "$cpus" env OPENVT_PACKAGE_BULK="$BULK" POTTSMODELS_SHARD="$k/3" GROUP=PottsModels \
        "$JULIA" -t 4 --project=test test/runtests.jl
done
launch GPU 6-7,22-23 env GROUP=GPU POTTS_GPU=rocm "$JULIA" --project=test test/runtests.jl
launch Potts 8-9,24-25 env GROUP=Potts "$JULIA" --project=test test/runtests.jl
launch CorePotts+MakiePotts 10-11,26-27 bash -c \
    "GROUP=CorePotts '$JULIA' --project=test test/runtests.jl && GROUP=MakiePotts '$JULIA' --project=test test/runtests.jl"
wait

failed=0
for name in "${names[@]}"; do
    read -r code secs < "$LOGS/$name.exit" || { code=99; secs=0; }
    echo "::group::$name — exit $code, $(( secs / 60 )) min $(( secs % 60 )) s"
    cat "$LOGS/$name.log"
    echo "::endgroup::"
    [ "$code" = 0 ] || { failed=1; echo "::error::$name failed (exit $code); its log is in the group above"; }
done
echo "summary:"
for name in "${names[@]}"; do
    read -r code secs < "$LOGS/$name.exit" || { code=99; secs=0; }
    printf '  %-22s exit %-3s %3d min %02d s\n' "$name" "$code" $(( secs / 60 )) $(( secs % 60 ))
done
exit $failed
