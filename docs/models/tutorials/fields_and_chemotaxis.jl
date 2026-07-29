using PottsToolkit
import CorePotts

# Declare field semantics once, then bind experiment-specific values.
medium = Medium(:Medium)
cell = CellType(:MigratingCell)
gradient = Field(
    :chemo_gradient;
    placement = CellCentered(),
    boundary = NoFlux(),
    interpolation = Multilinear(),
)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 12, strength = 2)),
    gradient,
    Chemotaxis(gradient, cell => 4),
)
values = repeat(reshape(range(0.0f0, 1.0f0; length = 12), :, 1), 1, 12)
mask = falses(12, 12)
mask[5:7, 5:8] .= true
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(Place(cell, mask; identity = 1));
    fields = (gradient => values,),
    capacity = 2,
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
