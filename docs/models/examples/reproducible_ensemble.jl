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
