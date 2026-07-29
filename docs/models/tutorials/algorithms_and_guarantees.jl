using PottsToolkit
import CorePotts

# Hold the model fixed while comparing two different proposal processes.
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
    tspan = (0, 1),
    seed = 17,
)
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
