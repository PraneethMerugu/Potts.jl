# [Solvers](@id fields-solvers)

A field algorithm advances a lattice problem over windows. The window is the `dt` of
`solve`. This page compares the algorithms, shows how to choose one per field, and gives
the rules for their substep counts and Newton iterations.

## Compare the algorithms

A stiff field: fast diffusion (`Dc = 50`) with a source in the middle of the lattice.

```@example fsolve
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
algs = (ExplicitEuler(), BackwardEuler(), CrankNicolson(), BDF2(), QuasiSteady())
map(algs) do alg
    sol = solve(prob, alg; dt = 0.5, save_everystep = false)
    (nameof(typeof(alg)), substep_counts(sol)[1], round(maximum(sol[c][end]); digits = 4))
end
```

`ExplicitEuler` takes 112 substeps per window for stability. The implicit steppers take
one. `QuasiSteady` gives the steady state, which the stepped fields approach.

| Algorithm | Order in time | Cost per substep | Use it for |
|---|---|---|---|
| `ExplicitEuler()` | 1 | one rate evaluation | a field with a small automatic count |
| `BackwardEuler()` | 1 | one linear solve | a stiff field (fast diffusion or decay) |
| `CrankNicolson()` | 2 | one linear solve | a stiff field with smooth data |
| `BDF2()` | 2 | one linear solve | a stiff field, without Crank–Nicolson's ringing |
| `QuasiSteady()` | none | one solve per window | a field faster than its inputs |
| `ExplicitMap()` | none | one map per window | a [map](@ref fields-maps) |

`BackwardEuler` pays a linear solve per substep. It is the faster choice when the explicit
count is large (fast diffusion, a stiff decay). For a field whose explicit count is a few
substeps, `ExplicitEuler` is cheaper.

## Give each field its own solver

`FieldGroups` gives a field its solver, and `default` solves the others:

```@example fsolve
@variables v(..)
V = v(t, x, y)
@named two = PDESystem(
    [D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y),
        D(V) ~ 0.1 * laplacian(V) + 0.5 * C - 0.2 * V],
    [c(0, x, y) ~ 0.0, v(0, x, y) ~ 0.0], dom, [t, x, y], [C, V, src(t, x, y)], [Dc, k, s])
tprob = discretize(two, LatticeDiscretization(Grid((64, 64))); inputs = [src => source])
tsol = solve(tprob, FieldGroups(c => BackwardEuler(); default = ExplicitEuler());
    dt = 0.5, save_everystep = false)
substep_counts(tsol)
```

`substep_counts` gives one count per group, in group order.
[Groups and loops](@ref fields-solvers-groups) gives the rules between groups.

## Linear solvers

The implicit algorithms take a linear solver as `linsolve`:

- `LatticePCG(; precs = LatticeMultigrid(), maxiters, reltol)`: conjugate gradients, the
  default.
- `LatticeMultigrid(; cycle = (2, 2), cycles, reltol, maxiters)`: multigrid cycles alone.
- `LatticeGMRES(; gmres_restart, maxiters, reltol, precs = LatticeBlockSolve())`: restarted
  GMRES, for the coupled steady solve of `QuasiSteady` only.

They are not field algorithms: `FieldGroups` refuses them and names the `linsolve` route.

```@example fsolve
sol = solve(prob, BackwardEuler(; linsolve = LatticePCG(; reltol = 1e-8)); dt = 0.5,
    save_everystep = false)
round(maximum(sol[c][end]); digits = 4)
```

`LatticeGMRES` is not a `linsolve` of `BackwardEuler`, `CrankNicolson` or `BDF2`. It was
slower in every case measured, so they refuse it.

## Backward Euler

`BackwardEuler()` solves `(u − uⁿ)/h = rhs(u)` in each substep, at the substep's end time.
An operator that reads the time is built at that end time. A stiff field therefore needs
no small substeps: the count is 1 unless a rule below raises it.

These terms are part of its linear solve, so one Newton iteration is exact:

- diffusion, linear decay, and kind-dependent diffusion multipliers;
- masks and face conditions, except a Robin face whose diagonal is negative
  (`α c + β ∂c/∂n = g` with `|β| > α/2` and `β` of the opposite sign).

These terms need more care:

- A local nonlinear term of the field itself (logistic growth `r c (1 − c)`, uptake
  `−V c/(K + c)`) enters the solve through its derivative at the current iterate. One
  Newton iteration keeps the method's order.
- A switch `−a max(c − c_T, 0)` takes two Newton iterations by default. The second is a
  flip pass that takes the switch state at the first one's result. It is not a
  convergence test.
- Other terms are corrected by more Newton iterations: advection, fields of one group that
  read one another in a loop, a negative Robin diagonal, and a second face coefficient next
  to a kind-dependent multiplier (`dk * laplacian(c) + DivKGrad(K, c)`; the term with the
  larger bound is in the solve).
- A second diffusion term that is at most half the one in the solve, face by face, needs no
  extra substeps, only a few more Newton iterations. The multiplier in the solve must be
  positive everywhere.

The substep count of an implicit algorithm is the largest of:

- the growth rule: `⌈2γ dt g⌉` for a positive local derivative `g` that the operator holds
  (γ = 1 for `BackwardEuler` and `BDF2`, 1/2 for `CrankNicolson`);
- the convergence rule: the count that keeps the Newton correction of the terms out of the
  operator converging, for the sum of their bounds. For advection with a constant velocity
  this is `substeps ≥ 2 · dt · Σ_a 2|u_a|/h_a`;
- the least count: 1, or 2 for `CrankNicolson` on data that can jump;
- `substeps = n`, which is a minimum.

When a rule raises the `substeps = n` you gave, a warning names the rule and the terms.
`nlsolve = nothing` (the default) chooses the Newton iteration count that the convergence
bound needs.

### Newton iterations

Each substep checks the Newton correction `δ_k = u_{k+1} − u_k` in the working float type
`T`. There are two modes:

- **Automatic** (`nlsolve = nothing`): the algorithm picks the iteration count from the
  contraction bound and stops on its own rule. A step whose iterations all run without
  meeting the rule is still accepted (`ReturnCode.Success`). It is counted in
  `stats.newton_budget` and warned once, with the routes `nlsolve = LatticeNewton(; κ,
  max_iter)` or more substeps.
- **`LatticeNewton(; κ = 1 // 100, max_iter = 10, check_div = true)`**: OrdinaryDiffEq's
  `NLNewton` criterion, over all the unknowns of the group, with the `abstol` and `reltol`
  of `solve`.

Under both modes, a run stops iterating once the group converges or fails.

<details>
<summary>The stopping rules</summary>

**Automatic mode.** The rule is an infinity-norm test, not `NLNewton`'s criterion:

```math
\|\delta_k\|_\infty \le 10^{-3} \|u_k - u^n\|_\infty + 10\,\mathrm{eps}(T) \|u_k\|_\infty
```

- `QuasiSteady` has no step increment and uses `10⁻³ ‖u_k‖∞` as the first term.
- Float16 storage adds the update's rounding floor.
- On a switch group, the second iteration is a flip pass with no check.
- `abstol` or `reltol` given to `solve` or `init` when no group uses `LatticeNewton` is an
  `ArgumentError`, because automatic mode ignores them.

**`LatticeNewton` mode.**

- At iteration `k`, `ndz` is the RMS norm of `δ_k / (abstol + max(|uⁿ|, |u_k|) reltol)`,
  with the iterate `u_k` before the update.
- `abstol` and `reltol` come from `solve`, with SciML's defaults `1e-6` and `1e-3`. On
  mixed `FieldGroups`, only the `LatticeNewton` groups read them.
- These defaults are looser than the automatic test when steps are small. Give a smaller
  `κ` or a tighter `reltol` for tight accuracy.
- Iteration 1 converges when `ndz < 1e-5`, also when `max_iter = 1`.
- After iteration 1, `θ = max(0.3 θ_prev, ndz / ndz_prev)`, and the test is
  `θ / (1 − θ) · ndz < κ`. `θ` is carried across steps and reset by `reinit!` and by a
  write of a parameter, table or state.
- Near the precision limit (`|θ − 1| ≤ 100 sqrt(eps(T))`), `ndz ≤ 1` converges and keeps
  the update. `ndz > 1` stops the run when `check_div = true`.
- With `check_div = true`, a divergence (`θ > 2`) or a budget hit ends the run with
  `ReturnCode.ConvergenceFailure`, with more substeps as the route.
- With `check_div = false`, a budget hit is accepted (`ReturnCode.Success`), counted once
  per group and substep in `stats.newton_budget`, and warned.
  `LatticeNewton(; max_iter = 1, check_div = false)` is one unchecked sweep.

</details>

## Crank–Nicolson and BDF2

`CrankNicolson()` and `BDF2()` are the second-order implicit algorithms. They take the
keywords of `BackwardEuler`, with the same meanings, and each substep costs one linear
solve. Both start with Backward Euler steps.

`CrankNicolson` solves `(u − uⁿ)/h = (rhs(uⁿ) + rhs(u))/2`, with `rhs(uⁿ)` at the substep's
start time and `rhs(u)` at its end time.

- Data that jump ring under Crank–Nicolson, so the first substep after a start is damped:
  two Backward Euler steps of `h/2`.
- A start is the first window and every write (a state, parameter or table write,
  `reinit!`).
- A field whose data can jump every window damps the first substep of every window. Such a
  field reads an input, another field group or a moving mask.
- Such a field takes at least 2 substeps per window: the damped one, then Crank–Nicolson
  substeps. The error of a window falls as `1/n²` with the count `n`.
- With `substeps = 1` it is Backward Euler in two halves: first order, at twice the cost.

`BDF2` solves `(u − (4uⁿ − uⁿ⁻¹)/3)/(2h/3) = rhs(u)` at the substep's end time.

- It keeps the field one substep back itself. That field is not part of the state, so it is
  not saved and not in a checkpoint.
- The first substep after a start is one Backward Euler substep.
- A start is the first window, every write, a restored checkpoint, and every change of the
  substep count (the formula needs one step length).

Neither keeps nonnegative values nonnegative: a stiff decay overshoots below 0. Give
`lower_bound = 0.0` for a concentration, or use `BackwardEuler`, which needs no clip on a
consumption field. A clip changes the equation solved slightly.

## Steady fields

`QuasiSteady()` solves a field's steady state `0 = rhs` in each window, at that window's
inputs. Use it for a field that relaxes much faster than its inputs change. Each window
starts from the last solution.

Write such a field's equation as a steady row, `0 ~ Dc * laplacian(c) - kd * c + s`:

- The row is solved for a field it reads that has no other equation, the one under its
  operator first.
- Its sign does not matter: `0 ~ kd * c - Dc * laplacian(c) - s` is the same row.
- A local row such as `0 ~ -2c + 0.5e`, with `D(e) ~ …`, is `c`'s.
- A steady row takes `QuasiSteady` by default; another algorithm for it is an error.
- Steady fields are solved first in each window, so the other fields read their values of
  that window.
- `QuasiSteady` also solves a rate row `D(c) ~ rhs` as `0 = rhs`.

`QuasiSteady` takes `nlsolve`, `linsolve` and `solver_type` with the meanings above. It has
no `substeps` and no `lower_bound`.

- A linear field takes one linear solve per window. A Robin face of either sign is in the
  operator, so a linear field with one is still one solve.
- A nonlinear or switched field takes up to 8 Newton iterations in automatic mode, or up to
  `max_iter` with `LatticeNewton`.
- A term out of the operator (advection) sets the automatic count from its bound against
  the decay: from 8 to at most 40 iterations. Give `nlsolve = LatticeNewton(; κ, max_iter)`
  if the warning says the budget is hit.

### Coupled steady fields

Some steady rows are solved together in one Newton iteration, with every cross term in the
operator:

- steady fields of one `QuasiSteady` that read one another (`0 ~ laplacian(a) - a + 0.5b`
  and `0 ~ laplacian(b) - b - 0.5a`, or a cross diffusion `laplacian(b)` in `a`'s row);
- a row with a term the operator does not see (`c²` in `0 ~ q - c^2`).

The solve is a restarted GMRES, `LatticeGMRES()`. A `LatticePCG` or `LatticeMultigrid`
given as `linsolve` is its preconditioner. There is no gain limit inside one group.

On a GPU this solve waits for each dot product of its GMRES: about 100 to 250 waits per
window for a strong pair. Every other field algorithm waits for none, so a system without
such coupling keeps a GPU step free of waits.

A coupled steady system whose slowest mode grows or is neutral has no stable steady state.
It is refused, naming the eigenvalue (with nonnegative real part), with the route
`BackwardEuler`.

- With constant coefficients the eigenvalues are exact, mode by mode.
- With a coefficient that varies by site, a short Arnoldi estimate through the coupled
  operator finds a growing mode.
- A linear group is checked at the start and at each parameter write.
- A nonlinear group is checked at the steady state of its first solve after either, or
  after the steady start. The run stops with the refusal right after that solve.

### What a steady field needs

The steady state must exist and be unique. `QuasiSteady` refuses three kinds of field, at
the start and at every parameter write:

- a growth that the operator sees (`+ g c`): its steady state is unstable or not unique.
  Step it with `BackwardEuler`.
- a Robin face `α c + β ∂c/∂n = g` with α and β of opposite signs that feeds the field more
  than its diffusion and decay remove (the steady operator is indefinite). Step it with
  `BackwardEuler`, or give the face a smaller |β|.
- a field with no decay and no fixed value (no Dirichlet or Robin face, no mask): `0 = rhs`
  then has no solution or many. Add a decay or a fixed value.

A region with neither a decay nor a fixed value can also appear only through the data: a
decay that an input switches off in a pocket. The solve finds it at run time. The run stops
with `ReturnCode.ConvergenceFailure`, and the warning names the field, the window and the
route.

### A steady field in a loop of groups

A steady field whose group reads another group that reads it back answers its inputs at
once, with the gain of its steady solve. The lag of one window between the groups can grow.

- The gain is at most `1/k` for a decay `k`, and less with a Dirichlet or Robin face. A mask
  does not count, since its data can move.
- A loop is accepted when `dt · Σ k_in · gain · k_out ≤ 1`. `k_in` are the coefficients by
  which the other group reads the steady field, and `k_out` those by which the steady field
  reads it back.
- Several steady groups in one loop compose their gains, as long as that composition is
  bounded.
- Past the limit, or with no bound for the gain (no decay and no face), the loop is
  refused. The routes: one `BackwardEuler` for the fields, `BackwardEuler` for the steady
  field, or a shorter window.
- A loop of steady groups only, or a steady group that reads another steady group of its
  loop, is refused with the route of one `QuasiSteady` for those fields.
- A steady field that other groups only read is accepted.

An accepted loop is first order in the window: the steady field reads the other field's
values at the start of the window. The limit is a stability rule, not an accuracy rule. An
excitatory loop can lag far behind its true growth even below it, so give it a shorter
window or step its fields in one group.

## A steady start

Every field algorithm takes `init = :steady`: before the first window, and at `reinit!`,
the group's steady state is solved once, as `QuasiSteady` would. The algorithm then steps
from it: `BackwardEuler(; init = :steady)`.

- The steady solve uses the algorithm's `linsolve`, by default conjugate gradients to a
  relative 1e-6.
- The steady state must exist and be unique, as for `QuasiSteady`. A growth is refused,
  with the route of leaving `init` out.
- A steady start that fails stops the run before its first window.
- A state restored from a checkpoint is not solved again.

## [The stability bound](@id fields-solvers-bound)

`substeps = nothing` takes the smallest count `n` with `dt / n · ρ ≤ 1.8`. `ρ` bounds the
spectral radius of the rate: `D · Σ_d 4/h_d²` for diffusion, plus the size of the
coefficient of `c` in a linear reaction. The count is computed again when the parameters
change, and `substeps = n` is a minimum.

- A `Bool` input and indicators such as `ismember(kind, g)` are evaluated at 0 and 1.
- A rate gated by a condition that reads no field (`ifelse(t >= t₀, …, 0)`) is bounded
  branch by branch; the worst branch counts.
- A diffusion multiplier that varies by site through a kind table or a kind set
  (`dk * laplacian(c)` with `dk => δ[kind]`, `ismember(kind, g) * laplacian(c)`) is bounded
  by the largest multiplier times the largest diffusion coefficient.
- A reaction coefficient that reads a kind table (`- dk * c`) is bounded at every entry of
  the table, and the count follows the table's values.
- A coefficient that is not finite at an entry (`- c / tk` with a zero entry of `tk`) is
  refused, naming the entry, even with `substeps = n`. Make the entry finite and nonzero.
- A field that reads another one way (`u` reads `c`, `c` does not read `u`) is bounded.

The bound also covers these terms over intervals:

- a coefficient that reads the coordinates (`(1 + x) * laplacian(c)`,
  `DivKGrad(:harmonic)(1 + x, c)`, `- k * (1 + x) * c`), over the site centers. For a
  velocity, and for a face coefficient on an axis with a boundary value or flux, the
  interval reaches one half spacing past the faces.
- a coefficient that reads a field with declared bounds (`c(..) = 0.5 [bounds = (0, 1)]`).
  `DivKGrad(:harmonic)(c, c)` takes the largest `K` over `[0, 1]`, and a nonlinear reaction
  (`a * c * (1 - c)`) the largest `|∂f/∂c|` over it.
- a switch (`- a * max(c - c_T, 0)`): its derivative is `a` or 0.
- upwind advection: `Σ_d 2 max|v_d| / h_d`, the CFL limit. The velocity may read
  parameters, the coordinates (`[50 * (1 + x), 0.0]`) or other fields with declared bounds.
- a term that reads an aux field, through the aux field's definition (`K ~ k * c` makes
  `- K` a decay `k`).

Declared bounds hold only inside the declared interval:

- A field that starts outside it, or a constant face or masked value outside it, is an
  error.
- A field that leaves it during an `ExplicitEuler` run ends the run with
  `ReturnCode.Unstable` and a warning. The routes are `substeps = n` or wider `bounds`.
- An implicit run warns and goes on. The routes are `lower_bound = lo` or wider `bounds`.

### Terms the bound cannot see

These terms need `substeps = n`. Without it, the problem throws an error that names the
term:

- a reaction that is not linear in `c`, with no declared bounds;
- a coefficient that reads other state: a field with no declared bounds;
- a velocity that reads the field it moves (`Advect([c, 0], c)`, Burgers): its flux Jacobian
  has a central part, so no count follows from the velocity alone. An implicit algorithm
  also works;
- a coefficient whose interval holds negative and positive values: a diffusion whose sign
  the bound does not know;
- a coefficient whose interval is not finite (`c / (x - 0.5)`); the error names the
  interval;
- fields that read each other in a loop (`- Dx * laplacian(u)` in the rate of `c` and
  `Dx * laplacian(c)` in the rate of `u`) when their rows of the Jacobian are not diagonally
  dominant.

With `substeps = n` in these cases, the count is the larger of `n` and the bound of the
terms the bound sees (diffusion at least). The problem warns once, naming the terms it does
not cover.

## [Groups and loops](@id fields-solvers-groups)

- Fields with the same algorithm step together, substep by substep. A field reads the
  fields it depends on after their update. Fields that depend on each other read each
  other's values from the start of the substep.
- Fields with different algorithms step one group after another, each reading the others'
  arrays.
- A one-way chain (`u` reads `c`, `c` does not read `u`) is not limited. Each group is
  stable under its own count, and the split adds only a first-order error.

Groups that read one another in a loop (`c` reads `o` and `o` reads `c`) can grow without
bound at any substep count, because each holds the others' values over the window.

- For each group in a loop, take the largest sum, over its fields, of the largest
  coefficient magnitudes of the terms that read other groups of the loop. The window times
  that sum must be at most 1. Reads of groups outside the loop do not count.
- Past the limit, the problem is refused, naming the fields of the loop. The routes: give
  those fields one algorithm (with `substeps = n` when their coupled rates have no automatic
  count), or a smaller `dt`.
- A group with a term that the bound cannot see and that reads another field counts as
  reading every other group. A term that reads only its own field (`- 0.1 * c^2`) does not.

A diffusion coefficient must not be negative. That is anti-diffusion, an ill-posed problem
whose shortest wavelengths grow without bound under any step. The problem throws an error
at build. A parameter write that makes a coefficient negative (`setp`, `integ.ps[k] = v`,
`remake`) throws the error and changes nothing. So does a write past the loop limit.

## Counts and reports

- `substep_counts(integ)` gives the substep count of each group, in group order (the order
  of each group's first field). It follows the parameter writes.
- `substep_counts(prob)` gives the counts at the problem's parameters.
- `field_report(x)` prints why each group steps as it does. `x` is a problem, an integrator
  (a field algorithm's or OrdinaryDiffEq's) or a solution.
- `field_report(prob, alg)` prints the policy of a problem under the algorithm `alg`
  without binding anything.

The report has one block per group. A block gives the group's fields and algorithm, the
window and the substep count with its cause, the stability bound and the terms it cannot
see, and the number types. An implicit group also gives its `linsolve` with its multigrid
levels and the Newton count. An integrator also gives the run's counters. The report ends
with the coupling between groups.

The report changes nothing in the run. It may synchronize a device, so call it outside a
timed loop. [Getting started](@ref fields-getting-started) shows it.
