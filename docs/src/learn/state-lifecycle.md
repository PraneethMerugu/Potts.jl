# [Lifecycle and relationships](@id lifecycle-and-relationships)

Cell identity is `(slot, generation, kind)`. Slots may be reused, but a stale
`CellIdentity` never aliases the new occupant. Lifecycle and relationship
changes stage against an inactive candidate and publish atomically after the
MCS and all coupled work succeed.

```@example lifecycle
using Potts
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

A `HistoryState` whose `of` source is cell-owned requires its own lifecycle
policies. It does not inherit policies from that source. Reset, initialization,
and retirement fill every retained sample; `CopyToDaughters` copies each lag to
the matching daughter lag, and `SplitConservatively` conserves each retained
sample separately. Explicit `lag` reads in transforms still read the named
retained sample rather than the current live source. These operations keep the
retention axis separate from cell slots and generations and publish or roll
back as one lifecycle transaction.
Sampling follows lifecycle work at a due boundary. For example, resetting all
three retained samples to `9` while retiring the live source to `0` gives
`(9, 9, 0)` after an `EveryMCS()` append, whereas a history not due for sampling
retains `(9, 9, 9)`.

Site-owned histories declare their own `ClearOnOwnershipChange()` or
`PreserveOnOwnershipChange()` law. Clearing affects every retained sample at
the changed site, not just its newest sample. `FieldState` is Eulerian: a
field and its history remain attached to fixed sites when cell occupancy
changes. They do not require an implicit ownership-change policy, but an
explicit clear or preserve law is honored independently on either declaration.

`RelationshipState` declares endpoint kinds, bounded capacity, payload schema,
maximum degree, and endpoint-lifecycle policy. At a settled host boundary,
`relationship_transaction!` applies `Create`, `Remove`, or `Retune` requests
atomically and validates generation-stamped endpoints.
