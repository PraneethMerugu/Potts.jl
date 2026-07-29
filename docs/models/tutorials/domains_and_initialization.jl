using PottsToolkit
import CorePotts

# Domain boundaries and obstacles are experiment geometry, not cell biology.
medium = Medium(:medium)
cell = CellType(:cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 4, strength = 2)),
)
domain = CartesianDomain(
    (6, 6);
    boundaries = (
        AxisBoundary(ClosedBoundary()),
        AxisBoundary(FixedExterior(CorePotts.MediumOwner(1))),
    ),
    obstacles = (
        CartesianIndex(3, 3) => CorePotts.MediumOwner(1),
        CartesianIndex(4, 3) => CorePotts.MediumOwner(1),
    ),
)
mask = falses(6, 6)
mask[2:3, 4:5] .= true
problem = PottsProblem(
    model,
    domain,
    Layout(Place(cell, mask; identity = 1));
    capacity = 4,
    tspan = (0, 1),
    seed = 3,
)

@assert CorePotts.mutable_site_count(domain) == 34
@assert backend_report(problem, SequentialCPM()).qualified
result = (; problem, mutable_sites = CorePotts.mutable_site_count(domain),
    initial_cells = CorePotts.n_cells(problem.u0), declared_capacity = 4)
