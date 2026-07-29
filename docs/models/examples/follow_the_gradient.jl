using PottsToolkit
using MakiePotts
import CorePotts

# The field declaration describes semantics; the numeric gradient is bound later.
medium = Medium(:Medium)
cell = CellType(:MigratingCell)
gradient = Field(
    :chemo_gradient;
    placement = CellCentered(),
    boundary = NoFlux(),
    interpolation = Multilinear(),
)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 14, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 0,
    ),
    gradient,
    Chemotaxis(gradient, cell => 40),
)

# Concentration rises from left to right; the cell starts left of center.
shape = (18, 18)
gradient_values = repeat(
    reshape(range(0.0f0, 1.0f0; length = shape[1]), :, 1),
    1,
    shape[2],
)
mask = falses(shape)
mask[4:7, 8:11] .= true
problem = PottsProblem(
    model,
    CartesianDomain(
        shape;
        boundaries = ntuple(_ -> AxisBoundary(ClosedBoundary()), 2),
    ),
    Layout(Place(cell, mask; identity = 1));
    fields = (gradient => gradient_values,),
    capacity = 2,
    tspan = (0, 24),
    seed = 21,
)
solution = CorePotts.solve(
    problem,
    BudgetedSequentialCPM(AttemptsPerSite(8); temperature = 4.0f0);
    saveat = 3,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

# Measure the x coordinate of the same finite cell in every saved state.
function cell_centroid(saved)
    state = CorePotts.snapshot_state(saved)
    cell_id = only(CorePotts.active_cell_ids(state))
    sites = [
        site for site in CartesianIndices(CorePotts.lattice_size(state))
        if (owner = CorePotts.owner_at(state, site);
            CorePotts.is_cell_owner(owner) && CorePotts.cell_id(owner) == cell_id)
    ]
    return (
        sum(site[1] for site in sites) / length(sites),
        sum(site[2] for site in sites) / length(sites),
    )
end

centroids = cell_centroid.(solution.u)
displacement = last(centroids)[1] - first(centroids)[1]
frames = renderframes(solution)
@assert solution.stats.completed_mcs == 24
@assert displacement > 0
@assert length(frames) == length(solution.t)
result = (; problem, solution, gradient_values, centroids, displacement, frames)
