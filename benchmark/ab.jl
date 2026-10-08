# Paired A/B timing of gate cases (AUTONOMY §7.4, D-157, P6.0bb). Absolute baselines are
# informational; a slowdown is decided here, against two same-commit controls.
#
#     julia benchmark/ab.jl <base> <candidate> <cases> <backend> [rounds] [options]
#     julia benchmark/ab.jl --inprocess <checkout> <variants.jl> <backend> [rounds] [options]
#
# <base>, <candidate>: checkouts (each with its workspace Manifest.toml). <cases>: gate case
# names (`benchmark/gate.jl`), comma-separated, or `all`. <backend>: `cpu` (sequential and
# checkerboard, Float64), `rocm` or `metal` (checkerboard on the device, Float32).
#
# By default (each can be turned off):
#  - Two same-commit controls. Besides the base and the candidate, every round times
#    `<base>-abctl` and `<candidate>-abctl`: detached worktrees of the base's and the
#    candidate's commits (created or moved there; both checkouts must be clean). Two
#    checkouts of one commit read up to 16 % apart unseeded on Metal (P6.2b), so the
#    controls show what the A/B can resolve.
#  - Type cache seeding. Every timed process fills the global Tuple type cache to the same
#    number of entries before it builds anything (`machine.jl`, D-145).
#  - Interleaving. Each round runs every side once, each in a fresh process under the
#    machine lock (`tools/exclusive.sh`), and the order rotates from round to round, so each
#    side runs first equally often (8 rounds for the 4 sides).
#  - Identical environments. Every side runs `--project=<side>/benchmark` with its own test
#    project stacked on JULIA_LOAD_PATH (where the device packages come from), so no side
#    differs from another in what its environment provides.
#  - Waiting. Each timed process, once it holds the lock and before it loads anything,
#    waits while a CI job runs on the machine (for rocm also while another process holds
#    the GPU), until one overall deadline (`--max-wait`, 4 h from the start). It then reports
#    what disturbed it at its start or end (a CI job, another GPU client, a busy SMT sibling
#    or another busy reserved CPU); disturbed runs are counted in the verdict.
#  - Memory cap. On the NucBox every child runs under `systemd-run --user --scope -p
#    MemoryMax=8G` (`POTTS_BENCH_MEMMAX` to change, 0 for none): the machine is shared.
#  - Pinning. On a machine that pins (the NucBox, `machine.jl`), every timed process runs on
#    one reserved logical CPU (default 12) with its SMT sibling idle; precompilation runs on
#    the other CPUs (0-11,16-27).
#
# When only the workload or the parameters change, run both in one process instead
# (`--inprocess`): <variants.jl> defines `AB_VARIANTS`, a vector of `label => T -> problem`
# (base first, candidate second), evaluated after `gate.jl` in the checkout's environment
# (example: `ab_variants_akeeb_mu.jl`). The controls are second copies of the base and of
# the candidate in the same process.
#
# The timed harness (`ab_one.jl`, `gate.jl`) is this checkout's for every side (its path and
# commit are printed), run in each side's environment, so an older base is timed with the
# same code. A side's own `ab_one.jl` is not used.
#
# Statistics, per case. Ratios: candidate/base, base-ctl/base and cand-ctl/candidate.
#  - `paired` (default for cpu and rocm): the median over rounds of the per-round ratio.
#    Sides run back to back within a round, so a slow drift of the machine cancels.
#  - `fastest` (default for metal): the ratio of the sides' fastest run medians, i.e. the
#    same power state on a GPU that switches between them (Metal, D-145).
#  - Interval: a 95 % bootstrap interval (rounds resampled with replacement, a fixed seed)
#    of the median paired ratio, for the candidate and for both controls.
# Verdict: exit 1 when some candidate/base exceeds 1 + tolerance (on `--stat`); else 3 when
# some timed run was disturbed (the counts are printed; time again with the machine idle);
# else 2 when some control's interval excludes 1 (two checkouts of one commit differ: the
# A/B cannot be read); else 0. The printed resolution is the largest control deviation from
# 1 and the largest control interval half-width.
#
# Options:
#   --alg=<sequential|checkerboard,…>  CPU algorithms (default both)
#   --rounds=<n>        rounds (default 8; also the optional positional [rounds])
#   --stat=<paired|fastest>  the verdict statistic (default paired; fastest for metal)
#   --tolerance=<x>     regression tolerance (default 0.05)
#   --no-control        no controls (and an in-process run builds none)
#   --seed=<n>          Tuple type cache entries to seed to (default 500000); --no-seed
#   --cpu=<n>           the logical CPU to pin to (default 12 on the NucBox); --no-pin
#   --samples=<n>, --seconds=<s>  BenchmarkTools samples and time budget per case (60, 40)
#   --wait=<all|gpu|none>  what each timed run waits for (default all: CI jobs and, for
#                       rocm, other GPU clients; gpu: other GPU clients only)
#   --max-wait=<hours>  the overall deadline for waiting (default 4)
#   --no-warm           skip the untimed precompile run of each checkout
#
# The D-090 form `ab.jl <base> <candidate> <case> <sequential|checkerboard> [rounds]` (no
# options) is kept for its frozen contract (benchmark/test/p6_0s_v7_tooling.jl, L2): each
# checkout's own `ab_one.jl` (unseeded), base then candidate, no control, the fastest run
# median per side. Only that form is kept: the three-argument form (which used to mean
# `metal`) is an error, and `<case> metal [rounds]` now runs the paired form.
using Printf
isdefined(Main, :BenchMachine) || include(joinpath(@__DIR__, "machine.jl"))

const LOCK = joinpath(@__DIR__, "..", "tools", "exclusive.sh")
const CHILD = joinpath(@__DIR__, "ab_one.jl")

# ------------------------------------------------------------------- the D-090 form
function islegacy(args)
    return length(args) in (4, 5) && !any(startswith("--"), args) &&
           args[4] in ("sequential", "checkerboard") &&
           (length(args) == 4 || all(isdigit, args[5]))
end

function legacy_main(args)
    base, cand, case, alg = args[1:4]
    rounds = length(args) >= 5 ? parse(Int, args[5]) : 4
    m = BenchMachine.machine()
    pin = BenchMachine.pins(m) ? BenchMachine.pin_cmd(m, BenchMachine.bench_cpu(m)) : ``
    mem = BenchMachine.mem_cmd(m)
    println("note: the D-090 form (no control, no seeding, fixed order); ",
        "prefer `ab.jl <base> <candidate> <case> cpu --alg=$alg`")
    function once(dir)
        ab_one = joinpath(dir, "benchmark", "ab_one.jl")
        out = read(Cmd(`$LOCK $mem $pin julia --project=benchmark $ab_one $case $alg`; dir), String)
        return parse(Float64, last(split(only(filter(startswith("AB "), split(out, '\n'))))))
    end
    a, b = Float64[], Float64[]
    for r in 1:rounds
        push!(a, once(base))
        push!(b, once(cand))
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
    length(pos) in (n, n + 1) ||
        error(inprocess ?
              "usage: ab.jl --inprocess <checkout> <variants.jl> <backend> [rounds] [options]" :
              "usage: ab.jl <base> <candidate> <cases> <backend> [rounds] [options] " *
              "(the backend is required: cpu, rocm or metal)")
    backend = pos[n]
    algs = get(opts, "alg", "sequential,checkerboard")
    if backend in ("sequential", "checkerboard")
        algs, backend = backend, "cpu"
    end
    backend in ("cpu", "metal", "rocm") ||
        error("backend must be cpu, metal or rocm; got $(repr(backend))")
    stat = get(opts, "stat", backend == "metal" ? "fastest" : "paired")
    stat in ("paired", "fastest") || error("--stat is paired or fastest")
    for a in split(algs, ',')
        a in ("sequential", "checkerboard") ||
            error("--alg takes sequential and/or checkerboard; got $(repr(a))")
    end
    wait = get(opts, "wait", "all")
    wait in ("all", "gpu", "none") || error("--wait is all, gpu or none")
    m = BenchMachine.machine()
    seed = haskey(opts, "no-seed") ? 0 :
           parse(Int, get(opts, "seed", string(BenchMachine.SEED_ENTRIES)))
    pin = !haskey(opts, "no-pin") && BenchMachine.pins(m)
    cpu = pin ?
          (haskey(opts, "cpu") ? parse(Int, opts["cpu"]) : BenchMachine.bench_cpu(m)) : -1
    return (; inprocess, pos, backend, variants = backend == "cpu" ? algs : backend,
        rounds = parse(Int, get(opts, "rounds", length(pos) > n ? pos[n + 1] : "8")),
        machine = m, seed, pin, cpu, stat, wait,
        tolerance = parse(Float64, get(opts, "tolerance", "0.05")),
        control = !haskey(opts, "no-control"),
        maxwait = 3600 * parse(Float64, get(opts, "max-wait", "4")),
        samples = get(opts, "samples", "60"), seconds = get(opts, "seconds", "40"),
        warm = !haskey(opts, "no-warm"), child = get(opts, "child", CHILD))
end

# ------------------------------------------------------------------- checkouts
git(dir, args...) = readchomp(`git -C $dir $args`)
isclean(dir) = isempty(git(dir, "status", "--porcelain", "--untracked-files=no"))
common_dir(dir) = git(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")

"""
`commit[+dirty]` of a checkout, or `?` outside git.
"""
function describe(dir)
    try
        return git(dir, "rev-parse", "--short=10", "HEAD") * (isclean(dir) ? "" : "+dirty")
    catch
        return "?"
    end
end

"""
A second checkout of `dir`'s commit, `<dir>-abctl`. A missing one is added as a detached
worktree of `dir`'s repository (the one write into that repository's `.git`, announced
first); an existing one must be a clean worktree of the same repository, and is moved to the
commit. Both checkouts must be clean, and the control ends at exactly `dir`'s commit.
"""
function control_checkout(dir)
    dir = rstrip(normpath(abspath(dir)), '/')
    sha = git(dir, "rev-parse", "HEAD")
    isclean(dir) ||
        error("the checkout $dir has uncommitted changes: a same-commit control needs a ",
            "clean checkout (commit them, or pass --no-control)")
    ctl = dir * "-abctl"
    gitdir = common_dir(dir)
    if !isdir(ctl)
        println(
            "creating control $ctl: `git worktree add --detach` writes a worktree entry ",
            "into $gitdir")
        run(`git -C $dir worktree add --quiet --detach $ctl $sha`)
    else
        isdir(joinpath(ctl, ".git")) || isfile(joinpath(ctl, ".git")) ||
            error("$ctl exists but is not a git checkout")
        common_dir(ctl) == gitdir ||
            error("$ctl is a checkout of another repository ($(common_dir(ctl)))")
        isclean(ctl) || error("control checkout $ctl has uncommitted changes")
        git(ctl, "rev-parse", "HEAD") == sha ||
            run(`git -C $ctl checkout --quiet --detach $sha`)
    end
    git(ctl, "rev-parse", "HEAD") == sha && isclean(ctl) ||
        error("control checkout $ctl is not a clean checkout of $sha")
    man = joinpath(dir, "Manifest.toml")
    cm = joinpath(ctl, "Manifest.toml")
    isfile(man) && (!isfile(cm) || read(cm) != read(man)) && cp(man, cm; force = true)
    return ctl
end

"""
The environment of a child run in checkout `dir`: the same shape for every side.
"""
function child_env(dir, o)
    sep = Sys.iswindows() ? ';' : ':'
    return merge(ENV,
        Dict{String, String}("JULIA_NUM_THREADS" => "1",
            "POTTS_BENCH_PINNED" => o.pin ? "1" : "0",
            "JULIA_LOAD_PATH" => join(["@", joinpath(dir, "test"), "@stdlib"], sep)))
end

julia_bin() = joinpath(Sys.BINDIR, Base.julia_exename())

function warm(dir, o)
    dev = o.backend == "metal" ? "; import Metal" :
          o.backend == "rocm" ? "; import AMDGPU" : ""
    code = "using BenchmarkTools, Potts, PottsModels, KernelAbstractions$dev"
    proj = joinpath(dir, "benchmark")
    cmd = `$(BenchMachine.mem_cmd(o.machine)) $(BenchMachine.work_cmd(o.machine)) $(julia_bin()) --startup-file=no --project=$proj -e $code`
    println("precompiling $dir ...")
    flush(stdout)
    return run(setenv(cmd, child_env(dir, o); dir))
end

# ------------------------------------------------------------------- runs
"""
Run one timed child under the machine lock. Returns `(results, skips, disturbances, tc)`:
`label => (median, minimum)` pairs, the skipped labels, the reasons the run was disturbed,
and the child's Tuple-cache lines.
"""
function child(dir, childargs, o, deadline)
    pin = o.pin ? BenchMachine.pin_cmd(o.machine, o.cpu) : ``
    mem = BenchMachine.mem_cmd(o.machine)
    proj = joinpath(dir, "benchmark")
    cmd = `$LOCK $mem $pin $(julia_bin()) --startup-file=no --project=$proj $(o.child) $childargs --seed=$(o.seed) --samples=$(o.samples) --seconds=$(o.seconds) --wait=$(o.wait) --deadline=$deadline`
    buf = IOBuffer()
    p = run(pipeline(ignorestatus(setenv(cmd, child_env(dir, o); dir)); stdout = buf, stderr = buf))
    out = String(take!(buf))
    success(p) || (print(out); error("timed run in $dir failed (exit $(p.exitcode))"))
    res = Pair{String, Tuple{Float64, Float64}}[]
    skips, dist, tcs = String[], String[], String[]
    for l in split(out, '\n')
        f = split(l)
        isempty(f) && continue
        f[1] == "ABR" &&
            push!(res, String(f[2]) => (parse(Float64, f[3]), parse(Float64, f[4])))
        f[1] == "TC" && push!(tcs, join(f[2:end], "/"))
        f[1] == "ABSKIP" && push!(skips, String(f[2]))
        f[1] == "DISTURBED" && push!(dist, join(f[2:end], " "))
        f[1] == "WAIT" && (println("   waited: ", join(f[2:end], " ")); flush(stdout))
    end
    return res, skips, dist, tcs
end

"""
side => key => [(median, minimum) per round]
"""
const Results = Dict{String, Dict{String, Vector{Tuple{Float64, Float64}}}}

function record!(R, side, res)
    for (k, v) in res
        d = get!(R, side, Dict{String, Vector{Tuple{Float64, Float64}}}())
        push!(get!(d, k, Tuple{Float64, Float64}[]), v)
    end
    return R
end

# the sides that may skip a case `all` names: the base and its control (an older checkout)
const MAY_SKIP = ("base", "base-ctl")

function rounds_checkouts!(R, D, sides, cases, o, deadline)
    skipped = Set{String}()
    for r in 1:(o.rounds)
        order = circshift(sides, -(r - 1))
        println("round $r: ", join(first.(order), ", "))
        flush(stdout)
        for (side, dir) in order
            res, skips, dist, tcs = child(dir, [cases, o.variants], o, deadline)
            isempty(skips) || side in MAY_SKIP ||
                error("the $side ($dir) skipped $(join(skips, ", ")): only the base and ",
                    "its control may lack a case")
            union!(skipped, skips)
            record!(R, side, res)
            isempty(dist) || push!(D, "round $r $side: " * join(dist, "; "))
            println(@sprintf("   %-9s Tuple cache %s  ", side, join(tcs, " → ")),
                join([@sprintf("%s %.2f", k, v[1]) for (k, v) in res], "  "),
                isempty(dist) ? "" : "  DISTURBED: " * join(dist, "; "))
            flush(stdout)
        end
    end
    isempty(skipped) ||
        println("skipped (not in the base): ", join(sort(collect(skipped)), ", "))
    return R
end

function rounds_inprocess!(R, D, dir, file, o, deadline)
    println("in-process A/B in $dir: ", file)
    args = ["--variants=$(abspath(file))", o.variants, "--rounds=$(o.rounds)"]
    o.control || push!(args, "--no-control")
    res, skips, dist, tcs = child(dir, args, o, deadline)
    for (lk, v) in res
        side, key = split(lk, ':'; limit = 2)
        record!(R, String(side), [String(key) => v])
    end
    isempty(dist) || push!(D, "in-process run: " * join(dist, "; "))
    println("   Tuple cache ", join(tcs, " → "), isempty(dist) ? "" :
                                                 "  DISTURBED: " * join(dist, "; "))
    return R
end

# ------------------------------------------------------------------- verdict
function mid(x)
    (s = sort(x); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)
end
fastest(v) = minimum(first, v)
ratios(a, b) = [y[1] / x[1] for (x, y) in zip(a, b)]
paired(a, b) = mid(ratios(a, b))

"""
95 % percentile bootstrap interval of the median of `r` (resampled with replacement, `B`
times, from a fixed-seed generator, so the same data give the same interval).
"""
function boot_interval(r; B = 4000, level = 0.95)
    n = length(r)
    n == 0 && return (NaN, NaN)
    state = UInt64(0x9e3779b97f4a7c15)
    meds = Vector{Float64}(undef, B)
    x = similar(r)
    for b in 1:B
        for i in 1:n
            state = state * 0x5851f42d4c957f2d + 0x14057b7ef767814f   # 64-bit LCG
            x[i] = r[Int((state >> 33) % n) + 1]
        end
        meds[b] = mid(x)
    end
    sort!(meds)
    lo = meds[max(1, floor(Int, (1 - level) / 2 * B))]
    hi = meds[min(B, ceil(Int, (1 + level) / 2 * B))]
    return (lo, hi)
end

function verdict(R, D, o)
    none = Dict{String, Vector{Tuple{Float64, Float64}}}()
    b, c = get(R, "base", none), get(R, "candidate", none)
    ctls = o.control ? [("base-ctl", "base"), ("cand-ctl", "candidate")] :
           Tuple{String, String}[]
    keys_ = sort([k
                  for k in keys(b)
                  if haskey(c, k) && all(haskey(get(R, s, none), k) for (s, _) in ctls)])
    isempty(keys_) && error("no case was timed on every side")
    point(x, y) = o.stat == "paired" ? paired(x, y) : fastest(y) / fastest(x)
    iv(x, y) = boot_interval(ratios(x, y))
    fmt(t) = @sprintf("[%.4f, %.4f]", t...)
    slow, wide = String[], String[]
    dev, half = 0.0, 0.0
    @printf("\n%-34s %9s %9s | %-26s",
        "case (ns/site, fastest median)", "base", "candidate",
        "candidate/base ($(o.stat)) 95%")
    for (s, ref) in ctls
        @printf(" | %-26s", "$s/$ref ($(o.stat)) 95%")
    end
    println()
    for k in keys_
        rc = point(b[k], c[k])
        rc > 1 + o.tolerance && push!(slow, k)
        @printf("%-34s %9.2f %9.2f | %.4f %s", k, fastest(b[k]), fastest(c[k]), rc,
            fmt(iv(b[k], c[k])))
        flags = rc > 1 + o.tolerance ? ["SLOWER"] : String[]
        for (s, ref) in ctls
            x, y = R[ref][k], R[s][k]
            rk, (lo, hi) = point(x, y), iv(x, y)
            dev = max(dev, abs(rk - 1))
            half = max(half, (hi - lo) / 2)
            lo <= 1 <= hi || (push!(wide, "$k ($s)"); push!(flags, "$s EXCLUDES 1"))
            @printf(" | %.4f %s", rk, fmt((lo, hi)))
        end
        println(isempty(flags) ? "" : "  " * join(flags, ", "))
    end
    nd = length(D)
    o.control &&
        @printf("resolution: largest control deviation %.4f, largest control interval half-width %.4f\n",
            dev, half)
    nd == 0 || println("disturbed runs ($nd):\n  ", join(D, "\n  "))
    code = !isempty(slow) ? 1 : nd > 0 ? 3 : !isempty(wide) ? 2 : 0
    @printf("verdict (%s, tolerance %.3f): %s\n", o.stat,
        o.tolerance,
        code == 1 ? "REGRESSION: " * join(slow, ", ") :
        code == 3 ? "$nd disturbed run(s): time again with the machine idle" :
        code == 2 ?
        "a control interval excludes 1 ($(join(wide, ", "))): the A/B cannot be read" :
        "pass")
    return code
end

function ab_main(args)
    islegacy(args) && return legacy_main(args)
    o = parse_ab(args)
    m = o.machine
    harness = dirname(@__DIR__)
    deadline = time() + o.maxwait
    @printf("machine %s (%s); backend %s (%s); %s; Tuple cache seeded to %s; %d rounds; wait %s\n",
        m.key, BenchMachine.cpu_model(), o.backend, o.variants,
        o.pin ?
        "pinned to logical CPU $(o.cpu), siblings $(BenchMachine.siblings(o.cpu)) idle" :
        "not pinned", o.seed > 0 ? string(o.seed) : "– (off)", o.rounds, o.wait)
    println("harness: $(o.child) (checkout $harness at $(describe(harness)))")
    R, D = Results(), String[]
    if o.inprocess
        dir, file = o.pos[1], o.pos[2]
        println("checkout: $dir at $(describe(dir))")
        o.warm && warm(dir, o)
        rounds_inprocess!(R, D, dir, file, o, deadline)
    else
        base, cand, cases = o.pos[1], o.pos[2], o.pos[3]
        sides = ["base" => base, "candidate" => cand]
        o.control && append!(sides, ["base-ctl" => control_checkout(base),
            "cand-ctl" => control_checkout(cand)])
        for (s, d) in sides
            println(@sprintf("%-9s %s at %s", s, d, describe(d)))
        end
        o.warm && foreach(d -> warm(d, o), unique(last.(sides)))
        rounds_checkouts!(R, D, sides, cases, o, deadline)
    end
    return verdict(R, D, o)
end

abspath(PROGRAM_FILE) == (@__FILE__) && exit(ab_main(ARGS))
