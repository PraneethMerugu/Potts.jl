# [Domains and initialization](@id domains-and-initialization)

A reusable model becomes executable only after a domain and layout are chosen. Keep these choices
out of the biological declarations when they vary between experiments.

## Cartesian domains

`CartesianDomain` supports two and three dimensions, positive spacing, one boundary pair per axis,
and immutable obstacle sites. The default is periodic on every axis. Available ownership boundary
conditions are:

- `PeriodicBoundary()` on both faces of an axis;
- `ClosedBoundary()` for an edge with no outgoing ownership relation;
- `FixedExterior(MediumOwner(...))` for a conceptual external medium or wall.

Periodic faces must occur as a pair. Obstacles remain in rectangular storage but are never mutable
recipient sites.

```@example domains-and-initialization
using PottsToolkit
import CorePotts

medium = Medium(:medium)
cell = CellType(:cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 4, strength = 2)),
)
domain = CartesianDomain(
    (6, 6);
    boundaries = (
        AxisBoundary(ClosedBoundary()),
        AxisBoundary(FixedExterior(CorePotts.MediumOwner(1))),
    ),
    obstacles = (
        CartesianIndex(3, 3) => CorePotts.MediumOwner(1),
        CartesianIndex(4, 3) => CorePotts.MediumOwner(1),
    ),
)
mask = falses(6, 6)
mask[2:3, 4:5] .= true
problem = PottsProblem(
    model,
    domain,
    Layout(Place(cell, mask; identity = 1));
    capacity = 4,
    tspan = (0, 1),
    seed = 3,
)

@assert CorePotts.mutable_site_count(domain) == 34
@assert backend_report(problem, SequentialCPM()).qualified
result = (; problem, mutable_sites = CorePotts.mutable_site_count(domain),
    initial_cells = CorePotts.n_cells(problem.u0), declared_capacity = 4)

(result.mutable_sites, result.initial_cells, result.declared_capacity)
```

## Layouts

Use the least ambiguous layout for the job:

| Layout | Use |
|:--|:--|
| `LabelledCells` | Exact externally prepared ownership |
| `Place` | One cell with an explicit mask |
| `UniformSiteSeeds` | Reproducible sparse seeds |
| `SequentialRejectionPlacement` | Procedural non-overlapping placement |

Large label arrays belong in data or canonical source files, not copied into prose.

## Capacity

Capacity is the maximum number of finite-cell slots, not the number of lattice sites. It must
contain the initial population and every admitted lifecycle outcome. Exhaustion is an error; the
engine does not silently resize storage or discard a division.

## Validate the realized problem

Model validation catches declaration defects. Problem validation additionally checks the domain,
layout, fields, capacity, cell identities, and declared medium domains. `backend_report` then
checks the exact model–algorithm–backend combination.

The canonical program combines closed and fixed-exterior axes with two immutable sites, places one
cell, and verifies that 34 of 36 sites remain mutable.
