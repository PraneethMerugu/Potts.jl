using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (10, 10); target_volume = 12, tspan = (0, 1), seed = 19)
algorithm = SequentialCPM(temperature = 2.0f0)
report = backend_report(problem, algorithm)
profile = CorePotts.algorithm_guarantees(algorithm)
solution = CorePotts.solve(problem, algorithm; save_everystep = false)

@assert report.qualified
@assert solution.stats.completed_mcs == 1
result = (; report, profile, stats = solution.stats,
    contracts = CorePotts.scientific_contract_versions())
