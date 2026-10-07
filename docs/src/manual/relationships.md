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
| `@after_mcs rest ~ Pre(rest) + κ * (distance - Pre(rest))` | update an edge variable on every link |

In edge terms and link rules, `a` and `b` are the two cells, `distance` the distance between
their centroids, and cell quantities are read as `kind[a]`, `volume[b]`, `x[a]`. Link rules
run at the end of the MCS. Initial links go in the operating point as
`:bond => [(1, 2), (2, 3)]`, and an edge variable's value there (`:rest => 9.0`, one number,
or a parameter expression evaluated at construction: a later `remake` of parameters does
not re-seed it) is its initial value on every initial link of its relationship; without it the initial
links start at the default. Links made by `@link` always start at the default. Cells that
die lose their links; daughters start unlinked.

An update of an edge variable in `@before_mcs` or `@after_mcs` (with `Every(n)` as for any
update) runs once per existing link of its relationship, with the same names as an edge
term: `a`, `b`, `distance`, parameters, `mcs`, model variables and the relationship's edge
variables, `Pre(x)` being the value before the update block. Both stored ends of the link
get the new value. It creates and removes no links, and leaves links to a dead cell (volume
0) as they are. Reading another relationship's edge variable is an error naming the variable
and its relationship; another edge variable written in the same block is read only as
`Pre(y)`, at the same cadence. Rest lengths that relax toward the current distance, or bonds
that age, are

```julia
@after_mcs rest ~ Pre(rest) + κ * (distance - Pre(rest))
@before_mcs Every(10) age += 1
```

An extension (`@extend`) may re-declare an inherited edge variable to change its default:
`@variables rest(edge) = 9.0` over a base's `rest(bond)` stays an edge variable of `bond`,
whatever relationships the extension adds. Re-declaring it as an edge variable of another
relationship is an error: each edge variable belongs to one relationship.

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
