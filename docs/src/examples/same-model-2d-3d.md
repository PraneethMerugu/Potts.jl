# [Same Model in 2D and 3D](@id same-model-2d-3d)

Reference constructors accept dimension-generic shapes, while realized geometry, volume, and
computational cost remain dimension-specific.

```@example same-model-2d-3d
using PottsToolkit
using MakiePotts
import CorePotts

problems = (
    PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
        (10, 10); target_volume = 12, tspan = (0, 2), seed = 9),
    PottsToolkit.ReferenceModels.single_cell_fluctuation_problem(
        (7, 7, 7); target_volume = 16, tspan = (0, 2), seed = 9),
)
algorithm = SequentialCPM(temperature = 2.0f0)
reports = map(problem -> backend_report(problem, algorithm), problems)
solutions = map(problem -> CorePotts.solve(
    problem, algorithm;
    snapshot_policy = CorePotts.HostSnapshotPolicy()), problems)
dimensions = map(problem -> length(CorePotts.lattice_size(problem.u0)), problems)
frames = (
    renderframe(solutions[1]),
    renderframe(
        solutions[2],
        RenderRequest(extent = OrthogonalSlice(3, 4))),
)

@assert dimensions == (2, 3)
@assert all(report -> report.qualified, reports)
@assert all(solution -> solution.stats.completed_mcs == 2, solutions)
@assert frame_size.(frames) == ((10, 10), (7, 7))
result = (; problems, reports, solutions, dimensions, frames)

(result.dimensions,
    map(report -> report.qualified, result.reports),
    map(solution -> solution.stats.completed_mcs, result.solutions))
```

```@example same-model-2d-3d
using CairoMakie

figure = Figure(size = (900, 360))
axis_2d = Axis(figure[1, 1], title = "2D domain", aspect = DataAspect())
plot_2d = pottsplot!(axis_2d, result.frames[1]; boundaries = true)
axis_3d = Axis(
    figure[1, 2], title = "3D domain · z = 4", aspect = DataAspect())
plot_3d = pottsplot!(axis_3d, result.frames[2]; boundaries = true)
potts_legend(figure[1, 3], plot_2d)
figure
```

The source constructs related two- and three-dimensional fluctuating-cell problems, preflights
both, and requires both bounded runs to complete. It does not claim that equal numeric parameters
have equal physical meaning across dimensions.

For visualization, materialize a full 2D frame or an `OrthogonalSlice` of a 3D state. Record the
slice axis and index with exported output.

Teaching inspiration: the dimension progression in
[CellularPotts.jl Going 3D](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/Going3D/Going3D/).
The source is original PottsToolkit code.
