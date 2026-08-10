# Potts.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://praneethmerugu.github.io/Potts.jl/dev/)

Potts.jl is a Cellular Potts modeling system for Julia. The repository contains three independently
testable Julia packages:

- **PottsToolkit**: the repository-root biological authoring interface.
- **CorePotts**: the scientific execution engine and advanced extension interface.
- **MakiePotts**: native Makie recipes over explicit, host-owned render frames.

The historical `Potts` umbrella package and pre-freeze engine have been removed.

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

The package family supports Julia 1.12 and later Julia 1.x releases. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the complete development commands.

## Documentation

The repository is currently in pre-1.0 authoring and ModelingToolkit hardening. G5H and its product
manual cleared on an exact candidate; LocalWorksets LW-0 is next and G6 remains closed.

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

The complete Learn, Published Models, and API manual builds strictly against the qualified public
interface. There is no compatibility promise for unpublished pre-V1 authoring names.
