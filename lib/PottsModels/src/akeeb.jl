"""
    AkeebInvasion(; name, lattice = (500, 300), J = akeeb_contacts(2.0), μ, …)

Leader/follower collective invasion with proliferation (Akeeb, Marcus & Jiang, PLoS
Comput. Biol. 22, e1014747, 2026), checked against the authors' CompuCell3D source:

- **Kinds.** Leaders and followers, both kept connected (CompuCell3D's `Connectivity`
  plugin: the losing cell's sites in the 8-ring must form one arc) and never extinct.
- **Energies.** A per-cell target volume, and adhesion
  `J = [0 2 10; 2 16 J_LF; 10 J_LF 5]` (medium, leader, follower).
- **Migration cue.** A static field `cue = y − 1`. A copy whose source or target cell is a
  leader gains `−μ Δcue`: leaders climb the cue (CompuCell3D's default chemotaxis). The
  default `μ = 24` is the authors' reference sample (`(J_LF, λ, PP) = (2, 24, 0.5)`).
- **Growth and division.** Followers with a mitotic clock (`clock ≥ 0`) grow their target
  volume by `rate` per MCS up to `V_max`. They divide when larger than `V_max` and their
  clock exceeds `clock_min + clock_spread · U(0, 1)`, with a fresh draw every MCS. The
  division plane is random, the target volume is split, and clocks restart.

Use `akeeb_state` for the published initial slab.

Faithful to the authors' CompuCell3D model in its mechanics. Where that code differs from
the paper's text, this model follows the code:
- the cue term is per-copy chemotaxis, not the paper's Eq. (1) potential over leader sites;
- leaders are one-site cells inserted into followers until they are a quarter of all cells,
  not a quarter of the followers relabelled;
- the mitotic clock starts uniformly in `0:74` and a division needs
  `clock > clock_min + clock_spread · U(0, 1)`, redrawn every MCS, not the paper's
  `U(25, 125)` MCS timer;
- every follower grows, with or without a mitotic clock.

One CompuCell3D step is 1 MCS here. The authors' "MCS t" is the state after `t + 1` MCS
(their runs take 701 steps for "MCS 700"). [`akeeb_observables`](@ref) measures a state as
the authors' metric code does.
"""
@potts_model AkeebInvasion begin
    @structural_parameters begin
        lattice = (500, 300)
    end
    @kinds medium leader follower
    @parameters begin
        λᵥ = 2.0
        μ = 24.0
        T = 10.0
        V_max = 20.0
        clock_min = 75.0
        clock_spread = 50.0
        J[kind, kind] = [0.0 2.0 10.0; 2.0 16.0 2.0; 10.0 2.0 5.0]
    end
    @variables begin
        V_target(cell) = 10.0
        clock(cell) = -1.0
        rate(cell) = 0.0
        cue(site) = 0.0
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = Moore(1))
    @relations proposal = VonNeumann(1)     # CC3D Potts NeighborOrder 1
    @energy begin
        cells => λᵥ * (volume - V_target)^2
        contacts => J[kind, kind′]
    end
    @drive copy => ifelse((kind[new] == leader) || (kind[old] == leader), -μ * (cue[target] - cue[source]), 0.0)
    @constraint connectivity(leader, follower)   # one arc in the 8-ring: CC3D's Connectivity plugin
    @constraint no_extinction
    @after_mcs begin
        V_target ~ ifelse(Pre(V_target) < V_max, Pre(V_target) + rate, Pre(V_target))
        clock ~ ifelse(Pre(clock) >= 0, Pre(clock) + 1, Pre(clock))
    end
    @divide cells(follower) when = (clock >= 0) && (volume > V_max) && (clock > clock_min + clock_spread * rand()),
        along = RandomPlane(), V_target => Split(), clock => 0.0
    @sweep Metropolis(; temperature = T)
end

"""`akeeb_contacts(J_LF)`: the adhesion table with leader–follower energy `J_LF`."""
akeeb_contacts(jlf) = [0.0 2.0 10.0; 2.0 16.0 jlf; 10.0 jlf 5.0]

"""
    akeeb_layout(; lattice = (500, 300), seed = 0x5cd2609, slab = 21, seeding = :authors)
        -> AbstractLayout

The published initial slab of [`akeeb_state`](@ref) as a layout value, written with the
public layers only:

```julia
overlay(Tiling((3, 3); region = (1:X, 1:3cld(slab, 3)), kinds = [:follower], partial = :clip),
        InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses,
                    region = (2:X, 2:(slab - 1)), splits = :allow))
```

with `X = lattice[1]`.

- **Followers.** 3×3 tiles fill `y ≤ slab` (rounded up to whole tiles), clipped at the
  right edge, ids row by row with `x` fastest.
- **Leaders.** One-site leaders go on random follower pixels, drawn over the ranges of the
  authors' CompuCell3D seeding loop, until leaders are a quarter of all cells. `seeding`
  chooses `misses`:
  - `:authors` (default) gives `misses = :count`, the authors' loop: every draw counts one
    leader toward the quota, a leader is painted only on a hit, and the quota is tested
    only after a hit. A miss leaves no cell (an empty "ghost" leader), so fewer
    leaders are painted than counted: at 500×300, ≈ 382 of a counted 390.
  - `:retry` gives `misses = :retry`: a miss is redrawn, so exactly the quota is painted.

Several leaders inside one follower can cut it in two; that is the published slab, so the
leader layer has `splits = :allow` and painting the layout does not warn.

The layout carries no lattice: painted on a lattice wider than `X`, the `X`-wide slab is
painted and the rest stays medium. The counted inventory is the leader layer's row of the
layout report:

```julia
point, report = layout(akeeb_layout(; lattice, seed), lattice; report = true)
t = only(r for r in report if r.type === :InsertUntil)
t.painted, t.misses, t.counted     # leaders created, missed draws, the CC3D inventory
```
"""
function akeeb_layout(; lattice = (500, 300), seed = 0x5cd2609, slab = 21, seeding::Symbol = :authors)
    seeding in (:authors, :retry) ||
        throw(ArgumentError("akeeb_layout: seeding must be :authors or :retry, got :$seeding"))
    length(lattice) == 2 || throw(ArgumentError("akeeb_layout: the lattice must be 2D, got $lattice"))
    X, Y = lattice
    top = 3 * cld(slab, 3)                                   # the last tile row ends here
    Y > top || throw(ArgumentError("akeeb_layout: lattice height $Y must exceed the slab ($top rows)"))
    misses = seeding === :authors ? :count : :retry
    return overlay(Tiling((3, 3); region = (1:X, 1:top), kinds = [:follower], partial = :clip),
        InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses, region = (2:X, 2:(slab - 1)),
            splits = :allow))
end

"""
    akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609, slab = 21,
                seeding = :authors) -> operating point

The published initial slab:
- **Cells.** `σ` and `kinds` are `layout(akeeb_layout(; lattice, seed, slab, seeding), lattice)`
  (see [`akeeb_layout`](@ref)): a follower slab of 3×3 tiles over `y ≤ slab`, then one-site
  leaders inserted until leaders are a quarter of all cells, under the authors' counting
  of missed draws (`seeding = :authors`) or with misses redrawn (`:retry`). The lattice
  must be taller than the slab. The counted leader inventory is the leader layer's row of
  `layout(akeeb_layout(…), lattice; report = true)`.
- **Clocks.** Each follower has a mitotic clock with probability `pp`, drawn uniformly
  from `0:74`. Followers have `rate = 0.015`.
- **Cue.** `y − 1`.

All draws use `StableRNG`, so the state is the same on every Julia version: the
leaders `StableRNG(seed)` (inside `InsertUntil`), the clocks `Potts.layer_rng(seed, :clock)`,
which is `StableRNG(Potts._substream_seed(seed, :clock))` (a mixed sub-stream, so clocks at
consecutive seeds are uncorrelated), one cell at a time in id order (a leader draws
nothing).
"""
function akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609, slab = 21,
        seeding::Symbol = :authors)
    X, Y = lattice
    top = 3 * cld(slab, 3)                                   # the last tile row ends here
    Y > top || throw(ArgumentError("akeeb_state: lattice height $Y must exceed the slab ($top rows)"))
    seeding in (:authors, :retry) ||
        throw(ArgumentError("akeeb_state: seeding must be :authors or :retry, got :$seeding"))
    l = akeeb_layout(; lattice, seed, slab, seeding)
    point = layout(l, lattice)               # the leader layer allows split followers: no warning
    σ, kinds = point[1].second, point[2].second
    rng = Potts.layer_rng(seed, :clock)
    clocks = [k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]
    rates = [k === :leader ? 0.0 : 0.015 for k in kinds]
    cue = [Float64(y - 1) for x in 1:X, y in 1:Y]
    return [ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]
end

"""
    akeeb_observables(σ::AbstractMatrix{<:Integer}, kinds::AbstractVector{Symbol}) -> NamedTuple
    akeeb_observables(u)

The invasion metrics of one state as the authors' analysis code computes them (Akeeb,
Marcus & Jiang 2026; spec 10 §5.3.3, O1–O8), so they compare directly with the released
data. `σ` is a 2-D state with `x` (the first index) periodic and `y` (the second) closed;
cell `c` is σ's value `c` and `kinds[c]` its kind, `:leader` or `:follower`. An id that owns
no site is not a cell: it counts nothing and its kind is not read. The second method reads `u.σ` and the kinds of a
state of [`AkeebInvasion`](@ref) (kind 1 is the leader).

- **Adjacency.** Two cells are neighbours when they own von Neumann-adjacent sites
  (`x` periodic); the medium is not a cell.
- **Main tumour `M`.** The connected components of the cells that own a site in row
  `y = 2` with `x ∈ 1:X−1`: the authors' row 0 and their `x` range, which skips the last
  column.
- **`invasive`, `infiltrative`** (px², `Float64`). Per column, the top of `M` and the top of
  any cell; the columns where both exist are kept, in `x` order, and `base` is the lowest
  kept top of `M`. The areas are the trapezoid integrals over the kept `x` of
  `top_M − base` and `top_any − base`, not periodic.
- **`fingers`.** The peaks of the kept `top_M` array (on its index, not on `x`) found by
  `find_peaks(…; prominence = 10, distance = 10, width = 5)`, then thinned by
  `merge_peaks(…, 15)`.
- **`singles`.** Leaders with no neighbour whose mean `y` is above the lowest mean `y`
  of a cell of `M`.
- **`detached`.** Cells of either kind outside `M` whose mean `y` is above that height.
- **`clusters`.** The connected components outside `M` with at least two cells and at
  least one follower (leader-only groups never count), with no height condition.
  `cluster_leaders` and `cluster_followers` give each counted cluster's leaders and
  followers, clusters ordered by their smallest cell id.

Throws an `ArgumentError` when no cell owns a site in the seed row (the authors' code has no
main tumour to measure then). Built from [`PottsModels.Analysis`](@ref): `cell_graph`,
`reachable`, `components`, `centroids`, `column_tops`, `trapz`, `find_peaks` and
`merge_peaks`.

```julia
sol = solve(PottsProblem(AkeebInvasion(; name = :a), akeeb_state(), (0, 701); capacity = 4000),
    SequentialCPM(; proposal = VonNeumann(1)))
akeeb_observables(sol.u[end])    # the authors' "MCS 700"
```
"""
function akeeb_observables(σ::AbstractMatrix{<:Integer}, kinds::AbstractVector{Symbol})
    A = Analysis
    X = size(σ, 1)
    size(σ, 2) >= 2 || throw(ArgumentError("akeeb_observables: σ needs at least 2 rows in y, got size $(size(σ))"))
    n = Int(maximum(σ; init = 0))
    length(kinds) >= n ||
        throw(ArgumentError("akeeb_observables: σ has cell ids up to $n but there are $(length(kinds)) kinds"))
    alive = falses(n)
    for c in σ
        c > 0 && (alive[c] = true)
    end
    for c in 1:n                                  # an id that owns no site is not a cell
        alive[c] && !(kinds[c] in (:leader, :follower)) &&
            throw(ArgumentError("akeeb_observables: kind of cell $c must be :leader or :follower, got :$(kinds[c])"))
    end
    leader(c) = kinds[c] === :leader
    g = A.cell_graph(σ; periodic = (true, false))                       # O1
    seeds = unique(Int(σ[x, 2]) for x in 1:(X - 1) if σ[x, 2] != 0)     # O2
    isempty(seeds) &&
        throw(ArgumentError("akeeb_observables: no cell owns a site in row y = 2 (x ∈ 1:$(X - 1)), so there is no main tumour"))
    M = A.reachable(g, seeds)
    inM = falses(n)
    inM[M] .= true
    ycom = [p[2] for p in A.centroids(σ)]                              # NaN for an empty id
    ymin = minimum(ycom[c] for c in M)
    above(c) = alive[c] && ycom[c] > ymin
    singles = count(c -> above(c) && leader(c) && isempty(g[c]), 1:n)  # O6
    detached = count(c -> above(c) && !inM[c], 1:n)                    # O7
    comps = A.components(g, [c for c in 1:n if alive[c] && !inM[c]])  # O8
    counted = filter(k -> length(k) >= 2 && !all(leader, k), comps)
    top_main = A.column_tops(c -> inM[c], σ)                            # O3
    top_out = A.column_tops(σ)
    kept = [x for x in 1:X if top_main[x] > 0 && top_out[x] > 0]
    main = top_main[kept]
    base = minimum(main)
    invasive = A.trapz(kept, main .- base)                             # O4
    infiltrative = A.trapz(kept, top_out[kept] .- base)
    fingers = length(A.merge_peaks(A.find_peaks(main; prominence = 10, distance = 10, width = 5), 15))  # O5
    return (; invasive, infiltrative, singles, fingers, detached, clusters = length(counted),
        cluster_leaders = [count(leader, k) for k in counted], cluster_followers = [count(!leader, k) for k in counted])
end

function akeeb_observables(u)
    σ = Array(u.σ)
    codes = Array(u.cell.kind)
    n = Int(maximum(σ; init = 0))
    return akeeb_observables(σ, [codes[c] == 1 ? :leader : :follower for c in 1:n])
end
