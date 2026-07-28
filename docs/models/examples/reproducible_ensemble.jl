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
