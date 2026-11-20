# the lifecycle on the device.
# Decisions: D-089 (no synchronize on a quiet MCS; the lifecycle is planned on the device),
# D-085 (the transfer counters), D-081 (`frozen_kind_mask_tests.jl` mask counts), D-035 (lifecycle semantics, as
# amended), D-048 (ordinary tests, no parity harness).
#
# What is pinned. On a GPU backend (Metal here), with the counters of D-085
# (`stats.syncs`, `stats.transfers`, `stats.transfer_bytes`):
#  (i)   A quiet lifecycle MCS (no event) costs exactly 0 syncs / 0 transfers / 0 B, for every
#        published model that has a lifecycle and for the fixtures below (F1–F3).
#  (ii)  An event MCS's host traffic is O(events): on a division fixture with the same two
#        divisions, the counter deltas of the event MCS (syncs, transfers, bytes) are the
#        same whether the lattice is 16×8 or 64×32, whether the cells carry 1 or 8 cell
#        quantities besides `V_target`, and whether the capacity is 6 or 60 slots; and for
#        these plain divisions it is exactly 0 syncs / 0 transfers / 0 B (D-089: the whole
#        lifecycle on the device, no host decision). Compartment (F2) and link (F3) event
#        MCS: the same traffic on a 16×16 and a 64×64 lattice (their host planning may stay,
#        O(events); a device link graph is later work).
#  (iii) Events keep their exact MCS and the results are those of the CPU path, in law:
#        division counts, kinds, generations (a reused slot's generation goes up by one),
#        daughters' copied quantities and state rules, compartment clusters (a cluster
#        divides as a unit, the daughters form a new cluster, a lone cell's daughter is
#        lone), links (a removed cell's links are dropped from its partners, a daughter
#        starts unlinked, also in a reused slot), lowest-first slot allocation, and every
#        tracker (volume, surface, centroid and covariance from the moments, cluster volume)
#        equal to an independent recount from σ after the events. The deterministic
#        fixtures (T = 0, every copy rejected) are compared state by state with the CPU,
#        up to a relabelling of the daughters among the slots the CPU uses; a random-plane
#        model (OpenVT) is compared in law over seeds.
#  (iv)  `stats.lifecycle` and the `frozen_kind_mask_tests.jl` mask counts (`stats.attempts`) are exact at the
#        host read points of D-089: a save (after the `step!` that saves), the end of
#        `solve!` (`sol.stats`), `checkpoint` (`ck.stats`) and `current_state(integ)` (`current_state`).
#        Between those points they may lag on a device (documented, not tested);
#        `reinit!`, `set_state!` and `merge` are not pinned.
#  (v)   No GPU wait at all in a quiet lifecycle MCS (OpenVT, Akeeb): Metal.jl's
#        `wait_cmdbuf!` is never called across a quiet window, counted with the
#        test-only wrapper of `test/transfer_counts.jl` (Metal.jl 1.10.0 bodies; another
#        Metal version fails loudly). Control: a checkpoint on the same integrator waits.
# The CPU parts (fixture checks, oracles, both algorithms, counters all zero) run in the
# PottsModels suite; the Metal parts run where Metal is loaded (`POTTS_GPU=metal`).
#
# Negative controls: every measured event MCS is shown to have fired, at that MCS, by a
# checkpoint around it; the quiet windows are shown to be quiet the same way; the counters
# are shown to be live on the same integrator (a checkpoint, which copies the state down,
# counts transfers and at least σ's bytes); the scaled fixtures really differ in σ bytes,
# cell columns and capacity; the mask fixture's mobile count changes at the transition,
# so a stale count fails; the kind-B cell and the control cluster never divide.
#
# Today (the D-035 path) the Metal parts fail for these reasons: (i) every quiet lifecycle
# MCS costs 1 sync / 1 transfer / 4 B (the trigger read-back); (ii) the event MCS copies σ
# down (bytes grow with the lattice), every non-tracker cell column down and up (bytes
# grow with the quantities) and whole capacity-sized arrays (bytes grow with capacity).
# (ii) also: the event MCS of F1 is not 0 / 0 / 0, and F2/F3 copy σ down. (v): every
# quiet lifecycle MCS waits (the read-back's sync and blit). (iii) and (iv) hold today and
# pin what the device planner must keep.

@testsetup module DeviceLifecycleSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using Statistics: mean, var
const ON_DEVICE = PottsDevices.on_device()
device_lifecycle_counts(s) = (s.syncs, s.transfers, s.transfer_bytes)
device_lifecycle_run(s) = NamedTuple{fieldnames(typeof(s.lifecycle))}(getfield.(Ref(s.lifecycle), fieldnames(typeof(s.lifecycle))))
lifecycle_total(s::NamedTuple) = sum(values(s))
lifecycle_total(s) = lifecycle_total(device_lifecycle_run(s))
device_lifecycle_host(u) = (; ownership = Array(u.ownership), cell = map(Array, u.cell))
# ---------------------------------------------------------------------------------------
# Fixture F1: plain divisions at MCS DEVICE_LIFECYCLE_S, scaled in lattice size and cell quantities.
# Cells 1, 2 (kind A, 4×2) divide along (1, 0) at MCS S and only then; cell 3 (kind B)
# never divides. T = 0 and weight 100 on (volume − V_target)² with every cell at its
# target reject every copy (the 0.01·surface term moves ΔH by < 0.1), so the cells split
# 4 | 4 whatever the RNG; `V_target => Split()` puts both halves at their new target, so
# the state stays frozen after the event. Closed lattice: centroids are plain means.
const DEVICE_LIFECYCLE_S = 2
const CELLS = ((3:6, 2:3), (10:13, 5:6), (3:6, 6:7))
# A, A, B
for Q in (1, 8)
    vars = Expr(:block, :(V_target(cell) = 8.0), (:($(Symbol(:q, k))(cell) = 0.0) for k in 1:Q)...)
    @eval @potts_model $(Symbol(:Divide, Q)) begin
        @structural_parameters begin
            lattice = (16, 8)
        end
        @kinds medium A B
        @variables $vars
        @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
        @energy cells => 100 * (volume - V_target)^2 + 0.01 * surface
        @divide cells(A) when = mcs == $DEVICE_LIFECYCLE_S, along = (1.0, 0.0), V_target => Split()
        @sweep Metropolis(; temperature = 0.0)
    end
end
function divide_problem(; lattice = (16, 8), Q = 1, capacity = 6, T = Float64, tspan = (0, 5))
    σ = zeros(Int32, lattice)
    for (c, (r, k)) in enumerate(CELLS)
        σ[r, k] .= c
    end
    sys = (Q == 1 ? Divide1 : Divide8)(; name = :device_lifecycle, lattice)
    qs = [Symbol(:q, k) => [10.0k + c for c in 1:3] for k in 1:Q]   # distinct per cell and column
    return PottsProblem(sys, [ownership => σ, kind => [:A, :A, :B], qs...], tspan; T, capacity)
end
# ---------------------------------------------------------------------------------------
# Fixture F2: compartments. Two clusters (cytoplasm 6×4 with a 2×2 nucleus in the middle)
# divide as units along (1, 0) through the cluster centroid at MCS 1 (cytoplasm 10 | 10,
# nucleus 2 | 2, no site on the plane), and a lone `free` cell divides alone along (0, 1).
# Frozen at T = 0 as F1.
@potts_model Cluster begin
    @structural_parameters begin
        lattice = (16, 16)
    end
    @kinds medium cyto nuc free
    @variables begin
        V_target(cell) = 8.0
        w(cell) = 1.0
    end
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => 100 * (volume - V_target)^2 + 0.01 * surface
        contacts => ifelse(cluster[owner] == cluster[neighbor_owner], 0.01, 0.02)
        clusters(cyto) => 0.001 * cluster_volume
    end
    @divide clusters(cyto) when = mcs == 1, along = (1.0, 0.0), V_target => Split()
    @divide cells(free) when = mcs == 1, along = (0.0, 1.0), V_target => Split()
    @sweep Metropolis(; temperature = 0.0)
end
function cluster_problem(; T = Float64, lattice = (16, 16))
    σ = zeros(Int32, lattice)
    σ[3:8, 2:5] .= 1; σ[5:6, 3:4] .= 2
    σ[3:8, 9:12] .= 3; σ[5:6, 10:11] .= 4
    σ[12:13, 3:6] .= 5
    return PottsProblem(
        Cluster(; name = :device_lifecycle_c, lattice), [
            ownership => σ, kind => [:cyto, :nuc, :cyto, :nuc, :free],
            cluster => [1, 1, 3, 3, 5], :V_target => [20.0, 4.0, 20.0, 4.0, 8.0], :w => [1.0, 2.0, 3.0, 4.0, 5.0],
        ],
        (0, 3); T, capacity = 12
    )
end
# ---------------------------------------------------------------------------------------
# Fixture F3: links, removal and slot reuse, through CorePotts' public hand-written
# `Lifecycle` (Potts has no `@remove` yet; installed with `remake(prob; f = …)` as in
# `frozen_kind_mask_tests.jl`). Bonds 1–2, 1–3, 2–3. At MCS 1 cell 1 divides along (1, 0) and cell 2 is
# removed; at MCS 3 cell 3 divides and its daughter takes the lowest free slot, 2 (the
# removed cell's, generation 1 → 2). The daughter state rule halves `V_target` (frozen at
# T = 0 after each event). The model's `@divide` never fires: it gives the moments.
@potts_model Linked begin
    @structural_parameters begin
        lattice = (16, 16)
    end
    @kinds medium A
    @variables V_target(cell) = 8.0
    @relationship bond(cell, cell) capacity = 3
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => 100 * (volume - V_target)^2 + 0.01 * surface
        edges(bond) => 0.001 * distance
    end
    @divide cells(A) when = volume >= 10000
    @sweep Metropolis(; temperature = 0.0)
end
struct LinkTrigger end
function (::LinkTrigger)(st, p, ctx, key, mcs, c)
    mcs == 1 && c == 1 && return EVENT_DIVIDE
    mcs == 1 && c == 2 && return EVENT_REMOVE
    mcs == 3 && c == 3 && return EVENT_DIVIDE
    return EVENT_NONE
end
struct Normal end
(::Normal)(st, p, ctx, key, mcs, c) = (1.0f0, 0.0f0)
struct Halve end
function (::Halve)(st, p, ctx, key, mcs, parent, daughter)
    v = st.cell.V_target[parent] / 2
    st.cell.V_target[parent] = v
    st.cell.V_target[daughter] = v
    return nothing
end
function with_lifecycle(prob, lc)
    f = prob.f
    g = CPMFunction(
        f.delta_H; f.commit!, f.constraint, f.temperature, f.bias, f.phases,
        lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys
    )
    return remake(prob; f = g)
end
function link_problem(; T = Float64, lattice = (16, 16))
    σ = zeros(Int32, lattice)
    σ[3:6, 2:3] .= 1; σ[3:4, 10:11] .= 2; σ[10:13, 5:6] .= 3
    prob = PottsProblem(
        Linked(; name = :device_lifecycle_l, lattice), [
            ownership => σ, kind => [:A, :A, :A],
            :V_target => [8.0, 4.0, 8.0], :bond => [(1, 2), (1, 3), (2, 3)],
        ], (0, 5); T, capacity = 5
    )
    return with_lifecycle(prob, Lifecycle(LinkTrigger(); normal = Normal(), divide! = Halve()))
end
device_lifecycle_bonds(u) = Set(minmax(Int(a), Int(c)) for c in axes(u.cell.links__bond, 2) for a in u.cell.links__bond[:, c] if a != 0)
# the store is symmetric: every entry has its mirror
device_lifecycle_symmetric(u) = (
    L = u.cell.links__bond;
    all(c -> all(a -> a == 0 || any(==(c), L[:, a]), L[:, c]), axes(L, 2))
)
# ---------------------------------------------------------------------------------------
# Fixture F4: the `frozen_kind_mask_tests.jl` mask. Cell 1 (kind `cell`) becomes `wall` (frozen) at the lifecycle
# of MCS DEVICE_LIFECYCLE_S (a public `Lifecycle` transition); cell 2 is a wall from the start, cell
# 3 a free control. 20×20 closed, every cell 4×4 at its target, T = 0: nothing moves, so
# the mobile-site count is 400 − 16 = 384 up to the sweep of MCS S and 368 from S + 1 on.
@potts_model Frozen begin
    @kinds medium cell wall[frozen]
    @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
    @energy cells => 100 * (volume - 16)^2
    @divide cells(cell) when = volume >= 10000
    @sweep Metropolis(; temperature = 0.0)
end
struct ToWall end
(::ToWall)(st, p, ctx, key, mcs, c) = mcs == DEVICE_LIFECYCLE_S && c == 1 ? EVENT_TRANSITION : EVENT_NONE
struct WallKind end
(::WallKind)(st, p, ctx, key, mcs, c) = Int32(2)
function frozen_problem(; T = Float64, tspan = (0, 6))
    σ = zeros(Int32, 20, 20)
    σ[3:6, 3:6] .= 1; σ[12:15, 3:6] .= 2; σ[3:6, 12:15] .= 3
    prob = PottsProblem(Frozen(; name = :device_lifecycle_f), [ownership => σ, kind => [:cell, :wall, :cell]], tspan; T)
    return with_lifecycle(prob, Lifecycle(ToWall(); kind = WallKind(), normal = Normal()))
end
mobile(m) = m <= DEVICE_LIFECYCLE_S ? 384 : 368
device_lifecycle_attempts(t, t0 = 0) = sum(mobile, t0:(t - 1); init = 0)
# the MCS t0 … t − 1

# ---------------------------------------------------------------------------------------
# Oracles
"""Every built-in tracker of host state `u` against a recount from σ (closed lattice,
Moore(1) unweighted surface). Returns the worst absolute error (0 when exact)."""
function tracker_error(u)
    σ, cell = u.ownership, u.cell
    cap = length(cell.volume)
    err = 0.0
    vol = [count(==(c), σ) for c in 1:cap]
    err = max(err, maximum(abs.(Int.(cell.volume) .- vol)))
    for c in 1:cap
        vol[c] == 0 && continue
        idx = findall(==(c), σ)
        x = [Float64(i[1]) for i in idx]; y = [Float64(i[2]) for i in idx]
        mx, my = mean(x), mean(y)
        cen = ntuple(k -> cell.anchor[k, c] + cell.m1[k, c] / vol[c], 2)   # closed: no wrap
        err = max(err, abs(cen[1] - mx), abs(cen[2] - my))
        cov = CorePotts.covariance(Float64, cell, c, Val(2))
        orc = (mean(x .^ 2) - mx^2, mean(x .* y) - mx * my, mean(y .^ 2) - my^2)
        err = max(err, maximum(abs.(cov .- orc)))
    end
    if haskey(cell, :surface)
        sfc = zeros(cap)
        for i in CartesianIndices(σ), d in CartesianIndices((-1:1, -1:1))
            j = i + d
            (d == CartesianIndex(0, 0) || !checkbounds(Bool, σ, j)) && continue
            σ[i] > 0 && σ[i] != σ[j] && (sfc[σ[i]] += 1)
        end
        err = max(err, maximum(abs.(Float64.(cell.surface) .- sfc)))
    end
    if haskey(cell, :cluster_volume)
        cl = cell.cluster
        cv = [count(s -> s > 0 && cl[s] == r, σ) for r in 1:cap]
        err = max(err, maximum(abs.(Int.(cell.cluster_volume) .- cv)))
    end
    return err
end
device_lifecycle_live(u) = sort!(unique(filter(>(0), vec(u.ownership))))
device_lifecycle_sites(u, c) = findall(==(c), vec(u.ownership))
"""Host state `u` with its cell ids relabelled by first site (a canonical form that forgets
which free slot each daughter took). Non-tracker columns, kinds, generations, clusters
(mapped) and the bond partner sets (mapped) are kept per live cell."""
function canon(u)
    live = device_lifecycle_live(u)
    order = sort(live; by = c -> first(device_lifecycle_sites(u, c)))
    new = Dict(c => i for (i, c) in enumerate(order))
    σ = map(s -> s == 0 ? 0 : new[s], u.ownership)
    skip = (:volume, :surface, :anchor, :m1, :m2, :cluster, :cluster_volume, :cluster_surface)
    cols = Dict(
        k => [Float64.(collect(selectdim(v, ndims(v), c))) for c in order]
            for (k, v) in pairs(u.cell) if !(k in skip) && !startswith(String(k), "link")
    )
    cl = haskey(u.cell, :cluster) ?
        [sort([new[m] for m in live if u.cell.cluster[m] == u.cell.cluster[c]]) for c in order] : nothing
    bonds = haskey(u.cell, :links__bond) ?
        [sort([new[a] for a in u.cell.links__bond[:, c] if a != 0]) for c in order] : nothing
    return (; ownership = σ, cols, cl, bonds)
end
function same_canon(a, b)
    ca, cb = canon(a), canon(b)
    ca.ownership == cb.ownership && ca.cl == cb.cl && ca.bonds == cb.bonds || return false
    keys(ca.cols) == keys(cb.cols) || return false
    return all(k -> all(i -> isapprox(ca.cols[k][i], cb.cols[k][i]; rtol = 1.0e-6), eachindex(ca.cols[k])), keys(ca.cols))
end
"""Device state `g` against CPU state `c` at the same MCS: equal up to relabelling of the
daughters, the same slots in use (lowest-first), and every cell live before the event
(`before`, ids) owning exactly the same sites on both."""
matches(g, c, before) = same_canon(g, c) && device_lifecycle_live(g) == device_lifecycle_live(c) &&
    all(id -> device_lifecycle_sites(g, id) == device_lifecycle_sites(c, id), intersect(before, device_lifecycle_live(c)))
# ---------------------------------------------------------------------------------------
# The published models (the same enumeration as the siblings guardrail): a builder per
# model. A new published model must be added here; those with a lifecycle are measured.
function device_lifecycle_published(T)
    gg = graner_glazier_state()
    w = zeros(Int32, 32, 32); w[12:20, 12:20] .= 1
    return Dict(
        :GranerGlazier => () -> PottsProblem(GranerGlazier(; name = :gg), [ownership => gg[1], kind => gg[2]], (0, 8); T),
        :WortelAct => () -> PottsProblem(WortelAct(; name = :w, lattice = (32, 32)), [ownership => w, kind => [:cell]], (0, 8); T),
        :MerksVasculogenesis => () -> PottsProblem(
            MerksVasculogenesis(; name = :m, lattice = (32, 32)),
            merks_state(; lattice = (32, 32), n = 6, side = 7), (0, 8); T, field_solver = ExplicitEuler(substeps = 2, lower_bound = 0.0)
        ),
        :OpenVTGrowingMonolayer => () -> PottsProblem(
            OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24), τ = 1.0e6),
            openvt_monolayer_state(; lattice = (24, 24)), (0, 8); T, capacity = 64
        ),
        :AkeebInvasion => () -> PottsProblem(
            AkeebInvasion(; name = :a, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (0, 8); T, capacity = 1000
        ),
        :OpenVTChain => () -> PottsProblem(OpenVTChain(; name = :c), openvt_chain(11), (0, 8); T),   # D-148 amendment
        # D-150 amendment: X ≡ 2 (σ_X = 0) keeps the disc (52 sites) below its threshold of 100
        :OpenVTReferenceMonolayer => () -> PottsProblem(
            OpenVTReferenceMonolayer(; name = :r, lattice = (24, 24)),
            [openvt_reference_state(; lattice = (24, 24)); :σ_X => 0.0], (0, 8); T, capacity = 64
        ),
        :Merks2006 => () -> PottsProblem(
            Merks2006(; name = :m6, lattice = (32, 32)),                    # D-153 amendment
            layout(merks2006_layout(; lattice = (32, 32), n = 6, side = 7), (32, 32)), (0, 8); T,
            field_solver = ExplicitEuler(substeps = 15)
        ),
        :Merks2008 => () -> PottsProblem(
            Merks2008(; name = :m8, lattice = (32, 32)),                    # D-153 amendment
            layout(merks2008_denovo(; lattice = (32, 32), n = 12, rounds = 2), (32, 32)), (0, 8); T,
            field_solver = ExplicitEuler(substeps = 15)
        ),
        :ShearedFoam => () -> PottsProblem(
            ShearedFoam(; name = :f, lattice = (32, 32)),                 # D-238 amendment
            [sheared_foam_state(; lattice = (32, 32)); :ytop => 32.0; :ymid => 16.5; :γ0 => 2.0; :T => 1.0], (0, 8); T
        ),
    )
end
const MODELS = filter(n -> (f = getfield(PottsModels, n); f isa Function && isuppercase(first(string(n)))), names(PottsModels))
"""Counter deltas of `nstep` MCS after `nwarm` MCS (no saves), with a checkpoint before and
after the window (outside it): returns `(deltas, lifecycle before, lifecycle after,
checkpoint delta)`. The checkpoints are the read points that make the lifecycle counts exact."""
function device_lifecycle_window(prob, alg; backend, nwarm, nstep)
    integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
    for _ in 1:nwarm
        step!(integ)
    end
    c0 = device_lifecycle_counts(integ.stats)
    l0 = device_lifecycle_run(checkpoint(integ).stats)
    ckd = device_lifecycle_counts(integ.stats) .- c0
    deltas = NTuple{3, Int}[]
    for _ in 1:nstep
        c = device_lifecycle_counts(integ.stats)
        step!(integ)
        push!(deltas, device_lifecycle_counts(integ.stats) .- c)
    end
    l1 = device_lifecycle_run(checkpoint(integ).stats)
    return deltas, l0, l1, ckd
end
const CPU_ALGS = (SequentialCPM(), CheckerboardCPM())
# =======================================================================================
# (ii) event MCS: O(events)
const VARIANTS = (
    base = (; lattice = (16, 8), Q = 1, capacity = 6),
    lattice = (; lattice = (64, 32), Q = 1, capacity = 6),      # 16× the sites
    quantities = (; lattice = (16, 8), Q = 8, capacity = 6),    # 8 cell quantities instead of 1
    capacity = (; lattice = (16, 8), Q = 1, capacity = 60),     # 10× the slots
)
# =======================================================================================
# (iii) results: exact MCS, the CPU path's law, trackers
"""CPU checks of the deterministic fixtures (both algorithms); returns the checkerboard solution."""
function check_divide(sol)
    @test [length(device_lifecycle_live(u)) for u in sol.u] == [t <= DEVICE_LIFECYCLE_S ? 3 : 5 for t in sol.t]
    u = device_lifecycle_host(sol.u[end])
    @test device_lifecycle_live(u) == 1:5                                   # daughters in the lowest free slots 4, 5
    for (c, (r, k)) in enumerate(CELLS[1:2])               # parents keep the low-x half
        @test device_lifecycle_sites(u, c) == findall(
            vec(
                let m = falses(size(u.ownership))
                    m[r[1:2], k] .= true; m
                end
            )
        )
    end
    @test device_lifecycle_sites(u, 3) == device_lifecycle_sites(device_lifecycle_host(sol.u[1]), 3)   # kind B never divides
    d = Dict(c => only(unique(u.ownership[r[3:4], k])) for (c, (r, k)) in enumerate(CELLS[1:2]))
    @test sort(collect(values(d))) == [4, 5]
    @test u.cell.kind[1:5] == Int32[1, 1, 2, 1, 1]
    @test u.cell.generation[1:6] == Int32[1, 1, 1, 1, 1, 0]      # a fresh slot: 0 → 1
    @test u.cell.V_target[1:5] == [4.0, 4.0, 8.0, 4.0, 4.0]      # the state rule
    for (k, v) in pairs(u.cell)
        startswith(String(k), "q") || continue
        @test all(c -> v[d[c]] == v[c], 1:2)                     # default: the parent's value
        @test v[1:3] == [10.0parse(Int, String(k)[2:end]) + c for c in 1:3]
    end
    @test all(x -> tracker_error(device_lifecycle_host(x)) < 1.0e-9, sol.u)
end
function check_cluster(sol)
    @test [length(device_lifecycle_live(u)) for u in sol.u] == [t <= 1 ? 5 : 10 for t in sol.t]
    u = device_lifecycle_host(sol.u[end])
    cl, σ = u.cell.cluster, u.ownership
    # parent => a site of its daughter (the +x half of each cluster, the +y half of cell 5)
    d = Dict(1 => σ[7, 2], 2 => σ[6, 3], 3 => σ[7, 9], 4 => σ[6, 10], 5 => σ[12, 5])
    @test sort(collect(values(d))) == 6:10                       # the lowest free slots
    @test σ[3, 2] == 1 && σ[5, 3] == 2 && σ[3, 9] == 3 && σ[5, 10] == 4 && σ[12, 3] == 5   # parents keep the low half
    @test all(p -> u.cell.kind[d[p]] == u.cell.kind[p] && u.cell.w[d[p]] == u.cell.w[p], 1:5)
    @test cl[1] == cl[2] == 1 && cl[3] == cl[4] == 3            # parent clusters keep their roots
    @test cl[d[1]] == cl[d[2]] == min(d[1], d[2])               # the daughters form a new cluster …
    @test cl[d[3]] == cl[d[4]] == min(d[3], d[4])
    @test cl[d[1]] != cl[1] && cl[d[3]] != cl[3] && cl[d[1]] != cl[d[3]]
    @test cl[5] == 5 && cl[d[5]] == d[5]                        # … a lone cell's daughter is lone
    @test u.cell.volume[[1, 2, 3, 4, 5]] == Int32[10, 2, 10, 2, 4]
    @test u.cell.volume[[d[p] for p in 1:5]] == Int32[10, 2, 10, 2, 4]
    @test u.cell.generation[1:10] == fill(Int32(1), 10) && u.cell.generation[11] == 0
    @test sol.stats.lifecycle.divisions == 5
    @test all(x -> tracker_error(device_lifecycle_host(x)) < 1.0e-9, sol.u)
end
function check_links(sol)
    @test [length(device_lifecycle_live(u)) for u in sol.u] == [3, 3, 3, 3, 4, 4]     # t = 0 … 5
    u2, u4 = device_lifecycle_host(sol.u[3]), device_lifecycle_host(sol.u[5])                    # after MCS 1, after MCS 3
    @test device_lifecycle_live(u2) == [1, 3, 4]                            # 2 removed; 1's daughter in slot 4
    @test device_lifecycle_bonds(u2) == Set([(1, 3)])                       # 1–2, 2–3 dropped; the daughter is unlinked
    @test device_lifecycle_live(u4) == [1, 2, 3, 4]                         # 3's daughter reuses slot 2 …
    @test u4.cell.generation[1:5] == Int32[1, 2, 1, 1, 0]        # … one generation up
    @test device_lifecycle_bonds(u4) == Set([(1, 3)])                       # and starts unlinked
    @test all(x -> device_lifecycle_symmetric(device_lifecycle_host(x)), sol.u)
    @test sol.stats.lifecycle.divisions == 2 && sol.stats.lifecycle.removals == 1
    @test all(x -> tracker_error(device_lifecycle_host(x)) < 1.0e-9, sol.u)
end
const FIXTURES = (
    divide = (() -> divide_problem(), T -> divide_problem(; T), check_divide),
    cluster = (() -> cluster_problem(), T -> cluster_problem(; T), check_cluster),
    links = (() -> link_problem(), T -> link_problem(; T), check_links),
)
# A random-plane model in law: OpenVT's growing monolayer, 40×40, τ = 8, 70 MCS (about 23
# divisions per run, sd 2.5; measured on the D-035 path, where Metal and the CPU agree seed
# by seed). The numbers of divisions and of live cells at the end, CPU checkerboard
# (Float32) against Metal over the same 24 seeds (|Δmean| ≤ 4 SE + 0.5), plus invariants of
# every saved Metal state: trackers exact, at most one live cell more per division, and
# Σ generation = initial + divisions (each division raises one slot's generation by one).
const OPENVT_SEEDS = 1:24
openvt(seed; T = Float32) = PottsProblem(
    OpenVTGrowingMonolayer(; name = :o, lattice = (40, 40), τ = 8.0),
    openvt_monolayer_state(; lattice = (40, 40)), (0, 70); T, capacity = 256, seed
)
function openvt_invariants(sol)
    ok = true
    g0 = sum(device_lifecycle_host(sol.u[1]).cell.generation)
    u = device_lifecycle_host(sol.u[end])
    ok &= sum(u.cell.generation) == g0 + sol.stats.lifecycle.divisions
    ok &= length(device_lifecycle_live(u)) <= 1 + sol.stats.lifecycle.divisions
    ok &= all(x -> tracker_error(device_lifecycle_host(x)) < 1.0e-6, sol.u)
    return ok
end
agree(a, b) = abs(mean(a) - mean(b)) <= 4sqrt((var(a) + var(b)) / length(a)) + 0.5
# =======================================================================================
# (iv) exact counts at the host read points
"""Run the read-point schedule on `backend` (tspan (0, 6); the event is at MCS S):
- a save at t = 1 (before the event): `r1`;
- past the event MCS without a save, then `current_state(integ)` at t = S + 1, the first read after it: `ru`;
- one more MCS (it runs with the new mask), then `checkpoint` at t = S + 2: `rck`;
- the save at t = S + 3: `r2`; then `solve!` to the end: `rend`;
- a second integrator with no save and no read until `current_state(integ)` at t = S + 3: `ru3`.
Returns the lifecycle counts and `stats.attempts` read at each point."""
function read_points(prob, alg; backend)
    rd(st) = (device_lifecycle_run(st), st.attempts)
    integ = init(prob, alg; backend, saveat = [1, DEVICE_LIFECYCLE_S + 3], save_start = false, save_end = false)
    step!(integ)                                                 # t = 1: a save
    r1 = rd(integ.stats)
    while integ.t < DEVICE_LIFECYCLE_S + 1
        step!(integ)
    end
    current_state(integ)                                                      # t = S + 1: a host read, no save
    ru = rd(integ.stats)
    step!(integ)
    ck = checkpoint(integ)                                       # t = S + 2
    rck = rd(ck.stats)
    step!(integ)
    r2 = rd(integ.stats)                                         # t = S + 3: a save
    sol = solve!(integ)
    rend = rd(sol.stats)
    integ = init(prob, alg; backend, save_start = false, save_everystep = false, save_end = false)
    while integ.t < DEVICE_LIFECYCLE_S + 3
        step!(integ)
    end
    current_state(integ)
    ru3 = rd(integ.stats)
    return (; r1, ru, rck, r2, rend, ru3)
end
function check_read_points(r, prob)
    lc0 = (; divisions = 0, removals = 0, transitions = 0, deferred = 0, empty_daughters = 0)
    @test r.r1[1] == lc0
    @test r.ru[1] == r.rck[1] == r.r2[1] == r.rend[1] == r.ru3[1]
    @test r.r1[2] == device_lifecycle_attempts(1) && r.ru[2] == device_lifecycle_attempts(DEVICE_LIFECYCLE_S + 1)
    @test r.rck[2] == device_lifecycle_attempts(DEVICE_LIFECYCLE_S + 2) && r.r2[2] == device_lifecycle_attempts(DEVICE_LIFECYCLE_S + 3)
    @test r.rend[2] == device_lifecycle_attempts(prob.tspan[2]) && r.ru3[2] == device_lifecycle_attempts(DEVICE_LIFECYCLE_S + 3)
end
# =======================================================================================
# (v) no GPU wait in a quiet lifecycle MCS

# Test-only instrumentation, as in `test/transfer_counts.jl`: `Metal.wait_cmdbuf!` gains a
# counter; the queue-depth back-pressure of `wait_oldest_cleanup!` (the host running ahead
# of the GPU) is not a sync and is excluded. The bodies copy Metal.jl 1.10.0's, hence the
# version pin. Each file instruments at its own top level just before its testsets, so
# whichever is included last owns the methods while its tests run.
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
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "device lifecycle (i): the published lifecycle models (CPU: fixture checks, counters zero)" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    # =======================================================================================
    # (i) quiet lifecycle MCS
    @testset "device lifecycle (i): the published lifecycle models (CPU: fixture checks, counters zero)" begin
        builders = device_lifecycle_published(Float64)
        @test Set(MODELS) == Set(keys(builders))           # every published model listed
        withlc = sort([n for (n, make) in builders if make().f.lifecycle !== nothing])
        @test length(withlc) >= 3                                    # non-vacuous: OpenVT, Akeeb and more
        @test issubset([:OpenVTGrowingMonolayer, :AkeebInvasion], withlc)
        for n in withlc
            deltas, l0, l1, ckd = device_lifecycle_window(builders[n](), CheckerboardCPM(); backend = CPU(), nwarm = 2, nstep = 4)
            @test l0 == l1                                           # the window is quiet
            @test all(==((0, 0, 0)), deltas) && ckd == (0, 0, 0)    # nothing is counted on the CPU
        end
    end
end

@testitem "device lifecycle (i): a quiet lifecycle MCS costs 0 syncs / 0 transfers / 0 B on the device" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (i): a quiet lifecycle MCS costs 0 syncs / 0 transfers / 0 B on the device" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            builders = device_lifecycle_published(Float32)
            withlc = sort([n for (n, make) in builders if make().f.lifecycle !== nothing])
            @test length(withlc) >= 3
            for n in withlc
                deltas, l0, l1, ckd = device_lifecycle_window(builders[n](), CheckerboardCPM(); backend, nwarm = 2, nstep = 4)
                @test l0 == l1                                       # control: the window is quiet
                @test ckd[2] >= 1 && ckd[3] >= 4                     # control: the counters are live here
                @test all(==((0, 0, 0)), deltas)
                all(==((0, 0, 0)), deltas) || @info "device lifecycle quiet lifecycle MCS" n deltas
            end
            # the division fixture: the MCS before and after its event MCS are quiet too
            integ = init(divide_problem(; T = Float32), CheckerboardCPM(); backend, save_start = false, save_everystep = false, save_end = false)
            for mcs in 0:4
                c = device_lifecycle_counts(integ.stats)
                step!(integ)
                mcs == DEVICE_LIFECYCLE_S || @test device_lifecycle_counts(integ.stats) .- c == (0, 0, 0)
            end
            @test checkpoint(integ).stats.lifecycle.divisions == 2  # control: the event did fire
            # compartments (events at MCS 1) and links with a removal (events at MCS 1 and 3)
            for (make, events, n) in (
                    (() -> cluster_problem(; T = Float32), (1,), 3),
                    (() -> link_problem(; T = Float32), (1, 3), 5),
                )
                integ = init(make(), CheckerboardCPM(); backend, save_start = false, save_everystep = false, save_end = false)
                for mcs in 0:(n - 1)
                    c = device_lifecycle_counts(integ.stats)
                    step!(integ)
                    mcs in events || @test device_lifecycle_counts(integ.stats) .- c == (0, 0, 0)
                end
                @test lifecycle_total(checkpoint(integ).stats) > 0   # control: events fired
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "device lifecycle (ii): the scaled division fixtures (CPU: each fires its two divisions at MCS)" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (ii): the scaled division fixtures (CPU: each fires its two divisions at MCS $DEVICE_LIFECYCLE_S)" begin
        for (label, kw) in pairs(VARIANTS), alg in CPU_ALGS
            prob = divide_problem(; kw...)
            sol = solve(prob, alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success
            @test [length(device_lifecycle_live(u)) for u in sol.u] == [t <= DEVICE_LIFECYCLE_S ? 3 : 5 for t in sol.t]   # at MCS S exactly
            @test sol.stats.lifecycle.divisions == 2 && device_lifecycle_counts(sol.stats) == (0, 0, 0)
            @test all(u -> tracker_error(device_lifecycle_host(u)) < 1.0e-9, sol.u)
        end
        # control: the variants really differ in what the D-035 path copies
        u = Dict(k => divide_problem(; kw...).u0 for (k, kw) in pairs(VARIANTS))
        @test sizeof(u[:lattice].ownership) == 16 * sizeof(u[:base].ownership)
        @test length(u[:quantities].cell) == length(u[:base].cell) + 7
        @test length(u[:capacity].cell.kind) == 10 * length(u[:base].cell.kind)
        # F2 and F3 on 64×64: the same events as on 16×16
        for make in (cluster_problem, link_problem)
            a, b = (solve(make(; lattice), CheckerboardCPM(); saveat = 1) for lattice in ((16, 16), (64, 64)))
            @test device_lifecycle_run(a.stats) == device_lifecycle_run(b.stats) && lifecycle_total(a.stats) > 0
            @test [length(device_lifecycle_live(u)) for u in a.u] == [length(device_lifecycle_live(u)) for u in b.u]
        end
    end
end

@testitem "device lifecycle (ii): event-MCS host traffic is independent of lattice size, quantities and capacity on the device" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (ii): event-MCS host traffic is independent of lattice size, quantities and capacity on the device" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            ev = Dict{Symbol, NTuple{3, Int}}()
            for (label, kw) in pairs(VARIANTS)
                prob = divide_problem(; T = Float32, kw...)
                deltas, l0, l1, ckd = device_lifecycle_window(prob, CheckerboardCPM(); backend, nwarm = DEVICE_LIFECYCLE_S, nstep = 1)
                @test l0.divisions == 0 && l1.divisions == 2         # control: the measured MCS is the event MCS
                @test ckd[2] >= 1 && ckd[3] >= sizeof(prob.u0.ownership)     # control: the counters see a state copy
                ev[label] = only(deltas)
            end
            for label in (:lattice, :quantities, :capacity)
                @test ev[label] == ev[:base]
            end
            @test ev[:base] == (0, 0, 0)                             # plain divisions: no host traffic (D-089)
            all(l -> ev[l] == (0, 0, 0), keys(ev)) || @info "device lifecycle event-MCS traffic (syncs, transfers, bytes)" ev
            # compartments (event MCS 1) and links with a removal (event MCS 1 and 3): the same
            # traffic on 16×16 and 64×64 (host-planned cluster or link work may remain, O(events))
            for (label, make, events) in (("clusters", cluster_problem, (1,)), ("links", link_problem, (1, 3)))
                for e in events
                    d = map(((16, 16), (64, 64))) do lattice
                        deltas, l0, l1, _ = device_lifecycle_window(make(; T = Float32, lattice), CheckerboardCPM(); backend, nwarm = e, nstep = 1)
                        @test lifecycle_total(l1) > lifecycle_total(l0)   # control: events at MCS e
                        only(deltas)
                    end
                    @test d[1] == d[2]
                    d[1] == d[2] || @info "device lifecycle event-MCS traffic, 16×16 vs 64×64" label e d
                end
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "device lifecycle (iii): lifecycle results of the deterministic fixtures (CPU)" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (iii): lifecycle results of the deterministic fixtures (CPU $(nameof(typeof(alg))))" for alg in CPU_ALGS
        for (label, (make, _, check)) in pairs(FIXTURES)
            sol = solve(make(), alg; saveat = 1)
            @test Symbol(sol.retcode) === :Success
            check(sol)
        end
    end
end

@testitem "device lifecycle (iii): the device runs the deterministic fixtures' events at the same MCS, with the CPU's result" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (iii): the device runs the deterministic fixtures' events at the same MCS, with the CPU's result" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            for (label, (make, makeT, check)) in pairs(FIXTURES)
                cpu = solve(make(), CheckerboardCPM(); saveat = 1)
                gpu = solve(makeT(Float32), CheckerboardCPM(); backend, saveat = 1)
                @test Symbol(gpu.retcode) === :Success && gpu.t == cpu.t
                check(gpu)                                           # the same oracles as on the CPU
                for i in eachindex(cpu.t)
                    g, c = device_lifecycle_host(gpu.u[i]), device_lifecycle_host(cpu.u[i])
                    before = i == 1 ? device_lifecycle_live(c) : device_lifecycle_live(device_lifecycle_host(cpu.u[i - 1]))
                    @test matches(g, c, before)
                end
                @test device_lifecycle_run(gpu.stats) == device_lifecycle_run(cpu.stats)
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "device lifecycle (iii): OpenVT divisions in law (CPU part: the fixture divides)" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (iii): OpenVT divisions in law (CPU part: the fixture divides)" begin
        sols = [solve(openvt(s), CheckerboardCPM(); saveat = 10) for s in OPENVT_SEEDS[1:4]]
        @test all(s -> s.stats.lifecycle.divisions >= 15, sols)     # control: many divisions per run
        @test all(openvt_invariants, sols)
    end
end

@testitem "device lifecycle (iii): OpenVT divisions in law, CPU against the device" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (iii): OpenVT divisions in law, CPU against the device" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            cpu = [solve(openvt(s), CheckerboardCPM(); saveat = 10) for s in OPENVT_SEEDS]
            gpu = [solve(openvt(s), CheckerboardCPM(); backend, saveat = 10) for s in OPENVT_SEEDS]
            @test all(s -> Symbol(s.retcode) === :Success, gpu)
            dc = [s.stats.lifecycle.divisions for s in cpu]; dg = [s.stats.lifecycle.divisions for s in gpu]
            lc = [length(device_lifecycle_live(device_lifecycle_host(s.u[end]))) for s in cpu]; lg = [length(device_lifecycle_live(device_lifecycle_host(s.u[end]))) for s in gpu]
            @test agree(dg, dc)
            @test agree(lg, lc)
            agree(dg, dc) && agree(lg, lc) || @info "device lifecycle OpenVT in law" mean(dc) mean(dg) mean(lc) mean(lg)
            @test all(openvt_invariants, gpu)
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "device lifecycle (iv): stats.lifecycle and the mask counts at host read points (CPU)" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (iv): stats.lifecycle and the mask counts at host read points (CPU $(nameof(typeof(alg))))" for alg in CPU_ALGS
        prob = frozen_problem()
        @test prob.u0.cell.kind[1:3] == Int32[1, 2, 1]               # fixture: kind indices
        sol = solve(prob, alg; saveat = 1)
        # control: the mobile count changes at the transition, so a stale count fails
        @test [count(!, frozen_sites(prob, u)) for u in sol.u] == [mobile(t) for t in sol.t]
        @test mobile(DEVICE_LIFECYCLE_S) != mobile(DEVICE_LIFECYCLE_S + 1)
        @test sol.stats.lifecycle.transitions == 1 && sol.stats.attempts == device_lifecycle_attempts(6)
        r = read_points(prob, alg; backend = CPU())
        check_read_points(r, prob)
        @test r.ru[1].transitions == 1
        # the division fixture: lifecycle counts at the same points; capacity deferral
        d = read_points(divide_problem(; tspan = (0, 6)), alg; backend = CPU())
        @test d.r1[1].divisions == 0
        @test all(x -> x[1].divisions == 2, (d.ru, d.rck, d.r2, d.rend, d.ru3))
        sol = @test_logs (:warn, r"deferred") match_mode = :any solve(divide_problem(; capacity = 4), alg)
        @test sol.stats.lifecycle.divisions == 1 && sol.stats.lifecycle.deferred == 1
        @test length(device_lifecycle_live(device_lifecycle_host(sol.u[end]))) == 4
    end
end

@testitem "device lifecycle (iv): stats.lifecycle and the mask counts are exact at host read points on the device" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "device lifecycle (iv): stats.lifecycle and the mask counts are exact at host read points on the device" begin
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM()
            prob = frozen_problem(; T = Float32)
            r = read_points(prob, alg; backend)
            check_read_points(r, prob)
            @test r.ru[1].transitions == 1
            # every MCS saved: exact after each step, against the saved states' own masks
            integ = init(prob, alg; backend, saveat = 1)
            while integ.t < prob.tspan[2]
                step!(integ)
                @test integ.stats.attempts == sum(u -> count(!, frozen_sites(prob, u)), integ.saved_u[1:(end - 1)])
                @test integ.stats.lifecycle.transitions == (integ.t > DEVICE_LIFECYCLE_S)
            end
            d = read_points(divide_problem(; T = Float32, tspan = (0, 6)), alg; backend)
            @test d.r1[1].divisions == 0
            @test all(x -> x[1].divisions == 2, (d.ru, d.rck, d.r2, d.rend, d.ru3))
            l = solve(link_problem(; T = Float32), alg; backend)
            @test l.stats.lifecycle.divisions == 2 && l.stats.lifecycle.removals == 1
            sol = solve(divide_problem(; T = Float32, capacity = 4), alg; backend)
            @test sol.stats.lifecycle.divisions == 1 && sol.stats.lifecycle.deferred == 1
            @test length(device_lifecycle_live(device_lifecycle_host(sol.u[end]))) == 4
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "device lifecycle (v): no GPU wait in a quiet lifecycle MCS on Metal (OpenVT, Akeeb)" setup = [DeviceLifecycleSetup] tags = [:pottsmodels, :acceptance] begin
    # at top level: the testset must see the new methods
    @testset "device lifecycle (v): no GPU wait in a quiet lifecycle MCS on Metal (OpenVT, Akeeb)" begin
        if ON_METAL
            @test METAL_VERSION == v"1.10.0"
            METAL_VERSION == v"1.10.0" || @error "device_lifecycle_tests.jl copies Metal.jl 1.10.0's " *
                "`wait_cmdbuf!`/`wait_oldest_cleanup!`; Metal is $METAL_VERSION: update the copies and the version"
        else
            @test_skip "device (POTTS_GPU=metal; Metal.jl wait counter)"
        end
        if WAITS_ON
            backend = PottsDevices.device_backend()
            builders = device_lifecycle_published(Float32)
            for n in (:OpenVTGrowingMonolayer, :AkeebInvasion)
                integ = init(builders[n](), CheckerboardCPM(); backend, save_start = false, save_everystep = false, save_end = false)
                step!(integ); step!(integ)
                l0 = device_lifecycle_run(checkpoint(integ).stats)
                PottsDevices.device_sync()
                w0 = WAITS[]
                for _ in 1:4
                    step!(integ)
                end
                waits = WAITS[] - w0
                l1 = device_lifecycle_run(checkpoint(integ).stats)
                @test l0 == l1                                       # control: the window is quiet
                @test WAITS[] - w0 - waits >= 1                # control: the wrapper counts the checkpoint's waits
                @test waits == 0
                waits == 0 || @info "device lifecycle GPU waits in 4 quiet lifecycle MCS" n waits
            end
        end
    end
end
