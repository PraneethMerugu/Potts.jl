using PottsToolkit
using MakiePotts
import CorePotts

# The cell mechanics are ordinary; the domain carries the obstacle contract.
medium = Medium(:medium)
cell = CellType(:cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 6, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 6,
        (cell, cell) => 2,
    ),
)
# Obstacles are immutable medium-owned sites inside the rectangular lattice.
obstacles = Tuple(
    CartesianIndex(8, y) => CorePotts.MediumOwner(1) for y in 4:9)
domain = CartesianDomain(
    (14, 14);
    boundaries = (
        AxisBoundary(ClosedBoundary()),
        AxisBoundary(ClosedBoundary()),
    ),
    obstacles,
)
mask = falses(14, 14)
mask[4:5, 6:8] .= true
# Place the cell to the left of the wall and save the final host state.
problem = PottsProblem(
    model,
    domain,
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 4),
    seed = 71,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
final_state = CorePotts.snapshot_state(last(solution.u))
frame = renderframe(solution)

@assert all(pair -> CorePotts.owner_at(final_state, first(pair)) == last(pair), obstacles)
@assert frame_size(frame) == (14, 14)
result = (; problem, solution, obstacle_count = length(obstacles),
    immutable_obstacles = true, frame)
