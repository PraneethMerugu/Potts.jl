# P6.0af (ROADMAP Phase 6, step 0): follow-ups of P6.0v3's launch fusion (D-101 review
# notes). X4 (typed literals in generated code) is not covered here: it changes every
# fingerprint and is batched with another fingerprint change.
#
# What is pinned:
#  (a) A device lifecycle whose staged form fails AFTER its first kernel ran (the trigger,
#      which runs the fused `Lifecycle.before` cell update in the same work item) hands the
#      MCS to the host planner with `before_ran[] = true`: the host planner must not run
#      `before` a second time. Oracle: the unfused twin of the same problem (`before =
#      nothing`, the update as the last after-MCS `CellPhase`, D-101's construction).
#        - fused + fault  ==  unfused + the same fault: bitwise in σ, every cell column and
#          the model state (both runs end on the host planner after the same handover);
#        - fused + fault  ==  unfused without a fault (the device planner throughout):
#          bitwise in σ, the model state and every cell column except the trackers
#          `anchor`/`m1`/`m2`, whose representation the host planner chooses differently
#          (D-089); those are checked against a recount from σ instead (centroid and
#          covariance of every live cell), in both runs;
#        - the same number of divisions, and divisions happen after the handover;
#        - the handover really happened (the form ends as `_FORM_HOST`, the "cannot launch"
#          warning is logged once) and the fused problem really is fused.
#      Fault points: after the first kernel (trigger + `before`) and after the second (the
#      planner), both before the lifecycle writes σ or any cell column.
#      Negative control: a twin that applies the update twice at the handover MCS (what a
#      host planner rerunning `before` would do) differs from the fused + fault run, so the
#      comparison detects a double application.
#      CPU: the device planner forced on the CPU backend (`_FORCE_DEVICE_LIFECYCLE`, as the
#      CorePotts tests do), `FUSE_SITES[] = 0` so the staged form is the one that runs.
#      Metal (POTTS_GPU=metal with Metal loaded, Float32): the same comparisons.
#  (b) `generated_code(sys)` shows the lifecycle as Potts builds it. Contract: the result
#      has a field `lifecycle`, `nothing` for a model without divisions, else a NamedTuple
#      with at least `trigger` (the trigger's expression) and `before` (the expression of
#      the fused cell update, or `nothing`). When the problem fuses (`prob.f.lifecycle.before
#      !== nothing`), `lifecycle.before` is the update and the update is NOT among
#      `phases`; when fusion is not legal (the trigger reads another cell's value of the
#      written column; the update is not the last after-MCS phase), `lifecycle.before ===
#      nothing` and the update stays in `phases`. `generated_code` and `PottsProblem` agree
#      for both scalar types. Fingerprints are unchanged (recorded on 457104d8): showing the
#      code differently must not change the code.
#
# Test-only hook the implementer adds (not public, not exported), next to `_LAUNCH_FAULT`
# in `lib/CorePotts/src/lifecycle_device.jl`:
#
#     const _STAGED_FAULT_AFTER = Ref(0)
#
#   k = _STAGED_FAULT_AFTER[] > 0: the staged form's first (not yet proven) launch enqueues
#   its first k kernels (k = 1: the trigger kernel, with `Lifecycle.before`; k = 2: also the
#   planner) and then throws `ArgumentError` as if the next kernel's launch had failed, so
#   `_form_failed!` runs with `before_ran[] == true` and the host planner takes the MCS.
#   0 (the default) is off. Like `_LAUNCH_FAULT` it acts only on an unproven form, so it
#   fires once per integrator.
#
# Today: (a) fails (the hook does not exist); (b) fails (`generated_code` has no `lifecycle`
# and lists the fused update among `phases`). With the hook emulated by a shim (the
# contract above, patched in at run time; not committed), (a) passes on the CPU and on
# Metal except one target: Akeeb with the fault after kernel 2 counts 85 divisions against
# the device planner's 72 (seed 1; fused and unfused twin alike, σ and every column still
# equal): the planner kernel has already added this MCS's divisions to the device
# accumulators when the host planner takes the MCS and counts them again. The Metal
# testset runs where Metal is loaded with POTTS_GPU=metal (wiring into `test/gpu.jl` is
# the coordinator's).
using Potts: CorePotts

const P60AF_ON_METAL = get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)
const P60AF_HOOK = isdefined(CorePotts, :_STAGED_FAULT_AFTER)
# fingerprints recorded on 457104d8 (T = Float64): `generated_code` must not change the code
const P60AF_FP_COUNTER = 0x5814e247991ede24
const P60AF_FP_OTHER = 0x98201bd26f585fa7
const P60AF_FP_OPENVT = 0xfe0d128235b9b8a6

@potts_model P60afCounter begin
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
@potts_model P60afCounter2 begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((48, 48); boundary = Closed(), neighborhood = Moore(1))
    @relations proposal = Moore(1)
    @energy begin
        cells(A) => 2.0 * (volume - 30.0)^2
        contacts => 4.0
    end
    @after_mcs g ~ g + 1.0
    @divide cells(A) Every(2) when = g >= 4.0 && volume >= 20, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 8.0)
end
# (b) fusion not legal: the trigger reads another cell's `g`
@potts_model P60afOther begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @divide cells(A) when = g[3 - id] >= 3.0, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 1.0)
end
# (b) fusion not legal: the update is not the last after-MCS phase (the ODE follows it)
@potts_model P60afNotLast begin
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
@potts_model P60afNoLifecycle begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @sweep Metropolis(; temperature = 1.0)
end

function p60af_counter_state(n = 4)
    σ = zeros(Int32, 48, 48)
    for (i, (x, y)) in enumerate(Iterators.take(((x, y) for x in 8:12:44, y in 8:12:44), n))
        σ[x-2:x+3, y-2:y+3] .= i
    end
    return [ownership => σ, kind => fill(:A, n)]
end

# The unfused twin (D-101's construction): `before = nothing`, the update as the last
# after-MCS `CellPhase`; `extra` appends more after-MCS phases (the negative control)
function p60af_unfuse(prob; extra = ())
    f = prob.f; lc = f.lifecycle
    @assert lc.before !== nothing
    lc0 = CorePotts.Lifecycle(lc.trigger, lc.normal, lc.cluster_normal, lc.kind, lc.divide!, lc.cluster_divide!,
        lc.rebuild!, lc.every, lc.rules, nothing)
    ph = f.phases
    ph0 = CorePotts.Phases(ph.before_mcs, (ph.after_mcs..., CorePotts.CellPhase(lc.before), extra...), ph.end_mcs, ph.at_init)
    f0 = CorePotts.CPMFunction(f.delta_H, f.commit!, f.constraint, f.claims, f.reads, f.temperature, f.bias, ph0, lc0,
        f.acceptance, f.footprint, f.fingerprint, f.sys)
    return CorePotts.PottsProblem(f0, prob.u0, prob.lattice, prob.contact, prob.proposal, prob.relations, prob.spacing,
        prob.frozen, prob.tspan, prob.p, prob.seed, prob.replica, prob.repeat)
end

const P60AF_TRACKERS = (:anchor, :m1, :m2)
p60af_same(a, b) = length(a.u) == length(b.u) &&
    all(i -> a.u[i].σ == b.u[i].σ && a.u[i].cell == b.u[i].cell && a.u[i].model == b.u[i].model, eachindex(a.u))
p60af_same_but_trackers(a, b) = length(a.u) == length(b.u) && all(eachindex(a.u)) do i
    x, y = a.u[i], b.u[i]
    x.σ == y.σ && x.model == y.model && keys(x.cell) == keys(y.cell) &&
        all(k -> k in P60AF_TRACKERS || getfield(x.cell, k) == getfield(y.cell, k), keys(x.cell))
end
# trackers of every save equal a recount from σ (centroid and covariance of each live cell)
function p60af_trackers_exact(sol, lat::CorePotts.Lattice{N}) where {N}
    all(sol.u) do u
        cap = length(u.cell.volume)
        m = CorePotts.init_moments(u.σ, lat, cap)
        ref = merge(m, (; volume = Int32[count(==(c), u.σ) for c in 1:cap]))
        u.cell.volume == ref.volume && all(1:cap) do c
            ref.volume[c] == 0 && return true
            all(isapprox.(CorePotts.centroid(u.cell, lat, c), CorePotts.centroid(ref, lat, c); atol = 1e-9)) &&
                all(isapprox.(CorePotts.covariance(Float64, u.cell, c, Val(N)), CorePotts.covariance(Float64, ref, c, Val(N));
                    atol = 1e-9))
        end
    end
end

# Solve with the staged form forced and the fault at kernel `k` (0: none); returns the
# solution, the final form and the MCS at which the form changed (or -1)
function p60af_run(prob, k; backend = nothing, device_on_cpu = backend === nothing)
    fuse, force = CorePotts.FUSE_SITES[], CorePotts._FORCE_DEVICE_LIFECYCLE[]
    CorePotts.FUSE_SITES[] = 0
    CorePotts._FORCE_DEVICE_LIFECYCLE[] = device_on_cpu
    P60AF_HOOK && (CorePotts._STAGED_FAULT_AFTER[] = k)
    try
        kw = backend === nothing ? (;) : (; backend)
        integ = init(prob, CheckerboardCPM(); saveat = 1, kw...)
        D = integ.lcache.device
        @assert D isa CorePotts.DeviceLifecycle && D.fused! === nothing
        handover = -1
        while integ.t < last(prob.tspan)
            t = integ.t
            step!(integ)
            handover < 0 && D.form[] == CorePotts._FORM_HOST && (handover = t)
        end
        return solve!(integ), D.form[], handover
    finally
        CorePotts.FUSE_SITES[] = fuse
        CorePotts._FORCE_DEVICE_LIFECYCLE[] = force
        P60AF_HOOK && (CorePotts._STAGED_FAULT_AFTER[] = 0)
    end
end

function p60af_cases(T)
    [
        "counter" => PottsProblem(P60afCounter(; name = :c), p60af_counter_state(), (0, 40); T, capacity = 64),
        "counter Every(2)" => PottsProblem(P60afCounter2(; name = :c), p60af_counter_state(), (1, 41); T, capacity = 64),
        "OpenVT monolayer" => PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (60, 60), τ = 10.0),
            openvt_monolayer_state(; lattice = (60, 60)), (0, 60); T, capacity = 256),
        "Akeeb" => PottsProblem(AkeebInvasion(; name = :a, lattice = (60, 40)),
            [akeeb_state(; lattice = (60, 40)); :clock_min => 3.0; :clock_spread => 5.0; :V_max => 9.0], (0, 60);
            T, capacity = 1500),
    ]
end

function p60af_check_handover(name, prob, k; backend = nothing)
    @test prob.f.lifecycle.before !== nothing                     # the problem is fused
    q = p60af_unfuse(prob)
    fa, form, at = @test_logs (:warn, r"cannot launch") match_mode = :any p60af_run(prob, k; backend)
    @test form == CorePotts._FORM_HOST && at >= 0                  # the handover happened
    ua, uform, uat = p60af_run(q, k; backend)
    @test uform == CorePotts._FORM_HOST && uat == at
    un, nform, _ = p60af_run(q, 0; backend)
    @test nform != CorePotts._FORM_HOST                            # the device planner throughout
    # the same path: bitwise in everything
    @test p60af_same(fa, ua)
    # against the device planner: bitwise except the trackers' representation …
    @test p60af_same_but_trackers(fa, un)
    # … whose values both equal a recount from σ
    @test p60af_trackers_exact(fa, prob.lattice) && p60af_trackers_exact(un, prob.lattice)
    @test fa.stats.lifecycle.divisions == un.stats.lifecycle.divisions == ua.stats.lifecycle.divisions
    # divisions after the handover (the host planner really planned some)
    live(u) = count(>(0), u.cell.volume)
    @test live(fa.u[end]) > live(fa.u[findfirst(>=(at), fa.t)])
    return fa, at
end

@testset "P6.0af: lifecycle follow-ups (D-101)" begin
    @testset "(a) staged form fails after the fused `before` ran (CPU, forced device planner)" begin
        @test P60AF_HOOK                       # CorePotts._STAGED_FAULT_AFTER (test-only hook)
        if P60AF_HOOK
            for (name, prob) in p60af_cases(Float64), k in (1, 2), seed in (1, 2)
                @testset "$name, fault after kernel $k, seed $seed" begin
                    p60af_check_handover(name, remake(prob; seed), k)
                end
            end
            # negative control: applying the update twice at the handover MCS (what a host
            # planner that reruns `before` does) is detected by the comparison
            prob = remake(last(p60af_cases(Float64)[1]); seed = 1)
            fa, at = p60af_run(prob, 1)[[1, 3]]
            up = prob.f.lifecycle.before
            twice(st, p, ctx, key, mcs, c) = (mcs == at && up(st, p, ctx, key, mcs, c); nothing)
            dbl = p60af_run(p60af_unfuse(prob; extra = (CorePotts.CellPhase(twice),)), 0)[1]
            @test !p60af_same_but_trackers(fa, dbl)
            # control of the control: the wrapper is inert at an MCS the run never reaches
            never(st, p, ctx, key, mcs, c) = (mcs == -7 && up(st, p, ctx, key, mcs, c); nothing)
            inert = p60af_run(p60af_unfuse(prob; extra = (CorePotts.CellPhase(never),)), 0)[1]
            @test p60af_same_but_trackers(fa, inert)
        end
    end

    if P60AF_ON_METAL
        @testset "(a) on Metal" begin
            @test P60AF_HOOK
            if P60AF_HOOK
                backend = Main.Metal.MetalBackend()
                for (name, prob) in p60af_cases(Float32), k in (1, 2)
                    @testset "$name, fault after kernel $k" begin
                        p60af_check_handover(name, remake(prob; seed = 1), k; backend)
                    end
                end
            end
        end
    end

    @testset "(b) generated_code shows the fused lifecycle" begin
        σ = zeros(Int32, 24, 24); σ[3:6, 3:6] .= 1; σ[15:18, 15:18] .= 2
        op = [ownership => σ, kind => [:A, :A]]
        fused_model(name) = P60afCounter(; name)
        writes_g(ex) = ex !== nothing && occursin("st.cell.g[c] =", string(ex))
        is_trigger(ex) = ex !== nothing && occursin("EVENT_DIVIDE", string(ex)) && occursin("EVENT_NONE", string(ex))
        for T in (Float64, Float32)
            # fused: the update is the lifecycle's `before`, not an after-MCS phase
            prob = PottsProblem(fused_model(:f), p60af_counter_state(), (0, 4); T, capacity = 16)
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
            for M in (P60afOther, P60afNotLast)
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
            g = generated_code(P60afNoLifecycle(; name = :f); T)
            @test count(writes_g, g.phases) == 1
            @test hasproperty(g, :lifecycle) && g.lifecycle === nothing
        end
        # a published model: OpenVT's `V_target` update is fused
        sys = OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))
        prob = PottsProblem(sys, openvt_monolayer_state(; lattice = (24, 24)), (0, 2); capacity = 64)
        @test prob.f.lifecycle.before !== nothing
        gc = generated_code(sys)
        writes_vt(ex) = ex !== nothing && occursin("st.cell.V_target[c] =", string(ex))
        @test any(writes_vt, Any[gc.phases...; hasproperty(gc, :lifecycle) ? [gc.lifecycle.before] : []])  # control
        @test !any(writes_vt, gc.phases)
        @test hasproperty(gc, :lifecycle) && writes_vt(gc.lifecycle.before)
        # the code itself is unchanged (fingerprints recorded on 457104d8)
        @test PottsProblem(fused_model(:f), p60af_counter_state(), (0, 4); capacity = 16).f.fingerprint == P60AF_FP_COUNTER
        @test PottsProblem(P60afOther(; name = :f), op, (0, 4); capacity = 16).f.fingerprint == P60AF_FP_OTHER
        @test prob.f.fingerprint == P60AF_FP_OPENVT
    end
end
