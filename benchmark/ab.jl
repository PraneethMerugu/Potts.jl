# Paired A/B timing of gate cases (AUTONOMY §7.4, D-157, P6.0bb). Absolute baselines are
# informational; a slowdown is decided here, against a same-commit control.
#
#     julia benchmark/ab.jl <base> <candidate> <cases> <backend> [rounds] [options]
#     julia benchmark/ab.jl --inprocess <checkout> <variants.jl> <backend> [rounds] [options]
#
# <base>, <candidate>: checkouts (each with its workspace Manifest.toml). <cases>: gate case
# names (`benchmark/gate.jl`), comma-separated, or `all`. <backend>: `cpu` (sequential and
# checkerboard, Float64), `rocm` or `metal` (checkerboard on the device, Float32).
#
# By default (each can be turned off):
#  - Same-commit control. A third side times a second checkout of the base's commit
#    (`<base>-abctl`, a detached worktree created or moved to that commit; the base must be
#    clean). Two checkouts of one commit read up to 16 % apart unseeded on Metal (P6.2b), so
#    the control's ratio bounds what the A/B can resolve.
#  - Type cache seeding. Every timed process fills the global Tuple type cache to the same
#    number of entries before it builds anything (`machine.jl`, D-145).
#  - Interleaving. Each round runs every side once, each in a fresh process under the
#    machine lock (`tools/exclusive.sh`), and the order rotates from round to round, so each
#    side runs first equally often (rounds default to 6).
#  - Memory cap. On the NucBox every child runs under `systemd-run --user --scope -p
#    MemoryMax=8G` (`POTTS_BENCH_MEMMAX` to change, 0 for none): the machine is shared.
#  - Pinning. On a machine that pins (the NucBox, `machine.jl`), every timed process runs on
#    one reserved logical CPU (default 12) with its SMT sibling idle; precompilation runs on
#    the other CPUs (0-11,16-27). Each timed run first waits while a CI job runs on the
#    machine (for rocm also while another process holds the GPU); busy reserved CPUs are
#    warned about.
#
# When only the workload or the parameters change, run both in one process instead
# (`--inprocess`): <variants.jl> defines `AB_VARIANTS`, a vector of `label => T -> problem`
# (base first, candidate second), evaluated after `gate.jl` in the checkout's environment
# (see the P6.2b μ = 30 vs 24 A/B). The control is a second copy of the base in the same
# process.
#
# The timed harness (`ab_one.jl`, `gate.jl`) is this checkout's for every side, run in each
# side's environment (`--project=<side>/benchmark`), so an older base is timed with the
# same code. Its own `ab_one.jl` is not used.
#
# Verdict per case, on one of two statistics (`--stat`):
#  - `paired` (default for cpu and rocm): the median over rounds of the per-round ratio
#    (candidate/base, control/base). Sides run back to back within a round, so a slow drift
#    of the machine (load from other jobs, clocks) cancels. On the NucBox a ROCm run whose
#    timings drifted ~5 % over the hour read worst controls 1.024 (fastest) against 1.006
#    (paired), 2026-10-07.
#  - `fastest` (default for metal): each side's fastest run median over the rounds, i.e. the
#    same power state on a GPU that switches between them (Metal, D-145).
# Both are printed. Exit 1 when some candidate/base exceeds 1 + tolerance, else 2 when some
# |control/base − 1| exceeds the control bound (the A/B cannot be read at that resolution),
# else 0.
#
# Options:
#   --alg=<sequential|checkerboard,…>  CPU algorithms (default both)
#   --rounds=<n>        rounds (default 6; also the optional positional [rounds])
#   --stat=<paired|fastest>  the verdict statistic (default paired; fastest for metal)
#   --tolerance=<x>     regression tolerance (default 0.05)
#   --control-bound=<x> allowed |control/base − 1| (default per machine: 0.01 NucBox, else 0.03)
#   --control=<dir>     the same-commit checkout to use; --no-control: none
#   --seed=<n>          Tuple type cache entries to seed to (default 500000); --no-seed
#   --cpu=<n>           the logical CPU to pin to (default 12 on the NucBox); --no-pin
#   --samples=<n>, --seconds=<s>  BenchmarkTools samples and time budget per case (60, 40)
#   --no-warm           skip the untimed precompile run of each checkout
#   --no-wait           do not wait for a CI job (or, for rocm, another GPU client) to end
#                       before each timed run (machine.jl `wait_idle`); --wait=gpu waits
#                       only for other GPU clients
#
# The D-090 form `ab.jl <base> <candidate> <case> <sequential|checkerboard> [rounds]` (no
# options) is kept as it was for its frozen contract (benchmark/test/p6_0s_v7_tooling.jl): it
# runs each checkout's own `ab_one.jl`, base then candidate, with no control. It is pinned
# where the machine pins, and it prints a note pointing to the paired form.
using Printf
isdefined(Main, :BenchMachine) || include(joinpath(@__DIR__, "machine.jl"))

const LOCK = joinpath(@__DIR__, "..", "tools", "exclusive.sh")
const CHILD = joinpath(@__DIR__, "ab_one.jl")

# ------------------------------------------------------------------- the D-090 form
islegacy(args) = length(args) in (4, 5) && !any(startswith("--"), args) &&
    args[4] in ("sequential", "checkerboard") && (length(args) == 4 || all(isdigit, args[5]))

function legacy_main(args)
    base, cand, case, alg = args[1:4]
    rounds = length(args) >= 5 ? parse(Int, args[5]) : 4
    m = BenchMachine.machine()
    pin = BenchMachine.pins(m) ? BenchMachine.pin_cmd(m, BenchMachine.bench_cpu(m)) : ``
    mem = BenchMachine.mem_cmd(m)
    println("note: the D-090 form (no control, no seeding of an older checkout, fixed order); ",
        "prefer `ab.jl <base> <candidate> <case> cpu --alg=$alg`")
    function once(dir)
        out = read(Cmd(`$LOCK $mem $pin julia --project=benchmark $(joinpath(dir, "benchmark", "ab_one.jl")) $case $alg`; dir), String)
        return parse(Float64, last(split(only(filter(startswith("AB "), split(out, '\n'))))))
    end
    a, b = Float64[], Float64[]
    for r in 1:rounds
        push!(a, once(base)); push!(b, once(cand))
        @printf("round %d  base %.2f  candidate %.2f ns/site (median)\n", r, a[end], b[end])
    end
    ratio = minimum(b) / minimum(a)
    @printf("%s.%s  candidate/base = %.3f\n", case, alg, ratio)
    return ratio > 1.05 ? 1 : 0
end

# ------------------------------------------------------------------- arguments
function parse_ab(args)
    opts = Dict{String, String}()
    pos = String[]
    for a in args
        if startswith(a, "--")
            k, v = occursin('=', a) ? split(a[3:end], '='; limit = 2) : (a[3:end], "")
            opts[String(k)] = String(v)
        else
            push!(pos, a)
        end
    end
    inprocess = haskey(opts, "inprocess")
    n = inprocess ? 3 : 4
    length(pos) in (n, n + 1) || error(inprocess ?
        "usage: ab.jl --inprocess <checkout> <variants.jl> <backend> [rounds] [options]" :
        "usage: ab.jl <base> <candidate> <cases> <backend> [rounds] [options]")
    backend = pos[n]
    algs = get(opts, "alg", "sequential,checkerboard")
    if backend in ("sequential", "checkerboard")
        algs, backend = backend, "cpu"
    end
    backend in ("cpu", "metal", "rocm") || error("backend must be cpu, metal or rocm; got $(repr(backend))")
    get(opts, "stat", "paired") in ("paired", "fastest") || error("--stat is paired or fastest")
    for a in split(algs, ',')
        a in ("sequential", "checkerboard") || error("--alg takes sequential and/or checkerboard; got $(repr(a))")
    end
    variants = backend == "cpu" ? algs : backend
    rounds = parse(Int, get(opts, "rounds", length(pos) > n ? pos[n + 1] : "6"))
    m = BenchMachine.machine()
    seed = haskey(opts, "no-seed") ? 0 : parse(Int, get(opts, "seed", string(BenchMachine.SEED_ENTRIES)))
    pin = !haskey(opts, "no-pin") && BenchMachine.pins(m)
    cpu = pin ? (haskey(opts, "cpu") ? parse(Int, opts["cpu"]) : BenchMachine.bench_cpu(m)) : -1
    return (; inprocess, pos, backend, variants, rounds, machine = m, seed, pin, cpu,
        tolerance = parse(Float64, get(opts, "tolerance", "0.05")),
        bound = parse(Float64, get(opts, "control-bound", string(m.control_bound))),
        control = haskey(opts, "no-control") ? nothing : get(opts, "control", ""),
        samples = get(opts, "samples", "60"), seconds = get(opts, "seconds", "40"),
        stat = get(opts, "stat", backend == "metal" ? "fastest" : "paired"),
        warm = !haskey(opts, "no-warm"), wait = !haskey(opts, "no-wait"), gpuwait = get(opts, "wait", "") == "gpu", child = get(opts, "child", CHILD))
end

# ------------------------------------------------------------------- checkouts
git(dir, args...) = readchomp(`git -C $dir $args`)
isclean(dir) = isempty(git(dir, "status", "--porcelain", "--untracked-files=no"))

"""A second checkout of `base`'s commit, `<base>-abctl`, created or moved there as needed."""
function control_checkout(base)
    base = rstrip(normpath(abspath(base)), '/')
    sha = git(base, "rev-parse", "HEAD")
    isclean(base) || error("the base checkout $base has uncommitted changes: a same-commit control needs ",
        "a clean base (commit them, or pass --control=<dir> or --no-control)")
    ctl = base * "-abctl"
    if !isdir(ctl)
        run(`git -C $base worktree add --detach $ctl $sha`)
    elseif git(ctl, "rev-parse", "HEAD") != sha
        isclean(ctl) || error("control checkout $ctl has uncommitted changes")
        run(`git -C $ctl checkout --quiet --detach $sha`)
    end
    man = joinpath(base, "Manifest.toml")
    cm = joinpath(ctl, "Manifest.toml")
    isfile(man) && (!isfile(cm) || read(cm) != read(man)) && cp(man, cm; force = true)
    return ctl
end

"""The environment of a child run in checkout `dir`."""
function child_env(dir, o)
    e = Dict{String, String}("JULIA_NUM_THREADS" => "1", "POTTS_BENCH_PINNED" => o.pin ? "1" : "0")
    if o.backend in ("metal", "rocm")
        pkg = o.backend == "metal" ? "Metal" : "AMDGPU"
        bp = joinpath(dir, "benchmark", "Project.toml")
        tp = joinpath(dir, "test", "Project.toml")
        # an older checkout whose benchmark project lacks the device package: stack its test
        # project (same workspace, same Manifest), which has had both since P6.0bg
        if isfile(bp) && !occursin("\n$pkg = ", read(bp, String)) && isfile(tp) && occursin("\n$pkg = ", read(tp, String))
            e["JULIA_LOAD_PATH"] = join(["@", joinpath(dir, "test"), "@stdlib"], Sys.iswindows() ? ';' : ':')
        end
    end
    return merge(ENV, e)
end

julia_bin() = joinpath(Sys.BINDIR, Base.julia_exename())

function warm(dir, o)
    dev = o.backend == "metal" ? "; import Metal" : o.backend == "rocm" ? "; import AMDGPU" : ""
    code = "using BenchmarkTools, Potts, PottsModels, KernelAbstractions$dev"
    cmd = `$(BenchMachine.mem_cmd(o.machine)) $(BenchMachine.work_cmd(o.machine)) $(julia_bin()) --startup-file=no --project=$(joinpath(dir, "benchmark")) -e $code`
    println("precompiling $dir ...")
    run(setenv(cmd, child_env(dir, o); dir))
end

# ------------------------------------------------------------------- runs
"""Run one timed child; returns (label => [(median, minimum)], TC lines)."""
function child(dir, childargs, o)
    o.wait && BenchMachine.wait_idle(; gpu = o.backend == "rocm", ci = !o.gpuwait)
    o.pin && (q = BenchMachine.check_quiet(o.cpu; reserved = o.machine.bench); isempty(q) || println("   [", q, "]"))
    flush(stdout)
    pin = o.pin ? BenchMachine.pin_cmd(o.machine, o.cpu) : ``
    cmd = `$LOCK $(BenchMachine.mem_cmd(o.machine)) $pin $(julia_bin()) --startup-file=no --project=$(joinpath(dir, "benchmark")) $(o.child) $childargs --seed=$(o.seed) --samples=$(o.samples) --seconds=$(o.seconds)`
    buf = IOBuffer()
    p = run(pipeline(ignorestatus(setenv(cmd, child_env(dir, o); dir)); stdout = buf, stderr = buf))
    out = String(take!(buf))
    success(p) || (print(out); error("timed run in $dir failed (exit $(p.exitcode))"))
    res = Pair{String, Tuple{Float64, Float64}}[]
    tcs = String[]
    for l in split(out, '\n')
        f = split(l)
        isempty(f) && continue
        f[1] == "ABR" && push!(res, String(f[2]) => (parse(Float64, f[3]), parse(Float64, f[4])))
        f[1] == "TC" && push!(tcs, join(f[2:end], "/"))
        f[1] == "ABSKIP" && println("   skipped in $dir: $(f[2])")
    end
    return res, tcs
end

"""side => key => [(median, minimum) per round]"""
const Results = Dict{String, Dict{String, Vector{Tuple{Float64, Float64}}}}

record!(R, side, res) = for (k, v) in res
    push!(get!(get!(R, side, Dict{String, Vector{Tuple{Float64, Float64}}}()), k, Tuple{Float64, Float64}[]), v)
end

function rounds_checkouts!(R, sides, cases, o)
    for r in 1:o.rounds
        order = circshift(sides, -(r - 1))
        println("round $r: ", join(first.(order), ", "))
        flush(stdout)
        for (side, dir) in order
            res, tcs = child(dir, [cases, o.variants], o)
            record!(R, side, res)
            println(@sprintf("   %-9s Tuple cache %s  ", side, join(tcs, " → ")),
                join([@sprintf("%s %.2f", k, v[1]) for (k, v) in res], "  "))
            flush(stdout)
        end
    end
end

function rounds_inprocess!(R, dir, file, o)
    println("in-process A/B in $dir: ", file)
    res, tcs = child(dir, ["--variants=$(abspath(file))", o.variants, "--rounds=$(o.rounds)"], o)
    for (lk, v) in res
        side, key = split(lk, ':'; limit = 2)
        record!(R, String(side), [String(key) => v])
    end
    println("   Tuple cache ", join(tcs, " → "))
end

# ------------------------------------------------------------------- verdict
mid(x) = (s = sort(x); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)
fastest(v) = minimum(first, v)
paired(a, b) = mid([y[1] / x[1] for (x, y) in zip(a, b)])

function verdict(R, o)
    b, c = R["base"], R["candidate"]
    ctl = get(R, "control", nothing)
    keys_ = sort([k for k in keys(b) if haskey(c, k) && (ctl === nothing || haskey(ctl, k))])
    worst = 0
    stat(x, y) = o.stat == "paired" ? paired(x, y) : fastest(y) / fastest(x)
    @printf("\n%-34s %9s %9s %9s | %8s %8s | %8s %8s\n", "case (ns/site, fastest median)", "base", "candidate",
        "control", "paired", "ctl pair", "fastest", "ctl fast")
    for k in keys_
        rc = stat(b[k], c[k])
        rk = ctl === nothing ? NaN : stat(b[k], ctl[k])
        slow = rc > 1 + o.tolerance
        wide = !isnan(rk) && abs(rk - 1) > o.bound
        slow && (worst = 1)
        wide && worst == 0 && (worst = 2)
        f(x) = ctl === nothing ? "–" : @sprintf("%.4f", x)
        @printf("%-34s %9.2f %9.2f %9s | %8.4f %8s | %8.4f %8s%s\n", k, fastest(b[k]), fastest(c[k]),
            ctl === nothing ? "–" : @sprintf("%.2f", fastest(ctl[k])),
            paired(b[k], c[k]), f(ctl === nothing ? NaN : paired(b[k], ctl[k])),
            fastest(c[k]) / fastest(b[k]), f(ctl === nothing ? NaN : fastest(ctl[k]) / fastest(b[k])),
            slow ? "  SLOWER" : wide ? "  CONTROL WIDE" : "")
    end
    @printf("verdict on the %s statistic; tolerance %.3f, control bound ±%.3f; %s\n", o.stat, o.tolerance, o.bound,
        worst == 1 ? "REGRESSION" : worst == 2 ? "control outside its bound: the A/B cannot be read at this resolution" : "pass")
    return worst
end

function ab_main(args)
    islegacy(args) && return legacy_main(args)
    o = parse_ab(args)
    m = o.machine
    @printf("machine %s (%s); backend %s (%s); %s; Tuple cache seeded to %s; %d rounds\n", m.key,
        BenchMachine.cpu_model(), o.backend, o.variants,
        o.pin ? "pinned to logical CPU $(o.cpu), siblings $(BenchMachine.siblings(o.cpu)) idle" : "not pinned",
        o.seed > 0 ? string(o.seed) : "– (off)", o.rounds)
    BenchMachine.ci_job_running() && @warn "a CI job is running on this machine; timings may be disturbed (D-157)"
    R = Results()
    if o.inprocess
        dir, file = o.pos[1], o.pos[2]
        o.warm && warm(dir, o)
        rounds_inprocess!(R, dir, file, o)
        o.control === nothing && delete!(R, "control")
    else
        base, cand, cases = o.pos[1], o.pos[2], o.pos[3]
        sides = ["base" => base, "candidate" => cand]
        if o.control !== nothing
            ctl = isempty(o.control) ? control_checkout(base) : o.control
            println("same-commit control: $ctl")
            push!(sides, "control" => ctl)
        end
        o.warm && foreach(d -> warm(d, o), unique(last.(sides)))
        rounds_checkouts!(R, sides, cases, o)
    end
    return verdict(R, o)
end

abspath(PROGRAM_FILE) == (@__FILE__) && exit(ab_main(ARGS))
