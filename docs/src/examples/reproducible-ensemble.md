# [A reproducible ensemble exposes variability](@id reproducible-ensemble)

Twelve trajectories derive independent semantic seeds from one ensemble seed. Instead of choosing
one representative run, the visualization shows every trajectory and the distribution of final
volumes.

## Define the shared experiment

```@example reproducible-ensemble
using PottsToolkit
using MakiePotts
import CorePotts

# One explicit problem becomes the template for a seeded ensemble.
medium = Medium(:Medium)
cell = CellType(:Cell)
target_volume = 24
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = target_volume, strength = 2)),
)
mask = falses(14, 14)
mask[6:9, 6:9] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 10),
    seed = 0x1234,
)
nothing # hide
```

## Let the engine derive trajectory seeds

```@example reproducible-ensemble
# The ensemble seed deterministically derives a distinct seed per trajectory.
ensemble = CorePotts.EnsembleProblem(problem; seed = 0xc0ffee)
solutions = CorePotts.solve(
    ensemble,
    SequentialCPM(temperature = 3.0f0),
    CorePotts.EnsembleSerial();
    trajectories = 12,
    saveat = 2,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
seeds = [solution.provenance.seed for solution in solutions.u]
nothing # hide
```

The seed policy defines trajectory identity independently of execution order. `EnsembleSerial`
keeps this documentation example small and deterministic.

## Preserve and verify every trajectory

```@example reproducible-ensemble
# Preserve every trajectory so variability is visible, not reduced to one frame.
volume_traces = map(solutions.u) do solution
    states = CorePotts.snapshot_state.(solution.u)
    cell_id = only(CorePotts.active_cell_ids(first(states)))
    [CorePotts.finite_volume(state, cell_id) for state in states]
end
final_volumes = last.(volume_traces)
mean_final_volume = sum(final_volumes) / length(final_volumes)
representative_frame = renderframe(first(solutions.u))

@assert length(unique(seeds)) == 12
@assert all(>(0), final_volumes)
@assert frame_size(representative_frame) == (14, 14)
result = (; problem, solutions, seeds, target_volume, volume_traces,
    final_volumes, mean_final_volume, representative_frame)

(result.final_volumes, result.mean_final_volume)
```

## Plot the ensemble, not a mascot trajectory

```@example reproducible-ensemble
using CairoMakie

figure = Figure(size = (1120, 650))
trace_axis = Axis(
    figure[1, 1:2];
    title = "Twelve independently seeded trajectories",
    xlabel = "Monte Carlo steps",
    ylabel = "Cell area",
)
for (index, trace) in enumerate(result.volume_traces)
    lines!(trace_axis, result.solutions.u[index].t, trace;
        color = (:steelblue, 0.4), linewidth = 2)
end
hlines!(trace_axis, [result.target_volume];
    color = :black, linestyle = :dash, label = "target")
axislegend(trace_axis)

distribution_axis = Axis(
    figure[2, 1];
    title = "Final-volume distribution",
    xlabel = "Final area",
    ylabel = "Trajectory",
)
scatter!(
    distribution_axis,
    result.final_volumes,
    eachindex(result.final_volumes);
    markersize = 14,
)
vlines!(distribution_axis, [result.mean_final_volume];
    color = :black, linewidth = 2, label = "mean")
axislegend(distribution_axis)

state_axis = Axis(
    figure[2, 2]; title = "One state, for spatial context", aspect = DataAspect())
state_plot = pottsplot!(state_axis, result.representative_frame; boundaries = true)
potts_legend(figure[2, 3], state_plot)
save("reproducible-ensemble-preview.svg", figure)
figure
```

Twelve smoke trajectories demonstrate deterministic seed derivation and visible variability. They
do not justify a scientific sample size or confidence interval; those choices belong in a
preregistered analysis plan.
