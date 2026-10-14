#!/bin/bash
# Lane S (D-248): one branch's suites on the CI cores, preempted by CI.
#
#   item.sh <item> <commit> [--docs] [--extra '<shell command>']...
#
# Runs in pueue group `suites` (parallelism 1). The checkout is ~/potts-ci/<item>, a detached
# worktree of ~/potts-full (the coordinator fetches the bundle there first). It is created
# when missing; an existing one must already be at <commit> and clean.
#
# Steps: instantiate + precompile (as CI does), the frozen check, the unchanged
# .github/ci/parallel.sh (six pinned processes on 0-11/16-27), then the optional docs build
# and extra commands (run from the checkout, pinned to 0-11/16-27). Every Julia process runs
# under tools/pc/julia-scoped.sh (systemd scope, MemoryMax=24G, CPUWeight=10).
#
# Yielding to CI: before each step, the script waits while a GitHub Actions job runs (a
# `Runner.Worker` process, the test in benchmark/machine.jl). While a step runs, it polls every
# 15 s; when a job starts, it kills the step's process group, waits for the job to end and runs
# the step again. The pueue task itself never fails because of CI, so an A/B queued with
# `--after` on it is not cancelled.
#
# Files (the coordinator's conventions): ~/potts-ci/<item>-run.pid (this script),
# <item>-step.pid (the running step's process group), <item>-status (one "step code" line each,
# then SUITES-DONE / DONE), <item>-<step>.log, and <item>-ci-logs/ (parallel.sh's logs).
set -u
ITEM=$1 COMMIT=$2; shift 2
DOCS=0 EXTRA=()
while [ $# -gt 0 ]; do
    case $1 in
        --docs) DOCS=1 ;;
        --extra) EXTRA+=("$2"); shift ;;
        *) echo "unknown argument $1" >&2; exit 64 ;;
    esac
    shift
done
HERE=$(cd "$(dirname "$0")" && pwd)
CI=$HOME/potts-ci D=$HOME/potts-ci/$ITEM
S=$CI/$ITEM-status
PIN="taskset -c 0-11,16-27"
export PATH=$HOME/.juliaup/bin:$PATH
export OPENVT_PACKAGE_BULK=$CI/openvt-bulk
export JULIA=$HERE/julia-scoped.sh POTTS_CPUWEIGHT=${POTTS_CPUWEIGHT:-10}
echo $$ > "$CI/$ITEM-run.pid"
: > "$S"

# exact process-name match (never -f, which would match this shell); POTTS_CI_PROC is for tests
ci_running() { pgrep -x "${POTTS_CI_PROC:-Runner.Worker}" > /dev/null; }
wait_ci() {
    ci_running || return 0
    echo "waiting for CI $(date +%H:%M)" >> "$S"
    while ci_running; do sleep 15; done
}

# step <name> <command...>: run under setsid (its own process group), killed and re-run if a
# CI job starts. Logs to <item>-<name>.log; appends "<name> <code>" to the status file.
step() {
    local name=$1; shift
    local code
    while true; do
        wait_ci
        (cd "$D" && exec setsid "$@") > "$CI/$ITEM-$name.log" 2>&1 &
        local pid=$!
        echo $pid > "$CI/$ITEM-step.pid"
        local preempted=0
        while kill -0 $pid 2>/dev/null; do
            if ci_running; then
                kill -TERM -- -$pid 2>/dev/null; sleep 10; kill -KILL -- -$pid 2>/dev/null
                preempted=1
                break
            fi
            sleep 15
        done
        wait $pid; code=$?
        rm -f "$CI/$ITEM-step.pid"
        [ $preempted = 1 ] && { echo "$name preempted by CI $(date +%H:%M)" >> "$S"; continue; }
        echo "$name $code" >> "$S"
        return $code
    done
}

if [ ! -d "$D" ]; then
    git -C "$HOME/potts-full" worktree add -q --detach "$D" "$COMMIT" || { echo "worktree 1" >> "$S"; exit 1; }
fi
head=$(git -C "$D" rev-parse HEAD) want=$(git -C "$D" rev-parse "$COMMIT^{commit}" 2>/dev/null)
if [ "$head" != "$want" ] || [ -n "$(git -C "$D" status --porcelain --untracked-files=no)" ]; then
    echo "checkout mismatch: $D is at ${head:0:9}, wanted $COMMIT (or has local changes)" >> "$S"
    exit 1
fi
[ -f "$D/.github/ci/parallel.sh" ] || { echo "no .github/ci/parallel.sh at $COMMIT" >> "$S"; exit 1; }
echo "checkout ${head:0:9}" >> "$S"

fail=0
# as CI's precompile step: the workspace, then each test project, so the parallel processes
# only read the depot's compile cache
step inst $PIN bash -c '"$JULIA" --project=. -e "using Pkg; Pkg.instantiate(); Pkg.precompile()" &&
    for p in test lib/CorePotts/test lib/MakiePotts/test lib/PottsModels/test benchmark docs; do
        "$JULIA" --project=$p -e "using Pkg; Pkg.precompile()" || exit 1
    done' || exit 1
step frozen $PIN "$JULIA" --project=lib/PottsModels/test -e 'using Test; include("lib/PottsModels/test/frozen.jl")' || fail=1
step suites env POTTS_CI_LOGS="$CI/$ITEM-ci-logs" bash .github/ci/parallel.sh || fail=1
echo SUITES-DONE >> "$S"
[ $DOCS = 1 ] && { step docs $PIN "$JULIA" -t 4 --project=docs docs/make.jl || fail=1; }
for i in "${!EXTRA[@]}"; do
    step "extra$((i + 1))" $PIN bash -c "${EXTRA[$i]}" || fail=1
done
echo DONE >> "$S"
exit $fail
