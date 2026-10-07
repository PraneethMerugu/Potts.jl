# [API](@id api)

Every documented public name of the packages. Potts re-exports CorePotts, so
`using Potts` is enough for everything in the first two sections.

```@contents
Pages = ["api.md"]
Depth = 2
```

## Potts

The modelling language: `@potts_model`, `PottsProblem` for symbolic models, layouts,
solver specifications, and measurements of a state: `total_energy` and the public, not
exported, `Potts.boundary_lengths` and `Potts.anneal` (see [Boundary lengths and annealed
states](@ref manual-analysis)).

The sweep's definition is visible to ModelingToolkit's generic tools.
`Potts.hamiltonian(sys)` gives the `@energy` terms as `domain => expr` pairs of Symbolics
expressions, `Potts.drives(sys)` gives the `@drive` expressions, and MTK's
`ModelingToolkitBase.constraints(sys)` gives the `@constraint` entries. Generic code detects
a Potts model, and reads its sweep, with MTK's metadata API:

```julia
using ModelingToolkitBase: getmetadata, hasmetadata
hasmetadata(sys, Potts.PottsSweepSpec)               # true for every Potts model, false for a System
spec = getmetadata(sys, Potts.PottsSweepSpec, nothing)
spec.hamiltonian, spec.drives, spec.constraints, spec.temperature, spec.proposal
```

The payload is a description: a Potts model is still solved through `PottsProblem`, and
`ODEProblem`/`JumpProblem` of a Potts model are `ArgumentError`s.

The update rules are visible the same way. `Potts.updates(sys)` lists every `@before_mcs`,
`@after_mcs` and `@on_copy` statement as written, with its phase, the scope of the variable
it writes, its cadence (a `Potts.Every`) and its `Equation` in ModelingToolkit's `Pre` form:

```julia
for u in Potts.updates(sys)
    println(u.phase, " ", u.scope, " ", u.every, ": ", u.eq)   # e.g. after_mcs cell Every(1): x ~ Pre(x) + 1
end
```

Potts compiles and runs these rules in its sweep; they are not ModelingToolkit events, so
`ModelingToolkitBase.discrete_events(sys)` is empty.

A model's cell and model ODEs are ModelingToolkit systems compiled by `mtkcompile`.
`Potts.ode_system(csys, :cell)` and `Potts.ode_system(csys, :model)` return them from a
compiled model `csys` (see [Equations and solvers](@ref manual-equations)).

```@autodocs
Modules = [Potts]
Private = false
```

## CorePotts

The numerical layer: lattices and relations, the algorithms, solutions, ensembles,
callbacks and checkpoints.

```@autodocs
Modules = [CorePotts]
Private = false
```

## PottsModels

Published models as `@potts_model` constructors, and their initial states. The model
constructors and their state functions are documented on their [Models](@ref models) pages.

```@autodocs
Modules = [PottsModels]
Private = false
Filter = t -> !Main.on_model_page(t)
```

## PottsModels.Analysis

```@autodocs
Modules = [PottsModels.Analysis]
Private = false
```

## MakiePotts

Plotting and videos of states and solutions.

```@autodocs
Modules = [MakiePotts]
Private = false
```
