# Site conversion, part 2 of 2:
# the shared ownership-delta routine, its priority, the ownership hooks and A-17.
# Part 1, `convert_tests.jl`, pins `@convert` itself (its header states the
# `@convert` API used below).
#
# Decisions: D-075 (api-synthesis §2.9: one host routine, priority remove > convert >
# transition > divide > create; "ownership hooks apply `clear_on_ownership_change`; `@on_copy`
# never fires from the lifecycle"), D-233 (the convert pass as kernels whose paint goes
# through the same routine, in device form), D-145 (`@schedule`), D-036 (clusters divide as a
# unit), D-066 (allocation, `birth`), D-089 (device planner), D-048.
# AUDIT A-17 (MED, lifecycle.jl): "A cluster member's transition is lost when its cluster
# divides in the same MCS. Fix: apply transitions before the cluster split, or carry them
# over." Group 3b (AUDIT fix log) carried a MEMBER's transition over
# (`_EVENT_DIVIDE_CLUSTER_TRANSITION`), but applied it AFTER the split and after the
# daughter state rules: the transition's `kind` hook then reads the post-split cell (a
# `Split()` quantity already halved) and the daughter rules read the pre-transition kind; and
# the cluster ROOT, whose trigger must return its cluster's division, still cannot
# transition in that MCS (one event code per cell). R8's priority "transition > divide"
# fixes both: transitions are applied before the split.
#
# =========================================================================================
# THE PUBLIC API AND SEMANTICS THESE TESTS EXPECT
# =========================================================================================
#
# A. The routine and its priority. Every ownership change outside a copy (a removal, a
#    conversion, a transition, a division, a creation) is applied by one routine that keeps
#    every tracker exact (volume, surface, moments, cluster volume, contact counts), links,
#    cluster roots, the frozen mask, and applies the hooks (B). Within one ROUND of the
#    routine the operations are applied in the order remove > convert > transition > divide
#    > create:
#    - triggers are evaluated on the state at the start of the round;
#    - a removed cell takes no other operation of the round (a member removed while its
#      cluster divides is not divided);
#    - a cell that transitions and divides in one round transitions FIRST: the `kind` hook
#      reads the pre-division cell, the division state rules read the NEW kind, and both
#      halves carry it (A-17);
#    - allocation is lowest-first in that order: cells created by conversions before
#      division daughters, daughters before `@create` cells (later work).
#    Rounds: the lifecycle entry of the schedule is one round; each firing of a `@convert`
#    pass is one round. Rounds run in `@schedule` order; an unlisted `@convert` runs right
#    before `lifecycle` (convert_tests.jl C), so by default a conversion is applied before
#    the transitions and divisions of the same MCS, as the priority says, and those see the
#    converted state (a lamellipodium created in an MCS divides with its cluster in that
#    MCS). `@schedule …, lifecycle, protrusion` reverses that, deliberately.
# B. Ownership hooks (D-075 clarify). At every site whose OWNER changes in the routine
#    (converted sites, a division daughter's sites, a removed cell's sites), every site
#    variable declared `[clear_on_ownership_change = true]` is reset to its declared default;
#    other site variables are untouched; a transition (owner unchanged) clears nothing.
#    `@on_copy` updates NEVER run from the routine (no source, no ΔH: they are copy scope);
#    they still run on every accepted copy of the sweep.
# C. CorePotts (hand-written lifecycles, as `Lifecycle(trigger; kind, divide!, …)`):
#    - `CorePotts.transitioning(event)` (new, public): the trigger's return value for a cell
#      that both transitions (to `kind(st, p, ctx, key, mcs, c)`) and has `event`, one of
#      `EVENT_DIVIDE` (it divides alone) or `EVENT_DIVIDE_CLUSTER` (its cluster divides, the
#      cell being the root). It composes with `ruled_event` (`ruled_event(transitioning(e),
#      i)`). The transition is applied before the division (A).
#    - `EVENT_TRANSITION` of a member whose cluster divides in the same round: as above.
#    - `stats.lifecycle.transitions` counts transitioning cells (one per cell whose trigger
#      asked for it, not per half); `divisions` counts divisions (one per divided cell).
#    - `EVENT_REMOVE` of a member whose cluster divides: the member is removed, not divided
#      (unchanged; pinned).
# D. Not pinned here: removal-time and transition-time hooks in the DSL (`@retire`,
#    `@transition` are later work; B is tested through divisions and conversions); `@create`
#    (later work); "remove > convert" inside one round (it needs `@retire … sites => ref`, later work).
#
# Sections: 1 fixtures; 2 the priority across the convert pass and the lifecycle (DSL);
# 3 hooks: `clear_on_ownership_change` and no `@on_copy`, with controls; 4 A-17 and the
# priority inside a lifecycle round (CorePotts); 5 device.

@testsetup module OwnershipDeltaSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Test, Potts, PottsModels
using Potts: CorePotts
const ON_DEVICE = PottsDevices.on_device()
const DEFINE_ERRORS = Dict{Symbol, Any}()
function define(name::Symbol, ex::Expr)
    try
        Core.eval(@__MODULE__, ex)
    catch e
        DEFINE_ERRORS[name] = e isa LoadError ? e.error : e
    end
    return nothing
end
function ownership_model(name::Symbol)
    if isdefined(@__MODULE__, name)
        return getfield(@__MODULE__, name)
    else
        error("convert fixture $name did not build: $(get(DEFINE_ERRORS, name, "unknown"))")
    end
end
system(name::Symbol; sysname = :m) = Base.invokelatest(ownership_model(name); name = sysname)
vol(u) = Array(u.cell.volume)
col(u, n) = Array(getfield(u.cell, n))
alive(u) = findall(>(0), vol(u))
# ---------------------------------------------------------------------------------------
# Fixtures

# O1. A cluster that converts and divides in the same MCS. Kinds: medium 0, cytoplasm 1,
# lamellipodium 2, nucleus 3. The sweep is frozen (`mobile = 0`): only the routine moves
# sites. `act` is cleared on ownership change and written by `@on_copy`; `keepv` is not
# cleared; `hits` counts copies gained (`@on_copy`).
function own_src(name, schedule)
    stmts = Any[
        :(@kinds medium cytoplasm lamellipodium nucleus),
        :(
            @parameters begin
                c = 1.0
                Vt3 = 100.0
                mobile = 0.0
                dv = 1.0
                T = 4.0
            end
        ),
        :(
            @variables begin
                sub(site) = 0.0
                act(site) = 0.0, [clear_on_ownership_change = true]
                keepv(site) = 0.0
                hits(cell) = 0.0
                V_target(cell) = 0.0
                births(model) = 0.0
            end
        ),
        :(@lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))),
        :(
            @energy begin
                cells => (volume - V_target)^2 + 0.1 * surface
                contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 1.0, 3.0)
            end
        ),
        :(@constraint mobile > 0.5),
        :(@on_copy act[target] ~ 5.0),
        :(@on_copy hits[new] ~ Pre(hits[new]) + 1),
        :(
            @convert protrusion clusters(cytoplasm) begin
                from = sibling(cytoplasm)
                to = sibling(lamellipodium) | Fresh(lamellipodium)
                at = sub > 0.5
                p = c * (1 - volume[to] / Vt3)
                V_target[to] += 1.0
                births += created
            end
        ),
        :(@divide clusters(cytoplasm) when = (mcs == 0) && (dv > 0.5), along = (0.0, 1.0)),
        :(@observed bth(cell) ~ birth),
    ]
    schedule === nothing || push!(stmts, schedule)
    push!(stmts, :(@sweep Metropolis(; temperature = T)))
    return Expr(:macrocall, Symbol("@potts_model"), LineNumberNode(0, :ownership), name, Expr(:block, stmts...))
end
define(:Own, own_src(:Own, nothing))
define(:OwnLate, own_src(:OwnLate, :(@schedule sweep, lifecycle, protrusion)))
# cytoplasm 1: σ[5:12, 5:12] minus the nucleus 2 (σ[8:9, 8:9]), 60 sites; one cluster, no
# lamellipodium. `sub` = 1 on σ[12, 5:12] (8 cytoplasm sites). Vt3 = 100: p = 1 for every
# candidate. The cluster's centroid is (8.5, 8.5) (with or without the conversion: the
# cluster's sites do not change); the plane along (0, 1) splits columns 5:8 | 9:12:
# cytoplasm 30 | 30 (26 | 26 after the conversions), nucleus 2 | 2, the row-12 sites 4 | 4.
function sigma()
    σ = zeros(Int32, 24, 24)
    σ[5:12, 5:12] .= 1
    σ[8:9, 8:9] .= 2
    return σ
end
function own_problem(name = :Own; seed = 1, tspan = (0, 1), T = Float64, kw...)
    sub = zeros(24, 24)
    sub[12, 5:12] .= 1.0
    prob = PottsProblem(
        system(name; sysname = :own), [
            ownership => sigma(), kind => [:cytoplasm, :nucleus],
            cluster => [1, 1], :sub => sub, :act => fill(7.0, 24, 24), :keepv => fill(7.0, 24, 24),
            :V_target => [60.0, 4.0],
        ], tspan; seed, T, capacity = 8
    )
    return isempty(kw) ? prob : remake(prob; p = [k => v for (k, v) in kw])
end
# O2. A hand-written CorePotts lifecycle on a Potts model (as `frozen_kind_mask_tests.jl`/`device_lifecycle_tests.jl` do). Kinds: medium
# 0, cyto 1, nuc 2, big 3. Cluster: cyto 1 (root, σ[5:12, 5:12] minus nuc 2 at σ[8:9, 8:9]);
# lone cyto 3 (σ[16:19, 5:12]). q = [20, 12, 14]. The `kind` hook sends a cell with q ≥ 10
# to `big`; the division rules split q and record the parent's kind in `tagk`.
@potts_model A17 begin
    @kinds medium cyto nuc big
    @parameters begin
        mobile = 0.0
        T = 1.0
    end
    @variables begin
        q(cell) = 0.0
        tagk(cell) = 0.0
    end
    @lattice Lattice((24, 24); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 16)^2
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 1.0, 3.0)
    end
    @constraint mobile > 0.5
    @divide clusters(cyto) when = volume >= 100000, along = (0.0, 1.0)     # never fires (it builds the cluster machinery)
    @observed bth(cell) ~ birth
    @sweep Metropolis(; temperature = T)
end
struct Trigger
    root::Int32     # the root's event at mcs 0
    member::Int32   # member 2's event
    lone::Int32     # lone cell 3's event
end
function (t::Trigger)(st, p, ctx, key, mcs, c)
    if mcs != 0
        return EVENT_NONE
    elseif c == 1
        return t.root
    elseif c == 2
        return t.member
    elseif c == 3
        return t.lone
    else
        return EVENT_NONE
    end
end
struct Kind end
(::Kind)(st, p, ctx, key, mcs, c) = st.cell.q[c] >= 10 ? Int32(3) : st.cell.kind[c]
struct Normal end
(::Normal)(st, p, ctx, key, mcs, c) = (0.0f0, 1.0f0)
struct Rule end
function (::Rule)(st, p, ctx, key, mcs, parent, daughter)
    h = st.cell.q[parent] / 2
    st.cell.q[parent] = h
    st.cell.q[daughter] = h
    k = st.cell.kind[parent]
    st.cell.tagk[parent] = k
    st.cell.tagk[daughter] = k
    return nothing
end
function a17_problem(trig; T = Float64, tspan = (0, 1))
    σ = zeros(Int32, 24, 24)
    σ[5:12, 5:12] .= 1
    σ[8:9, 8:9] .= 2
    σ[16:19, 5:12] .= 3
    prob = PottsProblem(
        A17(; name = :a17), [
            ownership => σ, kind => [:cyto, :nuc, :cyto], cluster => [1, 1, 3],
            :q => [20.0, 12.0, 14.0],
        ], tspan; T, capacity = 8
    )
    f = prob.f
    lc = Lifecycle(
        trig; kind = Kind(), normal = Normal(), cluster_normal = Normal(),
        divide! = Rule(), cluster_divide! = Rule()
    )
    g = CPMFunction(
        f.delta_H; f.commit!, f.constraint, f.temperature, f.bias, f.phases,
        lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys
    )
    return remake(prob; f = g)
end
# the new combinator, or a clean error today
function ownership_transitioning(e)
    if isdefined(CorePotts, :transitioning)
        return CorePotts.transitioning(e)
    else
        error("CorePotts.transitioning is not defined")
    end
end
# (kind, q, tagk) of the alive cells, sorted; cells of the cluster (not the lone cell 3)
function ownership_cells(u; skip = ())
    return sort(
        [
            (Int(col(u, :kind)[c]), col(u, :q)[c], col(u, :tagk)[c])
                for c in alive(u) if !(c in skip)
        ]
    )
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "convert ownership: the fixtures build" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Fixtures
    @testset "convert ownership: the fixtures build" begin
        @test isdefined(@__MODULE__, :Own)                      # DEFECT CHECK: `@convert` unknown today
        @test isdefined(@__MODULE__, :OwnLate)
        u = a17_problem(Trigger(EVENT_NONE, EVENT_NONE, EVENT_NONE)).u0
        @test vol(u)[1:3] == [60, 4, 32]                       # fixture
        @test col(u, :cluster)[1:3] == [1, 1, 3]
        @test col(u, :kind)[1:3] == [1, 2, 1]
    end
end

@testitem "convert ownership: convert before divide by default; the schedule can reverse it" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. The priority across the convert pass and the lifecycle (DSL)
    @testset "convert ownership: convert before divide by default; the schedule can reverse it ($(nameof(typeof(alg))))" for alg in
        (SequentialCPM(), CheckerboardCPM())
        # default: the pass (MCS 0) creates the lamellipodium, then the cluster divides with it
        prob = own_problem()
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        u = sol.u[end]
        a = alive(u)
        kd = col(u, :kind); v = vol(u); cl = col(u, :cluster); vt = col(u, :V_target)
        bth = observe(prob, :bth, u)
        @test length(a) == 6                                         # DEFECT CHECK
        lam = filter(c -> kd[c] == 2, a)
        @test length(lam) == 2 && all(c -> v[c] == 4, lam)           # the created cell divided in its MCS
        @test sort(bth[lam])[1] == 3                                 # created first (serial 3), then the daughters
        @test sort(bth[a]) == 1:6
        @test all(c -> vt[c] == 8.0, lam)                            # 8 conversions, then copied to the daughter
        @test u.model.births[1] == 1.0
        @test sort(v[filter(c -> kd[c] == 1, a)]) == [26, 26] && sort(v[filter(c -> kd[c] == 3, a)]) == [2, 2]
        # two clusters, each one cytoplasm, one nucleus, one lamellipodium
        roots = unique(cl[a])
        @test length(roots) == 2
        @test all(r -> sort(kd[filter(c -> cl[c] == r, a)]) == [1, 2, 3], roots)
        @test col(u, :cluster_volume) == CorePotts.recompute_cluster_volume(Array(u.ownership), cl)
        # reversed: the cluster divides first; then each half converts its own 4 candidates
        probl = own_problem(:OwnLate)
        w = solve(probl, alg).u[end]
        b = alive(w)
        kdw = col(w, :kind); vw = vol(w); clw = col(w, :cluster)
        laml = filter(c -> kdw[c] == 2, b)
        @test length(b) == 6 && length(laml) == 2
        @test sort(observe(probl, :bth, w)[laml]) == [5, 6]          # daughters took 3, 4
        @test all(c -> vw[c] == 4 && col(w, :V_target)[c] == 4.0, laml)
        @test w.model.births[1] == 2.0
        @test all(r -> sort(kdw[filter(c -> clw[c] == r, b)]) == [1, 2, 3], unique(clw[b]))
        # control: without the division the pass alone makes one lamellipodium of 8
        u0 = solve(own_problem(; dv = 0.0), alg).u[end]
        @test count(==(2), col(u0, :kind)[alive(u0)]) == 1 && maximum(vol(u0)[alive(u0)]) == 60 - 8
    end
end

@testitem "convert ownership: the routine clears `clear_on_ownership_change` and never fires @on_copy" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. Hooks: clear_on_ownership_change applied, @on_copy never fired
    @testset "convert ownership: the routine clears `clear_on_ownership_change` and never fires @on_copy ($(name))" for name in
        (:Own, :OwnLate)
        prob = own_problem(name)
        u = solve(prob, SequentialCPM()).u[end]
        σ0, σ1 = sigma(), Array(u.ownership)
        changed = σ0 .!= σ1
        # fixture: the 8 conversions, the daughter cytoplasm's 26 and nucleus's 2 (either order:
        # default, the lamellipodium's daughter half is among the 8; reversed, the daughter
        # cytoplasm's 4 row-12 sites convert again)
        @test count(changed) == 36
        act = Array(u.site.act)
        @test all(==(0.0), act[changed])                             # DEFECT CHECK: reset to the declared default
        @test all(==(7.0), act[.!changed])                           # untouched where the owner did not change
        @test all(==(7.0), Array(u.site.keepv))                      # not declared: never cleared
        @test !any(==(5.0), act)                                     # @on_copy did not run
        @test all(==(0.0), col(u, :hits))
        # the converted sites changed owner too (not only the daughters')
        @test all(changed[12, 5:12])
    end
end

@testitem "convert ownership: controls (the hooks are live on copies)" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "convert ownership: controls (the hooks are live on copies)" begin
        # the sweep unfrozen: @on_copy runs on accepted copies (act = 5 at targets, hits counted)
        prob = own_problem(; mobile = 1.0, dv = 0.0, tspan = (0, 5))
        u = solve(prob, SequentialCPM()).u[end]
        @test sum(col(u, :hits)) > 0
        @test any(==(5.0), Array(u.site.act))
        # and frozen with no event: nothing changes, nothing is cleared
        prob0 = own_problem(; dv = 0.0, c = 0.0)
        u0 = solve(prob0, SequentialCPM()).u[end]
        @test Array(u0.ownership) == sigma()
        @test all(==(7.0), Array(u0.site.act))
    end
end

@testitem "convert ownership: A-17, a member transitions before its cluster splits" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. A-17 and the priority inside a lifecycle round (CorePotts)
    @testset "convert ownership: A-17, a member transitions before its cluster splits ($(nameof(typeof(alg))))" for alg in
        (SequentialCPM(), CheckerboardCPM())
        prob = a17_problem(Trigger(EVENT_DIVIDE_CLUSTER, EVENT_TRANSITION, EVENT_NONE))
        sol = solve(prob, alg)
        @test Symbol(sol.retcode) === :Success
        u = sol.u[end]
        @test length(alive(u)) == 5                            # 1, 2, the lone 3, two daughters
        @test sol.stats.lifecycle.divisions == 2
        @test sol.stats.lifecycle.transitions == 1
        # the transition read q = 12 BEFORE the split (≥ 10): both halves are `big`, and the
        # division rule saw the new kind (tagk = 3); the root stays cytoplasm
        @test ownership_cells(u; skip = (3,)) == [(1, 10.0, 1.0), (1, 10.0, 1.0), (3, 6.0, 3.0), (3, 6.0, 3.0)]   # DEFECT CHECK
        @test !any(==(2), col(u, :kind)[alive(u)])       # the transition is not lost
        @test col(u, :kind)[3] == 1                            # control: the lone cell had no event
        @test vol(u)[alive(u)] |> sort == [2, 2, 30, 30, 32]
    end
end

@testitem "convert ownership: A-17, the root transitions and its cluster divides (`transitioning`)" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "convert ownership: A-17, the root transitions and its cluster divides (`transitioning`)" begin
        prob = a17_problem(Trigger(ownership_transitioning(EVENT_DIVIDE_CLUSTER), EVENT_TRANSITION, EVENT_NONE))
        sol = solve(prob, SequentialCPM())
        u = sol.u[end]
        @test sol.stats.lifecycle.transitions == 2 && sol.stats.lifecycle.divisions == 2
        @test ownership_cells(u; skip = (3,)) == [(3, 6.0, 3.0), (3, 6.0, 3.0), (3, 10.0, 3.0), (3, 10.0, 3.0)]
        # the clusters are intact: two clusters of two `big` cells
        cl = col(u, :cluster)
        a = filter(!=(3), alive(u))
        @test length(unique(cl[a])) == 2 && all(r -> count(==(r), cl[a]) == 2, unique(cl[a]))
        # a lone cell that transitions and divides alone
        prob2 = a17_problem(Trigger(EVENT_NONE, EVENT_NONE, ownership_transitioning(EVENT_DIVIDE)))
        sol2 = solve(prob2, SequentialCPM())
        u2 = sol2.u[end]
        @test sol2.stats.lifecycle.transitions == 1 && sol2.stats.lifecycle.divisions == 1
        @test ownership_cells(u2; skip = (1, 2)) == [(3, 7.0, 3.0), (3, 7.0, 3.0)]
        @test col(u2, :kind)[1:2] == [1, 2]                   # control: the cluster had no event
        # ruled events compose
        @test CorePotts.ruled_event(ownership_transitioning(EVENT_DIVIDE), 2) >> 8 == 2
    end
end

@testitem "convert ownership: remove beats divide in one round" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "convert ownership: remove beats divide in one round" begin
        prob = a17_problem(Trigger(EVENT_DIVIDE_CLUSTER, EVENT_REMOVE, EVENT_NONE))
        sol = solve(prob, SequentialCPM())
        u = sol.u[end]
        @test sol.stats.lifecycle.removals == 1 && sol.stats.lifecycle.divisions == 1
        @test vol(u)[2] == 0                                   # removed, not divided
        @test all(==(0), Array(u.ownership)[8:9, 8:9])                       # its sites went to the medium
        @test ownership_cells(u; skip = (3,)) == [(1, 10.0, 1.0), (1, 10.0, 1.0)]
        @test !any(==(2), col(u, :kind)[alive(u)])
    end
end

@testitem "convert ownership: the routine on the device (Float32)" setup = [OwnershipDeltaSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 5. Device
    @testset "convert ownership: the routine on the device (Float32)" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM(; proposal = Moore(1))
            # O1 on CPU and device, Float32: the same cells (kind, site set, V_target) and the
            # same hook results, up to a relabelling of the slots the CPU uses (as `device_lifecycle_tests.jl`)
            function sig(u)
                return sort(
                    [
                        (Int(col(u, :kind)[c]), sort(findall(==(c), vec(Array(u.ownership)))), Float64(col(u, :V_target)[c]))
                            for c in alive(u)
                    ]
                )
            end
            for name in (:Own, :OwnLate)
                cpu = solve(own_problem(name; T = Float32), SequentialCPM()).u[end]
                dev = solve(own_problem(name; T = Float32), alg; backend).u[end]
                @test sig(dev) == sig(cpu)
                @test Array(dev.site.act) == Array(cpu.site.act)
                @test all(==(0.0f0), col(dev, :hits))
                @test sort(Array(dev.cell.birth)[alive(dev)]) == 1:6
            end
            # A-17 on the device
            for trig in (
                    Trigger(EVENT_DIVIDE_CLUSTER, EVENT_TRANSITION, EVENT_NONE),
                    Trigger(ownership_transitioning(EVENT_DIVIDE_CLUSTER), EVENT_TRANSITION, EVENT_NONE),
                )
                cpu = solve(a17_problem(trig; T = Float32), SequentialCPM())
                dev = solve(a17_problem(trig; T = Float32), alg; backend)
                @test ownership_cells(dev.u[end]; skip = (3,)) == ownership_cells(cpu.u[end]; skip = (3,))
                @test dev.stats.lifecycle.transitions == cpu.stats.lifecycle.transitions
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end
