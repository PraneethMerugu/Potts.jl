# Potts.jl

Cellular Potts models written as equations, in the style of ModelingToolkit, and solved
by SciML-style problems and solvers.

- **Potts** — the authoring surface: `@potts_model`, `PottsProblem`, `@extend`.
- **CorePotts** — the numerical layer: lattices, solvers (`SequentialCPM`,
  `CheckerboardCPM`), solutions, ensembles and callbacks.
- **PottsModels** — published models as ordinary `@potts_model` constructors.
- **MakiePotts** — plotting of states and solutions.

The [Published models](@ref published-models) section reproduces each model's paper from
its public constructor, with a deviations table and a validation table.
