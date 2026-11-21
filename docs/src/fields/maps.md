# [Maps](@id fields-maps)

A map gives the next value of a field from its present values: `Shift(t, 1)(c) ~ rhs`.
This page shows how to write a map with neighbor reads, solve it, and what a map system
cannot hold.

## Write a map

1. Declare one spacing parameter per axis, with the axis in `lattice_spacing`.
2. Read a neighbor as the field at a shifted coordinate, such as `N(t, x + dx, y)`.
3. Write the map with `Shift(t, 1)` on the left side.

This map averages the four neighbors, then applies a logistic growth step:

```@example fmaps
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y dx [lattice_spacing = 1] dy [lattice_spacing = 2] r = 0.5
@variables N(..)
Ne = N(t, x, y)
dom = lattice_domain(t, (x, y), (32, 32); tspan = (0.0, 10.0))
avg = (N(t, x + dx, y) + N(t, x - dx, y) + N(t, x, y + dy) + N(t, x, y - dy)) / 4
ic = [N(0, x, y) ~ ifelse((x - 16)^2 + (y - 16)^2 < 9, 1.0, 0.0)]
@named grow = PDESystem([Shift(t, 1)(Ne) ~ avg + r * avg * (1 - avg)], ic, dom,
    [t, x, y], [Ne], [dx, dy, r])
nothing # hide
```

- The discretization supplies the value of each spacing parameter from the domain.
- A neighbor read outside the box reads the ghost of the face condition, as `laplacian`
  does. With no condition, a face has zero flux.

## Solve it

`discretize` returns a `DiscreteProblem`. [`ExplicitMap`](@ref) applies the map once per
unit of time:

```@example fmaps
prob = discretize(grow, LatticeDiscretization(Grid((32, 32))))
sol = solve(prob, ExplicitMap(); saveat = 1)
length(sol.t), round.(sol[Ne][end][16, 14:18]; digits = 3)
```

- `solve(prob)` with no algorithm also takes `ExplicitMap()`.
- The solution reads as the solution of a rate system: `sol[Ne]`, `field_series(sol, Ne)`.

## Rates and maps together

One system holds rate equations or maps, not both. A system with both is refused:

```@example fmaps
@variables q(..)
Q = q(t, x, y)
@named mix = PDESystem([Shift(t, 1)(Ne) ~ avg, D(Q) ~ laplacian(Q)],
    [N(0, x, y) ~ 0.0, q(0, x, y) ~ 0.0], dom, [t, x, y], [Ne, Q], [dx, dy])
try
    discretize(mix, LatticeDiscretization(Grid((32, 32))))
catch err
    showerror(stdout, err)
end
```

Discretize the two parts as two systems. In a Potts model, a map steps once per MCS; see
[Equations](@ref manual-equations).
