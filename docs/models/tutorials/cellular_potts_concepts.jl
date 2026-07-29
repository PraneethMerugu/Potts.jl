using PottsToolkit
import CorePotts

# A cell is an extended set of owned sites, not a point particle.
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(medium, cell, Volume(cell => (target = 12, strength = 2)))
mask = falses(8, 8)
mask[3:5, 3:6] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 1),
    seed = 7,
)
algorithm = SequentialCPM(temperature = 2.0f0)
profile = CorePotts.algorithm_guarantees(algorithm)
state = problem.u0
cell_id = only(CorePotts.active_cell_ids(state))

@assert CorePotts.finite_volume(state, cell_id) > 0
result = (; lattice_sites = prod(CorePotts.lattice_size(state)),
    occupied_sites = CorePotts.finite_volume(state, cell_id),
    temperature = algorithm.temperature,
    guarantee = profile.guarantee_label)
