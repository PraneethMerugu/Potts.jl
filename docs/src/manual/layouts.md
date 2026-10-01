# [Layouts](@id manual-layouts)

A layout builds an initial state from layers. [Tutorial 4](@ref tutorial-layouts) walks
through them; this page is the reference.

## Turning layers into an operating point

- `layout(l, sys)` paints `l` on the lattice of model `sys` (its size, boundaries,
  neighbourhood, domain and geometry) and returns `[ownership => σ, kind => kinds]`.
- `layout(l, dims)` paints on a closed square lattice of size `dims` with `Moore(1)`.
- `layout(l, x; report = true)` also returns one row per layer, in paint order, with
  `type`, `requested`, `painted` (cells created), `dropped` (painted over completely),
  `misses` and `counted` (`InsertUntil`), and `splits` (cells this layer alone cut into
  disconnected pieces).
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
| `overlay(layers...)` | the layers in order, later ones on top |

Coordinates are lattice indices, so layouts work in 1D, 2D and 3D. On a hexagonal lattice
they are axial and a box is a rhombus. `remake(layer; kw...)` rebuilds a layer with some
keywords changed (`remake(Scattered(…); seed = 2)`). Random layers own their seed, so
adding a layer never changes another layer's draws.

## Writing a layer

Subtype `AbstractLayout` and add one method, `Potts.paint!(op::Potts.LayoutState, l, lat)`.
The paint state `op` is used only through:

| Function | Does |
|---|---|
| `Potts.new_cell!(op, kind)` | allocates a cell of `kind`, returns its number |
| `Potts.assign!(op, x, id)` | paints a site tuple, or a box of ranges, with cell `id` |
| `Potts.owner(op, x)` | the owner painted so far at site `x` (0 = medium) |
| `Potts.kindof(op, id)`, `Potts.ncells(op)` | a painted cell's kind; the number of cells so far |
| `Potts.record!(op; requested, painted, misses = 0, counted = painted)` | the layer's report row |

The lattice `lat` is read through `size(lat)`, `Potts.isperiodic(lat, d)`,
`Potts.indomain(lat, x)` and `Potts.core_lattice(lat)` (for CorePotts' `shift`, `relation`
and `embed`).

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
