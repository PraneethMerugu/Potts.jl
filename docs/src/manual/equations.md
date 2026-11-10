# [Equations and solvers: `@fields`, `@equations`, `@components`](@id manual-equations)

A model holds two kinds of equations:

- **Fields** are reaction–diffusion PDEs on the lattice. Each comes from a ModelingToolkit
  `PDESystem`, which `@fields` couples into the model (`Potts.couple` outside the macro).
- **Cell and model equations** are ODEs, algebraic equations and couplings in `@equations`,
  in ModelingToolkit syntax. `D` is the time derivative.

| Equation | Where | Meaning | Integrated by |
|---|---|---|---|
| `Dt(c) ~ Dc * Δ(c) + s * src - δ * c` | a `PDESystem` | a reaction–diffusion PDE on the lattice | `field_solver` |
| `Shift(t, 1)(m) ~ g * m + q` | a `PDESystem` | a map: one application per MCS | `field_solver` (`ExplicitMap()`) |
| `K ~ K₀ * (1 + 0.05 * u)` | a `PDESystem` | an aux field: its value from the others at every substep | — |
| `D(x) ~ k₁ - k₂ * x` | `@equations`, `x(cell)` | one ODE per live cell | `ode_solver` |
| `D(g) ~ -g + count(true for c in cells)` | `@equations`, `g(model)` | one ODE for the model | `ode_solver` |
| `y ~ volume / V₀` | `@equations`, `y(cell)` or `y(model)` | an algebraic variable (see below) | — |
| `comp.p ~ volume / V₀` | `@equations`, a component parameter | a coupling (see below) | — |

In the table and in the text below, a field `c` stands for `c(t, x, y)`.

## Fields: `@fields`

A field is a dependent variable of a `PDESystem` on the lattice's domain. The `PDESystem`
does not read the cells. It reads **input fields**, declared `[input = true]`, and
`@fields` binds each input to an expression of the site:

```@example equations
using Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: Δ, lattice_domain

t = Potts.t
Dt = Differential(t)
@parameters x y Dc = 0.2 s = 0.5 kd = 0.1 av = 0.01
@variables c(..) = 0.0 endo(..)::Bool [input = true] vol(..) [input = true]
C = c(t, x, y)
attractant = PDESystem([Dt(C) ~ Dc * Δ(C) + s * endo(t, x, y) - kd * C + av * vol(t, x, y)], [],
    lattice_domain(t, (x, y), (24, 20)), [t, x, y], [C, endo(t, x, y), vol(t, x, y)], [Dc, s, kd, av];
    name = :attractant)

@potts_model Secreting begin
    @kinds medium A
    @parameters χ = 400.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @fields c = attractant (endo => kind == A, vol => volume[owner])
    @drive Chemotaxis(c; strength = χ, kinds = (A,))
    @sweep Metropolis(; temperature = 4.0)
end

@named secreting = Secreting()
σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2
sol = solve(PottsProblem(secreting, [ownership => σ, kind => [:A, :A]], (0, 12); seed = 3), SequentialCPM())
maximum(sol[:c][end])
```

- **Lines.** `@fields c = sys (bindings…)` adds the fields, parameters, equations and
  conditions of `sys` to the model at that line. The names before `=` (`c`, or a list
  `c, u`) are bound to fields of `sys` for the lines after it, so a drive or an energy
  reads `c[target]`. Without names, `@fields sys (…)`, the fields are reached by name only
  (`sol[:c]`). Write `@fields` after `@kinds` and `@lattice`, and above every line that
  reads its names. A model can have several `@fields` lines. A later one can bind an input
  to a field of an earlier one: `@fields sys2 (cin => c)`.
- **Names.** Each field keeps its own name: `sol[:c]`, `FieldGroups(:c => …)`,
  `solvers = [:c => …]` and the operating point `:c => values` read it. Each parameter of
  `sys` becomes a model parameter with its value. The operating point (`:kd => 0.3`),
  `remake` and the constructor keyword (`Secreting(; kd = 0.3)`) change it. A name that the
  model already has is an error.
- **Domain.** The domain of `sys` is the lattice's, in the model's length unit: axis `d`
  spans `[0, dims[d] · spacing[d]]`. `lattice_domain(t, (x, y), dims; spacing)` gives it.
  Another interval is an error that names both. The time interval of `sys` is not read:
  the problem's `tspan` is. Periodicity is the lattice's, for every field.
- **Initial value.** A field starts at its default (`c(..) = 0.0`) or at a condition at the
  start time (`c(0, x, y) ~ v`). An operating-point entry `:c => values` replaces it.
  LatticePDE's `discretize` reads only the condition, so a `PDESystem` that you also solve
  on its own needs `c(0, x, y) ~ v`.
- **Bindings.** `input => expression` takes any site expression of the model: `kind == A`,
  `volume[owner]`, site variables, `position`, folds over the neighbors and helper
  functions of `site`. A `Bool` input (`endo(..)::Bool`) takes a truth value, and a numeric
  input takes a number. Potts fills every input at every site once per MCS, before the
  fields step, and holds it over the substeps.
- **Unbound inputs.** An input without a binding is filled by its `lattice_input_name`, or
  else by its own name: `kind` (the kind number of the site, 0 for the medium), `owner`,
  `position`, `site`, `mcs`, `time`, or a field or site variable of the model. A `Bool`
  input that such a word fills with numbers is an error that gives the binding.

The right side of a field equation reads the fields of its `PDESystem`, its inputs, its
parameters, the coordinates and `t`. In a field equation `t` is the time of the substep:
the time at the start of the field step plus `j h` at substep `j` (`h` the substep
length). An input named `mcs` reads the absolute MCS number, held over the substeps: a
problem whose span starts at MCS 2 reads 2 first. `step_index(t)` is the step index:

- in a coupled `PDESystem` (`@fields`, `Potts.couple`) it is the model's MCS number, the
  same absolute count as `mcs`;
- in a standalone or SciML solve (`discretize`, which then needs
  `LatticeDiscretization(…; clock = τ)`) it counts from the start of the problem's
  `tspan`.

**A source on a site predicate.** A binding can be any predicate of the site: its `kind`, a
fold over a relation of `site` (the neighbors), site variables or a helper function of
`site` defined in the model. F-actin made only at lamellipodium sites with a face neighbor
in the substrate (Fortuna et al. 2020, Eq. 6) binds the input `edge` of its `PDESystem`:

```julia
@variables F(..) = 0.0 edge(..) [input = true]
actin = PDESystem([Dt(F(t, x, y)) ~ D_F * Δ(F(t, x, y)) - k_decay * F(t, x, y) + k_source * edge(t, x, y)], [],
    lattice_domain(t, (x, y), dims), [t, x, y], [F(t, x, y), edge(t, x, y)], [D_F, k_decay, k_source]; name = :actin)

# in the model
@fields F = actin (edge => (kind == lamellipodium) * any(kind[n] == substrate for n in VonNeumann(1)(site)))
```

and `count(true for n in VonNeumann(1)(site) if kind[n] == substrate) > 0` is the same test.
The predicate reads σ as the field phase sees it, which no substep changes (fields run
between sweeps); a neighbor beyond a closed edge is skipped and a periodic edge wraps, as
in every neighbor fold. Only the source is gated: diffusion and decay act everywhere, so
the field spreads beyond the source sites. With one explicit substep the update is
`F + D_F·ΔF − k_decay·F + k_source·[predicate]`, so a persistent source settles at
`k_source/k_decay`. The same rate runs in the device field kernel.

!!! warning "Write a kind set as `ismember`, not with `∈`"
    In a `PDESystem` equation, write a kind set as `ismember(k, (1, 2))`. Two spellings
    with `∈` build without an error, but they do not test membership:

    - `k ∈ Set([1, 2])` is `false` before any symbolic term exists. So
      `3k * (k ∈ Set([1, 2]))` is `0`: the term is deleted from the equation, and no
      check can see it after that. This is reported to Symbolics as
      [Symbolics.jl#2126](https://github.com/JuliaSymbolics/Symbolics.jl/issues/2126).
    - `k ∈ (1, 2)` is a domain pairing (`VarDomainPairing`): it says that `k` lies in the
      interval from 1 to 2. In an expression it is an error from Symbolics
      (`MethodError: no method matching +(::Num, ::VarDomainPairing)`); alone as a side,
      LatticePDE refuses it.

    These facts hold on Symbolics 7.45.0 and 7.48.0.

    `k ∈ [1, 2]` stays a symbolic `in` term, which LatticePDE also refuses. A binding
    (`inner => kind == A`) keeps most kind tests out of the `PDESystem`.

**The operators of a PDESystem.** A field equation takes every operator of LatticePDE
(`using Potts.LatticePDE: DivKGrad, Advect, Upwind1`):

- `DivKGrad(:harmonic)(K, c)` and `DivKGrad(:arithmetic)(K, c)`: the conservative diffusion
  `∇⋅(K ∇c)`, with the face mean of `K`;
- `Advect(Upwind1())([ux, uy], c)`: first-order upwind advection, with one velocity term per
  axis (parameters, fields or any lowered term);
- a raw flux `Differential(x)(K * Differential(x)(c))`, the same as `DivKGrad` along `x`;
- the coordinates `x`, `y` and `z` of the `PDESystem` (cell centers, from 0 at the low
  face), such as a source `s * x`.

The coordinates are read by field equations; a site update reads the site's `position`
instead. `position` is the site's corner and `x` its center: `x = position[1] - h/2`, with
`h` the spacing. An operator applies to a field. To apply one to a cell quantity, hold the
quantity in a field.

**Aux fields and maps.** `K ~ expr` in a `PDESystem` defines the field `K` by its value:
every field group computes it from the values it reads, at every substep. A model whose
only fields are aux fields has no field to step: its field phase computes them once per
MCS, in its place in the schedule (in the first pass of a `repeat`), and once at the start,
so the first sweep reads `expr`, not the declared value. Such a model takes no
`field_solver`. `Shift(t, 1)(m) ~ rhs` is a map: one application per MCS, stepped by
`ExplicitMap()` (the default for a map). Under `repeat(R, sweep(…), fields)`, a map steps in
the first pass only, so it reads the CPM state after the first part of the sweep. A model
has rate equations or maps, not both: split stepping is planned. The error gives the route,
a site update `@after_mcs m ~ rhs` on a site variable.

## Cell and model ODEs are ModelingToolkit systems

The cell equations of a model are one ModelingToolkit `System`, the template of one cell, and
its model equations another. Each goes through ModelingToolkit's `mtkcompile`, and Potts
advances the simplified equations for every cell in one batched kernel.
`Potts.ode_system(mtkcompile(sys), :cell)` returns the compiled system (`:model` for the model
equations, `nothing` for a scope without equations). Quantities MTK cannot express, such as
`volume`, neighbor gathers, folds over cells and reads of other cells, appear in it as input
parameters.

A cell ODE reads cell quantities (`volume`, cell variables, `integral(c)` of a field `c`)
and can read other cells' values (`y[j]`); every ODE step reads the state at the start of
the step. `time` is the current time.

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

## Solvers are part of the problem

The model states the equations; the problem states how to integrate them:

```@example equations
using OrdinaryDiffEqTsit5: Tsit5

@parameters Dc = 0.5
@variables incell(..)::Bool [input = true]
chemical = PDESystem([Dt(C) ~ Dc * Δ(C) + 0.1 * incell(t, x, y) - 0.05 * C], [],
    lattice_domain(t, (x, y), (30, 30)), [t, x, y], [C, incell(t, x, y)], [Dc]; name = :chemical)

@potts_model Chem begin
    @kinds medium cell
    @variables begin
        q(cell) = 1.0
        g(model) = 0.0
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @fields c = chemical (incell => kind == cell)
    @equations begin
        D(q) ~ 0.2 * integral(c) / volume - 0.1 * q
        D(g) ~ count(true for k in cells) - g
    end
    @sweep Metropolis(; temperature = 8.0)
end

@named chem = Chem()
op = layout(Tiling((5, 5); region = (11:20, 11:20), kinds = [:cell]), chem)
prob = PottsProblem(chem, op, (0, 50); field_solver = ExplicitEuler(substeps = 4, lower = 0.0))
sol = solve(prob, SequentialCPM())
sol[:q][end], sol[:g][end]
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
(`dk * Δ(c) + DivKGrad(K, c)` with `dk => δ[kind]`: the term with the larger bound is in the
solve), are
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
  can jump every MCS damps the first substep of every MCS. Such a field reads an input (`kind`,
  a binding), another field group or `mcs`, or has a mask that moves. Such a field takes at
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
  for diffusion plus the size of the coefficient of `c` in a linear reaction. A `Bool`
  input and indicators such as `ismember(kind, g)` are evaluated at 0 and 1, and a rate
  gated by `ifelse(mcs >= t₀, …, 0)` (a condition that reads no field) is bounded branch
  by branch (the worst branch counts). The count is
  recomputed when parameters change; a number is a minimum. The bound also covers, over
  intervals (the interval bound):
  - a coefficient that reads the coordinates (`(1 + x) * Δ(c)`, `DivKGrad(:harmonic)(1 + x, c)`,
    `- k * (1 + x) * c`), over the lattice's cell centers and, for a velocity and for a face
    coefficient on an axis with a boundary value or flux, one half spacing past the faces;
  - a coefficient that reads a field with declared bounds (`c(..) = 0.5 [bounds = (0, 1)]`):
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
  state (a field with no declared bounds, `mcs`), and a diffusion multiplier that reads a
  bound cell quantity (`vol * Δ(c)` with `vol => volume[owner]`). So do fields
  that read each other in a loop (`- Dx * Δ(u)` in the rate of `c` and `Dx * Δ(c)` in the rate
  of `u`) when their rows of the Jacobian are not diagonally dominant. A field that reads
  another one way (`u` does not read `c` back) is bounded. A diffusion multiplier that varies
  by site through a kind table
  or a kind set (`dk * Δ(c)` with `dk => δ[kind]`, `ismember(kind, g) * Δ(c)`) is bounded: the bound takes
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
- `field_report(x)` (`Potts.LatticePDE.field_report`) prints why each field group of a
  LatticePDE problem steps as it does. `x` is a problem, an integrator (owned or
  OrdinaryDiffEq's) or a solution of either. One block per group gives its fields and
  algorithm, the window and the substep count with its cause, the stability bound and the
  terms it cannot see, the number types and the run's counters; then the coupling between
  groups. `field_report(prob, alg)` prints the policy of `prob` under the algorithm `alg`
  without binding anything. It may synchronize a device, so call it outside a timed loop.
  The [SciML path](@ref manual-sciml-path) below shows it.
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
- The inputs of a field (`kind`, bound cell reads, neighbor counts) are filled once per MCS,
  before the fields step, and held over the substeps; so is `mcs`. `t` advances with the
  substeps. `rand()` cannot appear in a field equation: draw in a site update and bind an
  input to its variable.
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

## Boundary conditions

A field's boundary conditions are the conditions of its `PDESystem`, its second argument.
A field is read at a face by its coordinates, with one of them fixed: `c(t, 0, y)` is the
low face of `x`, and `c(t, L, y)` the high face, with `L` the lattice's extent along `x`
(its size times the spacing):

```@example equations
using Potts.LatticePDE: masked
@parameters Dd = 0.2 S = 1.0
@variables wall(..)::Bool [input = true]
absorbing = PDESystem([Dt(C) ~ Dd * Δ(C) + 0.1 * incell(t, x, y)],
    [c(t, 0, y) ~ S,                         # the low x face held at S
     Differential(x)(c(t, 30, y)) ~ 0,       # the high x face closed
     C ~ masked(wall(t, x, y), 0.0)],        # an absorbing obstacle
    lattice_domain(t, (x, y), (30, 20)), [t, x, y], [C, incell(t, x, y), wall(t, x, y)], [Dd, S];
    name = :absorbing)

@potts_model Absorbed begin
    @kinds medium cell border[frozen]
    @lattice Lattice((30, 20); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != kind′)
    end
    @fields absorbing (incell => kind == cell, wall => kind == border)
    @sweep Metropolis(; temperature = 8.0)
end

@named absorbed = Absorbed()
σ = zeros(Int32, 30, 20); σ[14:17, 1:20] .= 1; σ[4:8, 8:12] .= 2
prob = PottsProblem(absorbed, [ownership => σ, kind => [:border, :cell]], (0, 20);
    field_solver = ExplicitEuler(substeps = 2))
u = solve(prob, SequentialCPM()).u[end]
(wall = maximum(u.site.c[14:17, :]), low_face = sum(u.site.c[1, :]) / 20)
```

- **Faces.** A face condition sets one face of a closed axis. Its value is a ghost value,
  the missing neighbor of an edge site:

  | Condition (low face of `x`) | Meaning | Ghost value |
  |---|---|---|
  | `c(t, 0, y) ~ v` | `c = v` at the face (Dirichlet) | `2v − c`: the field reaches `v` midway between the edge site and the face |
  | `Differential(x)(c(t, 0, y)) ~ 0` | zero flux | `c`: it mirrors the edge site |
  | `Differential(x)(c(t, 0, y)) ~ -q` | `∂c/∂n = q`, with the outward normal `n` (Neumann) | `c + q h` |
  | `α * c(t, 0, y) - β * Differential(x)(c(t, 0, y)) ~ g` | `α c + β ∂c/∂n = g` (Robin) | the value that meets the condition at the face |

  On the high face the outward normal is `+x`: `Differential(x)(c(t, L, y)) ~ q` is
  `∂c/∂n = q`. A closed axis without a condition is zero flux. A face coefficient that reads
  a field (`DivKGrad(:arithmetic)(c^3, c)`) takes the field's ghost value at the face: with
  `c(t, 0, y) ~ 1.0` and `c = 0` at the edge site, the face mean is `(0³ + 2³)/2`, so the
  field enters through the face. The bound of the field solvers covers these ghost values.
  The harmonic mean of `0³` and `2³` is 0, so `DivKGrad(:harmonic)` keeps a degenerate
  front (`K = 0` where `c = 0`) from moving; use `DivKGrad(:arithmetic)` for degenerate
  diffusion. A condition on a periodic axis, on an axis the lattice lacks, on a hexagonal
  lattice, or on a field whose equation has no spatial operator of it is an error naming
  it. So is a periodic pair on an axis the lattice closes: periodicity is the lattice's,
  for every field.
- **Site masks.** `c ~ masked(condition, v)` is a node value: every explicit substep writes
  `v` at every site where the condition holds (after the `lower` clip, so a mask value
  below `lower` wins), and a fresh initial state (the problem's `u0`, `init`, `reinit!`) is
  clamped too; a state restored from a checkpoint is not (it continues the run exactly),
  nor does `Potts.anneal` clamp. The condition reads the inputs and fields of the
  `PDESystem`. It is evaluated once per MCS before the substeps, so a mask on an input bound
  to a kind (`wall => kind == border`) moves with its cells. The masked sites then take
  their value before the first substep, so a site a cell has just reached holds `v` when
  its neighbors read it. The condition reads the state at the start of its field group's
  window: it is evaluated once, on the clamped values, and held over the MCS. This holds
  for every field it reads, the field it clamps and a field stepped after it included.
  With several solver groups, a field of a group stepped earlier in the MCS reads as
  stepped, as a rate reads another group's field. Write a condition on the field it clamps
  with `>=`, as in `c ~ masked(c >= 0.8, 0.8)`. With `>`, the clamp sets `c = 0.8`,
  `0.8 > 0.8` is false, and the next MCS releases the sites. The masks of a field group
  cost one kernel launch per MCS.
- **Values** of faces and masks are expressions of numbers, parameters, the coordinates
  and `t`: `c(t, 0, y) ~ S1 + S2`, `c(t, 0, y) ~ c0 * sin(ω * t)`,
  `Differential(x)(c(t, L, y)) ~ 0.5y`. A value that is not a number or a number times a
  parameter is computed at each boundary site at the time of each substep.
  `remake(prob; p = [:S => 2.0])` changes a value without regenerating code. The conditions
  themselves are part of the model's identity (the fingerprint): a checkpoint does not
  cross them.
- **Robin coefficients** `α` and `β` are expressions of numbers, parameters, the
  coordinates and `t`, as values are. An expression of parameters alone is one value at
  every site: a computed parameter of the face holds it, named `c_x_low_α` (field, axis,
  side, coefficient), which reads like any computed parameter and is derived again after
  every write. The slot holds `β` as the coefficient of the outward `∂c/∂n`, however the
  face is written: on a low face, `c_x_low_β` is minus the coefficient of `∂c/∂x`.
- A Robin coefficient that reads the coordinates or the time varies by site or in time:
  `(1 + 0.1y) * c(t, 0, y) - Differential(x)(c(t, 0, y)) ~ g`. It is computed at each
  boundary site at the time of each substep. An implicit field with such a face builds its
  operator per site, and rebuilds it at each substep when a coefficient reads the time.
  Where `α` and `β` have opposite signs at a site, that site's part stays out of the
  implicit operator and the Newton iterations correct it. The automatic explicit count
  bounds the face over its sites, and over each step's time span when a coefficient reads
  the time: the count can change from one MCS to the next.
- An initial condition (`c(0, x, y) ~ v`) is the field's initial value, not a boundary
  condition.

`Δ` is a field operator: it appears in `PDESystem` equations, where it reads the faces. In
a model line (site updates, energies, drives, `@observed`) it is an error.
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

`Potts.compose(model, Potts.component(:pk, sys, model))` adds the same system outside the
macro. `Potts.component` gives it the model's kinds and lattice, which a component must have.

### A `PDESystem` as a namespaced component

`@fields` and `Potts.couple` add a `PDESystem` under its own names. To keep its names apart
from the model's, compose it as a component instead: `Potts.compose(model,
Potts.component(:drug, pdesys, model))`. Each dependent variable `c` becomes the field
`drug₊c`, and each parameter `k` the parameter `drug₊k`. The fields run as the others do:
with the problem's `field_solver`, or by name in `FieldGroups(:drug₊c => BackwardEuler())`.

- The domain rule and the initial value are those of `@fields`.
- A component takes no bindings. Each input is filled by its `lattice_input_name` (or else
  its own name), as an unbound input of `@fields` is: `"kind"` is the kind of each site (0
  for the medium), and the name of a field or site variable of the model reads that
  variable.
- A kind table of the `PDESystem` is an error: declare the table in the model.

```@example equations
@parameters Dk = 0.5 kk = 0.1
@variables kin(..)::Int32 [input = true, lattice_input_name = "kind"]
pde = PDESystem([Dt(C) ~ Dk * Δ(C) - kk * C + (kin(t, x, y) == 1)], [],
    lattice_domain(t, (x, y), (30, 30)), [t, x, y], [C, kin(t, x, y)], [Dk, kk]; name = :drug)
withdrug = Potts.compose(dosed, Potts.component(:drug, pde, dosed))
s = solve(PottsProblem(withdrug, layout(Tiling((5, 5); region = (11:20, 11:20), kinds = [:cell]), withdrug), (0, 5)),
    SequentialCPM())
maximum(s.u[end].site.drug₊c)
```

## [The SciML path: `Potts.couple` and `Potts.field_inputs`](@id manual-sciml-path)

`Potts.couple(model, pdesys; inputs = [...])` is `@fields` as a function. It returns
`model` with the fields of `pdesys` under their own names. A binding compares a kind by its
number, which `Potts.lookup(model, :A)` gives:

```@example equations
@potts_model Host begin
    @kinds medium A[frozen]
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(A) => (volume - 16.0)^2
    @sweep Metropolis(; temperature = 4.0)
end
@named host = Host()
@parameters Ds = 0.2 ss = 0.5 ks = 0.1
source = PDESystem([Dt(C) ~ Ds * Δ(C) + ss * endo(t, x, y) - ks * C], [c(0, x, y) ~ 0.0],
    lattice_domain(t, (x, y), (24, 20)), [t, x, y], [C, endo(t, x, y)], [Ds, ss, ks]; name = :source)
coupled = Potts.couple(host, source; inputs = [endo => Potts.kind == Potts.lookup(host, :A)])
nothing # hide
```

The `PDESystem` stays a plain ModelingToolkit system. `Potts.field_inputs(integ)` gives the
current values of its inputs at the CPM state of an integrator, by name
(`Potts.field_inputs(prob)` at the problem's initial state). With them, LatticePDE's
`discretize` builds an `ODEProblem` of the fields, which any SciML solver steps. Here Tsit5
steps one MCS from the field at MCS 5 of a run, and the owned run steps the same MCS with
400 explicit substeps:

```@example equations
using Potts.LatticePDE: discretize, LatticeDiscretization, Grid
σs = zeros(Int32, 24, 20); σs[5:8, 5:8] .= 1; σs[14:17, 10:13] .= 2
integ = init(PottsProblem(coupled, [ownership => σs, kind => [:A, :A]], (0, 6); seed = 3,
    field_solver = ExplicitEuler(; substeps = 400)), SequentialCPM())
for _ in 1:5
    step!(integ)
end
c5 = copy(Array(integ.u.site.c))
fprob = discretize(source, LatticeDiscretization(Grid((24, 20)); T = Float64);
    inputs = collect(Potts.field_inputs(integ)))
fsol = solve(remake(fprob; u0 = vec(c5), tspan = (0.0, 1.0)), Tsit5(); abstol = 1e-11, reltol = 1e-11)
step!(integ)
maximum(abs, reshape(fsol.u[end], 24, 20) .- Array(integ.u.site.c))
```

The difference is the time error of the owned run's 400 explicit substeps.

!!! warning "The SciML path holds the cells fixed"
    The SciML problem carries a snapshot, and two things are not in it:

    - **The cells.** The inputs are a snapshot of one CPM state. The ODE path matches the
      owned run only while σ is frozen, as with the frozen kind `A` here. When the cells
      move, the owned run fills the inputs again at every MCS, and a SciML solve over
      several MCS still reads the snapshot.
    - **The clock.** The solve above starts at MCS 5 with `tspan = (0.0, 1.0)`. In it,
      `step_index(t)` counts from 0, not from 5, and `tspan = (5.0, 6.0)` also counts from
      0. A rate gated on the step index (`ifelse(step_index(t) >= 3, …, 0.0)`) is on in the
      owned run and off in the SciML solve.

A LatticePDE system on its own also takes `lattice_domain`. An input that changes in time
takes a function of the time, `inputs = [q => t -> values]`. A field algorithm writes its
value into the input at the start and at the end of each window. An OrdinaryDiffEq solver
evaluates it at every call of the right side, so it sees the input at each stage time. The
masks that read the input follow. This standalone system has a source that a moving front
switches on:

```@example equations
@parameters Dw = 0.5 kw = 0.1
@variables w(..) front(..) [input = true]
we, fe = w(t, x, y), front(t, x, y)
dom = lattice_domain(t, (x, y), (20, 10); spacing = 0.5, tspan = (0.0, 2.0))
pulse = PDESystem([Dt(we) ~ Dw * Δ(we) - kw * we + fe], [w(0, x, y) ~ 0.0], dom,
    [t, x, y], [we, fe], [Dw, kw]; name = :pulse)
lit(t) = [i <= 10t ? 1.0 : 0.0 for i in 1:20, j in 1:10]   # columns 1 to 10t are on
pprob = discretize(pulse, LatticeDiscretization(Grid((20, 10))); inputs = [fe => lit])
psol = solve(pprob, ExplicitEuler(; dt = 0.1))
round.(psol[we][end][:, 5]; digits = 2)
```

`field_report` gives the substep count of this system and its cause:

```@example equations
Potts.LatticePDE.field_report(pprob, ExplicitEuler(; dt = 0.1))
```
