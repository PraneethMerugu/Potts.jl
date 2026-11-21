# [Solvers](@id fields-solvers)

A field algorithm advances a lattice problem over windows. This page compares the
algorithms, shows how to choose one per field, and gives the rules for their substep
counts and Newton iterations.

The window is the time an algorithm advances in one step: the `dt` of `solve` in a
standalone problem, and one MCS (Monte Carlo step) times `mcs_duration` in a Potts model.
The text below says *window* for both.

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
| `BDF2()` | 2 | one linear solve | a stiff field, without the ringing of Crank–Nicolson |
| `QuasiSteady()` | — | one solve per window | a field that relaxes much faster than its inputs change |
| `ExplicitMap()` | — | one application per window | a map `Shift(t, 1)(m) ~ rhs` (see [Maps](@ref fields-maps)) |

## Give each field its own solver

`FieldGroups` gives a field its solver; `default` solves the others:

```@example fsolve
@variables v(..)
V = v(t, x, y)
@named two = PDESystem(
    [D(C) ~ Dc * laplacian(C) - k * C + s * src(t, x, y), D(V) ~ 0.1 * laplacian(V) + 0.5 * C - 0.2 * V],
    [c(0, x, y) ~ 0.0, v(0, x, y) ~ 0.0], dom, [t, x, y], [C, V, src(t, x, y)], [Dc, k, s])
tprob = discretize(two, LatticeDiscretization(Grid((64, 64))); inputs = [src => source])
tsol = solve(tprob, FieldGroups(c => BackwardEuler(); default = ExplicitEuler());
    dt = 0.5, save_everystep = false)
substep_counts(tsol)
```

`substep_counts` gives one count per group, in group order. In a Potts model the same
problem is `field_solver = FieldGroups(…)`, or `solvers = [c => BackwardEuler()]` (see
[Equations and solvers](@ref manual-equations)).

## Linear solvers

The linear solvers `LatticePCG(; precs = LatticeMultigrid(), maxiters, reltol)`, `LatticeMultigrid(; cycle = (2, 2), cycles, reltol, maxiters)`
and `LatticeGMRES(; gmres_restart, maxiters, reltol, precs = LatticeBlockSolve())` are the `LatticeFields.Solvers` objects, the same in Potts and LatticePDE. They are the
`linsolve` linear solver of the implicit field solvers:
`field_solver = BackwardEuler(; linsolve = LatticePCG(; maxiters = 12))`. They are not field
solvers themselves: `field_solver`, `solvers` and `FieldGroups` refuse them and give that
route.

```@example fsolve
sol = solve(prob, BackwardEuler(; linsolve = LatticePCG(; reltol = 1e-8)); dt = 0.5,
    save_everystep = false)
round(maximum(sol[c][end]); digits = 4)
```

## Implicit steppers

`BackwardEuler()` steps a field implicitly: each substep solves `(u − uⁿ)/h = rhs(u)` at the
substep's end time (an operator that reads the time is built at each substep's end time), so
a stiff field (fast diffusion, fast decay) needs no small substeps. Its substep count is 1
unless a growth term in the rate (`+ g c`) needs more. Diffusion, linear decay, kind-dependent
diffusion multipliers, masks and face conditions are part of its linear solve, so one Newton
iteration is exact. A Robin face whose diagonal is negative (`α c + β ∂c/∂n = g` with
`|β| > α/2` and `β` of the opposite sign) is the exception: that part is corrected by Newton
iterations. A local nonlinear term of the field itself (logistic growth `r c (1 − c)`, uptake
`−V c/(K + c)`) enters the solve through its derivative at the current iterate, so one Newton
iteration keeps the method's order. A switch `−a max(c − c_T, 0)` takes two Newton iterations
by default: the second is a flip pass that takes the switch state at the first one's result,
not a convergence test. Other terms, such as advection, fields of one group that read one
another in a loop, or a second face coefficient next to a kind-dependent multiplier
(`dk * laplacian(c) + DivKGrad(K, c)` with `dk => δ[kind]`: the term with the larger bound is in the
solve), are
corrected by more Newton iterations. Their substep count keeps the correction converging (for
the sum of their bounds; advection with a constant velocity: `substeps ≥ 2 · dt ·
Σ_a 2|u_a|/h_a`), and `nlsolve = nothing` chooses the automatic Newton iteration count that this bound needs. A second
diffusion term that is at most half the one in the solve, face by face (with a multiplier in
the solve that is positive everywhere), needs no extra substeps at all, only a few more
Newton iterations. When these rules raise a `substeps = n` you gave, a warning says which
rule and which terms. `LatticeGMRES` is not a time stepper's `linsolve` (it is the coupled steady
solve's, below): on BackwardEuler, CrankNicolson and BDF2 it was slower in every case measured,
so they refuse it. Each substep checks the Newton correction `δ_k = u_{k+1} − u_k` in the working float type `T`.
There are two distinct Newton modes:

- **Automatic mode (`nlsolve = nothing`)**: the solver picks the iteration count from the
  contraction bound of any out-of-operator terms and runs its own infinity-norm stopping rule
  (not `NLNewton`'s criterion):
  `‖δ_k‖∞ ≤ 1e-3 ‖u_k − uⁿ‖∞ + 10 eps(T) ‖u_k‖∞` (for `QuasiSteady`, which has no `uⁿ` step
  increment, `‖δ_k‖∞ ≤ 1e-3 ‖u_k‖∞ + 10 eps(T) ‖u_k‖∞`; Float16 storage adds the update's
  rounding floor; on an exact switch group, the second iteration is a flip pass with no check).
  If all iterations run without meeting the rule, the step is still accepted (`ReturnCode.Success`),
  counted in `integ.stats.newton_budget`, and warned once with the route
  (`nlsolve = LatticeNewton(; κ, max_iter)` or more substeps). Passing `abstol` or `reltol`
  to `solve`/`init` when no group uses `LatticeNewton` is refused with an `ArgumentError`,
  because automatic mode ignores them.
- **`LatticeNewton` mode (`nlsolve = LatticeNewton(; κ = 1 // 100, max_iter = 10, check_div = true)`)**:
  uses OrdinaryDiffEq's `NLNewton` criterion over all active unknowns in the group (one global
  norm for both row-by-row and coupled groups). At iteration `k`, `ndz` is the RMS norm of
  `δ_k / (abstol + max(|uⁿ|, |u_k|) * reltol)` using the pre-update iterate `u_k` and the
  `abstol` and `reltol` keywords from `solve` (SciML defaults `1e-6` and `1e-3` when unset,
  forwarded through both `LatticePDE` and `Potts` front ends; on mixed `FieldGroups`, only
  `LatticeNewton` groups read them). Note that `NLNewton`'s defaults (`κ = 1 // 100`,
  `abstol = 1e-6`, `reltol = 1e-3`) are looser than the automatic `1e-3 ‖u_k − uⁿ‖∞` test
  when steps are small; pass a smaller `κ` or tighter `reltol` when tight accuracy is needed.
  On iteration 1, convergence requires `ndz < 1e-5` (checked even when `max_iter = 1`).
  After iteration 1, `θ = prev_θ = max(0.3 * prev_θ, ndz / ndzprev)` (carried across steps
  and reset on `reinit!` or parameter, table, or state writes) and `η = θ / (1 - θ)` test
  `η * ndz < κ`. Near the floating-point precision limit (`|θ - 1| ≤ 100 * sqrt(eps(T))`,
  type-faithful in `T`), `ndz ≤ 1` converges (keeping the already-applied update `δ_k`
  without overwriting `prev_θ`), while `ndz > 1` aborts when `check_div = true`. When
  `check_div = true` (default), diverging rates (`θ > 2`) or budget hits end the run with
  `ReturnCode.ConvergenceFailure` (with more substeps as the route); when `check_div = false`,
  divergence-growth checks are disabled and a budget hit is accepted as converged
  (`ReturnCode.Success`, counted once per group per substep in `stats.newton_budget` and
  warned, unlike automatic mode's per-row count; pass `LatticeNewton(; max_iter = 1, check_div = false)`
  for a single unchecked sweep).

Under both modes, a CPU run stops early once the group converges (or fails); a GPU closes its
convergence gate once the group converges (or fails). On
a hexagonal lattice every implicit solver runs on the six-neighbor Laplacian. A face condition
there applies along each link that leaves the box: a diagonal link takes the condition of
axis 1's face when it leaves along axis 1, else axis 2's. Explicit and implicit steps use the
same rule.

`CrankNicolson()` and `BDF2()` are the second-order implicit solvers. They take the keywords
of `BackwardEuler`, with the same meanings, and their substeps cost one linear solve each,
as Backward Euler's do. Both start with Backward Euler steps:

- `CrankNicolson` solves `(u − uⁿ)/h = (rhs(uⁿ) + rhs(u))/2`, with `rhs(uⁿ)` at the substep's
  start time and `rhs(u)` at its end time. Data that jump ring under Crank–Nicolson, so its
  first substep after a start is damped: two Backward Euler steps of `h/2`. A start is the
  first window and every write (a state, parameter or table write, `reinit!`). A field whose data
  can jump every window damps the first substep of every window. Such a field reads an input (`kind`,
  a binding), another field group or `mcs`, or has a mask that moves. Such a field takes at
  least 2 substeps per window by default: the damped one, then Crank–Nicolson substeps, so the
  error of a window falls as `1/n²` with the count `n`. With `substeps = 1` it is Backward Euler
  in two halves: first order, at twice Backward Euler's cost.
- `BDF2` solves `(u − (4uⁿ − uⁿ⁻¹)/3)/(2h/3) = rhs(u)` at the substep's end time. It needs
  the field one substep back, which it keeps itself: it is not part of the state, so it is not
  saved and not in a checkpoint. The first substep after a start is one Backward Euler
  substep. A start is the first window, every write, a restored checkpoint, and every change of
  the substep count (the formula needs one step length). A move of the cells is no start.

Neither keeps nonnegative values nonnegative: a stiff decay overshoots below 0. Give
`lower_bound = 0.0` for a concentration, or use `BackwardEuler`, which needs no clip on a
consumption field. A clip changes the equation solved slightly.

`QuasiSteady()` solves a field's steady state `0 = rhs` in each window, at the cells of that
window: a field that relaxes much faster than the cells move. Each window starts from the last
solution. Write such a field's equation as a steady row, `0 ~ Dc * laplacian(c) - kd * c + s`: it is
solved for a field it reads that has no other equation, the one under its operator first,
with `QuasiSteady` by default (another solver for it is an error). Its sign does not matter:
`0 ~ kd * c - Dc * laplacian(c) - s` is the same row. A local row such as `0 ~ -2c + 0.5e`, with
`D(e) ~ …`, is `c`'s. Steady fields are solved first in each window, so the other fields read their
values of that window. `QuasiSteady` also solves a rate row `D(c) ~ rhs` as `0 = rhs`. It takes `nlsolve`, `linsolve` and `solver_type` with the meanings above, and has no
`substeps` and no `lower_bound`. A linear field takes one linear solve per window. A nonlinear or switched field takes up to 8 Newton iterations in automatic mode (`‖δ_k‖∞ ≤ 1e-3 ‖u_k‖∞ + 10 eps(T) ‖u_k‖∞`), or up to
`max_iter` with `nlsolve = LatticeNewton(; κ, max_iter, check_div)` using the rate-scaled
`NLNewton` criterion above (with one global RMS norm across all unknowns in the group). When a term stays out of the operator (advection), the automatic count comes from
the bound on that term against the decay, from 8 to at most 40 iterations; give
`nlsolve = LatticeNewton(; κ, max_iter)` if the warning says the budget is hit. Steady
fields of one `QuasiSteady` that read one another (`0 ~ laplacian(a) - a + 0.5b` and
`0 ~ laplacian(b) - b - 0.5a`, a cross diffusion `laplacian(b)` in `a`'s row), and a row with a term the
operator does not see (`c²` in `0 ~ q - c^2`), are solved together: one Newton iteration
solves all their rows with every cross term in the operator, by a restarted GMRES
(`LatticeGMRES()`; a `LatticePCG` or `LatticeMultigrid` given as `linsolve` is its preconditioner). There
is no gain limit inside one group. On a GPU this solve waits for each dot product of its GMRES
(about 100–250 waits per window for a strong pair), where every other field solver waits for none;
a model whose fields are not coupled this way keeps a GPU step free of waits. A coupled steady system whose slowest mode grows or is
neutral (an eigenvalue of its Jacobian with nonnegative real part) has no stable steady state:
it is refused, naming that eigenvalue, with the route `BackwardEuler`. With constant
coefficients the eigenvalues are exact, mode by mode. With a coefficient that varies by site
a growing mode is found by a short Arnoldi estimate through the coupled operator and refused
the same way: for a linear group at the start and at each parameter write, for a nonlinear group
at the steady state of its first solve after either, or after the steady start (`init = :steady`):
the run stops with the refusal right after that solve. In Potts a parameter write and a change of the cells' kinds are not checked again (only
the start is); in LatticePDE every parameter write is. A Robin face of either sign is in the operator, so a
linear field with one is still one solve. The steady state must exist and be unique, so `QuasiSteady` refuses
three kinds of field, at the start and at every parameter write:

- a growth that the operator sees (`+ g c`): its steady state is unstable or not unique; step
  it with `BackwardEuler`;
- a Robin face `α c + β ∂c/∂n = g` with α and β of opposite signs that feeds the field more
  than its diffusion and decay remove (the steady operator is indefinite): step it with
  `BackwardEuler`, or give the face a smaller |β|;
- a field with no decay and no fixed value (no Dirichlet or Robin face, no mask): `0 = rhs`
  then has no solution or many. Add a decay or a fixed value.

A steady field whose solver group reads another group that reads it back (a loop of groups)
answers its inputs at once, with the gain of its steady solve, so the lag of one window between
the groups can grow. The coupling rule takes that gain: at most `1/k` for a decay `k`, less
with a Dirichlet or Robin face (a mask does not count, since it moves with the cells). A loop
is accepted when `dt · Σ k_in · gain · k_out ≤ 1`, with `k_in` the coefficients by
which the other group reads the steady field and `k_out` those by which the steady field reads
it back. Several steady groups in one loop compose their gains (the rule solves the steady
responses together), as long as that composition is bounded. Past that limit, or when the rule
has no bound for the gain (no decay and no face), it is refused, with the routes: one
`BackwardEuler` solver for the fields, `BackwardEuler` for the steady field, or a shorter
window. A loop of steady groups only, or a steady group that reads another steady group of its
loop, is refused with the route of one `QuasiSteady` for those fields, which solves them
together. An accepted loop is first order in the window: the steady field reads the other field's
values at the start of the window. The limit `κ ≤ 1` is a stability rule, not an accuracy rule: an
excitatory loop (one that grows) can lag far behind its true growth even below the limit, so
give it a shorter window or step its fields in one solver group. A steady field that
other groups only read is accepted.

A region that the cells cut off with neither a decay nor a fixed value (a decay only inside
the cells, say, and a medium pocket with none) cannot be solved either. The solve finds it at
run time: the run stops with `ReturnCode.ConvergenceFailure`, and the warning names the field,
the window and the route.

Every field solver takes `init = :steady`: before the first window (and at `reinit!`) the group's
steady state is solved once, as `QuasiSteady` would, then the solver steps from it:
`field_solver = BackwardEuler(; init = :steady)`. The steady solve uses the solver's `linsolve`
(by default a conjugate gradient solve to a relative 1e-6), and the steady state must exist and
be unique, as for `QuasiSteady`: a growth is refused, with the route of leaving `init` out. A
steady start that fails stops the run before its first window. A state restored from a checkpoint
is not solved again.

`BackwardEuler` pays a linear solve per substep. It is the faster choice when the explicit
count is large (fast diffusion, a stiff decay); for a field whose explicit count is a few
substeps, `ExplicitEuler` is cheaper. Merks' model on 100² takes about 4.9 ms per MCS with
`BackwardEuler(; lower_bound = 0.0)` against 0.8 ms with `ExplicitEuler(; substeps = 15)` (4 CPU
threads).

## Substep counts, groups and reports

- `substeps = nothing` in a field solver takes the smallest count `n` with
  `dt / n · ρ ≤ 1.8`, where `ρ` bounds the rate's spectral radius: `D · Σ_d 4/h_d²`
  for diffusion plus the size of the coefficient of `c` in a linear reaction. A `Bool`
  input and indicators such as `ismember(kind, g)` are evaluated at 0 and 1, and a rate
  gated by `ifelse(mcs >= t₀, …, 0)` (a condition that reads no field) is bounded branch
  by branch (the worst branch counts). The count is
  recomputed when parameters change; a number is a minimum. The bound also covers, over
  intervals (the interval bound):
  - a coefficient that reads the coordinates (`(1 + x) * laplacian(c)`, `DivKGrad(:harmonic)(1 + x, c)`,
    `- k * (1 + x) * c`), over the lattice's cell centers and, for a velocity and for a face
    coefficient on an axis with a boundary value or flux, one half spacing past the faces;
  - a coefficient that reads a field with declared bounds (`c(..) = 0.5 [bounds = (0, 1)]`):
    `DivKGrad(:harmonic)(c, c)` takes the largest `K` over `[0, 1]`, and a nonlinear reaction
    (`a * c * (1 - c)`) takes the largest `|∂f/∂c|` over it. The bound holds inside the
    declared interval: a field that starts outside it, or a constant boundary or masked value
    outside it, is an error, and a field that leaves it during an `ExplicitEuler` run ends the
    run with `ReturnCode.Unstable` and a warning (`substeps = n` or wider `bounds` are the
    routes); an implicit run warns and goes on (`lower_bound = lo` or wider `bounds` are the routes);
  - a switch (`- a * max(c - c_T, 0)`): its derivative is `a` or 0, so it needs no interval;
  - upwind advection, `Σ_d 2 max|v_d| / h_d` (the CFL limit): a velocity of parameters, of the
    coordinates (`[50 * (1 + x), 0.0]`) or of other fields with declared bounds. A velocity
    that reads the field it moves (`Advect([c, 0], c)`, Burgers) is not bounded: its flux
    Jacobian has a central part, so no step count follows from the velocity alone; it needs
    `substeps = n` or an implicit solver;
  - a term that reads an aux field, through the aux field's definition (`K ~ k * c` makes
    `- K` a decay `k`).
  A coefficient whose interval holds negative values and positive ones is a diffusion whose
  sign the bound does not know, and one whose interval is not finite (`c / (x - 0.5)`) has no
  bound: both need `substeps = n`, and the error names the interval. A rate the bound cannot see
  needs `substeps`, and the problem throws an error naming the term without it: a
  reaction that is not linear in `c` (with no declared bounds), a coefficient that reads other
  state (a field with no declared bounds, `mcs`), and a diffusion multiplier that reads a
  bound cell quantity (`vol * laplacian(c)` with `vol => volume[owner]`). So do fields
  that read each other in a loop (`- Dx * laplacian(u)` in the rate of `c` and `Dx * laplacian(c)` in the rate
  of `u`) when their rows of the Jacobian are not diagonally dominant. A field that reads
  another one way (`u` does not read `c` back) is bounded. A diffusion multiplier that varies
  by site through a kind table
  or a kind set (`dk * laplacian(c)` with `dk => δ[kind]`, `ismember(kind, g) * laplacian(c)`) is bounded: the bound takes
  the largest multiplier times the largest diffusion coefficient. With `substeps = n` in the
  cases the bound cannot see, the count is the larger of
  `n` and the bound of the terms the bound sees (diffusion at least), and the problem warns
  once, naming the terms it does not cover. A reaction coefficient that reads a kind table
  (`- dk * c` with `dk => δ[kind]`) is bounded at every entry of the table, the medium's entry included, and
  the count follows the table's values. A coefficient that is not finite at an entry
  (`- c / tk` with `tk => τ[kind]` and a zero entry) is refused, naming the entry, even with
  `substeps = n`: make the entry finite and nonzero.
- `substep_counts(integ)` gives the substep count of each field group, in group order (the
  order of each group's first field). It follows the parameter writes. `substep_counts(prob)`
  gives the counts at the problem's parameters. The same function gives the counts of a
  LatticePDE problem.
- `field_report(x)` prints why each field group steps as it does. `x` is a `PottsProblem`,
  a `PottsIntegrator` or a `PottsSolution`, or a LatticePDE problem, integrator (owned or
  OrdinaryDiffEq's) or solution: it is the same function. One block per group gives its
  fields and algorithm, the window and the substep count with its cause, the
  stability bound and the terms it cannot see, and the number types. An implicit group also
  gives its `linsolve` solver with its multigrid levels and the Newton count. An integrator
  also gives the run's counters. Then the report gives the coupling between groups.
  `field_report(prob, alg)` prints the policy of a LatticePDE problem under the algorithm
  `alg` without binding anything. The report changes nothing in the run. It may synchronize
  a device, so call it outside a timed loop. [Getting started](@ref fields-getting-started)
  shows it.
- Fields with the same solver step together, substep by substep: a field reads the fields it
  depends on after their update, and fields that depend on each other read each other's
  values from the start of the substep. Fields with different solvers (`solvers = [u =>
  ExplicitEuler(substeps = 4)]`) step one group after another, each reading the others'
  arrays. `field_solver = FieldGroups(u => ExplicitEuler(substeps = 4); default =
  ExplicitEuler())` is the same problem in the form a LatticePDE problem takes: each pair
  gives a field its solver, and `default` solves the other fields. Groups that read one another in a loop (`c` reads `o` and `o` reads `c`) can grow
  without bound at any substep count, because each holds the others' values over the field
  window. For each group in such a loop, the window times the largest sum, over the group's
  fields, of the largest coefficient magnitudes of the terms that read other groups of the
  same loop must be at most 1. Reads of groups outside the loop do not count. Past it the
  problem is refused, naming the fields of the loop. The routes: give those fields one
  solver (with an explicit `substeps = n` when their coupled rates have no automatic count),
  or step the fields over a shorter window (a smaller `dt`; in a Potts model, `repeat(n, …)`
  of the fields or a smaller `mcs_duration`). A one-way chain (`u` reads `c`, `c` does not read `u`) is not limited:
  each group is stable under its own count, and the split adds only a first-order error. A
  group with a term that the stability bound cannot see and that reads another field counts
  as reading every other group. A term that reads only its own field (`- 0.1 * c^2`) does
  not.
- A diffusion coefficient must not be negative: that is anti-diffusion, an ill-posed problem
  whose shortest wavelengths grow without bound under any step. The problem throws an
  error at build. A parameter write that makes it negative (`setp`, `integ.ps[x] = v`,
  `remake`) throws the error itself and changes nothing. A write past the loop limit of
  solver groups (above) does the same.