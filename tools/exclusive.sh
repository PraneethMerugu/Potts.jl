#!/bin/sh
# Run a command while holding the machine-wide lock (AUTONOMY §7.4, D-090): GPU suites and
# the performance gate must not overlap each other, or anything else timed, across worktrees.
#     tools/exclusive.sh env POTTS_GPU=metal julia --project=test test/potts.jl
#     tools/exclusive.sh julia --project=benchmark benchmark/gate.jl metal
# Prints nothing on stdout of its own and exits with the command's status.
#
# Design: a FIFO ticket queue in front of a directory lock.
#  - The queue orders waiters. A ticket is a numbered directory in $QUEUE, taken by atomic
#    mkdir at one more than the highest ticket present. Waiters are served lowest ticket
#    first, polling about once a second, so a run queued before an A/B runs before the
#    A/B's next round (each round takes a fresh ticket at the back).
#  - The lock is the directory $LOCK (atomic mkdir), as in the earlier script that other
#    checkouts may still run: the head of the queue must still take it, so this script and
#    the earlier one are mutually exclusive.
#  - Stale rule: a ticket or lock older than 3 hours belongs to a dead process and no longer
#    blocks. Live waiters refresh their ticket at every poll; a live holder refreshes its
#    ticket and the lock every minute, so a long run is never taken for dead.
#  - The ticket and lock are removed on exit, including after INT or TERM (the command
#    still finishes first: the lock is held for as long as it runs).
# All state lives under paths starting with /tmp/potts-exclusive (the frozen test relies
# on that prefix, D-090).
LOCK=/tmp/potts-exclusive.lock
QUEUE=/tmp/potts-exclusive.q
STALE_MIN=180
POLL=1
REFRESH=60

ticket=
keeper=
locked=

cleanup() {
    [ -n "$keeper" ] && kill "$keeper" 2>/dev/null
    [ -n "$locked" ] && rmdir "$LOCK" 2>/dev/null
    [ -n "$ticket" ] && rmdir "$QUEUE/$ticket" 2>/dev/null
    keeper= locked= ticket=
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# remove a path (an empty directory) if its mtime is older than the stale rule
drop_stale() {
    find "$1" -maxdepth 0 -mmin +$STALE_MIN -exec rmdir {} \; 2>/dev/null
}

take_ticket() {
    while :; do
        mkdir -p "$QUEUE" 2>/dev/null
        max=$(ls "$QUEUE" 2>/dev/null | sort -n | tail -n 1)
        n=$((${max:-0} + 1))
        if mkdir "$QUEUE/$n" 2>/dev/null; then
            ticket=$n
            return
        fi
    done
}

take_ticket
said=
while :; do
    # tickets of dead processes stop blocking after 3 h; ours is fresh
    for t in $(ls "$QUEUE" 2>/dev/null); do
        [ "$t" = "$ticket" ] || drop_stale "$QUEUE/$t"
    done
    if [ ! -d "$QUEUE/$ticket" ]; then
        # our ticket vanished (e.g. removed as stale after a long machine sleep): requeue
        ticket=
        take_ticket
    fi
    touch "$QUEUE/$ticket"
    head=$(ls "$QUEUE" 2>/dev/null | sort -n | head -n 1)
    if [ "$head" = "$ticket" ]; then
        drop_stale "$LOCK"
        if mkdir "$LOCK" 2>/dev/null; then
            locked=1
            break
        fi
        [ "$said" = lock ] || echo "exclusive.sh: next in line; waiting for $LOCK" >&2
        said=lock
    else
        [ -n "$said" ] || echo "exclusive.sh: queued as ticket $ticket behind ticket $head" >&2
        said=queue
    fi
    sleep $POLL
done

# Refresh the ticket and the lock while this shell lives. The keeper checks the shell
# first, so the state of a SIGKILLed holder ages and becomes stale. Its output goes to
# /dev/null so that a caller reading our stdout to EOF is not held open by it.
parent=$$
(
    while sleep $REFRESH; do
        kill -0 "$parent" 2>/dev/null || exit 0
        touch -c "$QUEUE/$ticket" "$LOCK"
    done
) </dev/null >/dev/null 2>&1 &
keeper=$!

"$@"
status=$?
cleanup
trap - EXIT
exit $status
