# [Fields API](@id fields-api)

Every documented public name of LatticePDE and LatticeFields. `using LatticePDE` brings in
the first four sections; the LatticeFields names are reached as `LatticeFields.Problems.x`
and so on.

```@contents
Pages = ["api.md"]
Depth = 2:3
```

## LatticePDE

```@docs
LatticePDE
```

### Vocabulary

The operators, conditions, reads and variable options a `PDESystem` is written in, and the
checks of a system against them.

```@autodocs
Modules = [LatticePDE]
Private = false
Filter = t -> Main.latticepde_section(t) === :vocabulary
```

### Discretization

```@docs
LatticePDE.Grid
LatticePDE.HEX
```

```@autodocs
Modules = [LatticePDE]
Private = false
Filter = t -> Main.latticepde_section(t) === :discretization
```

### Problems and algorithms

The field algorithms and linear solvers that LatticePDE re-exports from LatticeFields.

```@docs
LatticePDE.ExplicitEuler
LatticePDE.BackwardEuler
LatticePDE.CrankNicolson
LatticePDE.BDF2
LatticePDE.QuasiSteady
LatticePDE.ExplicitMap
LatticePDE.FieldGroups
LatticePDE.LatticeNewton
LatticePDE.LatticePCG
LatticePDE.LatticeGMRES
LatticePDE.LatticeMultigrid
LatticePDE.LatticeBlockSolve
LatticePDE.VCycle
LatticePDE.steady_fields
LatticePDE.field_jacobian_sparsity
```

### Reports

```@docs
LatticePDE.field_report
LatticePDE.substep_counts
LatticePDE.field_series
```

```@autodocs
Modules = [LatticePDE]
Private = false
Filter = t -> Main.latticepde_section(t) === :reports
```

### Interface for front ends

Public names that the Potts compiler and other front ends build on. A field model does
not need them.

```@autodocs
Modules = [LatticePDE]
Private = false
Filter = t -> Main.latticepde_section(t) === :interface
```

## LatticeFields

The numerical layer under LatticePDE. It exports nothing; its submodules declare their
names public.

```@docs
LatticeFields
LatticeFields.isfatal
```

### Problems

```@autodocs
Modules = [LatticeFields.Problems]
Private = false
Filter = t -> !Main.shown_by_latticepde(t)
```

### Solvers

```@autodocs
Modules = [LatticeFields.Solvers]
Private = false
Filter = t -> !Main.shown_by_latticepde(t)
```

### Intermediate representation

```@autodocs
Modules = [LatticeFields.IR]
Private = false
Filter = t -> !Main.shown_by_latticepde(t)
```

### Compilation, schedule and execution

```@autodocs
Modules = [LatticeFields.Compile, LatticeFields.Schedule, LatticeFields.Exec]
Private = false
```
