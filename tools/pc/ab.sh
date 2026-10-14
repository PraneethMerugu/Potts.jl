#!/bin/bash
# Lane A (D-248): one paired A/B (D-171, D-242) in pueue group `ab` (parallelism 1).
#
#   ab.sh <item> <base-dir> <cand-dir> <cases> <backend>
#
# Drains Lane S first: pauses group `suites` with --wait (the running suites task finishes;
# no new one starts) and waits until none is running. It never freezes a suites task: a frozen
# process keeps its KFD handle, which benchmark/machine.jl's wait_idle(gpu = true) counts as busy,
# and memory-bandwidth load on 0-11 moves the controls (D-242). Then benchmark/ab.jl runs as
# before, from the candidate checkout, with its own CI/GPU wait and machine lock. Lane S is
# released when no other A/B is queued, unless a hold file says otherwise.
#
# The coordinator still announces the quiet window (D-242); queueing an A/B starts the drain.
# Files: ~/potts-ci/<item>-ab-<backend>.pid, <item>-ab-<backend>.log, a line in <item>-status.
set -u
ITEM=$1 BASE=$2 CAND=$3 CASES=$4 BACKEND=$5
P=${PUEUE:-$HOME/.local/bin/pueue}
CI=$HOME/potts-ci S=$HOME/potts-ci/$ITEM-status
export PATH=$HOME/.juliaup/bin:$PATH
export OPENVT_PACKAGE_BULK=$CI/openvt-bulk
echo $$ > "$CI/$ITEM-ab-$BACKEND.pid"

count() { # count <group> <state>: tasks of that group in that state; exits if pueue fails
    local json n
    json=$("$P" status --json) || { echo "ab-$BACKEND pueue unreachable" >> "$S"; exit 4; }
    n=$(jq --arg g "$1" --arg s "$2" \
        '[.tasks[] | select(.group == $g) | select(.status | if type == "object" then has($s) else . == $s end)] | length' <<< "$json") \
        || { echo "ab-$BACKEND pueue status unreadable" >> "$S"; exit 4; }
    echo "$n"
}

"$P" pause --group suites --wait > /dev/null || { echo "ab-$BACKEND cannot pause suites" >> "$S"; exit 4; }
echo "ab-$BACKEND draining suites $(date +%H:%M)" >> "$S"
while n=$(count suites Running) && [ "$n" != 0 ]; do sleep 30; done
[ "$n" = 0 ] || exit 4
echo "ab-$BACKEND window start $(date +%H:%M)" >> "$S"

cd "$CAND" && julia benchmark/ab.jl "$BASE" "$CAND" "$CASES" "$BACKEND" > "$CI/$ITEM-ab-$BACKEND.log" 2>&1
code=$?
echo "ab-$BACKEND $code" >> "$S"
echo "ab-$BACKEND window end $(date +%H:%M)" >> "$S"

# Release Lane S unless another A/B waits (it would only drain again) or the coordinator holds it.
if [ "$(count ab Queued)" = 0 ] && [ ! -e "$CI/lane-s.hold" ]; then
    "$P" start --group suites > /dev/null
fi
exit $code
