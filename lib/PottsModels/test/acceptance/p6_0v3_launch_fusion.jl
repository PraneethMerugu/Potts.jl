# P6.0v3 (ROADMAP Phase 6, step 0), including P6.0v8: launch fusion, Metal codegen fixes and
# no hidden GPU waits. Decisions: D-085 (counters), D-089/D-096 (device lifecycle), D-090
# (Metal timings), D-092 (P6.0v2; its review filed the double sync of item 4), D-098 (Merks'
# 15 field substeps). Audit: `docs/design/research/gpu-host-transfer-audit.md` §2.1, §6 T3,
# §8 (F1–F6, §8.2, §8.3, §8.4), §9–§11.
#
# What is pinned (Metal: POTTS_GPU=metal with Metal loaded, Float32, CheckerboardCPM):
#  (1) P6.0v8. A quiet MCS of every gate model (`benchmark/gate.jl` cases, built the same
#      way and at the same sizes: Graner–Glazier 72, Wortel Act 100, Merks 100 with 15
#      field substeps, OpenVT monolayer 100, Akeeb 99×60) makes 0 syncs, 0 transfers, 0 B
#      AND 0 GPU waits. GPU waits are the calls of Metal.jl's `wait_cmdbuf!`, counted with
#      the test-only wrapper of `test/transfer_counts.jl` (Metal.jl 1.10.0 bodies; the
#      back-pressure of `wait_oldest_cleanup!`, the host running ahead of a busy GPU, is not
#      a wait). Controls: the window is quiet (checkpoints around it show no lifecycle
#      event) and the wrapper counts the waits of the checkpoint after the window.
#  (2) Every device→device copy of the step path makes no GPU wait: a `FieldStep` fixture
#      with N = 1, 3, 15 substeps, a Potts cell-ODE fixture whose scratch is published by a
#      `CopyPhase` (Jacobi cross-cell read, P6.0n), and Merks with 2 and 15 substeps: waits
#      per MCS are the same for every N, and 0. Control: the launches grow with N (the
#      substeps ran).
#  (3) Launches. `stats.launches` of a quiet MCS of each gate model (gate sizes) lies in
#      [floor, bound], from the audit's §8.1 table and §11 after the fusions §10 assigns to
#      P6.0v3 (F1, F2, F3, T3; F5 is illegal and F6 is unassigned). Measured today on Metal
#      (and the same on the CPU): GG 8, Wortel 33, Merks 38, OpenVT 10, Akeeb 14.
#        Graner–Glazier 72  bound 8  = 4 colors × (propose + commit). No fusion applies (F5
#                           illegal: commit needs every proposal of its color, Metal has
#                           no grid barrier). Floor 8.
#        Wortel Act 100     bound 33 = 16 colors × 2 (F5) + the `act` decay `SitePhase`
#                           (F6: necessary as the model is written, not assigned). Floor 32.
#        Merks 100          bound 38 = 4 colors × 2 + 15 substeps × (field kernel + copy).
#                           F2 replaces Metal's waiting `copyto!` blit (counted as a launch
#                           today) by a KA copy kernel: one launch for one, the count stays;
#                           a ping-pong buffer may go lower. Floor 8 + 15 (one field kernel
#                           per substep).
#        OpenVT mono. 100   bound 9  = 4 colors × 2 + one launch for the `V_target`
#                           `CellPhase` and the lifecycle together (F1: the after-MCS cell
#                           phase fused with the trigger; legal, the trigger reads `volume`,
#                           which the phase does not write; T3's `fill!` is already gone
#                           under D-089, §11). Today 10 (phase + fused lifecycle kernel).
#                           Floor 9.
#        Akeeb 99×60        bound 13 = 6 colors × 2 + one launch for the `V_target`/`clock`
#                           `CellPhase` and the lifecycle (F1; legal, the trigger reads the
#                           cell's own `clock`, `volume` and parameters only). Today 14.
#                           Floor 13.
#      The floors keep the launch counter honest: every color still needs its two kernels.
#  (4) P6.0v2 review: an MCS with two consecutive adaptive-ODE host phases (a cell and a
#      model ODE, both `Adaptive`) makes exactly one counted sync (today two; the second
#      waits on an idle queue). Controls: a single adaptive phase makes one sync (the
#      counter is live), and both ODEs follow their analytic solutions.
#  (5) Exactness. On the CPU, bitwise with a fixed seed: the `FieldStep` fixture (σ frozen:
#      T = 0 and every cell at its target volume) equals a plain-Julia explicit-Euler oracle
#      written here, for N = 1, 3, 15, Float64 and Float32, both algorithms; the `CopyPhase`
#      fixture equals its exact oracle (k = 1: the two cells swap their values every MCS);
#      Merks (32², 6 cells, 15 substeps, seed 7, 6 MCS) equals the digests of σ and the field
#      recorded here from the current code (and differs for another seed: the digest is
#      sensitive). On Metal, bitwise too (the current code is: the field step is per-site
#      and the checkerboard sweep's draws are counter-based): the fixtures equal the same
#      oracles, and Merks equals the CPU Float32 run and the recorded Float32 digests.
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
# (14 > 13); (4) fails (2 syncs); (5) and (6) pass (they pin what the fusions must keep).
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P
using Potts.CorePotts.KernelAbstractions: @kernel, @index

const P60V3_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()
p60v3_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)
p60v3_lifecycle_total(s) = sum(f -> getfield(s.lifecycle, f), fieldnames(typeof(s.lifecycle)))

# ---------------------------------------------------------------------------------------
# The gate models, exactly as `benchmark/gate.jl` builds them

function p60v3_gate_cases(T)
    gg = graner_glazier_state()
    return [
        "graner_glazier_72" => () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 10^6); T),
        "wortel_act_100" => () -> (σ = zeros(Int32, 100, 100); σ[40:62, 40:62] .= 1;
            PottsProblem(WortelAct(; name = :w, lattice = (100, 100)), [ownership => σ, kind => [:cell]], (0, 10^6); T)),
        "merks_100" => () -> PottsProblem(MerksVasculogenesis(; name = :m, lattice = (100, 100)),
            merks_state(; lattice = (100, 100), n = 25), (0, 10^6); T,
            field_solver = ExplicitEuler(substeps = 15, lower = 0.0)),
        "openvt_monolayer_100" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (100, 100), τ = 1e6),
            openvt_monolayer_state(; lattice = (100, 100)), (0, 10^6); T, capacity = 64),
        "akeeb_99x60" => () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (0, 10^6); T, capacity = 1000),
    ]
end
# (floor, bound) of `stats.launches` per quiet MCS; derivations in the header, (3)
const P60V3_LAUNCHES = Dict(
    "graner_glazier_72" => (8, 8),
    "wortel_act_100" => (32, 33),
    "merks_100" => (8 + 15, 8 + 2 * 15),
    "openvt_monolayer_100" => (9, 9),
    "akeeb_99x60" => (13, 13),
)

# ---------------------------------------------------------------------------------------
# FieldStep fixture (CorePotts level). One 5×5 cell at its target volume, T = 0: every copy
# raises the energy and is rejected, so σ never changes and the field's source is known.
# rate(c)_i = D (c_{i-1} + c_{i+1} − 2 c_i) + s [σ_i ≠ 0] − k c_i over the linear index
# (periodic), explicit Euler in N substeps per MCS, clipped below at 0.

const P60V3_FDIMS = (16, 16)
p60v3_field_rate(st, p, ctx, key, mcs, i, c) = (n = length(c); l = i == 1 ? n : i - 1; r = i == n ? 1 : i + 1;
    p.D * (c[l] + c[r] - 2 * c[i]) + p.s * (st.σ[i] != 0) - p.k * c[i])
p60v3_field_c0(T) = T[sin(Float64(i))^2 for i in 1:prod(P60V3_FDIMS)]
function p60v3_field_σ()
    σ = zeros(Int32, P60V3_FDIMS)
    σ[5:9, 5:9] .= 1
    return σ
end
p60v3_field_params(T) = (; λ = T(1), V0 = T(25), T = T(0), D = T(0.2), s = T(0.01), k = T(0.003))
function p60v3_field_problem(; T = Float64, N = 3, nmcs = 4)
    site = (; c = reshape(p60v3_field_c0(T), P60V3_FDIMS), c__next = zeros(T, P60V3_FDIMS))
    u0 = CorePotts.initial_state(p60v3_field_σ(), Int32[1]; site)
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    ph = (CorePotts.FieldStep((:site, :c) => (:site, :c__next), p60v3_field_rate; dt = T(1), substeps = N, lower = T(0)),)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T, phases = CorePotts.Phases(; after_mcs = ph))
    return CorePotts.PottsProblem(f, u0, CorePotts.Lattice(P60V3_FDIMS), (0, nmcs), p60v3_field_params(T))
end
"""The field after `nmcs` MCS of N explicit-Euler substeps, in plain Julia (same operations,
same order, so bitwise equal to a correct implementation)."""
function p60v3_field_oracle(T, N, nmcs)
    c = p60v3_field_c0(T)
    σ = vec(p60v3_field_σ())
    p = p60v3_field_params(T)
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
    return reshape(c, P60V3_FDIMS)
end

# CopyPhase fixture (Potts level): a cell ODE that reads the other cell's unknown is Jacobi,
# so the generated code writes the scratch `y__ode` and publishes it with a `CopyPhase`
# (P6.0n). k = 1, one explicit-Euler step per MCS: y₁ ← y₂ and y₂ ← y₁ exactly. Both cells
# sit at their target volume with T ≈ 0, so σ does not matter.
@potts_model P60v3Pair begin
    @kinds medium A
    @parameters k = 1.0
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ k * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0e-6)
end
const P60V3_Y0 = (1.0, 3.0)
function p60v3_pair_problem(; T = Float64, nmcs = 4)
    σ = zeros(Int32, 12, 8)
    σ[2:5, 2:5] .= 1
    σ[8:11, 4:7] .= 2
    return PottsProblem(P60v3Pair(; name = :p60v3pair), [ownership => σ, kind => [:A, :A], :y => collect(P60V3_Y0)], (0, nmcs);
        T, ode_solver = ExplicitEuler())
end
p60v3_pair_oracle(T, nmcs) = T.(isodd(nmcs) ? reverse(collect(P60V3_Y0)) : collect(P60V3_Y0))

# Merks at a small size with the paper's 15 substeps (or `substeps`), a fixed seed.
p60v3_merks_problem(; T = Float64, substeps = 15, seed = 7, nmcs = 6) =
    PottsProblem(MerksVasculogenesis(; name = :m, lattice = (32, 32)), merks_state(; lattice = (32, 32), n = 6, side = 7),
        (0, nmcs); T, seed, field_solver = ExplicitEuler(; substeps, lower = 0.0))

# Two adaptive-ODE phases in one MCS: a cell ODE and a model ODE, both `Adaptive`
# (y(t) = exp(−k t), g(t) = exp(−k t)). The control model has the cell ODE only.
@potts_model P60v3TwoOde begin
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
@potts_model P60v3OneOde begin
    @kinds medium A
    @parameters k = 0.3
    @variables y(cell) = 1.0
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ -k * y
    @sweep Metropolis(; temperature = 1.0)
end
function p60v3_ode_problem(; two = true, T = Float64, nmcs = 5)
    σ = zeros(Int32, 16, 16)
    σ[3:6, 3:6] .= 1
    σ[10:13, 10:13] .= 2
    M = two ? P60v3TwoOde : P60v3OneOde
    return PottsProblem(M(; name = :p60v3ode), [ownership => σ, kind => [:A, :A]], (0, nmcs);
        T, capacity = 8, seed = 3, ode_solver = Adaptive(Rodas5P(); reltol = 1e-8, abstol = 1e-10))
end
p60v3_ode_exact(t) = exp(-0.3 * t)

# A digest of an array's bits (FNV-1a over the elements; independent of `Base.hash`).
p60v3_bits(x::Float64) = reinterpret(UInt64, x)
p60v3_bits(x::Float32) = UInt64(reinterpret(UInt32, x))
p60v3_bits(x::Int32) = UInt64(reinterpret(UInt32, x))
p60v3_digest(a) = foldl((h, x) -> (h ⊻ p60v3_bits(x)) * 0x00000100000001b3, vec(Array(a)); init = 0xcbf29ce484222325)
# Recorded from the current code (feat/p6-0v3 at d111e625) for `p60v3_merks_problem(; T)`
# after 6 MCS with `CheckerboardCPM()`: (σ, field c). Metal (Float32) equals the CPU's.
const P60V3_MERKS_DIGESTS = Dict(
    Float64 => (0xf1d750bea912b50c, 0x5600efddf14d35a6),
    Float32 => (0xf1d750bea912b50c, 0x2b64b4f3b29d28e5),
)

# Does a type contain a Float64 leaf (fields, recursively)?
function p60v3_hasf64(T::Type, seen = Set{Any}())
    T === Float64 && return true
    (T in seen || !isconcretetype(T)) && return false
    push!(seen, T)
    return any(t -> p60v3_hasf64(t, seen), fieldtypes(T))
end
p60v3_kernel_types(integ) = (typeof(integ.p), typeof(integ.state), typeof(integ.ctx), typeof(integ.kf))

# A kernel that touches a Float64 (the control of (6): Metal must refuse to compile it)
@kernel function p60v3_f64_kernel!(a)
    i = @index(Global, Linear)
    a[i] = Float32(Float64(a[i]) * 1.000000001)
end

# ---------------------------------------------------------------------------------------
# GPU-wait instrumentation, as in `test/transfer_counts.jl` and `p6_0v1_device_lifecycle.jl`:
# `Metal.wait_cmdbuf!` gains a counter; the queue-depth back-pressure of
# `wait_oldest_cleanup!` is excluded. The bodies copy Metal.jl 1.10.0's, hence the version
# pin. Each file instruments at its own top level just before its testsets, so whichever is
# included last owns the methods while its tests run.
const P60V3_WAITS = Ref(0)
const P60V3_INFLIGHT = Ref(false)
function p60v3_instrument_waits!()
    M = Main.PottsDevices.device_package()
    @eval M function wait_oldest_cleanup!(bq::BatchedCommandQueue)
        isempty(bq.cleanups) && return
        cmdbuf = first(bq.cleanups).cmdbuf
        $(P60V3_INFLIGHT)[] = true
        try
            wait_cmdbuf!(cmdbuf)
        finally
            $(P60V3_INFLIGHT)[] = false
        end
        drain_cleanups!(bq)
        return
    end
    @eval M function wait_cmdbuf!(cmdbuf::MTL.MTLCommandBufferLike)
        $(P60V3_INFLIGHT)[] || ($(P60V3_WAITS)[] += 1)
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
const P60V3_ON_METAL = P60V3_ON_DEVICE && Main.PottsDevices.device_name() == "metal"
const P60V3_METAL_VERSION = P60V3_ON_METAL ? pkgversion(Main.PottsDevices.device_package()) : nothing
const P60V3_WAITS_ON = P60V3_ON_METAL && P60V3_METAL_VERSION == v"1.10.0"
P60V3_WAITS_ON && p60v3_instrument_waits!()     # at top level: the testsets must see the new methods

"""Per-MCS `(counters, waits, launches)` of `nstep` MCS of `integ` (no saves), after a
synchronize; then `(quiet, checkpoint waits)`: the window is quiet when checkpoints before and
after it show no lifecycle event, and the second checkpoint's waits show the wrapper is live."""
function p60v3_window!(integ; nstep = 3)
    l0 = p60v3_lifecycle_total(checkpoint(integ).stats)
    Main.PottsDevices.device_sync()
    out = Tuple{NTuple{3, Int}, Int, Int}[]
    for _ in 1:nstep
        c, w, n = p60v3_counts(integ.stats), P60V3_WAITS[], integ.stats.launches
        step!(integ)
        push!(out, (p60v3_counts(integ.stats) .- c, P60V3_WAITS[] - w, integ.stats.launches - n))
    end
    w = P60V3_WAITS[]
    l1 = p60v3_lifecycle_total(checkpoint(integ).stats)
    return out, l0 == l1, P60V3_WAITS[] - w
end
function p60v3_metal_integ(prob; nwarm = 2)
    integ = init(prob, CheckerboardCPM(); backend = Main.PottsDevices.device_backend(), save_start = false, save_end = false)
    foreach(_ -> step!(integ), 1:nwarm)
    return integ
end

const P60V3_ALGS = (SequentialCPM(), CheckerboardCPM())

# =======================================================================================
# CPU

@testset "P6.0v3: the fixtures (CPU)" begin
    # the field fixture's σ is frozen, so the oracle's source term is exact
    sol = solve(p60v3_field_problem(; N = 3), CheckerboardCPM())
    @test all(u -> u.σ == p60v3_field_σ(), sol.u)
    # the CopyPhase fixture publishes a scratch through a CopyPhase (what (2) measures)
    prob = p60v3_pair_problem()
    @test any(ph -> ph isa CorePotts.CopyPhase, prob.f.phases.after_mcs)
    # gate cases build and run; nothing is counted on the CPU
    for (name, make) in p60v3_gate_cases(Float64)
        integ = init(make(), CheckerboardCPM(); save_start = false, save_end = false)
        foreach(_ -> step!(integ), 1:2)
        @test p60v3_counts(integ.stats) == (0, 0, 0)
        @test integ.stats.launches > 0
    end
end

@testset "P6.0v3 (4): two adaptive-ODE phases (CPU: results)" begin
    for alg in P60V3_ALGS
        u = solve(p60v3_ode_problem(), alg).u[end]
        @test u.cell.y[1:2] ≈ fill(p60v3_ode_exact(5), 2) rtol = 1e-6
        @test u.model.g[1] ≈ p60v3_ode_exact(5) rtol = 1e-6
        @test p60v3_counts(solve(p60v3_ode_problem(), alg).stats) == (0, 0, 0)
    end
end

@testset "P6.0v3 (5): exactness on the CPU ($(nameof(typeof(alg))))" for alg in P60V3_ALGS
    for T in (Float64, Float32), N in (1, 3, 15)
        u = solve(p60v3_field_problem(; T, N), alg; save_start = false).u[end]
        @test u.site.c == p60v3_field_oracle(T, N, 4)                       # bitwise
    end
    # negative control: the oracle tells substep counts apart
    @test p60v3_field_oracle(Float64, 3, 4) != p60v3_field_oracle(Float64, 15, 4)
    for T in (Float64, Float32), n in (3, 4)
        u = solve(p60v3_pair_problem(; T, nmcs = n), alg; save_start = false).u[end]
        @test u.cell.y[1:2] == p60v3_pair_oracle(T, n)
    end
    if alg isa CheckerboardCPM
        for T in (Float64, Float32)
            u = solve(p60v3_merks_problem(; T), alg; save_start = false).u[end]
            @test (p60v3_digest(u.σ), p60v3_digest(u.site.c)) == P60V3_MERKS_DIGESTS[T]
            v = solve(p60v3_merks_problem(; T, seed = 8), alg; save_start = false).u[end]
            @test p60v3_digest(v.σ) != P60V3_MERKS_DIGESTS[T][1]           # the digest is sensitive
        end
    end
end

@testset "P6.0v3 (6): no Float64 in what Float32 kernels receive (CPU builds)" begin
    for (name, make) in p60v3_gate_cases(Float32)
        integ = init(make(), CheckerboardCPM(); save_start = false, save_end = false)
        @test !any(p60v3_hasf64, p60v3_kernel_types(integ))
        any(p60v3_hasf64, p60v3_kernel_types(integ)) && @info "P6.0v3 Float64 leaf" name p60v3_hasf64.(p60v3_kernel_types(integ))
    end
    # control: the scan finds the Float64 of a T = Float64 build
    for (name, make) in p60v3_gate_cases(Float64)
        integ = init(make(), CheckerboardCPM(); save_start = false, save_end = false)
        @test any(p60v3_hasf64, p60v3_kernel_types(integ))
    end
end

# =======================================================================================
# Metal

@testset "P6.0v3: the wait wrapper is installed (Metal.jl 1.10.0)" begin
    if P60V3_ON_METAL
        @test P60V3_METAL_VERSION == v"1.10.0"
        P60V3_METAL_VERSION == v"1.10.0" || @error "p6_0v3_launch_fusion.jl copies Metal.jl 1.10.0's " *
            "`wait_cmdbuf!`/`wait_oldest_cleanup!`; Metal is $P60V3_METAL_VERSION: update the copies and the version"
    else
        @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
    end
end

@testset "P6.0v8 (1): a quiet MCS of every gate model makes no sync, transfer or GPU wait on Metal" begin
    if P60V3_WAITS_ON
        for (name, make) in p60v3_gate_cases(Float32)
            integ = p60v3_metal_integ(make())
            out, quiet, ckwaits = p60v3_window!(integ)
            @test quiet                                                  # control: no lifecycle event
            @test ckwaits >= 1                                           # control: the wrapper counts
            @test all(o -> o[1] == (0, 0, 0), out)
            @test all(o -> o[2] == 0, out)
            all(o -> o[1] == (0, 0, 0) && o[2] == 0, out) ||
                @info "P6.0v8 quiet MCS (counters, waits, launches)" name out
        end
    else
        @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
    end
end

@testset "P6.0v8 (2): device→device copies make no GPU wait, whatever the substep count" begin
    if P60V3_WAITS_ON
        waits, launches = Dict{Int, Int}(), Dict{Int, Int}()
        for N in (1, 3, 15)
            out, _, ckwaits = p60v3_window!(p60v3_metal_integ(p60v3_field_problem(; T = Float32, N, nmcs = 10)))
            @test ckwaits >= 1
            @test all(o -> o[1] == (0, 0, 0), out)
            waits[N] = maximum(o -> o[2], out)
            launches[N] = minimum(o -> o[3], out)
        end
        @info "P6.0v8 FieldStep fixture: GPU waits and launches per MCS by substeps" waits launches
        @test launches[15] > launches[3] > launches[1]                  # control: the substeps ran
        @test waits[1] == waits[3] == waits[15]                         # independent of N
        @test all(==(0), values(waits))
        # a generated CopyPhase (the Jacobi scratch of a cell ODE)
        out, _, ckwaits = p60v3_window!(p60v3_metal_integ(p60v3_pair_problem(; T = Float32, nmcs = 10)))
        @test ckwaits >= 1
        @test all(o -> o[1] == (0, 0, 0) && o[2] == 0, out)
        all(o -> o[2] == 0, out) || @info "P6.0v8 CopyPhase fixture (counters, waits, launches)" out
        # Merks with 2 and 15 substeps
        mw = Dict{Int, Int}()
        for substeps in (2, 15)
            out, _, _ = p60v3_window!(p60v3_metal_integ(p60v3_merks_problem(; T = Float32, substeps, nmcs = 10)))
            mw[substeps] = maximum(o -> o[2], out)
        end
        @info "P6.0v8 Merks: GPU waits per MCS by substeps" mw
        @test mw[2] == mw[15] == 0
    else
        @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
    end
end

@testset "P6.0v3 (3): launches per quiet MCS of the gate models on the device" begin
    if P60V3_ON_DEVICE
        for (name, make) in p60v3_gate_cases(Float32)
            integ = p60v3_metal_integ(make())
            l0 = p60v3_lifecycle_total(checkpoint(integ).stats)
            ns = Int[]
            for _ in 1:3
                n = integ.stats.launches
                step!(integ)
                push!(ns, integ.stats.launches - n)
            end
            @test p60v3_lifecycle_total(checkpoint(integ).stats) == l0   # control: quiet
            lo, hi = P60V3_LAUNCHES[name]
            @test all(n -> lo <= n <= hi, ns)
            all(n -> lo <= n <= hi, ns) || @info "P6.0v3 launches per quiet MCS" name ns floor = lo bound = hi
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

@testset "P6.0v3 (4): two consecutive adaptive-ODE host phases sync once on the device" begin
    if P60V3_ON_DEVICE
        host(a) = Array(a)
        syncs = Dict{Bool, Vector{Int}}()
        for two in (false, true)
            integ = p60v3_metal_integ(p60v3_ode_problem(; two, T = Float32, nmcs = 10); nwarm = 1)
            syncs[two] = Int[]
            for _ in 1:3
                s = integ.stats.syncs
                step!(integ)
                push!(syncs[two], integ.stats.syncs - s)
            end
            # control: the phases ran (t = 4)
            @test host(integ.state.cell.y)[1:2] ≈ fill(Float32(p60v3_ode_exact(4)), 2) rtol = 1e-4
            two && @test host(integ.state.model.g)[1] ≈ Float32(p60v3_ode_exact(4)) rtol = 1e-4
        end
        @info "P6.0v3 syncs per MCS: one / two adaptive phases" one = syncs[false] two = syncs[true]
        @test all(==(1), syncs[false])                                  # control: the counter is live
        @test all(==(1), syncs[true])
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

@testset "P6.0v3 (5): exactness on the device" begin
    if P60V3_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM()
        for N in (1, 3, 15)
            u = solve(p60v3_field_problem(; T = Float32, N), alg; backend, save_start = false).u[end]
            @test Array(u.site.c) == p60v3_field_oracle(Float32, N, 4)    # bitwise
        end
        for n in (3, 4)
            u = solve(p60v3_pair_problem(; T = Float32, nmcs = n), alg; backend, save_start = false).u[end]
            @test Array(u.cell.y)[1:2] == p60v3_pair_oracle(Float32, n)
        end
        m = solve(p60v3_merks_problem(; T = Float32), alg; backend, save_start = false).u[end]
        c = solve(p60v3_merks_problem(; T = Float32), alg; save_start = false).u[end]
        @test Array(m.σ) == c.σ && Array(m.site.c) == c.site.c          # bitwise, CPU = device
        @test (p60v3_digest(m.σ), p60v3_digest(m.site.c)) == P60V3_MERKS_DIGESTS[Float32]
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

@testset "P6.0v3 (6): no Float64 reaches a device kernel (gate models)" begin
    if P60V3_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        for (name, make) in p60v3_gate_cases(Float32)
            integ = p60v3_metal_integ(make())
            @test !any(p60v3_hasf64, p60v3_kernel_types(integ))
            foreach(_ -> step!(integ), 1:2)
            @test count(>(0), Array(integ.u.cell.volume)) > 0           # ran and saved on the device
        end
        # control: Metal refuses a kernel that touches a Float64 (a leak fails loudly). ROCm
        # has doubles; there the no-`double` IR check (test/device_ir.jl, D-157) is the control.
        if Main.PottsDevices.device_name() == "metal"
            a = Main.PottsDevices.device_array(ones(Float32, 8))
            err = try
                p60v3_f64_kernel!(backend)(a; ndrange = 8)
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
