# [Stop and resume without changing the trajectory](@id stop-and-resume)

This example branches one simulation at MCS 3. The uninterrupted and restored branches then take
the same three additional steps and must end in exactly the same logical state.

## Build the checkpointed problem

```@example stop-and-resume
using PottsToolkit
using MakiePotts
import CorePotts

# Build the checkpoint example from the same public declarations users author.
medium = Medium(:Medium)
cell = CellType(:Cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 16, strength = 2)),
)
mask = falses(12, 12)
mask[5:8, 5:8] .= true
problem = PottsProblem(
    model,
    CartesianDomain(size(mask)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 6),
    seed = 101,
)
nothing # hide
```

## Branch at an exact checkpoint

```@example stop-and-resume
# Branch at MCS 3, then advance the original and restored integrators equally.
algorithm = SequentialCPM(temperature = 2.0f0)
uninterrupted = CorePotts.init(
    problem,
    algorithm;
    save_start = false,
    save_end = false,
)
CorePotts.step!(uninterrupted, 3)
checkpoint = CorePotts.capture_checkpoint(uninterrupted)
resumed = CorePotts.restore_checkpoint(checkpoint, problem, algorithm)
CorePotts.step!(uninterrupted, 3)
CorePotts.step!(resumed, 3)
nothing # hide
```

`restore_checkpoint` continues the same contract. `import_checkpoint` starts a new run after a
compatibility report and intentionally carries a weaker guarantee.

## Compare state, not screenshots

```@example stop-and-resume
# Compare logical state exactly; matching pictures alone would be too weak.
expected = CorePotts.logical_state(uninterrupted)
observed = CorePotts.logical_state(resumed)
exact_lattice = CorePotts.lattice_storage(expected) ==
    CorePotts.lattice_storage(observed)
uninterrupted_frame = renderframe(expected, problem; mcs = uninterrupted.t)
resumed_frame = renderframe(observed, problem; mcs = resumed.t)

@assert exact_lattice
@assert resumed.t == uninterrupted.t == 6
@assert frame_mcs(uninterrupted_frame) == frame_mcs(resumed_frame) == 6
result = (; problem, algorithm, checkpoint, exact_lattice,
    resumed_mcs = resumed.t, uninterrupted_frame, resumed_frame)

(result.checkpoint.mcs, result.resumed_mcs, result.exact_lattice)
```

## Inspect both branches

```@example stop-and-resume
using CairoMakie

figure = Figure(size = (980, 430))
original_axis = Axis(
    figure[1, 1]; title = "Uninterrupted · 6 MCS", aspect = DataAspect())
original_plot = pottsplot!(
    original_axis, result.uninterrupted_frame; boundaries = true)
resumed_axis = Axis(
    figure[1, 2]; title = "Restored · 6 MCS", aspect = DataAspect())
pottsplot!(resumed_axis, result.resumed_frame; boundaries = true)
potts_legend(figure[1, 3], original_plot)
Label(
    figure[2, 1:2],
    result.exact_lattice ? "Exact lattice equality ✓" : "Lattices differ";
    fontsize = 24,
)
save("stop-and-resume-preview.svg", figure)
figure
```

The side-by-side views communicate the result; the exact logical-state assertion proves it.
