# Tests of the paired A/B harness (P6.0bb, D-157): machine table and pinning helpers, Tuple
# type cache seeding, `ab.jl` arguments, round rotation, verdicts and the same-commit control
# checkout, and the per-machine `baseline.toml`.
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
    lockroot = joinpath(root, "lockroot"); mkpath(lockroot)
    for (src, dst) in ((joinpath(REPO, "tools"), joinpath(root, "tools")), (joinpath(REPO, "benchmark"), joinpath(root, "benchmark")))
        mkpath(dst)
        for f in readdir(src)
            p = joinpath(src, f)
            isfile(p) || continue
            write(joinpath(dst, f), replace(read(p, String), PREFIX => joinpath(lockroot, "potts-exclusive")))
            chmod(joinpath(dst, f), filemode(p) | 0o700)
        end
    end
    return root
end

# A stub timed child: logs its side and arguments, prints ABR lines scaled by the factor in
# `<checkout>/factor.txt` (10 ns/site × factor), like `ab_one.jl`.
const STUB = raw"""
dir = pwd()
f = parse(Float64, strip(read(joinpath(dir, "factor.txt"), String)))
open(io -> println(io, basename(dir), " ", join(ARGS, " "), " threads=", get(ENV, "JULIA_NUM_THREADS", "")), ENV["STUB_LOG"], "a")
println("TC 100000 262144")
pos = filter(a -> !startswith(a, "--"), ARGS)
for v in split(pos[2], ','), c in split(pos[1], ',')
    println("ABR $c.$v $(10f) $(9f) 60")
end
println("TC 100500 262144")
"""

function fake(root, name, factor)
    d = joinpath(root, name); mkpath(d)
    write(joinpath(d, "factor.txt"), string(factor))
    return d
end

function run_ab(sb, args; log)
    out = IOBuffer()
    cmd = setenv(`$(jl()) $(joinpath(sb, "benchmark", "ab.jl")) $args`,
        merge(ENV, Dict("STUB_LOG" => log, "POTTS_MACHINE" => "test-machine", "POTTS_BENCH_NOWAIT" => "1")); dir = sb)
    p = run(pipeline(ignorestatus(cmd); stdout = out, stderr = out))
    return p.exitcode, String(take!(out))
end

@testset "P6.0bb paired A/B harness" begin
    @testset "machine table" begin
        @test BenchMachine.cpulist("0-11,16-27") == [0:11; 16:27]
        @test BenchMachine.cpulist("12") == [12]
        withenv("POTTS_MACHINE" => "nucbox") do
            m = BenchMachine.machine()
            @test m.key == "nucbox" && m.bench == 12:15 && m.work == "0-11,16-27" && m.control_bound == 0.01
            @test BenchMachine.bench_cpu(m) == 12
            if Sys.islinux() && Sys.which("systemd-run") !== nothing
                @test BenchMachine.mem_cmd(m) == `systemd-run --user --scope -q -p MemoryMax=8G`
                withenv(() -> (@test BenchMachine.mem_cmd(m) == ``), "POTTS_BENCH_MEMMAX" => "0")
            end
            withenv(() -> (@test BenchMachine.bench_cpu(m) == 14), "POTTS_BENCH_CPU" => "14")
        end
        withenv("POTTS_MACHINE" => "elsewhere") do
            m = BenchMachine.machine()
            @test m.key == "elsewhere" && isempty(m.bench) && !BenchMachine.pins(m)
            @test BenchMachine.pin_cmd(m, 12) == `` && BenchMachine.work_cmd(m) == `` && BenchMachine.mem_cmd(m) == ``
        end
        @test BenchMachine.slug("AMD RYZEN AI MAX+ 395 w/ Radeon 8060S") == "amd-ryzen-ai-max-395-w-radeon-8060s"
        if Sys.islinux()
            @test BenchMachine.allowed_cpus() isa Vector{Int}
            @test BenchMachine.siblings(0) isa Vector{Int}
        end
    end

    @testset "Tuple type cache seeding is equal whatever the session made before" begin
        mj = joinpath(REPO, "benchmark", "machine.jl")
        probe(pre) = split(readchomp(`$(jl()) -e "include($(repr(mj))); for i in 1:$pre; Core.apply_type(Tuple, Val{i}, Val{:other}); end; s = BenchMachine.seed_type_cache!(); println(s.entries, \" \", s.capacity)"`))
        a, b = probe(0), probe(25_000)                       # the second session made 25k more types
        @test parse(Int, a[2]) == parse(Int, b[2])           # same table size
        @test abs(parse(Int, a[1]) - parse(Int, b[1])) <= 100  # same number of entries
        @test parse(Int, a[1]) >= BenchMachine.SEED_ENTRIES
        # negative control: unseeded, the two sessions' tables differ
        probe0(pre) = split(readchomp(`$(jl()) -e "include($(repr(mj))); for i in 1:$pre; Core.apply_type(Tuple, Val{i}, Val{:other}); end; println(join(BenchMachine.type_cache_stats(), \" \"))"`))
        u, v = probe0(0), probe0(25_000)
        @test parse(Int, v[1]) - parse(Int, u[1]) >= 20_000
    end

    @testset "arguments" begin
        @test islegacy(["b", "c", "gg", "sequential", "4"])           # the frozen D-090 form
        @test islegacy(["b", "c", "gg", "checkerboard"])
        @test !islegacy(["b", "c", "gg", "metal"])                    # Metal goes to the paired form
        @test !islegacy(["b", "c", "gg", "sequential", "--rounds=4"])
        @test !islegacy(["b", "c", "gg", "cpu", "4"])
        o = withenv(() -> parse_ab(["b", "c", "all", "cpu"]), "POTTS_MACHINE" => "nucbox")
        @test o.variants == "sequential,checkerboard" && o.rounds == 6 && o.control == "" && o.seed == BenchMachine.SEED_ENTRIES
        @test o.bound == 0.01 && o.tolerance == 0.05 && o.warm && o.wait
        @test !parse_ab(["b", "c", "gg", "cpu", "--no-wait"]).wait
        @test o.stat == "paired" && parse_ab(["b", "c", "gg", "metal"]).stat == "fastest"
        @test parse_ab(["b", "c", "gg", "cpu", "--stat=fastest"]).stat == "fastest"
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cpu", "--stat=mean"])
        @test BenchMachine.gpu_users() isa Vector{Int}
        @test withenv(() -> BenchMachine.wait_idle(; gpu = true), "POTTS_BENCH_NOWAIT" => "1")
        @test o.pin == (Sys.islinux() && Sys.which("taskset") !== nothing)
        o = parse_ab(["b", "c", "gg", "sequential", "--no-control", "--no-seed", "--rounds=3"])
        @test o.backend == "cpu" && o.variants == "sequential" && o.control === nothing && o.seed == 0 && o.rounds == 3
        o = parse_ab(["b", "c", "gg", "rocm", "8", "--no-pin"])
        @test o.variants == "rocm" && o.rounds == 8 && !o.pin
        o = parse_ab(["--inprocess", "d", "v.jl", "cpu", "--alg=checkerboard"])
        @test o.inprocess && o.pos == ["d", "v.jl", "cpu"] && o.variants == "checkerboard"
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cuda"])
        @test_throws ErrorException parse_ab(["b", "c", "gg", "cpu", "--alg=metal"])
        @test_throws ErrorException parse_ab(["b", "c"])
    end

    @testset "rounds rotate, every side runs each round, verdicts" begin
        sb = sandbox()
        stub = joinpath(sb, "stub.jl"); write(stub, STUB)
        common = ["--no-warm", "--child=$stub", "--rounds=3", "--alg=sequential"]
        for (fb, fc, fk, code) in ((1.0, 1.0, 1.0, 0), (1.0, 1.10, 1.0, 1), (1.0, 1.0, 1.05, 2), (1.0, 1.02, 1.0, 0))
            root = mktempdir(; cleanup = true)
            log = joinpath(root, "log")
            b, c, k = fake(root, "base", fb), fake(root, "cand", fc), fake(root, "ctl", fk)
            st, out = run_ab(sb, [b, c, "gg,wa", "cpu", "--control=$k", common...]; log)
            @test st == code
            code != 0 || @test occursin("pass", out)
            ev = split.(readlines(log))
            @test length(ev) == 9                                         # 3 sides × 3 rounds
            @test first.(ev) == ["base", "cand", "ctl", "cand", "ctl", "base", "ctl", "base", "cand"]
            @test all(e -> "--seed=$(BenchMachine.SEED_ENTRIES)" in e && "threads=1" in e, ev)
            @test occursin("gg.sequential", out) && occursin("wa.sequential", out)
        end
        # without a control: two sides alternate, and nothing reads as unreliable
        root = mktempdir(; cleanup = true); log = joinpath(root, "log")
        b, c = fake(root, "base", 1.0), fake(root, "cand", 1.0)
        st, out = run_ab(sb, [b, c, "gg", "cpu", "--no-control", "--no-seed", common...]; log)
        @test st == 0
        ev = split.(readlines(log))
        @test first.(ev) == ["base", "cand", "cand", "base", "base", "cand"]
        @test all(e -> "--seed=0" in e, ev)
    end

    @testset "same-commit control checkout" begin
        Sys.which("git") === nothing && return @test_skip "git"
        root = mktempdir(; cleanup = true)
        base = joinpath(root, "base")
        mkpath(base)
        g(args...) = run(`git -C $base -c user.name=t -c user.email=t@t $args`)
        g("init", "-q"); write(joinpath(base, "a.txt"), "1"); g("add", "a.txt"); g("commit", "-qm", "one")
        write(joinpath(base, "Manifest.toml"), "# manifest")          # untracked, copied over
        ctl = control_checkout(base)
        @test ctl == base * "-abctl"
        @test git(ctl, "rev-parse", "HEAD") == git(base, "rev-parse", "HEAD")
        @test read(joinpath(ctl, "Manifest.toml"), String) == "# manifest"
        write(joinpath(base, "a.txt"), "2"); g("commit", "-qam", "two")
        @test control_checkout(base) == ctl                            # moved to the new commit
        @test git(ctl, "rev-parse", "HEAD") == git(base, "rev-parse", "HEAD")
        @test read(joinpath(ctl, "a.txt"), String) == "2"
        write(joinpath(base, "a.txt"), "dirty")
        @test_throws ErrorException control_checkout(base)             # a dirty base has no control
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
