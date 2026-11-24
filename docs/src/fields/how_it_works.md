# [How it works](@id fields-how)

This page explains what `discretize` and the field algorithms do with a `PDESystem`. You do
not need it to use LatticePDE. Read it to predict a substep count, the order of groups, or
how a mask or a periodic field is read.

## The pipeline

`discretize(pdesys, LatticeDiscretization(grid))` runs these stages:

1. **Check.** [`check_vocabulary`](@ref) refuses spellings that ModelingToolkit accepts but
   that mean something else on a lattice, and names the route.
2. **Conditions.** [`parse_bcs`](@ref) reads the face conditions, the periodic pairs and the
   masks of each field.
3. **Classify.** [`linearity`](@ref) sorts each rate term: linear in its field, a diffusion
   operator, or a term that the implicit operator cannot hold.
4. **Lower.** [`symbolic_discretize`](@ref) lowers every equation to a LatticeFields
   program: one kernel per rate, map, aux field and mask, plus the face rules. The result
   is a [`CompiledField`](@ref).
5. **Compile.** LatticeFields fuses the kernels into launches and compiles them with
   KernelAbstractions for the backend, on the host or a GPU. It fuses a kernel into the
   current launch whenever that is legal. On a GPU, a launch also stays within the
   backend's kernel-argument budget. `field_report` lists each fusion and split with its
   reason. `LatticeDiscretization(…; fuse = false)` runs one launch per kernel, with the
   same results. Use it where the fused launches are slower on your hardware.
6. **Problem.** `discretize` wraps the program in an `ODEProblem` of the rates or a
   `DiscreteProblem` of the maps. Its `p` holds the parameters, the tables, the inputs and
   the step index of the clock.

A field algorithm steps the problem with the compiled kernels. An OrdinaryDiffEq solver
calls a compiled right side instead, which is built at its first call.

## The stability bound and the substep count

[`ExplicitEuler`](@ref) splits each window `dt` into `n` substeps of `dt / n`. The count
comes from the stability bound `ρ` of the system at the current parameters:

```math
n = \left\lceil \frac{dt \, \rho(p)}{1.8} \right\rceil
```

- `ρ` bounds the largest rate of change per unit value over all sites. It covers the
  diffusion operators, the local terms, the face conditions and the reads of a pair table.
  [`stability_bound`](@ref) returns it as a function of the parameters.
- The count is computed again when a parameter changes (`remake`, `integ.ps[k] = v`).
- A coefficient that reads the time is bounded over each window's time span.
- These terms are ones the bound cannot see, and they make the automatic count refuse the
  problem:
  - a nonlinear rate over a field with no declared `bounds`;
  - a velocity that reads the field it moves (Burgers);
  - a coefficient with more than 6 kind sets and comparisons, or with more than 4096
    evaluations (the evaluation cap);
  - a parameter without a value;
  - coupled rows that are not diagonally dominant, whose spectrum may be complex.
- `substeps = n` is a minimum. The count is the larger of `n` and the bound over the terms
  that the bound sees. When the bound sees no term, `n` is used.

Diffusion with `Dc = 1` and a decay `k = 0.1` on a lattice of spacing 1 has `ρ = 8.1`, so a
window `dt = 1` takes 5 substeps. A larger `substeps` is used as given, and a smaller one
is raised to 5:

```jldoctest fhow
julia> using ModelingToolkitBase, LatticePDE

julia> using ModelingToolkitBase: t_nounits as t, D_nounits as D

julia> @parameters x y Dc = 1.0 k = 0.1;

julia> @variables c(..);

julia> dom = lattice_domain(t, (x, y), (32, 32); tspan = (0.0, 1.0));

julia> @named heat = PDESystem(D(c(t, x, y)) ~ Dc * laplacian(c(t, x, y)) - k * c(t, x, y),
           [c(0, x, y) ~ 1.0], dom, [t, x, y], [c(t, x, y)], [Dc, k]);

julia> prob = discretize(heat, LatticeDiscretization(Grid((32, 32))));

julia> [only(substep_counts(solve(prob, ExplicitEuler(; substeps = n); dt = 1.0)))
        for n in (nothing, 8, 2)]
3-element Vector{Int64}:
 5
 8
 5
```

An implicit algorithm takes one substep per window by default. It raises the count only
where its operator needs it. A positive local derivative `g` that the operator holds takes
`n ≥ ⌈2γ dt g⌉`, with γ = 1 for `BackwardEuler` and `BDF2` and γ = 1/2 for
`CrankNicolson`. Here too `substeps = n` is a minimum.

[`substep_counts`](@ref) returns the count of each group, and [`field_report`](@ref) prints
the bound and its cause. [Solvers](@ref fields-solvers) gives the other implicit rules: the
convergence rule of the Newton correction, and the least count of 2 for `CrankNicolson` on
data that can jump.

## Groups and their order

- With one algorithm, every field is in one group.
- [`FieldGroups`](@ref) gives fields their own algorithms. Fields with equal algorithms form
  one group.
- Groups run in state order, the order of their first field, in each window.
- A group reads the fields of other groups as they are when it runs. A group stepped earlier
  in the window is read as stepped.
- Steady rows (`0 ~ rhs`) form a group of their own, stepped by [`QuasiSteady`](@ref), and
  solved first in each window.
- Groups that read one another in a loop hold each other's values over the window. Such a
  loop is refused when `dt` times the coupling between its groups is larger than 1; the
  error names the fields and the routes.
- One system holds rates or maps, never both.

## [Masks](@id fields-how-masks)

A mask holds a field at a value where a condition is true: `c ~ masked(condition, v)`.

The condition takes one of these forms:

| Condition | Example | When it changes |
|---|---|---|
| a `Bool` input | `masked(wall(t, x, y), 0.0)` | when the input is written (`integ.ps[wall] = W`, or an input that is a function of `t`) |
| a comparison of a field | `masked(c >= 0.8, 0.8)` | at each window, from the field's values |
| a comparison of the time | `masked(t >= t_on, 0.0)` | when the comparison changes sign |
| a kind set | `masked(ismember(k(t, x, y), (1, 2)), 0.0)` | when the input `k` is written |

Each solver holds the mask in its own way:

- **Explicit algorithms** evaluate the condition once at the start of each window, then
  write `v` at the masked sites after every substep.
- **Implicit algorithms** replace the row of each masked site in the operator by the value
  `v`. The masked site is a fixed value of the linear solve.
- **OrdinaryDiffEq solvers** set the rate of a masked site to 0 and run the masks again
  after each accepted step. A comparison of the time with parameters and numbers is an
  event that the solver locates. Any other change of the mask needs `dtmax` or `tstops`.

## [Periodicity per field](@id fields-how-periodicity)

A periodic pair `c(t, x, 0) ~ c(t, x, L)` makes `c` wrap on that axis. Other fields stay
closed there. Reads follow these rules:

1. A read of a field follows that field's own conditions, in every equation. With `c`
   periodic on `y` and `d` closed, `laplacian(c)` in the rate of `d` wraps, and
   `laplacian(d)` in the rate of `c` takes the faces of `d`, as in MethodOfLines.
2. An aux field `K ~ expr` wraps where every field it reads wraps. A neighbor read of an
   aux field that reads fields of both kinds on that axis is refused. A read at its own
   site is accepted.
3. An input, the `domain` mask, and an aux field that reads no field wrap only where every
   field wraps. A neighbor read of such a value by a field that wraps where another field
   is closed is refused. A `domain` is refused outright when the fields differ in
   periodicity on an axis, because each field reads the mask at its neighbors.
4. These are refused: a face condition and a periodic pair of one field on one axis, a
   pair that joins two fields, and a pair on an axis the lattice lacks.

The refusals name the field, the axis and each rule that applies.

## [GPUs](@id fields-how-gpus)

The kernels are KernelAbstractions kernels, so one system runs on the host or a GPU:

1. Load the backend package, for example `using AMDGPU`.
2. Give its backend to the discretization.
3. Solve as usual. `sol[c]` returns host arrays.

```julia
using ModelingToolkitBase, LatticePDE, AMDGPU
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 1.0 k = 0.1
@variables c(..)
C = c(t, x, y)
dom = lattice_domain(t, (x, y), (256, 256); tspan = (0.0, 20.0))
ic = [c(0, x, y) ~ exp(-((x - 128)^2 + (y - 128)^2) / 20)]
@named spot = PDESystem(D(C) ~ Dc * laplacian(C) - k * C, ic, dom, [t, x, y], [C],
    [Dc, k])
gprob = discretize(spot, LatticeDiscretization(Grid((256, 256)); backend = ROCBackend()))
gsol = solve(gprob, ExplicitEuler(); dt = 1.0, saveat = 5.0)
eltype(gsol[c][end]), sum(gsol[c][end])
# (Float32, 8.332732f0)
```

Recorded on an AMD Ryzen AI Max+ 395 (Radeon 8060S, ROCm), Julia 1.13.4, 2026-11-21. The
same problem with `T = Float32` on the host gives the same values to the last bit.

- The state type on a GPU is `Float32` by default.
- ROCm is tested; Metal is supported but not tested here. Another KernelAbstractions backend
  needs a method of `LatticeFields.Exec.kernel_argument_bytes` (its kernel-argument budget
  in bytes) before a field program can be planned for it.
- A GPU with `Float64` (ROCm) takes `compute_type = Float64` on a `Float32` problem.
- Apple GPUs (Metal) have no `Float64`: give `T = Float32` or `Float16`, and leave
  `compute_type`, `solver_type` and `lattice_storage` at 32 bits or less.
- `sparse = true` and `jac = true` work on the host only. On a GPU, an OrdinaryDiffEq solver
  takes the matrix-free Jacobian-vector product ([SciML interop](@ref fields-sciml)).
