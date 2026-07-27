# MakiePotts

MakiePotts v0.2 is a native Makie extension. Its stable boundary is a complete, defensively owned
and logically immutable host-local [`PottsRenderFrame`](@ref), not a CorePotts storage object and
not an application-owned dashboard. This preserves Makie's normal composition model:

```julia
frame = renderframe(state, problem)
fig, axis, plot = plot(frame)

plot!(axis, another_makie_recipe)
potts_legend(fig[1, 2], plot)
```

For a continuous requested channel, the same plot works with Makie's standard colorbar:

```julia
request = RenderRequest(channels = (
    CellPropertyRequest(:activity, Float32; label = "Activity"),
))
frame = renderframe(state, problem, request)
fig, axis, plot = plot(frame; encoding = ChannelEncoding(
    CellChannelKey(:activity, Float32)))
Colorbar(fig[1, 2], plot)
```

## Explicit observation boundary

`renderframe` never synchronizes a device, transfers backend storage, or reconstructs an
undeclared observable. A saved solution can be converted only when it contains complete host
snapshots:

```julia
solution = CorePotts.solve(
    problem,
    CorePotts.SequentialCPM();
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
frames = renderframes(solution)
```

For bounded production observation, declare
[`PottsToolkit.LatticeOwnership`](@ref), retain it with
[`PottsToolkit.observation_policy`](@ref), and convert the resulting
[`PottsToolkit.SpatialSeries`](@ref). That path copies only the visualization-neutral values the
model declared.

## Stable and experimental surfaces

The stable surface comprises frames, render requests, typed channels, encodings, the 2D/slice
`PottsPlot`, boundaries, inspection labels, and the limited recording wrapper. `PottsVolume`,
`PottsExplorer`, and `RerunController` are experimental reference implementations.

Frames carry ownership, generation-aware cell identity, explicit geometry, requested channels, and
provenance. They never carry a colormap or precolored cell pixels. Styling remains ordinary Makie
attributes and themes.

Recording validates every frame and writes through a temporary artifact. A failed
update leaves an existing destination unchanged. Experimental controllers own
their lifecycle explicitly:

```julia
explorer = explore_potts(frames)
close(explorer)

controller = RerunController(run_model)
close(controller) # in-flight work can no longer publish
```

The package qualification includes a foreign frame implementation, custom
channel materializer and encoding, Cairo/GL/WGL backend smokes, allocation
ceilings, and one tolerant Cairo reference image. Visual-regression failures
retain expected, actual, and amplified-difference images; maintainers must use
an explicit acceptance mode to replace the reference.

## API

```@autodocs
Modules = [MakiePotts]
Private = false
```
