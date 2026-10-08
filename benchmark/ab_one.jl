# Child of benchmark/ab.jl: warm-MCS times of gate cases in the active project's checkout.
#
#     julia --project=benchmark benchmark/ab_one.jl <case> <alg>
#     julia --project=<checkout>/benchmark benchmark/ab_one.jl <cases> <variants> [options]
#     julia --project=<checkout>/benchmark benchmark/ab_one.jl --variants=<file.jl> <variant> [options]
#
# <cases>: gate case names, comma-separated, or `all`. <variants>: `sequential`,
# `checkerboard` (CPU, Float64), `metal` or `rocm` (checkerboard on that device, Float32),
# comma-separated; at most one device. Timed like the gate: on a device, `step!` followed by
# the device wait `device_sync` (D-090).
#
# The two-argument form is the D-090 contract (benchmark/test/p6_0s_v7_tooling.jl): no
# seeding, no waiting, one line `AB <median ns/site>`. Otherwise the process
#  1. waits, before loading any package, until the machine is idle (`--wait`, up to
#     `--deadline`; it runs under `ab.jl`'s machine lock, so no other timed run starts
#     meanwhile), printing `WAIT <reason>` while it waits;
#  2. loads the packages and seeds the Tuple type cache (`TC <entries> <capacity>`);
#  3. prints, per measurement, `ABR <label> <median ns/site> <minimum ns/site> <samples>`,
#     or `ABSKIP <label>` for a case `all` names but this checkout does not have;
#  4. prints `DISTURBED <reason>` for whatever disturbed the run at its start or its end
#     (`machine.jl` `disturbances`: a CI job, another GPU client, a busy SMT sibling or
#     another busy reserved CPU), and `TC` again.
#
# Options:
#   --seed=<n>       seed the Tuple type cache to n entries (default BenchMachine.SEED_ENTRIES;
#                    0 = no seeding). Seeding runs after the packages load, before any build.
#   --samples=<n>    samples per measurement (default 60), --seconds=<s> (default 40)
#   --wait=<all|gpu|none>  what to wait for: CI jobs and (rocm) other GPU clients (`all`,
#                    default), other GPU clients only, or nothing
#   --deadline=<t>   stop waiting at `time()` = t (default: 4 h from now) and time anyway
#   --variants=<f>   in-process A/B: `f` defines `AB_VARIANTS`, a vector of
#                    `label => T -> PottsProblem` (base first, candidate second; `T` is the
#                    float type). Measured `--rounds` times (default 8) in rotating order with
#                    two controls, separately built copies of the base and of the candidate
#                    (labels `base`, `candidate`, `base-ctl`, `cand-ctl`; `--no-control`:
#                    only the first two). Labels print as `<label>:<variant>`.
isdefined(Main, :BenchMachine) || include(joinpath(@__DIR__, "machine.jl"))

function ab_one_opts(args)
    opts = Dict{String, String}()
    pos = String[]
    for a in args
        if startswith(a, "--")
            k, v = occursin('=', a) ? split(a[3:end], '='; limit = 2) : (a[3:end], "")
            opts[k] = v
        else
            push!(pos, a)
        end
    end
    return pos, opts
end

const AB_POS, AB_OPTS = ab_one_opts(ARGS)
const AB_LEGACY = length(ARGS) == 2 && isempty(AB_OPTS)
const AB_GPU = any(v -> v in ("rocm", "metal"), split(join(AB_POS, ","), ','))
const AB_WAIT = get(AB_OPTS, "wait", "all")
AB_WAIT in ("all", "gpu", "none") || error("--wait is all, gpu or none")

"""
What disturbs this run now (empty off a pinning machine and in the D-090 form).
"""
function ab_disturbances()
    (AB_LEGACY || AB_WAIT == "none") && return String[]
    m = BenchMachine.machine()
    BenchMachine.pins(m) ||
        return BenchMachine.busy_reasons(; gpu = AB_GPU, ci = AB_WAIT == "all")
    c = something(BenchMachine.allowed_cpus(), Int[])
    return BenchMachine.disturbances(length(c) == 1 ? only(c) : -1, m.bench;
        gpu = AB_GPU, ci = AB_WAIT == "all")
end

# 1. wait (before loading anything heavy, so a waiting child holds no GPU context)
if !AB_LEGACY && AB_WAIT != "none"
    deadline = parse(Float64, get(AB_OPTS, "deadline", string(time() + 4 * 3600)))
    BenchMachine.wait_idle(; gpu = AB_GPU, ci = AB_WAIT == "all", deadline) ||
        println("DISTURBED waited until the deadline; timed while busy")
end
const AB_START_DISTURBANCES = ab_disturbances()

include(joinpath(@__DIR__, "gate.jl"))
using Statistics: median

const AB_ALGS = Dict("sequential" => (SequentialCPM(), false),
    "checkerboard" => (CheckerboardCPM(), false),
    "metal" => (CheckerboardCPM(), true), "rocm" => (CheckerboardCPM(), true))

function ab_variant(v)
    haskey(AB_ALGS, v) ||
        error("unknown variant $(repr(v)); one of $(join(sort(collect(keys(AB_ALGS))), ", "))")
    alg, dev = AB_ALGS[v]
    dev && v != DEVICE && error("variant $v needs the $v backend loaded")
    return alg, dev ? device_backend() : nothing, dev ? Float32 : Float64
end

function ab_time(prob, alg, backend; samples, seconds)
    fresh_integrator(prob, alg, backend)
    b = run(@benchmarkable timed_step!(i, $backend) setup=(i=fresh_integrator($prob, $alg, $backend)) evals=1 samples=samples seconds=seconds)
    n = length(prob.u0.σ)
    return median(b).time / n, minimum(b).time / n, length(b.times)
end

function ab_one_main(pos, opts)
    seed = AB_LEGACY ? 0 : parse(Int, get(opts, "seed", string(BenchMachine.SEED_ENTRIES)))
    seed > 0 && BenchMachine.seed_type_cache!(seed)
    AB_LEGACY || println("TC ", join(BenchMachine.type_cache_stats(), " "))
    samples = parse(Int, get(opts, "samples", "60"))
    seconds = parse(Float64, get(opts, "seconds", "40"))
    if haskey(opts, "variants")
        Base.include(Main, opts["variants"])
        vs = Main.AB_VARIANTS
        length(vs) >= 2 || error("AB_VARIANTS needs a base and a candidate")
        rounds = parse(Int, get(opts, "rounds", "8"))
        for v in split(only(pos), ',')
            alg, backend, T = ab_variant(v)
            sides = ["base" => vs[1][2](T), "candidate" => vs[2][2](T)]
            haskey(opts, "no-control") ||
                append!(sides, ["base-ctl" => vs[1][2](T), "cand-ctl" => vs[2][2](T)])
            for r in 1:rounds, (label, prob) in circshift(sides, -(r - 1))

                med, mn, k = ab_time(prob, alg, backend; samples, seconds)
                println("ABR $label:$v $med $mn $k")
                flush(stdout)
            end
        end
    else
        length(pos) == 2 || error("usage: ab_one.jl <cases> <variants> [options]")
        allcases = first.(cases(Float64))
        names = pos[1] == "all" ? allcases : split(pos[1], ',')
        for v in split(pos[2], ',')
            alg, backend, T = ab_variant(v)
            mk = Dict(cases(T))
            for name in names
                haskey(mk, name) ||
                    error("unknown case $(repr(name)); gate cases: $(join(allcases, ", "))")
                # `all` against an older checkout: skip a case whose model it does not have
                # (ab.jl accepts a skip only from the base and its control)
                prob = try
                    mk[name]()
                catch e
                    pos[1] == "all" && e isa UndefVarError || rethrow()
                    println("ABSKIP $name.$v")
                    continue
                end
                med, mn, k = ab_time(prob, alg, backend; samples, seconds)
                println(AB_LEGACY ? "AB $med" : "ABR $name.$v $med $mn $k")
                flush(stdout)
            end
        end
    end
    if !AB_LEGACY
        for d in unique([AB_START_DISTURBANCES; ab_disturbances()])
            println("DISTURBED ", d)
        end
        println("TC ", join(BenchMachine.type_cache_stats(), " "))
    end
    return 0
end

ab_one_main(AB_POS, AB_OPTS)
