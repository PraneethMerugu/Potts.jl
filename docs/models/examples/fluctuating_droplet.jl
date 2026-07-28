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
