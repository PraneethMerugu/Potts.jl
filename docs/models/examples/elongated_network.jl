using PottsToolkit
import CorePotts

model = PottsToolkit.ReferenceModels.elongation_driven_angiogenesis_model(
    target_volume = 8,
    target_elongation = 3.0,
    elongation_strength = 20,
    preserve_connectivity = true,
)
endothelial = only(
    declaration for declaration in model.declarations
    if declaration isa CellType)
labels = zeros(UInt64, 18, 18)
for (cell_id, x_range, y_range) in (
        (1, 5:8, 5:6),
        (2, 11:14, 5:6),
        (3, 5:8, 13:14),
        (4, 11:14, 13:14))
    labels[x_range, y_range] .= cell_id
end
problem = PottsProblem(
    model,
    CartesianDomain((18, 18);
        boundaries = ntuple(_ -> AxisBoundary(ClosedBoundary()), 2)),
    Layout(LabelledCells(
        labels, [cell_id => endothelial for cell_id in UInt64(1):UInt64(4)]));
    capacity = 8,
    tspan = (0, 100),
    seed = 44,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    saveat = 20,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

function mean_bounding_box_elongation(saved)
    state = CorePotts.snapshot_state(saved)
    elongations = Float64[]
    for cell_id in CorePotts.active_cell_ids(state)
        sites = CartesianIndex{2}[]
        for site in CartesianIndices(CorePotts.lattice_size(state))
            owner = CorePotts.owner_at(state, site)
            CorePotts.is_cell_owner(owner) || continue
            CorePotts.cell_id(owner) == cell_id && push!(sites, site)
        end
        widths = ntuple(axis -> begin
            coordinates = getindex.(Tuple.(sites), axis)
            maximum(coordinates) - minimum(coordinates) + 1
        end, 2)
        push!(elongations, max(widths...) / min(widths...))
    end
    return sum(elongations) / length(elongations)
end

elongation_trace = mean_bounding_box_elongation.(solution.u)
@assert isvalid(model)
@assert solution.stats.completed_mcs == 100
@assert CorePotts.n_cells(CorePotts.snapshot_state(last(solution.u))) == 4
@assert all(>=(1), elongation_trace)
result = (; model, problem, solution, target_elongation = 3.0,
    elongation_trace, connectivity_preserved = true)
