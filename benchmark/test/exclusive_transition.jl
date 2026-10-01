# Transition safety of `tools/exclusive.sh` (P6.0s, D-090): while other checkouts still run
# the earlier script (a bare `mkdir` lock on /tmp/potts-exclusive.lock, stale after 3 h),
# a holder of the earlier script and a holder of the queued script never overlap. Also the
# queue's robustness: a SIGKILLed waiter's ticket, stray entries and a vanished ticket do
# not block the queue, while the lock keeps the earlier 3-hour stale rule.
#
#     julia benchmark/test/exclusive_transition.jl
#
# Like the frozen P6.0s test, it runs both scripts in a sandbox whose lock prefix points into
# a private temp directory, so it never takes or waits on the real machine lock. The earlier
# script is embedded verbatim except for that prefix and its poll interval (20 s -> 1 s).
using Test

const REPO = normpath(joinpath(@__DIR__, "..", ".."))
const PREFIX = "/tmp/potts-exclusive"

# tools/exclusive.sh as of ec544d8 (before D-090)
const OLD_SCRIPT = raw"""
#!/bin/sh
LOCK=/tmp/potts-exclusive.lock
while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +180 2>/dev/null)" ]; then
        echo "exclusive.sh: removing stale lock $LOCK" >&2; rmdir "$LOCK"; continue
    fi
    sleep 20
done
trap 'rmdir "$LOCK"' EXIT INT TERM
"$@"
"""

function sandbox()
    root = mktempdir(; cleanup = true)
    lockroot = joinpath(root, "lockroot")
    mkpath(lockroot)
    to_sandbox(txt) = replace(txt, PREFIX => joinpath(lockroot, "potts-exclusive"))
    new = joinpath(root, "new.sh")
    old = joinpath(root, "old.sh")
    write(new, to_sandbox(read(joinpath(REPO, "tools", "exclusive.sh"), String)))
    write(old, replace(to_sandbox(lstrip(OLD_SCRIPT)), "sleep 20" => "sleep 1"))
    chmod(new, 0o755)
    chmod(old, 0o755)
    return (; root, lockroot, new, old, log = joinpath(root, "events.log"))
end

stamp_sh(log, tag, what) =
    "perl -MTime::HiRes=time -e 'printf qq(%s %s %.6f\\n), \$ARGV[0], \$ARGV[1], time' $tag $what >> $log"

"""`script` (or nothing: no lock at all) running a shell job that stamps around `sleep d`."""
function holder(sb, script, tag, d)
    job = ["sh", "-c", "$(stamp_sh(sb.log, tag, "start")); sleep $d; $(stamp_sh(sb.log, tag, "end"))"]
    return Cmd(script === nothing ? job : [script; job])
end

spawn(cmd) = run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)

function events(log)
    isfile(log) || return Tuple{String, String, Float64}[]
    return [(String(a), String(b), parse(Float64, c)) for (a, b, c) in split.(filter(!isempty, readlines(log)))]
end
started(sb, tag) = any(e -> e[1] == tag && e[2] == "start", events(sb.log))

function wait_until(f, timeout)
    t0 = time()
    while !f()
        time() - t0 > timeout && return false
        sleep(0.05)
    end
    return true
end

"""Intervals `(tag, start, end)` sorted by start; each tag runs once."""
function intervals(ev)
    s = Dict(e[1] => e[3] for e in ev if e[2] == "start")
    e = Dict(e[1] => e[3] for e in ev if e[2] == "end")
    return sort([(t, s[t], e[t]) for t in keys(s) if haskey(e, t)]; by = x -> x[2])
end
disjoint(iv) = all(iv[k][3] <= iv[k + 1][2] for k in 1:(length(iv) - 1))

"""Kill only processes this test started (by PID), if they are still running."""
reap!(procs) = foreach(p -> process_running(p) && kill(p, Base.SIGKILL), procs)

"""Run `jobs` (pairs `tag => cmd`, each started once the previous one holds or is queued)."""
function scenario(sb, jobs; stagger = 0.5)
    procs = Base.Process[]
    try
        for (k, (tag, cmd)) in enumerate(jobs)
            push!(procs, spawn(cmd))
            # the first job must hold the lock before the second one starts waiting
            k == 1 && (wait_until(() -> started(sb, tag), 30) || error("$tag never started"))
            sleep(stagger)
        end
        ok = wait_until(() -> !any(process_running, procs), 120)
        return (; ok, allok = ok && all(success, procs), iv = intervals(events(sb.log)))
    finally
        reap!(procs)
    end
end

lockfree(sb) = !ispath(joinpath(sb.lockroot, "potts-exclusive.lock")) &&
    isempty(readdir(joinpath(sb.lockroot, "potts-exclusive.q")))

@testset "exclusive.sh: old and new holders never overlap" begin
    @testset "old holder first, new waiter" begin
        sb = sandbox()
        r = scenario(sb, ["O" => holder(sb, sb.old, "O", 3), "N" => holder(sb, sb.new, "N", 1)])
        @test r.allok
        @test [x[1] for x in r.iv] == ["O", "N"]
        @test disjoint(r.iv)
        @test lockfree(sb)
    end
    @testset "new holder first, old waiter" begin
        sb = sandbox()
        r = scenario(sb, ["N" => holder(sb, sb.new, "N", 3), "O" => holder(sb, sb.old, "O", 1)])
        @test r.allok
        @test [x[1] for x in r.iv] == ["N", "O"]
        @test disjoint(r.iv)
        @test lockfree(sb)
    end
    @testset "a mixed burst" begin
        sb = sandbox()
        jobs = [t => holder(sb, startswith(t, "O") ? sb.old : sb.new, t, 1)
                for t in ("N1", "O1", "N2", "O2", "N3", "O3")]
        r = scenario(sb, jobs; stagger = 0.1)
        @test r.allok
        @test length(r.iv) == 6
        @test disjoint(r.iv)
        @test lockfree(sb)
    end
    @testset "negative control: unlocked jobs do overlap" begin
        sb = sandbox()
        r = scenario(sb, ["A" => holder(sb, nothing, "A", 3), "B" => holder(sb, nothing, "B", 1)])
        @test r.allok
        @test length(r.iv) == 2
        @test !disjoint(r.iv)
    end
end

# ---------------------------------------------------------------------------- queue robustness
queue(sb) = joinpath(sb.lockroot, "potts-exclusive.q")
lockdir(sb) = joinpath(sb.lockroot, "potts-exclusive.lock")
age!(p, minutes) = run(`touch -h -t $(Libc.strftime("%Y%m%d%H%M.%S", time() - 60 * minutes)) $p`)
finished_within(p, t) = wait_until(() -> !process_running(p), t)

@testset "exclusive.sh: queue robustness" begin
    @testset "a SIGKILLed waiter's ticket stops blocking after 5 min" begin
        sb = sandbox()
        procs = Base.Process[]
        try
            push!(procs, spawn(holder(sb, sb.new, "H", 4)))
            @test wait_until(() -> started(sb, "H"), 30)
            w = spawn(holder(sb, sb.new, "W", 1))
            push!(procs, w)
            @test wait_until(() -> isdir(joinpath(queue(sb), "2")), 10)    # W waits on ticket 2
            kill(w, Base.SIGKILL)                                          # no trap runs
            @test wait_until(() -> !process_running(procs[1]), 30)        # H done
            @test isdir(joinpath(queue(sb), "2"))                          # W's ticket is left
            n = spawn(holder(sb, sb.new, "N", 0))
            push!(procs, n)
            # negative control: a fresh dead ticket still blocks (the queue is honored)
            @test !wait_until(() -> started(sb, "N"), 3)
            age!(joinpath(queue(sb), "2"), 6)                              # past the 5 min rule
            @test wait_until(() -> started(sb, "N"), 5)
            @test finished_within(n, 10) && success(n)
            @test !started(sb, "W")
            @test lockfree(sb)
        finally
            reap!(procs)
        end
    end
    @testset "stray entries in the queue" begin
        sb = sandbox()
        mkpath(queue(sb))
        # a regular file with a ticket's name (what a bare `touch` could create): removed
        # once stale, like a dead ticket
        touch(joinpath(queue(sb), "1"))
        age!(joinpath(queue(sb), "1"), 6)
        # a name that is not a ticket is ignored, however fresh
        touch(joinpath(queue(sb), "junk"))
        p = spawn(Cmd([sb.new, "true"]))
        @test finished_within(p, 5) && success(p)
        @test !ispath(joinpath(queue(sb), "1"))
        @test readdir(queue(sb)) == ["junk"]
        @test !ispath(lockdir(sb))
        reap!([p])
    end
    @testset "a waiter whose ticket vanishes requeues without leaving a file" begin
        sb = sandbox()
        procs = Base.Process[]
        try
            push!(procs, spawn(holder(sb, sb.new, "H", 4)))
            @test wait_until(() -> started(sb, "H"), 30)
            push!(procs, spawn(holder(sb, sb.new, "W", 1)))
            t2 = joinpath(queue(sb), "2")
            @test wait_until(() -> isdir(t2), 10)
            rm(t2)                                                         # pruned under W
            files = false
            ok = wait_until(30) do
                files |= any(f -> !isdir(joinpath(queue(sb), f)), readdir(queue(sb)))
                !any(process_running, procs)
            end
            @test ok && all(success, procs)
            @test !files                                                   # never a regular file
            @test started(sb, "W")
            @test disjoint(intervals(events(sb.log)))
            @test lockfree(sb)
        finally
            reap!(procs)
        end
    end
    @testset "the lock keeps the 3 h stale rule (earlier holders never refresh it)" begin
        sb = sandbox()
        mkdir(lockdir(sb))
        age!(lockdir(sb), 60)                     # an earlier-script holder 1 h into its run
        p = spawn(Cmd([sb.new, "true"]))
        @test !finished_within(p, 3)               # still held
        age!(lockdir(sb), 4 * 60)                 # past 3 h: the holder is dead
        @test finished_within(p, 5) && success(p)
        @test lockfree(sb)
        reap!([p])
    end
end
