# [Visualize and export](@id visualize-and-export)

MakiePotts converts explicit host-owned state into visualization-neutral frames. Rendering never
changes the simulation schedule, random stream, saved observations, or authoritative state.

## Materialize a frame

```@example visualize-and-export
using PottsToolkit
using MakiePotts
import CorePotts

# Two typed cells make the categorical encoding and legend concrete.
medium = Medium(:Medium)
population_a = CellType(:PopulationA)
population_b = CellType(:PopulationB)
model = PottsModel(
    medium,
    population_a,
    population_b,
    Volume(
        population_a => (target = 8, strength = 2),
        population_b => (target = 8, strength = 2),
    ),
)
labels = zeros(UInt64, 12, 12)
labels[3:4, 5:8] .= 1
labels[9:10, 5:8] .= 2
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(LabelledCells(labels, (1 => population_a, 2 => population_b)));
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
