"""
    AkeebInvasion(; name, lattice = (500, 300), J = akeeb_contacts(2.0), μ, …)

Leader/follower collective invasion with proliferation (Akeeb, Marcus & Jiang, PLoS
Comput. Biol. 22, e1014747, 2026), checked against the authors' CompuCell3D source:

- **Kinds.** Leaders and followers, both kept connected (CompuCell3D's `Connectivity`
  plugin: the losing cell's sites in the 8-ring must form one arc) and never extinct.
- **Energies.** A per-cell target volume, and adhesion
  `J = [0 2 10; 2 16 J_LF; 10 J_LF 5]` (medium, leader, follower).
- **Migration cue.** A static field `cue = y − 1`. A copy whose source or target cell is a
  leader gains `−μ Δcue`: leaders climb the cue (CompuCell3D's default chemotaxis).
- **Growth and division.** Followers with a mitotic clock (`clock ≥ 0`) grow their target
  volume by `rate` per MCS up to `V_max`. They divide when larger than `V_max` and their
  clock exceeds `clock_min + clock_spread · U(0, 1)`, with a fresh draw every MCS. The
  division plane is random, the target volume is split, and clocks restart.

Use `akeeb_state` for the published initial slab.

Faithful to the authors' CompuCell3D model, which differs from the paper's text in the
cue term (per-copy chemotaxis, not a potential over leader sites), the leader seeding and
the division timing. One CC3D step is 1 MCS here; the source runs 701.
"""
@potts_model AkeebInvasion begin
    @structural_parameters begin
        lattice = (500, 300)
    end
    @kinds medium leader follower
    @parameters begin
        λᵥ = 2.0
        μ = 30.0
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
leaders `StableRNG(seed)` (inside `InsertUntil`), the clocks `StableRNG(seed + 1)`, one
cell at a time in id order (a leader draws nothing).
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
    rng = StableRNG(seed + 1)
    clocks = [k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]
    rates = [k === :leader ? 0.0 : 0.015 for k in kinds]
    cue = [Float64(y - 1) for x in 1:X, y in 1:Y]
    return [ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]
end
