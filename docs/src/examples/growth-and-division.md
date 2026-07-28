# [Grow, Divide, Retire](@id growth-division-example)

This example combines volume-target growth, threshold-triggered division, and scheduled retirement.

```@example division
using PottsToolkit
using MakiePotts
import CorePotts

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

(result.cell_counts, result.retiring_counts, result.retirement_mcs)
```

```@example division
using CairoMakie

figure, axis, potts_plot = plot(
    last(result.frames);
    encoding = CellIdentityEncoding(),
    axis = (; title = "Cell identities after division and retirement"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The model uses:

- `Growth` to update the target-volume property;
- `PropertyAtLeast` to request division at a declared threshold;
- `RandomOrientationSplit` for division geometry;
- `ImmediateDeath` for explicit retirement of a separately typed seed at MCS 4;
- explicit property inheritance policies during daughter construction.

The assertions require the maximum live-cell count to exceed the initial count and the scheduled
retiring population to fall from one cell to zero. The short threshold and retirement schedule are
chosen for an executable mechanism example, not as biological cell-cycle or death calibration.

Capacity must cover the maximum admitted live population. Exhausting capacity is an error, not an
implicit lattice resize. Cell identity is generation-aware across retirement and slot reuse, so
analysis should join observations by `(cell_id, generation)`.

Teaching inspiration: lifecycle workflows in the
[CC3D reference manual](https://compucell3dreferencemanual.readthedocs.io/en/latest/). The source
is an original PottsToolkit model.
