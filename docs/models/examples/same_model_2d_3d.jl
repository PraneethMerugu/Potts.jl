using PottsToolkit
using MakiePotts
import CorePotts

# The biological declarations do not encode a lattice dimension.
medium = Medium(:Medium)
cell = CellType(:Cell)
target_volume = 16
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = target_volume, strength = 2)),
)
algorithm = SequentialCPM(temperature = 2.0f0)

# Bind the same model to one planar mask and one volumetric mask.
mask_2d = falses(10, 10)
mask_2d[4:7, 4:7] .= true
mask_3d = falses(7, 7, 7)
mask_3d[3:5, 3:5, 3:4] .= true
problems = (
    PottsProblem(
        model,
        CartesianDomain(size(mask_2d)),
        Layout(Place(cell, mask_2d; identity = 1));
        capacity = 2,
        tspan = (0, 2),
        seed = 9,
    ),
    PottsProblem(
        model,
        CartesianDomain(size(mask_3d)),
        Layout(Place(cell, mask_3d; identity = 1));
        capacity = 2,
        tspan = (0, 2),
        seed = 9,
    ),
)

# MakiePotts renders 2D directly and 3D through an explicit orthogonal slice.
reports = map(problem -> backend_report(problem, algorithm), problems)
solutions = map(problem -> CorePotts.solve(
    problem,
    algorithm;
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
), problems)
frames = (
    renderframe(solutions[1]),
    renderframe(solutions[2], RenderRequest(extent = OrthogonalSlice(3, 4))),
)

@assert all(report -> report.qualified, reports)
@assert all(solution -> solution.stats.completed_mcs == 2, solutions)
@assert frame_size.(frames) == ((10, 10), (7, 7))
result = (; model, problems, reports, solutions, frames)
