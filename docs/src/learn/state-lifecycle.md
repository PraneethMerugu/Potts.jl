# [Lifecycle and relationships](@id lifecycle-and-relationships)

Cell identity is `(slot, generation, kind)`. Slots may be reused, but a stale
`CellIdentity` never aliases the new occupant. Lifecycle and relationship
changes stage against an inactive candidate and publish atomically after the
MCS and all coupled work succeed.

```@example lifecycle
using PottsToolkit
using Symbolics

@variables activity
cell = CellKind(:cell; extinction=RetireAtZero())
daughter = CellKind(:daughter; extinction=RetireAtZero())
medium = MediumKind(:medium)
division_relation = SpatialRelation(:division; neighborhood=VonNeumann())
anchor = CellBinding(:event_cell)
cell_activity = CellState(
    activity;
    initial=1.0,
    retirement=RetireTo(0.0),
    division=CopyToDaughters(),
)
transition = LifecycleProcess(
    :transition;
    domain=cells(cell),
    anchor,
    expression=true,
    effects=(Transition(
        anchor,
        daughter;
        state=(cell_activity=>Transform(activity + 1),),
        on_inadmissible=ErrorOnInadmissible(),
    ),),
    cadence=AtMCS(1),
)
source = PottsSystem(
    name=:lifecycle_example,
    statements=StatementSet((
        Lattice((4, 4); max_cells=4),
        cell,
        daughter,
        medium,
        division_relation,
        cell_activity,
        ProposalConstraint(:frozen, false),
        transition,
        Protocol(Sweep(; temperature=0.0); name=:main),
    )),
    unknowns=[activity],
)
plans = inspect(complete(source), LifecyclePlans())
(length(plans), typeof(first(plans)))
```

Creation, removal, retirement, transition, and division require explicit
state and relationship policies. Per-cell native components additionally
declare creation, transition, and daughter-state transfer; the pool capacity
is fixed at compile time while live count and generations remain data.

`RelationshipState` declares endpoint kinds, bounded capacity, payload schema,
maximum degree, and endpoint-lifecycle policy. At a settled host boundary,
`relationship_transaction!` applies `Create`, `Remove`, or `Retune` requests
atomically and validates generation-stamped endpoints.
