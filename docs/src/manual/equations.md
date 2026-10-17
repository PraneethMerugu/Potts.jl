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
| `y ~ volume / V₀` | `y(cell)` or `y(model)` | an algebraic variable (see below) | — |
| `comp.p ~ volume / V₀` | a component parameter | a coupling (see below) | — |

The right side of a field equation is a site expression: `kind`, `owner`, `position`,
other fields, kind tables (`δ[kind]`). A cell ODE reads cell quantities (`volume`, cell
variables, `integral(c)`) and can read other cells' values (`y[j]`); every ODE step reads
the state at the start of the step. `time` is the current time.

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
| `field_solver` | `ExplicitEuler(; substeps, lower)`: `substeps` explicit steps per MCS, values clipped at `lower` | none: required when the model has a field |
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
  reaction that is not linear in `c`, a coefficient that reads a kind table or other state,
  and a diffusion multiplier that varies by site (`ismember(kind, g) * Δ(c)`). So does a
  rate that reads another field (`- Dx * Δ(u)`, `- k * u`) when its row of the Jacobian is
  not diagonally dominant. With `substeps = n` in these cases the count is the larger of
  `n` and the bound of the terms the bound sees (diffusion at least), and the problem warns
  once, naming the terms it does not cover.
- Fields with the same solver step together, substep by substep: a field reads the fields
  it depends on after their update, and fields that depend on each other read each other's
  values from the start of the substep. Fields with different solvers (`solvers = [u =>
  ExplicitEuler(substeps = 4)]`) step one group after another, each reading the others'
  arrays. A strong coupling between two groups is split per MCS and can be unstable however
  many substeps each takes; keep it weak relative to `1 / mcs_duration`.
- The CPM quantities in a field equation (`kind`, cell reads, neighbor counts) are evaluated
  once per MCS, before the fields step, and held over the substeps; so is `mcs`. `rand()`
  cannot appear in a field equation: draw in a site update and read its variable.
- On a hexagonal lattice, `Δ` is the only spatial operator. On a lattice with a `domain`,
  the fields live in the domain: a site outside it keeps its value, and the domain's edge
  has zero flux. Face values still apply at the faces of the box.
- A diffusion coefficient must not be negative: that is anti-diffusion, an ill-posed problem
  whose shortest wavelengths grow without bound under any step. The problem throws an
  error at build, or at the next MCS after a parameter change makes it negative.
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
  axis, each `Dirichlet(v)` or `NoFlux()`. A face value is a ghost value: `Dirichlet(v)` sets
  the missing neighbor of an edge site to `2v − c`, so the field reaches `v` midway between
  the edge site and the face; `NoFlux()` mirrors the edge site. A closed axis without an entry
  is zero flux. An entry on a periodic axis, on an axis the lattice lacks, on a hexagonal
  lattice, or on a field whose equation has no `Δ` of it is an error naming it.
- **Site masks.** `sites(condition) => Dirichlet(v)` is a node value: every explicit
  substep writes `v` at every site where the condition holds (after the `lower` clip, so a
  mask value below `lower` wins), and a fresh initial state (the problem's `u0`, `init`,
  `reinit!`) is clamped too; a state restored from a checkpoint is not (it continues the run
  exactly), nor does `Potts.anneal` clamp. The condition is a site expression (`kind`,
  `owner`, site and field variables), evaluated once per MCS before the substeps, so a mask
  on a kind moves with its cells. It cannot read the field it clamps, or a field stepped
  after it (in the order of `@equations`): that is an error naming it. The masks of a field
  group cost one kernel launch per MCS.
- **Values** are numbers, parameters or parameter expressions; `remake(prob; p = [:S => 2.0])`
  changes a value without regenerating code. The conditions themselves are part of the
  model's identity (the fingerprint): a checkpoint does not cross them.
- In an extension, a field's `@boundary` replaces the base's for that field.

`Δ(c)` is a field operator: it appears in field equations (`D(c) ~ …`), where it reads the
faces. Anywhere else (site updates, energies, drives, `@observed`) it is an error.

`@bcs` takes raw MTK boundary conditions, one per line (for example
`c ~ masked(kind == border, 0.0)`). In this release they are stored in the model and printed
with it; they do not change the run. The field compiler reads them in a later release.

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
