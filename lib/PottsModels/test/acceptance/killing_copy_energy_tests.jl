# the energy of a killing copy.
# Decision: D-066 item 4 (amends D-037); follows D-079 (`link_partner_death_tests.jl`, the dead-partner skip).
#
# The defect. A copy that takes the last site of a linked cell `o` (a killing copy) reports
# a ΔH that leaves o's edges in place: `centroid_shift` returns 0 for a cell going to
# volume 0, so `link_delta` evaluates o's edges at o's pre-copy centroid, while
# `total_energy` drops them (both ends must be alive, D-079). The killing copy's ΔH
# therefore differs from H(after) − H(before) by exactly the edge credit (a
# probe: 4.56, 146.55). And `total_energy` sums cell and cluster terms over every slot, so
# a dead cell still contributes E(empty state).
#
# D-066 item 4 prescribes (quoted):
#   "`total_energy` sums: cell terms over alive cells; cluster terms over roots `r`
#   (`cluster[r] == r`) of clusters with at least one alive member [...]; edge terms over
#   links whose two ends are both alive. A dead cell contributes nothing."
# The scope: "the killing copy's ΔH credits the dead cell's edge energy", and
#   "Accept: for every copy, including a killing copy, ΔH equals the H difference on a
#   linked model."
#
# Semantics pinned here. For a copy whose old owner `o` it kills (credits per D-066 item 4,
# with the edge credit folded into ΔH):
#
#     ΔH(copy) == H(after) − H(before) + E_cell(o, empty state)
#                 [+ E_cluster(cluster[o], empty state), if that cluster has no alive member]
#
# and for every other copy ΔH(copy) == H(after) − H(before). There is NO edge credit: the
# killing copy's ΔH itself removes o's edges, at their pre-copy energy. In the linked
# fixtures the dying kind has E_cell(empty) = 0, so there ΔH equals the H difference
# literally, for every copy.
#  1. Brute force: every Moore(1) copy of a small linked state in which a cell with two live
#     links owns one site (killing copies by medium and by a linked partner included).
#  2. Trajectories (SequentialCPM, CheckerboardCPM): every copy touching the dying cell on
#     every saved state before its death, then a deterministic peeling sequence that copies
#     it away site by site, its killing copy, and every copy touching the survivor after.
#  3. Dead cells leave H: a killed cell with E_cell(empty) ≠ 0 contributes nothing to
#     `total_energy` (independent oracle: the same σ built without it); a cluster with no
#     alive member contributes nothing, and a cluster whose copy-killed root still has an
#     alive member keeps its term.
#  4. Behaviour (CPU and Metal): a cell whose spring is stretched past its own cost of
#     dying is killed during the run (with the edge credit missing from ΔH, the killing
#     copy costs +λd and is never accepted at T = 1).
#  5. Negative controls: the check is sensitive (copies with a nonzero edge change exist
#     and match; dropping the edge credit, or the cell credit, is detected).
#
# Entry points: `energy_change` and `total_energy` (public); a copy is applied as in the
# self-check helpers (`σ[t] = new` plus the model's `prob.f.commit!`).

@testsetup module KillingCopyEnergySetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
# Linked fixture: blob (V₀ = 36) and doomed (λd·volume², so E(empty) = 0) cells, all linked.
@potts_model Linked begin
    @kinds medium blob doomed
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        λd = 50.0
        T = 10.0
        k = 2.0
        ℓ = 12.0
        J[kind, kind] = [0 16 16; 16 2 16; 16 16 2]
    end
    @relationship bond(cell, cell) capacity = 2
    @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        cells(doomed) => λd * volume^2
        contacts => J[kind, neighbor_kind]
        edges(bond) => k * (distance - ℓ)^2
    end
    @sweep Metropolis(; temperature = T)
end
# Snap fixture (part 4): dying costs the doomed cell +λd (E = λd·V(V − 2): E(1) = −λd,
# E(0) = E(2) = 0, so it neither dies nor grows on its own at T = 1), but frees a spring
# stretched by ≈ 10.5 (k (d − ℓ)² ≈ 110 > λd). Contacts with medium are free.
@potts_model Snap begin
    @kinds medium blob doomed
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        λd = 50.0
        T = 1.0
        k = 1.0
        ℓ = 12.0
        J[kind, kind] = [0 16 0; 16 2 16; 0 16 2]
    end
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        cells(doomed) => λd * volume * (volume - 2)
        contacts => J[kind, neighbor_kind]
        edges(bond) => k * (distance - ℓ)^2
    end
    @sweep Metropolis(; temperature = T)
end
# Cluster fixture (part 3): cytoplasm roots carry a cluster term.
@potts_model Clusters begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        λ = 1.0
        V₀[kind] = [0.0, 36.0, 4.0]
        λc = 1.0
        Vc = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 8; 16 8 2]
    end
    @lattice Lattice((30, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => J[kind, neighbor_kind]
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2
    end
    @sweep Metropolis(; temperature = T)
end
const LAMBDA = 1.0
const KILLING_V0 = 36.0
const KILLING_K = 2.0
const ELL = 12.0
# Small linked state: blobs 1 (rows 4:9, cols 12:17) and 2 (rows 25:30, cols 12:17); cell 3
# owns the single site (10, 15), next to blob 1 (so blob 1 can take it). Links 1–3, 2–3
# (cell 3 has two live links) and 1–2. Kinds: cell 3 doomed (E(empty) = 0) or blob
# (E(empty) = λ V₀²).
function small(; kind3 = :doomed)
    σ = zeros(Int32, 40, 30)
    σ[4:9, 12:17] .= 1
    σ[25:30, 12:17] .= 2
    σ[10, 15] = 3
    return PottsProblem(
        Linked(; name = :killing_copy), [
            ownership => σ, kind => [:blob, :blob, kind3],
            :bond => [(1, 3), (2, 3), (1, 2)],
        ], (0, 10)
    )
end
# the `link_partner_death_tests.jl` trajectory fixture (blob 1, doomed 2×2 cell 2, bonded), with capacity 2
function pair(; tspan = (0, 30), seed = 1)
    σ = zeros(Int32, 40, 30)
    σ[8:13, 12:17] .= 1
    σ[24:25, 14:15] .= 2
    return PottsProblem(
        Linked(; name = :killing_copy), [ownership => σ, kind => [:blob, :doomed], :bond => [(1, 2)]],
        (tspan[1], tspan[2]); seed
    )
end
# snap fixture: blob centroid (6.5, 14.5), doomed single site (29, 15): d ≈ 22.5
function killing_snap(; tspan = (0, 20), seed = 1, T = Float64)
    σ = zeros(Int32, 40, 30)
    σ[4:9, 12:17] .= 1
    σ[29, 15] = 2
    return PottsProblem(
        Snap(; name = :snap), [ownership => σ, kind => [:blob, :doomed], :bond => [(1, 2)]],
        (tspan[1], tspan[2]); seed, T
    )
end
ctx(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...)
vol(u) = Array(u.cell.volume)
# every Moore(1) copy (target t takes source s's owner); `touching` restricts to copies
# whose old or new owner is in the set
function killing_props(prob, u; touching = nothing)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    σ = Array(u.ownership)
    out = CorePotts.Proposal{2}[]
    for t in eachindex(σ)
        x = CorePotts.coordinates(lat, t)
        for kk in 1:length(moore)
            ins, y = CorePotts.shift(lat, x, moore.offsets[kk])
            ins || continue
            s = CorePotts.linear_index(lat, y)
            σ[t] == σ[s] && continue
            touching === nothing || σ[t] in touching || σ[s] in touching || continue
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end
# the state after `prop` (as the self-check helpers apply a copy)
function apply(prob, u, prop)
    a = deepcopy(u)
    a.ownership[prop.target] = prop.new
    prob.f.commit!(a, prob.p, prop, ctx(prob))
    return a
end
killing_kills(u, prop) = prop.old != 0 && vol(u)[prop.old] == 1
# ΔH − (H(after) − H(before)) − credit(u, prop, after): 0 for every copy under D-066 item 4
function gap(prob, u, prop; credit = (u, prop, a) -> 0.0)
    a = apply(prob, u, prop)
    return energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u)) - credit(u, prop, a)
end
# independent oracle for the edge energy of the link a–b from σ (closed lattice: plain mean)
function killing_centroid(σ, c)
    idx = findall(==(c), σ)
    return (sum(i -> i[1], idx) / length(idx), sum(i -> i[2], idx) / length(idx))
end
function edge(σ, a, b)
    ca = killing_centroid(σ, a); cb = killing_centroid(σ, b)
    return KILLING_K * (hypot(ca[1] - cb[1], ca[2] - cb[2]) - ELL)^2
end
# ---------------------------------------------------------------------------------------
# 4. Behaviour: the credited ΔH lets a stretched spring kill its cell (CPU and Metal)
function snap_check(sol)
    @test Symbol(sol.retcode) === :Success
    @test sol.t[end] == 20
    v2 = [vol(u)[2] for u in sol.u]
    @test v2[1] == 1                                             # alive at the start
    @test v2[end] == 0                                           # DEFECT CHECK (currently 1: the copy costs +λd)
    @test all(u -> vol(u)[1] > 0, sol.u)
    return nothing
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "killing copy energy: ΔH equals the H difference for every copy, killing copies included" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Brute force on a small linked state: every copy, including the killing copies
    @testset "killing copy energy: ΔH equals the H difference for every copy, killing copies included" begin
        prob = small()
        u = prob.u0
        @test vol(u) == [36, 36, 1]
        @test linked(CorePotts.link_store(u.cell, :bond), 1, 3) && linked(CorePotts.link_store(u.cell, :bond), 2, 3)
        props = killing_props(prob, u)
        kills = filter(p -> killing_kills(u, p), props)
        # fixture: killing copies by medium and by a linked partner (blob 1 takes the site)
        @test any(p -> p.new == 0, kills) && any(p -> p.new == 1, kills)
        @test length(props) > 100
        gaps = [gap(prob, u, p) for p in props]
        @test all(isfinite, gaps)
        for (p, g) in zip(props, gaps)
            killing_kills(u, p) || continue
            @test abs(g) < 1.0e-9                                      # DEFECT CHECK (currently the edge credit)
        end
        @test maximum(abs, gaps) < 1.0e-9                              # every copy
        # the killing copy's ΔH removes both of cell 3's edges at their pre-copy energy
        # (independent oracle on σ): ΔH(kill by medium) = contact + cell change − E₁₃ − E₂₃
        σ = Array(u.ownership)
        edges3 = edge(σ, 1, 3) + edge(σ, 2, 3)
        @test edges3 > 1.0                                           # both live links carry energy
        pm = first(filter(p -> p.new == 0, kills))
        unlinked = deepcopy(u); remove_incident!((; links = unlinked.cell.links__bond), 3)
        @test energy_change(prob, u, pm) ≈ energy_change(prob, unlinked, pm) - edges3 atol = 1.0e-9   # DEFECT CHECK
    end
end

@testitem "killing copy energy: ΔH equals the H difference along a run to a death" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2. Trajectories: every copy around a cell that dies by copies
    @testset "killing copy energy: ΔH equals the H difference along a run to a death ($(nameof(typeof(alg))))" for alg in
        (SequentialCPM(), CheckerboardCPM())
        prob = pair()
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        vols = [vol(u)[2] for u in sol.u]
        i = findfirst(==(0), vols)
        @test i !== nothing && i >= 2                                # fixture: cell 2 dies by copies during the run
        pre = sol.u[1:(i - 1)]                                       # cell 2 alive
        worst = 0.0
        for u in pre, p in killing_props(prob, u; touching = (2,))
            worst = max(worst, abs(gap(prob, u, p)))
        end
        @test worst < 1.0e-9
        # peel cell 2 from the last state before its death: each step copies the neighbour
        # owner into cell 2's lowest site; the last step is the killing copy. Every copy
        # touching cell 2 is checked on every intermediate state.
        u = deepcopy(pre[end])
        nkill = 0
        while vol(u)[2] > 0
            props = killing_props(prob, u; touching = (2,))
            for p in props
                g = gap(prob, u, p)
                killing_kills(u, p) && (nkill += 1; @test abs(g) < 1.0e-9)   # DEFECT CHECK (currently the edge credit)
                worst = max(worst, abs(g))
            end
            t = minimum(findall(==(2), vec(Array(u.ownership))))
            step = first(filter(p -> p.target == t && p.old == 2, props))
            u = apply(prob, u, step)
        end
        @test nkill > 0
        @test worst < 1.0e-9
        # after the death: copies touching the survivor still match
        @test isfinite(total_energy(prob, u))
        @test maximum(p -> abs(gap(prob, u, p)), killing_props(prob, u; touching = (1,))) < 1.0e-9
    end
end

@testitem "killing copy energy: a copy-killed cell's cell term leaves H" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 3. A dead cell, and a cluster without an alive member, leave H
    @testset "killing copy energy: a copy-killed cell's cell term leaves H" begin
        prob = small(; kind3 = :blob)                           # E_cell(3, empty) = λ V₀² ≠ 0
        u = prob.u0
        Eempty = LAMBDA * KILLING_V0^2
        kills = filter(p -> killing_kills(u, p), killing_props(prob, u))
        @test !isempty(kills)
        for p in kills
            a = apply(prob, u, p)
            @test vol(a)[3] == 0
            # independent oracle: H of the same σ built with cells 1, 2 only (and their link)
            fresh = PottsProblem(
                Linked(; name = :killing_copy), [
                    ownership => Array(a.ownership), kind => [:blob, :blob],
                    :bond => [(1, 2)],
                ], (0, 10)
            )
            @test total_energy(prob, a) ≈ total_energy(fresh) atol = 1.0e-8                           # DEFECT CHECK (currently + λV₀²)
            # D-066 item 4 self-check: the cell credit only (no edge credit)
            @test abs(gap(prob, u, p; credit = (u, p, a) -> Eempty)) < 1.0e-8                   # DEFECT CHECK
        end
    end
end

@testitem "killing copy energy: cluster terms over clusters with an alive member" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "killing copy energy: cluster terms over clusters with an alive member" begin
        # cluster 1: cytoplasm 1 (6×6, root) with nucleus 2 inside; cluster 3: cytoplasm 3 alone,
        # one site; cluster 4: cytoplasm root 4 (one site) with nucleus 5 (2×2) next to it.
        σ = zeros(Int32, 30, 30)
        σ[3:8, 3:8] .= 1
        σ[5:6, 5:6] .= 2
        σ[15, 15] = 3
        σ[22, 10] = 4
        σ[23:24, 10:11] .= 5
        prob = PottsProblem(
            Clusters(; name = :killing_c), [
                ownership => σ,
                kind => [:cytoplasm, :nucleus, :cytoplasm, :cytoplasm, :nucleus], cluster => [1, 1, 3, 4, 4],
            ], (0, 10)
        )
        u = prob.u0
        @test Array(u.cell.cluster)[1:5] == [1, 1, 3, 4, 4]
        Ecell = 1.0 * 36.0^2                                         # λ (0 − V₀[cytoplasm])²
        Eclus = 1.0 * 40.0^2                                         # λc (0 − Vc)²
        props = killing_props(prob, u)
        k3 = filter(p -> p.old == 3, props)                          # all kill cell 3 (and empty cluster 3)
        k4 = filter(p -> p.old == 4, props)                          # all kill root 4; nucleus 5 stays alive
        @test !isempty(k3) && !isempty(k4) && any(p -> p.new == 5, k4)
        for p in k3
            # cluster 3 has no alive member left: its term leaves H with the cell's
            @test abs(gap(prob, u, p; credit = (u, p, a) -> Ecell + Eclus)) < 1.0e-8             # DEFECT CHECK
        end
        for p in k4
            # cluster 4 keeps an alive member: its term stays in H (named by the dead root)
            @test abs(gap(prob, u, p; credit = (u, p, a) -> Ecell)) < 1.0e-8                    # DEFECT CHECK
        end
        # every other copy: no credit
        rest = filter(p -> !killing_kills(u, p), props)
        @test maximum(p -> abs(gap(prob, u, p)), rest) < 1.0e-8
    end
end

@testitem "killing copy energy: a stretched spring's cell is killed during the run" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "killing copy energy: a stretched spring's cell is killed during the run ($(nameof(typeof(alg))))" for alg in
        (SequentialCPM(), CheckerboardCPM())
        prob = killing_snap()
        u = prob.u0
        # fixture: the killing copy by medium has ΔH = λd − k (d − ℓ)² < −40 (accepted at
        # T = 1); its growth copies cost > 30 (never accepted)
        props = killing_props(prob, u; touching = (2,))
        dk = [energy_change(prob, u, p) for p in props if p.old == 2]
        dg = [energy_change(prob, u, p) for p in props if p.new == 2]
        @test all(<(-40.0), dk)                                      # DEFECT CHECK (currently +50)
        @test all(>(30.0), dg)
        @test maximum(p -> abs(gap(prob, u, p)), props) < 1.0e-9  # DEFECT CHECK
        snap_check(solve(prob, alg; saveat = 1))
        # negative control: without the link the cell is never killed
        free = PottsProblem(Snap(; name = :snap), [ownership => Array(u.ownership), kind => [:blob, :doomed]], (0, 20); seed = 1)
        @test all(u -> vol(u)[2] == 1, solve(free, alg; saveat = 1).u)
    end
end

@testitem "killing copy energy: a partner killed during a device run" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    @testset "killing copy energy: a partner killed during a device run" begin
        if PottsDevices.on_device()
            backend = PottsDevices.device_backend()
            prob = killing_snap(; T = Float32)
            sol = solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 1)
            snap_check(sol)
            # the survivor keeps moving after the death, and H (host, Float32 problem) is finite
            @test isfinite(total_energy(prob, sol.u[end]))
            # the `link_partner_death_tests.jl` trajectory fixture on Metal: the partner dies by copies, the run ends
            pp = PottsProblem(
                Linked(; name = :killing_copy), [
                    ownership => Array(pair().u0.ownership), kind => [:blob, :doomed],
                    :bond => [(1, 2)],
                ], (0, 30); T = Float32
            )
            solp = solve(pp, CheckerboardCPM(; proposal = Moore(1)); backend, saveat = 1)
            @test Symbol(solp.retcode) === :Success
            @test vol(solp.u[1])[2] == 4 && vol(solp.u[end])[2] == 0
            @test vol(solp.u[end])[1] > 0
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "killing copy energy: the check is sensitive (negative controls)" setup = [KillingCopyEnergySetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 5. Negative controls: the check is sensitive
    @testset "killing copy energy: the check is sensitive (negative controls)" begin
        prob = small()
        u = prob.u0
        σ = Array(u.ownership)
        # non-killing copies of blob 1 change its edges (oracle on σ) and still match exactly
        props = filter(p -> !killing_kills(u, p) && (p.old == 1 || p.new == 1), killing_props(prob, u))
        shifts = map(props) do p
            a = copy(σ); a[p.target] = p.new
            (edge(a, 1, 3) + edge(a, 1, 2)) - (edge(σ, 1, 3) + edge(σ, 1, 2))
        end
        @test maximum(abs, shifts) > 0.1                             # the edge change is not a no-op
        @test maximum(p -> abs(gap(prob, u, p)), props) < 1.0e-9
        # a killing copy: D-066's former edge credit, applied on top of a ΔH that already
        # removes the edges, is detected well above tolerance (as is a ΔH that misses them,
        # part 1); and a blob's killing copy needs its cell credit
        pm = first(filter(p -> killing_kills(u, p) && p.new == 0, killing_props(prob, u)))
        edges3 = edge(σ, 1, 3) + edge(σ, 2, 3)
        @test edges3 > 1.0
        @test abs(gap(prob, u, pm; credit = (u, p, a) -> edges3)) > 1.0    # DEFECT CHECK (currently 0)
        blob = small(; kind3 = :blob)
        pb = first(filter(p -> killing_kills(blob.u0, p) && p.new == 0, killing_props(blob, blob.u0)))
        @test abs(gap(blob, blob.u0, pb)) > 1.0                 # the cell credit is needed for a blob
    end
end
