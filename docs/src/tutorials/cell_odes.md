# [Tutorial 5: cell ODEs and ModelingToolkit components](@id tutorial-cell-odes)

Potts.jl puts ordinary differential equations (ODEs) inside cells. You write them as plain
equations or as ModelingToolkit systems. Inside each cell, chemistry runs on its own time
scale: a cell-cycle clock, a signaling pathway or a gene network. You will learn:

- how to write a per-cell ODE and a whole-model ODE in `@equations`;
- how to choose the ODE solver of a problem;
- how to put a ModelingToolkit `System` in every cell with `@components`, couple it to the
  cell and let it trigger division;
- (advanced) how to add a Boolean gene network.

The models on this page are generic teaching models.

```@example odes
using Potts, MakiePotts, CairoMakie
CairoMakie.activate!(type = "png") # hide
nothing # hide
```

## A cell-cycle clock as a component

You build a ModelingToolkit model from variables, parameters and equations. Here is a
one-variable cell cycle. The phase `m` grows at rate `r/τ`, so it reaches 1 after `τ` MCS
(Monte Carlo steps) when `r = 1`. Potts provides the time variable `Potts.t` and the
derivative `Potts.D`:

```@example odes
using Potts.ModelingToolkitBase: System, @variables, @parameters

@variables m(Potts.t) = 0.0
@parameters τ = 60.0 r = 1.0
@named cycle = System([Potts.D(m) ~ r / τ], Potts.t)
```

`@components cells(cell) cycle = cycle` gives **every cell** of kind `cell` its own copy of
this system. Inside the model, `cycle.m` is the cell's phase and `cycle.r` its rate:

```@example odes
@potts_model Cycling begin
    @kinds medium cell
    @parameters begin
        λ = 2.0
        V₀ = 25.0
        T = 10.0
        J[kind, kind] = [0 12; 12 6]
    end
    @variables p(cell) = 0.0
    @components cells(cell) cycle = cycle
    @lattice Lattice((60, 60); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cell) => λ * (volume - V₀ * (1 + cycle.m))^2
        contacts => J[kind, kind′]
    end
    @equations begin
        cycle.r ~ volume / V₀           # squeezed cells cycle more slowly
        D(p) ~ 0.1 - 0.05 * p           # a protein made and degraded in every cell
    end
    @divide cells(cell) when = cycle.m >= 1, along = RandomPlane(), cycle.m => 0.0, p => Split()
    @sweep Metropolis(; temperature = T)
end
nothing # hide
```

Three couplings link the clock to the cell:

- **The cell reads the clock.** The target volume `V₀ (1 + m)` doubles over the cycle.
- **The clock reads the cell.** `cycle.r ~ volume / V₀` replaces the parameter `r` by an
  expression of the cell. A compressed cell therefore cycles more slowly.
- **The clock triggers division.** `when = cycle.m >= 1` divides the cell, and
  `cycle.m => 0.0` restarts both daughters' clocks.

`D(p) ~ 0.1 - 0.05 * p` is a plain per-cell ODE for the cell variable `p`. The scope of the
variable decides what the equation is:

- a `cell` variable gives one ODE per cell;
- a `field` gives a PDE;
- a `model` variable gives one ODE for the whole model.

`p => Split()` halves `p` between the daughters.

```@example odes
@named cycling = Cycling()
start = layout(Tiling((5, 5); region = (28:32, 28:32), kinds = [:cell]), cycling)
prob = PottsProblem(cycling, start, (0, 200); seed = 1, capacity = 150)
sol = solve(prob, SequentialCPM(); saveat = 3)
record_potts("cell_odes_cycle.mp4", sol; framerate = 12, title = "", figure = (; size = (420, 420)))
nothing # hide
```

```@raw html
<video src="../cell_odes_cycle.mp4" controls autoplay loop muted playsinline width="420"></video>
```

A component's variables are cell variables named `component₊variable` (the `₊` is typed
`\_+` then Tab). Read them like any other:

```@example odes
phases = sol[:cycle₊m][end]
alive = sol[:volume][end] .> 0
fig = Figure(size = (600, 300))
ax = Axis(fig[1, 1]; xlabel = "cell-cycle phase m", ylabel = "area")
scatter!(ax, phases[alive], sol[:volume][end][alive])
fig
```

The component's uncoupled parameters become model parameters, so `remake` changes them.
For example, `remake(prob; p = [:cycle₊τ => 30.0])` halves the cycle time.

## Choosing the ODE solver

The problem, not the model, chooses how to integrate the ODEs. The default,
`ode_solver = ExplicitEuler()`, takes one Euler time step per MCS. `RK4(substeps = n)` is the
classic fourth-order Runge–Kutta method with `n` time steps per MCS:

```@example odes
prob_rk4 = remake(prob; ode_solver = RK4(substeps = 2))
sol_rk4 = solve(prob_rk4, SequentialCPM())
count(>(0), sol_rk4[:volume][end])
```

`Adaptive(alg; kwargs...)` integrates with any adaptive SciML solver. Use it for stiff or
precise chemistry. Load the solver package first:

```@example odes
using OrdinaryDiffEqTsit5: Tsit5
prob_adaptive = remake(prob; ode_solver = Adaptive(Tsit5(); reltol = 1e-8))
sol_adaptive = solve(prob_adaptive, SequentialCPM())
count(>(0), sol_adaptive[:volume][end])
```

`solvers = [p => RK4(substeps = 4)]` gives one variable (or one component, `cycle`) its
own solver. The rest use `ode_solver`. Changing a solver regenerates the code, which takes
a moment. Changing parameters does not regenerate the code.

!!! note "Time units"
    By default, one MCS is one unit of ODE time. To match the rates of a published ODE
    model, change this with `mcs_duration`. `@sweep Metropolis(; temperature = T,
    mcs_duration = 0.5)` makes one MCS half a time unit.

## A model-level ODE

A `model` variable is a single number for the whole model. Its equation can read
**population folds** such as `count(true for c in cells)`, the number of live cells:

```@example odes
@potts_model Signalling begin
    @extend base = Cycling()
    @variables g(model) = 0.0
    @equations D(g) ~ 0.01 * count(true for c in cells) - 0.1 * g
end

@named signalling = Signalling()
prob_g = PottsProblem(signalling, start, (0, 200); seed = 1, capacity = 150)
sol_g = solve(prob_g, SequentialCPM(); saveat = 2)
fig = Figure(size = (600, 300))
ax = Axis(fig[1, 1]; xlabel = "MCS", ylabel = "g")
lines!(ax, sol_g.t, sol_g[:g])
fig
```

`@components model drug = sys` adds one instance of a ModelingToolkit system to the whole
model. An example is a pharmacokinetic model whose dose depends on the cell count.

## Advanced: a Boolean gene network

!!! warning "Advanced"
    This section uses discrete-time ModelingToolkit systems. Skip it on a first reading.

A discrete-time ModelingToolkit system with a `ShiftIndex` clock is a Boolean (or any
discrete) network. It updates once per MCS. `A(k)` is the new value and `A(k - 1)` the
previous one. Here `B` follows `A`. `A` switches on when the input `on` is true and `B` was
off. The pair therefore oscillates once the cell's signal arrives:

```@example odes
using Potts.ModelingToolkitBase: ShiftIndex
k = ShiftIndex(Potts.t, 0)
@variables A(Potts.t)::Bool = false B(Potts.t)::Bool = true
@parameters on::Bool = false
@named grn = System([A(k) ~ on & !B(k - 1), B(k) ~ A(k - 1)], Potts.t)

@potts_model GeneSwitch begin
    @kinds medium cell
    @variables signal(cell) = 0.0
    @components cells(cell) grn = grn
    @lattice Lattice((30, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cell) => (volume - 25.0)^2
        contacts => 10 * (kind != kind′)
    end
    @equations grn.on ~ signal > 0.5
    @after_mcs signal ~ ifelse(mcs > 5, 1.0, 0.0)
    @sweep Metropolis(; temperature = 5.0)
end

@named switch = GeneSwitch()
op = layout(Tiling((5, 5); region = (11:15, 11:15), kinds = [:cell]), switch)
sol_grn = solve(PottsProblem(switch, op, (0, 15)), SequentialCPM(); saveat = 1)
[Int(x[1]) for x in sol_grn[:grn₊A]]     # A of cell 1 at each MCS
```

Potts.jl stores the network nodes as 0/1 cell variables. A node can trigger division
(`when = grn.A & (volume > 40)`). You can also couple nodes to continuous components.

## What you learned

- `D(x) ~ …` in `@equations` is a per-cell ODE for a `cell` variable and a global ODE for a
  `model` variable.
- `@components cells(k) name = sys` puts a ModelingToolkit system in every cell. Couple it
  with `name.param ~ expression` and read it as `name.var`.
- The problem chooses the integrator: `ode_solver = ExplicitEuler()`, `RK4(substeps = n)` or
  `Adaptive(alg)`, and `solvers = [...]` per variable.

Next, [Tutorial 6](@ref tutorial-links) links cells together.
