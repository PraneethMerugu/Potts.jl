# [Equations and solvers: `@equations`, `@components`](@id manual-equations)

`@equations` holds differential equations and couplings, in ModelingToolkit syntax. `D` is
the time derivative and `Δ` the lattice Laplacian. The scope of the variable decides what
an equation is:

| Equation | Variable | Meaning | Integrated by |
|---|---|---|---|
| `D(c) ~ Dc * Δ(c) + s * (kind == k) - δ * c` | `c(field)` | a reaction–diffusion PDE on the lattice | `field_solver` |
| `D(x) ~ k₁ - k₂ * x` | `x(cell)` | one ODE per live cell | `ode_solver` |
| `D(g) ~ -g + count(true for c in cells)` | `g(model)` | one ODE for the model | `ode_solver` |
| `comp.p ~ volume / V₀` | a component parameter | a coupling (see below) | — |

The right side of a field equation is a site expression: `kind`, `owner`, `position`,
other fields, kind tables (`δ[kind]`). A cell ODE reads cell quantities (`volume`, cell
variables, `integral(c)`) and can read other cells' values (`y[j]`); every ODE step reads
the state at the start of the step. `time` is the current time.

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
  `mcs_duration / n · (D · Σ_d 4/h_d² + k) ≤ 1.8`, where `k` bounds the reaction's
  `|∂f/∂c|` (the coefficient of `c` in a linear reaction, indicators such as
  `(kind == medium)` and `rand()` counting as 1, a kind table `δ[kind]` as its largest
  entry), recomputed when parameters change; a number is a minimum. A reaction that is not
  linear in `c`, or whose coefficient of `c` reads other state, is not counted (the problem
  warns): give `substeps` yourself.
- Fields are stepped one after another within an MCS, each seeing the others' values from
  the start of its own step. A strong coupling between two fields is therefore split per
  MCS, and it can be unstable however many substeps each field takes; keep such couplings
  weak relative to `1 / mcs_duration`. For the same reason another field's Laplacian
  (`- Dx * Δ(u)` in `D(c)`) is a source term for `c` and does not change its substep count.
- A diffusion coefficient must not be negative: that is anti-diffusion, an ill-posed problem
  whose shortest wavelengths grow without bound under any step (the problem warns).
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
  the missing neighbour of an edge site to `2v − c`, so the field reaches `v` midway between
  the edge site and the face; `NoFlux()` mirrors the edge site. A closed axis without an entry
  is zero flux. An entry on a periodic axis, on an axis the lattice lacks, on a hexagonal
  lattice, or on a field whose equation has no `Δ` of it is an error naming it.
- **Site masks.** `sites(condition) => Dirichlet(v)` is a node value: after every explicit
  substep (after the write and the `lower` clip, before the next rate evaluation) every site
  where the condition holds is set to `v`, and a fresh initial state (the problem's `u0`,
  `init`, `reinit!`) is clamped too; a state restored from a checkpoint is not (it continues
  the run exactly), nor does `Potts.anneal` clamp. The condition is a site expression
  (`kind`, `owner`, site and field variables), evaluated from the state the substep reads,
  so a mask on a kind moves with its cells. It cannot read the field it clamps, or a field
  stepped after it (in the order of `@equations`): that is an error naming it. A clamp costs
  no extra kernel launch. A mask value below `lower` wins.
- **Values** are numbers, parameters or parameter expressions; `remake(prob; p = [:S => 2.0])`
  changes a value without regenerating code. The conditions themselves are part of the
  model's identity (the fingerprint): a checkpoint does not cross them.
- In an extension, a field's `@boundary` replaces the base's for that field.

`Δ(c)` reads the faces wherever the model uses it: equations, site updates, site energies,
drives, constraints and `@observed`.

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
