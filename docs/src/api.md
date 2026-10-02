# [API](@id api)

Every documented public name of the packages. Potts re-exports CorePotts, so
`using Potts` is enough for everything in the first two sections.

```@contents
Pages = ["api.md"]
Depth = 2
```

## Potts

The modelling language: `@potts_model`, `PottsProblem` for symbolic models, layouts,
solver specifications.

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
