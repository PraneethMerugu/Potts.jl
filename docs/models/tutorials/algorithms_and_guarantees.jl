using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (10, 10); target_volume = 12, tspan = (0, 1), seed = 17)
algorithms = (
    SequentialCPM(temperature = 2.0f0),
    CheckerboardSweepCPM(temperature = 2.0f0),
)
profiles = map(CorePotts.algorithm_guarantees, algorithms)
reports = map(algorithm -> backend_report(problem, algorithm), algorithms)

@assert all(report -> report.qualified, reports)
@assert profiles[1].proposal_process != profiles[2].proposal_process
result = (; algorithms, profiles,
    guarantee_labels = map(profile -> profile.guarantee_label, profiles))
