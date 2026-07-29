# [One model, two and three dimensions](@id same-model-2d-3d)

The biological model below contains no dimensional constant. We bind it once to a 2D layout and
once to a 3D layout, preflight both, and visualize the 3D result through an explicit slice.

## Declare a dimension-independent model

```@example same-model-2d-3d
using PottsToolkit
using MakiePotts
import CorePotts

# The biological declarations do not encode a lattice dimension.
medium = Medium(:Medium)
cell = CellType(:Cell)
target_volume = 16
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = target_volume, strength = 2)),
)
algorithm = SequentialCPM(temperature = 2.0f0)
nothing # hide
```

The same numeric target does not automatically have the same physical interpretation in different
dimensions. The point here is API reuse, not cross-dimensional calibration.

## Bind dimension-specific geometry

```@example same-model-2d-3d
# Bind the same model to one planar mask and one volumetric mask.
mask_2d = falses(10, 10)
mask_2d[4:7, 4:7] .= true
mask_3d = falses(7, 7, 7)
mask_3d[3:5, 3:5, 3:4] .= true
problems = (
    PottsProblem(
        model,
        CartesianDomain(size(mask_2d)),
        Layout(Place(cell, mask_2d; identity = 1));
        capacity = 2,
        tspan = (0, 2),
        seed = 9,
    ),
    PottsProblem(
        model,
        CartesianDomain(size(mask_3d)),
        Layout(Place(cell, mask_3d; identity = 1));
        capacity = 2,
        tspan = (0, 2),
        seed = 9,
    ),
)
nothing # hide
```

## Preflight, solve, and request a slice

```@example same-model-2d-3d
# MakiePotts renders 2D directly and 3D through an explicit orthogonal slice.
reports = map(problem -> backend_report(problem, algorithm), problems)
solutions = map(problem -> CorePotts.solve(
    problem,
    algorithm;
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
), problems)
frames = (
    renderframe(solutions[1]),
    renderframe(solutions[2], RenderRequest(extent = OrthogonalSlice(3, 4))),
)

@assert all(report -> report.qualified, reports)
@assert all(solution -> solution.stats.completed_mcs == 2, solutions)
@assert frame_size.(frames) == ((10, 10), (7, 7))
result = (; model, problems, reports, solutions, frames)

(map(report -> report.qualified, result.reports), frame_size.(result.frames))
```

## Compare the rendered geometries

```@example same-model-2d-3d
using CairoMakie

figure = Figure(size = (960, 430))
axis_2d = Axis(
    figure[1, 1]; title = "2D result · full domain", aspect = DataAspect())
plot_2d = pottsplot!(axis_2d, result.frames[1]; boundaries = true)
axis_3d = Axis(
    figure[1, 2]; title = "3D result · z = 4 slice", aspect = DataAspect())
pottsplot!(axis_3d, result.frames[2]; boundaries = true)
potts_legend(figure[1, 3], plot_2d)
save("same-model-2d-3d-preview.svg", figure)
figure
```

`OrthogonalSlice(3, 4)` makes the visual projection part of the reproducible request. Record the
slice axis and index with exported output.

Teaching inspiration: [CellularPotts.jl Going 3D](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/Going3D/Going3D/).
The implementation is original PottsToolkit code.
