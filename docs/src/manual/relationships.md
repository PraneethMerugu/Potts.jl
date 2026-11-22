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
links start at the default. Links made by `@link` always start at the default. A cell
removed by the lifecycle loses its links; a cell squeezed out by copies (volume 0) keeps
them, contributing no energy, until the next `@link` or `@unlink` phase drops them.
Daughters start unlinked.

An update of an edge variable in `@before_mcs` or `@after_mcs` (with `Every(n)` as for any
update) runs once per existing link of its relationship, with the same names as an edge
term: `a`, `b`, `distance`, parameters, `mcs`, model variables and the relationship's edge
variables, `Pre(x)` being the value before the update block. Both stored ends of the link
get the new value. It creates and removes no links, and leaves the links of a cell squeezed
out by copies (volume 0) as they are. Reading another relationship's edge variable is an error naming the variable
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
using Potts.Layouts
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
        contacts => J[kind, neighbor_kind]
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
sol = solve(PottsProblem(tethers, op, (0, 100); seed = 1), SequentialCPM(); save_everystep = false)
u = sol.u[end]
count_links(u, name) = sum(c -> CorePotts.link_count(CorePotts.link_store(u.cell, name), c), eachindex(volumes(u))) ÷ 2
(tether = count_links(u, :tether), touch = count_links(u, :touch))
```

`CorePotts.link_store(u.cell, :name)` is the link table of a saved state;
`CorePotts.linked(store, a, b)` and `CorePotts.link_count(store, c)` query it. The edge
variable values of a relationship's links are stored as cell arrays (`u.cell.link_len`).

## Ordered relationships and angle terms

An **ordered** relationship links its members into chains. Each member has at most one
predecessor and one successor, so its capacity is 2.

```julia
@relationship chain(cell, cell) ordered = true
```

| Expression | Meaning |
|---|---|
| `prev(chain, c)` | the predecessor of cell `c`, or 0 for a head |
| `next(chain, c)` | the successor of cell `c`, or 0 for a tail |
| `rank(chain, c)` | the position of `c` in its chain: 1 for a head (and for a cell in no link) |
| `linked(chain, a, b)` | whether `a` and `b` are linked (any relationship) |
| `angles(chain) => E` | an energy summed over each member with both neighbors |

`prev` and `next` are references, as a `CellRef` variable is: read through them as
`kind[prev(chain, id)]`, and test them with `alive(next(chain, id))`. All four read the
stored links, so they are available where references are: cell energies, drives,
constraints, updates, link rules and `@observed`. The links change only between sweeps.

In the operating point, a pair `(x, y)` makes `y` the successor of `x`:
`:chain => [(1, 2), (2, 3), (3, 4)]` is a chain of four with head 1. A pair that gives a
cell a second predecessor or successor, or closes a chain on itself, is an `ArgumentError`.
`@link chain when = cond` links a touching pair from the cell for which `cond(a, b)` holds
(`a`) to the other (`b`), and does not make a link that would branch or close a chain.

Unlinking changes the order at once. When `@unlink` removes the link `x → y`, `y` becomes
the head of the rest of its chain, which is ranked again from 1. A cell squeezed out by
copies (volume 0) keeps its place until the next link phase drops its links: `prev` and
`next` still name it and `rank` counts it, but `alive` is false and its triples add no
energy. Then the chain splits there. A cell removed by the lifecycle loses its links at
once, and daughters start unlinked.

In an angle term, `pivot` is the member, `a` its predecessor and `b` its successor.
`angle` is the angle at the pivot between the centroids of `a` and `b`, in `[0, π]`, so a
straight triple has `angle = π`. `curvature` is `1/R`, the inverse radius of the circle
through the three centroids, which is `2 sin(angle) / |a − b|`. Both use minimum-image
vectors on periodic axes and the embedded geometry on a hexagonal lattice. A triple whose
centroids coincide in pairs has `curvature = 0`, and `angle = π` when the pivot coincides
with an end. A bending energy on the inverse radius of curvature and a stretching energy on
the links are

```julia
@energy begin
    angles(chain) => ξ * curvature^2
    edges(chain) => ζ * (distance - D)^2
end
```

The energy change of a copy is exact: the copy moves the centroids of `old` and `new`, and
every triple that contains either is evaluated again with both shifts. An angle term reads
parameters and the cell variables of its three cells that no `@on_copy` update writes
(`stiffness[pivot]`), but no edge variable, nothing a copy changes and no references. Only
`SequentialCPM` runs a model with an angle term: `CheckerboardCPM`, on the CPU or a GPU, is
an `ArgumentError`, because another block can move the two-hop neighbors whose centroids
the energy change reads.
