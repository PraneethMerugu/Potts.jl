# Potts.jl

Potts.jl is in an intentional pre-1.0 cohesion and ModelingToolkit hardening phase. The active
package family is:

| Package | Responsibility |
|:--|:--|
| `PottsToolkit` | Symbolic Potts authoring, ModelingToolkit integration, component scheduling, and the public SciML problem lifecycle |
| `CorePotts` | MTK-free CPM state, transitions, lifecycle, checkpoints, reproducibility, and CPU/GPU execution |
| `MakiePotts` | Visualization over explicit public observations and solutions |

## Current documentation status

The earlier manual described the removed `PottsModel` API while the source had already moved to
`PottsSystem`. Those pages are retained in the repository as rewrite material, but they are
deliberately excluded from the active documentation build. They are not a migration guide or a
compatibility promise.

This temporary manual documents only the current architecture, runtime boundary, and honest
capability state. The authoring lifecycle and G5H-4 implementation matrix now have executable CPU,
Metal, MethodOfLines, and ensemble rows; the complete Learn, Examples, Published Models, and API
manual returns in G5H-5 after the final interface is frozen.

## Target public lifecycle

```text
construct / @named / compose
        -> complete
        -> mtkcompile
        -> scheduled PottsSystem
        -> PottsProblem
        -> init or solve with an algorithm and backend
        -> PottsIntegrator / PottsSolution
```

`mtkcompile` is structural. It must not choose the CPM engine, backend, scalar type, device, seed,
or runtime state. Native ModelingToolkit systems remain native component islands with explicit IO,
scope, cadence, and coupling semantics. CorePotts remains independent of ModelingToolkit.

## Implemented but not yet a final stable user claim

- the final constructor vocabulary and exported API;
- the final documentation and spelling freeze for global/per-cell native MTK components;
- broader MethodOfLines support than the exact checked CPU grid/solver row;
- broader Metal support than the exact 2D `Float32` fixed-step rows;
- CUDA, ROCm, adaptive native GPU solves, GPU remeshing, or unrestricted graph rewriting;
- executable Wortel and Merks documentation through the final interface; and
- API compatibility with any earlier unpublished authoring surface.

See [Architecture](@ref architecture), [Runtime boundary](@ref runtime-boundary), and
[Capability status](@ref capability-status) for the current boundary.

## Development

Package and integration commands remain in the repository `CONTRIBUTING.md`. The normative phase
sequence is maintained under `spec/`; public documentation never overrides it.
