# Frozen acceptance test for P6.0s (fair machine lock) and P6.0v7 (Metal gate and A/B
# timings to GPU completion). AUTONOMY §7.2 step 2.
#
#     julia --project=benchmark benchmark/test/p6_0s_v7_tooling.jl
#     tools/exclusive.sh env POTTS_GPU=metal julia --project=benchmark benchmark/test/p6_0s_v7_tooling.jl
#
# The first command needs no GPU and never touches the machine lock. The second command
# also runs the Metal part.
#
# Contracts the implementation must keep (the test relies on them):
#  L1. Every path that `tools/exclusive.sh` (and anything `benchmark/ab.jl` uses for locking)
#      keeps lock or queue state in starts with the literal prefix `/tmp/potts-exclusive`.
#      The test copies `tools/` and `benchmark/*.jl` into a sandbox and rewrites that prefix
#      to a private directory, so it never takes or waits on the real machine lock.
#  L2. `ab.jl`'s command line is unchanged. Its runs are fresh processes,
#      `julia --project=benchmark <checkout>/benchmark/ab_one.jl <case> <alg>`, started in the
#      checkout. Each prints a line `AB <ns/site>`, and each round runs base then candidate.
#  T1. `measure(make, alg; backend)` in `benchmark/gate.jl` returns `(ns per site, allocs)`.
#      When `backend !== nothing`, the timed expression is `step!` followed by
#      `KernelAbstractions.synchronize(backend)`. When `backend === nothing` (the CPU rows),
#      nothing is added to the timed expression. The test uses
#      `backend = KernelAbstractions.CPU()` as a mock device, with `synchronize(::CPU)`
#      redefined to spin for 2 ms.
#  T2. In `benchmark/ab_one.jl`, the Metal timing includes `synchronize` (written directly
#      in a `@benchmarkable`, or through a function defined in gate.jl or ab_one.jl). The
#      CPU timing adds nothing.
#
# Lock checks besides the accept line: no two holders overlap; the command's exit status is
# passed through; the lock is free right after use; the state left by a SIGKILLed holder,
# once older than 3 h, does not block a new run (it proceeds within 60 s).
# Metal part (POTTS_GPU=metal): GG 72² gate and ab_one times are at least 0.5 × the time of
# `step!` + `synchronize` measured here. On 2026-10-01 the gate read 15 ns/site against
# 86–140 for step! + synchronize. The 0.5 factor covers the GPU's power states, which
# differ by about 1.6×.
#
# P6.0s accept line: "a waiter queued before an A/B starts runs before the A/B's second
# round". Scenario: a holder H holds the lock. A waiter W queues while H holds it. H
# releases, then an A/B with 4 rounds starts, using stub checkouts whose `ab_one.jl` only
# sleeps. Today W polls every 20 s, the A/B's runs re-take the lock at once, and W starves
# until the A/B ends. A design where ab.jl holds one lock for all its rounds also fails this
# test, because W then runs after the whole A/B.
using Test
using Printf: @sprintf

const REPO = normpath(joinpath(@__DIR__, "..", ".."))
const PREFIX = "/tmp/potts-exclusive"

# ---------------------------------------------------------------------------- helpers
"""A private copy of `tools/` and `benchmark/*.jl` whose lock prefix points into a temp dir."""
function sandbox()
    root = mktempdir(; cleanup = true)
    lockroot = joinpath(root, "lockroot")
    mkpath(lockroot)
    for (src, dst) in ((joinpath(REPO, "tools"), joinpath(root, "tools")),
                       (joinpath(REPO, "benchmark"), joinpath(root, "benchmark")))
        mkpath(dst)
        for f in readdir(src)
            p = joinpath(src, f)
            isfile(p) || continue
            src == joinpath(REPO, "benchmark") && !endswith(f, ".jl") && continue
            txt = read(p, String)
            write(joinpath(dst, f), replace(txt, PREFIX => joinpath(lockroot, "potts-exclusive")))
            chmod(joinpath(dst, f), filemode(p) | 0o700)
        end
    end
    return (; root, lockroot, excl = joinpath(root, "tools", "exclusive.sh"))
end

stamp_sh(log, tag, what) =
    "perl -MTime::HiRes=time -e 'printf qq(%s %s %.6f\\n), \$ARGV[0], \$ARGV[1], time' $tag $what >> $log"

"""`exclusive.sh` running a shell holder that stamps start/end around `sleep d`."""
holder(sb, log, tag, d) =
    Cmd([sb.excl, "sh", "-c", "$(stamp_sh(log, tag, "start")); sleep $d; $(stamp_sh(log, tag, "end"))"])

spawn(cmd; out = devnull) = run(pipeline(cmd; stdout = out, stderr = out); wait = false)

function events(log)
    isfile(log) || return Tuple{String, String, Float64}[]
    return [(String(a), String(b), parse(Float64, c)) for (a, b, c) in split.(filter(!isempty, readlines(log)))]
end
stamp_of(ev, tag, what) = (i = findfirst(e -> e[1] == tag && e[2] == what, ev); i === nothing ? nothing : ev[i][3])

function wait_until(f, timeout)
    t0 = time()
    while !f()
        time() - t0 > timeout && return false
        sleep(0.1)
    end
    return true
end

"""Kill only processes this test started (by PID), if they are still running."""
function reap!(procs)
    for p in procs
        process_running(p) && kill(p, Base.SIGKILL)
    end
end

"""Intervals `(start, end)` per run; `tags` as written by the stamps (each tag once)."""
function intervals(ev)
    out = Tuple{String, Float64, Float64}[]
    starts = [e for e in ev if e[2] == "start"]
    ends = [e for e in ev if e[2] == "end"]
    for s in starts
        i = findfirst(e -> e[1] == s[1] && e[3] >= s[3], ends)
        i === nothing && continue
        push!(out, (s[1], s[3], ends[i][3]))
        deleteat!(ends, i)
    end
    return sort(out; by = x -> x[2])
end
disjoint(iv) = all(iv[k][3] <= iv[k + 1][2] for k in 1:(length(iv) - 1))

const STUB_AB_ONE = raw"""
# stub ab_one for the P6.0s acceptance test: holds whatever lock it runs under for 3 s
log = ENV["P60S_LOG"]
tag = basename(dirname(@__DIR__))
st(w) = open(io -> println(io, tag, " ", w, " ", round(time(); digits = 6)), log, "a")
st("start"); sleep(3.0); st("end")
println("AB 1.0")
"""

function fake_checkout(root, name)
    d = joinpath(root, name)
    mkpath(joinpath(d, "benchmark"))
    write(joinpath(d, "benchmark", "Project.toml"), "")
    write(joinpath(d, "benchmark", "ab_one.jl"), STUB_AB_ONE)
    return d
end

# ---------------------------------------------------------------------------- scenarios
function fairness_scenario()
    sb = sandbox()
    log = joinpath(sb.root, "events.log")
    base, cand = fake_checkout(sb.root, "base"), fake_checkout(sb.root, "cand")
    about = joinpath(sb.root, "ab.out")
    procs = Base.Process[]
    try
        push!(procs, spawn(holder(sb, log, "H", 5)))
        wait_until(() -> stamp_of(events(log), "H", "start") !== nothing, 60) || return (; error = "H never started")
        push!(procs, spawn(holder(sb, log, "W", 1)))              # W queues while H holds
        sleep(1.0)
        tq = time()
        wait_until(() -> stamp_of(events(log), "H", "end") !== nothing, 60) || return (; error = "H never ended")
        sleep(0.5)
        tab = time()                                              # the A/B starts after W queued
        abcmd = setenv(`$(Base.julia_cmd()) --startup-file=no $(joinpath(sb.root, "benchmark", "ab.jl")) $base $cand fake_case sequential 4`,
            merge(ENV, Dict("P60S_LOG" => log)); dir = sb.root)
        ab = spawn(abcmd; out = about)
        push!(procs, ab)
        ok = wait_until(() -> !any(process_running, procs), 300)
        return (; error = ok ? nothing : "timeout after 300 s", ev = events(log), tq, tab,
            ab_ok = success(ab), abtxt = isfile(about) ? read(about, String) : "")
    finally
        reap!(procs)
    end
end

function mutex_scenario()
    sb = sandbox()
    log = joinpath(sb.root, "events.log")
    procs = [spawn(holder(sb, log, "M$k", 1)) for k in 1:3]
    try
        ok = wait_until(() -> !any(process_running, procs), 180)
        allok = ok && all(success, procs)
        # the exit status of the command is passed through, and the lock is free afterwards
        t0 = time()
        st = ok ? run(ignorestatus(Cmd([sb.excl, "sh", "-c", "exit 3"]))).exitcode : -1
        quick = ok ? (run(Cmd([sb.excl, "true"])); time() - t0) : Inf
        return (; error = ok ? nothing : "timeout after 180 s", ev = events(log), allok, st, quick)
    finally
        reap!(procs)
    end
end

function stale_scenario()
    sb = sandbox()
    log = joinpath(sb.root, "events.log")
    pidfile = joinpath(sb.root, "inner.pid")
    procs = Base.Process[]
    try
        k = spawn(Cmd([sb.excl, "sh", "-c", "echo \$\$ > $pidfile; exec sleep 600"]))
        push!(procs, k)
        wait_until(() -> isfile(pidfile) && !isempty(read(pidfile, String)), 60) || return (; error = "holder never started")
        inner = parse(Int, strip(read(pidfile, String)))
        run(ignorestatus(`kill -9 $inner`))                       # own descendant, by PID
        kill(k, Base.SIGKILL)                                     # no trap runs: state is left behind
        wait_until(() -> !process_running(k), 30)
        left = String[]
        for (d, dirs, files) in walkdir(sb.lockroot), x in vcat(dirs, files)
            push!(left, joinpath(d, x))
        end
        old = Libc.strftime("%Y%m%d%H%M.%S", time() - 4 * 3600)  # 4 h ago: past the 3 h rule
        for p in sort(left; by = length, rev = true)
            run(`touch -h -t $old $p`)
        end
        n = spawn(Cmd([sb.excl, "sh", "-c", stamp_sh(log, "N", "start")]))
        push!(procs, n)
        ok = wait_until(() -> stamp_of(events(log), "N", "start") !== nothing, 60)
        return (; error = nothing, ok, left)
    finally
        reap!(procs)
    end
end

# ---------------------------------------------------------------------------- P6.0v7 setup
module GateUnderTest end
Base.include(GateUnderTest, joinpath(REPO, "benchmark", "gate.jl"))
import KernelAbstractions
using BenchmarkTools: @benchmarkable
using Statistics: median
if get(ENV, "POTTS_GPU", "") == "metal"
    using Metal
end

# A mock device: `synchronize` on the CPU backend spins for SPIN_NS (it is a no-op
# otherwise). A timing that synchronizes an explicit backend must include the spin. A CPU
# row (no backend) must not include it.
const SPIN_NS = Ref(0)
KernelAbstractions.synchronize(::KernelAbstractions.CPU) =
    (t = time_ns(); while time_ns() - t < SPIN_NS[] end; nothing)

const SPIN = 2_000_000                       # 2 ms; a warm CPU MCS of GG 72² is ~0.15 ms

"""Every function defined in `files`: name => bodies (short and long form)."""
function defs(files)
    d = Dict{Symbol, Vector{Any}}()
    walk(ex) = ex isa Expr && begin
        if ex.head in (:function, :(=)) && ex.args[1] isa Expr && ex.args[1].head == :call
            f = ex.args[1].args[1]
            f isa Symbol && push!(get!(d, f, Any[]), ex.args[2])
        end
        foreach(walk, ex.args)
    end
    for f in files
        walk(Meta.parseall(read(f, String)))
    end
    return d
end
callee(ex) = ex isa Expr && ex.head == :call ? (f = ex.args[1]; f isa Expr && f.head == :. ? f.args[end] : f) : nothing
unq(x) = x isa QuoteNode ? x.value : x
function syncs(ex, d, seen = Set{Symbol}())
    ex isa Expr || return false
    c = unq(callee(ex))
    c === :synchronize && return true
    if c isa Symbol && haskey(d, c) && !(c in seen)
        push!(seen, c)
        any(b -> syncs(b, d, seen), d[c]) && return true
    end
    return any(a -> syncs(a, d, seen), ex.args)
end
"""`ex` contains a `@benchmarkable` whose timed expression synchronizes (or calls one that does)."""
function times_with_sync(ex, d, seen = Set{Symbol}())
    ex isa Expr || return false
    if ex.head == :macrocall && ex.args[1] === Symbol("@benchmarkable")
        core = first(a for a in ex.args[2:end] if !(a isa LineNumberNode))
        syncs(core, d) && return true
    end
    c = unq(callee(ex))
    if c isa Symbol && haskey(d, c) && !(c in seen)
        push!(seen, c)
        any(b -> times_with_sync(b, d, seen), d[c]) && return true
    end
    return any(a -> times_with_sync(a, d, seen), ex.args)
end

# ---------------------------------------------------------------------------- tests
@testset "P6.0s and P6.0v7 tooling acceptance" begin
    @testset "P6.0s fair machine lock" begin
        sb = sandbox()
        # L1: the sandbox is private. No `/tmp/` path is left except the sandbox's own: on
        # Linux `mktempdir` is itself under /tmp, so the rewritten prefix (inside
        # `sb.lockroot`) is masked before the search (P6.0bx).
        private(txt) = !occursin(PREFIX, txt) && !occursin("/tmp/", replace(txt, sb.lockroot => "<sandbox>"))
        for f in ("tools/exclusive.sh", "benchmark/ab.jl")
            @test private(read(joinpath(sb.root, f), String))
        end
        @test occursin(joinpath(sb.lockroot, "potts-exclusive"), read(sb.excl, String))  # the rewrite happened
        @test !private(read(joinpath(REPO, "tools", "exclusive.sh"), String))          # control: the real script fails
        fair = mut = stale = nothing
        @sync begin
            @async fair = fairness_scenario()
            @async mut = mutex_scenario()
            @async stale = stale_scenario()
        end

        @testset "waiter queued before an A/B runs before its second round" begin
            @test fair.error === nothing
            ev = fair.ev
            children = sort([e for e in ev if e[1] in ("base", "cand") && e[2] == "start"]; by = e -> e[3])
            @test fair.ab_ok
            @test count(startswith("round "), split(fair.abtxt, '\n')) == 4
            @test length(children) == 8
            @test [c[1] for c in children] == repeat(["base", "cand"], 4)
            hend, wstart, wend = stamp_of(ev, "H", "end"), stamp_of(ev, "W", "start"), stamp_of(ev, "W", "end")
            @test hend !== nothing && fair.tq < hend < fair.tab                # W queued while H held, before the A/B
            @test wstart !== nothing && wend !== nothing
            r2 = length(children) >= 3 ? children[3][3] : -Inf
            if wend !== nothing
                @info @sprintf("P6.0s: W ran %.1f s after the A/B started; round 2 started %.1f s after it", wend - fair.tab, r2 - fair.tab)
            end
            @test wend !== nothing && wend <= r2                             # the accept line
            iv = intervals(ev)
            @test length(iv) == 10                                            # H, W and 8 runs
            @test disjoint(iv)                                                # no two holders overlap
        end

        @testset "mutual exclusion and exit status" begin
            @test mut.error === nothing
            iv = intervals(mut.ev)
            @test length(iv) == 3
            @test mut.allok
            @test disjoint(iv)
            @test mut.st == 3
            @test mut.quick < 5
        end

        @testset "state of a killed holder is stale after 3 h" begin
            @test stale.error === nothing
            @test !isempty(stale.left)                                        # the kill left state behind
            @test stale.ok                                                     # aged past 3 h: a new run proceeds
        end
    end

    @testset "P6.0v7 timing to GPU completion" begin
        gatejl, abonejl = joinpath(REPO, "benchmark", "gate.jl"), joinpath(REPO, "benchmark", "ab_one.jl")
        gg = Dict(GateUnderTest.cases(Float64))["graner_glazier_72"]
        n = 72^2
        alg = GateUnderTest.CheckerboardCPM()

        @testset "gate measure: a device timing includes synchronize (mock device)" begin
            SPIN_NS[] = SPIN
            ns_dev, _ = GateUnderTest.measure(gg, alg; backend = KernelAbstractions.CPU())
            ns_cpu, allocs = GateUnderTest.measure(gg, alg)
            ns_seq, _ = GateUnderTest.measure(gg, GateUnderTest.SequentialCPM())
            SPIN_NS[] = 0
            @info @sprintf("P6.0v7 mock: device row %.1f µs per MCS (spin %.1f µs); CPU rows %.1f / %.1f µs",
                ns_dev * n / 1e3, SPIN / 1e3, ns_cpu * n / 1e3, ns_seq * n / 1e3)
            @test ns_dev * n >= SPIN                     # the synchronize is inside the timing
            @test ns_cpu * n < SPIN / 2                  # CPU rows add no synchronize
            @test ns_seq * n < SPIN / 2
            @test allocs == 0
        end

        @testset "gate CPU rows are unchanged" begin
            src = read(gatejl, String)
            @test occursin("\"sequential\" => (SequentialCPM(), nothing, Float64)", src)
            @test occursin("\"checkerboard\" => (CheckerboardCPM(), nothing, Float64)", src)
        end

        @testset "ab_one: the Metal timing includes synchronize (structural)" begin
            d = defs([gatejl, abonejl])
            body = Meta.parseall(read(abonejl, String))
            @test times_with_sync(body, d)
        end

        @testset "ab_one: the CPU timing adds no synchronize (mock device)" begin
            pre = tempname() * ".jl"
            write(pre, """
                import KernelAbstractions
                KernelAbstractions.synchronize(::KernelAbstractions.CPU) =
                    (t = time_ns(); while time_ns() - t < $SPIN end; nothing)
                """)
            code = "include(popfirst!(ARGS)); include($(repr(abonejl)))"
            cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code $pre graner_glazier_72 checkerboard`; dir = REPO)
            out = read(cmd, String)
            line = filter(startswith("AB "), split(out, '\n'))
            @test length(line) == 1
            ab = parse(Float64, last(split(only(line))))
            @info @sprintf("P6.0v7 mock: ab_one CPU %.1f µs per MCS", ab * n / 1e3)
            @test ab * n < SPIN / 2
        end

        if get(ENV, "POTTS_GPU", "") == "metal"
            @testset "Metal: GG 72 gate and ab_one time step! to completion" begin
                be = Metal.MetalBackend()
                gg32 = Dict(GateUnderTest.cases(Float32))["graner_glazier_72"]
                prob = gg32()
                fresh() = (i = GateUnderTest.init(prob, alg; backend = be, save_start = false, save_end = false);
                    GateUnderTest.step!(i); GateUnderTest.step!(i); KernelAbstractions.synchronize(be); i)
                fresh()
                ref() = run(@benchmarkable((GateUnderTest.step!(i); KernelAbstractions.synchronize($be)),
                    setup = (i = $fresh()), evals = 1, samples = 40, seconds = 20))
                # interleaved, so both sides see the same GPU power states; min vs min
                r1 = ref(); g1 = first(GateUnderTest.measure(gg32, alg; backend = be))
                r2 = ref(); g2 = first(GateUnderTest.measure(gg32, alg; backend = be))
                rmin = min(minimum(r1).time, minimum(r2).time) / n
                gmin = min(g1, g2)
                @info @sprintf("P6.0v7 Metal GG 72: gate %.2f ns/site, step!+synchronize %.2f ns/site", gmin, rmin)
                @test gmin >= 0.5 * rmin
                out = read(Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $abonejl graner_glazier_72 metal`; dir = REPO), String)
                ab = parse(Float64, last(split(only(filter(startswith("AB "), split(out, '\n'))))))
                r3 = ref()
                rmed = minimum(median(r).time for r in (r1, r2, r3)) / n
                @info @sprintf("P6.0v7 Metal GG 72: ab_one median %.2f ns/site, step!+synchronize median %.2f ns/site", ab, rmed)
                @test ab >= 0.5 * rmed
            end
        else
            @info "P6.0v7 Metal part skipped (set POTTS_GPU=metal and run under tools/exclusive.sh)"
        end
    end
end
