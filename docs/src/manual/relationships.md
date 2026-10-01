# [Relationships: `@relationship`, `@link`, `@unlink`](@id manual-relationships)

A **relationship** is a named set of links between cells, with at most `capacity` links per
cell. A model can declare several.

| Statement | Meaning |
|---|---|
| `@relationship bond(cell, cell) capacity = 4` | declare `bond` |
| `@variables rest(bond) = 6.0` | an edge variable: one value per link (default for new links) |
| `@energy edges(bond) => k * (distance - rest)^2` | an energy summed over the links |
| `@link bond when = cond` | link touching, unlinked pairs (`new_contact(a, b)`) where `cond` holds |
| `@unlink bond when = cond` | remove links where `cond` holds |
| `every = n` or `Every(n)` | check a link rule every `n` MCS |

In edge terms and link rules, `a` and `b` are the two cells, `distance` the distance between
their centroids, and cell quantities are read as `kind[a]`, `volume[b]`, `x[a]`. Link rules
run at the end of the MCS. Initial links go in the operating point as
`:bond => [(1, 2), (2, 3)]`. Cells that die lose their links; daughters start unlinked.

```@example rel
using Potts
using Potts: CorePotts

@potts_model Tethers begin
    @kinds medium leader follower
    @parameters J[kind, kind] = [0 12 12; 12 8 8; 12 8 8]
    @variables len(tether) = 8.0
    @relationship tether(cell, cell) capacity = 2
    @relationship touch(cell, cell) capacity = 4
    @lattice Lattice((50, 50); neighborhood = Moore(1))
    @energy begin
        Volume(leader, follower; target = 25.0, strength = 1.0)
        contacts => J[kind, kind′]
        edges(tether) => 1.0 * (distance - len)^2
        edges(touch) => 0.5 * (distance - 5.0)^2
    end
    @link tether when = new_contact(a, b) && (kind[a] == leader) && (kind[b] == follower)
    @link touch when = new_contact(a, b), every = 10
    @unlink touch when = distance > 9.0
    @sweep Metropolis(; temperature = 10.0)
end

@named tethers = Tethers()
op = layout(Tiling((5, 5); region = (16:35, 16:35), kinds = [:leader, :follower, :follower]), tethers)
sol = solve(PottsProblem(tethers, op, (0, 100); seed = 1), SequentialCPM())
u = sol.u[end]
count_links(u, name) = sum(c -> CorePotts.link_count(CorePotts.link_store(u.cell, name), c), eachindex(u.cell.volume)) ÷ 2
(tether = count_links(u, :tether), touch = count_links(u, :touch))
```

`CorePotts.link_store(u.cell, :name)` is the link table of a saved state;
`CorePotts.linked(store, a, b)` and `CorePotts.link_count(store, c)` query it. The edge
variable values of a relationship's links are stored as cell arrays (`u.cell.link_len`).
