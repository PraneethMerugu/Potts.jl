# [Visualize and export](@id visualize-and-export)

MakiePotts converts explicit host-owned state into visualization-neutral frames. Rendering never
changes the simulation schedule, random stream, saved observations, or authoritative state.

## Materialize a frame

```@example visualize-and-export
visual = include(joinpath(
    ENV["POTTS_DOCS_ROOT"], "models", "tutorials",
    "visualize_and_export.jl"))
(frame_size(visual.frame), length(visual.legend),
    visual.provenance.source)
```

`PottsRenderFrame` contains logical owners, generation-aware cell metadata, geometry, requested
channels, and provenance. `encode` converts those values for a selected visual mapping.

## Plot with an installed backend

```julia
using CairoMakie
using MakiePotts

figure, axis, plot = plot(visual.frame; boundaries = true)
potts_legend(figure[1, 2], plot)
save("population-types.png", figure)
```

Use `ChannelEncoding` and ordinary Makie `Colorbar` for continuous channels. Three-dimensional
state can be converted with an `OrthogonalSlice`; full volume exploration remains experimental.

## Export policy

Figures should record source fingerprint, saved MCS, render request, encoding, backend, dimensions,
and output command. Selected CairoMakie PNGs may use tolerant approved regression tests.
Animations are validated through canonical source, metadata, and representative frames instead of
byte-comparing encoder output.

The fast documentation suite materializes frames but does not require a display. Expensive
animation rendering runs separately under the media budget.
