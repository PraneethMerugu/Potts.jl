using PottsToolkit
import CorePotts

# Freeze one explicit problem before deriving independent ensemble trajectories.
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(medium, cell, Volume(cell => (target = 12, strength = 2)))
mask = falses(10, 10)
mask[4:6, 4:7] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 2),
    seed = 0x1234,
)
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
