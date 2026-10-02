# [Roadmap](@id roadmap)

!!! warning "Not yet available"
    Everything on this page is **planned, not implemented**. The syntax shown is a design
    sketch and may change. None of it works in the current version; the rest of the
    documentation describes only what works today.

## Lifecycle rules

Today a cell dies by losing its sites, and kinds change only through callbacks. Planned:

```julia
# NOT YET AVAILABLE
@retire cells(tumor) when = volume < 2               # remove a cell, its sites to the medium or neighbours
@create medium when = rand() < p, kind = tumor        # seed new cells
@transition cells(follower) => leader when = …        # change kind by a rule
@terminate when = count(true for c in cells(tumor)) == 0
```

Division options planned: `side = RandomSide()` / `CanonicalSide()`, a plane from cell
state (`along = normal(orientation)`), and a `daughter` index in state rules.

## Energies and acceptance

- Contact and surface energies per unit boundary length: `contacts(; per_length = true)`.
- Library terms for adhesion molecules (`Homophilic`, `Heterophilic`), `Aspherity`,
  `ExternalPotential` in CompuCell3D's exact form, `Haptotaxis`.
- Shape descriptors beyond `major_length`: `minor_length`, `elongation`, `orientation`,
  `eccentricity` as built-ins.

## Motility

Vector-valued copy-scope names (`δcentroid[c]`, `normal`, `velocity[c]`) and library terms
`DirectedMotion`, `PersistentMotion`. Today persistent motion is written with the scalar
`displacement(c, k)` and `centroid(k)` (see [Drives](@ref manual-drive)).

## Neighbour cells

```julia
# NOT YET AVAILABLE
@observed signal(cell) ~ sum(delta[n] * contact(c, n) for n in neighbors(c)) / surface
```

Iteration over the cells touching a cell, weighted by the shared interface length, for
juxtacrine signalling and contact-dependent rules.

## Fields

- Kind-dependent diffusion in flux form, `∇⋅(Dc[kind] * ∇(c))`, with harmonic-mean faces.
- Secretion and uptake helpers (`secrete`, `uptake`, at rims, contacts or centroids).
- Per-face boundary conditions (`@boundary c begin … end`, Dirichlet and flux).
- Quasi-steady fields (`0 ~ Do * Δ(o) - …`) solved by a linear solver each MCS.
- Noise in cell and field equations (`@brownians`).

## Intracellular models

Kind-scoped equation blocks with their own solver and time step, and stochastic per-cell
components (`JumpSystem`, Catalyst reaction networks, SBML import).

## Initial states and I/O

- More layouts: Eden growth, `BrickWall`, chains, spheres, fibres, planes, and layouts from
  an image or mask.
- A MorpheusML importer, and live parameter steering in MakiePotts.
