# [Layouts](@id manual-layouts)

A layout builds an initial state from layers. [Tutorial 4](@ref tutorial-layouts) walks
through them; this page is the reference.

## Turning layers into an operating point

- `layout(l, sys)` paints `l` on the lattice of model `sys` (its size, boundaries,
  neighbourhood, domain and geometry) and returns `[ownership => σ, kind => kinds]`.
- `layout(l, dims)` paints on a closed square lattice of size `dims` with `Moore(1)`.
- `layout(l, x; report = true)` also returns one row per layer, in paint order, with
  `type`, `requested`, `painted` (cells created), `dropped` (painted over completely),
  `misses` and `counted` (`InsertUntil`), `clipped` (the points of a `Voronoi` region lost
  to closed edges and the domain; 0 for the other built-in layers) and `splits` (cells this
  layer alone cut into disconnected pieces).
- Cells left without a site are dropped and the rest renumbered in order. `layout` warns
  when a cell ends up in disconnected pieces, unless every layer that cut it has
  `splits = :allow`.

## Built-in layers

| Layer | Paints |
|---|---|
| `Tiling(size; spacing = 0, region, kinds, partial = :skip)` | boxes of `size` filling `region` (default: the lattice), `spacing` apart, in column-major order; `kinds` is cycled; `partial = :clip` keeps the part of a box that sticks out of the region |
| `Scattered(n, size; region, kinds, seed, gap = 1)` | `n` boxes at random positions, at least `gap` sites apart; throws when they cannot be placed |
| `Frame(kind; width = 1)` | one cell owning every site within `width` of a closed edge (or of the domain boundary) |
| `InsertUntil(kind; into, number \| fraction, seed, region, misses = :retry)` | one-site cells of `kind` at random sites of cells of the kinds `into`, until `number` are made or `kind` is a `fraction` of all cells; `misses = :count` counts draws that miss |
| `Voronoi(points; region, lloyd = 0, kinds)` | one cell per generator, filling the region's medium sites (it never cuts an earlier layer): each site goes to the nearest generator; `lloyd = k` moves the generators to their cells' centroids k times; every cell is one piece |
| `overlay(layers...)` | the layers in order, later ones on top |

Box coordinates are lattice indices, so layouts work in 1D, 2D and 3D. On a hexagonal lattice
they are axial and a box is a rhombus. `remake(layer; kw...)` rebuilds a layer with some
keywords changed (`remake(Scattered(…); seed = 2)`). Random layers own their seed, so
adding a layer never changes another layer's draws.

## Shapes and points

`region` is a tuple of index ranges (a box) or, for `Voronoi` and `RandomPoints`, a round
shape: `Circle(Point(x, y), r)`, `Sphere(Point(x, y, z), r)` or `HyperSphere`. These are
GeometryBasics' types, the same bindings Makie exports, so `using Potts, CairoMakie` is
unambiguous.

- Shapes and points are **Cartesian**: the lattice's embedding of the index (the identity on
  a square lattice, `(q + r/2, r√3/2)` on a hexagonal one), so a circle is round on a
  hexagonal lattice too.
- Membership is **closed**: a site belongs to `Circle(c, r)` when its embedded position is
  at distance `≤ r` from `c`, up to rounding (a relative `1e-12`, so a hexagonal disc of
  radius 1 about a site holds the site and all 6 neighbours).
- A shape **wraps** through a periodic edge and is **clipped** at a closed edge and at the
  domain; the report's `clipped` counts the lost points.

The point patterns are

| Pattern | Points |
|---|---|
| `Center()` | the lattice centre, `embed((size .+ 1) ./ 2)` |
| `RandomPoints(n; region, seed)` | `n` distinct in-domain sites of `region`, drawn uniformly with `Potts.layer_rng(seed)` |
| `[Point(…), Center(), …]` | the given points |

`Potts.points(pattern, sys)` returns a pattern's points on a lattice. A round aggregate of
`n` compact cells, as in Graner and Glazier's sorting experiment, is

```julia
ball = Circle(Point(50.5, 50.5), 30.0)
layout(Voronoi(RandomPoints(200; region = ball, seed = 1); region = ball, lloyd = 30, kinds = [:dark, :light]), (100, 100))
```

!!! note "DomainSets"
    DomainSets (which ModelingToolkit loads) exports its own `Sphere` and `Point`. After
    `using Potts, DomainSets` both names are ambiguous: write `Potts.Sphere` and
    `Potts.Point`, or import the ones you need (`using Potts: Sphere, Point`).

## Writing a layer

Subtype `AbstractLayout` and add one method, `Potts.paint!(op::Potts.LayoutState, l, lat)`.
The paint state `op` is used only through:

| Function | Does |
|---|---|
| `Potts.new_cell!(op, kind)` | allocates a cell of `kind`, returns its number |
| `Potts.assign!(op, x, id)` | paints a site tuple, or a box of ranges, with cell `id` |
| `Potts.owner(op, x)` | the owner painted so far at site `x` (0 = medium) |
| `Potts.kindof(op, id)`, `Potts.ncells(op)` | a painted cell's kind; the number of cells so far |
| `Potts.record!(op; requested, painted, misses = 0, counted = painted, clipped = 0)` | the layer's report row |

The lattice `lat` is read through `size(lat)`, `Potts.isperiodic(lat, d)`,
`Potts.indomain(lat, x)` and `Potts.core_lattice(lat)` (for CorePotts' `shift`, `relation`
and `embed`). A random layer draws from `Potts.layer_rng(seed)` (and
`Potts.layer_rng(seed, :name)` for a second, independent stream), which is the same on every
Julia version.

```@example mlayouts
using Potts

struct Stripe <: AbstractLayout
    rows::UnitRange{Int}
    kind::Symbol
end
function Potts.paint!(op::Potts.LayoutState, l::Stripe, lat)
    id = Potts.new_cell!(op, l.kind)
    Potts.assign!(op, (l.rows, 1:size(lat)[2]), id)
    Potts.record!(op; requested = 1, painted = 1)
    return nothing
end

op, report = layout(overlay(Tiling((4, 4); kinds = [:a1]), Stripe(9:12, :b1)), (20, 20); report = true)
report
```
