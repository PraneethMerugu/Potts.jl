# [A compressed cell relaxes](@id relaxing-cell)

An 80-site cell begins far above its preferred area of 50 sites. This example exposes the complete
model, then puts the shape change and volume error in the same figure.

## Declare the energy

```@example relaxing-cell
using PottsToolkit
using MakiePotts
import CorePotts

# A compressed cell pays a quadratic penalty for missing its preferred volume.
medium = Medium(:Medium)
cell = CellType(:RelaxingCell)
target_volume = 50
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = target_volume, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 0,
    ),
)
nothing # hide
```

The volume term supplies the restoring pressure. Adhesion controls the energetic cost of the
cell-medium boundary; neither mechanism is hidden in a reference constructor.

## Create a measurable perturbation

```@example relaxing-cell
# The 10×8 seed starts well above the 50-site target.
mask = falses(26, 22)
mask[9:18, 8:15] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 40),
    seed = 11,
)
nothing # hide
```

The initialization is intentionally not near the target. That makes “relaxation” a quantitative
statement: the final absolute volume error must be smaller than the initial error.

## Run and calculate the contract

```@example relaxing-cell
# Complete snapshots let the same run drive both the metric and MakiePotts.
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 3.0f0);
    saveat = 5,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
states = CorePotts.snapshot_state.(solution.u)
cell_id = only(CorePotts.active_cell_ids(first(states)))
volume_trace = [CorePotts.finite_volume(state, cell_id) for state in states]
absolute_error = abs.(volume_trace .- target_volume)
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 40
@assert last(absolute_error) < first(absolute_error)
@assert length(frames) == length(solution.t)
result = (; problem, solution, target_volume, volume_trace, absolute_error, frames)

(first(result.volume_trace), last(result.volume_trace),
    first(result.absolute_error), last(result.absolute_error))
```

## Read shape and error together

```@example relaxing-cell
using CairoMakie

figure = Figure(size = (1050, 620))
before_axis = Axis(figure[1, 1]; title = "Compressed · 80 sites", aspect = DataAspect())
after_axis = Axis(figure[1, 2]; title = "Relaxed · $(last(result.volume_trace)) sites",
    aspect = DataAspect())
before_plot = pottsplot!(before_axis, first(result.frames); boundaries = true)
pottsplot!(after_axis, last(result.frames); boundaries = true)
potts_legend(figure[1, 3], before_plot)

trace_axis = Axis(
    figure[2, 1:2];
    title = "Volume error collapses after the perturbation",
    xlabel = "Monte Carlo steps",
    ylabel = "|volume − target|",
)
lines!(trace_axis, result.solution.t, result.absolute_error; linewidth = 3)
scatter!(trace_axis, result.solution.t, result.absolute_error; markersize = 10)
save("relaxing-cell-preview.svg", figure)
figure
```

This verifies one bounded seeded trajectory. It does not establish an equilibrium distribution or
a relaxation time constant; those require a declared ensemble, burn-in, estimator, and uncertainty
analysis.
