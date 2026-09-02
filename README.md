# Potts.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://praneethmerugu.github.io/Potts.jl/dev/)

Potts.jl is a Cellular Potts modeling system for Julia. The repository contains four independently
testable Julia packages:

- **Potts**: the repository-root biological authoring interface.
- **CorePotts**: the scientific execution engine and advanced extension interface.
- **LocalMath**: the backend-portable local execution substrate used internally by CorePotts.
- **MakiePotts**: native Makie recipes over explicit, host-owned render frames.

The historical `Potts` umbrella package and pre-freeze engine have been removed.

## Installation

Until the package family is registered, install Potts directly from the repository root:

```julia
using Pkg
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl", subdir = "lib/LocalMath")
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl", subdir = "lib/CorePotts")
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl")
```

The unregistered CorePotts dependency resolves LocalMath explicitly; user scripts import
CorePotts directly for execution. Add the `lib/MakiePotts` subdirectory as a direct dependency
when using visualization.

For development:

```julia
using Pkg
Pkg.develop(path="lib/LocalMath")
Pkg.develop(path="lib/CorePotts")
Pkg.develop(path=".")
```

The package family supports Julia 1.12 and later Julia 1.x releases. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the complete development commands.

## Documentation

The repository is pre-1.0. Its [LocalMath contract](spec/localmath.md) uses one
typed LocalMath pipeline and one CorePotts checkerboard execution
graph. CorePotts retains scientific ownership of proposal ordering, failure
boundaries, acceptance, semantic randomness, lifecycle behavior, and
checkpoint continuation. Historical development records remain available under
[`design/`](design/) but do not define product APIs or runtime modes.

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

The complete Learn, Published Models, and API manual builds strictly against
the public interface. There is no compatibility promise for unpublished
pre-release authoring names.
