# [Cells acquire elongated, connected shapes](@id elongated-network)

Four cells combine volume control, a major-axis elongation target, differential contact energy, and
per-cell connectivity preservation. This is a shape-mechanism example—not a validated
angiogenesis model.

## Compose shape mechanisms directly

```@example elongated-network
using PottsToolkit
using MakiePotts
import CorePotts

# Shape, contact, and connectivity mechanisms are independent declarations.
medium = Medium(:Medium)
network_cell = CellType(:NetworkCell)
target_elongation = 3.0
model = PottsModel(
    medium,
    network_cell,
    Volume(network_cell => (target = 8, strength = 2)),
    Elongation(network_cell => (target = target_elongation, strength = 20)),
    Adhesion(
        (medium, medium) => 0,
        (medium, network_cell) => 10,
        (network_cell, network_cell) => 4,
    ),
    PreserveConnectivity(),
)
nothing # hide
```

`PreserveConnectivity` prevents fragmentation of each finite cell. It does not assert that the
population forms one connected graph.

## Seed four legible cells

```@example elongated-network
# Four short bars begin separated so their shape evolution stays legible.
labels = zeros(UInt64, 18, 18)
for (cell_id, x_range, y_range) in (
        (1, 5:8, 5:6),
        (2, 11:14, 5:6),
        (3, 5:8, 13:14),
        (4, 11:14, 13:14))
    labels[x_range, y_range] .= cell_id
end
assignments = [UInt64(cell_id) => network_cell for cell_id in 1:4]
problem = PottsProblem(
    model,
    CartesianDomain(
        (18, 18);
        boundaries = ntuple(_ -> AxisBoundary(ClosedBoundary()), 2),
    ),
    Layout(LabelledCells(labels, assignments));
    capacity = 8,
    tspan = (0, 100),
    seed = 44,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    saveat = 10,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
nothing # hide
```

## Measure a transparent shape proxy

```@example elongated-network
# A bounding-box ratio is a transparent teaching proxy, not a vascular metric.
function mean_bounding_box_elongation(saved)
    state = CorePotts.snapshot_state(saved)
    elongations = Float64[]
    for cell_id in CorePotts.active_cell_ids(state)
        sites = [
            site for site in CartesianIndices(CorePotts.lattice_size(state))
            if (owner = CorePotts.owner_at(state, site);
                CorePotts.is_cell_owner(owner) && CorePotts.cell_id(owner) == cell_id)
        ]
        widths = ntuple(axis -> begin
            coordinates = getindex.(Tuple.(sites), axis)
            maximum(coordinates) - minimum(coordinates) + 1
        end, 2)
        push!(elongations, max(widths...) / min(widths...))
    end
    return sum(elongations) / length(elongations)
end

elongation_trace = mean_bounding_box_elongation.(solution.u)
frames = renderframes(solution)
@assert solution.stats.completed_mcs == 100
@assert CorePotts.n_cells(CorePotts.snapshot_state(last(solution.u))) == 4
@assert all(>=(1), elongation_trace)
@assert length(frames) == length(solution.t)
result = (; model, problem, solution, target_elongation, elongation_trace, frames)

result.elongation_trace
```

## Watch morphology and the proxy together

```@example elongated-network
using CairoMakie

figure = Figure(size = (1080, 520))
state_axis = Axis(figure[1, 1]; title = "Cell identities · 0 MCS", aspect = DataAspect())
shape_axis = Axis(
    figure[1, 2];
    title = "Mean bounding-box elongation",
    xlabel = "Monte Carlo steps",
    ylabel = "long side / short side",
)
frame_observable = Observable(first(result.frames))
shown_mcs = Observable(result.solution.t[1:1])
shown_elongation = Observable(result.elongation_trace[1:1])
state_plot = pottsplot!(
    state_axis,
    frame_observable;
    encoding = CellIdentityEncoding(),
    boundaries = true,
)
lines!(shape_axis, shown_mcs, shown_elongation; linewidth = 3)
scatter!(shape_axis, shown_mcs, shown_elongation; markersize = 9)
xlims!(shape_axis, first(result.solution.t), last(result.solution.t))
ylims!(shape_axis, 0, 1.15maximum(result.elongation_trace))
potts_legend(figure[1, 3], state_plot)

record_potts(
    "elongated-network.mp4",
    figure,
    eachindex(result.frames);
    framerate = 3,
    update! = index -> begin
        frame_observable[] = result.frames[index]
        shown_mcs[] = result.solution.t[1:index]
        shown_elongation[] = result.elongation_trace[1:index]
        state_axis.title = "Cell identities · $(result.solution.t[index]) MCS"
    end,
)
save("elongated-network-preview.svg", figure)
figure
```

![Animation of four connected cells changing shape with their elongation proxy.](elongated-network.mp4)

A network claim would require a separately defined graph, branch statistic, initialization
distribution, replicates, and uncertainty. Here the name describes the mechanism portfolio only.
