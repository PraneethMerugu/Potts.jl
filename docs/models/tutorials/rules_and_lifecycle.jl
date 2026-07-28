using PottsToolkit
import CorePotts

model = PottsToolkit.ReferenceModels.monolayer_growth_model(
    target_volume = 6,
    division_target = 8,
    growth_rate = 1,
)
problem = PottsToolkit.ReferenceModels.monolayer_growth_problem(
    (12, 12);
    target_volume = 6,
    division_target = 8,
    growth_rate = 1,
    capacity = 8,
    tspan = (0, 2),
    seed = 12,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM();
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
final_state = CorePotts.snapshot_state(last(solution.u))

@assert isvalid(model)
@assert CorePotts.n_cells(final_state) >= 1
result = (; model, problem, completed_mcs = solution.stats.completed_mcs,
    final_cells = CorePotts.n_cells(final_state))
