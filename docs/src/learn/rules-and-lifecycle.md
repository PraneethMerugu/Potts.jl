# [Rules and lifecycle](@id rules-and-lifecycle)

Lifecycle behavior is explicit state transition, not an afterthought hidden in callbacks. A model
declares properties, update rules, triggers, geometry, inheritance, conflict policy, and capacity.

## Properties and rules

Properties carry value type, initializer, mutability, and lifecycle policies. Rules read from a
declared snapshot and write through registered effects. This makes dependencies and continuation
state inspectable before execution.

`Growth` is the high-level target-volume update. More general rules can use supported property,
spatial-query, schedule, and event expressions without reaching into engine arrays.

## Division and retirement

`Division` combines:

- the admitted parent cell type;
- a trigger such as `PropertyAtLeast`;
- geometry such as `RandomOrientationSplit`;
- declared daughter property policies.

Type transition, shrink death, and immediate removal have separate semantics. Cell identity is
generation-aware, so analysis must join longitudinal records on both ID and generation.

```@example rules-and-lifecycle
using PottsToolkit
import CorePotts

# Growth updates a property; division reads that property through an explicit trigger.
medium = Medium(:Medium)
cell = CellType(:CyclingCell)
volume = Volume(cell => (target = 6, strength = 2))
model = PottsModel(
    medium,
    cell,
    volume,
    Growth(volume, cell; rate = 1),
    Division(
        cell;
        geometry = RandomOrientationSplit(),
        trigger = PropertyAtLeast(:volume__target, Float32(8)),
    ),
)
mask = falses(12, 12)
mask[5:7, 5:6] .= true
problem = PottsProblem(
    model,
    CartesianDomain((12, 12)),
    Layout(Place(cell, mask; identity = 1));
    capacity = 8,
    tspan = (0, 2),
    seed = 12,
)
solution = CorePotts.solve(
    problem,
    SequentialCPM();
    snapshot_policy = CorePotts.HostSnapshotPolicy(),
)
final_state = CorePotts.snapshot_state(last(solution.u))

@assert isvalid(model)
@assert CorePotts.n_cells(final_state) >= 1
result = (; model, problem, completed_mcs = solution.stats.completed_mcs,
    final_cells = CorePotts.n_cells(final_state))

(isvalid(result.model), result.completed_mcs, result.final_cells)
```

The canonical program uses a deliberately small threshold for a fast smoke. It proves the
growth/division mechanism executes and leaves a valid live population; it is not a calibrated cell
cycle.

## Conflict and capacity rules

Triggers are evaluated against their declared snapshot. Conflicting requests use the model's
explicit lifecycle conflict policy and commit only at the registered phase. A failure must not
expose partially committed state.

Capacity must cover the maximum population admitted by the study. Treat exhaustion as a model or
run-design defect, not as a reason to resize silently.

The [Grow, Divide, Retire](@ref growth-division-example) example records a quantitative cell-count
trace and renders the final cell identities with MakiePotts.
