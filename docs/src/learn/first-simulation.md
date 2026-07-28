# [Your first simulation](@id first-simulation)

In this tutorial you will build a complete Cellular Potts model, run it for 30 Monte Carlo steps,
and inspect both the cell geometry and its volume trajectory. Nothing important is hidden behind a
reference-problem constructor.

## 1. Declare the model

PottsToolkit models read like a list of biological and mechanical declarations. This cell has a
preferred volume and pays contact energy where it meets the medium.

```@example first-simulation
using PottsToolkit
using MakiePotts
import CorePotts

# Declare the biological vocabulary and the two energetic mechanisms.
medium = Medium(:Medium)
cell = CellType(:Cell)
target_volume = 36
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = target_volume, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 0,
    ),
)
nothing # hide
```

The pairwise table is explicit: there is no implied default for an omitted biological contact.
`Volume` and `Adhesion` are reusable declarations; lattice size and initial placement come next.

## 2. Place a deliberately undersized cell

The cell begins as a 4×4 square—16 lattice sites—while its target is 36. That mismatch gives the
simulation a visible question to answer.

```@example first-simulation
# Start one cell below its target so the trajectory has something to explain.
mask = falses(20, 20)
mask[9:12, 9:12] .= true
problem = PottsProblem(
    model,
    CartesianDomain((20, 20)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 30),
    seed = 11,
)
nothing # hide
```

`capacity` reserves finite-cell identities; it is not the lattice size. The fixed seed makes this
exact teaching trajectory reproducible.

## 3. Solve and measure

`SequentialCPM` selects the update algorithm. A `HostSnapshotPolicy` is requested because the next
step needs complete saved states for analysis and rendering.

```@example first-simulation
# Save host snapshots because analysis and MakiePotts consume explicit saved state.
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 4.0f0);
    saveat = 5,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
states = CorePotts.snapshot_state.(solution.u)
cell_id = only(CorePotts.active_cell_ids(first(states)))
volume_trace = [CorePotts.finite_volume(state, cell_id) for state in states]
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 30
@assert length(frames) == length(solution.t) == length(volume_trace)
@assert all(>(0), volume_trace)
result = (; problem, solution, target_volume, volume_trace, frames)

(solution.retcode, volume_trace)
```

## 4. See geometry and measurement together

MakiePotts renders semantic cell types and boundaries directly from saved simulation state. The
volume trace uses ordinary Makie in the same figure, so the picture and measurement share one
reproducible result.

```@example first-simulation
using CairoMakie

figure = Figure(size = (980, 650))
initial_axis = Axis(
    figure[1, 1]; title = "Initial state · 0 MCS", aspect = DataAspect())
final_axis = Axis(
    figure[1, 2]; title = "Final state · 30 MCS", aspect = DataAspect())
initial_plot = pottsplot!(initial_axis, first(result.frames); boundaries = true)
pottsplot!(final_axis, last(result.frames); boundaries = true)
potts_legend(figure[1, 3], initial_plot)

trace_axis = Axis(
    figure[2, 1:2];
    title = "The cell approaches its preferred volume",
    xlabel = "Monte Carlo steps",
    ylabel = "Cell area (lattice sites)",
)
lines!(trace_axis, result.solution.t, result.volume_trace; linewidth = 3)
scatter!(trace_axis, result.solution.t, result.volume_trace; markersize = 10)
hlines!(trace_axis, [result.target_volume];
    color = :gray45, linestyle = :dash, label = "target = $(result.target_volume)")
axislegend(trace_axis; position = :rb)
figure
```

The trajectory is one seeded realization, not an equilibrium estimate. For a study, predeclare the
algorithm, temperature, initialization distribution, replicate count, summary statistic, and
stopping or burn-in rule.

## Where to go next

- [Compose a biological model](@ref build-model) adds multiple cell types.
- [Observe and analyze](@ref observe-and-analyze) uses typed observables and lean snapshots.
- [Visualize and export](@ref visualize-and-export) covers encodings, slices, and recording.
- [Algorithms and guarantees](@ref algorithms-and-guarantees) explains what an update rule does
  and does not guarantee.
