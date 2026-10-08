# Tests of the paired A/B harness and the gate (P6.0bb, D-157): machine table and pinning
# helpers, Tuple type cache seeding, `ab.jl` arguments, round rotation, statistics,
# intervals and verdicts (with per-round stub timings), skips, disturbed runs, the
# in-process form, the same-commit control checkouts, `gate.jl` with a mocked `measure`, and
# the per-machine `baseline.toml`.
#
#     julia --project=benchmark benchmark/test/p6_0bb_ab.jl
#
# No timing and no GPU. Like the frozen P6.0s test, `ab.jl` runs in a sandbox whose lock
# prefix points into a private directory, with a stub timed child (`--child`), so it never
# takes the real machine lock.
using Test, TOML

const REPO = normpath(joinpath(@__DIR__, "..", ".."))
const PREFIX = "/tmp/potts-exclusive"
include(joinpath(REPO, "benchmark", "machine.jl"))
include(joinpath(REPO, "benchmark", "ab.jl"))            # defines functions; main is guarded

jl() = `$(Base.julia_cmd()) --startup-file=no`

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
            write(joinpath(dst, f),
                replace(read(p, String), PREFIX => joinpath(lockroot, "potts-exclusive")))
            chmod(joinpath(dst, f), filemode(p) | 0o700)
        end
    end
    return root
end

# A stub timed child, like `ab_one.jl`. Per checkout name `n` (base, cand, base-abctl,
# cand-abctl, or the in-process labels), `$STUB_DIR/n.txt` lists factors, one per run of
# that side (cycled; default 1); every case reads 10 ns/site × factor. `n.skip` lists
# labels to skip, `n.disturb` a disturbance to report. Logs `n args threads=…`.
const STUB = raw"""
sd = ENV["STUB_DIR"]
factors(n) = (f = joinpath(sd, n * ".txt"); isfile(f) ? parse.(Float64, split(read(f, String))) : [1.0])
function nextrun(n)
    f = joinpath(sd, n * ".count")
    k = isfile(f) ? parse(Int, read(f, String)) : 0
    write(f, string(k + 1))
    return k
end
fac(n) = (fs = factors(n); fs[mod1(nextrun(n) + 1, length(fs))])
me = basename(pwd())
open(io -> println(io, me, " ", join(ARGS, " "), " threads=", get(ENV, "JULIA_NUM_THREADS", "")), ENV["STUB_LOG"], "a")
println("TC 500000 1048576")
pos = filter(a -> !startswith(a, "--"), ARGS)
opt(k) = (i = findfirst(startswith("--$k="), ARGS); i === nothing ? nothing : split(ARGS[i], '='; limit = 2)[2])
if opt("variants") !== nothing
    labels = "--no-control" in ARGS ? ["base", "candidate"] : ["base", "candidate", "base-ctl", "cand-ctl"]
    for r in 1:parse(Int, opt("rounds")), l in circshift(labels, -(r - 1))
        f = fac(l)
        println("ABR $l:$(pos[1]) $(10f) $(9f) 60")
    end
else
    f = fac(me)
    skip = (s = joinpath(sd, me * ".skip"); isfile(s) ? split(read(s, String)) : String[])
    for v in split(pos[2], ','), c in split(pos[1], ',')
        "$c.$v" in skip ? println("ABSKIP $c.$v") : println("ABR $c.$v $(10f) $(9f) 60")
    end
    d = joinpath(sd, me * ".disturb")
    isfile(d) && println("DISTURBED ", strip(read(d, String)))
end
println("TC 500100 1048576")
"""

g(dir, args...) = run(`git -C $dir -c user.name=t -c user.email=t@t $args`)

"""
Two clean git checkouts `base` and `cand` in a fresh root, and the stub's directory.
"""
function checkouts()
    root = mktempdir(; cleanup = true)
    dirs = map(("base", "cand")) do n
        d = joinpath(root, n)
        mkpath(d)
        g(d, "init", "-q")
        write(joinpath(d, "a.txt"), n)
        g(d, "add", "a.txt")
        g(d, "commit", "-qm", n)
        d
    end
    sd = joinpath(root, "stub")
    mkpath(sd)
    return root, dirs..., sd
end

function run_ab(sb, sd, args)
    out = IOBuffer()
    env = Dict("STUB_LOG" => joinpath(sd, "log"), "STUB_DIR" => sd, "POTTS_MACHINE" => "test-machine")
    cmd = setenv(`$(jl()) $(joinpath(sb, "benchmark", "ab.jl")) $args`, merge(ENV, env); dir = sb)
    p = run(pipeline(ignorestatus(cmd); stdout = out, stderr = out))
    log = joinpath(sd, "log")
    return p.exitcode, String(take!(out)),
    isfile(log) ? split.(readlines(log)) : Vector{SubString{String}}[]
end
setf(sd, n, fs...) = write(joinpath(sd, n * ".txt"), join(fs, " "))

@testset "P6.0bb paired A/B harness" begin
    @testset "machine table" begin
        @test BenchMachine.cpulist("0-11,16-27") == [0:11; 16:27]
        @test BenchMachine.cpulist("12") == [12]
        withenv("POTTS_MACHINE" => "nucbox") do
            m = BenchMachine.machine()
            @test m.key == "nucbox" && m.bench == 12:15 && m.work == "0-11,16-27"
            @test BenchMachine.bench_cpu(m) == 12
            if Sys.islinux() && Sys.which("systemd-run") !== nothing
                # with a user service manager (a login or SSH session) the cap applies;
                # without one (a CI job) it is dropped, tested below
                @test BenchMachine.mem_cmd(m) ==
                      (BenchMachine.user_scope_works() ?
                       `systemd-run --user --scope -q -p MemoryMax=8G` : ``)
                withenv(() -> (@test BenchMachine.mem_cmd(m) == ``), "POTTS_BENCH_MEMMAX" => "0")
            end
            withenv(() -> (@test BenchMachine.bench_cpu(m) == 14), "POTTS_BENCH_CPU" => "14")
        end
        # no user service manager (a CI job under the runner's system service): no cap,
        # rather than a `systemd-run --user` prefix that fails every child (CI 37721528049)
        withenv("POTTS_MACHINE" => "nucbox") do
            m = BenchMachine.machine()
            @test BenchMachine.mem_cmd(m; works = () -> false) == ``
            if Sys.islinux() && Sys.which("systemd-run") !== nothing
                @test BenchMachine.mem_cmd(m; works = () -> true) ==
                      `systemd-run --user --scope -q -p MemoryMax=8G`
                # the real probe, in a process without a user bus, as under the runner
                mj = joinpath(REPO, "benchmark", "machine.jl")
                code = "include($(repr(mj))); m = BenchMachine.machine(); " *
                       "print(BenchMachine.user_scope_works(), \" \", isempty(BenchMachine.mem_cmd(m).exec))"
                env = filter(p -> !(first(p) in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS")), ENV)
                env["POTTS_MACHINE"] = "nucbox"
                out = read(setenv(`$(jl()) -e $code`, env), String)
                @test out == "false true"
                # and the D-090 run itself works there: a stub child runs and prints its line
                stubco = mktempdir(; cleanup = true)
                mkpath(joinpath(stubco, "benchmark"))
                write(joinpath(stubco, "benchmark", "Project.toml"), "")
                write(joinpath(stubco, "benchmark", "ab_one.jl"), "println(\"AB 1.0\")")
                sbx = sandbox()
                p = run(pipeline(ignorestatus(setenv(
                        `$(jl()) $(joinpath(sbx, "benchmark", "ab.jl")) $stubco $stubco c sequential 1`,
                        env; dir = sbx)); stdout = devnull, stderr = devnull))
                @test success(p)
            end
        end
        withenv("POTTS_MACHINE" => "elsewhere") do
            m = BenchMachine.machine()
            @test m.key == "elsewhere" && isempty(m.bench) && !BenchMachine.pins(m)
            @test BenchMachine.pin_cmd(m, 12) == `` && BenchMachine.work_cmd(m) == `` &&
                  BenchMachine.mem_cmd(m) == ``
        end
        @test BenchMachine.slug("AMD RYZEN AI MAX+ 395 w/ Radeon 8060S") ==
              "amd-ryzen-ai-max-395-w-radeon-8060s"
        @test BenchMachine.gpu_users() isa Vector{Int}
        @test BenchMachine.busy_reasons(; ci = false) == String[]
        @test BenchMachine.wait_idle(; ci = false, gpu = false)          # nothing to wait for
        if Sys.islinux()
            @test BenchMachine.allowed_cpus() isa Vector{Int}
            @test BenchMachine.siblings(0) isa Vector{Int}
            @test BenchMachine.disturbances(-1, Int[]; ci = false) == String[]
            @test getpid() in BenchMachine.ancestors()
            # inside a CI job the runner's worker is an ancestor, and does not count
            @test BenchMachine.ci_job_running() isa Bool
        end
        # disturbances with injected CPU load and topology
        sibs(c) = c < 16 ? [c + 16] : [c - 16]
        dist(load; reasons = () -> String[]) = BenchMachine.disturbances(12, 12:15;
            busy = cpus -> Dict(k => get(load, k, 0.0) for k in cpus), siblings = sibs,
            linux = true, reasons)
        @test dist(Dict()) == String[]
        @test dist(Dict(28 => 0.10)) == ["SMT sibling cpu28 10% busy"]
        @test dist(Dict(28 => 0.03)) == String[]                     # below 5 %: idle enough
        @test dist(Dict(14 => 0.90, 30 => 0.40)) == ["reserved cpu14 90% busy"]
        @test dist(Dict(13 => 0.30)) == String[]                     # below 50 %
        @test dist(Dict(); reasons = () -> ["a CI job (Runner.Worker) is running"]) ==
              ["a CI job (Runner.Worker) is running"]
        @test BenchMachine.disturbances(12, 12:15; linux = false,
            reasons = () -> String[], busy = _ -> error("not called")) == String[]
    end

    @testset "Tuple type cache seeding is equal whatever the session made before" begin
        mj = joinpath(REPO, "benchmark", "machine.jl")
        mk(pre,
            body) = "include($(repr(mj))); for i in 1:$pre; Core.apply_type(Tuple, Val{i}, Val{:other}); end; $body"
        probe(pre) = split(readchomp(`$(jl()) -e $(mk(pre, "s = BenchMachine.seed_type_cache!(); println(s.entries, \" \", s.capacity)"))`))
        a, b = probe(0), probe(25_000)                       # the second session made 25k more types
        @test parse(Int, a[2]) == parse(Int, b[2])           # same table size
        @test abs(parse(Int, a[1]) - parse(Int, b[1])) <= 100  # same number of entries
        @test parse(Int, a[1]) >= BenchMachine.SEED_ENTRIES
        # negative control: unseeded, the two sessions' tables differ
        probe0(pre) = split(readchomp(`$(jl()) -e $(mk(pre, "println(join(BenchMachine.type_cache_stats(), \" \"))"))`))
        u, v = probe0(0), probe0(25_000)
        @test parse(Int, v[1]) - parse(Int, u[1]) >= 20_000
    end

    @testset "arguments" begin
        @test islegacy(["b", "c", "gg", "sequential", "4"])           # the frozen D-090 form
        @test islegacy(["b", "c", "gg", "checkerboard"])
        @test !islegacy(["b", "c", "gg", "metal"])                    # Metal goes to the paired form
        @test !islegacy(["b", "c", "gg", "sequential", "--rounds=4"])
        @test !islegacy(["b", "c", "gg", "cpu", "4"])
        @test_throws ErrorException parse_ab(["b", "c", "gg"])        # the 3-argument form errors
        o = withenv(() -> parse_ab(["b", "c", "all", "cpu"]), "POTTS_MACHINE" => "nucbox")
        @test o.variants == "sequential,checkerboard" && o.rounds == 8 && o.control &&
              o.seed == BenchMachine.SEED_ENTRIES
        @test o.tolerance == 0.05 && o.warm && o.wait == "all" && o.maxwait == 4 * 3600
        @test o.pin == (Sys.islinux() && Sys.which("taskset") !== nothing)
        @test o.stat == "paired" && parse_ab(["b", "c", "gg", "metal"]).stat == "fastest"
        @test parse_ab(["b", "c", "gg", "metal", "3"]).rounds == 3
        @test parse_ab(["b", "c", "gg", "cpu", "--stat=fastest"]).stat == "fastest"
        @test parse_ab(["b", "c", "gg", "cpu", "--wait=gpu", "--max-wait=0.5"]).maxwait ==
              1800
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cpu", "--stat=mean"])
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cpu", "--wait=sometimes"])
        o = parse_ab([
            "b", "c", "gg", "sequential", "--no-control", "--no-seed", "--rounds=3"])
        @test o.backend == "cpu" && o.variants == "sequential" && !o.control &&
              o.seed == 0 &&
              o.rounds == 3
        o = parse_ab(["b", "c", "gg", "rocm", "8", "--no-pin"])
        @test o.variants == "rocm" && o.rounds == 8 && !o.pin
        o = parse_ab(["--inprocess", "d", "v.jl", "cpu", "--alg=checkerboard"])
        @test o.inprocess && o.pos == ["d", "v.jl", "cpu"] && o.variants == "checkerboard"
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cuda"])
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cpu", "--alg=metal"])
        @test_throws ErrorException parse_ab(["b", "c"])
    end

    @testset "statistics and intervals" begin
        x = [(10.0, 9.0), (11.0, 9.0), (11.0, 9.0), (11.0, 9.0)]
        y = [(11.0, 9.0), (11.0, 9.0), (11.0, 9.0), (11.0, 9.0)]
        @test paired(x, y) ≈ 1.0                       # per-round ratios 1.1, 1, 1, 1
        @test fastest(y) / fastest(x) ≈ 1.1
        lo, hi = boot_interval([1.0, 1.0, 1.0, 1.0])
        @test lo == hi == 1.0
        r = [0.99, 1.01, 1.0, 1.02, 0.98, 1.0, 1.01, 0.99]
        lo, hi = boot_interval(r)
        @test lo <= mid(r) <= hi && lo < 1 < hi && hi - lo < 0.04
        @test boot_interval(r) == boot_interval(r)     # fixed seed: reproducible
        @test_throws ErrorException ratios(x, y[1:3])   # mismatched round counts
        lo, hi = boot_interval(r .+ 0.05)
        @test lo > 1                                   # an offset control excludes 1
    end

    sb = sandbox()
    stub = joinpath(sb, "stub.jl")
    write(stub, STUB)
    common = ["--no-warm", "--child=$stub", "--wait=none", "--alg=sequential"]
    @testset "rounds rotate; verdicts on per-round timings" begin
        # (factor lists per side, expected exit code, extra args)
        scen = [
            (Dict(), 0, String[]),                                   # all equal: pass
            (Dict("cand" => (1.10,), "cand-abctl" => (1.10,)), 1, String[]),          # 10 % slower
            # an offset control (3 %) narrows the pass margin to 1.02: 1.03 is unreadable
            (Dict("base-abctl" => (1.03,), "cand" => (1.03,), "cand-abctl" => (1.03,)),
                2,
                String[]),
            # probe B: controls offset by 1 %, candidate 1.03 <= margin 1.04: pass
            (Dict("base-abctl" => (1.01,), "cand" => (1.03,), "cand-abctl" => (1.0403,)),
                0,
                String[]),
            # probe A: a noisy control (point 1.04, its interval containing 1) and a
            # candidate at 1.048, inside 1 + tolerance but above the margin 1.01: unreadable
            (
                Dict("base-abctl" => (0.95, 0.96, 1.03, 1.04, 1.04, 1.05, 1.10, 1.10),
                    "cand" => (1.048,), "cand-abctl" => (1.048,)),
                2,
                ["--rounds=8"]),
            # drift: the base's first run is fast, so paired (1.0) and fastest (1.1) differ
            (
                Dict("base" => (1.0, 1.1, 1.1, 1.1), "base-abctl" => (1.0, 1.1, 1.1, 1.1),
                    "cand" => (1.1,), "cand-abctl" => (1.1,)),
                0,
                String[]),
            (
                Dict("base" => (1.0, 1.1, 1.1, 1.1), "base-abctl" => (1.0, 1.1, 1.1, 1.1),
                    "cand" => (1.1,), "cand-abctl" => (1.1,)),
                1,
                ["--stat=fastest"])
        ]
        for (fs, code, extra) in scen
            root, b, c, sd = checkouts()
            for (n, f) in fs
                setf(sd, n, f...)
            end
            st, out, ev = run_ab(sb, sd,
                [b, c, "gg,wa", "cpu", "--rounds=4", common..., extra...])
            @test st == code
            code == 0 && @test occursin("verdict (paired): pass", out)
            code == 2 && @test occursin("UNREADABLE", out)
            @test occursin("pass margin: candidate/base <=", out)
            @test isdir(b * "-abctl") && isdir(c * "-abctl")
            @test length(ev) == 4 * ("--rounds=8" in extra ? 8 : 4)    # 4 sides × rounds
            @test first.(ev[1:8]) == ["base", "cand", "base-abctl", "cand-abctl",
                "cand", "base-abctl", "cand-abctl", "base"]
            @test all(
                e -> "--seed=$(BenchMachine.SEED_ENTRIES)" in e && "threads=1" in e &&
                     "--wait=none" in e && any(startswith("--deadline="), e),
                ev)
            @test occursin("gg.sequential", out) && occursin("wa.sequential", out)
            @test occursin("resolution: largest control deviation", out)
            @test occursin("harness: ", out)
        end
    end

    @testset "skips, disturbed runs, no control" begin
        root, b, c, sd = checkouts()
        write(joinpath(sd, "base.skip"), "wa.sequential")            # an older base lacks `wa`
        st, out, _ = run_ab(sb, sd, [b, c, "gg,wa", "cpu", "--rounds=4", common...])
        @test st == 0 && occursin("skipped (not in the base): wa.sequential", out)
        @test occursin("gg.sequential", out) && !occursin(r"\nwa\.sequential", out)
        root, b, c, sd = checkouts()
        write(joinpath(sd, "cand.skip"), "wa.sequential")            # the candidate may not skip
        st, out, _ = run_ab(sb, sd, [b, c, "gg,wa", "cpu", "--rounds=4", common...])
        @test st == 4 && occursin("only the base and its control may lack a case", out)
        root, b, c, sd = checkouts()
        write(joinpath(sd, "base.skip"), "gg.sequential")
        st, out, _ = run_ab(sb, sd, [b, c, "gg", "cpu", "--rounds=4", common...])
        @test st == 4 && occursin("no case was timed on every side", out)
        root, b, c, sd = checkouts()
        write(joinpath(sd, "cand.disturb"), "a CI job (Runner.Worker) is running")
        st, out, _ = run_ab(sb, sd, [b, c, "gg", "cpu", "--rounds=4", common...])
        @test st == 3 && occursin("disturbed runs (4)", out)
        root, b, c, sd = checkouts()                                 # disturbed beats slower
        write(joinpath(sd, "cand.disturb"), "a CI job (Runner.Worker) is running")
        setf(sd, "cand", 1.2)
        setf(sd, "cand-abctl", 1.2)
        st, out, _ = run_ab(sb, sd, [b, c, "gg", "cpu", "--rounds=4", common...])
        @test st == 3
        root, b, c, sd = checkouts()                                 # bad arguments: harness error
        st, out, _ = run_ab(sb, sd, [b, c, "gg", "cuda", common...])
        @test st == 4 && occursin("harness error", out)
        root, b, c, sd = checkouts()
        st, out, ev = run_ab(sb, sd, [
            b, c, "gg", "cpu", "--rounds=4", "--no-control", common...])
        @test st == 0 &&
              first.(ev) == ["base", "cand", "cand", "base", "base", "cand", "cand", "base"]
        @test !isdir(b * "-abctl") && !occursin("resolution:", out)
        root, b, c, sd = checkouts()
        write(joinpath(c, "a.txt"), "dirty")                         # a control needs a clean checkout
        st, out, _ = run_ab(sb, sd, [b, c, "gg", "cpu", "--rounds=4", common...])
        @test st == 4 && occursin("uncommitted changes", out)
    end

    @testset "in-process form" begin
        root, b, c, sd = checkouts()
        vf = joinpath(root, "variants.jl")
        write(vf, "const AB_VARIANTS = []")
        setf(sd, "candidate", 1.2)
        st, out, ev = run_ab(sb, sd, ["--inprocess", b, vf, "cpu", "--rounds=4", common...])
        @test st == 1 && occursin("REGRESSION", out)
        @test length(ev) == 1 && any(startswith("--variants="), ev[1]) &&
              !("--no-control" in ev[1])
        @test !isdir(b * "-abctl")                                   # in process: no control checkout
        root, b, c, sd = checkouts()
        st, out, ev = run_ab(sb, sd, [
            "--inprocess", b, vf, "cpu", "--rounds=4", "--no-control", common...])
        @test st == 0 && "--no-control" in ev[1] && !occursin("base-ctl", out)
    end

    @testset "same-commit control checkout" begin
        root, base, cand, _ = checkouts()
        write(joinpath(base, "Manifest.toml"), "# manifest")          # untracked, copied over
        ctl = control_checkout(base)
        @test ctl == base * "-abctl"
        @test git(ctl, "rev-parse", "HEAD") == git(base, "rev-parse", "HEAD")
        @test read(joinpath(ctl, "Manifest.toml"), String) == "# manifest"
        write(joinpath(base, "a.txt"), "2")
        g(base, "commit", "-qam", "two")
        @test control_checkout(base) == ctl                            # moved to the new commit
        @test git(ctl, "rev-parse", "HEAD") == git(base, "rev-parse", "HEAD")
        @test read(joinpath(ctl, "a.txt"), String) == "2"
        write(joinpath(ctl, "a.txt"), "edited")                        # a dirty control is refused
        @test_throws ErrorException control_checkout(base)
        g(ctl, "checkout", "--", "a.txt")
        mv(cand, base * "-other")                                      # another repository at the path
        rm(ctl; recursive = true)
        g(base, "worktree", "prune")
        mv(base * "-other", ctl)
        @test_throws ErrorException control_checkout(base)
        rm(ctl; recursive = true)
        # a directory inside a checkout is refused before anything is written (H-B)
        nw = length(readlines(`git -C $base worktree list`))
        mkpath(joinpath(base, "sub"))                                   # a plain nested directory
        mkpath(joinpath(base, "benchmark"))                             # like <checkout>/benchmark
        write(joinpath(base, "benchmark", "x.txt"), "x")
        g(base, "add", "benchmark/x.txt")
        g(base, "commit", "-qm", "bench")
        for d in (joinpath(base, "sub"), joinpath(base, "benchmark"))
            @test_throws ErrorException control_checkout(d)
            @test !isdir(d * "-abctl")
        end
        @test length(readlines(`git -C $base worktree list`)) == nw
        mkpath(ctl)                                                     # a plain directory at the path
        @test_throws ErrorException control_checkout(base)
        @test length(readlines(`git -C $base worktree list`)) == nw
        rm(ctl; recursive = true)
        write(joinpath(base, "a.txt"), "dirty")
        @test_throws ErrorException control_checkout(base)             # a dirty base has no control
    end

    @testset "ab_one.jl with a mocked gate" begin
        sb2 = sandbox()
        write(joinpath(sb2, "benchmark", "gate.jl"), """
            using BenchmarkTools
            const DEVICE = ""
            device_backend() = nothing
            struct SequentialCPM end
            struct CheckerboardCPM end
            cases(T) = ["fake" => () -> (; u0 = (; σ = zeros(T, 10)))]
            fresh_integrator(prob, alg, backend) = nothing
            timed_step!(i, backend) = (sleep(0.0005); nothing)
            """)
        one = joinpath(sb2, "benchmark", "ab_one.jl")
        proj = joinpath(REPO, "benchmark")
        run1(args...) = read(ignorestatus(`$(jl()) --project=$proj $one $args`), String)
        out = run1("fake", "sequential,checkerboard", "--samples=3", "--seconds=1",
            "--wait=none", "--seed=0")
        l = filter(!isempty, split(out, '\n'))
        @test count(startswith("ABR fake.sequential "), l) == 1
        @test count(startswith("ABR fake.checkerboard "), l) == 1
        @test count(startswith("TC "), l) == 2 && !any(startswith("DISTURBED"), l)
        r = split(only(filter(startswith("ABR fake.sequential "), l)))
        @test 2e3 < parse(Float64, r[3]) < 1e6        # ~0.5 ms per MCS over 10 sites, in ns
        out = run1(
            "fake", "sequential", "--samples=3", "--seconds=1", "--wait=gpu", "--seed=0")
        @test occursin("ABR fake.sequential", out)    # nothing to wait for without a device
        out = run1(
            "all", "sequential", "--samples=3", "--seconds=1", "--wait=none", "--seed=0")
        @test occursin("ABR fake.sequential", out)
        out = run1("fake", "sequential")             # the D-090 form: one AB line only
        l = filter(!isempty, split(out, '\n'))
        @test length(l) == 1 && startswith(l[1], "AB ")
        buf = IOBuffer()
        p = run(pipeline(
            ignorestatus(`$(jl()) --project=$proj $one nope sequential --wait=none --seed=0`);
            stdout = buf, stderr = buf))
        @test !success(p) && occursin("unknown case", String(take!(buf)))
    end

    @testset "gate.jl with a mocked measure" begin
        G = Core.eval(Main, :(module GateMock end))
        Base.include(G, joinpath(REPO, "benchmark", "gate.jl"))
        Core.eval(G, quote
            const MOCK = Ref{Any}(nothing)
            cases(T) = ["c1" => () -> 1, "c2" => () -> 2]
            measure(make, alg; backend = nothing) = MOCK[](make(), nameof(typeof(alg)))
        end)
        withenv("POTTS_MACHINE" => "test-machine") do
            dir = mktempdir(; cleanup = true)
            bl = joinpath(dir, "baseline.toml")
            write(bl, """
                [other.cpu]
                "c1.sequential" = 99.0
                [test-machine.metal]
                "c1.checkerboard" = 5.0
                [test-machine.cpu]
                "c1.sequential" = 10.0
                "c2.sequential" = 10.0
                "c1.checkerboard" = 10.0
                "c2.checkerboard" = 10.0
                """)
            G.MOCK[] = (c, a) -> (10.0, 0)
            @test G.main(["--no-wait"]; baseline = bl) == 0
            G.MOCK[] = (c, a) -> (c == 2 && a == :SequentialCPM ? 13.0 : 10.0, 0)   # 30 % slower
            @test G.main(["--no-wait"]; baseline = bl) == 0                         # informational
            @test G.main(["--no-wait", "--strict"]; baseline = bl) == 1             # the old rule
            G.MOCK[] = (c, a) -> (10.0, c == 1 ? 16 : 0)                            # allocates
            @test G.main(["--no-wait"]; baseline = bl) == 1
            G.MOCK[] = (c, a) -> (c == 1 ? 7.0 : 8.0, 0)
            @test G.main(["--no-wait", "update"]; baseline = bl) == 0
            t = TOML.parsefile(bl)
            @test t["other"]["cpu"]["c1.sequential"] == 99.0                       # other machines kept
            @test t["test-machine"]["metal"]["c1.checkerboard"] == 5.0              # other backends kept
            @test t["test-machine"]["cpu"] ==
                  Dict("c1.sequential" => 7.0, "c2.sequential" => 8.0,
                "c1.checkerboard" => 7.0, "c2.checkerboard" => 8.0)
            @test t["test-machine"]["meta"]["threads"] == 1
            @test startswith(read(bl, String), "# Informational per-machine baselines")
        end
    end

    @testset "baseline.toml is keyed by machine and backend" begin
        t = TOML.parsefile(joinpath(REPO, "benchmark", "baseline.toml"))
        @test haskey(t, "mac")
        for (mk, mt) in t
            @test mt isa Dict && haskey(mt, "meta")
            for (bk, rows) in mt
                bk == "meta" && continue
                @test bk in ("cpu", "metal", "rocm")
                @test all(k -> occursin(r"^[a-z0-9_]+\.(sequential|checkerboard)$", k), keys(rows))
                bk == "cpu" || @test all(endswith(".checkerboard"), keys(rows))
                @test all(v -> v isa Real && v > 0, values(rows))
            end
        end
    end
end
