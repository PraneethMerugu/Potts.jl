# [Number types](@id fields-types)

Each role in a field problem has its own number type. This page shows how to set the state
type, the storage of one field, the type the kernels compute in, and how ForwardDiff's
dual numbers pass through.

| Role | Set by | Default |
|---|---|---|
| state | `LatticeDiscretization(grid; T)`: `Float16`, `Float32` or `Float64` | `Float64` on the host, `Float32` on a GPU |
| storage of one field | `@variables c(..) [lattice_storage = Float16]` (`Float16`, `Float32` or `Float64`) | the state type |
| computation | `compute_type` of a field algorithm (`Float32` or `Float64`) | the state type |
| implicit solve | `solver_type` of an implicit algorithm (`Float32` or `Float64`) | the state type |
| parameters | the values in `p`, or a dual number in `remake(prob; p)` | the state type |

The examples use this system:

```@example ftypes
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 50.0 k = 1.0 s = 1.0
@variables c(..) src(..)::Bool [input = true]
dom = lattice_domain(t, (x, y), (64, 64); tspan = (0.0, 2.0))
C = c(t, x, y)
@named spot = PDESystem(D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y),
    [c(0, x, y) ~ 0.0], dom, [t, x, y], [C, src(t, x, y)], [Dc, k, s])
source = falses(64, 64)
source[28:36, 28:36] .= true
nothing # hide
```

## Single precision

1. Give `T = Float32` to the discretization.
2. Solve as usual.

```@example ftypes
p32 = discretize(spot, LatticeDiscretization(Grid((64, 64)); T = Float32);
    inputs = [src => source])
s32 = solve(p32, ExplicitEuler(); dt = 0.5, save_everystep = false)
eltype(s32[c][end])
```

The save times stay `Float64`, whatever `T` is.

## A field in half precision

A field with `[lattice_storage = Float16]` keeps its array in Float16. Its kernels compute
in the algorithm's `compute_type` and round once at each store:

```@example ftypes
@variables h(..) [lattice_storage = Float16]
H = h(t, x, y)
@named half = PDESystem(D(H) ~ Dc * laplacian(H) - k * H + s * src(t, x, y),
    [h(0, x, y) ~ 0.0], dom, [t, x, y], [H, src(t, x, y)], [Dc, k, s])
p16 = discretize(half, LatticeDiscretization(Grid((64, 64)); T = Float32);
    inputs = [src => source])
s16 = solve(p16, ExplicitEuler(; compute_type = Float64); dt = 0.5,
    save_everystep = false)
eltype(s16[h][end])
```

[`field_report`](@ref) prints the storage and compute types of each group:

```@example ftypes
field_report(s16)
```

- Every field algorithm takes a Float16 field. An implicit algorithm solves in its
  `solver_type` and rounds each update to Float16.
- In a Potts model the same option goes on the field's declaration in `@fields`; see
  [Variables](@ref manual-variables).

## Derivatives

A dual number in a parameter makes the run compute in duals:

```@example ftypes
using ForwardDiff
prob = discretize(spot, LatticeDiscretization(Grid((64, 64))); inputs = [src => source])
total(kv) = sum(solve(remake(prob; p = [k => kv]), ExplicitEuler(); dt = 0.5,
    save_everystep = false)[c][end])
ForwardDiff.derivative(total, 1.0)
```

Central differences agree:

```@example ftypes
(total(1.0 + 1e-6) - total(1.0 - 1e-6)) / 2e-6
```

[Derivatives with ForwardDiff](@ref manual-derivatives) gives the rules for seeding and
reading duals.

## On a GPU

A GPU problem takes `T = Float32` by default. [GPUs](@ref fields-how-gpus) gives the
number types that each kind of GPU takes.
