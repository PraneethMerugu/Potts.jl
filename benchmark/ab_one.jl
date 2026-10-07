# Child of benchmark/ab.jl: warm-MCS times of gate cases in the active project's checkout.
#
#     julia --project=benchmark benchmark/ab_one.jl <case> <alg>
#     julia --project=<checkout>/benchmark benchmark/ab_one.jl <cases> <variants> [options]
#     julia --project=<checkout>/benchmark benchmark/ab_one.jl --variants=<file.jl> <variant> [options]
#
# <cases>: gate case names, comma-separated, or `all`. <variants>: `sequential`,
# `checkerboard` (CPU, Float64), `metal` or `rocm` (checkerboard on that device, Float32),
# comma-separated; at most one device. Timed like the gate: on a device, `step!` followed by
# `synchronize` (D-090). The two-argument form prints one line `AB <median ns/site>` (the
# D-090 contract); otherwise each measurement prints
#     ABR <label> <median ns/site> <minimum ns/site> <samples>
# and the process prints `TC <entries> <capacity>` of its Tuple type cache, once after
# seeding and once at the end.
#
# Options:
#   --seed=<n>       seed the Tuple type cache to n entries (default BenchMachine.SEED_ENTRIES;
#                    0 = no seeding). Seeding runs after the packages load, before any build.
#   --samples=<n>    samples per measurement (default 60), --seconds=<s> (default 40)
#   --variants=<f>   in-process A/B: `f` defines `AB_VARIANTS`, a vector of
#                    `label => T -> PottsProblem` (base first, candidate second; `T` is the
#                    float type). Measured `--rounds` times (default 6) in rotating order,
#                    with a control: a second, separately built copy of the base, labelled
#                    `control`. Labels print as `<label>:<variant>`.
isdefined(Main, :BenchMachine) || include(joinpath(@__DIR__, "machine.jl"))
include(joinpath(@__DIR__, "gate.jl"))
using Statistics: median

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

const AB_ALGS = Dict("sequential" => (SequentialCPM(), false), "checkerboard" => (CheckerboardCPM(), false),
    "metal" => (CheckerboardCPM(), true), "rocm" => (CheckerboardCPM(), true))

function ab_variant(v)
    haskey(AB_ALGS, v) || error("unknown variant $(repr(v)); one of $(join(sort(collect(keys(AB_ALGS))), ", "))")
    alg, dev = AB_ALGS[v]
    dev && v != DEVICE && error("variant $v needs the $v backend loaded")
    return alg, dev ? device_backend() : nothing, dev ? Float32 : Float64
end

function ab_time(prob, alg, backend; samples, seconds)
    fresh_integrator(prob, alg, backend)
    b = run(@benchmarkable timed_step!(i, $backend) setup = (i = fresh_integrator($prob, $alg, $backend)) evals = 1 samples = samples seconds = seconds)
    n = length(prob.u0.σ)
    return median(b).time / n, minimum(b).time / n, length(b.times)
end

function ab_one_main(args)
    pos, opts = ab_one_opts(args)
    legacy = length(args) == 2 && isempty(opts)
    seed = parse(Int, get(opts, "seed", string(BenchMachine.SEED_ENTRIES)))
    tc = seed > 0 ? BenchMachine.seed_type_cache!(seed) : (; zip((:entries, :capacity), BenchMachine.type_cache_stats())...)
    legacy || println("TC ", tc.entries, " ", tc.capacity)
    samples = parse(Int, get(opts, "samples", "60"))
    seconds = parse(Float64, get(opts, "seconds", "40"))
    if haskey(opts, "variants")
        Base.include(Main, opts["variants"])
        vs = Main.AB_VARIANTS
        length(vs) >= 2 || error("AB_VARIANTS needs a base and a candidate")
        rounds = parse(Int, get(opts, "rounds", "6"))
        for v in split(only(pos), ',')
            alg, backend, T = ab_variant(v)
            sides = ["base" => first(vs)[2](T), "candidate" => vs[2][2](T), "control" => first(vs)[2](T)]
            for r in 1:rounds
                for (label, prob) in circshift(sides, -(r - 1))
                    med, mn, k = ab_time(prob, alg, backend; samples, seconds)
                    println("ABR $label:$v $med $mn $k")
                    flush(stdout)
                end
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
                haskey(mk, name) || error("unknown case $(repr(name)); gate cases: $(join(allcases, ", "))")
                # `all` against an older checkout: skip a case whose model it does not have
                prob = try
                    mk[name]()
                catch e
                    pos[1] == "all" && e isa UndefVarError || rethrow()
                    println("ABSKIP $name.$v")
                    continue
                end
                med, mn, k = ab_time(prob, alg, backend; samples, seconds)
                println(legacy ? "AB $med" : "ABR $name.$v $med $mn $k")
                flush(stdout)
            end
        end
    end
    legacy || println("TC ", join(BenchMachine.type_cache_stats(), " "))
    return 0
end

ab_one_main(ARGS)
