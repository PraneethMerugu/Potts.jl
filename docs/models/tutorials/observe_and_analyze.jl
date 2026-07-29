using PottsToolkit
import CorePotts

# Declare only the scientific observations this analysis will consume.
medium = Medium(:medium)
cell = CellType(:cell)
volumes = CellVolume()
types = CellTypeObservable()
ownership = LatticeOwnership()
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 4, strength = 2)),
    volumes,
    types,
    ownership,
)
mask = falses(6, 6)
mask[3:4, 3:4] .= true
problem = PottsProblem(
    model,
    CartesianDomain((6, 6)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 2),
    seed = 4,
)
requested = ObservationSet(volumes, types, ownership)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 0.0f0);
    snapshot_policy = observation_policy(requested),
)
volume_series = observe(solution, volumes)
rows = observation_table(solution, volumes, types)

@assert length(volume_series) == length(solution.t)
@assert !isempty(rows)
result = (; solution, volume_series, rows,
    ownership_series = observe(solution, ownership))
