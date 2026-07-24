# Potts.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://praneethmerugu.github.io/Potts.jl/dev/)

Potts.jl is a Cellular Potts modeling system for Julia. The Phase 13 paper-core release contains
two independently testable packages:

- **PottsToolkit**: the repository-root biological authoring interface.
- **CorePotts**: the scientific execution engine and advanced extension interface.

The historical `Potts` umbrella package and pre-freeze engine have been removed. MakiePotts remains
deferred source for its Phase 14.4 migration and is not part of the Phase 13 workspace or
compatibility guarantee. The obsolete NeuralPotts implementation was removed; a redesigned
experimental satellite may return only through the Phase 14.4-or-later scope and conformance gate.

## Installation

Until the package family is registered, install PottsToolkit directly from the repository root:

```julia
pkg> add https://github.com/PraneethMerugu/Potts.jl
```

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

Phase 13 documentation is strict and executable. The final API compatibility boundary is the
curated owner-approved freeze inventory, not the set of names that happen to be exported.
