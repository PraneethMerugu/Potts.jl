# Potts.jl

> **Development disclosure:** Substantial portions of this pre-release codebase,
> tests, and documentation were developed with generative-AI assistance and
> remain subject to maintainer review.

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://praneethmerugu.github.io/Potts.jl/dev/)

Potts.jl is the high-level Cellular Potts modeling system for Julia. It is one
member of four independently versioned packages:

- **[Potts](https://github.com/PraneethMerugu/Potts.jl)**: biological authoring and SciML integration.
- **[CorePotts](https://github.com/PraneethMerugu/CorePotts.jl)**: scientific execution and extension interfaces.
- **[LocalMath](https://github.com/PraneethMerugu/LocalMath.jl)**: typed bounded local computation.
- **[MakiePotts](https://github.com/PraneethMerugu/MakiePotts.jl)**: native Makie recipes.

The historical `Potts` umbrella package and pre-freeze engine have been removed.

## Installation

Until the package family is registered, install the release candidates in dependency order:

```julia
using Pkg
Pkg.add(url = "https://github.com/PraneethMerugu/LocalMath.jl", rev = "v0.2.0-rc1")
Pkg.add(url = "https://github.com/PraneethMerugu/CorePotts.jl", rev = "v0.2.0-rc1")
Pkg.add(url = "https://github.com/PraneethMerugu/Potts.jl", rev = "v0.3.0-rc1")
```

Add MakiePotts separately when visualization is required.

For development:

```julia
using Pkg
Pkg.develop(path="../LocalMath.jl")
Pkg.develop(path="../CorePotts.jl")
Pkg.develop(path="../Potts.jl")
```

The package family supports Julia 1.12 and later Julia 1.x releases. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the complete development commands.

## Documentation

The package family is pre-1.0. CorePotts retains scientific ownership of
proposal ordering, failure boundaries, acceptance, semantic randomness,
lifecycle behavior, and checkpoint continuation. LocalMath owns bounded
spatial and publication semantics. Historical development records under
[`design/`](design/) do not define product APIs or runtime modes.

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

The complete Learn, Published Models, and API manual builds strictly against
the public interface. There is no compatibility promise for unpublished
pre-release authoring names.
