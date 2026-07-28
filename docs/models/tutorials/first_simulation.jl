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
