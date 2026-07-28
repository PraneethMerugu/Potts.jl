# [Boundaries and Obstacles](@id boundaries-and-obstacles)

This example uses closed ownership boundaries and an immutable vertical obstacle segment. Obstacle
sites remain part of the rectangular array but cannot receive copy attempts.

```@example boundaries-and-obstacles
using PottsToolkit
using MakiePotts
import CorePotts

medium = Medium(:medium)
cell = CellType(:cell)
model = PottsModel(
    medium,
    cell,
    Volume(cell => (target = 6, strength = 2)),
    Adhesion(
        (medium, medium) => 0,
        (medium, cell) => 6,
        (cell, cell) => 2,
    ),
)
obstacles = Tuple(
    CartesianIndex(8, y) => CorePotts.MediumOwner(1) for y in 4:9)
domain = CartesianDomain(
    (14, 14);
    boundaries = (
        AxisBoundary(ClosedBoundary()),
        AxisBoundary(ClosedBoundary()),
    ),
    obstacles,
)
mask = falses(14, 14)
mask[4:5, 6:8] .= true
problem = PottsProblem(
    model,
    domain,
    Layout(Place(cell, mask; identity = 1));
    capacity = 2,
    tspan = (0, 4),
    seed = 71,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM(temperature = 2.0f0);
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
final_state = CorePotts.snapshot_state(last(solution.u))
frame = renderframe(solution)

@assert all(pair -> CorePotts.owner_at(final_state, first(pair)) == last(pair), obstacles)
@assert frame_size(frame) == (14, 14)
result = (; problem, solution, obstacle_count = length(obstacles),
    immutable_obstacles = true, frame)

(result.obstacle_count, result.immutable_obstacles,
    result.solution.stats.completed_mcs)
```

```@example boundaries-and-obstacles
using CairoMakie

figure, axis, potts_plot = plot(
    result.frame;
    axis = (; title = "Closed domain with immutable obstacles"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The numerical contract checks every obstacle site's final owner against the declared immutable
medium owner. That assertion is stronger than inspecting a wall-colored image.

Closed, periodic, and fixed-exterior faces express different ownership relations. Field boundary
conditions are separate and must be declared on the field. Do not infer one from the other.

Teaching inspiration: boundary-focused workflows in the
[CC3D reference manual](https://compucell3dreferencemanual.readthedocs.io/en/latest/). The model
and source are original.
