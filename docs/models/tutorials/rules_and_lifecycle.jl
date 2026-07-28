using PottsToolkit
import CorePotts

# Growth updates a property; division reads that property through an explicit trigger.
medium = Medium(:Medium)
cell = CellType(:CyclingCell)
volume = Volume(cell => (target = 6, strength = 2))
model = PottsModel(
    medium,
    cell,
    volume,
    Growth(volume, cell; rate = 1),
    Division(
        cell;
        geometry = RandomOrientationSplit(),
        trigger = PropertyAtLeast(:volume__target, Float32(8)),
    ),
)
mask = falses(12, 12)
mask[5:7, 5:6] .= true
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 8,
    tspan = (0, 2),
    seed = 12,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM();
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
final_state = CorePotts.snapshot_state(last(solution.u))

@assert isvalid(model)
@assert CorePotts.n_cells(final_state) >= 1
result = (; model, problem, completed_mcs = solution.stats.completed_mcs,
    final_cells = CorePotts.n_cells(final_state))
