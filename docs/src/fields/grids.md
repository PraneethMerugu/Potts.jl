# [Grids](@id fields-grids)

`LatticeDiscretization(Grid(dims))` puts a `PDESystem` on a lattice of `dims` sites. This
page shows how the spacing is set, and how to use coarse fields, a hexagonal lattice, an
irregular domain and periodicity per field.

## Sites and spacing

`Grid(dims)` gives only the site counts. The spacing comes from the system's domain,
`extent ./ dims`, and periodicity from its periodic pairs, so each fact has one source.
`lattice_domain(t, (x, y), dims; spacing)` writes the domain for you:

```@example fgrid
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 50.0 k = 1.0 s = 1.0
dom = lattice_domain(t, (x, y), (64, 64); spacing = 0.5, tspan = (0.0, 2.0))
dom[2], dom[3]
```

- The coordinates `x`, `y` and `z` in an equation are the site centers, from 0 at the low
  face: site `i` is at `(i - 1/2) h`.
- `spacing` is one number for every axis or one per axis.
- `sol[x]` of a solution gives the site centers.

The examples below use a lattice of spacing 1 and a source in its middle:

```@example fgrid
dom = lattice_domain(t, (x, y), (64, 64); tspan = (0.0, 2.0))
@variables c(..) src(..)::Bool [input = true]
C = c(t, x, y)
source = falses(64, 64)
source[28:36, 28:36] .= true
nothing # hide
```

## Coarse fields

A field with `[lattice_level = Coarse(k)]` lives on the grid coarsened by `k`: one node per
block of `k` sites on each axis, with the spacing `k h`. Here `m` is a slow field on a
16 × 16 grid that reads the fine field `c`:

```@example fgrid
@variables m(..) [lattice_level = Coarse(4)]
M = m(t, x, y)
@named slow = PDESystem(
    [D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y), D(M) ~ 2.0 * laplacian(M) + C - M],
    [c(0, x, y) ~ 0.0, m(0, x, y) ~ 0.0], dom, [t, x, y], [C, M, src(t, x, y)], [Dc, k, s])
cprob = discretize(slow, LatticeDiscretization(Grid((64, 64))); inputs = [src => source])
csol = solve(cprob, BackwardEuler(); dt = 0.5, save_everystep = false)
size(csol[c][end]), size(csol[m][end])
```

- `k` is a power of two, and it divides every axis of the lattice (an axis of size 1 is
  never coarsened).
- The field's equation, its conditions and its solver run on the coarse grid.
- A coarse field reads a fine field folded over each node's block: the coarse field
  receives the block's integral of the term. The docstring of [`Coarse`](@ref) gives the
  rules.
- A fine field reads a coarse one at the node of its block.
- A masked condition holds at a node when it holds at every site of the node's block; a
  block that it covers in part blends.

## A hexagonal lattice

`Grid(dims; geometry = HEX)` is a 2D lattice in axial coordinates: each site has six
neighbors.

```@example fgrid
@named spot = PDESystem(D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y),
    [c(0, x, y) ~ 0.0], dom, [t, x, y], [C, src(t, x, y)], [Dc, k, s])
hprob = discretize(spot, LatticeDiscretization(Grid((64, 64); geometry = HEX));
    inputs = [src => source])
hsol = solve(hprob, BackwardEuler(); dt = 0.5, save_everystep = false)
round(maximum(hsol[c][end]); digits = 4)
```

- `laplacian` is the only spatial operator on a hexagonal lattice. It lowers to
  `2/(3h²) Σₙ (cₙ − c)` over the six neighbors, and the axes must have equal spacing.
- Every implicit solver runs on the six-neighbor Laplacian.
- A face condition applies along each link that leaves the box. A diagonal link takes the
  condition of axis 1's face when it leaves along axis 1, else axis 2's.

## An irregular domain

`domain = dom` names a `Bool` input that marks the sites of the domain inside the box.
Give its values like any input:

```@example fgrid
@variables inside(..)::Bool [input = true]
@named disk = PDESystem(D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y),
    [c(0, x, y) ~ 0.0], dom, [t, x, y], [C, src(t, x, y), inside(t, x, y)], [Dc, k, s])
indisk = [hypot(i - 32.5, j - 32.5) < 25 for i in 1:64, j in 1:64]
dprob = discretize(disk, LatticeDiscretization(Grid((64, 64)); domain = inside);
    inputs = [src => source, inside => indisk])
dsol = solve(dprob, ExplicitEuler(); dt = 0.5, save_everystep = false)
dsol[c][end][1, 1]    # a site outside the disk keeps its value
```

- The fields live in the domain: a site outside it keeps its value, and its masked
  conditions do not hold.
- The domain's edge has zero flux: a neighbor read across it reads the site itself.
- Face conditions still apply at the faces of the box.
- On a coarse grid, a node is in the domain when most of its block is.

## [Periodicity per field](@id fields-grids-periodic)

A periodic pair makes its own field wrap on that axis. The other fields stay closed there,
with their face conditions or zero flux. Here `a` wraps on `y` and `b` does not, and the
source touches the low `y` face:

```@example fgrid
@variables a(..) b(..)
A, B = a(t, x, y), b(t, x, y)
Ly = maximum(dom[3].domain)
@named pair = PDESystem(
    [D(A) ~ laplacian(A) - 0.1A + src(t, x, y), D(B) ~ laplacian(B) - 0.1B + src(t, x, y)],
    [a(0, x, y) ~ 0.0, b(0, x, y) ~ 0.0, a(t, x, 0) ~ a(t, x, Ly)],
    dom, [t, x, y], [A, B, src(t, x, y)], [])
edge = falses(64, 64)
edge[28:36, 1:4] .= true
psol = solve(discretize(pair, LatticeDiscretization(Grid((64, 64))); inputs = [src => edge]),
    ExplicitEuler(); dt = 0.5, save_everystep = false)
(a_top = psol[a][end][32, 64], b_top = psol[b][end][32, 64])
```

`a` reaches the high `y` face through the wrap, and `b` does not.
[Periodicity per field](@ref fields-how-periodicity) gives the rules for reads across
fields that wrap differently.
