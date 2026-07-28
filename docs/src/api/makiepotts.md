# [MakiePotts API](@id makiepotts-api)

MakiePotts is a native Makie extension over explicit host-owned render frames.

The stable boundary is `PottsRenderFrame`, not a CorePotts storage object and not a dashboard.
Frames carry ownership, generation-aware cell identity, geometry, requested channels, and
provenance. Styling remains ordinary Makie attributes.

`renderframe` never synchronizes a device, transfers backend storage, or reconstructs an undeclared
observable. Convert a complete host snapshot or a retained ownership observation before plotting.

The stable surface comprises frames, render requests, typed channels, encodings, two-dimensional
and orthogonal-slice `PottsPlot`, boundaries, inspection labels, and the bounded recording wrapper.
The reference below is filtered through the stable and limited registries.

```julia
frame = renderframe(state, problem)
figure, axis, plot = plot(frame; boundaries = true)
potts_legend(figure[1, 2], plot)
```

For continuous data, request a typed channel and use a `ChannelEncoding`; the resulting plot works
with Makie's standard `Colorbar`.

## Stable API

```@autodocs
Modules = [MakiePotts]
Filter = is_stable_makiepotts
```

Experimental explorer and volume names appear only in [Experimental API](@ref experimental-api).
