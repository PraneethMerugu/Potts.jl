# P6.0v (ROADMAP Phase 6, step 0): GPU host-transfer audit and instrumentation. Frozen
# (AUTONOMY §7.3). This file accepts P6.0v itself (the counters, the current baseline and
# the audit document), not P6.0v1–v3: their zero-transfer targets freeze with them.
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
# Expected counts on Metal. (a) and (b) are exact and are also the long-term targets of
# P6.0v1–v3 (they hold at freeze time: 1554d56, plus P6.0d, whose `refresh_frozen!` returns
# before synchronizing when nothing is frozen, as in every fixture here):
#  (a) A quiet MCS of a gate model without a lifecycle (Graner–Glazier, Wortel Act, Merks
#      with the explicit field solver): 0 syncs, 0 transfers. `CheckerboardCPM` reads its
#      status back only at a save; the field step copies device to device.
#  (b) A quiet MCS (no lifecycle event) of a model with a lifecycle (OpenVT monolayer,
#      Akeeb, the division fixture after MCS 0): exactly the event-count readback (D-035):
#      1 sync, 1 transfer, 4 bytes (`lifecycle.jl` `run_lifecycle!`: synchronize, then
#      `_readback(cache.count)`, a 1-element Int32).
# (c) and (d) are invariants that survive P6.0v1/v2 (their exact current-path counts are an
# ordinary, non-frozen regression test that those rows update):
#  (c) The event MCS of the division fixture (every cell divides at MCS 0) reads back at
#      least the event count: syncs ≥ 1, transfers ≥ 1, bytes ≥ 4.
#  (d) An MCS running a `HostPhase` (host code over host copies) transfers: transfers ≥ 1.
#  Counters never decrease from one MCS to the next; a save (`integ.u`) is counted (lower
#  bounds: it synchronizes and copies σ and every cell column down).
# The audit document has a section per known starting point of the ROADMAP row.
#
# Today this fails with `FieldError: type PottsStats has no field transfers` (and `syncs`,
# `transfer_bytes`).
using Potts: CorePotts

const P60V_COUNTERS = (:syncs, :transfers, :transfer_bytes)
p60v_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)
const P60V_ON_METAL = get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)

# ---------------------------------------------------------------------------------------
# Fixtures

# Division fixture: every cell of kind A divides at MCS 0 (and only then), plane normal
# (1, 0). T = 0 and a volume constraint of weight 100 at V = 8 reject every copy of MCS 0,
# so both 4×2 cells still have 8 sites at the lifecycle and split 4 | 4 (independent of the
# RNG). Later MCS are quiet (the trigger fails).
@potts_model P60vDivide begin
    @kinds medium A
    @variables m(cell) = 1.0
    @lattice Lattice((16, 8))
    @energy cells => 100 * (volume - 8)^2
    @divide cells(A) when = mcs == 0, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 0.0)
end
const P60V_CAPACITY = 6
function p60v_divide_problem(; T = Float64, tspan = (0, 4))
    σ = zeros(Int32, 16, 8)
    σ[3:6, 2:3] .= 1
    σ[10:13, 5:6] .= 2
    return PottsProblem(P60vDivide(; name = :p60v), [ownership => σ, kind => [:A, :A]], tspan;
        T, capacity = P60V_CAPACITY)
end

# HostPhase fixture (CorePotts level): a no-op host phase after every sweep.
function p60v_hostphase_problem(; T = Float64)
    σ = zeros(Int32, 12, 12)
    σ[3:6, 3:6] .= 1
    σ[8:11, 7:10] .= 2
    u0 = CorePotts.initial_state(σ, Int32[1, 1]; cell = (; x = zeros(T, 2), y = zeros(T, 2)))
    dH(st, p, prop, ctx) = CorePotts.volume_delta(st.cell.volume, prop, (v, c) -> p.λ * (v - p.V0)^2)
    f = CorePotts.CPMFunction(dH; temperature = (st, p, prop, ctx) -> p.T,
        phases = CorePotts.Phases(; after_mcs = (CorePotts.HostPhase((cell, st, p, ctx, mcs) -> nothing),)))
    return CorePotts.PottsProblem(f, u0, CorePotts.Lattice(size(σ)), (0, 4), (; λ = T(1), V0 = T(16), T = T(2)))
end
# The gate models (benchmark/gate.jl) at small sizes. `lifecycle`: has a lifecycle.
function p60v_gate_models(T)
    gg = graner_glazier_state()
    w = zeros(Int32, 32, 32); w[12:20, 12:20] .= 1
    return [
        ("Graner–Glazier", false, () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 6); T)),
        ("Wortel Act", false, () -> PottsProblem(WortelAct(; name = :w, lattice = (32, 32)), [ownership => w, kind => [:cell]], (0, 6); T)),
        ("Merks", false, () -> PottsProblem(MerksVasculogenesis(; name = :m, lattice = (32, 32)),
            merks_state(; lattice = (32, 32), n = 6), (0, 6); T, field_solver = ExplicitEuler(substeps = 2, lower = 0.0))),
        ("OpenVT monolayer", true, () -> PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24), τ = 1e6),
            openvt_monolayer_state(; lattice = (24, 24)), (0, 6); T, capacity = 64)),
        ("Akeeb", true, () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (0, 6); T, capacity = 1000)),
    ]
end

p60v_lifecycle_total(s) = sum(f -> getfield(s.lifecycle, f), fieldnames(typeof(s.lifecycle)))

"""Per-MCS counter deltas of `step!` (no saves): a vector of `(quiet, (syncs, transfers, bytes))`,
`quiet` when the MCS had no lifecycle event."""
function p60v_step_deltas(prob, alg; backend, nwarm = 1, nstep = 4)
    integ = init(prob, alg; backend, save_start = false, save_end = false)
    for _ in 1:nwarm
        step!(integ)
    end
    out = Tuple{Bool, NTuple{3, Int}}[]
    for _ in 1:nstep
        c0, l0 = p60v_counts(integ.stats), p60v_lifecycle_total(integ.stats)
        step!(integ)
        push!(out, (p60v_lifecycle_total(integ.stats) == l0, p60v_counts(integ.stats) .- c0))
    end
    return out
end

"""Counter triples after each of `n` steps of `integ`."""
p60v_trace!(integ, n) = [(step!(integ); p60v_counts(integ.stats)) for _ in 1:n]
p60v_nondecreasing(tr) = all(i -> all(tr[i] .<= tr[i + 1]), 1:(length(tr) - 1))

# ---------------------------------------------------------------------------------------

@testset "P6.0v: transfer counters exist and are zero on the CPU" begin
    @test all(in(fieldnames(CorePotts.PottsStats)), P60V_COUNTERS)
    s = CorePotts.PottsStats()
    @test p60v_counts(s) == (0, 0, 0)
    a = CorePotts.PottsStats(; syncs = 1, transfers = 2, transfer_bytes = 8)
    b = CorePotts.PottsStats(; syncs = 3, transfers = 5, transfer_bytes = 40)
    @test p60v_counts(merge(a, b)) == (4, 7, 48)                     # ensemble totals
    for (label, _, make) in p60v_gate_models(Float64)
        prob = make()
        for alg in (SequentialCPM(), CheckerboardCPM())
            integ = init(prob, alg)
            @test p60v_counts(integ.stats) == (0, 0, 0)
            sol = solve!(integ)
            @test Symbol(sol.retcode) === :Success
            @test p60v_counts(sol.stats) == (0, 0, 0)
            @test all(x -> x isa Int, p60v_counts(sol.stats))
        end
    end
    # an event MCS and a HostPhase snapshot copy on the host: still nothing counted
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(p60v_divide_problem(), alg; saveat = 0:4)
        @test sol.stats.lifecycle.divisions == 2
        @test p60v_counts(sol.stats) == (0, 0, 0)
        sol = solve(p60v_hostphase_problem(), alg; saveat = 0:4)
        @test p60v_counts(sol.stats) == (0, 0, 0)
    end
end

@testset "P6.0v: transfer counters on Metal (quiet-MCS targets, invariants)" begin
    if P60V_ON_METAL
        backend = Main.Metal.MetalBackend()
        alg = CheckerboardCPM()
        # (a), (b): quiet MCS of every gate model
        for (label, lifecycle, make) in p60v_gate_models(Float32)
            deltas = p60v_step_deltas(make(), alg; backend)
            quiet = [d for (q, d) in deltas if q]
            @test length(quiet) >= 2
            expected = lifecycle ? (1, 1, 4) : (0, 0, 0)
            @test all(==(expected), quiet)
            all(==(expected), quiet) || @info "P6.0v quiet-MCS counts" label quiet
        end
        # (c) the division fixture: the event MCS reads back at least the event count;
        # later MCS are quiet (exact, as (b))
        prob = p60v_divide_problem(; T = Float32)
        integ = init(prob, alg; backend, save_start = false, save_end = false)
        c0 = p60v_counts(integ.stats)
        step!(integ)                                                     # MCS 0: both cells divide
        @test integ.stats.lifecycle.divisions == 2
        d = p60v_counts(integ.stats) .- c0
        @test d[1] >= 1 && d[2] >= 1 && d[3] >= 4
        for _ in 1:3
            c0 = p60v_counts(integ.stats)
            step!(integ)
            @test p60v_counts(integ.stats) .- c0 == (1, 1, 4)
        end
        @test integ.stats.lifecycle.divisions == 2
        # (d) a HostPhase every MCS
        integ = init(p60v_hostphase_problem(; T = Float32), alg; backend, save_start = false, save_end = false)
        for _ in 1:3
            c0 = p60v_counts(integ.stats)
            step!(integ)
            @test (p60v_counts(integ.stats) .- c0)[2] >= 1
        end
        # counters never decrease
        for prob in (p60v_divide_problem(; T = Float32), p60v_hostphase_problem(; T = Float32))
            integ = init(prob, alg; backend, save_start = false, save_end = false)
            c0 = p60v_counts(integ.stats)
            tr = pushfirst!(p60v_trace!(integ, 4), c0)
            @test p60v_nondecreasing(tr)
        end
        # a save is counted too: it synchronizes and copies the state down
        integ = init(p60v_divide_problem(; T = Float32, tspan = (0, 2)), alg; backend, save_start = false, save_end = false)
        step!(integ); c0 = p60v_counts(integ.stats)
        integ.u
        d = p60v_counts(integ.stats) .- c0
        @test d[1] >= 1 && d[2] >= 1 + length(integ.state.cell) && d[3] >= sizeof(integ.state.σ)
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

@testset "P6.0v: the host-transfer audit document" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "docs", "design", "research", "gpu-host-transfer-audit.md")
    @test isfile(path)
    text = isfile(path) ? read(path, String) : ""
    headings = lowercase.(filter(l -> startswith(l, "#"), split(text, '\n')))
    has(words...) = any(h -> all(w -> occursin(w, h), words), headings)
    @test has("lifecycle", "event")                  # 1. lifecycle on an event MCS
    @test has("refresh_frozen")                      # 2. P6.0d's mask refresh
    @test has("_adaptiveode")                        # 3. adaptive ODE phase
    @test has("hostphase")                           # 4. HostPhase
    @test has("trigger", "readback")                 # 5. the lifecycle trigger readback
    @test has("codegen")                             # codegen quality on Metal
    @test has("baseline")                            # quiet-MCS baseline per gate model
    low = lowercase(text)
    @test all(m -> occursin(m, low), ("graner", "wortel", "merks", "openvt", "akeeb"))
    @test all(r -> occursin(r, text), ("P6.0v1", "P6.0v2", "P6.0v3"))   # entries assigned to rows
end
