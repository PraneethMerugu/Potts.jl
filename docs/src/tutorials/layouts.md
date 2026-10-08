# [Tutorial 4: building initial states with layouts](@id tutorial-layouts)

Every simulation starts from an initial state: which cell owns each site, and the kind of
each cell. A **layout** describes that state as a stack of simple layers. You will learn:

- the built-in layers `Tiling`, `Scattered`, `Frame`, `InsertUntil` and `Voronoi`;
- the shapes and point patterns `Circle`, `Point`, `Center()` and `RandomPoints`;
- how `overlay` stacks layers and how `layout` turns them into an operating point;
- how to check what each layer did with `report = true`;
- how to write your own layer.

```@example layouts
using Potts, PottsModels, MakiePotts, CairoMakie
CairoMakie.activate!(type = "png") # hide
nothing # hide
```

## A model to lay out

The layers name kinds, so we need a model. This one has a frozen `wall` kind: cells of a
kind marked `[frozen]` never move, which makes walls and obstacles.

```@example layouts
@potts_model Tissue begin
    @kinds medium wall[frozen] dark light
    @parameters J[kind, kind] = [0 0 16 16; 0 0 20 20; 16 20 2 11; 16 20 11 14]
    @lattice Lattice((40, 40); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 25.0, strength = 1.0)
        Adhesion(J)
    end
    @sweep Metropolis(; temperature = 10.0)
end
@named tissue = Tissue()

# draw the state of an operating point (a problem with zero length holds it)
function show_layout(op; title = "")
    fig = Figure(size = (300, 300))
    ax = Axis(fig[1, 1]; title, aspect = DataAspect())
    hidedecorations!(ax)
    pottsplot!(ax, renderframe(PottsProblem(tissue, op, (0, 0)).u0))
    return fig
end
nothing # hide
```

## Tiling

`Tiling(size; spacing, region, kinds)` fills a region with boxes of `size`, `spacing`
sites apart. The kinds are used in turn, box by box, in column-major order (down the first
axis first):

```@example layouts
tiles = Tiling((5, 5); spacing = 1, region = (5:36, 5:36), kinds = [:dark, :light])
op = layout(tiles, tissue)
show_layout(op)
```

`layout(l, sys)` paints the layers on the model's lattice and returns the operating point
`[ownership => σ, kind => kinds]`. `region` is a tuple of ranges, one per axis; it defaults
to the whole lattice. A box that does not fit in the region is skipped;
`partial = :clip` keeps its part inside instead.

## Scattered

`Scattered(n, size; region, kinds, seed, gap)` places `n` boxes at random, at least `gap`
medium sites apart. The same `seed` gives the same placement:

```@example layouts
seeds = Scattered(12, (4, 4); region = (3:38, 3:38), kinds = [:dark, :light], seed = 1, gap = 2)
show_layout(layout(seeds, tissue))
```

`remake` changes a keyword of a layer, for example another draw:
`remake(seeds; seed = 2)`. When the boxes cannot fit, `Scattered` throws an error that
says so.

## Frame and overlay

`Frame(kind; width = 1)` is one cell that owns every site within `width` of the closed edges
of the lattice. `overlay(layers...)` paints layers in order; later layers overwrite earlier
ones:

```@example layouts
op = layout(overlay(Frame(:wall), seeds), tissue)
show_layout(op)
```

With a frozen `wall` kind the frame is a box the cells cannot leave or push. Whether cells
spread along it depends on the contact energies. Each unit of boundary a cell lays
against the wall turns wall–medium contact into wall–cell contact and saves the same
length of cell–medium contact, so it pays
``J(\text{cell}, \text{wall}) - J(\text{medium}, \text{wall}) - J(\text{cell}, \text{medium})``.
The cell stays off the wall when this is positive, ``J(\text{cell}, \text{wall}) > J(\text{medium}, \text{wall}) +
J(\text{cell}, \text{medium})``. Here ``J(\text{medium}, \text{wall}) = 0`` and
``J(\text{cell}, \text{wall}) = 20 > 0 + 16``, so the wall is not wetted.

## InsertUntil

`InsertUntil(kind; into, number | fraction, seed)` turns random single sites of existing
cells into new one-site cells of `kind`, until it has made `number` of them or the new kind
is a `fraction` of all cells. Here a quarter of the cells of a dark tiling become light
seeds, which grow to their target area once the simulation starts:

```@example layouts
start = overlay(Frame(:wall),
    Tiling((5, 5); region = (2:39, 2:39), kinds = [:dark]),
    InsertUntil(:light; into = [:dark], fraction = 1 // 4, seed = 3))
op, report = layout(start, tissue; report = true)
show_layout(op)
```

An inserted site cuts a hole in the cell it lands in, and can split it into pieces;
`layout` warns when a cell ends up in pieces. `splits = :allow` on a layer accepts it.

## Voronoi aggregates

`Voronoi(points; region, lloyd, kinds)` divides a region into one cell per generator point:
each site goes to the nearest generator. `RandomPoints(n; region, seed)` draws `n` distinct
sites of a region as generators, and `lloyd = k` moves every generator to the centroid of
its cell `k` times (Lloyd's algorithm), which makes the cells compact and of similar size.
The region here is a disk, `Circle(Point(x, y), r)`, in the lattice's Cartesian
coordinates; `Center()` is the lattice centre as a point:

```@example layouts
disk = Circle(Point(20.5, 20.5), 15.0)
aggregate = Voronoi(RandomPoints(28; region = disk, seed = 1); region = disk, lloyd = 30, kinds = [:dark, :light])
show_layout(layout(overlay(Frame(:wall), aggregate), tissue))
```

This is the round aggregate of Graner and Glazier's cell-sorting experiment
([`graner_glazier_aggregate`](@ref)). `Voronoi` only fills medium sites, so the frame
painted first is never cut. A shape that crosses a closed edge or the domain is clipped
(the report's `clipped` counts the lost sites); on a periodic lattice it wraps through the
edge instead.

## Seed and grow

`Eden(points; rounds, kinds, seed)` puts a one-site cell at each point and grows the cells
for `rounds` rounds: in each round, every medium site next to a growing cell picks one of
its neighbours at random and joins it if that neighbour is a growing cell. `Splits(layer,
k)` then cuts every cell of a layer in two across its long axis, `k` times over. Together
they are the TST starting states of Merks et al.'s angiogenesis models: one blob at the
centre, divided into 2⁴ = 16 cells here:

```@example layouts
sprout = Splits(Eden(Center(); rounds = 12, kinds = [:dark], seed = 2), 4; splits = :allow)
show_layout(layout(overlay(Frame(:wall), sprout), tissue))
```

Seeds drawn with `RandomPoints(n; replace = true, seed)` may coincide, and coinciding seeds
merge into one cell. `Eden` then paints fewer cells than it was given points, which it
refuses unless told otherwise with `shortfall = :allow` (or `:warn`):

```@example layouts
seeds = RandomPoints(60; region = (2:39, 2:39), replace = true, seed = 4)
op = layout(overlay(Frame(:wall), Eden(seeds; rounds = 2, kinds = [:dark, :light], seed = 1, shortfall = :allow)), tissue)
show_layout(op)
```

## The layout report

With `report = true`, `layout` also returns one row per layer: how many cells the layer
was asked for, how many it painted, how many were later painted over completely (dropped),
and, for `InsertUntil`, the draws that missed:

```@example layouts
foreach(println, report)
```

## Running from a layout

The operating point goes to `PottsProblem` like any other. The tiled tissue sorts inside its
frozen frame:

```@example layouts
op = layout(overlay(Frame(:wall), Tiling((5, 5); region = (5:36, 5:36), kinds = [:dark, :light])), tissue)
prob = PottsProblem(tissue, op, (0, 1500); seed = 1)
sol = solve(prob, SequentialCPM(); saveat = 25)
record_potts("layouts_frame.mp4", sol; framerate = 12, title = "", figure = (; size = (420, 420)))
nothing # hide
```

```@raw html
<video src="../layouts_frame.mp4" controls autoplay loop muted playsinline width="420"></video>
```

The operating point can also set other initial values: append pairs such as `:c => c0`
(a field) or `:V₀ => 30.0` (a parameter) to it.

## Writing the arrays yourself

A layout is a convenience. Any integer matrix of cell numbers works, with one kind per
cell number:

```@example layouts
σ = zeros(Int32, 40, 40)
σ[2:39, 1] .= 1; σ[2:39, 40] .= 1        # cell 1: two walls (one cell can have several pieces)
σ[10:15, 10:15] .= 2                     # cell 2
σ[25:30, 20:25] .= 3                     # cell 3
show_layout([ownership => σ, kind => [:wall, :dark, :light]])
```

## Your own layer

A new layer is a type and one method, `Potts.paint!(op, layer, lattice)`. Inside it,
`Potts.new_cell!(op, kind)` makes a cell and returns its number, `Potts.assign!(op, x, id)`
paints a site or a box of sites, and `Potts.record!` fills the layer's report row. This
layer paints a disk of one kind:

```@example layouts
struct Disk <: AbstractLayout
    center::Tuple{Int, Int}
    radius::Float64
    kind::Symbol
end

function Potts.paint!(op::Potts.LayoutState, d::Disk, lat)
    id = Potts.new_cell!(op, d.kind)
    for x in CartesianIndices(size(lat))
        sum(abs2, Tuple(x) .- d.center) <= d.radius^2 && Potts.assign!(op, Tuple(x), id)
    end
    Potts.record!(op; requested = 1, painted = 1)
    return nothing
end

show_layout(layout(overlay(Tiling((4, 4); kinds = [:dark]), Disk((20, 20), 9.0, :light)), tissue))
```

The disk overwrites the tiles under it, and tiles left without a site are dropped. Other
queries are `Potts.owner(op, x)`, `Potts.kindof(op, id)` and `Potts.ncells(op)` for the
paint so far, and `Potts.isperiodic(lat, d)` and `Potts.indomain(lat, x)` for the lattice;
see [Layouts](@ref manual-layouts).

!!! tip "Published initial states are layouts too"
    The initial slab of the Akeeb et al. invasion model is written with the same public
    layers, a clipped `Tiling` of followers and an `InsertUntil` of leaders:
    `akeeb_layout(; lattice = (500, 300))`.

## What you learned

- `Tiling`, `Scattered`, `Frame`, `InsertUntil`, `Voronoi`, `Eden` and `Splits` are layers;
  `overlay` stacks them.
- Shapes (`Circle`, `Sphere`) and points (`Point`, `Center()`, `RandomPoints`) are Cartesian.
- `layout(l, sys)` gives the operating point; `report = true` explains what each layer did.
- A custom layer is a struct and a `Potts.paint!` method.

**See also:** [`AkeebInvasion`](@ref model-akeeb) for the layout of a published model.

Next, [Tutorial 5](@ref tutorial-cell-odes) puts ODEs inside cells.
