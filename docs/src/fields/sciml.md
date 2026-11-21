# [SciML interop](@id fields-sciml)

`discretize` returns an ordinary SciML problem: an `ODEProblem` of the rates, or a
`DiscreteProblem` of the maps. This page shows how to solve it with OrdinaryDiffEq, change
it with `remake` and the integrator, and read the solution.

`Potts.fields(model)` returns the fields of a Potts model as a plain `PDESystem`, so every
step on this page applies to it as well.

The examples use a stiff system: fast diffusion from a source block.

```@example fsciml
using ModelingToolkitBase, LatticePDE
using ModelingToolkitBase: t_nounits as t, D_nounits as D

@parameters x y Dc = 50.0 k = 1.0 s = 1.0
@variables c(..) src(..)::Bool [input = true]
dom = lattice_domain(t, (x, y), (64, 64); tspan = (0.0, 2.0))
C = c(t, x, y)
@named stiff = PDESystem(D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y),
    [c(0, x, y) ~ 0.0], dom, [t, x, y], [C, src(t, x, y)], [Dc, k, s])
source = falses(64, 64)
source[28:36, 28:36] .= true
prob = discretize(stiff, LatticeDiscretization(Grid((64, 64))); inputs = [src => source])
typeof(prob).name.name
```

## Solve with OrdinaryDiffEq

An implicit OrdinaryDiffEq solver needs the Jacobian. `sparse = true` gives the problem the
sparse pattern of its Jacobian, read off the compiled program, and a coloring of it:

```@example fsciml
using OrdinaryDiffEqRosenbrock
sprob = discretize(stiff, LatticeDiscretization(Grid((64, 64))); inputs = [src => source],
    sparse = true)
rsol = solve(sprob, Rodas5P(); saveat = 1.0)
rsol.retcode, maximum(rsol[c][end])
```

- `jac = true` gives the problem the Jacobian itself (colored dual numbers).
- `sparse` and `jac` work on the host only.
- `field_jacobian_sparsity(prob)` returns the pattern.

The Jacobian-vector product `prob.f.jvp` is always set. A Krylov linear solver therefore
runs matrix-free, also on a GPU, and the lattice multigrid preconditions it:

```@example fsciml
using OrdinaryDiffEqBDF, LinearSolve
gmres = KrylovJL_GMRES(; precs = LatticeMultigrid(), gmres_restart = 10)
fsol = solve(prob, FBDF(; linsolve = gmres); saveat = 1.0)
fsol.retcode, maximum(fsol[c][end])
```

- With `LatticeMultigrid`, GMRES takes a few iterations per solve, so a small restart
  length is enough. LinearSolve currently allocates the GMRES workspace again at each new `W`
  (SciML/LinearSolve.jl#1378 fixes it).
- For a symmetric system, `linsolve = LatticePCG()` takes conjugate gradients with the
  same preconditioner.

## Change the problem

`discretize` takes SciML's keywords `u0`, `p` and `tspan`, with the rules of `remake`:

```@example fsciml
p2 = discretize(stiff, LatticeDiscretization(Grid((64, 64))); inputs = [src => source],
    p = [k => 2.0], tspan = (0.0, 1.0))
p2.tspan
```

`remake(prob; p = [k => 2.0])` does the same on a built problem. Any other keyword is an
error that names it.

## Change the integrator

1. Make an integrator with `init`.
2. Read a field with `integ[c]`. It returns a copy.
3. Assign a field with `integ[c] = values`.
4. Write a parameter, a table or an input with `integ.ps[k] = v`.

```@example fsciml
integ = init(prob, BackwardEuler(); dt = 0.1)
step!(integ)
integ.ps[k] = 3.0
integ[c] = zeros(64, 64)
step!(integ)
integ.t, maximum(integ[c])
```

- `integ[c]` is a copy on the problem's device. Writing into it, `integ[c][1, 1] = v`,
  changes nothing.
- A whole table takes `integ.ps[:δ] = values`, one entry `integ.ps[δ[2]] = v`, and an
  input `integ.ps[:kind] = K`.
- Each write runs the checks of `setp`, the substep count and the masks again.
- `integ[k]` of a parameter is an error that names `integ.ps`.
- The same writes work on an OrdinaryDiffEq integrator.

## Read the solution

Every solver returns SciML's `ODESolution`. A field algorithm interpolates linearly between
the saves.

```@example fsciml
bsol = solve(prob, BackwardEuler(); dt = 0.1, saveat = 1.0)
(last = maximum(bsol[c][end]), save2 = bsol[c, 2][32, 32], t15 = bsol(1.5; idxs = c)[32, 32])
```

- `sol[c]` (or `sol[:c]`) is one grid per save; `sol[c, i]` is the grid at save `i`.
- `sol(t; idxs = c)` is the grid at time `t`; `sol(t, x, y)` interpolates between sites.
- `sol[x]` holds the site centers.
- `sol.ps` holds the parameter values at the end of the run.
- `Array(sol)` and `sol.stats` work as on any `ODESolution`.

`field_series(sol, c)` is the time-first view, as in MethodOfLines. It reads the saves when
indexed:

```@example fsciml
series = field_series(bsol, c)
size(series), series[end, 32, 32] == bsol[c][end][32, 32]
```

On a large lattice, give an OrdinaryDiffEq solver `saveat` or `save_everystep = false`. By
default it saves every step with its dense output: about seven states per step for `FBDF`,
or 14 MiB per step at 512².

## Inputs that change in time

An input that changes in time takes a function of the time, `inputs = [q => t -> values]`:

- A field algorithm writes the input at the start and at the end of each window.
- An OrdinaryDiffEq solver evaluates it at every call of the right side, at each stage time.

A mask that reads such an input follows it too. This system has no mask: its source is an
input that a moving front switches on, one row of `x` sites at a time:

```@example fsciml
@parameters Dw = 0.5 kw = 0.1
@variables w(..) front(..) [input = true]
W, F = w(t, x, y), front(t, x, y)
wdom = lattice_domain(t, (x, y), (20, 10); spacing = 0.5, tspan = (0.0, 2.0))
@named pulse = PDESystem([D(W) ~ Dw * laplacian(W) - kw * W + F], [w(0, x, y) ~ 0.0],
    wdom, [t, x, y], [W, F], [Dw, kw])
# rows 1 to 10t (the x index) are on
lit(t) = [i <= 10t ? 1.0 : 0.0 for i in 1:20, j in 1:10]
pprob = discretize(pulse, LatticeDiscretization(Grid((20, 10))); inputs = [F => lit])
psol = solve(pprob, ExplicitEuler(); dt = 0.1, save_everystep = false)
round.(psol[W][end][:, 5]; digits = 2)
```

`field_report` gives the substep count of this system and its cause:

```@example fsciml
field_report(pprob, ExplicitEuler(); dt = 0.1)
```
