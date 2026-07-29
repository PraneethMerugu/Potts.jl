# [A cell follows a prescribed gradient](@id chemotaxis-example)

A finite cell starts on the low-concentration side of a linear field. The visualization shows the
field, cell, trajectory, and x displacement together—so the advertised mechanism is visible rather
than inferred from a final lattice.

## Declare field semantics and chemotactic work

```@example chemotaxis
using PottsToolkit
using MakiePotts
import CorePotts

# The field declaration describes semantics; the numeric gradient is bound later.
medium = Medium(:Medium)
cell = CellType(:MigratingCell)
gradient = Field(
    :chemo_gradient;
    placement = CellCentered(),
    boundary = NoFlux(),
    interpolation = Multilinear(),
)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 14, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 8,
        (cell, cell) => 0,
    ),
    gradient,
    Chemotaxis(gradient, cell => 40),
)
nothing # hide
```

`Field` declares placement, boundary behavior, and interpolation. `Chemotaxis` connects that field
to the migrating cell type with an explicit sensitivity.

## Bind the array and place the cell

```@example chemotaxis
# Concentration rises from left to right; the cell starts left of center.
shape = (18, 18)
gradient_values = repeat(
    reshape(range(0.0f0, 1.0f0; length = shape[1]), :, 1),
    1,
    shape[2],
)
mask = falses(shape)
mask[4:7, 8:11] .= true
problem = PottsProblem(
    model,
    CartesianDomain(
        shape;
        boundaries = ntuple(_ -> AxisBoundary(ClosedBoundary()), 2),
    ),
    Layout(Place(cell, mask; identity = 1));
    fields = (gradient => gradient_values,),
    capacity = 2,
    tspan = (0, 24),
    seed = 21,
)
solution = CorePotts.solve(
    problem,
    BudgetedSequentialCPM(AttemptsPerSite(8); temperature = 4.0f0);
    saveat = 3,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
nothing # hide
```

The declaration is reusable; `gradient_values` is experiment-specific realized data.

## Measure the trajectory

```@example chemotaxis
# Measure the x coordinate of the same finite cell in every saved state.
function cell_centroid(saved)
    state = CorePotts.snapshot_state(saved)
    cell_id = only(CorePotts.active_cell_ids(state))
    sites = [
        site for site in CartesianIndices(CorePotts.lattice_size(state))
        if (owner = CorePotts.owner_at(state, site);
            CorePotts.is_cell_owner(owner) && CorePotts.cell_id(owner) == cell_id)
    ]
    return (
        sum(site[1] for site in sites) / length(sites),
        sum(site[2] for site in sites) / length(sites),
    )
end

centroids = cell_centroid.(solution.u)
displacement = last(centroids)[1] - first(centroids)[1]
frames = renderframes(solution)
@assert solution.stats.completed_mcs == 24
@assert displacement > 0
@assert length(frames) == length(solution.t)
result = (; problem, solution, gradient_values, centroids, displacement, frames)

result.displacement
```

## Watch the cell and its displacement

```@example chemotaxis
using CairoMakie

figure = Figure(size = (1080, 520))
field_axis = Axis(
    figure[1, 1];
    title = "Prescribed field + cell · 0 MCS",
    xlabel = "x",
    ylabel = "y",
    aspect = DataAspect(),
)
displacement_axis = Axis(
    figure[1, 2];
    title = "Directed displacement",
    xlabel = "Monte Carlo steps",
    ylabel = "centroid x − initial x",
)
heatmap!(field_axis, result.gradient_values; colormap = :viridis)
frame_observable = Observable(first(result.frames))
path_x = Observable([first(result.centroids)[1]])
path_y = Observable([first(result.centroids)[2]])
shown_mcs = Observable(result.solution.t[1:1])
shown_displacement = Observable([0.0])
cell_plot = pottsplot!(
    field_axis,
    frame_observable;
    boundaries = true,
    medium_color = (:white, 0.15),
    alpha = 0.82,
)
lines!(field_axis, path_x, path_y; color = :white, linewidth = 4)
scatter!(field_axis, path_x, path_y; color = :white, markersize = 8)
lines!(displacement_axis, shown_mcs, shown_displacement; linewidth = 3)
scatter!(displacement_axis, shown_mcs, shown_displacement; markersize = 9)
xlims!(displacement_axis, first(result.solution.t), last(result.solution.t))
all_displacements = first.(result.centroids) .- first(result.centroids)[1]
ylims!(displacement_axis, minimum(all_displacements) - 1, maximum(all_displacements) + 1)
potts_legend(figure[1, 3], cell_plot)

initial_x = first(result.centroids)[1]
record_potts(
    "chemotaxis.mp4",
    figure,
    eachindex(result.frames);
    framerate = 3,
    update! = index -> begin
    frame_observable[] = result.frames[index]
    path_x[] = first.(result.centroids[1:index])
    path_y[] = last.(result.centroids[1:index])
    shown_mcs[] = result.solution.t[1:index]
    shown_displacement[] = first.(result.centroids[1:index]) .- initial_x
    field_axis.title = "Prescribed field + cell · $(result.solution.t[index]) MCS"
    end,
)
save("chemotaxis-preview.svg", figure)
figure
```

![Animation of a cell moving on a visible prescribed gradient with its centroid displacement.](chemotaxis.mp4)

The positive displacement assertion supports a bounded directional-mechanism example. It is not
validation of a particular cell type or assay.
