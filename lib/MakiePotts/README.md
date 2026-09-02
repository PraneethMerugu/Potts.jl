# MakiePotts

> **Development disclosure:** Substantial portions of this pre-release codebase,
> tests, and documentation were developed with generative-AI assistance and
> remain subject to maintainer review.

MakiePotts v0.2 turns explicit Potts observations into native Makie recipes.

```julia
using MakiePotts
using CairoMakie

frame = renderframe(state, problem)
fig, axis, plot = plot(frame; boundaries = true)
potts_legend(fig[1, 2], plot)
```

The stable API centers on:

- validated `PottsRenderFrame` snapshots that defensively own their inputs;
- data-only `RenderRequest` values and typed render channels;
- open encoding and frame-accessor protocols;
- `PottsPlot` for 2D domains and orthogonal 3D slices;
- normal Makie composition, themes, `Observable`s, `DataInspector`, `Legend`,
  `Colorbar`, `save`, and `record`.

`renderframe` is deliberately explicit. It never transfers backend state or
reconstructs an observation that was not retained. Use
`CorePotts.HostSnapshotPolicy()` for complete post-hoc frames, or retain
`Potts.LatticeOwnership()` for a bounded visualization-neutral
observation.

`PottsVolume`, `PottsExplorer`, and `RerunController` are experimental. The
frame, request, channel, encoding, 2D recipe, boundary, inspection, and limited
recording contracts are stable for the v0.2 line.

`record_potts` validates inputs and replaces its destination only after a
successful temporary recording. Experimental explorers and rerun controllers
are explicitly closable with `close`.

The ordinary package and backend tests exercise an unrelated downstream frame
implementation, custom request and encoding extensions,
CairoMakie/GLMakie/WGLMakie, tolerant visual regression, allocation
measurements, strict documentation, and a clean install-to-PNG workflow.
