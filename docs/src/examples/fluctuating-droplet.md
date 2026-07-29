# [A droplet fluctuates around its preferred volume](@id fluctuating-droplet)

This example places mechanical noise in the volume-pressure declaration, then shows the resulting
shape, time series, and finite-sample distribution. It does not label a short trace as equilibrium.

## Declare noisy pressure explicitly

```@example fluctuating-droplet
using PottsToolkit
using MakiePotts
import CorePotts

# Noise enters the volume-pressure declaration, not an analysis afterthought.
medium = Medium(:Medium)
droplet = CellType(:Droplet)
target_volume = 24
model = PottsModel(
    medium,
    droplet,
    FluctuatingVolumePressure(
        droplet => (target = target_volume, strength = 1);
        eta = 0.2,
        noise = AcceptanceTemperature(),
    ),
    Adhesion(
        (medium, medium) => 0,
        (medium, droplet) => 8,
        (droplet, droplet) => 0,
    ),
)
nothing # hide
```

## Run a bounded fluctuation trace

```@example fluctuating-droplet
# A compact seed leaves room for the noisy interface to move.
mask = falses(18, 18)
mask[7:11, 7:11] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(droplet, mask; identity = 1));
    capacity = 2,
    tspan = (0, 60),
    seed = 31,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 3.0f0);
    saveat = 2,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
nothing # hide
```

## Calculate the trace and distribution

```@example fluctuating-droplet
# Report the time series and its finite-sample distribution side by side.
states = CorePotts.snapshot_state.(solution.u)
cell_id = only(CorePotts.active_cell_ids(first(states)))
volume_trace = [CorePotts.finite_volume(state, cell_id) for state in states]
mean_volume = sum(volume_trace) / length(volume_trace)
variance = sum((volume - mean_volume)^2 for volume in volume_trace) /
    length(volume_trace)
frames = renderframes(solution)

@assert solution.stats.completed_mcs == 60
@assert variance > 0
@assert length(frames) == length(solution.t)
result = (; problem, solution, target_volume, volume_trace, mean_volume, variance, frames)

(result.mean_volume, result.variance, extrema(result.volume_trace))
```

## See configuration, history, and sampled values

```@example fluctuating-droplet
using CairoMakie

figure = Figure(size = (1120, 680))
state_axis = Axis(figure[1, 1]; title = "Droplet · 60 MCS", aspect = DataAspect())
state_plot = pottsplot!(state_axis, last(result.frames); boundaries = true)
potts_legend(figure[1, 2], state_plot)

trace_axis = Axis(
    figure[1, 3];
    title = "Volume history",
    xlabel = "Monte Carlo steps",
    ylabel = "Area",
)
lines!(trace_axis, result.solution.t, result.volume_trace; linewidth = 3)
hlines!(trace_axis, [result.target_volume];
    color = :gray45, linestyle = :dash, label = "target")
axislegend(trace_axis; position = :rb)

distribution_axis = Axis(
    figure[2, 1:3];
    title = "Finite-sample volume distribution",
    xlabel = "Cell area (lattice sites)",
    ylabel = "Saved-state count",
)
hist!(distribution_axis, result.volume_trace; bins = minimum(result.volume_trace):maximum(result.volume_trace),
    color = (:steelblue, 0.75))
vlines!(distribution_axis, [result.mean_volume];
    color = :black, linewidth = 2, label = "sample mean")
axislegend(distribution_axis)
save("fluctuating-droplet-preview.svg", figure)
figure
```

The histogram summarizes this short, correlated trace. An equilibrium claim requires a qualified
algorithm plus declared burn-in, sampling interval, convergence checks, and replicate uncertainty.
