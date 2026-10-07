# Performance gate (D-053, D-157): warm cost of one MCS for every published model,
# sequential and checkerboard on the CPU, and checkerboard on a device backend when one is
# named, against this machine's rows of `benchmark/baseline.toml`.
#
#     julia --project=benchmark benchmark/gate.jl              # CPU rows
#     julia --project=benchmark benchmark/gate.jl rocm         # CPU rows and ROCm (AMDGPU.jl)
#     julia --project=benchmark benchmark/gate.jl metal        # CPU rows and Metal (Metal.jl)
#     julia --project=benchmark benchmark/gate.jl rocm update  # rewrite this machine's rows
#
# Options: `--no-wait` (do not wait for a running CI job or, for rocm, another GPU client
# to end first; `machine.jl` `wait_idle`), `--no-cpu` (device rows only), `--strict` (a CPU row more than `TOLERANCE` above
# its baseline fails, as before D-157).
#
# `baseline.toml` is keyed by machine and backend (`[mac.cpu]`, `[mac.metal]`,
# `[nucbox.cpu]`, `[nucbox.rocm]`; machines in `machine.jl`), and each machine reads only its
# own rows. Absolute baselines are informational (D-157): the gate fails on any warm-MCS
# allocation (CPU rows), while a row more than `TOLERANCE` slower than its baseline is only
# flagged, to be decided by the paired A/B `benchmark/ab.jl` with its same-commit control.
#
# On a machine that pins (the NucBox), the gate re-runs itself pinned to one reserved logical
# CPU (`machine.jl`). Run it alone on the machine (on the Mac under `tools/exclusive.sh`): it
# runs single-threaded, because a threaded KernelAbstractions launch allocates a fixed few
# KB for its tasks, which would hide per-site allocations, and one thread gives steadier
# timings. Its Tuple type cache is seeded like an A/B side (D-145).
#
# On a device backend `step!` only enqueues kernels, so every device timing is `step!`
# followed by a wait for the device (`device_sync`: `KernelAbstractions.synchronize`, or
# on ROCm AMDGPU's blocking synchronize), and each sample's setup waits for
# its own work too (D-090): the number is the GPU's cost, not the host's enqueue cost. CPU
# rows (`backend === nothing`) time `step!` alone.
using BenchmarkTools, Potts, PottsModels, TOML, Printf
import KernelAbstractions
isdefined(@__MODULE__, :BenchMachine) || include(joinpath(@__DIR__, "machine.jl"))

# The device backend named in ARGS ("" | "metal" | "rocm"), loaded through the test suites'
# shared helper (test/shared/devices.jl, D-157); including this file with no device in ARGS
# loads no GPU package.
function requested_device(args)
    toks = [t for a in args for t in split(a, r"[,=]")]
    d = unique(filter(in(("metal", "rocm")), toks))
    length(d) <= 1 || error("one device backend per process; got $(join(d, ", "))")
    return isempty(d) ? "" : String(only(d))
end
const DEVICE = requested_device(ARGS)
if !isempty(DEVICE)
    ENV["POTTS_GPU"] = DEVICE
    isdefined(@__MODULE__, :PottsDevices) ||
        include(joinpath(@__DIR__, "..", "test", "shared", "devices.jl"))
end

"""The device backend object for `DEVICE` (`nothing` when none was named)."""
device_backend() = isempty(DEVICE) ? nothing : PottsDevices.device_backend()

const TOLERANCE = 0.05
const BASELINE = joinpath(@__DIR__, "baseline.toml")
const BASELINE_HEADER = """
    # Informational per-machine baselines (D-157): [<machine>.<backend>], rows <case>.<alg> in ns/site per warm MCS.
    # Written by `gate.jl ... update`; machines are defined in machine.jl. A slowdown is decided by ab.jl, not by these.
    """

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
        # D-150: the Table S1 model, a 6 × 6 colony of 7 × 7 cells (every cell reads the two
        # contact folds after every MCS); X ≡ 2, so no cell reaches its threshold while timed
        "openvt_reference_100" => () -> (σ = zeros(Int32, 100, 100);
            foreach(((k, (a, b)),) -> σ[29 + 7a .+ (1:7), 29 + 7b .+ (1:7)] .= k, enumerate(Iterators.product(0:5, 0:5)));
            PottsProblem(OpenVTReferenceMonolayer(; name = :r, lattice = (100, 100)),
                [ownership => σ, kind => fill(:cell, 36), :σ_X => 0.0], (0, 10^6); T, capacity = 128)),
        # D-153: the 2006 set on merks_100's start inside its 1-site frame (soft E₀ drive,
        # length energy, absorbing field), and the 2008 sprout of the released files on 202²
        # (20 neighbours, 2-site frame) with the field on from MCS 0 (t_relax = 0)
        "merks2006_100" => () -> PottsProblem(Merks2006(; name = :m6, lattice = (100, 100)),
            layout(merks2006_layout(; lattice = (100, 100), n = 25), (100, 100)), (0, 10^6); T,
            field_solver = ExplicitEuler(substeps = 15)),
        "merks2008_202" => () -> PottsProblem(Merks2008(; name = :m8),
            [layout(merks2008_sprout(), (202, 202)); :t_relax => 0.0], (0, 10^6); T,
            field_solver = ExplicitEuler(substeps = 15)),
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

# Wait for all work queued on a device backend: `KernelAbstractions.synchronize`, except on
# ROCm. AMDGPU.jl's default (non-blocking) synchronize spins 256 times and then waits for a
# HIP host callback through Julia's event loop, whose wake-up costs a few ms: a ROCm
# Graner–Glazier MCS read ~20, ~47 or ~2500 ns/site by which path a run's waits took
# (2026-10-07, NucBox); the blocking form (`hipStreamSynchronize`) adds its own wake-up
# latency (GG ~43, Akeeb ~87). Here the host spins on `hipStreamQuery` until the stream is
# done, then calls the blocking synchronize (which returns at once, and raises any kernel
# exception), so the number is the GPU's completion time (D-090).
device_sync(backend) = (KernelAbstractions.synchronize(backend); nothing)
if DEVICE == "rocm"
    const AMDGPU_PKG = PottsDevices.device_package()
    function device_sync(::AMDGPU_PKG.ROCBackend)
        s = AMDGPU_PKG.stream()
        while !AMDGPU_PKG.HIP.isdone(s)
            ccall(:jl_cpu_pause, Cvoid, ())
        end
        AMDGPU_PKG.synchronize(; blocking = true)
        return nothing
    end
end

# Wait until all work queued on `backend` has finished; nothing to wait for on the CPU rows.
settle(::Nothing) = nothing
settle(backend) = device_sync(backend)

# The timed expression of every gate and A/B measurement: one MCS, to completion.
timed_step!(integ, ::Nothing) = (step!(integ); nothing)
timed_step!(integ, backend) = (step!(integ); device_sync(backend); nothing)

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

# The baseline table of one backend on one machine: `baseline.toml` → [machine.backend].
rows(table, machine, backend) = get(get(table, machine, Dict{String, Any}()), backend, Dict{String, Any}())

function main(args)
    Threads.nthreads() == 1 || error("run the performance gate single-threaded (no -t)")
    m = BenchMachine.machine()
    code = BenchMachine.pin_or_reexec(m, args)
    code === nothing || return code
    update = "update" in args
    strict = "--strict" in args
    "--no-wait" in args || BenchMachine.wait_idle(; gpu = DEVICE == "rocm")
    tc = BenchMachine.seed_type_cache!()
    algs = Pair{String, Any}["sequential" => (SequentialCPM(), nothing, Float64),
        "checkerboard" => (CheckerboardCPM(), nothing, Float64)]
    "--no-cpu" in args && empty!(algs)
    isempty(DEVICE) || push!(algs, DEVICE => (CheckerboardCPM(), device_backend(), Float32))
    table = isfile(BASELINE) ? TOML.parsefile(BASELINE) : Dict{String, Any}()
    quiet = BenchMachine.pins(m) ? BenchMachine.check_quiet(BenchMachine.bench_cpu(m); reserved = m.bench) : ""
    println("machine $(m.key) ($(BenchMachine.cpu_model())); CPUs $(something(BenchMachine.allowed_cpus(), "all"))",
        isempty(quiet) ? "" : "; $quiet", "; Tuple cache $(tc.entries)/$(tc.capacity)")
    new = Dict{String, Dict{String, Any}}()
    failed = String[]
    flagged = String[]
    for (aname, (alg, backend, T)) in algs, (name, make) in cases(T)
        bk = backend === nothing ? "cpu" : aname
        rkey = "$name.$(backend === nothing ? aname : "checkerboard")"
        key = "$name.$aname"
        ns, allocs = measure(make, alg; backend)
        get!(new, bk, Dict{String, Any}())[rkey] = round(ns; digits = 3)
        old = get(rows(table, m.key, bk), rkey, nothing)
        ratio = old === nothing ? NaN : ns / old
        slow = !update && old !== nothing && ratio > 1 + TOLERANCE
        bad = allocs > 0 || (strict && slow && backend === nothing)
        bad && push!(failed, key)
        slow && !bad && push!(flagged, key)
        @printf("%-36s %8.2f ns/site  baseline %8s  ratio %6s  allocs %d%s\n", key, ns,
            old === nothing ? "–" : @sprintf("%.2f", old), isnan(ratio) ? "–" : @sprintf("%.3f", ratio), allocs,
            bad ? "  FAIL" : key in flagged ? "  A/B" : "")
    end
    if update
        mt = get!(table, m.key, Dict{String, Any}())
        for (bk, r) in new
            merge!(get!(mt, bk, Dict{String, Any}()), r)
        end
        mt["meta"] = Dict("cpu" => BenchMachine.cpu_model(), "threads" => Threads.nthreads(), "julia" => string(VERSION),
            "cpus" => string(something(BenchMachine.allowed_cpus(), "all")))
        open(BASELINE, "w") do io
            println(io, BASELINE_HEADER)
            TOML.print(io, table; sorted = true)
        end
        println("baseline written: ", BASELINE, " [", m.key, "]")
        return 0
    end
    isempty(flagged) || println("slower than the informational baseline, decide with benchmark/ab.jl: ", join(flagged, ", "))
    isempty(failed) || (println("REGRESSION: ", join(failed, ", ")); return 1)
    println("performance gate: pass")
    return 0
end

abspath(PROGRAM_FILE) == (@__FILE__) && exit(main(ARGS))
