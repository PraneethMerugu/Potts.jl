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
domain_run = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "domains_and_initialization.jl"))
(domain_run.mutable_sites, domain_run.initial_cells,
    domain_run.declared_capacity)
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
