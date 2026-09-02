# CorePotts.jl

CorePotts is the typed scientific execution core for cellular Potts models. It
owns proposal semantics, semantic randomness, scheduling, lifecycle
transactions, rollback, bank authorization, and checkpoint continuation while
using LocalMath for eligible bounded spatial mechanics.

CorePotts is primarily a compiler and runtime substrate. Most model authors
should use [Potts.jl](https://github.com/PraneethMerugu/Potts.jl).

> **Development disclosure:** Substantial portions of this pre-release codebase,
> tests, and documentation were developed with generative-AI assistance and
> remain subject to maintainer review.
