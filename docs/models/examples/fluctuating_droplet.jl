using PottsToolkit
using MakiePotts
import CorePotts

# Noise enters the volume-pressure declaration, not an analysis afterthought.
medium = Medium(:Medium)
droplet = CellType(:Droplet)
target_volume = 24
model = PottsModel(
    medium,
    droplet,
    FluctuatingVolumePressure(
        droplet => (target = target_volume, strength = 1);
        eta = 0.2,
        noise = AcceptanceTemperature(),
    ),
    Adhesion(
        (medium, medium) => 0,
        (medium, droplet) => 8,
        (droplet, droplet) => 0,
    ),
)

# A compact seed leaves room for the noisy interface to move.
mask = falses(18, 18)
mask[7:11, 7:11] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(droplet, mask; identity = 1));
    capacity = 2,
    tspan = (0, 60),
    seed = 31,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 3.0f0);
    saveat = 2,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

# Report the time series and its finite-sample distribution side by side.
states = CorePotts.snapshot_state.(solution.u)
cell_id = only(CorePotts.active_cell_ids(first(states)))
volume_trace = [CorePotts.finite_volume(state, cell_id) for state in states]
mean_volume = sum(volume_trace) / length(volume_trace)
variance = sum((volume - mean_volume)^2 for volume in volume_trace) /
    length(volume_trace)
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 60
@assert variance > 0
@assert length(frames) == length(solution.t)
result = (; problem, solution, target_volume, volume_trace, mean_volume, variance, frames)
