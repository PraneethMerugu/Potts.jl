using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.chemotaxis_problem(
    (12, 12);
    profile = :linear,
    target_volume = 12,
    sensitivity = 4,
    tspan = (0, 2),
    seed = 21,
)
algorithm = SequentialCPM(temperature = 2.0f0)
report = backend_report(problem, algorithm)
solution = CorePotts.solve(problem, algorithm)

@assert report.qualified
@assert solution.stats.completed_mcs == 2
result = (; problem, report, completed_mcs = solution.stats.completed_mcs,
    retcode = solution.retcode)
