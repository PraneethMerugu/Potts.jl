using PottsToolkit
using MakiePotts
import CorePotts

# A compressed cell pays a quadratic penalty for missing its preferred volume.
medium = Medium(:Medium)
cell = CellType(:RelaxingCell)
target_volume = 50
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

# The 10×8 seed starts well above the 50-site target.
mask = falses(26, 22)
mask[9:18, 8:15] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 40),
    seed = 11,
)

# Complete snapshots let the same run drive both the metric and MakiePotts.
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 3.0f0);
    saveat = 5,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
states = CorePotts.snapshot_state.(solution.u)
cell_id = only(CorePotts.active_cell_ids(first(states)))
volume_trace = [CorePotts.finite_volume(state, cell_id) for state in states]
absolute_error = abs.(volume_trace .- target_volume)
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 40
@assert last(absolute_error) < first(absolute_error)
@assert length(frames) == length(solution.t)
result = (; problem, solution, target_volume, volume_trace, absolute_error, frames)
