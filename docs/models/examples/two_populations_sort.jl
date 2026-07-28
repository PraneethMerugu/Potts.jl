using PottsToolkit
using MakiePotts
import CorePotts

# Heterotypic interfaces cost more than contacts within either population.
medium = Medium(:Medium)
population_a = CellType(:PopulationA)
population_b = CellType(:PopulationB)
within_energy = 2
between_energy = 18
model = PottsModel(
    medium,
    population_a,
    population_b,
    Volume(
        population_a => (target = 16, strength = 2),
        population_b => (target = 16, strength = 2),
    ),
    Adhesion(
        (medium, medium) => 0,
        (medium, population_a) => 20,
        (medium, population_b) => 20,
        (population_a, population_a) => within_energy,
        (population_b, population_b) => within_energy,
        (population_a, population_b) => between_energy,
    ),
)

# Twelve 4×4 cells begin in an alternating checkerboard.
labels = zeros(UInt64, 24, 24)
assignments = Pair{UInt64, CellType}[]
for block_y in 0:2, block_x in 0:3
    cell_id = 4block_y + block_x + 1
    labels[(4block_x + 5):(4block_x + 8),
        (4block_y + 7):(4block_y + 10)] .= cell_id
    population = isodd(cell_id) ? population_a : population_b
    push!(assignments, UInt64(cell_id) => population)
end
problem = PottsProblem(
    model,
    CartesianDomain((24, 24)),
    Layout(LabelledCells(labels, assignments));
    capacity = 16,
    tspan = (0, 200),
    seed = 8,
)
solution = CorePotts.solve(
    problem,
    BudgetedSequentialCPM(AttemptsPerSite(4); temperature = 8.0f0);
    saveat = 20,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

# Count unlike cell-cell edges once, using only positive lattice directions.
function heterotypic_contacts(saved)
    state = CorePotts.snapshot_state(saved)
    contacts = 0
    for site in CartesianIndices(CorePotts.lattice_size(state))
        owner = CorePotts.owner_at(state, site)
        CorePotts.is_cell_owner(owner) || continue
        for offset in (CartesianIndex(1, 0), CartesianIndex(0, 1))
            neighbor = site + offset
            checkbounds(Bool, CartesianIndices(CorePotts.lattice_size(state)), neighbor) ||
                continue
            other = CorePotts.owner_at(state, neighbor)
            CorePotts.is_cell_owner(other) || continue
            first_id = CorePotts.cell_id(owner)
            second_id = CorePotts.cell_id(other)
            first_id == second_id && continue
            CorePotts.cell_type(state, first_id) != CorePotts.cell_type(state, second_id) &&
                (contacts += 1)
        end
    end
    return contacts
end

contact_trace = heterotypic_contacts.(solution.u)
frames = renderframes(solution)
@assert solution.stats.completed_mcs == 200
@assert first(contact_trace) > 0
@assert last(contact_trace) < first(contact_trace)
@assert length(frames) == length(solution.t)
result = (; problem, solution, contact_trace, within_energy, between_energy, frames)
