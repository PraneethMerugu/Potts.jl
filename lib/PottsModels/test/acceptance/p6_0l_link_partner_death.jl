# P6.0l (ROADMAP Phase 6, step 0): links to a copy-killed cell. Frozen (AUTONOMY §7.3).
# Decision: D-066 (liveness), item 2 X3 and item 5.
#
# The defect. When a linked cell loses its last site through copies, its centroid is 0/0
# (`m1 / volume` with volume 0). `link_delta` is then NaN for every copy of the surviving
# partner and `total_energy` is NaN. Links were dropped only on `EVENT_REMOVE`. (ROADMAP
# describes a silent freeze; on the tree this was frozen against, the first non-finite ΔH
# sets STATUS_NONFINITE, so the survivor stops moving because the run ends with retcode
# `Failure` within an MCS of the death. Both are covered: the run must reach its end and
# the survivor must move.)
#
# D-066 prescribes BOTH halves (quoted):
#   X3: "Dropped at the next boundary; dead partner skipped meanwhile".
#   Item 5: "**Links:** `link_delta` and `total_energy` skip a partner with `volume == 0`.
#   This reuses `centroid`'s load and fixes the NaN freeze (P6.0l)."
#   Item 5, boundaries: "Dead cells' links are dropped [...] (c) at the start of each
#   `@link`/`@unlink` host phase, before links are created, so a stale degree or `linked`
#   never blocks creation. A relationship with none of these never creates links; the skip
#   suffices there."
#
# Semantics pinned here:
#  1. Skip (every model). Once a linked partner has volume 0, its links contribute nothing:
#     for every copy touching the survivor, `energy_change` equals the energy change of the
#     same state with the dead cell's links removed, and is finite; `total_energy` is finite
#     and equals the unlinked state's. The survivor keeps moving. SequentialCPM and
#     CheckerboardCPM.
#  2. Boundary (c). In a model with an `@unlink` rule, or a `@link` rule, whose condition
#     never fires on these cells, the link to the dead cell is gone from the store after
#     the run (the host phase runs every MCS after the death). Boundaries (a) (lifecycle
#     event MCS) and (b) (R8 host routine) are not pinned here; whether a model with no
#     boundary keeps the stale entry in its store is left free.
#  3. Negative controls. With both cells alive, the link energy acts: its share of ΔH and
#     of H equals an independent oracle (k (d − ℓ)² on centroids computed from σ), and the
#     boundary rules leave the live link in place.
#
# Fixture. Cell 1 (`blob`, V₀ = 36) and cell 2 (`doomed`, energy λd·volume², λd = 50,
# 2×2 sites) are bonded. Removing a doomed site lowers H by ≥ 50, so at T = 10 the medium
# eats it within a few MCS (checked: the death MCS is asserted below). The doomed cell has
# no connectivity or extinction constraint, so it dies by copies. Closed 40×30 lattice.
using Potts: CorePotts

const P60L_K = 2.0
const P60L_ELL = 12.0

@potts_model P60lPair begin
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
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        cells(doomed) => λd * volume^2
        contacts => J[kind, kind′]
        edges(bond) => k * (distance - ℓ)^2
    end
    @sweep Metropolis(; temperature = T)
end

# the same, with an `@unlink` rule that never fires on a live link (boundary (c))
@potts_model P60lUnlink begin
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
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        cells(doomed) => λd * volume^2
        contacts => J[kind, kind′]
        edges(bond) => k * (distance - ℓ)^2
    end
    @unlink bond when = distance > 1000.0
    @sweep Metropolis(; temperature = T)
end

# the same, with a `@link` rule that never creates a link (boundary (c))
@potts_model P60lLinkRule begin
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
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((40, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        cells(doomed) => λd * volume^2
        contacts => J[kind, kind′]
        edges(bond) => k * (distance - ℓ)^2
    end
    @link bond when = distance < 0.0
    @sweep Metropolis(; temperature = T)
end

# blob 6×6 at rows 8:13, cols 12:17 (centroid (10.5, 14.5)); doomed 2×2 at rows 24:25,
# cols 14:15 (centroid (24.5, 14.5)); distance 14, rest length 12: the live link stores
# k (14 − 12)² = 8 in H.
function p60l_problem(model; kinds = [:blob, :doomed], tspan = (0, 60), seed = 1)
    σ = zeros(Int32, 40, 30)
    σ[8:13, 12:17] .= 1
    σ[24:25, 14:15] .= 2
    return PottsProblem(model(; name = :p60l), [ownership => σ, kind => kinds, :bond => [(1, 2)]],
        (tspan[1], tspan[2]); seed)
end

p60l_bond(u) = (; links = u.cell.links__bond)                  # the bond adjacency (D-075 layout)
function p60l_unlinked(u)                                        # u with cell 2's links dropped
    v = deepcopy(u)
    remove_incident!(p60l_bond(v), 2)
    return v
end
p60l_mask(u, c) = Array(u.σ) .== c

# independent oracle: centroid of cell c from σ (closed lattice: the plain mean)
function p60l_centroid(σ, c)
    idx = findall(==(c), σ)
    return (sum(i -> i[1], idx) / length(idx), sum(i -> i[2], idx) / length(idx))
end
p60l_dist(σ, a, b) = (ca = p60l_centroid(σ, a); cb = p60l_centroid(σ, b); hypot(ca[1] - cb[1], ca[2] - cb[2]))
p60l_edge(σ) = P60L_K * (p60l_dist(σ, 1, 2) - P60L_ELL)^2

# every Moore(1) copy (target t takes source s's owner) that touches cell c
function p60l_props(prob, u, c)
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    σ = Array(u.σ)
    out = CorePotts.Proposal{2}[]
    for t in eachindex(σ)
        x = CorePotts.coordinates(lat, t)
        for kk in 1:length(moore)
            ins, y = CorePotts.shift(lat, x, moore.offsets[kk])
            ins || continue
            s = CorePotts.linear_index(lat, y)
            σ[t] == σ[s] && continue
            (σ[t] == c || σ[s] == c) || continue
            push!(out, CorePotts.Proposal(t, s, x, 1, σ[t], σ[s]))
        end
    end
    return out
end

# ---------------------------------------------------------------------------------------
# 3. Negative control: both cells alive, the link energy acts (independent oracle)

@testset "P6.0l: a live link's energy acts (negative control)" begin
    prob = p60l_problem(P60lPair)
    u = prob.u0
    σ = Array(u.σ)
    @test linked(p60l_bond(u), 1, 2)
    @test p60l_edge(σ) ≈ 8.0
    # H share of the link: H(linked) − H(unlinked) == k (d − ℓ)²
    @test total_energy(prob, u) - total_energy(prob, p60l_unlinked(u)) ≈ 8.0 atol = 1e-9
    # ΔH share of the link on every copy touching the blob equals the oracle's change
    props = p60l_props(prob, u, 1)
    @test length(props) > 20
    worst = 0.0; biggest = 0.0
    for prop in props
        share = energy_change(prob, u, prop) - energy_change(prob, p60l_unlinked(u), prop)
        after = copy(σ); after[prop.target] = prop.new
        oracle = p60l_edge(after) - p60l_edge(σ)
        worst = max(worst, abs(share - oracle)); biggest = max(biggest, abs(share))
    end
    @test worst < 1e-9
    @test biggest > 0.1                                          # the link is not a no-op
end

# ---------------------------------------------------------------------------------------
# 1. Skip: the survivor of a copy-killed partner keeps moving, ΔH and H finite

@testset "P6.0l: a copy-killed partner is skipped ($(nameof(typeof(alg))))" for alg in
                                                                               (SequentialCPM(), CheckerboardCPM())
    prob = p60l_problem(P60lPair)
    sol = solve(prob, alg; saveat = 1)
    @test Symbol(sol.retcode) === :Success                      # DEFECT CHECK (currently Failure)
    @test sol.t[end] == 60                                       # the run is not cut short
    vols = [Array(u.cell.volume)[2] for u in sol.u]
    i = findfirst(==(0), vols)
    @test i !== nothing                                          # fixture: the partner dies by copies
    @test i <= 11                                                # … within 10 MCS (margin: ≥ 50 MCS after)
    @test all(==(0), vols[i:end])                                # and stays dead
    @test all(u -> Array(u.cell.volume)[1] > 0, sol.u)           # the survivor stays alive
    post = sol.u[i:end]
    @test length(post) >= 50

    # the survivor keeps moving: its site set changes in most MCS after the death
    # (the defect freezes it: zero changes)
    moves = count(j -> p60l_mask(post[j], 1) != p60l_mask(post[j - 1], 1), 2:length(post))
    @test moves >= (length(post) - 1) ÷ 2                        # DEFECT CHECK (currently 0)
    @test p60l_mask(post[end], 1) != p60l_mask(post[1], 1)

    # total H finite after the death, and the dead link adds nothing to it
    @test all(u -> isfinite(total_energy(prob, u)), post)        # DEFECT CHECK (currently NaN)
    @test all(u -> isapprox(total_energy(prob, u), total_energy(prob, p60l_unlinked(u)); atol = 1e-9), post)

    # every ΔH of a copy touching the survivor is finite and ignores the dead link
    for u in (post[1], post[end])
        props = p60l_props(prob, u, 1)
        @test length(props) > 20
        dH = [energy_change(prob, u, prop) for prop in props]
        @test all(isfinite, dH)                                  # DEFECT CHECK (currently NaN)
        free = p60l_unlinked(u)
        @test all(j -> isapprox(dH[j], energy_change(prob, free, props[j]); atol = 1e-9), eachindex(props))
    end
end

# ---------------------------------------------------------------------------------------
# 2. Boundary (c): an `@unlink`/`@link` host phase drops the dead cell's link

@testset "P6.0l: the `$rule` phase drops a dead partner's link ($(nameof(typeof(alg))))" for (rule, model) in
                                                                                             (("@unlink", P60lUnlink),
                                                                                              ("@link", P60lLinkRule)),
                                                                                         alg in (SequentialCPM(), CheckerboardCPM())
    prob = p60l_problem(model)
    sol = solve(prob, alg)
    @test Symbol(sol.retcode) === :Success                      # DEFECT CHECK (currently Failure)
    @test sol.t[end] == 60                                       # the run reaches its end
    u = sol.u[end]
    @test Array(u.cell.volume)[2] == 0                          # fixture: the partner died
    bond = (; links = Array(u.cell.links__bond))
    @test !linked(bond, 1, 2)                                    # DEFECT CHECK (currently linked)
    @test link_count(bond, 1) == 0 && link_count(bond, 2) == 0
    @test isfinite(total_energy(prob, u))

    # negative control: both cells alive (the second is a blob too); the rule keeps the link
    alive = p60l_problem(model; kinds = [:blob, :blob])
    solv = solve(alive, alg)
    @test Symbol(solv.retcode) === :Success
    v = solv.u[end]
    @test all(>(0), Array(v.cell.volume)[1:2])
    @test linked((; links = Array(v.cell.links__bond)), 1, 2)
    @test isfinite(total_energy(alive, v))
end
