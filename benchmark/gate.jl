# Performance gate (D-053): warm cost of one MCS for every published model, sequential and
# checkerboard on the CPU (and Metal with `metal`), against `benchmark/baseline.toml`.
#
#     julia --project=benchmark benchmark/gate.jl            # compare, exit 1 on regression
#     julia --project=benchmark benchmark/gate.jl update     # rewrite the baseline
#     julia --project=benchmark benchmark/gate.jl metal      # also gate Metal
#
# A merge fails if any CPU case is more than `TOLERANCE` slower than its baseline (minimum
# over samples, ns per site per MCS) or any case allocates in a warm MCS. On this Mac the
# GPU timing is bimodal (about 1.5x between power states, the same for any commit), so a
# slow Metal case is only flagged: it is decided by `benchmark/ab.jl`, which interleaves
# the base and the candidate (AUTONOMY §7.4). Run it alone on the
# machine: parallel test suites make timings meaningless. It runs single-threaded: a
# threaded KernelAbstractions launch allocates a fixed few KB for its tasks, which would
# hide per-site allocations, and one thread gives steadier timings.
#
# On a device backend `step!` only enqueues kernels, so every device timing is `step!`
# followed by `KernelAbstractions.synchronize(backend)`, and each sample's setup waits for
# its own work too (D-090): the number is the GPU's cost, not the host's enqueue cost. CPU
# rows (`backend === nothing`) time `step!` alone.
using BenchmarkTools, Potts, PottsModels, TOML, Printf
import KernelAbstractions
const METAL = "metal" in ARGS
METAL && using Metal

const TOLERANCE = 0.05
const BASELINE = joinpath(@__DIR__, "baseline.toml")

function cases(T)
    gg = graner_glazier_state()
    return [
        "graner_glazier_72" => () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 10^6); T),
        "wortel_act_100" => () -> (σ = zeros(Int32, 100, 100); σ[40:62, 40:62] .= 1;
            PottsProblem(WortelAct(; name = :w, lattice = (100, 100)), [ownership => σ, kind => [:cell]], (0, 10^6); T)),
        "merks_100" => () -> PottsProblem(MerksVasculogenesis(; name = :m, lattice = (100, 100)),
            merks_state(; lattice = (100, 100), n = 25), (0, 10^6); T,          # 10² cells, ≈ 25 % cover
            field_solver = ExplicitEuler(substeps = 15, lower = 0.0)),
        "openvt_monolayer_100" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (100, 100), τ = 1e6),
            openvt_monolayer_state(; lattice = (100, 100)), (0, 10^6); T, capacity = 64),
        "akeeb_99x60" => () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (0, 10^6); T, capacity = 1000),
    ]
end

# a function barrier: `integ` is concretely typed here, so only `step!` is measured
function warm_allocs(integ)
    m = typemax(Int)
    for _ in 1:5
        m = min(m, @allocated step!(integ))
    end
    return m
end

# Wait until all work queued on `backend` has finished; nothing to wait for on the CPU rows.
settle(::Nothing) = nothing
settle(backend) = (KernelAbstractions.synchronize(backend); nothing)

# The timed expression of every gate and A/B measurement: one MCS, to completion.
timed_step!(integ, ::Nothing) = (step!(integ); nothing)
timed_step!(integ, backend) = (step!(integ); KernelAbstractions.synchronize(backend); nothing)

# A warmed-up integrator (two MCS) with no work still in flight.
function fresh_integrator(prob, alg, backend)
    kw = backend === nothing ? (;) : (; backend)
    integ = init(prob, alg; save_start = false, save_end = false, kw...)
    step!(integ)
    step!(integ)
    settle(backend)
    return integ
end

function measure(make, alg; backend = nothing)
    prob = make()
    integ = fresh_integrator(prob, alg, backend)
    timed_step!(integ, backend)
    allocs = backend === nothing ? warm_allocs(integ) : 0
    b = run(@benchmarkable timed_step!(i, $backend) setup = (i = fresh_integrator($prob, $alg, $backend)) evals = 1 samples = 40 seconds = 30)
    n = length(integ.state.σ)
    return minimum(b).time / n, allocs
end

function main(args)
    Threads.nthreads() == 1 || error("run the performance gate single-threaded (no -t)")
    update = "update" in args
    algs = Pair{String, Any}["sequential" => (SequentialCPM(), nothing, Float64),
        "checkerboard" => (CheckerboardCPM(), nothing, Float64)]
    METAL && push!(algs, "metal" => (CheckerboardCPM(), Metal.MetalBackend(), Float32))
    base = isfile(BASELINE) ? TOML.parsefile(BASELINE) : Dict{String, Any}()
    new = Dict{String, Any}()
    failed = String[]
    flagged = String[]
    for (aname, (alg, backend, T)) in algs, (name, make) in cases(T)
        key = "$name.$aname"
        ns, allocs = measure(make, alg; backend)
        new[key] = round(ns; digits = 3)
        old = get(base, key, nothing)
        ratio = old === nothing ? NaN : ns / old
        slow = !update && old !== nothing && ratio > 1 + TOLERANCE
        bad = allocs > 0 || (slow && aname != "metal")
        bad && push!(failed, key)
        slow && aname == "metal" && push!(flagged, key)
        @printf("%-36s %8.2f ns/site  baseline %8s  ratio %6s  allocs %d%s\n", key, ns,
            old === nothing ? "–" : @sprintf("%.2f", old), isnan(ratio) ? "–" : @sprintf("%.3f", ratio), allocs,
            bad ? "  FAIL" : key in flagged ? "  A/B" : "")
    end
    if update
        meta = Dict("machine" => Sys.cpu_info()[1].model, "threads" => Threads.nthreads(), "julia" => string(VERSION))
        open(BASELINE, "w") do io
            TOML.print(io, merge(merge(base, new), Dict("meta" => meta)); sorted = true)
        end
        println("baseline written: ", BASELINE)
        return 0
    end
    isempty(flagged) || println("Metal flagged, decide with benchmark/ab.jl: ", join(flagged, ", "))
    isempty(failed) || (println("REGRESSION: ", join(failed, ", ")); return 1)
    println("performance gate: pass")
    return 0
end

abspath(PROGRAM_FILE) == (@__FILE__) && exit(main(ARGS))
