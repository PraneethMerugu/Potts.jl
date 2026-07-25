# Phase 14 Relationship and Coupled Lifecycle Semantics

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: Relationship storage and mutation specialize `state` and `process`; lifecycle
requests and commits specialize the one `lifecycle` contract in the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md).

## Purpose

This document defines mutation of `RelationshipSet`, ordinary `SiteDynamics`, and composition of all
Phase 14 state with the accepted [Cell Lifecycle](lifecycle.md). It does not change the existing
fixed `FocalPointSpringHamiltonian` or the accepted lifecycle phase order.

The ordinary contract below uses the completed-MCS lifecycle boundary. The opt-in multirate timing
extension, which reuses the same typed planning/commit laws at explicit global-time boundaries, is
defined in
[Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md).
That extension is separately fingerprinted and requires D10 acceptance; it does not alter ordinary
models.

The state containers and endpoint identity laws are defined in
[Dynamic State Ownership Semantics](phase-14-dynamic-state-semantics.md). This document defines who
may mutate them and when those mutations become visible.

## Relationship Dynamics

### Public process

`RelationshipDynamics` is an immutable process declaration:

```julia
junction_dynamics = RelationshipDynamics(
    :junction_dynamics,
    target = :junctions,
    candidates = ContactingCells(relation = :query),
    create = CreateWhen(ContactDuration() >= 2),
    remove = RemoveWhen(Distance() > :break_distance),
    update = Retune(rest_length = CurrentDistance()),
    capacity = RelationshipCapacity(4096),
    conflicts = StableRelationshipPriority(:junction_priority),
)
```

It declares candidate generation, eligibility, creation, removal, payload update, conflict
resolution, semantic RNG labels, capacity, and supported execution profiles. Omitted operations are
disabled; no creation or removal law is inferred from a spring Hamiltonian.

One phase invocation reads a common graph, cell-generation, geometry, property, and query snapshot.
It produces a bounded transaction containing canonical creates, removes, and payload updates.
Validation and capacity preflight complete before graph mutation.

### Candidate and endpoint semantics

Candidate generation uses explicit endpoint domains and a named query relation. A finite-cell
candidate is `(cell_id, generation)`, never a slot number alone. Contacting, distance-limited,
same-type, cross-type, or source-specific candidate rules are separately typed predicates.

For an undirected relationship, endpoint order is canonicalized before eligibility, RNG addressing,
duplicate checking, priority, and persistence. For a directed relationship, order is retained.
Self-edges are forbidden unless the `RelationshipSet` explicitly declares them meaningful.

Existing edges and absent candidates form distinct domains:

- removal and retuning inspect existing edges;
- creation inspects canonical absent candidates;
- one invocation cannot remove and recreate the same canonical edge unless a separately named
  replacement operation defines the resulting payload; and
- stale-generation candidates are invalid, not absent reusable identities.

Candidate enumeration order, hash-table order, thread scheduling, and device atomic arrival do not
affect scientific outcomes.

### Conflict resolution

The default rejects two incompatible writes to the same edge or a capacity-contending creation set
without an explicit policy. `StableRelationshipPriority(namespace)` assigns each proposed operation
a semantic priority from:

```text
(master seed, RNG contract, process identity, target MCS,
 canonical edge identity, operation label)
```

It is invariant under declaration and execution order. A deterministic source-defined priority may
instead use an explicit stable biological key. Cell ID, slot index, candidate enumeration position,
and container position are not implicit priorities.

Remove dominates a payload update only when the declared conflict policy says so. There is no
universal category precedence.

### Capacity

`RelationshipSet` declares scientific bounds such as allowed endpoint domains, maximum degree, and
maximum parallel edges. The realized `PottsProblem` declares physical relationship capacity.
Construction proves the physical capacity is at least every static scientific bound.

When the candidate set is state-dependent and cannot be bounded more tightly than the declared
physical capacity, exhaustion is a structured `RelationshipCapacityError`. The complete relationship
phase aborts without mutation. Committing the first enumerated or first atomically arriving subset is
prohibited.

A model may explicitly choose `SelectByPriority(maximum_edges)` as a biological creation law. That
selection is fingerprinted scientific semantics, not recovery from insufficient storage.

### Commit and visibility

Commit uses this logical order:

1. validate active endpoint identities and generations;
2. validate payloads and relationship invariants;
3. resolve operation conflicts;
4. preflight resulting edge and degree capacities;
5. remove accepted edges;
6. apply accepted payload updates to surviving edges;
7. insert accepted new edges in canonical order;
8. rebuild or repair derived adjacency indexes; and
9. validate the resulting graph.

The whole phase becomes visible together. A Hamiltonian or query in a later phase observes the
committed graph. Potts attempts cannot observe graph mutations from a phase that follows them.

Dynamic relationship Hamiltonians read a `RelationshipSet` snapshot but cannot mutate it during
proposal evaluation. The existing fixed focal-point component remains an immutable tuple and keeps
its frozen identity.

## Site Dynamics

### Public process

`SiteDynamics` performs one bounded pointwise or neighborhood update of a declared `SiteProperty`:

```julia
decay_activity = SiteDynamics(
    :decay_activity,
    target = :activity,
    law = ExponentialDecay(factor = 0.9f0),
    domain = MutableSites(),
)
```

A law declares its site domain, read relation, ownership filters, fields and properties read,
randomness, update equation, invariant policy, and conflict footprint. All outputs are computed from
one phase snapshot and committed together.

The required stable families are:

- pointwise deterministic transforms;
- pointwise addressed-stochastic transforms;
- finite-neighborhood reductions over a declared relation; and
- bounded multi-actor proposals resolved by a typed stable conflict policy.

Iterative convergence loops, global unbounded graph searches, and arbitrary host callbacks are not
part of the first stable contract.

### Act activity example

An Act-compatible assembly uses:

1. `AcceptedCopyUpdate` to write activity only after an eligible accepted protrusion;
2. proposal-time geometric-mean reduction over same-cell site activity from the immutable attempt
   snapshot; and
3. one post-attempt `SiteDynamics` decay phase.

Whether the gained site receives maximum activity on every accepted copy or only a source-defined
protrusion category is selected by the accepted-copy eligibility law. Rejected, constrained,
same-owner, invalid-boundary, and dynamic-conflict no-ops never write activity.

Decay observes all accepted-copy commits from that MCS when it appears after `PottsAttempts`.
Changing decay before/after the attempts changes the plan fingerprint.

### Degradable structures

BrM/ECM-like material uses a typed `SiteProperty` when one site has one bounded material state.
`SiteDynamics` declares:

- which biological actors may propose degradation;
- whether actors are determined by ownership, adjacency, field, or relationship state;
- rate/probability and semantic RNG identity;
- whether degradation is pointwise, accumulated, or thresholded;
- how simultaneous actors combine;
- whether occupied material sites are allowed;
- resulting material states and invariants; and
- visibility to field, proposal, energy, and lifecycle consumers.

Simultaneous actor counts are computed from the snapshot. A stochastic probability is applied once
to the explicitly defined aggregate, not once in incidental actor order. Material mutation does not
change CPM ownership unless a separate lifecycle or ownership transaction says so.

If the CNV source requires multiple occupants, continuous deformation, or a structure topology that
cannot be represented by one bounded site value, a distinct state contract is required. The current
source audit has not established such a requirement.

## Coupled Lifecycle Snapshot

The existing `PreLifecycleSnapshot(target_mcs)` is extended additively to expose declared read-only
views of:

- `CellProperty` and `CellHistory`;
- evolving field values and semantic field times;
- `SiteProperty`;
- `RelationshipSet`;
- completed post-attempt geometry and derived queries;
- stage identity and scheduled parameters; and
- process-clock state.

A trigger receives only the capabilities it declares. Extension of the snapshot does not make
every field automatically visible or authorize host access. All due triggers still observe the same
snapshot and cannot observe other lifecycle outcomes at that boundary.

Typed state-dependent triggers may compare, reduce, or combine declared values. The first stable
contract supports bounded device-lowerable expressions and addressed stochastic decisions. A
long-running biological state machine is represented by explicit checkpointed `CellProperty` state
plus ordinary triggers and effects, not hidden mutable callback state.

## Auxiliary Lifecycle Policies

Every Phase 14 state declaration is incomplete unless it supplies applicable typed policies for:

- initialization;
- binary division;
- type transition;
- progressive-death initiation and progression;
- immediate death;
- extinction and retirement; and
- slot generation reuse.

### Site properties

Site properties are spatial state and are not divided with a cell. Division changes ownership while
the property's declared ownership-change policy decides whether values remain, reset, or are managed
by an explicit transaction. Death and extinction follow the same law per changed site. Retirement
does not clear unrelated sites after ownership has been reassigned.

### Cell histories

For a successful division the history policy explicitly chooses:

- `CopyHistoryToBoth`;
- `PreserveParentResetChild(initialization)`;
- `ResetHistoryForBoth(initialization)`; or
- a registered transformation over the parent pre-lifecycle history.

The parent and daughter receive generation-correct buffers in the same lifecycle transaction.
Retirement resets storage and invalidates the old generation. New cells are not sampled again at the
same boundary when `HistorySample` precedes lifecycle.

### Relationship sets

Before commit, lifecycle planning derives relationship operations for every affected endpoint:

- immediate death and retirement remove all incident edges atomically;
- type transition preserves, retunes, or removes each edge according to its endpoint transition
  policy;
- division may retain parent edges, copy eligible edges to the daughter, split payload, or remove
  and recreate through an explicit division policy; and
- generation reuse never revives an old edge.

Any new daughter edge is validated only after the daughter identity, generation, and geometry are
known. Duplicate, degree, and capacity rules participate in the same lifecycle preflight.

### Cell dynamics

The mapped `CellProperty` policies govern ODE/vector state. Process clocks are model-level and do
not divide. Per-cell adaptive solver state, if ever used, requires its own generation-aware policies.
The stable fixed-step profile has no per-cell hidden continuation state.

### Fields and exchange

Ordinary lifecycle does not divide or retire field arrays. A lifecycle effect may atomically update
a named cell property that later influences exchange. Direct field mutation is a separately typed
field lifecycle effect with explicit conservation and split-order semantics; it is not implied by
death or division.

Pending exchange is absent at the stable lifecycle boundary under the standard plans. A custom plan
that carries authoritative accumulated forcing must define lifecycle policies for that accumulator.

## Coupled Lifecycle Transaction

The accepted lifecycle category order remains unchanged. Coupled auxiliary planning is inserted into
the existing validation and commit machinery:

1. evaluate all triggers from `PreLifecycleSnapshot`;
2. resolve one identity-changing outcome per cell;
3. plan ordinary and coupled-state policies;
4. validate division geometry and all affected property/auxiliary schemas;
5. preflight cell, relationship, and other fixed capacities for the complete batch;
6. commit ownership, identity, type, and ordinary property changes;
7. commit history and relationship policies;
8. apply any explicitly declared field/site lifecycle effects;
9. retire extinct identities and reset all generation-owned state;
10. rebuild derived state and indexes;
11. validate cross-family invariants; and
12. publish lifecycle diagnostics.

The ordering within these logical groups is an implementation detail only when no declared
read-after-write relation distinguishes it. A source requiring one effect to read another effect's
new value uses one explicitly composed effect with an internal normative transaction.

Capacity failure, stale endpoints, invalid property policies, graph invariant failure, or any other
coupled validation error aborts the complete lifecycle transaction before mutation. It cannot commit
cell division while dropping daughter relationships or history.

## Lifecycle Event Targets

The accepted active-cell and global targets remain. Phase 14 adds an active-relationship target
domain for relationship-specific lifecycle events:

```julia
LifecycleEvent(
    ActiveRelationships(:junctions),
    EveryMCS(),
    EdgeTrigger(...),
    EdgeEffect(...),
)
```

It uses the same snapshot, scheduling, typed transaction, conflict, and semantic RNG rules.
Relationship declaration order and adjacency storage order do not determine outcomes.

Site-domain events are expressed as `SiteDynamics` unless they change biological identity. This
keeps the lifecycle taxonomy focused on identity and long-running biological programs.

## Inspection and Diagnostics

The completed MCS report includes, per process or lifecycle family:

- relationship candidates, creates, removes, retunes, conflicts, and capacity demand;
- site candidates, writes, conflicts, invariant rejections, and degradation totals;
- coupled trigger counts and resolved outcomes;
- history initialization/reset/copy counts;
- incident edges removed or created by lifecycle;
- field/site lifecycle-effect balance; and
- structured failure identity.

Requesting a report may materialize bounded diagnostics under the existing observation rules. It
does not change scientific execution.

## Backend Contract

CPU reference behavior is mandatory. A GPU claim requires bounded backend-resident storage,
device-lowerable candidate generation and policies, deterministic conflict semantics, no undeclared
host synchronization, and real-hardware conformance. Until qualified, preflight rejects the exact
process or lifecycle extension; it does not migrate only that phase to the host.

## Required Conformance Evidence

- canonical directed and undirected endpoint fixtures;
- duplicate, stale-generation, self-edge, degree, and capacity failures;
- declaration/enumeration/thread-order invariant create/remove/retune results;
- fixed focal-point v1 non-regression;
- Act accepted-copy/decay/neighborhood truth tables against Artistoo;
- deterministic and stochastic site dynamics;
- single- and multi-actor degradation fixtures;
- common coupled lifecycle snapshot tests;
- division/death/type-transition policies for every Phase 14 state family;
- atomic cross-family capacity rollback;
- ID retirement and next-MCS reuse;
- relationship-target event scheduling and conflicts;
- uninterrupted-versus-checkpoint continuation; and
- CompuCell3D focal-link and CNV scenario microfixtures after source closure.

## Source Closure Required for Paper Qualification

Reusable semantics are complete enough to implement, but exact paper claims still require:

- CompuCell3D focal-link candidate, activation, removal, retuning, and neighbor-order laws;
- the CNV minimum lifecycle subset and BrM/ECM mutation equation;
- Wang focal-link update order and daughter/death policies if those events occur; and
- the precise Artistoo protrusion category that writes activity.

Unknown source behavior is registered as paper ambiguity and may not be replaced by library defaults
in a close-reproduction model.
