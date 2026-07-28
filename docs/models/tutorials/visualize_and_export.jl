using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.differential_adhesion_problem(
    (12, 12);
    cells_per_population = 1,
    target_volume = 8,
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
