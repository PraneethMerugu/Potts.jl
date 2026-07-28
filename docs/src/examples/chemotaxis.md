# [Follow the Gradient](@id chemotaxis-example)

This example couples a single finite cell to a prescribed scalar field. It is a compact field and
drive example, not a claim about a particular biological assay.

```@example chemotaxis
using PottsToolkit
using MakiePotts
import CorePotts

problem = PottsToolkit.ReferenceModels.chemotaxis_problem(
    (18, 18);
    profile = :linear,
    target_volume = 14,
    sensitivity = 20,
    tspan = (0, 20),
    seed = 21,
)
solution = CorePotts.solve(
    problem,
    BudgetedSequentialCPM(AttemptsPerSite(4); temperature = 4.0f0);
    saveat = 4,
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)

function cell_centroid_x(saved)
    state = CorePotts.snapshot_state(saved)
    cell_id = only(CorePotts.active_cell_ids(state))
    xs = Float64[]
    for site in CartesianIndices(CorePotts.lattice_size(state))
        owner = CorePotts.owner_at(state, site)
        CorePotts.is_cell_owner(owner) || continue
        CorePotts.cell_id(owner) == cell_id && push!(xs, site[1])
    end
    return sum(xs) / length(xs)
end

centroid_x = cell_centroid_x.(solution.u)
displacement = last(centroid_x) - first(centroid_x)
frames = renderframes(solution)
@assert solution.stats.completed_mcs == 20
@assert displacement > 0
@assert length(frames) == length(solution.t)
result = (; problem, solution, centroid_x, displacement,
    gradient_axis = 1, gradient_direction = :positive, frames)

(result.centroid_x, result.displacement, result.gradient_direction)
```

```@example chemotaxis
using CairoMakie

figure, axis, potts_plot = plot(
    last(result.frames);
    axis = (; title = "Cell after moving up the prescribed gradient"),
    boundaries = true,
)
potts_legend(figure[1, 2], potts_plot)
figure
```

The reusable model declares:

- one medium and one migrating cell type;
- a volume constraint;
- pairwise adhesion;
- a cell-centered field with no-flux boundaries and multilinear interpolation;
- a chemotactic drive with an explicit response law and extension/retraction mode.

The problem constructor binds the reusable field declaration to a realized gradient array and
places one connected cell.

The source asserts positive displacement along the declared positive gradient axis. It uses
`BudgetedSequentialCPM(AttemptsPerSite(4))`, making the additional copy-attempt budget explicit
instead of changing the meaning of ordinary `SequentialCPM`.

Change only one interpretation at a time: the `profile` changes the realized field, `sensitivity`
changes drive strength, and the chemotaxis `mode` changes whether extension, retraction, or both
contribute work.

Teaching inspiration: task-oriented migration examples in
[CC3D QuickModels](https://compucell3d.org/QuickModels). The implementation is original and makes
no assay-specific validation claim.
