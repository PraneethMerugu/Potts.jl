# [Fluctuating Droplet](@id fluctuating-droplet)

A single droplet combines explicit contact energy with fluctuating volume pressure. Mechanical
noise is declared by the component rather than hidden inside a plotting or analysis step.

```@example fluctuating-droplet
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.droplet_problem(
    (18, 18);
    target_volume = 24,
    volume_strength = 1,
    eta = 0.2,
    contact_energy = 8,
    tspan = (0, 8),
    seed = 31,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 3.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
cell_id = only(CorePotts.active_cell_ids(
    CorePotts.snapshot_state(first(solution.u))))
volume_trace = [
    CorePotts.finite_volume(CorePotts.snapshot_state(saved), cell_id)
    for saved in solution.u
]
mean_volume = sum(volume_trace) / length(volume_trace)
variance = sum((volume - mean_volume)^2 for volume in volume_trace) /
    length(volume_trace)
frame = renderframe(solution)

@assert solution.stats.completed_mcs == 8
@assert variance >= 0
@assert frame_size(frame) == (18, 18)
result = (; problem, solution, volume_trace, mean_volume, variance, frame)

(result.volume_trace, result.mean_volume, result.variance)
```

```@example fluctuating-droplet
using CairoMakie

figure, axis, potts_plot = plot(
    result.frame;
    axis = (; title = "Fluctuating droplet at MCS $(frame_mcs(result.frame))"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The source computes the finite-sample volume mean and variance and asserts that the statistic is
well-defined. The pinned smoke commonly produces a nonzero fluctuation; the assertion remains
mathematically correct even if a future compatible run yields zero variance over this short
window.

Do not describe this trace as an equilibrium distribution. Equilibrium requires the separate
algorithm/evidence gate plus declared burn-in, sampling, and convergence analysis.

This is an original PottsToolkit example backed by the reusable `droplet_problem` constructor.
