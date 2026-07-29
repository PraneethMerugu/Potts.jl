# [Two populations reduce unlike contacts](@id differential-adhesion-example)

Twelve cells begin in an alternating checkerboard. Contacts within either population cost 2;
contacts between populations cost 18. The animation shows the evolving lattice while the trace
measures the interfaces that the mechanism is expected to reduce.

## Declare the differential-adhesion model

```@example sorting
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
nothing # hide
```

The full contact table is visible. Lower same-population energies favor like-like interfaces, but a
sorting claim still needs a statistic; a plausible-looking final frame is not enough.

## Build a deliberately mixed initial condition

```@example sorting
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
nothing # hide
```

`AttemptsPerSite(4)` explicitly adds four copy-attempt budgets per lattice site per MCS. It does not
silently redefine ordinary `SequentialCPM`.

## Count unlike interfaces

```@example sorting
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

(first(result.contact_trace), last(result.contact_trace),
    result.within_energy, result.between_energy)
```

## Watch sorting and its statistic

```@example sorting
using CairoMakie

figure = Figure(size = (1060, 520))
state_axis = Axis(figure[1, 1]; title = "Cell types · 0 MCS", aspect = DataAspect())
contact_axis = Axis(
    figure[1, 2];
    title = "Unlike interfaces",
    xlabel = "Monte Carlo steps",
    ylabel = "Heterotypic lattice edges",
)
frame_observable = Observable(first(result.frames))
shown_mcs = Observable(result.solution.t[1:1])
shown_contacts = Observable(result.contact_trace[1:1])
state_plot = pottsplot!(state_axis, frame_observable; boundaries = true)
lines!(contact_axis, shown_mcs, shown_contacts; linewidth = 3)
scatter!(contact_axis, shown_mcs, shown_contacts; markersize = 10)
xlims!(contact_axis, first(result.solution.t), last(result.solution.t))
ylims!(contact_axis, 0, 1.15maximum(result.contact_trace))
potts_legend(figure[1, 3], state_plot)

record_potts(
    "sorting.mp4",
    figure,
    eachindex(result.frames);
    framerate = 3,
    update! = index -> begin
    frame_observable[] = result.frames[index]
    shown_mcs[] = result.solution.t[1:index]
    shown_contacts[] = result.contact_trace[1:index]
    state_axis.title = "Cell types · $(result.solution.t[index]) MCS"
    end,
)
save("sorting-preview.svg", figure)
figure
```

![Animation of two cell populations sorting while their heterotypic contact count is traced.](sorting.mp4)

The final value is lower for this pinned trajectory; the curve is not required to be monotonic.
A scientific sorting study must additionally declare replicates, initialization distribution,
algorithm, attempt normalization, temperature, stopping rule, statistic, and uncertainty.

Teaching inspiration: outcome-first migration and sorting examples in
[CC3D QuickModels](https://compucell3d.org/QuickModels). The implementation is original.
