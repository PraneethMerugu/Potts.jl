# [Two Populations Sort](@id differential-adhesion-example)

This example initializes a confluent checkerboard of two populations with lower within-population
contact energy than heterotypic contact energy.

```@example sorting
using PottsToolkit
using MakiePotts
import CorePotts

model = PottsToolkit.ReferenceModels.differential_adhesion_model(
    target_volume = 16,
    within_a = 2,
    within_b = 2,
    between = 18,
    medium_contact = 20,
)
populations = Tuple(
    declaration for declaration in model.declarations
    if declaration isa CellType)
labels = zeros(UInt64, 24, 24)
assignments = Pair{UInt64, CellType}[]
for block_y in 0:2, block_x in 0:3
    cell_id = 4block_y + block_x + 1
    labels[(4block_x + 5):(4block_x + 8),
        (4block_y + 7):(4block_y + 10)] .= cell_id
    push!(assignments, UInt64(cell_id) => populations[isodd(cell_id) ? 1 : 2])
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
    saveat = 40,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

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
@assert all(>=(0), contact_trace)
@assert first(contact_trace) > 0
@assert last(contact_trace) < first(contact_trace)
@assert length(frames) == length(solution.t)
result = (; problem, solution, contact_trace,
    initial_contacts = first(contact_trace), final_contacts = last(contact_trace),
    between_energy = 18, within_energy = 2, frames)

(result.initial_contacts, result.final_contacts,
    result.within_energy, result.between_energy)
```

```@example sorting
using CairoMakie

figure, axis, potts_plot = plot(
    last(result.frames);
    axis = (; title = "Two populations after 200 MCS"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The canonical source reports a heterotypic-contact trace and asserts that the initial condition
contains measurable heterotypic interfaces. Its energy contrast is quantitative:
`between_energy - within_energy == 16`.

The deterministic smoke ends with fewer heterotypic contacts than it starts with. That verifies
the mechanism, statistic, executable source, and one bounded trajectory; it is not a convergence or
equilibrium claim. A scientific sorting study must predeclare its segregation statistic, burn-in
or stopping rule, replicates, algorithm, attempt normalization, temperature, initialization
distribution, and evidence target.

Teaching inspiration: [CC3D QuickModels](https://compucell3d.org/QuickModels). This is a clean
original PottsToolkit implementation, not translated CC3D code.
