using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
    (10, 10); target_volume = 12, tspan = (0, 2), seed = 0x1234)
ensemble = CorePotts.EnsembleProblem(problem; seed = 0x5eed)
solutions = CorePotts.solve(
    ensemble,
    SequentialCPM(temperature = 2.0f0),
    CorePotts.EnsembleSerial();
    trajectories = 3,
    save_start = false,
    save_end = true,
)
seeds = [solution.provenance.seed for solution in solutions.u]

@assert length(unique(seeds)) == 3
@assert length(solutions.u) == 3
result = (; solutions, seeds,
    contracts = CorePotts.scientific_contract_versions())
