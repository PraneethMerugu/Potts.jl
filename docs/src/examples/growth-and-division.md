# [Cells grow, divide, and retire](@id growth-division-example)

One cell grows and divides when its target-volume property crosses a threshold. A second,
separately typed cell retires at MCS 4. The animation pairs generation-aware identities with the
population counts that prove both lifecycle events occurred.

## Declare three lifecycle rules

```@example division
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
nothing # hide
```

Growth changes the declared volume target. Division has an explicit trigger and geometry.
Retirement targets only the `RetiringCell` type at a declared schedule.

## Place one cell on each path

```@example division
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
nothing # hide
```

Capacity must cover the maximum admitted live population. Exhaustion is an error, not an implicit
resize.

## Verify division and retirement

```@example division
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

(result.cell_counts, result.retiring_counts)
```

## Watch identities and population size

```@example division
using CairoMakie

figure = Figure(size = (1080, 520))
state_axis = Axis(figure[1, 1]; title = "Cell identities · 0 MCS", aspect = DataAspect())
count_axis = Axis(
    figure[1, 2];
    title = "Lifecycle events",
    xlabel = "Monte Carlo steps",
    ylabel = "Live cells",
)
frame_observable = Observable(first(result.frames))
shown_mcs = Observable(result.solution.t[1:1])
shown_cells = Observable(result.cell_counts[1:1])
shown_retiring = Observable(result.retiring_counts[1:1])
state_plot = pottsplot!(
    state_axis,
    frame_observable;
    encoding = CellIdentityEncoding(),
    boundaries = true,
)
lines!(count_axis, shown_mcs, shown_cells; linewidth = 3, label = "all cells")
lines!(count_axis, shown_mcs, shown_retiring;
    linewidth = 3, linestyle = :dash, label = "retiring type")
vlines!(count_axis, [result.retirement_mcs];
    color = :gray45, linestyle = :dot, label = "scheduled retirement")
xlims!(count_axis, first(result.solution.t), last(result.solution.t))
ylims!(count_axis, 0, maximum(result.cell_counts) + 1)
axislegend(count_axis; position = :lt)
potts_legend(figure[1, 3], state_plot; title = "Generation-aware identity")

record_potts(
    "growth-and-division.mp4",
    figure,
    eachindex(result.frames);
    framerate = 2,
    update! = index -> begin
        frame_observable[] = result.frames[index]
        shown_mcs[] = result.solution.t[1:index]
        shown_cells[] = result.cell_counts[1:index]
        shown_retiring[] = result.retiring_counts[1:index]
        state_axis.title = "Cell identities · $(result.solution.t[index]) MCS"
    end,
)
save("growth-and-division-preview.svg", figure)
figure
```

![Animation of growth, division, and scheduled retirement with live population traces.](growth-and-division.mp4)

The short threshold and schedule are chosen to expose the API, not as biological calibration.
Analysis should join cell histories by `(cell_id, generation)` because retirement and slot reuse are
generation-aware.
