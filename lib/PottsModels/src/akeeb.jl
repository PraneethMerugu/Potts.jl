"""
    AkeebInvasion(; name, lattice = (500, 300), λᵥ = 2.0, μ = 24.0, T = 10.0,
        V_max = 20.0, clock_min = 75.0, clock_spread = 50.0, J = akeeb_contacts(2.0))

Build the Akeeb–Marcus–Jiang model of leader/follower collective invasion with
proliferation, checked against the authors' CompuCell3D source.

- **Kinds.** Leaders and followers, both kept connected (CompuCell3D's `Connectivity`
  plugin, `Local()`: the losing cell's sites in the 8-ring must form one arc and the gaining
  cell must own a face neighbor of the target; with `VonNeumann(1)` copies the second
  always holds) and never extinct.
- **Energies.** A per-cell target volume, `λᵥ (volume − V_target)²`, and adhesion
  `J = [0 2 10; 2 16 J_LF; 10 J_LF 5]` (medium, leader, follower).
- **Migration cue.** A static field `cue = y − 1`. A copy whose source or target cell is a
  leader gains `−μ Δcue`: leaders climb the cue (CompuCell3D's default chemotaxis). The
  default `μ = 24` is the authors' reference sample (`(J_LF, λ, PP) = (2, 24, 0.5)`).
- **Growth and division.** Every cell grows its target volume by its own `rate` per MCS
  while the target is below `V_max`, whether or not it has a mitotic clock;
  [`akeeb_state`](@ref) gives every follower `rate = 0.015` and every leader `rate = 0`, so
  all followers grow and leaders do not. Only followers with a mitotic clock (`clock ≥ 0`)
  divide: when larger than `V_max` and their clock exceeds
  `clock_min + clock_spread · U(0, 1)`, with a fresh draw every MCS. The division plane is
  random, the target volume is split, and clocks restart.

The lattice is periodic in `x` and closed in `y`, with Moore contacts and `VonNeumann(1)`
copies. The cell variables are `V_target`, `clock` and `rate`, and the site variable is
`cue`. Use [`akeeb_state`](@ref) for the published initial slab.

Faithful to the authors' CompuCell3D model in its mechanics. Where that code differs from
the paper's text, this model follows the code:
- the cue term is per-copy chemotaxis, not the paper's Eq. (1) potential over leader sites;
- leaders are one-site cells inserted into followers until they are a quarter of all cells,
  not a quarter of the followers converted;
- the mitotic clock starts uniformly in `0:74` and a division needs
  `clock > clock_min + clock_spread · U(0, 1)`, redrawn every MCS, not the paper's
  `U(25, 125)` MCS timer;
- every follower grows, with or without a mitotic clock.

One CompuCell3D step is 1 MCS here. The authors' "MCS t" is the state after `t + 1` MCS
(their runs take 701 steps for "MCS 700"). [`akeeb_observables`](@ref) measures a state as
the authors' metric code does.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (500, 300)`: the lattice size (structural).
- `λᵥ = 2.0`: the volume strength.
- `μ = 24.0`: the chemotaxis strength of leaders on the cue.
- `T = 10.0`: the Metropolis temperature.
- `V_max = 20.0`: the volume above which a follower with a clock may divide, and the cap of
  target growth.
- `clock_min = 75.0`, `clock_spread = 50.0`: the clock threshold of a division.
- `J = akeeb_contacts(2.0)`: the contact energies over (medium, leader, follower).

# Returns
- `PottsSystem`: the model.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> AkeebInvasion(; name = :invasion, J = akeeb_contacts(10.0)) isa PottsSystem
true
```

# References
- Akeeb, Marcus & Jiang, PLoS Comput. Biol. 22, e1014747 (2026).

See also [`akeeb_state`](@ref), [`akeeb_observables`](@ref), [`akeeb_phenotype`](@ref).
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
        contacts => J[kind, neighbor_kind]
    end
    @drive copy => ifelse(
        (kind[new] == leader) || (kind[old] == leader), -μ *
            (cue[target] - cue[source]), 0.0
    )
    # `Local()`: CC3D's Connectivity plugin (D-191)
    @constraint connectivity(leader, follower)
    @constraint no_extinction
    @after_mcs begin
        V_target ~ ifelse(Pre(V_target) < V_max, Pre(V_target) + rate, Pre(V_target))
        clock ~ ifelse(Pre(clock) >= 0, Pre(clock) + 1, Pre(clock))
    end
    @divide cells(follower) when = (clock >= 0) && (volume > V_max) &&
        (clock > clock_min + clock_spread * rand()),
        along = RandomPlane(), V_target => Split(), clock => 0.0
    @sweep Metropolis(; temperature = T)
end

"""
    akeeb_contacts(J_LF) -> Matrix{Float64}

Return the adhesion table of [`AkeebInvasion`](@ref) with leader–follower energy `J_LF`.

# Arguments
- `J_LF`: the leader–follower contact energy.

# Returns
- `Matrix{Float64}`: `[0 2 10; 2 16 J_LF; 10 J_LF 5]` over (medium, leader, follower).

# Examples
```jldoctest
julia> using PottsModels

julia> akeeb_contacts(4.0)
3×3 Matrix{Float64}:
  0.0   2.0  10.0
  2.0  16.0   4.0
 10.0   4.0   5.0
```

See also [`AkeebInvasion`](@ref).
"""
akeeb_contacts(jlf) = [0.0 2.0 10.0; 2.0 16.0 jlf; 10.0 jlf 5.0]

"""
    akeeb_layout(; lattice = (500, 300), seed = 0x5cd2609, slab = 21, seeding = :authors)
        -> AbstractLayout

Return the published initial slab of [`akeeb_state`](@ref) as a layout value, written with
the public layers only.

With `X = lattice[1]`, the layout is

```julia
overlay(Tiling((3, 3); region = (1:X, 1:3cld(slab, 3)), kinds = [:follower],
        partial = :clip),
    InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses,
        region = (2:X, 2:(slab - 1)), splits = :allow))
```

- **Followers.** 3×3 tiles fill `y ≤ slab` (rounded up to whole tiles), clipped at the
  right edge, numbered row by row with `x` fastest.
- **Leaders.** One-site leaders go on random follower sites, drawn over the ranges of the
  authors' CompuCell3D seeding loop, until leaders are a quarter of all cells. `seeding`
  chooses `misses`:
  - `:authors` (default) gives `misses = :count`, the authors' loop: every draw counts one
    leader toward the quota, a leader is painted only on a hit, and the quota is tested
    only after a hit. A miss leaves no cell (an empty "ghost" leader), so fewer leaders are
    painted than counted.
  - `:retry` gives `misses = :retry`: a miss is redrawn, so exactly the quota is painted.

Several leaders inside one follower can cut it in two; that is the published slab, so the
leader layer has `splits = :allow` and painting the layout does not warn.

The layout carries no lattice: painted on a lattice wider than `X`, the `X`-wide slab is
painted and the rest stays medium. The counted inventory is the leader layer's row of the
layout report.

# Keywords
- `lattice = (500, 300)`: the 2D lattice size. Its height must exceed `3cld(slab, 3)`.
- `seed = 0x5cd2609`: the seed of the leader draws.
- `slab = 21`: the slab height, in sites.
- `seeding::Symbol = :authors`: `:authors` or `:retry`.

Throws an `ArgumentError` for another `seeding`, a lattice that is not 2D, or a lattice
that is not taller than the slab.

# Returns
- `AbstractLayout`: the layout.

# Examples
```julia
using PottsModels, Potts
lattice = (500, 300)
point, report = layout(akeeb_layout(; lattice), lattice; report = true)
t = only(r for r in report if r.type === :InsertUntil)
t.painted, t.misses, t.counted     # leaders created, missed draws, the CC3D inventory
```

See also [`akeeb_state`](@ref).
"""
function akeeb_layout(;
        lattice = (500, 300), seed = 0x05cd2609, slab = 21,
        seeding::Symbol = :authors
    )
    seeding in (:authors, :retry) ||
        throw(ArgumentError("akeeb_layout: seeding must be :authors or :retry, got \
            :$seeding"))
    length(lattice) == 2 ||
        throw(ArgumentError("akeeb_layout: the lattice must be 2D, got $lattice"))
    X, Y = lattice
    top = 3 * cld(slab, 3)                                   # the last tile row ends here
    Y > top ||
        throw(ArgumentError("akeeb_layout: lattice height $Y must exceed the slab ($top \
            rows)"))
    misses = seeding === :authors ? :count : :retry
    return overlay(
        Tiling((3, 3); region = (1:X, 1:top), kinds = [:follower], partial = :clip),
        InsertUntil(
            :leader; into = [:follower], fraction = 1 // 4,
            seed, misses, region = (2:X, 2:(slab - 1)),
            splits = :allow
        )
    )
end

"""
    akeeb_state(; lattice = (500, 300), pp = 0.5, seed = 0x5cd2609, slab = 21,
        seeding = :authors) -> Vector{Pair}

Return the published initial state of [`AkeebInvasion`](@ref): the slab, the clocks, the
growth rates and the cue.

- **Cells.** `σ` and `kinds` are `layout(akeeb_layout(; lattice, seed, slab, seeding),
  lattice)` (see [`akeeb_layout`](@ref)): a follower slab of 3×3 tiles over `y ≤ slab`,
  then one-site leaders inserted until leaders are a quarter of all cells, under the
  authors' counting of missed draws (`seeding = :authors`) or with misses redrawn
  (`:retry`).
- **Clocks.** Each follower has a mitotic clock with probability `pp`, drawn uniformly
  from `0:74`; the others have `clock = -1`. Followers have `rate = 0.015`, leaders 0.
- **Cue.** `y − 1`.

All draws use `StableRNG`, so the state is the same on every Julia version: the leaders
use `StableRNG(seed)` (inside `InsertUntil`) and the clocks use
`Potts.layer_rng(seed, :clock)`, a mixed sub-stream, so clocks at consecutive seeds are
uncorrelated. The clocks are drawn one cell at a time in cell-number order (a leader draws
nothing).

# Keywords
- `lattice = (500, 300)`: the 2D lattice size. Its height must exceed `3cld(slab, 3)`.
- `pp = 0.5`: the probability that a follower has a mitotic clock.
- `seed = 0x5cd2609`: the seed of all draws.
- `slab = 21`: the slab height, in sites.
- `seeding::Symbol = :authors`: `:authors` or `:retry`.

Throws an `ArgumentError` for another `seeding` or a lattice that is not taller than the
slab.

# Returns
- `Vector{Pair}`: the operating point
  `[ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]`.

# Examples
```julia
using PottsModels, Potts
prob = PottsProblem(AkeebInvasion(; name = :a), akeeb_state(; seed = 3), (0, 701);
    capacity = 4000)
```

See also [`akeeb_layout`](@ref), [`AkeebInvasion`](@ref).
"""
function akeeb_state(;
        lattice = (500, 300), pp = 0.5, seed = 0x05cd2609, slab = 21,
        seeding::Symbol = :authors
    )
    X, Y = lattice
    top = 3 * cld(slab, 3)                                   # the last tile row ends here
    Y > top ||
        throw(ArgumentError("akeeb_state: lattice height $Y must exceed the slab ($top \
            rows)"))
    seeding in (:authors, :retry) ||
        throw(ArgumentError("akeeb_state: seeding must be :authors or :retry, got \
            :$seeding"))
    l = akeeb_layout(; lattice, seed, slab, seeding)
    # the leader layer allows split followers: no warning
    point = layout(l, lattice)
    σ, kinds = point[1].second, point[2].second
    rng = Potts.layer_rng(seed, :clock)
    clocks = [
        k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74))
            for k in kinds
    ]
    rates = [k === :leader ? 0.0 : 0.015 for k in kinds]
    cue = [Float64(y - 1) for x in 1:X, y in 1:Y]
    return [ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]
end

"""
    akeeb_observables(σ::AbstractMatrix{<:Integer},
        kinds::AbstractVector{Symbol}) -> NamedTuple
    akeeb_observables(u) -> NamedTuple

Return the invasion metrics of one state as the authors' analysis code computes them, so
they compare directly with the released data.

`σ` is a 2D state with `x` (the first index) periodic and `y` (the second) closed; cell
`c` is σ's value `c` and `kinds[c]` its kind, `:leader` or `:follower`. A cell number that
owns no site is not a cell: it counts nothing and its kind is not read. The second method
reads `u.ownership` and the kinds of a state of [`AkeebInvasion`](@ref) (kind 1 is the
leader). The metrics follow `docs/design/research/model-specs/10_akeeb_invasion.md`
§5.3.3.

- **Adjacency.** Two cells are neighbors when they own von Neumann-adjacent sites (`x`
  periodic); the medium is not a cell.
- **Main tumor `M`.** The connected components of the cells that own a site in row `y = 2`
  with `x ∈ 1:X−1`: the authors' row 0 and their `x` range, which skips the last column.
- **`invasive`, `infiltrative`** (sites, `Float64`). Per column, the top of `M` and the
  top of any cell; the columns where both exist are kept, in `x` order, and `base` is the
  lowest kept top of `M`. The areas are the trapezoid integrals over the kept `x` of
  `top_M − base` and `top_any − base`, not periodic.
- **`fingers`.** The peaks of the kept `top_M` array (on its index, not on `x`) found by
  `find_peaks(…; prominence = 10, distance = 10, width = 5)`, then thinned by
  `merge_peaks(…, 15)`.
- **`singles`.** Leaders with no neighbor whose mean `y` is above the lowest mean `y` of a
  cell of `M`.
- **`detached`.** Cells of either kind outside `M` whose mean `y` is above that height.
- **`clusters`.** The connected components outside `M` with at least two cells and at
  least one follower (leader-only groups never count), with no height condition.
  `cluster_leaders` and `cluster_followers` give each counted cluster's leaders and
  followers, clusters ordered by their smallest cell number.

It is built from [`PottsModels.Analysis`](@ref): `cell_graph`, `reachable`, `components`,
`centroids`, `column_tops`, `trapezoid_integral`, `find_peaks` and `merge_peaks`.

# Arguments
- `σ::AbstractMatrix{Integer}`: the ownership, with at least 2 rows in `y`.
- `kinds::AbstractVector{Symbol}`: the kind of each cell number, at least up to
  `maximum(σ)`.
- `u`: a saved state of [`AkeebInvasion`](@ref).

Throws an `ArgumentError` when `σ` has fewer than 2 rows in `y`, when `kinds` is too short
or holds another kind for a live cell, or when no cell owns a site in the seed row (the
authors' code has no main tumor to measure then).

# Returns
- `NamedTuple`: `(; invasive, infiltrative, singles, fingers, detached, clusters,
  cluster_leaders, cluster_followers)`. The areas are `Float64`, the counts `Int` and the
  cluster lists `Vector{Int}`.

# Examples
```julia
using PottsModels, Potts
prob = PottsProblem(AkeebInvasion(; name = :a), akeeb_state(), (0, 701); capacity = 4000)
sol = solve(prob, SequentialCPM(; proposal = VonNeumann(1)); save_everystep = false)
akeeb_observables(sol.u[end])    # the authors' "MCS 700"
```

See also [`akeeb_phenotype`](@ref).
"""
function akeeb_observables(σ::AbstractMatrix{<:Integer}, kinds::AbstractVector{Symbol})
    A = Analysis
    X = size(σ, 1)
    size(σ, 2) >= 2 ||
        throw(ArgumentError("akeeb_observables: σ needs at least 2 rows in y, got \
            size $(size(σ))"))
    n = Int(maximum(σ; init = 0))
    length(kinds) >= n ||
        throw(ArgumentError("akeeb_observables: σ has cell ids up to $n but there \
            are $(length(kinds)) kinds"))
    alive = falses(n)
    for c in σ
        c > 0 && (alive[c] = true)
    end
    for c in 1:n                                  # an id that owns no site is not a cell
        alive[c] && !(kinds[c] in (:leader, :follower)) &&
            throw(ArgumentError("akeeb_observables: kind of cell $c must be :leader or \
                :follower, got :$(kinds[c])"))
    end
    leader(c) = kinds[c] === :leader
    g = A.cell_graph(σ; periodic = (true, false))                       # O1
    seeds = unique(Int(σ[x, 2]) for x in 1:(X - 1) if σ[x, 2] != 0)     # O2
    isempty(seeds) &&
        throw(ArgumentError("akeeb_observables: no cell owns a site in row y = 2 (x ∈ \
            1:$(X - 1)), so there is no main tumor"))
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
    invasive = A.trapezoid_integral(kept, main .- base)                             # O4
    infiltrative = A.trapezoid_integral(kept, top_out[kept] .- base)
    # O5
    fingers = length(
        A.merge_peaks(A.find_peaks(main; prominence = 10, distance = 10, width = 5), 15)
    )
    return (;
        invasive, infiltrative, singles, fingers, detached, clusters = length(counted),
        cluster_leaders = [count(leader, k) for k in counted], cluster_followers = [
            count(!leader, k)
                for k in counted
        ],
    )
end

function akeeb_observables(u)
    σ = Array(u.ownership)
    codes = Array(u.cell.kind)
    n = Int(maximum(σ; init = 0))
    return akeeb_observables(σ, [codes[c] == 1 ? :leader : :follower for c in 1:n])
end

"""
    akeeb_phenotype(obs) -> Symbol

Return the invasion phenotype of one measured state, by the authors' area-equality
classifier.

The classifier is the paper's Fig. 5B and S1 Table: the first `classify_phenotype` of
`Implementation/TumorInvasionAnalysis/ResultExtraction.ipynb`, cell 3, in the authors'
released code. The tests are applied in order, and the areas are compared exactly:

- `:none`: `invasive == infiltrative`, no fingers, no singles, no clusters;
- `:single`: `invasive < infiltrative`, no fingers, singles, no clusters;
- `:bulk`: `invasive == infiltrative`, fingers, no singles, no clusters;
- `:multimodal`: `invasive < infiltrative`, fingers and singles (any clusters);
- `:unclassified`: anything else. The authors drop these states before computing
  phenotype fractions.

The paper's Fig. 5A uses a different rule, on fingers, singles and clusters only
(`docs/design/research/model-specs/10_akeeb_invasion.md` §5.3.5); it is not this function.

# Arguments
- `obs`: any value with the fields `invasive`, `infiltrative`, `fingers`, `singles` and
  `clusters`, such as the result of [`akeeb_observables`](@ref).

# Returns
- `Symbol`: `:none`, `:single`, `:bulk`, `:multimodal` or `:unclassified`.

# Examples
```jldoctest
julia> using PottsModels

julia> akeeb_phenotype((; invasive = 5.0, infiltrative = 9.0, fingers = 0, singles = 2,
                          clusters = 0))
:single
```

See also [`akeeb_observables`](@ref).
"""
function akeeb_phenotype(obs)
    inv, inf = obs.invasive, obs.infiltrative
    f, s, c = obs.fingers, obs.singles, obs.clusters
    inv == inf && f == 0 && s == 0 && c == 0 && return :none
    inv < inf && f == 0 && s > 0 && c == 0 && return :single
    inv == inf && f > 0 && s == 0 && c == 0 && return :bulk
    inv < inf && f > 0 && s > 0 && c >= 0 && return :multimodal
    return :unclassified
end
