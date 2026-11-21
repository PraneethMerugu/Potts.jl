# [Fields API](@id fields-api)

Every exported name of LatticePDE: what `using LatticePDE` brings in. The public names
that front ends and solver authors build on are on the
[Developer reference](@ref fields-developer).

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
Modules = [Potts.LatticePDE]
Private = false
Filter = t -> Main.latticepde_section(t) === :vocabulary
```

### Discretization

```@docs
LatticePDE.Grid
LatticePDE.HEX
```

```@autodocs
Modules = [Potts.LatticePDE]
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
Modules = [Potts.LatticePDE]
Private = false
Filter = t -> Main.latticepde_section(t) === :reports
```

### Re-exported names

LatticePDE re-exports the SciML calls that a field model uses, so `using LatticePDE` is
enough to solve one: `solve`, `solve!`, `init` and `step!` (CommonSolve), `remake`
(SciMLBase), `getp`, `getu` and `setp` (SymbolicIndexingInterface), and `Interval`
(IntervalSets), for a domain such as `x ∈ Interval(0.0, 1.0)`. Their docstrings are in
those packages.
