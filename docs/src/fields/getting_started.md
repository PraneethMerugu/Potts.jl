# [Getting started: a field on the lattice](@id fields-getting-started)

LatticePDE puts a ModelingToolkit `PDESystem` on a lattice and solves it with SciML's
`solve`. This tutorial solves a spot of a chemical that diffuses and decays on a
64 × 64 lattice, makes a video of it, and then solves the same problem with Tsit5. It
needs no Potts model.

The tutorial uses these packages:

- ModelingToolkitBase, to write the equations;
- LatticePDE, to discretize and solve them;
- MakiePotts and CairoMakie, for the video;
- OrdinaryDiffEqTsit5, for the last step.

## Step 1: Write the PDE system

1. Declare the coordinates, the parameters and the field.
2. Write the equation, the initial value and the domain.
3. Build the `PDESystem`.

```@example fgs
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 1.0 k = 0.1
@variables c(..)
eq = D(c(t, x, y)) ~ Dc * laplacian(c(t, x, y)) - k * c(t, x, y)
ic = [c(0, x, y) ~ exp(-((x - 32)^2 + (y - 32)^2) / 20)]
dom = lattice_domain(t, (x, y), (64, 64); tspan = (0.0, 20.0))
@named spot = PDESystem(eq, ic, dom, [t, x, y], [c(t, x, y)], [Dc, k])
nothing # hide
```

- `laplacian(c)` is the lattice Laplacian. `Δ` is the same function.
- `lattice_domain` gives `x ∈ [0, 64]` and `y ∈ [0, 64]`: one length unit per site.
- The condition at `t = 0` is the initial value. The spot is centered at the middle of the
  lattice.
- The system has no face conditions, so each face has zero flux.

## Step 2: Discretize

Put the system on a 64 × 64 lattice:

```@example fgs
prob = discretize(spot, LatticeDiscretization(Grid((64, 64))))
typeof(prob).name.name
```

The result is a plain SciML `ODEProblem`. The spacing comes from the domain:
`64 / 64 = 1`.

## Step 3: Solve with a field algorithm

1. Choose `ExplicitEuler()`, the lattice's forward Euler stepper.
2. Set the window `dt = 1.0` and save at every window.

```@example fgs
sol = solve(prob, ExplicitEuler(); dt = 1.0, saveat = 1.0)
sol.retcode, length(sol.t)
```

`ExplicitEuler` runs several substeps in each window. It takes the smallest count that
keeps the step stable:

```@example fgs
substep_counts(sol)
```

`field_report` shows why. The bound `ρ` adds the diffusion (`Dc · Σ 4/h² = 8`) and
the decay (`k = 0.1`):

```@example fgs
field_report(prob, ExplicitEuler(); dt = 1.0)
```

## Step 4: Read the field

`sol[c]` is one grid per save, as SciML reads a variable. `sol[:c]` and
`sol[c(t, x, y)]` are the same:

```@example fgs
size(sol[c][end])
```

Diffusion keeps the total amount, and decay removes a fraction `h k = 0.02` of it in each
of the 100 substeps (`h = 0.2`). So the total at `t = 20` is the first total times
`0.98^100`:

```@example fgs
sum(sol[c][end]), sum(sol[c][1]) * (1 - 0.2 * 0.1)^100
```

## Step 5: Make a video

1. Load MakiePotts and a Makie backend.
2. Record one frame per save with `record_field`.

```@example fgs
using MakiePotts, CairoMakie
record_field("fields_spot.mp4", sol, c; framerate = 6, figure = (; size = (480, 400)))
nothing # hide
```

```@raw html
<video src="../fields_spot.mp4" controls autoplay loop muted playsinline width="480"></video>
```

The color range is fixed over all saves, so the spot fades as it spreads. `fieldplot`
plots one save; its `index` keyword selects the save:

```@example fgs
fig, ax, plt = fieldplot(sol, c; index = 6)
Colorbar(fig[1, 2], plt)
fig
```

## Step 6: Solve the same problem with Tsit5

The problem is an `ODEProblem`, so any OrdinaryDiffEq solver takes it. Tsit5 adapts its
step to a tolerance and does not use the lattice's bound:

```@example fgs
using OrdinaryDiffEqTsit5
sol5 = solve(prob, Tsit5(); saveat = 1.0)
sol5.retcode
```

Its time error is small, so the total follows the exact decay `e^{-k t}`:

```@example fgs
sum(sol5[c][end]), sum(sol5[c][1]) * exp(-0.1 * 20)
```

The two solutions differ by the time error of forward Euler, about 4 % of the peak:

```@example fgs
maximum(abs, sol5[c][end] - sol[c][end]) / maximum(sol5[c][end])
```

## Next steps

- [Boundary conditions](@ref fields-boundaries): fixed values, fluxes, Robin faces,
  periodic axes and masks.
- [Solvers](@ref fields-solvers): implicit steppers, steady fields and the linear solvers.
- [Grids](@ref fields-grids): spacing, coarse fields, hexagonal lattices and irregular
  domains.
- [Number types](@ref fields-types): single and half precision, and derivatives.
- [Maps](@ref fields-maps): fields that step in discrete time.
- [SciML interop](@ref fields-sciml): OrdinaryDiffEq solvers, sparse Jacobians, the
  integrator and inputs that change in time.
- [How it works](@ref fields-how): the pipeline, the substep count and the order of
  groups.
- [Coupling to a Potts model](@ref fields-coupling): fields that read and drive cells.
