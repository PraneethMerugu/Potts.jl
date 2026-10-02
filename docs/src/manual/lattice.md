# [Lattices and relations: `@lattice`, `@relations`](@id manual-lattice)

## The lattice

`@lattice Lattice(dims; boundary, neighborhood, spacing, domain, geometry)` declares the
grid:

| Keyword | Values | Default |
|---|---|---|
| `dims` | `(nx, ny)` or `(nx, ny, nz)`; 1D, 2D and 3D work | — |
| `boundary` | `Periodic()` or `Closed()`, one for all axes or a tuple per axis | `Periodic()` |
| `neighborhood` | the contact (and surface) relation, see below | `Moore(1)` |
| `spacing` | site size per axis, used by `position` and the field Laplacian | 1 |
| `domain` | a `Bool` array, or a function `x -> condition`, restricting the lattice | whole box |
| `geometry` | `Square()` (cubic in 3D) or `Hexagonal()` (2D) | `Square()` |

A closed boundary has no copies across it; fields have zero flux there. Sites outside a
`domain` belong to no cell and act as a closed boundary for copies and fields.

```@example lattice
using Potts, MakiePotts, CairoMakie
CairoMakie.activate!(type = "png") # hide

@potts_model InADisk begin
    @kinds medium cell
    @lattice Lattice((50, 50); boundary = Closed(), neighborhood = Moore(1),
        domain = x -> (x[1] - 25.5)^2 + (x[2] - 25.5)^2 <= 23^2)
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 6.0 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = 8.0)
end
@named disk = InADisk()
op = layout(Tiling((5, 5); region = (11:40, 11:40), spacing = 1, kinds = [:cell]), disk)
sol = solve(PottsProblem(disk, op, (0, 200); seed = 1), SequentialCPM())
fig = Figure(size = (320, 320))
ax = Axis(fig[1, 1]; aspect = DataAspect())
hidedecorations!(ax)
pottsplot!(ax, renderframe(sol); boundaries = true)
fig
```

The grey region outside the disk is outside the domain.

### Hexagonal lattices

`geometry = Hexagonal()` makes a 2D hexagonal lattice. Sites are stored on the usual array
in axial coordinates. `Hex(k)` is the ball of hex distance `k` (6, 18, 36 neighbours);
`Moore(k)` and `VonNeumann(k)` mean `Hex(k)` on this geometry. The 12 *second-nearest*
neighbours of a hexagonal site (in Euclidean distance shells) are `NeighborOrder(2)`, not
`Hex(2)`, which has 18. Centroids, distances and the Laplacian are Cartesian.

```@example lattice
@potts_model HexSorting begin
    @kinds medium dark light
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @lattice Lattice((30, 30); geometry = Hexagonal(), neighborhood = Hex(2))
    @relations proposal = Hex(1)
    @energy begin
        cells(dark, light) => (volume - 19)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 8.0)
end
@named hexsort = HexSorting()
op = layout(Tiling((4, 4); region = (5:26, 5:26), kinds = [:dark, :light]), hexsort)
sol = solve(PottsProblem(hexsort, op, (0, 200); seed = 1), SequentialCPM())
fig = Figure(size = (320, 320))
ax = Axis(fig[1, 1]; aspect = DataAspect())
hidedecorations!(ax)
pottsplot!(ax, renderframe(sol))
fig
```

The plot shows the axial array; the cells are compact on the hexagonal lattice.

## Neighbourhoods

A neighbourhood (a **relation**) is a set of offsets:

| Relation | Offsets | 2D count | 3D count |
|---|---|---|---|
| `VonNeumann(k)` | Manhattan distance ≤ k | 4 (k = 1) | 6 |
| `Moore(k)` | Chebyshev distance ≤ k | 8 (k = 1), 24 (k = 2) | 26 |
| `NeighborOrder(k)` | the first `k` distance shells (CompuCell3D) | 4, 8, 12, 20, … | 6, 18, 26, … |
| `Ball(r)` | Euclidean distance ≤ r | | |
| `Hex(k)` | hex distance ≤ k (hexagonal lattices) | 6, 18, 36 | |
| `Stencil([(1, 0), (-1, 0), …])` | explicit offsets | | |

`include_self = true` adds the zero offset, for folds over a site and its neighbours (the
Act model's geometric mean).

## Relation roles: `@relations`

A model uses relations in three roles:

- **contact**: the pairs of `contacts` energy terms and the bonds counted by `surface`; set
  by `@lattice … neighborhood = …`.
- **proposal**: where a copy comes from: a random neighbour of the target site in this
  relation. The default is the first shell (`VonNeumann(1)`: 4 in 2D, 6 in 3D).
- **named relations**, used by `contacts(name)` terms and by folds such as
  `sum(c[n] for n in name(site))`.

```@example lattice
@potts_model Roles begin
    @kinds medium cell
    @lattice Lattice((40, 40); neighborhood = Moore(1))
    @relations begin
        proposal = Moore(1)           # copy from any of the 8 neighbours
        far = Ball(3.0)               # a named relation
    end
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 6.0 * (kind != kind′)
        contacts(far) => 0.2 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = 8.0)
end
@named roles = Roles()
prob = PottsProblem(roles, layout(Tiling((5, 5); region = (11:30, 11:30), kinds = [:cell]), roles), (0, 50))
solve(prob, SequentialCPM()).retcode
```

The algorithm can also override the proposal relation per solve:
`SequentialCPM(; proposal = Moore(1))`. Widening the contact relation never widens the
proposals.
