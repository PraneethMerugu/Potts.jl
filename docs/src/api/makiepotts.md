# [MakiePotts API](@id makiepotts-api)

MakiePotts is a native Makie extension over explicit host-owned render frames. It supplies semantic
Potts recipes while leaving figure composition, axes, traces, layouts, and export to ordinary
Makie.

## Choose a workflow

| I need to… | Start with |
|:--|:--|
| render the latest complete saved state | [`renderframe`](@ref) |
| render every saved state | [`renderframes`](@ref) |
| select a 3D plane | [`RenderRequest`](@ref) with [`OrthogonalSlice`](@ref) |
| color by cell type | [`CellTypeEncoding`](@ref) |
| distinguish finite-cell identities | [`CellIdentityEncoding`](@ref) |
| show a retained continuous variable | [`ChannelEncoding`](@ref) and a Makie `Colorbar` |
| compose into an existing figure | [`pottsplot!`](@ref), [`pottsboundaries!`](@ref) |
| add a categorical legend | [`potts_legend`](@ref) |
| record validated frames | [`record_potts`](@ref) |

## Frame, encode, compose

```julia
frames = renderframes(solution)

figure = Figure()
axis = Axis(figure[1, 1]; aspect = DataAspect())
potts_plot = pottsplot!(
    axis,
    last(frames);
    encoding = CellTypeEncoding(),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
```

Use ordinary Makie axes beside the spatial panel for volume histories, contact statistics,
trajectories, distributions, and uncertainty. The gallery examples demonstrate these compositions
and use `record_potts` for the four temporal mechanisms where motion is part of the lesson.

## Understand the boundary

The stable boundary is [`PottsRenderFrame`](@ref), not a CorePotts storage object and not a
dashboard.
Frames carry ownership, generation-aware cell identity, geometry, requested channels, and
provenance. Styling remains ordinary Makie attributes.

`renderframe` never synchronizes a device, transfers backend storage, or reconstructs an undeclared
observable. Convert a complete host snapshot or a retained ownership observation before plotting.

For continuous data, request a typed channel and use a `ChannelEncoding`; the resulting plot works
with Makie's standard `Colorbar`.

## Stable API index

```@autodocs
Modules = [MakiePotts]
Filter = is_stable_makiepotts
```

The index is filtered through the stable and limited registries. Experimental explorer and true
volume names appear only in [Experimental API](@ref experimental-api).
