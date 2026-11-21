# [Boundary conditions](@id fields-boundaries)

A field's boundary conditions are the conditions of its `PDESystem`, its second argument.
This page shows each form: values and fluxes on a face, Robin faces, periodic axes and
site masks. A face without a condition has zero flux.

## Faces, a periodic axis and a mask

A field is read at a face by its coordinates, with one of them fixed: `c(t, 0, y)` is the
low face of `x`, and `c(t, Lx, y)` the high face, with `Lx` the extent of `x`. Read the
extents from the domain, so that the lattice size is written once:

```@example fbc
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 1.0 k = 0.05 S = 1.0 q = 0.1
@variables c(..) wall(..)::Bool [input = true]
dom = lattice_domain(t, (x, y), (40, 20); tspan = (0.0, 10.0))
Lx, Ly = maximum(dom[2].domain), maximum(dom[3].domain)   # 40.0, 20.0
C = c(t, x, y)
bcs = [
    c(0, x, y) ~ 0.0,                         # the initial value
    c(t, 0, y) ~ S,                           # the low x face held at S
    Differential(x)(c(t, Lx, y)) ~ q,         # a flux q in through the high x face
    c(t, x, 0) ~ c(t, x, Ly),                 # periodic in y
    C ~ masked(wall(t, x, y), 0.0),           # an absorbing wall
]
@named bar = PDESystem(D(C) ~ Dc * laplacian(C) - k * C, bcs, dom, [t, x, y],
    [C, wall(t, x, y)], [Dc, k, S, q])
walls = falses(40, 20)
walls[20:22, 5:15] .= true
prob = discretize(bar, LatticeDiscretization(Grid((40, 20))); inputs = [wall => walls])
sol = solve(prob, ExplicitEuler(); dt = 1.0, saveat = 1.0)
(wall = maximum(sol[c][end][20:22, 5:15]), low = sol[c][end][1, 10],
    high = sol[c][end][40, 10])
```

The wall holds 0, the edge site next to the low face is close to `S`, and the high face
feeds the field.

## Face conditions

A face condition sets one face of a closed axis. Its value is a ghost value, the missing
neighbor of an edge site:

| Condition (low face of `x`) | Meaning | Ghost value |
|---|---|---|
| `c(t, 0, y) ~ v` | `c = v` at the face (Dirichlet) | `2v − c`: the field reaches `v` midway between the edge site and the face |
| `Differential(x)(c(t, 0, y)) ~ 0` | zero flux | `c`: it mirrors the edge site |
| `Differential(x)(c(t, 0, y)) ~ -q` | `∂c/∂n = q`, with the outward normal `n` (Neumann) | `c + q h` |
| `α * c(t, 0, y) - β * Differential(x)(c(t, 0, y)) ~ g` | `α c + β ∂c/∂n = g` (Robin) | the value that meets the condition at the face |

- On the high face the outward normal is `+x`: `Differential(x)(c(t, Lx, y)) ~ q` is
  `∂c/∂n = q`.
- A closed axis without a condition has zero flux. A field with no condition that a
  spatial operator reads (`laplacian(v)`) also has zero-flux faces on each closed axis.
- A face coefficient that reads a field (`DivKGrad(:arithmetic)(c^3, c)`) takes the
  field's ghost value at the face. With `c(t, 0, y) ~ 1.0` and `c = 0` at the edge site,
  the face mean is `(0³ + 2³)/2`, so the field enters through the face. The bound of the
  field solvers covers these ghost values.
- The harmonic mean of `0³` and `2³` is 0, so `DivKGrad(:harmonic)` keeps a degenerate
  front (`K = 0` where `c = 0`) from moving. Use `DivKGrad(:arithmetic)` for degenerate
  diffusion.
- An initial condition (`c(0, x, y) ~ v`) is the field's initial value, not a boundary
  condition.

## Values and Robin coefficients

**Values** of faces and masks are expressions of numbers, parameters, the coordinates and
`t`: `c(t, 0, y) ~ S1 + S2`, `c(t, 0, y) ~ c0 * sin(ω * t)`,
`Differential(x)(c(t, Lx, y)) ~ 0.5y`.

- A value that is not a number or a number times a parameter is computed at each boundary
  site at the time of each substep.
- `remake(prob; p = [:S => 2.0])` changes a value without generating code again.

**Robin coefficients** `α` and `β` are expressions of numbers, parameters, the coordinates
and `t`, as values are.

- A number, a parameter or a number times a parameter is read as it is.
- Any other expression of parameters alone (`a + b`) is one value at every site. A
  computed parameter of the face holds it, named `c_x_low_α` (field, axis, side,
  coefficient). It reads like any computed parameter and is derived again after every
  write.
- The slot holds `β` as the coefficient of the outward `∂c/∂n`, however the face is
  written: on a low face, `c_x_low_β` is minus the coefficient of `∂c/∂x`.
- A coefficient that reads the coordinates or the time varies by site or in time:
  `(1 + 0.1y) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ g`. It is computed at each
  boundary site at the time of each substep. An implicit field with such a face builds its
  operator per site, and builds it again at each substep when a coefficient reads the
  time.
- Where `α` and `β` have opposite signs at a site, that site's part stays out of the
  implicit operator, and the Newton iterations correct it. The automatic explicit count
  bounds the face over its sites, and over each step's time span when a coefficient reads
  the time, so the count can change from one window to the next.

A Robin face with `BackwardEuler`:

```@example fbc
@parameters a = 2.0 b = 1.0
rob = PDESystem(D(C) ~ Dc * laplacian(C) - k * C,
    [c(0, x, y) ~ 0.0, a * c(t, 0, y) - b * Differential(x)(c(t, 0, y)) ~ 1.0],
    dom, [t, x, y], [C], [Dc, k, a, b]; name = :rob)
rsol = solve(discretize(rob, LatticeDiscretization(Grid((40, 20)))), BackwardEuler();
    dt = 1.0, saveat = 10.0)
round.(rsol[c][end][1:3, 10]; digits = 3)
```

## Periodic axes

Periodicity is per field and axis:

- A periodic pair (`c(t, x, 0) ~ c(t, x, Ly)`) makes that field wrap on that axis. The
  other fields stay closed there.
- A condition on an axis the lattice lacks is an error that names it. So is a condition
  on a field whose equation has no spatial operator of it.
- [Periodicity per field](@ref fields-grids-periodic) shows an example and gives the
  rules for reads across fields that wrap differently.

## Site masks

`c ~ masked(condition, v)` is a node value: every explicit substep writes `v` at every
site where the condition holds.

- The value is written after the `lower_bound` clip, so a mask value below `lower_bound`
  wins.
- A fresh initial state (the problem's `u0`, `init`, `reinit!`) is clamped too. A state
  restored from a checkpoint is not: it continues the run exactly.
- The condition reads the inputs and fields of the `PDESystem`. It is evaluated once per
  window, before the substeps, on the clamped values, and held over the window. This holds
  for every field it reads, the field it clamps and a field stepped after it included.
  The masked sites take their value before the first substep.
- With several solver groups, a field of a group stepped earlier in the window reads as
  stepped, as a rate reads another group's field.
- Write a condition on the field it clamps with `>=`, as in `c ~ masked(c >= 0.8, 0.8)`.
  With `>`, the clamp sets `c = 0.8`, `0.8 > 0.8` is false, and the next window releases
  the sites.
- The masks of a field group cost one kernel launch per window.
- On a coarse grid, [Coarse fields](@ref fields-grids) gives the rule for a node.

[Masks](@ref fields-how-masks) gives the forms of a condition and how each solver holds
a mask.

## In a Potts model

A coupled `PDESystem` takes the same conditions. The lattice's periodic axes set the
default, and [Equations and solvers](@ref manual-equations) gives the rules for a field
whose conditions differ from the lattice's. A coupled system may leave its domain out:
each axis then spans the lattice. Write the high face from the lattice size and spacing
that the model uses, for example `dims = (200, 100)` with
`lattice_domain(t, (x, y), dims)`, and `c(t, maximum(dom[2].domain), y)`. A resize then
moves the face with the lattice.
