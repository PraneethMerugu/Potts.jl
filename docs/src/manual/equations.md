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
| `field_solver` | `ExplicitEuler(; substeps, lower)`: `substeps` explicit steps per MCS, values clipped at `lower` | `ExplicitEuler()`: the automatic count, no clip |
| `ode_solver` | `ExplicitEuler(; substeps)`, `RK4(; substeps)`, `Adaptive(alg; kwargs...)` | `ExplicitEuler()`, one step per MCS |
| `solvers` | `[x => solver, …]`, per variable or component | — |

- `substeps = nothing` in a field solver takes the smallest count `n` with
  `mcs_duration / n · ρ ≤ 1.8`, where `ρ` bounds the rate's spectral radius: `D · Σ_d 4/h_d²`
  for diffusion plus the size of the coefficient of `c` in a linear reaction. Indicators
  such as `(kind == medium)` and `ismember(kind, g)` are evaluated at 0 and 1, and a rate
  gated by `ifelse(mcs >= t₀, …, 0)` (a condition that reads no field) is bounded branch
  by branch (the worst branch counts). The count is
  recomputed when parameters change; a number is a minimum. A rate the bound cannot see
  needs `substeps`, and the problem throws an error naming the term without it: a
  reaction that is not linear in `c`, a coefficient that reads other state (a field, `mcs`),
  and a diffusion multiplier that reads a CPM value directly (`volume[owner] * Δ(c)`). So does a
  rate that reads another field (`- Dx * Δ(u)`, `- k * u`) when its row of the Jacobian is
  not diagonally dominant. A diffusion multiplier that varies by site through a kind table
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
  gives `Flux(g / β)`. A closed axis without an entry is zero flux. An entry on a periodic
  axis, on an axis the lattice lacks, on a hexagonal lattice, or on a field whose equation
  has no spatial operator of it is an error naming it.
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
