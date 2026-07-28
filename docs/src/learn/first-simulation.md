# [First simulation](@id first-simulation)

The first complete session runs a relaxing cell, records a deterministic volume trace, and creates
before/after render frames. Rendering remains optional for headless work, but the normal path makes
the result visible.

## Run the canonical program

```@example first-simulation
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (12, 12); target_volume = 16, tspan = (0, 2), seed = 11)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
first_state = CorePotts.snapshot_state(first(solution.u))
last_state = CorePotts.snapshot_state(last(solution.u))
cell_id = only(CorePotts.active_cell_ids(last_state))
volume_trace = [
    CorePotts.finite_volume(CorePotts.snapshot_state(saved), cell_id)
    for saved in solution.u
]
frames = MakiePotts.renderframes(solution)

@assert solution.stats.completed_mcs == 2
@assert length(volume_trace) == length(solution.t) == length(frames)
result = (; times = collect(solution.t), volume_trace,
    initial_volume = CorePotts.finite_volume(first_state, cell_id),
    final_volume = last(volume_trace), first_frame = first(frames),
    last_frame = last(frames))

(result.times, result.volume_trace, result.initial_volume, result.final_volume)
```

The source is
[`docs/models/tutorials/first_simulation.jl`](https://github.com/PraneethMerugu/Potts.jl/blob/main/docs/models/tutorials/first_simulation.jl).
It uses a fixed model, seed, algorithm, and two-MCS time span. Its assertions require one volume
value and one render frame for every saved time.

## Read the program

The reusable problem comes from `ReferenceModels.single_cell_fluctuation_problem`. Execution is
still explicit:

```julia
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
```

`HostSnapshotPolicy` is chosen because this beginner example wants complete before/after frames.
Production analysis should normally retain only declared observations.

## Render when a Makie backend is available

The canonical source converts saved host states with `MakiePotts.renderframes`. To draw them, add
and activate a Makie backend:

```@example first-simulation
using CairoMakie
using MakiePotts

figure, axis, plot = plot(result.last_frame; boundaries = true)
potts_legend(figure[1, 2], plot)
figure
```

The simulation and trace work without CairoMakie. This keeps servers and CI headless while
preserving the normal visual workflow.

## What this result proves

The smoke proves construction, preflight, deterministic execution under the recorded contract,
volume extraction, and render-frame materialization. It does not prove equilibrium or calibrate
MCS to physical time. Those stronger claims need their own evidence.

Continue to [Compose a biological model](@ref build-model) to replace the reference constructor
with declarations you control.
