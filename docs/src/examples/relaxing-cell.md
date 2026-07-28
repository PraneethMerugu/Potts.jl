# [Relaxing Cell](@id relaxing-cell)

A single cell begins below its target volume and relaxes under an explicit fluctuating-volume
mechanism. The output is a deterministic volume trace, not merely a picture.

```@example relaxing-cell
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (14, 14); target_volume = 20, volume_strength = 2,
    tspan = (0, 6), seed = 11)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 1.5f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
cell_id = only(CorePotts.active_cell_ids(
    CorePotts.snapshot_state(first(solution.u))))
volume_trace = [
    CorePotts.finite_volume(CorePotts.snapshot_state(saved), cell_id)
    for saved in solution.u
]
target_volume = 20
absolute_error = abs.(volume_trace .- target_volume)
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 6
@assert all(>(0), volume_trace)
@assert length(frames) == length(solution.t)
result = (; problem, solution, volume_trace, absolute_error,
    initial_error = first(absolute_error), final_error = last(absolute_error),
    frames)

(result.volume_trace, result.absolute_error,
    result.initial_error, result.final_error)
```

```@example relaxing-cell
using CairoMakie

figure, axis, potts_plot = plot(
    last(result.frames);
    axis = (; title = "Relaxed cell at MCS $(frame_mcs(last(result.frames)))"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The canonical source asserts positive volume throughout the run and records the absolute
target-volume error at every saved time. With the pinned seed and algorithm, this smoke reaches the
declared target in the retained trace.

Use this example to learn:

- the distinction between target and realized volume;
- explicit algorithm temperature;
- complete host snapshots for a small diagnostic trace;
- why deterministic numerical output is stronger than visual plausibility.

The short run is not an equilibrium claim. A fluctuation or equilibrium study needs burn-in,
sampling cadence, a stationary statistic, replicates, and its applicable qualification gate.

Teaching inspiration: the approachable first-cell progression in
[CellularPotts.jl Hello World](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/HelloWorld/HelloWorld/).
The implementation is clean original PottsToolkit code.
