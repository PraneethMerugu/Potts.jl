# Transition safety of `tools/exclusive.sh` (P6.0s, D-090): while other checkouts still run
# the earlier script (a bare `mkdir` lock on /tmp/potts-exclusive.lock, stale after 3 h),
# a holder of the earlier script and a holder of the queued script never overlap.
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
        for p in procs                   # only processes this test started, by PID
            process_running(p) && kill(p, Base.SIGKILL)
        end
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
