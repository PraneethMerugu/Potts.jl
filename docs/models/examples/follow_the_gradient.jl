using PottsToolkit
import CorePotts

problem = PottsToolkit.ReferenceModels.chemotaxis_problem(
    (18, 18);
    profile = :linear,
    target_volume = 14,
    sensitivity = 20,
    tspan = (0, 20),
    seed = 21,
)
solution = CorePotts.solve(
    problem,
    BudgetedSequentialCPM(AttemptsPerSite(4); temperature = 4.0f0);
    saveat = 4,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

function cell_centroid_x(saved)
    state = CorePotts.snapshot_state(saved)
    cell_id = only(CorePotts.active_cell_ids(state))
    xs = Float64[]
    for site in CartesianIndices(CorePotts.lattice_size(state))
        owner = CorePotts.owner_at(state, site)
        CorePotts.is_cell_owner(owner) || continue
        CorePotts.cell_id(owner) == cell_id && push!(xs, site[1])
    end
    return sum(xs) / length(xs)
end

centroid_x = cell_centroid_x.(solution.u)
displacement = last(centroid_x) - first(centroid_x)
@assert solution.stats.completed_mcs == 20
@assert displacement > 0
result = (; problem, solution, centroid_x, displacement,
    gradient_axis = 1, gradient_direction = :positive)
