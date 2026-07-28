using PottsToolkit
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

@assert solution.stats.completed_mcs == 6
@assert all(>(0), volume_trace)
result = (; problem, solution, volume_trace, absolute_error,
    initial_error = first(absolute_error), final_error = last(absolute_error))
