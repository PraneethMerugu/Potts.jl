# Child of benchmark/ab.jl: warm-MCS times of gate cases in the active project's checkout.
#
#     julia --project=<checkout>/benchmark benchmark/ab_one.jl <cases> <variants> [options]
#     julia --project=<checkout>/benchmark benchmark/ab_one.jl --variants=<file.jl> <variant> [options]
#
# <cases>: gate case names, comma-separated, or `all`. <variants>: `sequential`,
# `checkerboard`, `boundary` (CPU, Float64), `metal` or `rocm` (checkerboard on that device, Float32),
# comma-separated; at most one device. Timed like the gate: on a device, `step!` followed by
# the device wait `device_sync` (D-090).
#
# In `--prepare` mode (used by `ab.jl`'s parallel-compile path), the process:
#  1. loads the packages, seeds the Tuple type cache (on CPU/Metal), builds all problems,
#     compiles kernels via one untimed `fresh_integrator` + `timed_step!` per case/variant
#     (except on ROCm, where problems are built before READY while loading AMDGPU/KFD,
#     seeding the Tuple type cache, and GPU kernel compile stay after `GO` so no sibling
#     holds a KFD context during timing), and runs `GC.gc()` (`ab.jl` handles waiting in
#     the parent before spawning and inside the lock before each `GO`);
#  2. prints `READY <pid>`, flushes stdout, and blocks reading stdin for
#     `GO <cpu> [<exclude_pids>]`;
#  3. once `GO` arrives (already re-pinned by the parent to `<cpu>` while the parent holds
#     `tools/exclusive.sh`), checks start disturbances (excluding live sibling PIDs), runs
#     a 1.5 s fixed burn-in on the benchmark core so boost clocks settle before the first
#     sample, prints the post-seed `TC <entries> <capacity>`, runs the timed trials (`ABR`/`ABSKIP` lines),
#     checks end disturbances, prints `DISTURBED`, final `TC`, and `DONE`, and waits for
#     stdin EOF so the parent can re-pin it off the benchmark core before heap teardown.
#
# Without `--prepare` (used by `--serial`, `--inprocess`, and direct runs), the process
# runs steps 1–2 and times immediately in one pass without reading stdin or printing
# `READY`/`DONE`.
#
# Options:
#   --prepare        build and compile all cases first, print `READY <pid>`, wait for `GO`
#   --seed=<n>       seed the Tuple type cache to n entries (default BenchMachine.SEED_ENTRIES;
#                    0 = no seeding). Seeding runs after the packages load, before any build
#                    (except ROCm `--prepare`, where problems build first and seeding runs
#                    after `GO` once AMDGPU loads).
#   --samples=<n>    samples per measurement (default 60), --seconds=<s> (default 40)
#   --gctrial, --no-gctrial  BenchmarkTools' GC scrub (`gctrial`: three full collections
#                    once per trial, before its first sample). Default (D-252): off for the CPU
#                    variants, on for device variants. Each `ABR`
#                    line ends with the trial's largest per-sample GC time (ns) and the minimum
#                    allocations and bytes over its samples; on the CPU, a GC inside any timed
#                    sample is reported as DISTURBED, which there means the timed step allocated
#                    (an allocation regression, not machine noise)
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
const AB_PREPARE = haskey(AB_OPTS, "prepare")
const AB_GPU = any(v -> v in ("rocm", "metal"), split(join(AB_POS, ","), ','))
const AB_ROCM_DEFER = AB_PREPARE && any(v -> v == "rocm", split(join(AB_POS, ","), ','))
const AB_WAIT = get(AB_OPTS, "wait", "all")
AB_WAIT in ("all", "gpu", "none") || error("--wait is all, gpu or none")

"""
What disturbs this run now (nothing with `--wait=none`).
"""
function ab_disturbances(; exclude = Int[])
    AB_WAIT == "none" && return String[]
    m = BenchMachine.machine()
    BenchMachine.pins(m) ||
        return BenchMachine.busy_reasons(; gpu = AB_GPU, ci = AB_WAIT == "all", exclude)
    c = something(BenchMachine.allowed_cpus(), Int[])
    return BenchMachine.disturbances(length(c) == 1 ? only(c) : -1, m.bench;
        gpu = AB_GPU, ci = AB_WAIT == "all", exclude
    )
end

# 1. wait (before loading anything heavy, so a waiting child holds no GPU context; in
#    `--prepare` mode, the parent handles waiting before spawning and inside the lock)
if !AB_PREPARE && AB_WAIT != "none"
    deadline = parse(Float64, get(AB_OPTS, "deadline", string(time() + 4 * 3600)))
    BenchMachine.wait_idle(; gpu = AB_GPU, ci = AB_WAIT == "all", deadline) ||
        println("DISTURBED waited until the deadline; timed while busy")
end
const AB_START_DISTURBANCES = AB_PREPARE ? String[] : ab_disturbances()

AB_ROCM_DEFER && (ENV["POTTS_DEFER_DEVICE"] = "1")
include(joinpath(@__DIR__, "gate.jl"))
using Statistics: median

# `boundary` (D-177, D-198): sequential copy attempts at boundary sites only
const AB_ALGS = Dict("sequential" => (SequentialCPM(), false),
    "checkerboard" => (CheckerboardCPM(), false),
    "boundary" => (SequentialCPM(; skip_interior = true), false),
    "metal" => (CheckerboardCPM(), true), "rocm" => (CheckerboardCPM(), true))

function ab_variant(v; load_backend = true)
    haskey(AB_ALGS, v) ||
        error("unknown variant $(repr(v)); one of $(join(sort(collect(keys(AB_ALGS))), ", "))")
    alg, dev = AB_ALGS[v]
    dev && v != DEVICE && error("variant $v needs the $v backend loaded")
    return alg, load_backend && dev ? device_backend() : nothing, dev ? Float32 : Float64, dev
end

# the number of sites of a state (the ownership array is `σ` in older checkouts: an A/B base
# may be one)
# The old name is accepted only so an A/B can run against a base older than the renames; drop it once no base predates them.
nsites(u) = length(hasproperty(u, :ownership) ? u.ownership : u.σ)

function ab_time(prob, alg, backend; samples, seconds, gctrial = backend !== nothing)
    fresh_integrator(prob, alg, backend)
    b = run(@benchmarkable timed_step!(i, $backend) setup=(i=fresh_integrator($prob, $alg, $backend)) evals=1 samples=samples seconds=seconds gctrial=gctrial)
    n = nsites(prob.u0)
    # the largest per-sample GC time, and the allocations and bytes (BenchmarkTools keeps the
    # minimum over samples, so these only show allocation in every sample; the GC field is the check)
    return median(b).time / n, minimum(b).time / n, length(b.times), maximum(b.gctimes), b.allocs, b.memory
end

# D-252: the CPU step allocates nothing, so no collection may land inside a timed sample; one
# thread, the step never yields, and gc time is read after setup, so a GC here means the step
# allocated (it recurs on re-timing: treat it as an allocation regression, not noise)
const AB_GC_DISTURBANCES = String[]
function ab_check_gc!(label, backend, maxgc)
    backend === nothing && maxgc > 0 &&
        push!(AB_GC_DISTURBANCES, "a GC ran inside a timed sample of $label ($(round(Int, maxgc)) ns)")
    return nothing
end

function ab_build_cases(pos; load_backend = true)
    length(pos) == 2 || error("usage: ab_one.jl <cases> <variants> [options]")
    allcases = first.(cases(Float64))
    names = pos[1] == "all" ? allcases : split(pos[1], ',')
    items = Any[]
    for v in split(pos[2], ',')
        alg, backend, T, dev = ab_variant(v; load_backend)
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
                nothing
            end
            push!(items, (; label = "$name.$v", prob, alg, backend, dev))
        end
    end
    return items
end

function ab_time_item!(item; samples, seconds, gctrial)
    if item.prob === nothing
        println("ABSKIP ", item.label)
        flush(stdout)
        return nothing
    end
    med, mn, k, gc, al, mem = ab_time(
        item.prob, item.alg, item.backend;
        samples, seconds, gctrial
    )
    ab_check_gc!(item.label, item.backend, gc)
    println("ABR ", item.label, " ", med, " ", mn, " ", k, " ", gc, " ", al, " ", mem)
    flush(stdout)
    return nothing
end

function ab_wait_go()
    println("READY ", getpid())
    flush(stdout)
    line = readline(stdin)
    isempty(strip(line)) && return nothing
    fields = split(strip(line))
    fields[1] == "GO" || error("expected GO, got $(repr(line))")
    target_cpu = length(fields) >= 2 ? parse(Int, fields[2]) : -1
    exclude_pids = length(fields) >= 3 ?
        parse.(Int, split(fields[3], ','; keepempty = false)) : Int[]
    if target_cpu >= 0 && BenchMachine.pins(BenchMachine.machine())
        allowed = BenchMachine.allowed_cpus()
        allowed == [target_cpu] ||
            error("child $(getpid()) expected CPU $target_cpu, got $allowed")
    end
    return (; target_cpu, exclude_pids)
end

function ab_burnin!(prepared)
    t0 = time_ns()
    while time_ns() - t0 < 1_500_000_000
    end
    for item in prepared
        item.prob === nothing && continue
        integ = fresh_integrator(item.prob, item.alg, item.backend)
        timed_step!(integ, item.backend)
        break
    end
    return nothing
end

function ab_run_prepared!(
        prepared, tc_start, go, samples, seconds, gctrial_for;
        resolve_dev = false
    )
    items = resolve_dev ?
        [
            (;
                item.label, item.prob, item.alg,
                backend = item.dev ? device_backend() : nothing,
            ) for item in prepared
        ] :
        prepared
    start_dist = ab_disturbances(; exclude = go.exclude_pids)
    ab_burnin!(items)
    println("TC ", join(tc_start, " "))
    flush(stdout)
    for item in items
        ab_time_item!(item; samples, seconds, gctrial = gctrial_for(item.backend))
    end
    end_dist = ab_disturbances(; exclude = go.exclude_pids)
    for d in unique([start_dist; end_dist; AB_GC_DISTURBANCES])
        println("DISTURBED ", d)
    end
    println("TC ", join(BenchMachine.type_cache_stats(), " "))
    println("DONE")
    flush(stdout)
    # Wait for parent to re-pin us off the benchmark core and close stdin before tearing down.
    eof(stdin)
    return 0
end

function ab_one_main(pos, opts)
    seed = parse(Int, get(opts, "seed", string(BenchMachine.SEED_ENTRIES)))
    samples = parse(Int, get(opts, "samples", "60"))
    seconds = parse(Float64, get(opts, "seconds", "40"))
    # D-252: no scrub for the CPU variants; device variants keep it
    gctrial_opt = haskey(opts, "gctrial") ? true : haskey(opts, "no-gctrial") ? false : nothing
    gctrial_for(backend) = something(gctrial_opt, backend !== nothing)
    if AB_PREPARE
        haskey(opts, "variants") && error("--prepare cannot be combined with --variants")
        if AB_ROCM_DEFER
            prepared = ab_build_cases(pos; load_backend = false)
            GC.gc()
            go = ab_wait_go()
            go === nothing && return 1
            load_device!(DEVICE)
            seed > 0 && BenchMachine.seed_type_cache!(seed)
            tc_start = BenchMachine.type_cache_stats()
            return Base.invokelatest(
                ab_run_prepared!, prepared, tc_start, go,
                samples, seconds, gctrial_for; resolve_dev = true
            )
        end
        seed > 0 && BenchMachine.seed_type_cache!(seed)
        tc_start = BenchMachine.type_cache_stats()
        prepared = ab_build_cases(pos)
        for item in prepared
            item.prob === nothing && continue
            # Build and compile every case/variant before READY so no child compiles during timing.
            integ = fresh_integrator(item.prob, item.alg, item.backend)
            timed_step!(integ, item.backend)
        end
        GC.gc()
        go = ab_wait_go()
        go === nothing && return 1
        return ab_run_prepared!(prepared, tc_start, go, samples, seconds, gctrial_for)
    end
    seed > 0 && BenchMachine.seed_type_cache!(seed)
    tc_start = BenchMachine.type_cache_stats()
    println("TC ", join(tc_start, " "))
    if haskey(opts, "variants")
        Base.include(Main, opts["variants"])
        vs = Main.AB_VARIANTS
        length(vs) >= 2 || error("AB_VARIANTS needs a base and a candidate")
        rounds = parse(Int, get(opts, "rounds", "8"))
        for v in split(only(pos), ',')
            alg, backend, T, _ = ab_variant(v)
            sides = ["base" => vs[1][2](T), "candidate" => vs[2][2](T)]
            haskey(opts, "no-control") ||
                append!(sides, ["base-ctl" => vs[1][2](T), "cand-ctl" => vs[2][2](T)])
            for r in 1:rounds, (label, prob) in circshift(sides, -(r - 1))
                med, mn, k, gc, al, mem = ab_time(prob, alg, backend; samples, seconds,
                    gctrial = gctrial_for(backend))
                ab_check_gc!("$label:$v", backend, gc)
                println("ABR $label:$v $med $mn $k $gc $al $mem")
                flush(stdout)
            end
        end
    else
        length(pos) == 2 || error("usage: ab_one.jl <cases> <variants> [options]")
        allcases = first.(cases(Float64))
        names = pos[1] == "all" ? allcases : split(pos[1], ',')
        for v in split(pos[2], ',')
            alg, backend, T, _ = ab_variant(v)
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
                ab_time_item!(
                    (; label = "$name.$v", prob, alg, backend);
                    samples, seconds, gctrial = gctrial_for(backend)
                )
            end
        end
    end
    for d in unique([AB_START_DISTURBANCES; ab_disturbances(); AB_GC_DISTURBANCES])
        println("DISTURBED ", d)
    end
    println("TC ", join(BenchMachine.type_cache_stats(), " "))
    return 0
end

let rc = ab_one_main(AB_POS, AB_OPTS)
    if abspath(PROGRAM_FILE) == (@__FILE__)
        exit(rc)
    end
end
