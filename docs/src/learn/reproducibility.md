# [Observe, checkpoint, and reproduce](@id observe-checkpoint-reproduce)

Saved states expose ownership, generation/kind metadata, declared state, and
requested observations. SymbolicIndexingInterface getters work on problems,
integrators, saved states, and solutions. A declared-but-unsaved observation
raises a different error from an unknown identity.

Use `SymbolicIndexingInterface.setu(integrator, state)` to build a setter for
one whole canonical state, then call it as `setter(integrator, value)`.
An array-valued symbolic variable accepts its whole fixed-array value, and a
product accepts its complete named tuple. A tuple of targets builds one
transaction, for example `setu(integrator, (amount, polarity))(integrator,
(2.0, SVector(1.0, 0.0)))`. Named target tuples also accept named replacement
values, including a subset of the selected names.
An empty named subset is a no-op after settlement. A setter may also be built
from the scheduled `PottsSystem` or `PottsProblem` and reused with its
integrators. Cached setters contain state indices: reuse requires the same
scheduled system and state schema, not an unrelated model. Rebuild setters after
changing or replacing the model.

Site values use the complete lattice-shaped buffer; cell values use every
compiled cell slot, including inactive slots. History values are chronological
tuples of source-shaped samples, oldest first, just as in initial conditions.
Replacement values and buffers are supplied on the host, including when the
integrator publishes into device storage; arbitrary device-array inputs are not
established by this workflow.
Values use the declaration's logical type, shape and unit references. Supply
compatible quantities for dimensional states; saved normalized numbers do not
implicitly acquire physical units when passed back to a setter.

Mutation first settles pending work, validates and converts every replacement,
then publishes through CorePotts' state transaction. Invalid values leave the
published state unchanged. The current `integrator.u` is refreshed, while
previously saved snapshots remain detached. A late failing ordinary callback
restores earlier state and parameter edits at that callback boundary. A failed
integrator cannot be repaired with a setter. Backend execution or copy failures
do not carry a general rollback guarantee.

Setters target stored states, not ownership, observations, derived expressions,
individual vector elements or product fields. Pure parameter setters retain the
usual `setp` behavior; mixed parameter/state target batches are not supported.
To change a field, construct and replace its whole logical value. Initial callback
edits occur before an explicit `AtMCS(0)` history capture; checkpoint restoration
preserves the stored history and does not repeat that capture.

`checkpoint(integrator)` captures the logical continuation state at a settled
boundary. Restore uses `init(...; checkpoint=...)` with the same problem and
execution identity. Native state, lifecycle generations,
relationships, replica/repeat identity, and replay evidence participate in
compatibility.

```@example replay
using Potts

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
system = PottsSystem(
    name=:replay_example,
    statements=StatementSet((
        Lattice((3, 3); boundary=Periodic()),
        cell,
        medium,
        Protocol(Sweep(; temperature=1.0); name=:main),
    )),
)
labels = zeros(Int, 3, 3)
labels[2, 2] = 1
problem = PottsProblem(
    system,
    PottsInitialState(
        ownership=LabelledCells(labels; cells=[cell], medium),
    ),
    (0, 2);
    seed=0x71,
)
integrator = init(problem, SequentialCPM(); save_start=false)
step!(integrator)
captured = checkpoint(integrator)
restored = init(
    problem,
    SequentialCPM();
    checkpoint=captured,
    save_start=false,
)
step!(integrator)
step!(restored)
integrator.u.ownership == restored.u.ownership
```

`remake` creates a related problem and invalidates only affected materialized
profiles. `replica` identifies an ensemble trajectory; `repeat` identifies a
retry of that trajectory. Both are part of semantic RNG addressing and persist
through checkpoints.

An authored `DrawKey` belongs to its qualified component and process at its
declared execution boundary. Draw identities use the Potts package UUID as their
owner namespace and are resolved together by CorePotts into two-word operation
keys. Reordering declarations, adding an unrelated draw, or changing a
distribution's parameters does not renumber existing operation keys. Renaming a
component, process, or draw does change its identity. Each component still
requires unique draw labels, including division geometry, random side selection,
and daughter-state redraws. Initialization uses the declared
`RandomSitePlacement` name, not its position in the placement list.

Scheduled assignments use the same `draw(distribution, DrawKey(:label))`
surface as proposal rules. For example, a cell-owned sampled signal can be
updated with `Synchronous(:sample_signal, Assign(signal,
draw(Normal(0.0, 1.0), DrawKey(:signal_noise))); domain=cells(tissue))`.
Each selected active cell gets one sample per update, regardless of area;
other kinds and inactive slots do not evaluate the draw. Model-owned samples
use a singleton model identity, and site-owned samples use logical lattice
indices. Retiring and reusing a cell slot changes its generation and therefore
its draw identity.

Scheduled samples use the absolute completed MCS and their scientific
before/after-lifecycle boundary. Reordering unrelated declarations does not
consume or shift their draws. CorePotts's iterated-site compiler interface
receives fresh noise at each declared substep; this does not add an arbitrary
stochastic right-hand side to the public `DiscreteFieldEuler` configuration.
To hold noise, sample a separate state and read it from another process.
Checkpoint continuation preserves the addressing identity.
A failed transaction does not consume samples or advance the logical MCS;
`repeat` remains an explicit trajectory choice, not a failed-transaction count.
Normal samples can differ in floating-point rounding across CPU and GPU even
when their addressed uniforms agree.

The runnable `examples/cell_polarity_dynamics.jl` applies this held-state pattern
to a whole two-component cell polarity. At a boundary, the angular sampler
writes the next turn while the rotation reads the entry turn. The initial zero
turn therefore holds orientation at the first boundary. Subsequent boundaries
rotate once per selected cell, regardless of area. This is polarity dynamics
with fixed ownership, not a demonstrated migration or energy-coupled model.
The ordinary scalar `sin` and `cos` operations accept dimensionless real
arguments; these operations do not imply complex or array-broadcast support.

Stable random addresses are not a promise of unchanged trajectories after
changing a model: proposals, state, acceptance, and competing initialization
placements can change. CorePotts owns the versioned generator/address protocol;
its current protocol consumes both operation-key words and the full
seed/replica/repeat identity. Checkpoint replay requires a matching execution
identity and protocol, not merely the same seed. A protocol change does not
preserve earlier seeded trajectories, and cross-backend floating-point replay
is a separate guarantee.
