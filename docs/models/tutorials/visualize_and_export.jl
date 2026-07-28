using PottsToolkit
using MakiePotts
import CorePotts

# Two typed cells make the categorical encoding and legend concrete.
medium = Medium(:Medium)
population_a = CellType(:PopulationA)
population_b = CellType(:PopulationB)
model = PottsModel(
    medium,
    population_a,
    population_b,
    Volume(
        population_a => (target = 8, strength = 2),
        population_b => (target = 8, strength = 2),
    ),
)
labels = zeros(UInt64, 12, 12)
labels[3:4, 5:8] .= 1
labels[9:10, 5:8] .= 2
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(LabelledCells(labels, (1 => population_a, 2 => population_b)));
    capacity = 4,
    tspan = (0, 1),
    seed = 8,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
frame = renderframe(solution)
encoded = encode(frame, CellTypeEncoding())

@assert frame_size(frame) == (12, 12)
@assert size(encoded.values) == frame_size(frame)
result = (; frame, encoded, legend = legend_entries(encoded),
    provenance = frame_provenance(frame))
