# [Equations and solvers: `@fields`, `@equations`, `@components`](@id manual-equations)

A model holds two kinds of equations:

- **Fields** are reaction–diffusion PDEs on the lattice. Each comes from a ModelingToolkit
  `PDESystem`, which `@fields` couples into the model (`Potts.couple` outside the macro).
- **Cell and model equations** are ODEs, algebraic equations and couplings in `@equations`,
  in ModelingToolkit syntax. `D` is the time derivative.

| Equation | Where | Meaning | Integrated by |
|---|---|---|---|
| `Dt(c) ~ Dc * laplacian(c) + s * src - δ * c` | a `PDESystem` | a reaction–diffusion PDE on the lattice | `field_solver` |
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
using Potts.Layouts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
using Potts.LatticePDE: laplacian, lattice_domain

t = Potts.t
Dt = Differential(t)
@parameters x y Dc = 0.2 s = 0.5 kd = 0.1 av = 0.01
@variables c(..) = 0.0 endo(..)::Bool [input = true] vol(..) [input = true]
C = c(t, x, y)
attractant = PDESystem([Dt(C) ~ Dc * laplacian(C) + s * endo(t, x, y) - kd * C + av * vol(t, x, y)], [],
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
sol = solve(PottsProblem(secreting, [ownership => σ, kind => [:A, :A]], (0, 12); seed = 3), SequentialCPM(); save_everystep = false)
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
  the problem's `tspan` is. A field wraps on the lattice's periodic axes and is closed on
  its closed axes, unless its own conditions say otherwise (see Boundary conditions).
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
actin = PDESystem([Dt(F(t, x, y)) ~ D_F * laplacian(F(t, x, y)) - k_decay * F(t, x, y) + k_source * edge(t, x, y)], [],
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
chemical = PDESystem([Dt(C) ~ Dc * laplacian(C) + 0.1 * incell(t, x, y) - 0.05 * C], [],
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
        contacts => 8.0 * (kind != neighbor_kind)
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
prob = PottsProblem(chem, op, (0, 50); field_solver = ExplicitEuler(substeps = 4, lower_bound = 0.0))
sol = solve(prob, SequentialCPM(); save_everystep = false)
sol[:q][end], sol[:g][end]
```

| Keyword | Values | Default |
|---|---|---|
| `field_solver` | `ExplicitEuler(; substeps, lower_bound)`: `substeps` explicit steps per MCS, values clipped at `lower_bound`; `BackwardEuler(; substeps, nlsolve, lower_bound, linsolve, solver_type)`: implicit steps, each a linear solve with `linsolve`; `CrankNicolson(…)`, `BDF2(…)`: second-order implicit steps, the same keywords; `QuasiSteady(; nlsolve, linsolve, solver_type)`: the steady state in each MCS; each takes `init = :steady` (a steady start) and `compute_type` (`Float32` or `Float64`: the number type its kernels compute in; default the problem's `T`) | `ExplicitEuler()`: the automatic count, no clip |
| `ode_solver` | `ExplicitEuler(; substeps)`, `Potts.RK4(; substeps)`, `Adaptive(alg; kwargs...)` | `ExplicitEuler()`, one step per MCS |
| `solvers` | `[x => solver, …]`, per variable or component | — |

[Solvers](@ref fields-solvers) gives the linear solvers, the implicit steppers, the
Newton modes and the rules for substep counts and groups. In a Potts model the window of
those rules is one MCS times `mcs_duration`. These rules hold only in a Potts model:

- The inputs of a field (`kind`, bound cell reads, neighbor counts) are filled once per MCS,
  before the fields step, and held over the substeps; so is `mcs`. `t` advances with the
  substeps. A field equation has no draws. `rand()` written in a `PDESystem` equation is
  Julia's `rand()`: it is evaluated once, when the equation is built, and the field reads
  that one number at every site and every step. For a random source, draw in a site update
  (`@after_mcs s ~ rand()`) and read `s` as an input.
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
prob2 = remake(prob; ode_solver = Adaptive(Tsit5(); reltol = 1e-8), solvers = [:g => Potts.RK4(substeps = 4)])
solve(prob2, SequentialCPM(); save_everystep = false).retcode
```

`field_report` of an integrator of the first model on this page (`secreting`) gives the
substep count of its field `c` and its cause, the bound, and the counters of three MCS:

```@example equations
integ = init(PottsProblem(secreting, [ownership => σ, kind => [:A, :A]], (0, 12); seed = 3), SequentialCPM(); save_everystep = false)
for _ in 1:3
    step!(integ)
end
field_report(integ)
```

The time step is one MCS times `mcs_duration` (default 1), set in `@sweep`.

## Boundary conditions

A field's boundary conditions are the conditions of its `PDESystem`, its second argument.
A field is read at a face by its coordinates, with one of them fixed: `c(t, 0, y)` is the
low face of `x`, and `c(t, Lx, y)` the high face, with `Lx` the extent of `x` in the
domain:

```@example equations
using Potts.LatticePDE: masked
@parameters Dd = 0.2 S = 1.0
@variables wall(..)::Bool [input = true]
adom = lattice_domain(t, (x, y), (30, 20))
Lx = maximum(adom[2].domain)                 # 30.0, from the domain
absorbing = PDESystem([Dt(C) ~ Dd * laplacian(C) + 0.1 * incell(t, x, y)],
    [c(t, 0, y) ~ S,                         # the low x face held at S
     Differential(x)(c(t, Lx, y)) ~ 0,       # the high x face closed
     C ~ masked(wall(t, x, y), 0.0)],        # an absorbing obstacle
    adom, [t, x, y], [C, incell(t, x, y), wall(t, x, y)], [Dd, S]; name = :absorbing)

@potts_model Absorbed begin
    @kinds medium cell border[frozen]
    @lattice Lattice((30, 20); boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        Volume(cell; target = 25.0, strength = 1.0)
        contacts => 8.0 * (kind != neighbor_kind)
    end
    @fields absorbing (incell => kind == cell, wall => kind == border)
    @sweep Metropolis(; temperature = 8.0)
end

@named absorbed = Absorbed()
σ = zeros(Int32, 30, 20); σ[14:17, 1:20] .= 1; σ[4:8, 8:12] .= 2
prob = PottsProblem(absorbed, [ownership => σ, kind => [:border, :cell]], (0, 20);
    field_solver = ExplicitEuler(substeps = 2))
u = solve(prob, SequentialCPM(); save_everystep = false).u[end]
(wall = maximum(u.site.c[14:17, :]), low_face = sum(u.site.c[1, :]) / 20)
```

[Boundary conditions](@ref fields-boundaries) gives the face conditions, their values,
Robin faces and site masks. In a Potts model they work as on their own, with these
additions:

- **The lattice sets the default.** A closed axis without a condition is zero flux. A
  site variable or a field with no condition that a spatial operator reads
  (`laplacian(v)`) has zero-flux faces on each closed axis, and wraps on each periodic
  axis.
- **A field can differ from the lattice.** A periodic pair (`c(t, x, 0) ~ c(t, x, L)`)
  makes that field wrap on that axis, also where the lattice is closed. A face condition
  on an axis the lattice wraps closes that field there; the other fields still wrap.
  [Periodicity per field](@ref fields-how-periodicity) gives the rules for reads across
  fields that wrap differently.
- **A mask moves with the cells.** The condition is evaluated once per MCS, before the
  substeps, so a mask on an input bound to a kind (`wall => kind == border`) moves with
  its cells. A site that a cell has just reached holds `v` when its neighbors read it.
  `Potts.anneal` does not clamp.
- **The conditions are part of the model's identity** (the fingerprint): a checkpoint
  does not cross them.

`laplacian` is a field operator: it appears in `PDESystem` equations, where it reads the faces. In
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
        contacts => 8.0 * (kind != neighbor_kind)
    end
    @sweep Metropolis(; temperature = 8.0)
end
@named dosed = Dosed()
s = solve(PottsProblem(dosed, layout(Tiling((5, 5); region = (11:20, 11:20), kinds = [:cell]), dosed), (0, 20)),
    SequentialCPM(); save_everystep = false)
s[:pk₊drug][end]
```

`compose(model, Potts.component(:pk, sys, model))` adds the same system outside the
macro. `Potts.component` gives it the model's kinds and lattice, which a component must have.

### A `PDESystem` as a namespaced component

`@fields` and `Potts.couple` add a `PDESystem` under its own names. To keep its names apart
from the model's, compose it as a component instead: `compose(model,
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
pde = PDESystem([Dt(C) ~ Dk * laplacian(C) - kk * C + (kin(t, x, y) == 1)], [],
    lattice_domain(t, (x, y), (30, 30)), [t, x, y], [C, kin(t, x, y)], [Dk, kk]; name = :drug)
withdrug = compose(dosed, Potts.component(:drug, pde, dosed))
s = solve(PottsProblem(withdrug, layout(Tiling((5, 5); region = (11:20, 11:20), kinds = [:cell]), withdrug), (0, 5)),
    SequentialCPM(); save_everystep = false)
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
source = PDESystem([Dt(C) ~ Ds * laplacian(C) + ss * endo(t, x, y) - ks * C], [c(0, x, y) ~ 0.0],
    lattice_domain(t, (x, y), (24, 20)), [t, x, y], [C, endo(t, x, y)], [Ds, ss, ks]; name = :source)
coupled = Potts.couple(host, source; inputs = [endo => Potts.kind == Potts.lookup(host, :A)])
nothing # hide
```

The `PDESystem` stays a plain ModelingToolkit system. `Potts.fields(coupled)` is the
`PDESystem` of the model's fields: the equations of `source`, with each binding written in
as its CPM input (`endo` becomes `kind == 1`, read from the input `kind`).
`Potts.field_inputs(integ)` gives the current values of those inputs at the CPM state of an
integrator, by the names `Potts.fields` gives them (`Potts.field_inputs(prob)` at the
problem's initial state). `Potts.field_inputs(integ, source)` gives the inputs of `source`
itself instead (`endo`, its binding's truth value at each site), for `discretize(source, …)`.
With them, LatticePDE's `discretize` builds an `ODEProblem` of the fields, which any SciML
solver steps. Here Tsit5 steps one MCS from the field at MCS 5 of a
run, and the owned run steps the same MCS with 400 explicit substeps:

```@example equations
using Potts.LatticePDE: discretize, LatticeDiscretization, Grid
σs = zeros(Int32, 24, 20); σs[5:8, 5:8] .= 1; σs[14:17, 10:13] .= 2
integ = init(PottsProblem(coupled, [ownership => σs, kind => [:A, :A]], (0, 6); seed = 3,
    field_solver = ExplicitEuler(; substeps = 400)), SequentialCPM(); save_everystep = false)
for _ in 1:5
    step!(integ)
end
c5 = copy(Array(current_state(integ).site.c))
fprob = discretize(Potts.fields(coupled), LatticeDiscretization(Grid((24, 20)); T = Float64);
    inputs = collect(Potts.field_inputs(integ)))
fsol = solve(remake(fprob; u0 = vec(c5), tspan = (0.0, 1.0)), Tsit5(); abstol = 1e-11, reltol = 1e-11)
step!(integ)
maximum(abs, reshape(fsol.u[end], 24, 20) .- Array(current_state(integ).site.c))
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

[SciML interop](@ref fields-sciml) shows a field system on its own: inputs that change in
time, sparse Jacobians and the integrator.
