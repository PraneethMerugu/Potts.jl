# Potts.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://praneethmerugu.github.io/Potts.jl/dev/)

Potts.jl is a Cellular Potts modeling system for Julia. The repository contains three independently
testable user-facing packages:

- **PottsToolkit**: the repository-root biological authoring interface.
- **CorePotts**: the scientific execution engine and advanced extension interface.
- **MakiePotts**: native Makie recipes over explicit, host-owned render frames.

The historical `Potts` umbrella package and pre-freeze engine have been removed. ProcessBigraphs
is developed separately as an internal runtime foundation; its incubation status is not a public
Potts runtime or parity claim.

## Installation

Until the package family is registered, install PottsToolkit directly from the repository root:

```julia
using Pkg
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl", subdir = "lib/CorePotts")
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl")
```

CorePotts is installed explicitly because user scripts import it directly for execution. Add the
`lib/MakiePotts` subdirectory as a direct dependency when using visualization.

For development:

```julia
using Pkg
Pkg.develop(path="lib/CorePotts")
Pkg.develop(path=".")
```

The development, test, benchmark, documentation, and evidence target is Julia 1.12.6.

## Documentation

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

The manual is organized as Learn, Examples, Published Models, Concepts and Guarantees, and API.
Documentation builds are strict and executable. API compatibility is assigned by curated
inventories and guarantee metadata, not merely by whether a name is exported.
