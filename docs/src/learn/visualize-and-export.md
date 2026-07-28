# [Visualize and export](@id visualize-and-export)

MakiePotts converts explicit host-owned state into visualization-neutral frames. Rendering never
changes the simulation schedule, random stream, saved observations, or authoritative state.

## Materialize a frame

```@example visualize-and-export
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.differential_adhesion_problem(
    (12, 12);
    cells_per_population = 1,
    target_volume = 8,
    capacity = 4,
    tspan = (0, 1),
    seed = 8,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
frame = renderframe(solution)
encoded = encode(frame, CellTypeEncoding())

@assert frame_size(frame) == (12, 12)
@assert size(encoded.values) == frame_size(frame)
result = (; frame, encoded, legend = legend_entries(encoded),
    provenance = frame_provenance(frame))

(frame_size(result.frame), length(result.legend), result.provenance.source)
```

`PottsRenderFrame` contains logical owners, generation-aware cell metadata, geometry, requested
channels, and provenance. `encode` converts those values for a selected visual mapping.

## Plot with an installed backend

```@example visualize-and-export
using CairoMakie
using MakiePotts

figure, axis, plot = plot(result.frame; boundaries = true)
potts_legend(figure[1, 2], plot)
mktempdir() do directory
    save(joinpath(directory, "population-types.png"), figure)
end
figure
```

Use `ChannelEncoding` and ordinary Makie `Colorbar` for continuous channels. Three-dimensional
state can be converted with an `OrthogonalSlice`; full volume exploration remains experimental.

## Export policy

Figures should record source fingerprint, saved MCS, render request, encoding, backend, dimensions,
and output command. The documentation executes CairoMakie headlessly, so every displayed example
figure comes from the visible MakiePotts recipe call. Use `record_potts` when a study needs an
animation; it validates the render-frame sequence before delegating to Makie's recorder.
