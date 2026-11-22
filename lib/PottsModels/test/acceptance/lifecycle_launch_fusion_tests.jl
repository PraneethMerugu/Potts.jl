# Lifecycle launch fusion (D-101 follow-ups). X4 (typed literals in generated code) is not
# covered here: it changes every fingerprint and is batched with another fingerprint change.
#
# What is pinned:
#  (a) A fused lifecycle form whose first launch fails (on a device: its workgroup exceeds
#      the kernel's limit; simulated by `_LAUNCH_FAULT`) hands the MCS to the staged form
#      before anything is enqueued, so the fused `Lifecycle.before` cell update runs once.
#      Oracle: the unfused twin of the same problem (`before = nothing`, the update as the
#      last after-MCS `CellPhase`, D-101's construction), run staged.
#        - fused + fault  ==  unfused + the same fault  ==  unfused staged: bitwise in σ,
#          every cell column and the model state (CPU);
#        - the trackers equal a recount from σ (centroid and covariance of every live
#          cell), and every run counts each division once;
#        - the handover really happened (the form ends staged, at the first checked MCS;
#          the "cannot launch" warning is logged) and the fused problem really is fused.
#      Negative control: a twin that applies the update twice at the handover MCS differs
#      from the fused + fault run, so the comparison detects a double application.
#      CPU: the fused form forced on the CPU backend (`_FORCE_FUSED_LIFECYCLE`). A device
#      (POTTS_GPU set): the same, without the run-to-run comparisons (D-271).
#  (b) `generated_code(sys)` shows the lifecycle as Potts builds it. Contract: the result
#      has a field `lifecycle`, `nothing` for a model without divisions, else a NamedTuple
#      with at least `trigger` (the trigger's expression) and `before` (the expression of
#      the fused cell update, or `nothing`). When the problem fuses
#      (`prob.f.lifecycle.before !== nothing`), `lifecycle.before` is the update and the
#      update is NOT among `phases`; when fusion is not legal (the trigger reads another
#      cell's value of the written column; the update is not the last after-MCS phase),
#      `lifecycle.before === nothing` and the update stays in `phases`. `generated_code` and
#      `PottsProblem` agree for both scalar types.

@testsetup module LifecycleLaunchFusionSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
const ON_DEVICE = PottsDevices.on_device()
@potts_model Counter begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((48, 48); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A) => 2.0 * (volume - 30.0)^2
        contacts => 4.0
    end
    @after_mcs g ~ g + 1.0
    @divide cells(A) when = g >= 4.0 && volume >= 20, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 8.0)
end
@potts_model Counter2 begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((48, 48); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A) => 2.0 * (volume - 30.0)^2
        contacts => 4.0
    end
    @after_mcs g ~ g + 1.0
    @divide cells(A) Every(2) when = g >= 4.0 && volume >= 20, along = RandomPlane(),
        g => 0.0
    @sweep Metropolis(; temperature = 8.0)
end
# (b) fusion not legal: the trigger reads another cell's `g`
@potts_model Other begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @divide cells(A) when = g[3 - id] >= 3.0, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 1.0)
end
# (b) fusion not legal: the update is not the last after-MCS phase (the ODE follows it)
@potts_model NotLast begin
    @kinds medium A
    @parameters k = 0.1
    @variables begin
        g(cell) = 0.0
        y(cell) = 1.0
    end
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @equations D(y) ~ -k * y
    @divide cells(A) when = g >= 3.0, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 1.0)
end
# (b) no divisions: no lifecycle
@potts_model NoLifecycle begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @sweep Metropolis(; temperature = 1.0)
end
function counter_state(n = 4)
    σ = zeros(Int32, 48, 48)
    for (i, (x, y)) in enumerate(Iterators.take(((x, y) for x in 8:12:44, y in 8:12:44), n))
        σ[(x - 2):(x + 3), (y - 2):(y + 3)] .= i
    end
    return [ownership => σ, kind => fill(:A, n)]
end
# The unfused twin (D-101's construction): `before = nothing`, the update as the last
# after-MCS `CellPhase`; `extra` appends more after-MCS phases (the negative control)
function unfuse(prob; extra = ())
    f = prob.f
    lc = f.lifecycle
    @assert lc.before !== nothing
    lc0 = CorePotts.Lifecycle(
        lc.trigger, lc.normal, lc.cluster_normal, lc.kind, lc.divide!, lc.cluster_divide!,
        lc.rebuild!, lc.every, lc.rules, nothing, nothing, nothing
    )
    ph = f.phases
    ph0 = CorePotts.Phases(
        ph.before_mcs, (ph.after_mcs..., CorePotts.CellPhase(lc.before), extra...),
        ph.end_mcs, ph.at_init
    )
    f0 = CorePotts.CPMFunction(
        f.delta_H, f.commit!, f.constraint, f.temperature, f.bias, ph0, lc0,
        f.acceptance, f.footprint, f.fingerprint, f.sys, f.track, f.connectivity
    )
    return CorePotts.PottsProblem(
        f0, prob.u0, prob.lattice, prob.contact, prob.proposal, prob.relations,
        prob.spacing,
        prob.frozen, prob.tspan, prob.p, prob.seed, prob.replica,
        prob.repeat, prob.tangent, prob.kwargs
    )
end
const TRACKERS = (:anchor, :m1, :m2)
function same(a, b)
    return length(a.u) == length(b.u) && all(
        i -> a.u[i].ownership == b.u[i].ownership && a.u[i].cell == b.u[i].cell &&
            a.u[i].model == b.u[i].model,
        eachindex(a.u)
    )
end
function same_but_trackers(a, b)
    return length(a.u) == length(b.u) && all(eachindex(a.u)) do i
        x, y = a.u[i], b.u[i]
        x.ownership == y.ownership && x.model == y.model && keys(x.cell) == keys(y.cell) &&
            all(
            k -> k in TRACKERS || getfield(x.cell, k) == getfield(y.cell, k),
            keys(x.cell)
        )
    end
end
# trackers of every save equal a recount from σ (centroid and covariance of each live cell)
function trackers_exact(sol, lat::CorePotts.Lattice{N}) where {N}
    all(sol.u) do u
        cap = length(u.cell.volume)
        m = CorePotts.init_moments(u.ownership, lat, cap)
        ref = merge(m, (; volume = Int32[count(==(c), u.ownership) for c in 1:cap]))
        u.cell.volume == ref.volume && all(1:cap) do c
            ref.volume[c] == 0 && return true
            all(
                isapprox.(
                    CorePotts.centroid(u.cell, lat, c),
                    CorePotts.centroid(ref, lat, c); atol = 1.0e-9
                )
            ) && all(
                isapprox.(
                    CorePotts.covariance(Float64, u.cell, c, Val(N)), CorePotts.covariance(
                        Float64, ref, c, Val(N)
                    );
                    atol = 1.0e-9
                )
            )
        end
    end
end
# daughters seen in the saves (every MCS): a slot whose volume goes from 0 to positive. A
# division counted twice (the planner kernel's and the host planner's) exceeds them; this
# holds for one run alone, so it also checks the device runs, which are not reproducible
function births(sol)
    return sum(2:length(sol.u); init = 0) do i
        a, b = sol.u[i - 1].cell.volume, sol.u[i].cell.volume
        count(c -> a[c] == 0 && b[c] > 0, eachindex(b))
    end
end
# (no case removes cells, so no slot is reused; a daughter left empty is not seen)
function divisions_seen(sol)
    s = sol.stats.lifecycle
    return s.removals == 0 && s.divisions == births(sol) + s.empty_daughters
end
# Solve with CheckerboardCPM: `fused = true` starts from the fused form (forced on the CPU),
# `fault = true` makes its first launch fail; returns the solution, the final form and the
# MCS at which the form changed (or -1)
function lifecycle_run(prob, fault::Bool; fused::Bool = true, backend = nothing)
    CorePotts._FORCE_FUSED_LIFECYCLE[] = fused
    CorePotts._LAUNCH_FAULT[] = fault ? CorePotts._FORM_FUSED : 0
    try
        kw = backend === nothing ? (;) : (; backend)
        alg = fused ? CheckerboardCPM() : CheckerboardCPM(; fused_lifecycle_max_sites = 0)
        integ = init(prob, alg; saveat = 1, kw...)
        D = integ.lcache.device
        @assert D isa CorePotts.DeviceLifecycle && (D.fused! !== nothing) == fused
        handover = -1
        while integ.t < last(prob.tspan)
            t = integ.t
            step!(integ)
            handover < 0 && fused && D.form[] == CorePotts._FORM_STAGED && (handover = t)
        end
        return solve!(integ), D.form[], handover
    finally
        CorePotts._FORCE_FUSED_LIFECYCLE[] = false
        CorePotts._LAUNCH_FAULT[] = 0
    end
end
function cases(T)
    [
        "counter" =>
            PottsProblem(Counter(; name = :c), counter_state(), (0, 40); T, capacity = 64),
        "counter Every(2)" =>
            PottsProblem(Counter2(; name = :c), counter_state(), (1, 41); T, capacity = 64),
        "OpenVT monolayer" => PottsProblem(
            OpenVTGrowingMonolayer(; name = :o, lattice = (60, 60), τ = 10.0),
            openvt_monolayer_state(; lattice = (60, 60)), (0, 60); T, capacity = 256
        ),
        "Akeeb" => PottsProblem(
            AkeebInvasion(; name = :a, lattice = (60, 40)),
            [
                akeeb_state(; lattice = (60, 40)); :clock_min => 3.0; :clock_spread => 5.0;
                :V_max => 9.0
            ], (0, 60);
            T, capacity = 1500
        ),
    ]
end
function check_handover(name, prob; backend = nothing)
    @test prob.f.lifecycle.before !== nothing                     # the problem is fused
    q = unfuse(prob)
    fa, form, at = @test_logs (
        :warn,
        r"cannot launch",
    ) match_mode = :any lifecycle_run(prob, true; backend)
    # the handover happened, at the first checked MCS
    @test form == CorePotts._FORM_STAGED && first(prob.tspan) <= at < first(prob.tspan) + 2
    ua, uform, uat = lifecycle_run(q, true; backend)
    @test uform == CorePotts._FORM_STAGED && uat == at
    un = first(lifecycle_run(q, false; fused = false, backend))
    # a device checkerboard is not reproducible (D-271): its runs are compared only through
    # the recount below; the CPU runs (phases inline) carry the run-to-run comparisons
    if backend === nothing
        @test same(fa, ua) && same(fa, un)
        @test fa.stats.lifecycle.divisions == un.stats.lifecycle.divisions ==
            ua.stats.lifecycle.divisions > 0
    end
    @test trackers_exact(fa, prob.lattice) && trackers_exact(un, prob.lattice) &&
        trackers_exact(ua, prob.lattice)
    # each run counts the divisions it made, once
    @test divisions_seen(fa) && divisions_seen(ua) && divisions_seen(un)
    return fa, at
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "lifecycle launch fusion: lifecycle follow-ups" setup = [
    LifecycleLaunchFusionSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "lifecycle launch fusion: lifecycle follow-ups" begin
        @testset "(a) a fused form that cannot launch hands over to the staged form (CPU)" begin
            for (name, prob) in cases(Float64), seed in (1, 2)
                @testset "$name, seed $seed" begin
                    check_handover(name, remake(prob; seed))
                end
            end
            # negative control: applying the update twice at the handover MCS is detected
            # by the comparison
            prob = remake(last(cases(Float64)[1]); seed = 1)
            fa, _, at = lifecycle_run(prob, true)
            up = prob.f.lifecycle.before
            function twice(st, p, ctx, key, mcs, c)
                mcs == at && up(st, p, ctx, key, mcs, c)
                return nothing
            end
            dbl = first(
                lifecycle_run(
                    unfuse(prob; extra = (CorePotts.CellPhase(twice),)), false;
                    fused = false
                )
            )
            @test !same_but_trackers(fa, dbl)
            # control of the control: the wrapper is inert at an MCS the run never reaches
            function never(st, p, ctx, key, mcs, c)
                mcs == -7 && up(st, p, ctx, key, mcs, c)
                return nothing
            end
            inert = first(
                lifecycle_run(
                    unfuse(prob; extra = (CorePotts.CellPhase(never),)), false;
                    fused = false
                )
            )
            @test same(fa, inert)
        end

        if ON_DEVICE
            @testset "(a) on the device" begin
                backend = PottsDevices.device_backend()
                for (name, prob) in cases(Float32)
                    @testset "$name" begin
                        check_handover(name, remake(prob; seed = 1); backend)
                    end
                end
            end
        end

        @testset "(b) generated_code shows the fused lifecycle" begin
            σ = zeros(Int32, 24, 24)
            σ[3:6, 3:6] .= 1
            σ[15:18, 15:18] .= 2
            op = [ownership => σ, kind => [:A, :A]]
            fused_model(name) = Counter(; name)
            writes_g(ex) = ex !== nothing && occursin("st.cell.g[c] =", string(ex))
            function is_trigger(ex)
                return ex !== nothing && occursin("EVENT_DIVIDE", string(ex)) &&
                    occursin("EVENT_NONE", string(ex))
            end
            for T in (Float64, Float32)
                # fused: the update is the lifecycle's `before`, not an after-MCS phase
                prob = PottsProblem(
                    fused_model(:f), counter_state(), (0, 4); T, capacity = 16
                )
                @test prob.f.lifecycle.before !== nothing
                gc = generated_code(fused_model(:f); T)
                @test hasproperty(gc, :lifecycle)
                if hasproperty(gc, :lifecycle)
                    @test gc.lifecycle !== nothing
                    @test writes_g(gc.lifecycle.before)
                    @test is_trigger(gc.lifecycle.trigger)
                end
                @test !any(writes_g, gc.phases)
                # not legal: the update stays its own phase
                for M in (Other, NotLast)
                    p = PottsProblem(M(; name = :f), op, (0, 4); T, capacity = 16)
                    @test p.f.lifecycle.before === nothing                         # control
                    g = generated_code(M(; name = :f); T)
                    @test count(writes_g, g.phases) == 1
                    @test hasproperty(g, :lifecycle)
                    if hasproperty(g, :lifecycle)
                        @test g.lifecycle !== nothing && g.lifecycle.before === nothing
                        @test is_trigger(g.lifecycle.trigger)
                    end
                end
                g = generated_code(NoLifecycle(; name = :f); T)
                @test count(writes_g, g.phases) == 1
                @test hasproperty(g, :lifecycle) && g.lifecycle === nothing
            end
            # a published model: OpenVT's `V_target` update is fused
            sys = OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))
            prob = PottsProblem(
                sys, openvt_monolayer_state(; lattice = (24, 24)), (0, 2);
                capacity = 64
            )
            @test prob.f.lifecycle.before !== nothing
            gc = generated_code(sys)
            writes_vt(ex) = ex !== nothing && occursin("st.cell.V_target[c] =", string(ex))
            @test any(
                writes_vt, Any[
                    gc.phases...;
                    hasproperty(gc, :lifecycle) ? [gc.lifecycle.before] :
                        []
                ]
            )  # control
            @test !any(writes_vt, gc.phases)
            @test hasproperty(gc, :lifecycle) && writes_vt(gc.lifecycle.before)
        end
    end
end
