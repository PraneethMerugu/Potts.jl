# [Developer reference](@id fields-developer)

The public names under the user-facing [API](@ref fields-api): the interface that the Potts
compiler and other front ends build on, and the numerical layer, LatticeFields. A field
model does not need them.

```@contents
Pages = ["developer.md"]
Depth = 2:3
```

## LatticePDE: interface for front ends

```@autodocs
Modules = [Potts.LatticePDE]
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
