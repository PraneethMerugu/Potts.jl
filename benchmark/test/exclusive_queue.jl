# Robustness of the queue in `tools/exclusive.sh` (P6.0s, D-090): a SIGKILLed waiter's
# ticket, stray entries and a vanished ticket do not block the queue, and the lock is stale
# after 3 h untouched.
#
#     julia benchmark/test/exclusive_queue.jl
#
# Like the frozen P6.0s test, it runs the script in a sandbox whose lock prefix points into a
# private temp directory, so it never takes or waits on the real machine lock.
using Test

const REPO = normpath(joinpath(@__DIR__, "..", ".."))
const PREFIX = "/tmp/potts-exclusive"

function sandbox()
    root = mktempdir(; cleanup = true)
    lockroot = joinpath(root, "lockroot")
    mkpath(lockroot)
    excl = joinpath(root, "exclusive.sh")
    write(excl, replace(read(joinpath(REPO, "tools", "exclusive.sh"), String),
        PREFIX => joinpath(lockroot, "potts-exclusive")))
    chmod(excl, 0o755)
    return (; root, lockroot, excl, log = joinpath(root, "events.log"))
end

stamp_sh(log, tag, what) =
    "perl -MTime::HiRes=time -e 'printf qq(%s %s %.6f\\n), \$ARGV[0], \$ARGV[1], time' $tag $what >> $log"

"""`exclusive.sh` running a shell job that stamps around `sleep d`."""
holder(sb, tag, d) =
    Cmd([sb.excl, "sh", "-c", "$(stamp_sh(sb.log, tag, "start")); sleep $d; $(stamp_sh(sb.log, tag, "end"))"])

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

lockfree(sb) = !ispath(joinpath(sb.lockroot, "potts-exclusive.lock")) &&
    isempty(readdir(joinpath(sb.lockroot, "potts-exclusive.q")))

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
            push!(procs, spawn(holder(sb, "H", 4)))
            @test wait_until(() -> started(sb, "H"), 30)
            w = spawn(holder(sb, "W", 1))
            push!(procs, w)
            @test wait_until(() -> isdir(joinpath(queue(sb), "2")), 10)    # W waits on ticket 2
            kill(w, Base.SIGKILL)                                          # no trap runs
            @test wait_until(() -> !process_running(procs[1]), 30)        # H done
            @test isdir(joinpath(queue(sb), "2"))                          # W's ticket is left
            n = spawn(holder(sb, "N", 0))
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
        p = spawn(Cmd([sb.excl, "true"]))
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
            push!(procs, spawn(holder(sb, "H", 4)))
            @test wait_until(() -> started(sb, "H"), 30)
            push!(procs, spawn(holder(sb, "W", 1)))
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
    @testset "a lock untouched for 3 h is stale" begin
        sb = sandbox()
        mkdir(lockdir(sb))
        age!(lockdir(sb), 60)                     # untouched for 1 h: not yet stale
        p = spawn(Cmd([sb.excl, "true"]))
        @test !finished_within(p, 3)               # still held
        age!(lockdir(sb), 4 * 60)                 # past 3 h: the holder is dead
        @test finished_within(p, 5) && success(p)
        @test lockfree(sb)
        reap!([p])
    end
end
