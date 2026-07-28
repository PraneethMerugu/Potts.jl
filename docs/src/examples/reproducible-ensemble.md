# [Reproducible Ensemble](@id reproducible-ensemble)

Replicates should derive independent semantic seeds through the engine's ensemble policy, not task
order or ad hoc arithmetic.

```@example reproducible-ensemble
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (12, 12); target_volume = 16, tspan = (0, 3), seed = 0x1234)
ensemble = CorePotts.EnsembleProblem(problem; seed = 0xc0ffee)
solutions = CorePotts.solve(
    ensemble,
    SequentialCPM(temperature = 2.0f0),
    CorePotts.EnsembleSerial();
    trajectories = 4,
    save_start = false,
    save_end = true,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
seeds = [solution.provenance.seed for solution in solutions.u]
final_volumes = map(solutions.u) do solution
    state = CorePotts.snapshot_state(last(solution.u))
    cell_id = only(CorePotts.active_cell_ids(state))
    CorePotts.finite_volume(state, cell_id)
end
representative_frame = renderframe(first(solutions.u))

@assert length(unique(seeds)) == 4
@assert all(>(0), final_volumes)
@assert frame_size(representative_frame) == (12, 12)
result = (; problem, solutions, seeds, final_volumes,
    mean_final_volume = sum(final_volumes) / length(final_volumes),
    representative_frame)

(result.seeds, result.final_volumes, result.mean_final_volume)
```

```@example reproducible-ensemble
using CairoMakie

figure, axis, potts_plot = plot(
    result.representative_frame;
    axis = (; title = "Representative seeded trajectory"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The source requires four distinct derived seeds and positive final cell volume in every
trajectory. `EnsembleSerial` makes the fast example deterministic; the seed policy is designed so
an applicable threaded execution does not redefine trajectory identity.

The displayed mean is descriptive for four tiny smoke trajectories. It is not a confidence
interval or scientific sample-size justification. A study must define its statistic, replicate
count, exclusions, rerun policy, and uncertainty analysis in advance.

Teaching inspiration: complete parameter-scan workflows in
[CC3D QuickModels](https://compucell3d.org/QuickModels). The implementation uses the native
CorePotts ensemble contract.
