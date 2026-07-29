using PottsToolkit
using MakiePotts
import CorePotts

# Shape, contact, and connectivity mechanisms are independent declarations.
medium = Medium(:Medium)
network_cell = CellType(:NetworkCell)
target_elongation = 3.0
model = PottsModel(
    medium,
    network_cell,
    Volume(network_cell => (target = 8, strength = 2)),
    Elongation(network_cell => (target = target_elongation, strength = 20)),
    Adhesion(
        (medium, medium) => 0,
        (medium, network_cell) => 10,
        (network_cell, network_cell) => 4,
    ),
    PreserveConnectivity(),
)

# Four short bars begin separated so their shape evolution stays legible.
labels = zeros(UInt64, 18, 18)
for (cell_id, x_range, y_range) in (
        (1, 5:8, 5:6),
        (2, 11:14, 5:6),
        (3, 5:8, 13:14),
        (4, 11:14, 13:14))
    labels[x_range, y_range] .= cell_id
end
assignments = [UInt64(cell_id) => network_cell for cell_id in 1:4]
problem = PottsProblem(
    model,
    CartesianDomain(
        (18, 18);
        boundaries = ntuple(_ -> AxisBoundary(ClosedBoundary()), 2),
    ),
    Layout(LabelledCells(labels, assignments));
    capacity = 8,
    tspan = (0, 100),
    seed = 44,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    saveat = 10,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

# A bounding-box ratio is a transparent teaching proxy, not a vascular metric.
function mean_bounding_box_elongation(saved)
    state = CorePotts.snapshot_state(saved)
    elongations = Float64[]
    for cell_id in CorePotts.active_cell_ids(state)
        sites = [
            site for site in CartesianIndices(CorePotts.lattice_size(state))
            if (owner = CorePotts.owner_at(state, site);
                CorePotts.is_cell_owner(owner) && CorePotts.cell_id(owner) == cell_id)
        ]
        widths = ntuple(axis -> begin
            coordinates = getindex.(Tuple.(sites), axis)
            maximum(coordinates) - minimum(coordinates) + 1
        end, 2)
        push!(elongations, max(widths...) / min(widths...))
    end
    return sum(elongations) / length(elongations)
end

elongation_trace = mean_bounding_box_elongation.(solution.u)
frames = renderframes(solution)
@assert solution.stats.completed_mcs == 100
@assert CorePotts.n_cells(CorePotts.snapshot_state(last(solution.u))) == 4
@assert all(>=(1), elongation_trace)
@assert length(frames) == length(solution.t)
result = (; model, problem, solution, target_elongation, elongation_trace, frames)
