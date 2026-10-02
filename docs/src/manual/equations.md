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

- `substeps = nothing` in a field solver takes the smallest stable count for the diffusion
  term alone, recomputed when parameters change; a number is a minimum. Leave a margin for
  reaction terms.
- `Adaptive(alg; reltol, abstol, …)` integrates cell and model ODEs on the host with any
  SciML ODE algorithm (load its package, e.g. OrdinaryDiffEqTsit5). Equations with
  `rand()` cannot be integrated adaptively.
- `remake(prob; ode_solver = …)` regenerates the code with the new solver and keeps the
  state, parameters and seed.

```@example equations
prob2 = remake(prob; ode_solver = Adaptive(Tsit5(); reltol = 1e-8), solvers = [:g => RK4(substeps = 4)])
solve(prob2, SequentialCPM()).retcode
```

The time step is one MCS times `mcs_duration` (default 1), set in `@sweep`.

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
