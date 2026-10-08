# [Relation to ModelingToolkit](@id modelingtoolkit)

This page states exactly what Potts.jl takes from
[ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/) (MTK) and what it does
itself. Each claim below comes with the public function that makes it true and a short
example that you can run. The acceptance test
`lib/PottsModels/test/acceptance/p6_0bs_mtk_claims.jl` checks every claim on every
published model, and checks that this page keeps saying them. The test's testset for a
claim is given in brackets, e.g. [C1].

## The claim in brief

Potts.jl is built on ModelingToolkit. Every Potts model is a ModelingToolkit system: an
`AbstractSystem` whose parameters, state variables, equations, observables, update rules
and Hamiltonian are Symbolics expressions that ModelingToolkit's generic tools can
inspect, index and complete. The continuous parts of a model, its cell- and model-scale
ODEs, are ModelingToolkit systems compiled by `mtkcompile`; Potts.jl lowers the simplified
equations into its batched kernels. Entity-local initialization equations are
ModelingToolkit initialization systems, solved per cell by MTK's `InitializationProblem`.
Existing ModelingToolkit models plug in as components, continuous ones and clocked ones.
The stochastic lattice dynamics, a Markov operator over cell ownership with no equation
form in ModelingToolkit, are compiled from the symbolic Hamiltonian by Potts.jl's own code
generator into fused CPU and GPU kernels. This is the same division of labour Catalyst
uses for spatial reaction networks.

## One model with every part

The examples on this page use one small model. It has a cell ODE with an algebraic
variable, a model ODE, a diffusing field, an update rule, an initialization equation and a
ModelingToolkit component in every cell:

```@example mtk
using Potts
using Potts.ModelingToolkitBase: System, @variables, @parameters

@variables y(Potts.t) = 1.0
@parameters kc = 0.1
@named decay = System([Potts.D(y) ~ -kc * y], Potts.t)   # an ordinary MTK model

@potts_model AllParts begin
    @kinds medium A
    @parameters begin
        k = 0.1
        r = 0.2
        Dc = 0.1
    end
    @variables begin
        x(cell) = 2.0
        excess(cell) = 0.0
        m(model) = 0.0
        gap(model) = 0.0
        acc(cell) = 0.0
        c(field) = 0.0
        rt(cell), [guess = 1.0]
    end
    @components cells(A) decay = decay
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(x) ~ -k * excess
        excess ~ x                     # algebraic: eliminated by mtkcompile
        D(m) ~ r * gap
        gap ~ 1 - m
        D(c) ~ Dc * Δ(c) - 0.1 * c     # a field PDE, stepped by Potts
    end
    @initialization_equations rt^2 ~ volume
    @after_mcs acc ~ Pre(acc) + excess
    @sweep Metropolis(; temperature = 1.0)
end

@named sys = AllParts()
σ = zeros(Int32, 12, 8); σ[3:6, 3:6] .= 1; σ[7:10, 3:5] .= 2   # cells of 16 and 12 sites
prob = PottsProblem(sys, [ownership => σ, kind => [:A, :A]], (0, 5);
    seed = 3, field_solver = ExplicitEuler(substeps = 2))
nothing # hide
```

## A model is an `AbstractSystem` [C1, C2]

A Potts model is a `PottsSystem`, a subtype of ModelingToolkit's `AbstractSystem`. It is
not MTK's concrete `System`: a Potts model carries a lattice, kinds and a sweep, which a
`System` has no place for.

```@example mtk
const MTK = Potts.ModelingToolkitBase
(sys isa MTK.AbstractSystem, sys isa MTK.System, MTK.iscomplete(complete(sys)))
```

MTK's own accessors work on it and return Symbolics objects:

```@example mtk
MTK.parameters(sys)
```

```@example mtk
MTK.equations(sys)
```

`MTK.unknowns`, `MTK.observed`, `nameof`, `complete` and `extend` work too.
SymbolicIndexingInterface (SII) indexes a problem, a solution and an integrator by name,
including an algebraic variable that is not stored:

```@example mtk
using Potts.SymbolicIndexingInterface: getp, getu
sol = solve(prob, SequentialCPM(); saveat = 1)
(k = getp(prob, :k)(prob), x = getu(sol, :x)(sol)[end], excess = sol[:excess][end])
```

## The Hamiltonian as Symbolics expressions [C3]

`Potts.hamiltonian(sys)` gives the `@energy` terms as `domain => expr` pairs of Symbolics
expressions; `Potts.drives(sys)` and `MTK.constraints(sys)` give the drives and the
constraints. Generic code reads the whole sweep definition through MTK's metadata API:

```@example mtk
Potts.hamiltonian(sys)
```

```@example mtk
spec = MTK.getmetadata(sys, Potts.PottsSweepSpec, nothing)
(MTK.hasmetadata(sys, Potts.PottsSweepSpec), MTK.hasmetadata(decay, Potts.PottsSweepSpec),
 isequal(spec.hamiltonian, Potts.hamiltonian(sys)))
```

## Cell and model ODEs through `mtkcompile` [C4]

`Potts.ode_system(csys, :cell)` and `Potts.ode_system(csys, :model)` return the
ModelingToolkit `System` that `mtkcompile` produced from a compiled model `csys` (`nothing`
for a scope without ODEs). The algebraic variable `excess` is one of its `observed`
equations, not an unknown, and the problem does not store it:

```@example mtk
csys = mtkcompile(sys)
o = Potts.ode_system(csys, :cell)
(MTK.isscheduled(o), MTK.unknowns(o), MTK.observed(o))
```

```@example mtk
propertynames(prob.u0.cell)
```

Potts then lowers these simplified equations into one batched kernel that steps every
cell at once (see [Equations and solvers](@ref manual-equations)).

## Components [C5]

A ModelingToolkit `System` given to `@components` goes through `mtkcompile` like any MTK
model. Only its unknowns after simplification become cell variables (here `decay₊y`, one
per cell), and a clocked system with a `ShiftIndex` goes through MTK's discrete pass (see
[Tutorial 5](@ref tutorial-cell-odes)):

```@example mtk
sol[:decay₊y][end]
```

## Update rules in MTK's `Pre` form [C6]

A model's update rules are Symbolics equations in ModelingToolkit's `Pre` form that MTK's
generic tools can inspect. `Potts.updates(sys)` lists each `@before_mcs`, `@after_mcs` and
`@on_copy` statement with its phase, scope and cadence:

```@example mtk
u = only(Potts.updates(sys))
(u.phase, u.scope, u.every, u.eq)
```

Update rules are not ModelingToolkit events: Potts compiles and runs them in its sweep,
and `MTK.discrete_events(sys)` and `MTK.continuous_events(sys)` are empty:

```@example mtk
(MTK.discrete_events(sys), MTK.continuous_events(sys))
```

## Initialization per cell [C7]

`Potts.initialization_system(csys, :cell)` is a complete `System` whose
`initialization_equations` are the model's `@initialization_equations`, with inputs such
as `volume` as its parameters. When a problem is built, Potts solves MTK's
`InitializationProblem` of that system for every cell. Here `rt = √volume`, so the two
cells start with different values:

```@example mtk
isys = Potts.initialization_system(csys, :cell)
(MTK.initialization_equations(isys), prob.u0.cell.rt)
```

Cross-entity and lattice initialization stay in Potts' own initialization phase (see
[Variables](@ref manual-variables)).

## What ModelingToolkit does not do

- **It does not simulate the CPM sweep** [C9]. `mtkcompile` of a Potts model is Potts'
  own method and returns a `CompiledPottsSystem`, not an MTK `System`. A Potts model is
  solved through `PottsProblem`; MTK's `ODEProblem` and `JumpProblem` of a Potts model are
  `ArgumentError`s that point there:

  ```@example mtk
  try
      MTK.ODEProblem(sys, [], (0.0, 1.0))
  catch err
      sprint(showerror, err)
  end
  ```

- **Fields are not compiled by MTK** [C8]. A field PDE is a Symbolics equation that
  `MTK.equations` lists, but it is in no ModelingToolkit system: Potts steps it on the
  lattice with the problem's `field_solver`, and `Potts.ode_system(csys, :field)` is an
  `ArgumentError`.

- **Update rules are not MTK events** [C6]. They are compiled and run by Potts, so a
  reader of `MTK.discrete_events` sees none.

These are the current limits, not promises. Keeping update rules as ModelingToolkit
callbacks (`SymbolicDiscreteCallback`) is planned for step P6.4c, and cross-entity
initialization through MTK for P6.4a. When either lands, the acceptance test and this
page change with it.
