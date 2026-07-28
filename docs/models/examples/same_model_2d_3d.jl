using PottsToolkit
import CorePotts

problems = (
    PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
        (10, 10); target_volume = 12, tspan = (0, 2), seed = 9),
    PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
        (7, 7, 7); target_volume = 16, tspan = (0, 2), seed = 9),
)
algorithm = SequentialCPM(temperature = 2.0f0)
reports = map(problem -> backend_report(problem, algorithm), problems)
solutions = map(problem -> CorePotts.solve(problem, algorithm), problems)
dimensions = map(problem -> length(CorePotts.lattice_size(problem.u0)), problems)

@assert dimensions == (2, 3)
@assert all(report -> report.qualified, reports)
@assert all(solution -> solution.stats.completed_mcs == 2, solutions)
result = (; problems, reports, solutions, dimensions)
