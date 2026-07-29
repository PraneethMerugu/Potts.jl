using PottsToolkit
using MakiePotts
import CorePotts

# Declare the biological vocabulary and the two energetic mechanisms.
medium = Medium(:Medium)
cell = CellType(:Cell)
target_volume = 36
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = target_volume, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 0,
    ),
)

# Start one cell below its target so the trajectory has something to explain.
mask = falses(20, 20)
mask[9:12, 9:12] .= true
problem = PottsProblem(
    model,
    CartesianDomain((20, 20)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 30),
    seed = 11,
)

# Save host snapshots because analysis and MakiePotts consume explicit saved state.
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 4.0f0);
    saveat = 5,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
states = CorePotts.snapshot_state.(solution.u)
cell_id = only(CorePotts.active_cell_ids(first(states)))
volume_trace = [CorePotts.finite_volume(state, cell_id) for state in states]
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 30
@assert length(frames) == length(solution.t) == length(volume_trace)
@assert all(>(0), volume_trace)
result = (; problem, solution, target_volume, volume_trace, frames)
