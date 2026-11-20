# Launch fusion, Metal codegen fixes and
# no hidden GPU waits. Decisions: D-085 (counters), D-089/D-096 (device lifecycle), D-090
# (Metal timings), D-092 (column copies; the double sync of item 4), D-098 (Merks'
# 15 field substeps). Audit: `docs/design/research/gpu-host-transfer-audit.md` §2.1, §6 T3,
# §8 (F1–F6, §8.2, §8.3, §8.4), §9–§11.
#
# What is checked (Metal: POTTS_GPU=metal with Metal loaded, Float32, CheckerboardCPM):
#  (1) A quiet MCS of every gate model (`benchmark/gate.jl` cases, built the same
#      way and at the same sizes: Graner–Glazier 72, Wortel Act 100, Merks 100 with 15
#      field substeps, OpenVT monolayer 100, Akeeb 99×60) makes 0 syncs, 0 transfers, 0 B
#      AND 0 GPU waits. GPU waits are the calls of Metal.jl's `wait_cmdbuf!`, counted with
#      the test-only wrapper of `test/transfer_counts_tests.jl` (Metal.jl 1.10.0 bodies; the
#      back-pressure of `wait_oldest_cleanup!`, the host running ahead of a busy GPU, is not
#      a wait). Controls: the window is quiet (checkpoints around it show no lifecycle
#      event) and the wrapper counts the waits of the checkpoint after the window.
#  (2) Every device→device copy of the step path makes no GPU wait: a `FieldStep` fixture
#      with N = 1, 3, 15 substeps, a Potts cell-ODE fixture whose scratch is published by a
#      `CopyPhase` (Jacobi cross-cell read, `cell_ode_jacobi_tests.jl`), and Merks with 2 and 15 substeps: waits
#      per MCS are the same for every N, and 0. Control: the launches grow with N (the
#      substeps ran).
#  (3) Launches. `stats.launches` of a quiet MCS of each gate model (gate sizes) lies in
#      [floor, bound]. Re-derived for the lockless block checkerboard (D-271): an MCS is 64
#      phase launches (2D default, 8 parts per axis; no serial pass in these models), plus
#      the model's own phases, plus one moment re-centering (`recenter_kernel!`) for models
#      that track moments. Measured on ROCm 2026-11-05 (5 quiet MCS, constant): GG 64,
#      Wortel 65, Merks 95, OpenVT 66, Akeeb 66.
#        Graner–Glazier 72  64 phases. Floor = bound = 64.
#        Wortel Act 100     64 + the `act` decay `SitePhase` (F6, not assigned). Floor 64,
#                           bound 65.
#        Merks 100          64 + 15 substeps × (field kernel + copy) + 1 re-centering
#                           (`major_length`). Floor 64 + 15 + 1 (one field kernel per
#                           substep), bound 95.
#        OpenVT mono. 100   64 + one launch for the `V_target` `CellPhase` and the lifecycle
#                           together (F1) + 1 re-centering. Floor = bound = 66.
#        Akeeb 99×60        64 + one launch for the `V_target`/`clock` `CellPhase` and the
#                           lifecycle (F1) + 1 re-centering. Floor = bound = 66.
#      The floors keep the launch counter honest: every phase still needs its kernel.
#  (4) An MCS with two consecutive adaptive-ODE host phases (a cell and a
#      model ODE, both `Adaptive`) makes exactly one counted sync (today two; the second
#      waits on an idle queue). Controls: a single adaptive phase makes one sync (the
#      counter is live), and both ODEs follow their analytic solutions.
#  (5) Exactness. On the CPU, bitwise with a fixed seed: the `FieldStep` fixture (σ frozen:
#      T = 0 and every cell at its target volume) equals a plain-Julia explicit-Euler oracle
#      written here, for N = 1, 3, 15, Float64 and Float32, both algorithms; the `CopyPhase`
#      fixture equals its exact oracle (k = 1: the two cells swap their values every MCS);
#      Merks (32², 6 cells, 15 substeps, seed 7, 6 MCS) equals the digests of σ and the field
#      recorded here from the current code (and differs for another seed: the digest is
#      sensitive). On the device, the fixtures equal the same oracles bitwise (σ is frozen,
#      so the sweep's timing does not matter). Merks on the device is not reproducible
#      (D-271): it runs and keeps its invariants (labels in range, the CPU run's cells
#      alive, a finite field).
#  (6) No Float64 reaches a Metal kernel for the gate models. Practical form: the types of
#      everything the integrator hands to its kernels (`integ.p`, `integ.state`,
#      `integ.ctx`, the sweep's kernel function `integ.kf`) contain no `Float64` leaf when
#      built with `T = Float32` (CPU and Metal); on Metal the gate models also run and
#      save. Controls: the same scan finds `Float64` in the `T = Float64` builds, and Metal
#      rejects a kernel that touches a `Float64` at compile time (`InvalidIRError`), so a
#      leak cannot pass silently. Not done: scanning the device LLVM of every kernel
#      (`Metal.@device_code_llvm` sees only kernels compiled inside it, and the sibling
#      files compile the same kernels first in one session; audit §8.2 did the scan once).
#
# Today: (1) fails for Merks (30 GPU waits per quiet MCS: 15 substeps × 2 waits of
# Metal.jl's device→device `copyto!`); (2) fails (waits per MCS = 2N for the field fixture,
# 2 for the `CopyPhase` fixture, 4 and 30 for Merks); (3) fails for OpenVT (10 > 9) and Akeeb
# (14 > 13); (4) fails (2 syncs); (5) and (6) pass (they check what the fusions must keep).

@testsetup module LaunchFusionSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P
using Potts.CorePotts.KernelAbstractions: @kernel, @index
const ON_DEVICE = PottsDevices.on_device()
counts(s) = (s.syncs, s.transfers, s.transfer_bytes)
lifecycle_total(s) = sum(f -> getfield(s.lifecycle, f), fieldnames(typeof(s.lifecycle)))
# ---------------------------------------------------------------------------------------
# The gate models, exactly as `benchmark/gate.jl` builds them
function gate_cases(T)
    gg = graner_glazier_state()
    return [
        "graner_glazier_72" => () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 10^6); T),
        "wortel_act_100" => () -> (
            σ = zeros(Int32, 100, 100); σ[40:62, 40:62] .= 1;
            PottsProblem(WortelAct(; name = :w, lattice = (100, 100)), [ownership => σ, kind => [:cell]], (0, 10^6); T)
        ),
        "merks_100" => () -> PottsProblem(
            MerksVasculogenesis(; name = :m, lattice = (100, 100)),
            merks_state(; lattice = (100, 100), n = 25), (0, 10^6); T,
            field_solver = ExplicitEuler(substeps = 15, lower_bound = 0.0)
        ),
        "openvt_monolayer_100" => () -> PottsProblem(
            OpenVTGrowingMonolayer(; name = :o, lattice = (100, 100), τ = 1.0e6),
            openvt_monolayer_state(; lattice = (100, 100)), (0, 10^6); T, capacity = 64
        ),
        "akeeb_99x60" => () -> PottsProblem(
            AkeebInvasion(; name = :a, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (0, 10^6); T, capacity = 1000
        ),
    ]
end
# ---------------------------------------------------------------------------------------
# Field fixture (CorePotts level). One 5×5 cell at its target volume, T = 0: every copy
# raises the energy and is rejected, so σ never changes and the field's source is known.
# rate(c)_i = D (c_{i-1} + c_{i+1} − 2 c_i) + s [σ_i ≠ 0] − k c_i over the linear index
# (periodic), explicit Euler in N substeps per MCS, clipped below at 0. Since the
# field-compiler cutover (C8, CorePotts.FieldStep deleted) each substep is a site phase into
# the scratch and a device copy back (the field-compiler switch): the same operations, the same order.
const FDIMS = (16, 16)
field_rate(st, p, ctx, key, mcs, i, c) = (
    n = length(c); l = i == 1 ? n : i - 1; r = i == n ? 1 : i + 1;
    p.D * (c[l] + c[r] - 2 * c[i]) + p.s * (st.ownership[i] != 0) - p.k * c[i]
)
"""One explicit-Euler substep of length `h` into `c__next`, clipped below at 0."""
struct FieldSubstep{T}
    h::T
end
(f::FieldSubstep)(st, p, ctx, key, mcs, i) = (
    c = vec(st.site.c);
    @inbounds st.site.c__next[i] = max(c[i] + f.h * field_rate(st, p, ctx, key, mcs, i, c), zero(f.h)); nothing
)
field_c0(T) = T[sin(Float64(i))^2 for i in 1:prod(FDIMS)]
function field_σ()
    σ = zeros(Int32, FDIMS)
    σ[5:9, 5:9] .= 1
    return σ
end
field_params(T) = (; λ = T(1), V0 = T(25), T = T(0), D = T(0.2), s = T(0.01), k = T(0.003))
function field_problem(; T = Float64, N = 3, nmcs = 4)
    site = (; c = reshape(field_c0(T), FDIMS), c__next = zeros(T, FDIMS))
    u0 = CorePotts.initial_state(field_σ(), Int32[1]; site)
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    sub = (CorePotts.SitePhase(FieldSubstep(T(T(1) / N))), CorePotts.CopyPhase((:site, :c) => (:site, :c__next)))
    ph = Tuple(Iterators.flatten(ntuple(_ -> sub, N)))
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T, phases = CorePotts.Phases(; after_mcs = ph))
    return CorePotts.PottsProblem(f, u0, CorePotts.Lattice(FDIMS), (0, nmcs), field_params(T))
end
"""The field after `nmcs` MCS of N explicit-Euler substeps, in plain Julia (same operations,
same order, so bitwise equal to a correct implementation)."""
function field_oracle(T, N, nmcs)
    c = field_c0(T)
    σ = vec(field_σ())
    p = field_params(T)
    h = T(T(1) / N)
    n = length(c)
    for _ in 1:(nmcs * N)
        cn = similar(c)
        for i in 1:n
            l = i == 1 ? n : i - 1
            r = i == n ? 1 : i + 1
            cn[i] = max(c[i] + h * (p.D * (c[l] + c[r] - 2 * c[i]) + p.s * (σ[i] != 0) - p.k * c[i]), T(0))
        end
        c = cn
    end
    return reshape(c, FDIMS)
end
# CopyPhase fixture (Potts level): a cell ODE that reads the other cell's unknown is Jacobi,
# so the generated code writes the scratch `y__ode` and publishes it with a `CopyPhase`
# (`cell_ode_jacobi_tests.jl`). k = 1, one explicit-Euler step per MCS: y₁ ← y₂ and y₂ ← y₁ exactly. Both cells
# sit at their target volume with T ≈ 0, so σ does not matter.
@potts_model FusionPair begin
    @kinds medium A
    @parameters k = 1.0
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ k * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0e-6)
end
const FUSION_Y0 = (1.0, 3.0)
function pair_problem(; T = Float64, nmcs = 4)
    σ = zeros(Int32, 12, 8)
    σ[2:5, 2:5] .= 1
    σ[8:11, 4:7] .= 2
    return PottsProblem(
        FusionPair(; name = :pair), [ownership => σ, kind => [:A, :A], :y => collect(FUSION_Y0)], (0, nmcs);
        T, ode_solver = ExplicitEuler()
    )
end
pair_oracle(T, nmcs) = T.(isodd(nmcs) ? reverse(collect(FUSION_Y0)) : collect(FUSION_Y0))
# Merks at a small size with the paper's 15 substeps (or `substeps`), a fixed seed.
merks_problem(; T = Float64, substeps = 15, seed = 7, nmcs = 6) =
    PottsProblem(
    MerksVasculogenesis(; name = :m, lattice = (32, 32)), merks_state(; lattice = (32, 32), n = 6, side = 7),
    (0, nmcs); T, seed, field_solver = ExplicitEuler(; substeps, lower_bound = 0.0)
)
# Two adaptive-ODE phases in one MCS: a cell ODE and a model ODE, both `Adaptive`
# (y(t) = exp(−k t), g(t) = exp(−k t)). The control model has the cell ODE only.
@potts_model TwoOde begin
    @kinds medium A
    @parameters k = 0.3
    @variables begin
        y(cell) = 1.0
        g(model) = 1.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ -k * y
        D(g) ~ -k * g
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model OneOde begin
    @kinds medium A
    @parameters k = 0.3
    @variables y(cell) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -k * y
    @sweep Metropolis(; temperature = 1.0)
end
function ode_problem(; two = true, T = Float64, nmcs = 5)
    σ = zeros(Int32, 16, 16)
    σ[3:6, 3:6] .= 1
    σ[10:13, 10:13] .= 2
    M = two ? TwoOde : OneOde
    return PottsProblem(
        M(; name = :ode), [ownership => σ, kind => [:A, :A]], (0, nmcs);
        T, capacity = 8, seed = 3, ode_solver = Adaptive(Rodas5P(); reltol = 1.0e-8, abstol = 1.0e-10)
    )
end
ode_exact(t) = exp(-0.3 * t)
# A digest of an array's bits (FNV-1a over the elements; independent of `Base.hash`).
bits(x::Float64) = reinterpret(UInt64, x)
bits(x::Float32) = UInt64(reinterpret(UInt32, x))
bits(x::Int32) = UInt64(reinterpret(UInt32, x))
digest(a) = foldl((h, x) -> (h ⊻ bits(x)) * 0x00000100000001b3, vec(Array(a)); init = 0xcbf29ce484222325)
# Does a type contain a Float64 leaf (fields, recursively)?
function hasf64(T::Type, seen = Set{Any}())
    T === Float64 && return true
    (T in seen || !isconcretetype(T)) && return false
    push!(seen, T)
    return any(t -> hasf64(t, seen), fieldtypes(T))
end
kernel_types(integ) = (typeof(integ.p), typeof(integ.state), typeof(integ.ctx), typeof(integ.kf))
# A kernel that touches a Float64 (the control of (6): Metal must refuse to compile it)
@kernel function f64_kernel!(a)
    i = @index(Global, Linear)
    a[i] = Float32(Float64(a[i]) * 1.000000001)
end
# ---------------------------------------------------------------------------------------
# GPU-wait instrumentation, as in `test/transfer_counts_tests.jl` and `device_lifecycle_tests.jl`:
# `Metal.wait_cmdbuf!` gains a counter; the queue-depth back-pressure of
# `wait_oldest_cleanup!` is excluded. The bodies copy Metal.jl 1.10.0's, hence the version
# pin. Each file instruments at its own top level just before its testsets, so whichever is
# included last owns the methods while its tests run.
const WAITS = Ref(0)
const INFLIGHT = Ref(false)
function instrument_waits!()
    M = PottsDevices.device_package()
    @eval M function wait_oldest_cleanup!(bq::BatchedCommandQueue)
        isempty(bq.cleanups) && return
        cmdbuf = first(bq.cleanups).cmdbuf
        $(INFLIGHT)[] = true
        try
            wait_cmdbuf!(cmdbuf)
        finally
            $(INFLIGHT)[] = false
        end
        drain_cleanups!(bq)
        return
    end
    @eval M function wait_cmdbuf!(cmdbuf::MTL.MTLCommandBufferLike)
        $(INFLIGHT)[] || ($(WAITS)[] += 1)
        is_completed(cmdbuf) && return
        precompiling = ccall(:jl_generating_output, Cint, ()) != 0
        if use_nonblocking_synchronization && !precompiling
            spinning_synchronization(cmdbuf) || yielding_synchronization(cmdbuf)
        else
            wait_completed(cmdbuf)
        end
        return
    end
    return nothing
end
# the wait counter wraps Metal.jl internals: Metal only (D-157)
const ON_METAL = ON_DEVICE && PottsDevices.device_name() == "metal"
const METAL_VERSION = ON_METAL ? pkgversion(PottsDevices.device_package()) : nothing
const WAITS_ON = ON_METAL && METAL_VERSION == v"1.10.0"
WAITS_ON && instrument_waits!()
# at top level: the testsets must see the new methods
"""Per-MCS `(counters, waits, launches)` of `nstep` MCS of `integ` (no saves), after a
synchronize; then `(quiet, checkpoint waits)`: the window is quiet when checkpoints before and
after it show no lifecycle event, and the second checkpoint's waits show the wrapper is live."""
function quiet_window!(integ; nstep = 3)
    l0 = lifecycle_total(checkpoint(integ).stats)
    PottsDevices.device_sync()
    out = Tuple{NTuple{3, Int}, Int, Int}[]
    for _ in 1:nstep
        c, w, n = counts(integ.stats), WAITS[], integ.stats.launches
        step!(integ)
        push!(out, (counts(integ.stats) .- c, WAITS[] - w, integ.stats.launches - n))
    end
    w = WAITS[]
    l1 = lifecycle_total(checkpoint(integ).stats)
    return out, l0 == l1, WAITS[] - w
end
function metal_integ(prob; nwarm = 2)
    integ = init(prob, CheckerboardCPM(); backend = PottsDevices.device_backend(), save_start = false, save_everystep = false, save_end = false)
    foreach(_ -> step!(integ), 1:nwarm)
    return integ
end
const ALGS = (SequentialCPM(), CheckerboardCPM())
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "launch fusion: the fixtures (CPU)" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # CPU
    @testset "launch fusion: the fixtures (CPU)" begin
        # the field fixture's σ is frozen, so the oracle's source term is exact
        sol = solve(field_problem(; N = 3), CheckerboardCPM())
        @test all(u -> u.ownership == field_σ(), sol.u)
        # the CopyPhase fixture publishes a scratch through a CopyPhase (what (2) measures)
        prob = pair_problem()
        @test any(ph -> ph isa CorePotts.CopyPhase, prob.f.phases.after_mcs)
        # gate cases build and run; nothing is counted on the CPU
        for (name, make) in gate_cases(Float64)
            integ = init(make(), CheckerboardCPM(); save_start = false, save_everystep = false, save_end = false)
            foreach(_ -> step!(integ), 1:2)
            @test counts(integ.stats) == (0, 0, 0)
            @test integ.stats.launches > 0
        end
    end
end

@testitem "launch fusion (4): two adaptive-ODE phases (CPU: results)" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (4): two adaptive-ODE phases (CPU: results)" begin
        for alg in ALGS
            u = solve(ode_problem(), alg).u[end]
            @test u.cell.y[1:2] ≈ fill(ode_exact(5), 2) rtol = 1.0e-6
            @test u.model.g[1] ≈ ode_exact(5) rtol = 1.0e-6
            @test counts(solve(ode_problem(), alg).stats) == (0, 0, 0)
        end
    end
end

@testitem "launch fusion (5): exactness on the CPU" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (5): exactness on the CPU ($(nameof(typeof(alg))))" for alg in ALGS
        for T in (Float64, Float32), N in (1, 3, 15)
            u = solve(field_problem(; T, N), alg; save_start = false).u[end]
            @test u.site.c == field_oracle(T, N, 4)                       # bitwise
        end
        # negative control: the oracle tells substep counts apart
        @test field_oracle(Float64, 3, 4) != field_oracle(Float64, 15, 4)
        for T in (Float64, Float32), n in (3, 4)
            u = solve(pair_problem(; T, nmcs = n), alg; save_start = false).u[end]
            @test u.cell.y[1:2] == pair_oracle(T, n)
        end
    end
end

@testitem "launch fusion (6): no Float64 in what Float32 kernels receive (CPU builds)" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (6): no Float64 in what Float32 kernels receive (CPU builds)" begin
        for (name, make) in gate_cases(Float32)
            integ = init(make(), CheckerboardCPM(); save_start = false, save_everystep = false, save_end = false)
            @test !any(hasf64, kernel_types(integ))
            any(hasf64, kernel_types(integ)) && @info "launch fusion Float64 leaf" name hasf64.(kernel_types(integ))
        end
        # control: the scan finds the Float64 of a T = Float64 build
        for (name, make) in gate_cases(Float64)
            integ = init(make(), CheckerboardCPM(); save_start = false, save_everystep = false, save_end = false)
            @test any(hasf64, kernel_types(integ))
        end
    end
end

@testitem "launch fusion: the wait wrapper is installed (Metal.jl 1.10.0)" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # Metal
    @testset "launch fusion: the wait wrapper is installed (Metal.jl 1.10.0)" begin
        if ON_METAL
            @test METAL_VERSION == v"1.10.0"
            METAL_VERSION == v"1.10.0" || @error "launch_fusion_tests.jl copies Metal.jl 1.10.0's " *
                "`wait_cmdbuf!`/`wait_oldest_cleanup!`; Metal is $METAL_VERSION: update the copies and the version"
        else
            @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
        end
    end
end

@testitem "(1): a quiet MCS of every gate model makes no sync, transfer or GPU wait on Metal" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "(1): a quiet MCS of every gate model makes no sync, transfer or GPU wait on Metal" begin
        if WAITS_ON
            for (name, make) in gate_cases(Float32)
                integ = metal_integ(make())
                out, quiet, ckwaits = quiet_window!(integ)
                @test quiet                                                  # control: no lifecycle event
                @test ckwaits >= 1                                           # control: the wrapper counts
                @test all(o -> o[1] == (0, 0, 0), out)
                @test all(o -> o[2] == 0, out)
                all(o -> o[1] == (0, 0, 0) && o[2] == 0, out) ||
                    @info "launch fusion quiet MCS (counters, waits, launches)" name out
            end
        else
            @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
        end
    end
end

@testitem "(2): device→device copies make no GPU wait, whatever the substep count" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "(2): device→device copies make no GPU wait, whatever the substep count" begin
        if WAITS_ON
            waits, launches = Dict{Int, Int}(), Dict{Int, Int}()
            for N in (1, 3, 15)
                out, _, ckwaits = quiet_window!(metal_integ(field_problem(; T = Float32, N, nmcs = 10)))
                @test ckwaits >= 1
                @test all(o -> o[1] == (0, 0, 0), out)
                waits[N] = maximum(o -> o[2], out)
                launches[N] = minimum(o -> o[3], out)
            end
            @info "launch fusion field fixture: GPU waits and launches per MCS by substeps" waits launches
            @test launches[15] > launches[3] > launches[1]                  # control: the substeps ran
            @test waits[1] == waits[3] == waits[15]                         # independent of N
            @test all(==(0), values(waits))
            # a generated CopyPhase (the Jacobi scratch of a cell ODE)
            out, _, ckwaits = quiet_window!(metal_integ(pair_problem(; T = Float32, nmcs = 10)))
            @test ckwaits >= 1
            @test all(o -> o[1] == (0, 0, 0) && o[2] == 0, out)
            all(o -> o[2] == 0, out) || @info "launch fusion CopyPhase fixture (counters, waits, launches)" out
            # Merks with 2 and 15 substeps
            mw = Dict{Int, Int}()
            for substeps in (2, 15)
                out, _, _ = quiet_window!(metal_integ(merks_problem(; T = Float32, substeps, nmcs = 10)))
                mw[substeps] = maximum(o -> o[2], out)
            end
            @info "launch fusion Merks: GPU waits per MCS by substeps" mw
            @test mw[2] == mw[15] == 0
        else
            @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
        end
    end
end

@testitem "launch fusion (3): launches per quiet MCS of the gate models on the device" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (3): launches per quiet MCS of the gate models on the device" begin
        if ON_DEVICE
            for (name, make) in gate_cases(Float32)
                integ = metal_integ(make())
                l0 = lifecycle_total(checkpoint(integ).stats)
                ns = Int[]
                for _ in 1:3
                    n = integ.stats.launches
                    step!(integ)
                    push!(ns, integ.stats.launches - n)
                end
                @test lifecycle_total(checkpoint(integ).stats) == l0   # control: quiet
                @test all(>(0), ns)                                        # every quiet MCS launches
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "launch fusion (4): two consecutive adaptive-ODE host phases sync once on the device" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (4): two consecutive adaptive-ODE host phases sync once on the device" begin
        if ON_DEVICE
            host(a) = Array(a)
            syncs = Dict{Bool, Vector{Int}}()
            for two in (false, true)
                integ = metal_integ(ode_problem(; two, T = Float32, nmcs = 10); nwarm = 1)
                syncs[two] = Int[]
                for _ in 1:3
                    s = integ.stats.syncs
                    step!(integ)
                    push!(syncs[two], integ.stats.syncs - s)
                end
                # control: the phases ran (t = 4)
                @test host(integ.state.cell.y)[1:2] ≈ fill(Float32(ode_exact(4)), 2) rtol = 1.0e-4
                two && @test host(integ.state.model.g)[1] ≈ Float32(ode_exact(4)) rtol = 1.0e-4
            end
            @info "launch fusion syncs per MCS: one / two adaptive phases" one = syncs[false] two = syncs[true]
            @test all(==(1), syncs[false])                                  # control: the counter is live
            @test all(==(1), syncs[true])
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "launch fusion (5): exactness on the device" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (5): exactness on the device" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            for N in (1, 3, 15)
                u = solve(field_problem(; T = Float32, N), alg; backend, save_start = false).u[end]
                @test Array(u.site.c) == field_oracle(Float32, N, 4)    # bitwise
            end
            for n in (3, 4)
                u = solve(pair_problem(; T = Float32, nmcs = n), alg; backend, save_start = false).u[end]
                @test Array(u.cell.y)[1:2] == pair_oracle(Float32, n)
            end
            m = solve(merks_problem(; T = Float32), alg; backend, save_start = false).u[end]
            c = solve(merks_problem(; T = Float32), alg; save_start = false).u[end]
            # the device checkerboard is not reproducible (D-271, user ruling 2026-11-04): it runs and
            # keeps the model's invariants (labels in range, every cell alive, a finite field)
            σm = Array(m.ownership)
            @test size(σm) == size(c.ownership) && all(v -> 0 <= v <= maximum(c.ownership), σm)
            @test Set(filter(!=(0), unique(σm))) == Set(filter(!=(0), unique(c.ownership)))
            @test all(isfinite, Array(m.site.c))
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "launch fusion (6): no Float64 reaches a device kernel (gate models)" setup = [LaunchFusionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "launch fusion (6): no Float64 reaches a device kernel (gate models)" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            for (name, make) in gate_cases(Float32)
                integ = metal_integ(make())
                @test !any(hasf64, kernel_types(integ))
                foreach(_ -> step!(integ), 1:2)
                @test count(>(0), Array(current_state(integ).cell.volume)) > 0           # ran and saved on the device
            end
            # control: Metal refuses a kernel that touches a Float64 (a leak fails loudly). ROCm
            # has doubles; there the no-`double` IR check (test/device_ir.jl, D-157) is the control.
            if PottsDevices.device_name() == "metal"
                a = PottsDevices.device_array(ones(Float32, 8))
                err = try
                    f64_kernel!(backend)(a; ndrange = 8)
                    CorePotts.KernelAbstractions.synchronize(backend)
                    nothing
                catch e
                    e
                end
                @test err !== nothing && nameof(typeof(err)) === :InvalidIRError    # GPUCompiler's IR check
            else
                @test_skip "device (POTTS_GPU=metal; Metal's Float64 refusal)"
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end
