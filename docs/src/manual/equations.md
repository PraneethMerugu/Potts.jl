# [Equations and solvers: `@equations`, `@components`](@id manual-equations)

`@equations` holds differential equations, algebraic equations and couplings, in
ModelingToolkit syntax. `D` is
the time derivative and `Δ` the lattice Laplacian. The scope of the variable decides what
an equation is:

| Equation | Variable | Meaning | Integrated by |
|---|---|---|---|
| `D(c) ~ Dc * Δ(c) + s * (kind == k) - δ * c` | `c(field)` | a reaction–diffusion PDE on the lattice | `field_solver` |
| `D(x) ~ k₁ - k₂ * x` | `x(cell)` | one ODE per live cell | `ode_solver` |
| `D(g) ~ -g + count(true for c in cells)` | `g(model)` | one ODE for the model | `ode_solver` |
| `Shift(t, 1)(m) ~ g * m + x` | `m(field)` | a map: one application per MCS | `field_solver` (`ExplicitMap()`) |
| `K ~ K₀ * (1 + 0.05 * x)` | `K(field)` | an aux field: its value from the others at every substep | — |
| `y ~ volume / V₀` | `y(cell)` or `y(model)` | an algebraic variable (see below) | — |
| `comp.p ~ volume / V₀` | a component parameter | a coupling (see below) | — |

The right side of a field equation is a site expression: `kind`, `owner`, `position`,
other fields, kind tables (`δ[kind]`). A cell ODE reads cell quantities (`volume`, cell
variables, `integral(c)`) and can read other cells' values (`y[j]`); every ODE step reads
the state at the start of the step. `time` is the current time. In a field equation, `mcs`
is the MCS number at every substep, and `time` is the time of the substep: the time at the
start of the field step plus `j h` at substep `j` (`h` the substep length). `mcs` is the
absolute MCS number: a problem whose span starts at MCS 2 reads 2 first. The step index of a
LatticePDE system, `step_index(t)`, counts from the start of its own time span instead.

**A source on a site predicate.** A term of a field rate can be switched on by any
predicate of the site: its `kind`, a fold over a relation of `site` (the neighbors), site
variables or a helper function of `site` defined in the model. F-actin made only at
lamellipodium sites with a face neighbor in the substrate (Fortuna et al. 2020, Eq. 6) is

```julia
@equations D(F) ~ D_F * Δ(F) - k_decay * F +
                  k_source * (kind == lamellipodium) * any(kind[n] == substrate for n in VonNeumann(1)(site))
```

and `count(true for n in VonNeumann(1)(site) if kind[n] == substrate) > 0` is the same test.
The predicate reads σ as the field phase sees it, which no substep changes (fields run
between sweeps); a neighbor beyond a closed edge is skipped and a periodic edge wraps, as
in every neighbor fold. Only the source is gated: diffusion and decay act everywhere, so
the field spreads beyond the source sites. With one explicit substep the update is
`F + D_F·ΔF − k_decay·F + k_source·[predicate]`, so a persistent source settles at
`k_source/k_decay`. The same rate runs in the device field kernel.

## Cell and model ODEs are ModelingToolkit systems

The cell equations of a model are one ModelingToolkit `System`, the template of one cell, and
its model equations another. Each goes through ModelingToolkit's `mtkcompile`, and Potts
advances the simplified equations for every cell in one batched kernel.
`Potts.ode_system(mtkcompile(sys), :cell)` returns the compiled system (`:model` for the model
equations, `nothing` for a scope without equations). Quantities MTK cannot express, such as
`volume`, neighbor gathers, folds over cells and reads of other cells, appear in it as input
parameters.

An algebraic equation `y ~ expr` defines a cell or model variable `y` by an expression.
`mtkcompile` eliminates `y` as an observed variable, as in ModelingToolkit:

- `y` is not stored. Wherever the model reads it (ODEs, updates, energies, division
  conditions, observed quantities), it reads its definition on the current state.
- `sol[:y]` and `getu` evaluate it on saved states, one value per cell for a cell variable.
- It has no value of its own: a declared value other than zero (`y(cell) = 2.0`) is an
  error. An operating-point entry `y => v` is the initial condition `y ~ v`: the variables of
  its definition that have no value are solved for (see
  [Initialization equations](@ref manual-variables)), and one whose definition reads only
  fixed variables is an "overdetermined" error.
- `y` is read bare only. Every indexed read is an error: `y[j]`, `y[new]`, `y[owner]` and
  `sum(y[c] for c in cells)`. Write a fold over cells bare: `sum(y for c in cells)`.
- A definition is a function of the current state: `rand()` and `Pre` in it are errors. A
  model definition folds cell quantities (`sum(x for c in cells)`), and a cell definition
  reads site quantities through `integral(c)` or at a site (`c[…]`).
- Definitions must be explicit and acyclic: an implicit equation (`y + x ~ 1`), a
  definition that reads itself, two definitions that read each other, and two definitions of
  one variable are errors. So are a variable with both `D(y)` and `y ~ …`, and an update or
  division rule that writes `y`, or reads it as a previous value (`Pre(y)`). Site and field
  variables have no algebraic equations.

```julia
@equations begin
    D(x) ~ -k * excess
    excess ~ x - volume / V₀
end
```

**The operators of a PDESystem.** A field equation takes every operator of a LatticePDE
`PDESystem`. A model needs no import for them:

- `DivKGrad(:harmonic)(K, c)` and `DivKGrad(:arithmetic)(K, c)`: the conservative diffusion
  `∇⋅(K ∇c)`, with the face mean of `K`;
- `Advect(Upwind1())([ux, uy], c)`: first-order upwind advection, with one velocity term per
  axis (parameters, fields or any lowered term);
- a raw flux `Differential(x)(K * Differential(x)(c))`, the same as `DivKGrad` along `x`;
- the lattice coordinates `x`, `y` and `z` (cell centers, from 0 at the low face), such as a
  source `s * x`.

A model that declares its own `x` keeps it, and `Differential(x)` in that model is an error
that names the clash. The binding hides a global of the same name: a model body reads `x`
as the coordinate even when its module defines `x`. When that happens, `@potts_model` warns
once, naming the global; declare the value as a parameter (`@parameters x = 3.0`) to use it.
The coordinates are read by field equations; a site update reads the site's `position`
instead. `position` is the site's corner and `x` its center: `x = position[1] - h/2`, with
`h` the spacing. An operator applies to a field or a site variable. An operator of a CPM
read (`Δ(volume[owner])`) is an error: hold the value in a site variable and apply the
operator to it.

**Aux fields and maps.** `K ~ expr` defines the field `K` by its value: every field group
computes it from the values it reads, at every substep. A model whose only fields are aux
fields has no field to step: its field phase computes them once per MCS, in its place in the
schedule (in the first pass of a `repeat`), and once at the start, so the first sweep reads
`expr`, not the declared value. Such a model takes no `field_solver`. `Shift(t, 1)(m) ~ rhs` is a map: one
application per MCS, stepped by `ExplicitMap()` (the default for a map). Under
`repeat(R, sweep(…), fields)`, a map steps in the first pass only, so it reads the CPM state
after the first part of the sweep. A model has rate
equations or maps, not both: split stepping is planned. The error gives the route, a site
update `@after_mcs m ~ rhs` on a site variable.

## Solvers are part of the problem

The model states the equations; the problem states how to integrate them:

```@example equations
using Potts
using OrdinaryDiffEqTsit5: Tsit5

@potts_model Chem begin
    @kinds medium cell
    @parameters Dc = 0.5
    @variables begin
        c(field) = 0.0
        x(cell) = 1.0
        g(model) = 0.0
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @equations begin
        D(c) ~ Dc * Δ(c) + 0.1 * (kind == cell) - 0.05 * c
        D(x) ~ 0.2 * integral(c) / volume - 0.1 * x
        D(g) ~ count(true for k in cells) - g
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named chem = Chem()
op = layout(Tiling((5, 5); region = (11:20, 11:20), kinds = [:cell]), chem)
prob = PottsProblem(chem, op, (0, 50); field_solver = ExplicitEuler(substeps = 4, lower = 0.0))
sol = solve(prob, SequentialCPM())
sol[:x][end], sol[:g][end]
```

| Keyword | Values | Default |
|---|---|---|
| `field_solver` | `ExplicitEuler(; substeps, lower)`: `substeps` explicit steps per MCS, values clipped at `lower`; `BackwardEuler(; substeps, newton, lower, inner, solver_T)`: implicit steps, each a linear solve with `inner`; `CrankNicolson(…)`, `BDF2(…)`: second-order implicit steps, the same keywords; `QuasiSteady(; newton, inner, solver_T)`: the steady state in each MCS; each takes `init = :steady` (a steady start) and `compute_T` (`Float32` or `Float64`: the number type its kernels compute in; default the problem's `T`) | `ExplicitEuler()`: the automatic count, no clip |
| `ode_solver` | `ExplicitEuler(; substeps)`, `RK4(; substeps)`, `Adaptive(alg; kwargs...)` | `ExplicitEuler()`, one step per MCS |
| `solvers` | `[x => solver, …]`, per variable or component | — |

The linear solvers `DevicePCG(; budget, rtol, precond)`, `Multigrid(; cycle = (2, 2), cycles, rtol, budget)`
and `DeviceGMRES(; restart, budget, rtol, precond)` are the `LatticeFields.Solvers` objects, the same in Potts and LatticePDE. They are the
`inner` linear solver of the implicit field solvers:
`field_solver = BackwardEuler(; inner = DevicePCG(; budget = 12))`. They are not field
solvers themselves: `field_solver`, `solvers` and `FieldGroups` refuse them and give that
route.

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
(`δ[kind] * Δ(c) + DivKGrad(K, c)`: the term with the larger bound is in the solve), are
corrected by more Newton iterations. Their substep count keeps the correction converging (for
the sum of their bounds; advection with a constant velocity: `substeps ≥ 2 · mcs_duration ·
Σ_a 2|u_a|/h_a`), and `newton` defaults to the iterations that this bound needs. A second
diffusion term that is at most half the one in the solve, face by face (with a multiplier in
the solve that is positive everywhere), needs no extra substeps at all, only a few more
Newton iterations. When these rules raise a `substeps = n` you gave, a warning says which
rule and which terms. `DeviceGMRES` is not a time stepper's `inner` (it is the coupled steady
solve's, below): on BackwardEuler, CrankNicolson and BDF2 it was slower in every case measured,
so they refuse it. Each substep
checks the Newton correction: a correction that does not reach the tolerance in `newton`
iterations is counted in `integ.stats` and warned once with the route (a larger `newton = k`,
or more substeps). A correction that diverges ends the run with
`ReturnCode.ConvergenceFailure`, and the warning gives more substeps as the route. Under the
automatic count, a CPU run stops a substep's Newton iterations once the correction meets the
tolerance; a GPU runs them all, so CPU and GPU results agree to the tolerance, not bitwise. On
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
  first MCS and every write (a state, parameter or table write, `reinit!`). A field whose data
  can jump every MCS damps the first substep of every MCS. Such a field reads the CPM (`kind`,
  `ismember`), another field group or `mcs`, or has a mask that moves. Such a field takes at
  least 2 substeps per MCS by default: the damped one, then Crank–Nicolson substeps, so the
  error of an MCS falls as `1/n²` with the count `n`. With `substeps = 1` it is Backward Euler
  in two halves: first order, at twice Backward Euler's cost.
- `BDF2` solves `(u − (4uⁿ − uⁿ⁻¹)/3)/(2h/3) = rhs(u)` at the substep's end time. It needs
  the field one substep back, which it keeps itself: it is not part of the state, so it is not
  saved and not in a checkpoint. The first substep after a start is one Backward Euler
  substep. A start is the first MCS, every write, a restored checkpoint, and every change of
  the substep count (the formula needs one step length). A move of the cells is no start.

Neither keeps nonnegative values nonnegative: a stiff decay overshoots below 0. Give
`lower = 0.0` for a concentration, or use `BackwardEuler`, which needs no clip on a
consumption field. A clip changes the equation solved slightly.

`QuasiSteady()` solves a field's steady state `0 = rhs` in each MCS, at the cells of that
MCS: a field that relaxes much faster than the cells move. Each MCS starts from the last
solution. Write such a field's equation as a steady row, `0 ~ Dc * Δ(c) - kd * c + s`: it is
solved for a field it reads that has no other equation, the one under its operator first,
with `QuasiSteady` by default (another solver for it is an error). Its sign does not matter:
`0 ~ kd * c - Dc * Δ(c) - s` is the same row. A local row such as `0 ~ -2c + 0.5e`, with
`D(e) ~ …`, is `c`'s. Steady fields are solved first in each MCS, so the other fields read their
values of that MCS. `QuasiSteady` also solves a rate row `D(c) ~ rhs` as `0 = rhs`. It takes `newton`, `inner` and `solver_T` with the meanings above, and has no
`substeps` and no `lower`. A linear field takes one linear solve per MCS; a nonlinear or
switched one takes up to 8 Newton iterations, checked as above. When a term stays out of the
operator (advection), the count comes from the bound on that term against the decay, from 8
to at most 40 iterations; give `newton = k` if the warning says the budget is hit. Steady
fields of one `QuasiSteady` that read one another (`0 ~ Δ(a) - a + 0.5b` and
`0 ~ Δ(b) - b - 0.5a`, a cross diffusion `Δ(b)` in `a`'s row), and a row with a term the
operator does not see (`c²` in `0 ~ q - c^2`), are solved together: one Newton iteration
solves all their rows with every cross term in the operator, by a restarted GMRES
(`DeviceGMRES()`; a `DevicePCG` or `Multigrid` given as `inner` is its preconditioner). There
is no gain limit inside one group. On a GPU this solve waits for each dot product of its GMRES
(about 100–250 waits per MCS for a strong pair), where every other field solver waits for none;
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
answers its inputs at once, with the gain of its steady solve, so the lag of one MCS between
the groups can grow. The coupling rule takes that gain: at most `1/k` for a decay `k`, less
with a Dirichlet or Robin face (a mask does not count, since it moves with the cells). A loop
is accepted when `mcs_duration · Σ k_in · gain · k_out ≤ 1`, with `k_in` the coefficients by
which the other group reads the steady field and `k_out` those by which the steady field reads
it back. Several steady groups in one loop compose their gains (the rule solves the steady
responses together), as long as that composition is bounded. Past that limit, or when the rule
has no bound for the gain (no decay and no face), it is refused, with the routes: one
`BackwardEuler` solver for the fields, `BackwardEuler` for the steady field, or a shorter
window. A loop of steady groups only, or a steady group that reads another steady group of its
loop, is refused with the route of one `QuasiSteady` for those fields, which solves them
together. An accepted loop is first order in the window: the steady field reads the other field's
values at the start of the MCS. The limit `κ ≤ 1` is a stability rule, not an accuracy rule: an
excitatory loop (one that grows) can lag far behind its true growth even below the limit, so
give it a smaller `mcs_duration` or step its fields in one solver group. A steady field that
other groups only read is accepted.

A region that the cells cut off with neither a decay nor a fixed value (a decay only inside
the cells, say, and a medium pocket with none) cannot be solved either. The solve finds it at
run time: the run stops with `ReturnCode.ConvergenceFailure`, and the warning names the field,
the MCS and the route.

Every field solver takes `init = :steady`: before the first MCS (and at `reinit!`) the group's
steady state is solved once, as `QuasiSteady` would, then the solver steps from it:
`field_solver = BackwardEuler(; init = :steady)`. The steady solve uses the solver's `inner`
(by default a conjugate gradient solve to a relative 1e-6), and the steady state must exist and
be unique, as for `QuasiSteady`: a growth is refused, with the route of leaving `init` out. A
steady start that fails stops the run before its first MCS. A state restored from a checkpoint
is not solved again.

`BackwardEuler` pays a linear solve per substep. It is the faster choice when the explicit
count is large (fast diffusion, a stiff decay); for a field whose explicit count is a few
substeps, `ExplicitEuler` is cheaper. Merks' model on 100² takes about 4.9 ms per MCS with
`BackwardEuler(; lower = 0.0)` against 0.8 ms with `ExplicitEuler(; substeps = 15)` (4 CPU
threads).

- `substeps = nothing` in a field solver takes the smallest count `n` with
  `mcs_duration / n · ρ ≤ 1.8`, where `ρ` bounds the rate's spectral radius: `D · Σ_d 4/h_d²`
  for diffusion plus the size of the coefficient of `c` in a linear reaction. Indicators
  such as `(kind == medium)` and `ismember(kind, g)` are evaluated at 0 and 1, and a rate
  gated by `ifelse(mcs >= t₀, …, 0)` (a condition that reads no field) is bounded branch
  by branch (the worst branch counts). The count is
  recomputed when parameters change; a number is a minimum. The bound also covers, over
  intervals (the interval bound):
  - a coefficient that reads the coordinates (`(1 + x) * Δ(c)`, `DivKGrad(:harmonic)(1 + x, c)`,
    `- k * (1 + x) * c`), over the lattice's cell centers and, for a velocity and for a face
    coefficient on an axis with a boundary value or flux, one half spacing past the faces;
  - a coefficient that reads a field with declared bounds (`c(field) = 0.5, [bounds = (0, 1)]`):
    `DivKGrad(:harmonic)(c, c)` takes the largest `K` over `[0, 1]`, and a nonlinear reaction
    (`a * c * (1 - c)`) takes the largest `|∂f/∂c|` over it. The bound holds inside the
    declared interval: a field that starts outside it, or a constant boundary or masked value
    outside it, is an error, and a field that leaves it during an `ExplicitEuler` run ends the
    run with `ReturnCode.Unstable` and a warning (`substeps = n` or wider `bounds` are the
    routes); an implicit run warns and goes on (`lower = lo` or wider `bounds` are the routes);
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
  state (a field with no declared bounds, `mcs`), and a diffusion multiplier that reads a CPM
  value directly (`volume[owner] * Δ(c)`). So do fields
  that read each other in a loop (`- Dx * Δ(u)` in the rate of `c` and `Dx * Δ(c)` in the rate
  of `u`) when their rows of the Jacobian are not diagonally dominant. A field that reads
  another one way (`u` does not read `c` back) is bounded. A diffusion multiplier that varies
  by site through a kind table
  or a kind set (`δ[kind] * Δ(c)`, `ismember(kind, g) * Δ(c)`) is bounded: the bound takes
  the largest multiplier times the largest diffusion coefficient. With `substeps = n` in the
  cases the bound cannot see, the count is the larger of
  `n` and the bound of the terms the bound sees (diffusion at least), and the problem warns
  once, naming the terms it does not cover. A reaction coefficient that reads a kind table
  (`- δ[kind] * c`) is bounded at every entry of the table, the medium's entry included, and
  the count follows the table's values. A coefficient that is not finite at an entry
  (`- c / τ[kind]` with a zero entry) is refused, naming the entry, even with
  `substeps = n`: make the entry finite and nonzero.
- `substep_counts(integ)` gives the substep count of each field group, in group order (the
  order of each group's first field). It follows the parameter writes. `substep_counts(prob)`
  gives the counts at the problem's parameters. The same function gives the counts of a
  LatticePDE problem.
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
  or step the fields over a shorter window (`repeat(n, …)` of the fields, or a smaller
  `mcs_duration`). A one-way chain (`u` reads `c`, `c` does not read `u`) is not limited:
  each group is stable under its own count, and the split adds only a first-order error. A
  group with a term that the stability bound cannot see and that reads another field counts
  as reading every other group. A term that reads only its own field (`- 0.1 * c^2`) does
  not.
- The CPM quantities in a field equation (`kind`, cell reads, neighbor counts) are evaluated
  once per MCS, before the fields step, and held over the substeps; so is `mcs`. `time`
  advances with the substeps. `rand()` cannot appear in a field equation: draw in a site
  update and read its variable.
- On a hexagonal lattice, `Δ` is the only spatial operator. On a lattice with a `domain`,
  the fields live in the domain: a site outside it keeps its value, and the domain's edge
  has zero flux. Face values still apply at the faces of the box.
- A diffusion coefficient must not be negative: that is anti-diffusion, an ill-posed problem
  whose shortest wavelengths grow without bound under any step. The problem throws an
  error at build. A parameter write that makes it negative (`setp`, `integ.ps[x] = v`,
  `remake`) throws the error itself and changes nothing. A write past the loop limit of
  solver groups (above) does the same.
- `Adaptive(alg; reltol, abstol, …)` integrates cell and model ODEs on the host with any
  SciML ODE algorithm (load its package, e.g. OrdinaryDiffEqTsit5). Equations with
  `rand()` cannot be integrated adaptively. Its keywords and the algorithm's fields are
  part of the problem's identity (a checkpoint resumes only under an equal solver), so a
  value in them may be at most 8 levels deep and must not refer to itself. A closure or
  anonymous function there (`isoutofdomain = (u, p, t) -> …`) works, but its checkpoints
  load only in the same Julia session; use a named function or a callable struct to resume
  in a new session (see [Checkpoints](@ref)).
- `remake(prob; ode_solver = …)` regenerates the code with the new solver and keeps the
  state, parameters and seed.

```@example equations
prob2 = remake(prob; ode_solver = Adaptive(Tsit5(); reltol = 1e-8), solvers = [:g => RK4(substeps = 4)])
solve(prob2, SequentialCPM()).retcode
```

The time step is one MCS times `mcs_duration` (default 1), set in `@sweep`.

## Field boundaries: `@boundary`

A field's boundary conditions are model content, one `@boundary` block per field:

```@example equations
@potts_model Absorbed begin
    @kinds medium cell border[frozen]
    @parameters begin
        Dc = 0.2
        S = 1.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((30, 20); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @equations D(c) ~ Dc * Δ(c) + 0.1 * (kind == cell)
    @boundary c begin
        x => (Dirichlet(S), NoFlux())                 # the low x face held at S, the high one closed
        sites(kind == border) => Dirichlet(0.0)        # an absorbing obstacle
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named absorbed = Absorbed()
σ = zeros(Int32, 30, 20); σ[14:17, 1:20] .= 1; σ[4:8, 8:12] .= 2
prob = PottsProblem(absorbed, [ownership => σ, kind => [:border, :cell]], (0, 20);
    field_solver = ExplicitEuler(substeps = 2))
u = solve(prob, SequentialCPM()).u[end]
(wall = maximum(u.site.c[14:17, :]), low_face = sum(u.site.c[1, :]) / 20)
```

- **Faces.** `x => (low, high)` (and `y`, `z`: axes 1, 2, 3) sets both faces of a closed
  axis. A face value is a ghost value, the missing neighbor of an edge site:

  | Side | Meaning | Ghost value |
  |---|---|---|
  | `Dirichlet(v)` | `c = v` at the face | `2v − c`: the field reaches `v` midway between the edge site and the face |
  | `NoFlux()` | `∂c/∂n = 0` | `c`: it mirrors the edge site |
  | `Flux(q)` | `∂c/∂n = q`, with the outward normal `n` | `c + q h` |
  | `Robin(α, β, g)` | `α c + β ∂c/∂n = g` | the value that meets the condition at the face |

  These are the face equations of a LatticePDE system: `Flux(q)` on the low side of `x` is
  `Differential(x)(c(t, 0, y)) ~ -q`, on the high side `Differential(x)(c(t, L, y)) ~ q`.
  `Robin(α, 0, g)` is an error that gives `Dirichlet(g / α)`, and `Robin(0, β, g)` one that
  gives `Flux(g / β)`. A face coefficient that reads a field (`DivKGrad(:arithmetic)(c^3, c)`)
  takes the field's ghost value at the face: with `Dirichlet(1.0)` and `c = 0` at the edge
  site, the face mean is `(0³ + 2³)/2`, so the field enters through the face. The bound of the
  field solvers covers these ghost values. The harmonic mean of `0³` and `2³` is 0, so
  `DivKGrad(:harmonic)` keeps a degenerate front (`K = 0` where `c = 0`) from moving; use
  `DivKGrad(:arithmetic)` for degenerate diffusion. A closed axis without an entry is zero flux. An
  entry on a periodic axis, on an axis the lattice lacks, on a hexagonal lattice, or on a
  field whose equation has no spatial operator of it is an error naming it.
- **Site masks.** `sites(condition) => Dirichlet(v)` is a node value: every explicit
  substep writes `v` at every site where the condition holds (after the `lower` clip, so a
  mask value below `lower` wins), and a fresh initial state (the problem's `u0`, `init`,
  `reinit!`) is clamped too; a state restored from a checkpoint is not (it continues the run
  exactly), nor does `Potts.anneal` clamp. The condition is a site expression (`kind`,
  `owner`, site and field variables), evaluated once per MCS before the substeps, so a mask
  on a kind moves with its cells. The masked sites then take their value before the first
  substep, so a site a cell has just reached holds `v` when its neighbors read it. The
  condition reads the state at the start of its field group's window: it is evaluated
  once, on the clamped values, and held over the MCS. This holds for every field it reads,
  the field it clamps and a field stepped after it included. With several solver groups, a
  field of a group stepped earlier in the MCS reads as stepped, as a rate reads another
  group's field. Write a condition on the field it clamps with `>=`, as in
  `sites(c >= 0.8) => Dirichlet(0.8)`. With `>`, the clamp sets `c = 0.8`, `0.8 > 0.8` is
  false, and the next MCS releases the sites. The masks of a field group cost one kernel
  launch per MCS.
- **Values** are numbers, parameters, or a number times a parameter; `remake(prob; p = [:S => 2.0])`
  changes a value without regenerating code. For an expression of parameters, declare a
  computed parameter (`@parameters S = S1 + S2`) and write `Dirichlet(S)`; an expression in
  `Dirichlet(…)` is an error that names this route. The conditions themselves are part of the
  model's identity (the fingerprint): a checkpoint does not cross them.
- In an extension, a field's `@boundary` replaces the base's for that field.

`Δ(c)` is a field operator: it appears in field equations (`D(c) ~ …`), where it reads the
faces. Anywhere else (site updates, energies, drives, `@observed`) it is an error.

`@bcs` takes the boundary conditions of a LatticePDE system, one per line. A field is read
at a face by its coordinates, with one of them fixed: `c(t, 0, y)` is the low face of `x`,
and `c(t, L, y)` the high face, with `L` the lattice's extent along `x` (its size times the
spacing). The field compiler lowers them as it lowers a `PDESystem`:

- `c(t, 0, y) ~ v`: a fixed value, the same as `Dirichlet(v)`;
- `Differential(x)(c(t, L, y)) ~ q`: a gradient across the face (Neumann);
- `α * c(t, 0, y) - β * Differential(x)(c(t, 0, y)) ~ g`: a Robin face;
- `c ~ masked(kind == border, v)`: a node value, the same as `sites(kind == border) => Dirichlet(v)`.

A value is a number, a parameter, or a number times a parameter. A face or mask that
`@boundary` sets too is an error that prints the condition. So is an initial value
(`c(0, x, y) ~ v`: the field's `@variables` default is its initial value), and a periodic
pair on an axis the lattice closes (periodicity is the lattice's, for every field).
`Potts.fields(model)` holds the conditions, so `discretize` runs them as written.

## Components

`@components` adds ModelingToolkit systems to the model:

- `@components cells(k) name = sys`: one copy of `sys` in every cell of kind `k` (bare
  `@components name = sys`: every cell);
- `@components model name = sys`: one copy for the whole model.

The system's unknowns become cell (or model) variables named `name₊x`, read in the model as
`name.x`. A coupling `@equations name.p ~ expression` replaces the parameter `p` by an
expression of the cell; the other parameters become model parameters `name₊p`, which
`remake` can change. Division rules can read and set component variables
(`when = name.x >= 1`, `name.x => 0.0`).

Discrete-time systems with a `ShiftIndex` clock (Boolean or discrete networks) tick once
per MCS, or every `n` MCS with `ShiftIndex(Clock(n))`; continuous and discrete components
can be coupled. [Tutorial 5](@ref tutorial-cell-odes) shows both kinds.

```@example equations
using Potts.ModelingToolkitBase: System, @variables, @parameters
@variables drug(Potts.t) = 0.0
@parameters dose = 0.0 clearance = 0.2
@named pk = System([Potts.D(drug) ~ dose - clearance * drug], Potts.t)

@potts_model Dosed begin
    @kinds medium cell
    @components model pk = pk
    @equations pk.dose ~ 0.1 * count(true for c in cells)
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @sweep Metropolis(; temperature = 8.0)
end
@named dosed = Dosed()
s = solve(PottsProblem(dosed, layout(Tiling((5, 5); region = (11:20, 11:20), kinds = [:cell]), dosed), (0, 20)),
    SequentialCPM())
s[:pk₊drug][end]
```
