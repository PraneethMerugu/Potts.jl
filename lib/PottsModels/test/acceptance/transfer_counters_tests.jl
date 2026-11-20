# GPU host-transfer audit and instrumentation.
# This file checks the counters, the current baseline and the audit document; the zero-transfer
# targets of the later device work are checked with that work (`device_lifecycle_tests.jl`).
#
# The counters. Every device→host and host→device copy and every device synchronize that
# the integrator makes (`init`, `step!`, saves, the lifecycle, phases, generated code) goes
# through one helper that counts into `integ.stats`, beside `stats.launches`:
#   stats.syncs           explicit device synchronizations (`KernelAbstractions.synchronize`)
#   stats.transfers       host↔device copies, both directions; one contiguous array copy is
#                         one transfer (`Array(a)`, `copyto!(dev, host)`, `copyto!(host, dev)`,
#                         and each array leaf of an `Adapt.adapt(Array, …)` snapshot)
#   stats.transfer_bytes  bytes moved by those copies (`sizeof` of the device array copied)
# Device→device copies (`CopyPhase`, the field double buffer) and device-side fills are not
# transfers. On the CPU backend nothing is a transfer and nothing is counted: every counter
# stays 0 (a host `deepcopy` snapshot is not a transfer). The counters are `Int`, start at 0,
# add under `merge` (ensemble totals) like the other fields of `PottsStats`.
#
# Expected counts on Metal. (a) and (b) are exact and are also the long-term targets
# ((a) held at the first version: 1554d56, plus the frozen-kind mask, whose `refresh_frozen!`
# returns before synchronizing when nothing is frozen, as in every fixture here; (b) was
# amended under D-089):
#  (a) A quiet MCS of a gate model without a lifecycle (Graner–Glazier, Wortel Act, Merks
#      with the explicit field solver): 0 syncs, 0 transfers. `CheckerboardCPM` reads its
#      status back only at a save; the field step copies device to device.
#  (b) A quiet MCS (no lifecycle event) of a model with a lifecycle (OpenVT monolayer,
#      Akeeb, the division fixture after MCS 0): 0 syncs, 0 transfers, 0 bytes (D-089: the
#      lifecycle is planned on the device, with no trigger read-back; D-035's 1 sync,
#      1 transfer, 4 bytes event-count readback is withdrawn on GPU backends).
# (c) and (d) are invariants that survive the device lifecycle work (their exact current-path counts are an
# ordinary regression test that it updates):
#  (c) The division fixture (every cell divides at MCS 0) divides both cells at MCS 0, read
#      at a `checkpoint` (a host read point: under D-089 `stats.lifecycle` is exact only at
#      saves, the end of `solve!`, `checkpoint` and `current_state(integ)`, and the event MCS has no
#      host traffic bound here; amended under D-089).
#  (d) An MCS running a `HostPhase` (host code over host copies) transfers: transfers ≥ 1.
#  Counters never decrease from one MCS to the next; a save (`current_state(integ)`) is counted (lower
#  bounds: it synchronizes and copies σ and every cell column down).
# The audit document has a section per known starting point of the transfer work.
#
# Today this fails with `FieldError: type PottsStats has no field transfers` (and `syncs`,
# `transfer_bytes`).

@testsetup module TransferCountersSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
const COUNTERS = (:syncs, :transfers, :transfer_bytes)
transfer_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)
const ON_DEVICE = PottsDevices.on_device()
# ---------------------------------------------------------------------------------------
# Fixtures

# Division fixture: every cell of kind A divides at MCS 0 (and only then), plane normal
# (1, 0). T = 0 and a volume constraint of weight 100 at V = 8 reject every copy of MCS 0,
# so both 4×2 cells still have 8 sites at the lifecycle and split 4 | 4 (independent of the
# RNG). Later MCS are quiet (the trigger fails).
@potts_model Divide begin
    @kinds medium A
    @variables m(cell) = 1.0
    @lattice Lattice((16, 8))
    @energy cells => 100 * (volume - 8)^2
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 0.0)
end
const CAPACITY = 6
function divide_problem(; T = Float64, tspan = (0, 4))
    σ = zeros(Int32, 16, 8)
    σ[3:6, 2:3] .= 1
    σ[10:13, 5:6] .= 2
    return PottsProblem(
        Divide(; name = :transfer_counters), [ownership => σ, kind => [:A, :A]], tspan;
        T, capacity = CAPACITY
    )
end
# HostPhase fixture (CorePotts level): a no-op host phase after every sweep.
function hostphase_problem(; T = Float64)
    σ = zeros(Int32, 12, 12)
    σ[3:6, 3:6] .= 1
    σ[8:11, 7:10] .= 2
    u0 = CorePotts.initial_state(σ, Int32[1, 1]; cell = (; x = zeros(T, 2), y = zeros(T, 2)))
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    f = CorePotts.CPMFunction(
        dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = CorePotts.Phases(; after_mcs = (CorePotts.HostPhase((cell, st, p, ctx, mcs) -> nothing),))
    )
    return CorePotts.PottsProblem(f, u0, CorePotts.Lattice(size(σ)), (0, 4), (; λ = T(1), V0 = T(16), T = T(2)))
end
# The gate models (benchmark/gate.jl) at small sizes. `lifecycle`: has a lifecycle.
function gate_models(T)
    gg = graner_glazier_state()
    w = zeros(Int32, 32, 32); w[12:20, 12:20] .= 1
    return [
        ("Graner–Glazier", false, () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 6); T)),
        ("Wortel Act", false, () -> PottsProblem(WortelAct(; name = :w, lattice = (32, 32)), [ownership => w, kind => [:cell]], (0, 6); T)),
        (
            "Merks", false, () -> PottsProblem(
                MerksVasculogenesis(; name = :m, lattice = (32, 32)),
                merks_state(; lattice = (32, 32), n = 6, side = 7), (0, 6); T, field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)
            ),
        ),
        (
            "OpenVT monolayer", true, () -> PottsProblem(
                OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24), τ = 1.0e6),
                openvt_monolayer_state(; lattice = (24, 24)), (0, 6); T, capacity = 64
            ),
        ),
        (
            "Akeeb", true, () -> PottsProblem(
                AkeebInvasion(; name = :a, lattice = (99, 60)),
                akeeb_state(; lattice = (99, 60)), (0, 6); T, capacity = 1000
            ),
        ),
    ]
end
lifecycle_total(s) = sum(f -> getfield(s.lifecycle, f), fieldnames(typeof(s.lifecycle)))
"""Per-MCS counter deltas of `step!` (no saves): a vector of `(quiet, (syncs, transfers, bytes))`.
The window is quiet when a `checkpoint` (a host read point) before and after it shows
no lifecycle event; then every MCS in it is quiet, otherwise none is counted as quiet. The
checkpoints lie outside the measured deltas."""
function step_deltas(prob, alg; backend, nwarm = 1, nstep = 4)
    integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
    for _ in 1:nwarm
        step!(integ)
    end
    l0 = lifecycle_total(checkpoint(integ).stats)
    out = NTuple{3, Int}[]
    for _ in 1:nstep
        c0 = transfer_counts(integ.stats)
        step!(integ)
        push!(out, transfer_counts(integ.stats) .- c0)
    end
    quiet = lifecycle_total(checkpoint(integ).stats) == l0
    return [(quiet, d) for d in out]
end
"""Counter triples after each of `n` steps of `integ`."""
counter_trace!(integ, n) = [(step!(integ); transfer_counts(integ.stats)) for _ in 1:n]
nondecreasing(tr) = all(i -> all(tr[i] .<= tr[i + 1]), 1:(length(tr) - 1))
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "transfer counters: they exist and are zero on the CPU" setup = [TransferCountersSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    @testset "transfer counters: they exist and are zero on the CPU" begin
        @test all(in(fieldnames(CorePotts.PottsStats)), COUNTERS)
        s = CorePotts.PottsStats()
        @test transfer_counts(s) == (0, 0, 0)
        a = CorePotts.PottsStats(; syncs = 1, transfers = 2, transfer_bytes = 8)
        b = CorePotts.PottsStats(; syncs = 3, transfers = 5, transfer_bytes = 40)
        @test transfer_counts(merge(a, b)) == (4, 7, 48)                     # ensemble totals
        for (label, _, make) in gate_models(Float64)
            prob = make()
            for alg in (SequentialCPM(), CheckerboardCPM())
                integ = init(prob, alg)
                @test transfer_counts(integ.stats) == (0, 0, 0)
                sol = solve!(integ)
                @test Symbol(sol.retcode) === :Success
                @test transfer_counts(sol.stats) == (0, 0, 0)
                @test all(x -> x isa Int, transfer_counts(sol.stats))
            end
        end
        # an event MCS and a HostPhase snapshot copy on the host: still nothing counted
        for alg in (SequentialCPM(), CheckerboardCPM())
            sol = solve(divide_problem(), alg; saveat = 0:4)
            @test sol.stats.lifecycle.divisions == 2
            @test transfer_counts(sol.stats) == (0, 0, 0)
            sol = solve(hostphase_problem(), alg; saveat = 0:4)
            @test transfer_counts(sol.stats) == (0, 0, 0)
        end
    end
end

@testitem "transfer counters: on the device (quiet-MCS targets, invariants)" setup = [TransferCountersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "transfer counters: on the device (quiet-MCS targets, invariants)" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            # (a), (b): quiet MCS of every gate model
            for (label, lifecycle, make) in gate_models(Float32)
                deltas = step_deltas(make(), alg; backend)
                quiet = [d for (q, d) in deltas if q]
                @test length(quiet) >= 2
                expected = (0, 0, 0)                                         # (b): D-089
                @test all(==(expected), quiet)
                all(==(expected), quiet) || @info "transfer counters quiet-MCS counts" label quiet
            end
            # (c) the division fixture: both cells divide at MCS 0 (read at a checkpoint); later
            # MCS are quiet (exact, as (b))
            prob = divide_problem(; T = Float32)
            integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
            step!(integ)                                                     # MCS 0: both cells divide
            @test checkpoint(integ).stats.lifecycle.divisions == 2
            for _ in 1:3
                c0 = transfer_counts(integ.stats)
                step!(integ)
                @test transfer_counts(integ.stats) .- c0 == (0, 0, 0)          # (b): D-089
            end
            @test checkpoint(integ).stats.lifecycle.divisions == 2
            # (d) a HostPhase every MCS
            integ = init(hostphase_problem(; T = Float32), alg; backend, save_start = false, save_everystep = false, save_end = false)
            for _ in 1:3
                c0 = transfer_counts(integ.stats)
                step!(integ)
                @test (transfer_counts(integ.stats) .- c0)[2] >= 1
            end
            # counters never decrease
            for prob in (divide_problem(; T = Float32), hostphase_problem(; T = Float32))
                integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
                c0 = transfer_counts(integ.stats)
                tr = pushfirst!(counter_trace!(integ, 4), c0)
                @test nondecreasing(tr)
            end
            # a save is counted too: it synchronizes and copies the state down
            integ = init(divide_problem(; T = Float32, tspan = (0, 2)), alg; backend, save_start = false, save_everystep = false, save_end = false)
            step!(integ); c0 = transfer_counts(integ.stats)
            current_state(integ)
            d = transfer_counts(integ.stats) .- c0
            @test d[1] >= 1 && d[2] >= 1 + length(integ.state.cell) && d[3] >= sizeof(integ.state.ownership)
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "transfer counters: the host-transfer audit document" setup = [TransferCountersSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "transfer counters: the host-transfer audit document" begin
        path = joinpath(@__DIR__, "..", "..", "..", "..", "docs", "design", "research", "gpu-host-transfer-audit.md")
        @test isfile(path)
        text = isfile(path) ? read(path, String) : ""
        headings = lowercase.(filter(l -> startswith(l, "#"), split(text, '\n')))
        has(words...) = any(h -> all(w -> occursin(w, h), words), headings)
        @test has("lifecycle", "event")                  # 1. lifecycle on an event MCS
        @test has("refresh_frozen")                      # 2. `frozen_kind_mask_tests.jl`'s mask refresh
        @test has("_adaptiveode")                        # 3. adaptive ODE phase
        @test has("hostphase")                           # 4. HostPhase
        @test has("trigger", "readback")                 # 5. the lifecycle trigger readback
        @test has("codegen")                             # codegen quality on Metal
        @test has("baseline")                            # quiet-MCS baseline per gate model
        low = lowercase(text)
        @test all(m -> occursin(m, low), ("graner", "wortel", "merks", "openvt", "akeeb"))
        @test all(r -> occursin(r, text), ("P6.0v1", "P6.0v2", "P6.0v3"))   # entries assigned to rows
    end
end
