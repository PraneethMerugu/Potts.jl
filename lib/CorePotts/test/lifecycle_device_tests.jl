# The lifecycle planner (`src/lifecycle_device.jl`) is one KernelAbstractions planner for
# every backend and every algorithm. The CPU runs its staged form (one kernel per stage); the
# fused form (one workgroup) runs on a device, and here on the CPU under
# `_FORCE_FUSED_LIFECYCLE`, so the lifecycle, compartment and relationship tests check its
# kernels without a GPU. On a device the statistics are exact at host read points (saves,
# `current_state(integ)`, `checkpoint`, the end of `solve!`); on the CPU they are folded
# after every event round.

@testsetup module CP_lifecycle_device
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates,
    linear_index, shift
include("shared/gg_model.jl")
include("shared/geometry.jl")
include("shared/lifecycle.jl")
include("shared/compartments.jl")
include("shared/include_items.jl")

function ld_base_prob()
    lat = Lattice((20, 20))
    σ = zeros(Int32, 20, 20)
    σ[5:12, 5:10] .= 1
    st = with_capacity(initial_state(σ, Int32[1]; cell = init_moments(σ, lat, 1)), 3)
    once(st, p, ctx, key, mcs, c) = mcs == 1 && c == 1 ? EVENT_DIVIDE : EVENT_NONE
    f = CPMFunction(
        gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
        lifecycle = Lifecycle(once)
    )
    prob = PottsProblem(f, st, lat, (0, 4), gg_params())
    return (; prob, f, st, lat, σ, once)
end

function ld_growing_prob()
    σg = zeros(Int32, 40, 40)
    σg[15:24, 15:24] .= 1
    lg = Lattice((40, 40))
    stg = with_capacity(initial_state(σg, Int32[1]; cell = init_moments(σg, lg, 1)), 16)
    fg = CPMFunction(
        gg_delta_H; temperature = gg_temperature,
        lifecycle = Lifecycle(
            (st, p, ctx, key, mcs, c) -> if st.cell.volume[c] >= 60
                EVENT_DIVIDE
            else
                EVENT_NONE
            end;
            normal = RandomPlane()
        )
    )
    return PottsProblem(fg, stg, lg, (0, 30), merge(gg_params(), (; V0 = 70.0)))
end

# two solutions agree exactly, state by state
function same_run(a, b)
    return length(a.u) == length(b.u) && all(
        i -> a.u[i].ownership == b.u[i].ownership && a.u[i].cell == b.u[i].cell,
        eachindex(a.u)
    )
end

# run `f()` with the fused form forced on the CPU
function with_fused(f)
    CorePotts._FORCE_FUSED_LIFECYCLE[] = true
    try
        return f()
    finally
        CorePotts._FORCE_FUSED_LIFECYCLE[] = false
    end
end

include("shared/export_all.jl")
end

@testitem "lifecycle planner: attachment, statistics, scratch and determinism" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "lifecycle planner: attachment, statistics, scratch and determinism" begin
        prob = ld_base_prob().prob
        # one planner for every algorithm; the CPU runs it staged, a test may force fused
        for alg in (SequentialCPM(), CheckerboardCPM())
            integ = init(prob, alg; save_start = false, save_end = false)
            D = integ.lcache.device
            @test D isa CorePotts.DeviceLifecycle && D.fused! === nothing
            @test D.form[] == CorePotts._FORM_STAGED
            # the CPU has 64-bit atomics: the moment scratch is Int64
            @test eltype(D.dv.dm1) == Int64 && eltype(D.dv.dm2) == Int64
            @test with_fused(() -> init(prob, alg).lcache.device.fused!) !== nothing
        end
        # on the CPU the statistics are folded after the event round: current at once
        @testset "statistics current after the event ($form)" for form in (:staged, :fused)
            integ = if form == :fused
                with_fused(() -> init(prob, CheckerboardCPM(); save_start = false))
            else
                init(prob, CheckerboardCPM(); save_start = false)
            end
            step!(integ)
            step!(integ)                             # MCS 1: the division
            @test count(>(0), integ.state.cell.volume) == 2
            @test integ.stats.lifecycle.divisions == 1
            # a read point folds nothing twice
            u = current_state(integ)
            @test integ.stats.lifecycle.divisions == 1 && count(>(0), u.cell.volume) == 2
            current_state(integ)
            @test integ.stats.lifecycle.divisions == 1
        end
        # deterministic: two runs of a growing population agree exactly (random planes)
        pg = ld_growing_prob()
        g, h = (solve(pg, CheckerboardCPM(); saveat = 5) for _ in 1:2)
        @test g.stats.lifecycle.divisions == h.stats.lifecycle.divisions >= 2
        @test same_run(g, h)
    end
end

@testitem "lifecycle planner (fused): lifecycle_tests" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "fused lifecycle_tests" begin
        with_fused() do
            @test init(ld_base_prob().prob, CheckerboardCPM()).lcache.device.fused! !==
                nothing
            include_items(@__MODULE__, joinpath(@__DIR__, "lifecycle_tests.jl"))
        end
    end
end

@testitem "lifecycle planner (fused): compartments_tests" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "fused compartments_tests" begin
        with_fused() do
            @test init(ld_base_prob().prob, CheckerboardCPM()).lcache.device.fused! !==
                nothing
            include_items(@__MODULE__, joinpath(@__DIR__, "compartments_tests.jl"))
        end
    end
end

@testitem "lifecycle planner (fused): relationships_tests" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "fused relationships_tests" begin
        with_fused() do
            @test init(ld_base_prob().prob, CheckerboardCPM()).lcache.device.fused! !==
                nothing
            include_items(@__MODULE__, joinpath(@__DIR__, "relationships_tests.jl"))
        end
    end
end

@testitem "lifecycle planner: the fused form that cannot launch hands over" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "the fused form that cannot launch hands over" begin
        # A fused form whose first launch fails (on a device: its workgroup exceeds what
        # the kernel's pipeline allows; simulated here) hands over to the staged form, which
        # always launches; the results are the staged form's
        pg = ld_growing_prob()
        staged = solve(pg, CheckerboardCPM(); saveat = 5)
        try
            with_fused() do
                CorePotts._LAUNCH_FAULT[] = CorePotts._FORM_FUSED
                integ = init(pg, CheckerboardCPM(); save_start = false, save_end = false)
                @test integ.lcache.device.form[] == CorePotts._FORM_FUSED
                @test_logs (:warn, r"cannot launch") step!(integ)
                @test integ.lcache.device.form[] == CorePotts._FORM_STAGED
                @test_logs step!(integ)                                   # once
                sol = @test_logs (:warn, r"cannot launch") solve(
                    pg, CheckerboardCPM(); saveat = 5
                )
                @test sol.stats.lifecycle.divisions ==
                    staged.stats.lifecycle.divisions >= 2
                @test same_run(sol, staged)
            end
        finally
            CorePotts._LAUNCH_FAULT[] = 0
        end
    end
end

@testitem "lifecycle planner: workgroup fit and the smallest workgroup" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "workgroup fit and the smallest workgroup" begin
        # The plan does not depend on the planner's workgroup: a workgroup of one item (the
        # smallest a backend can impose) gives the same run as the default, in both forms
        pg = ld_growing_prob()
        try
            for fused in (false, true)
                run(w) = begin
                    CorePotts._PLAN_WG_MAX[] = w
                    f = () -> solve(pg, CheckerboardCPM(); saveat = 5)
                    fused ? with_fused(f) : f()
                end
                ref = run(CorePotts.PLAN_WG)
                one = run(1)
                @test one.stats.lifecycle.divisions == ref.stats.lifecycle.divisions >= 2
                @test same_run(one, ref)
                CorePotts._PLAN_WG_MAX[] = 1
                integ = fused ? with_fused(() -> init(pg, CheckerboardCPM())) :
                    init(pg, CheckerboardCPM())
                @test integ.lcache.device.wg[] == 1
            end
            CorePotts._PLAN_WG_MAX[] = CorePotts.PLAN_WG
            # the staged form fits the planner's workgroup to the pipeline's limit (here a
            # simulated limit of 24 items) before its first launch: halved to 16
            CorePotts._PLAN_WG_LIMIT[] = 24
            integ = init(pg, CheckerboardCPM(); save_start = false, save_end = false)
            @test integ.lcache.device.wg[] == CorePotts.PLAN_WG
            step!(integ)
            @test integ.lcache.device.wg[] == 16
            fit = solve(pg, CheckerboardCPM(); saveat = 5)
            CorePotts._PLAN_WG_LIMIT[] = 0
            @test same_run(fit, solve(pg, CheckerboardCPM(); saveat = 5))
            # the smallest workgroup, through the whole lifecycle suite (staged)
            CorePotts._PLAN_WG_MAX[] = 1
            include_items(@__MODULE__, joinpath(@__DIR__, "lifecycle_tests.jl"))
        finally
            CorePotts._PLAN_WG_MAX[] = CorePotts.PLAN_WG
            CorePotts._PLAN_WG_LIMIT[] = 0
        end
    end
end

@testitem "lifecycle planner: CPU quiet MCS, mobile-site list and host hooks" setup = [
    CP_lifecycle_device,
] tags = [:corepotts, :lifecycle_device] begin
    @testset "CPU quiet MCS, mobile-site list and host hooks" begin
        base = ld_base_prob()
        # a quiet MCS on the CPU costs the trigger kernel only, in both forms
        quiet = Lifecycle((st, p, ctx, key, mcs, c) -> EVENT_NONE)
        fq = CPMFunction(
            gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = quiet
        )
        f0 = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics)
        n(f, k) = begin
            integ = init(PottsProblem(f, base.st, base.lat, (0, 4), gg_params()), k)
            step!(integ)
            a = integ.stats.launches
            step!(integ)
            step!(integ)
            integ.stats.launches - a
        end
        for fused in (false, true), alg in (SequentialCPM(), CheckerboardCPM())
            m(f) = fused ? with_fused(() -> n(f, alg)) : n(f, alg)
            @test m(fq) - m(f0) == 2                       # one launch per quiet MCS
        end
        # an event MCS runs the remaining stages (control)
        integ = init(base.prob, CheckerboardCPM(); save_start = false)
        step!(integ)
        a = integ.stats.launches
        step!(integ)                                       # MCS 1: the division
        @test integ.stats.launches - a > 2

        # SequentialCPM: the host mobile-site list follows the frozen mask after each event
        # round (a transition into and out of the frozen kind, then a removal)
        S = 4
        ev(st, p, ctx, key, mcs, c) = if mcs == S
            EVENT_TRANSITION
        elseif mcs == 2S && c == 1
            EVENT_REMOVE
        else
            EVENT_NONE
        end
        integ = init(fk_problem(ev; kind = fk_swap, tspan = (0, 12)), SequentialCPM())
        m = integ.ctx.mobility
        @test m isa CorePotts.MaskMobility && m.sites !== nothing
        for t in 1:12
            step!(integ)
            m = integ.ctx.mobility
            @test m.sites == findall(!, vec(Array(m.frozen)))
            @test integ.nmobile == length(m.sites)
        end
        @test integ.stats.lifecycle.transitions == 2 && integ.stats.lifecycle.removals == 1
        @test integ.nmobile == 900                         # cell 1 (now frozen) removed

        # `Lifecycle.rebuild!` runs after the planner on every event round, with the
        # trackers already updated, and on no quiet round
        calls = Int[]
        rebuild!(st, p, ctx, backend) = (push!(calls, count(>(0), st.cell.volume)); nothing)
        fr = CPMFunction(
            gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = Lifecycle(base.once; rebuild!)
        )
        for alg in (SequentialCPM(), CheckerboardCPM())
            empty!(calls)
            sol = solve(PottsProblem(fr, base.st, base.lat, (0, 4), gg_params()), alg)
            @test sol.stats.lifecycle.divisions == 1 && calls == [2]
        end
    end
end

@testitem "lifecycle planner: divide! links and moment-scratch bound" setup = [
    CP_lifecycle_device,
] tags = [
    :corepotts, :lifecycle_device,
] begin
    @testset "divide! links and moment-scratch bound" begin
        base = ld_base_prob()
        σ, lat, once = base.σ, base.lat, base.once
        lim = CorePotts._SCRATCH_LIMIT[]
        try
            # A daughter rule that links mother and daughter: the newborn's links are
            # cleaned (and its columns copied) for every cell before any rule runs, so the
            # rule's link survives (a race before: the link was dropped)
            @testset "a divide! rule's links ($form)" for form in (:staged, :fused)
                function link_md!(st, p, ctx, key, mcs, parent, daughter)
                    add_link!(st.cell, parent, daughter)
                    return nothing
                end
                cl = merge(init_moments(σ, lat, 1), empty_links(2, 1))
                stl = with_capacity(initial_state(σ, Int32[1]; cell = cl), 3)
                fl = CPMFunction(
                    gg_delta_H; temperature = gg_temperature, constraint = (
                        st, p, prop, ctx
                    ) -> false,
                    lifecycle = Lifecycle(once; divide! = link_md!)
                )
                probl = PottsProblem(fl, stl, lat, (0, 3), gg_params())
                go = () -> solve(probl, CheckerboardCPM())
                sol = form == :fused ? with_fused(go) : go()
                @test sol.stats.lifecycle.divisions == 1
                @test linked(sol.u[end].cell, 1, 2) && linked(sol.u[end].cell, 2, 1)
                @test count(!iszero, sol.u[end].cell.links) == 2
            end

            # A cell too large for the moment scratch (here: a lowered bound) does not
            # divide: the division is deferred and counted, the state stays exact, the host
            # warns once per report, later reads and `reinit!` do not throw (the count is
            # not sticky)
            @testset "moment-scratch bound ($form)" for form in (:staged, :fused)
                CorePotts._FORCE_FUSED_LIFECYCLE[] = form == :fused
                alg = CheckerboardCPM()
                # cell 1 (8 × 6 sites: m2 about its anchor 264 in x, 152 in y) alone;
                # cluster {2, 3} with root 2 (a small and a large member) as a unit
                σs = zeros(Int32, 30, 30)
                σs[3:10, 3:8] .= 1
                σs[15:16, 15:16] .= 2
                σs[20:27, 15:20] .= 3
                function trs(st, p, ctx, key, mcs, c)
                    if mcs != 1
                        return EVENT_NONE
                    elseif c == 1
                        return EVENT_DIVIDE
                    elseif c == 2
                        return EVENT_DIVIDE_CLUSTER
                    else
                        return EVENT_NONE
                    end
                end
                latS = Lattice((30, 30))
                cells = merge(
                    init_moments(σs, latS, 3),
                    init_clusters(σs, Int32[1, 2, 2], latS)
                )
                sts = with_capacity(initial_state(σs, Int32[1, 1, 1]; cell = cells), 8)
                fs = CPMFunction(
                    gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
                    lifecycle = Lifecycle(trs)
                )
                probs = PottsProblem(fs, sts, latS, (0, 3), gg_params())
                # the two large cells exceed it
                CorePotts._SCRATCH_LIMIT[] = 20
                integ = init(
                    probs, alg; save_start = false,
                    save_end = false, save_everystep = false
                )
                step!(integ)
                # the CPU folds the counts after the event round: the warning comes at once
                @test_logs (:warn, r"moment scratch") step!(integ)
                step!(integ)
                u = current_state(integ)
                @test integ.stats.lifecycle.divisions == 0
                @test integ.stats.lifecycle.deferred == 2         # cell 1 and cluster 2
                @test u.ownership == σs && u.cell.volume[1:3] == Int32[48, 4, 48]
                @test u.cell.m1[:, 1:3] == cells.m1 && u.cell.m2[:, 1:3] == cells.m2
                # reported once
                @test_logs current_state(integ)
                reinit!(integ)
                @test integ.stats.lifecycle.deferred == 0
                # control: within the bound, both divide (cell 1 alone, the cluster as a
                # unit)
                CorePotts._SCRATCH_LIMIT[] = nothing
                integ = init(
                    probs, alg; save_start = false,
                    save_end = false, save_everystep = false
                )
                step!(integ)
                step!(integ)
                step!(integ)
                u = current_state(integ)
                @test integ.stats.lifecycle.divisions == 3 &&
                    integ.stats.lifecycle.deferred == 0
                @test u.cell.volume == Int32[count(==(c), u.ownership) for c in 1:8]
                @test same_moments(u, latS, 8, CheckerboardCPM())
            end
        finally
            CorePotts._SCRATCH_LIMIT[] = lim
            CorePotts._FORCE_FUSED_LIFECYCLE[] = false
        end
    end
end

@testitem "lifecycle planner: Lifecycle.before with the trigger" setup = [
    CP_lifecycle_device,
] tags = [
    :corepotts, :lifecycle_device,
] begin
    @testset "Lifecycle.before with the trigger" begin
        # `Lifecycle.before` (D-101): a cell update run with the trigger of each cell, in
        # one work item (one launch for both), on its own on MCS the lifecycle does not
        # check. Oracle: the same update as an after-MCS `CellPhase` and no `before`, in
        # every form (and through a failing form's handover)
        σb = zeros(Int32, 30, 30)
        σb[4:11, 4:11] .= 1
        σb[18:25, 18:25] .= 2
        latb = Lattice((30, 30))
        stb = with_capacity(
            initial_state(
                σb, Int32[1, 1]; cell = merge(
                    init_moments(σb, latb, 2), (;
                        g = [0.0, 2.0],
                    )
                )
            ),
            8
        )
        function tick!(st, p, ctx, key, mcs, c)
            st.cell.volume[c] > 0 && (st.cell.g[c] += 1.0)
            return nothing
        end
        # its own `g`
        ripe(st, p, ctx, key, mcs, c) = st.cell.g[c] >= 4.0 ? EVENT_DIVIDE : EVENT_NONE
        function restart!(st, p, ctx, key, mcs, parent, daughter)
            st.cell.g[parent] = 0.0
            st.cell.g[daughter] = 0.0
            return nothing
        end
        function make(fused, every)
            return PottsProblem(
                CPMFunction(
                    gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
                    phases = Phases(after_mcs = fused ? () : (CellPhase(tick!),)),
                    lifecycle = Lifecycle(
                        ripe; divide! = restart!, every, before = if fused
                            tick!
                        else
                            nothing
                        end
                    )
                ),
                stb, latb, (0, 9), gg_params()
            )
        end
        try
            for every in (1, 2),
                    (form, fused, fault) in (
                        ("staged", false, 0), ("fused", true, 0),
                        ("fused → staged", true, CorePotts._FORM_FUSED),
                    )

                alg = CheckerboardCPM()
                # the reference runs the form that ends up running
                CorePotts._FORCE_FUSED_LIFECYCLE[] = fused && fault == 0
                ref = solve(make(false, every), alg; saveat = 1)
                CorePotts._FORCE_FUSED_LIFECYCLE[] = fused
                CorePotts._LAUNCH_FAULT[] = fault
                sol = if fault == 0
                    solve(make(true, every), alg; saveat = 1)
                else
                    @test_logs (:warn, r"cannot launch") solve(
                        make(true, every), alg;
                        saveat = 1
                    )
                end
                CorePotts._LAUNCH_FAULT[] = 0
                @test sol.stats.lifecycle.divisions == ref.stats.lifecycle.divisions >= 3
                @test all(
                    i -> sol.u[i].ownership == ref.u[i].ownership &&
                        sol.u[i].cell == ref.u[i].cell,
                    eachindex(ref.u)
                )
                # one launch fewer per checked MCS
                fault == 0 && @test sol.stats.launches == ref.stats.launches - cld(9, every)
            end
        finally
            CorePotts._LAUNCH_FAULT[] = 0
            CorePotts._FORCE_FUSED_LIFECYCLE[] = false
        end
    end
end
