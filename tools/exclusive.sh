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
#    A/B's next round (each round takes a fresh ticket at the back). Entries whose names
#    are not numbers are ignored.
#  - The lock is the directory $LOCK (atomic mkdir), as in the earlier script that other
#    checkouts may still run: the head of the queue must still take it, so this script and
#    the earlier one are mutually exclusive.
#  - Stale rules. Live waiters touch their ticket at every poll and a live holder touches
#    its ticket and the lock every minute, so a ticket untouched for 5 minutes belongs to a
#    dead process (e.g. a SIGKILLed waiter) and is removed. The lock keeps the earlier
#    script's 3-hour rule, because that script's holders never refresh it.
#  - The ticket and lock are removed on exit, including after INT, TERM, HUP, QUIT or PIPE
#    (the command still finishes first: the lock is held for as long as it runs).
# All state lives under paths starting with /tmp/potts-exclusive (the frozen test relies
# on that prefix, D-090).
LOCK=/tmp/potts-exclusive.lock
QUEUE=/tmp/potts-exclusive.q
LOCK_STALE_MIN=180
TICKET_STALE_MIN=5
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
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 141' PIPE
trap 'exit 143' TERM

# remove `path` (an empty directory, or any other non-directory) if it is older than
# `minutes`
drop_stale() {
    find "$1" -maxdepth 0 -mmin +"$2" \( -type d -exec rmdir {} \; -o ! -type d -exec rm -f {} \; \) 2>/dev/null
}

# the numbered entries of the queue, lowest first
tickets() {
    ls "$QUEUE" 2>/dev/null | grep -E '^[1-9][0-9]*$' | sort -n
}

take_ticket() {
    while :; do
        mkdir -p "$QUEUE" 2>/dev/null
        max=$(tickets | tail -n 1)
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
    # tickets of dead processes stop blocking after 5 minutes; ours is fresh
    for t in $(tickets); do
        [ "$t" = "$ticket" ] || drop_stale "$QUEUE/$t" $TICKET_STALE_MIN
    done
    # -c: never create a regular file in place of a ticket that has just been removed
    touch -c "$QUEUE/$ticket"
    if [ ! -d "$QUEUE/$ticket" ]; then
        # our ticket vanished (e.g. removed as stale after a long machine sleep): requeue
        ticket=
        take_ticket
    fi
    head=$(tickets | head -n 1)
    if [ "$head" = "$ticket" ]; then
        drop_stale "$LOCK" $LOCK_STALE_MIN
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

# Refresh the ticket and the lock while this shell lives. The keeper is its own `sh`, so
# its `$$` is its own PID: it stops as soon as its parent is no longer this shell (a
# SIGKILLed holder's keeper is reparented), which rules out a reused PID, and the state
# of a dead holder ages and becomes stale. Its output goes to /dev/null so that a caller
# reading our stdout to EOF is not held open by it.
sh -c '
    while sleep "$4"; do
        p=$(ps -o ppid= -p $$ | tr -d " ")
        [ -z "$p" ] || [ "$p" = "$1" ] || exit 0          # empty: ps failed, skip the check
        touch -c "$2" "$3"
    done
' keeper $$ "$QUEUE/$ticket" "$LOCK" $REFRESH </dev/null >/dev/null 2>&1 &
keeper=$!

"$@"
status=$?
cleanup
trap - EXIT
exit $status
