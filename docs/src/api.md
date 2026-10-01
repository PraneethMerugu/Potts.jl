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

Published models as `@potts_model` constructors, and their initial states.

```@autodocs
Modules = [PottsModels]
Private = false
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
