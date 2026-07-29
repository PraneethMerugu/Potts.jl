using PottsToolkit
using MakiePotts
import CorePotts

# Give cycling and retiring cells separate lifecycle rules.
medium = Medium(:Medium)
cycling = CellType(:CyclingCell)
retiring = CellType(:RetiringCell)
volume = Volume(
    cycling => (target = 6, strength = 2),
    retiring => (target = 6, strength = 2),
)
contact_energy = PairwiseLaw(
    :contact_energy,
    (medium, medium) => 0,
    (medium, cycling) => 4,
    (medium, retiring) => 4,
    (cycling, cycling) => 10,
    (retiring, retiring) => 10,
    (cycling, retiring) => 10,
)
growth = Growth(volume, cycling; rate = 2)
division = Division(
    cycling;
    geometry = RandomOrientationSplit(),
    trigger = PropertyAtLeast(:volume__target, Float32(7)),
)
retirement = ImmediateDeath(retiring; medium, schedule = AtMCS(4))
model = PottsModel(
    medium, cycling, retiring, volume, Adhesion(contact_energy),
    growth, division, retirement)

# Start one cell of each type so both lifecycle events are visible.
labels = zeros(UInt64, 16, 16)
labels[5:7, 8:9] .= 1
labels[11:13, 8:9] .= 2
problem = PottsProblem(
    model,
    CartesianDomain((16, 16)),
    Layout(LabelledCells(labels, [1 => cycling, 2 => retiring]));
    capacity = 16,
    tspan = (0, 8),
    seed = 12,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 1.0f0);
    saveat = 1,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

# Count the full population and the retiring subtype at each saved MCS.
states = CorePotts.snapshot_state.(solution.u)
cell_counts = CorePotts.n_cells.(states)
retiring_counts = [
    count(cell_id -> CorePotts.cell_type(state, cell_id) == CorePotts.CellTypeID(2),
        CorePotts.active_cell_ids(state))
    for state in states
]
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 8
@assert maximum(cell_counts) > first(cell_counts)
@assert first(retiring_counts) == 1
@assert last(retiring_counts) == 0
@assert length(frames) == length(solution.t)
result = (; model, problem, solution, cell_counts, retiring_counts,
    initial_cells = first(cell_counts), final_cells = last(cell_counts),
    retirement_mcs = 4, frames)
