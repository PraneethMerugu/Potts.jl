# Symbolic Potts V1 lifecycle language — consolidation candidate

Status: G5-L0 cleared; folded into authoritative CCV1-027; retained as decision provenance  
Scope: G5-L cell lifecycle language before the one final R2 execution review  
Owner decisions: LCI-R1-01 through LCI-R5-07 accepted  
Authority: CCV1-027 in `spec/symbolic-potts-v1-compiler-construction.md`  
Clearance: `symbolic-potts-v1-lifecycle-language-g5-l0-rereview.md`

## 1. Purpose and restraint

V1 currently has two lifecycle authorities: public `LifecycleProcess` syntax and an unconditional
CorePotts zero-volume retirement scan. The compiler admits relationship removal/retuning in the
lifecycle phase but does not admit cell creation, occupied removal, transition, division, or
descriptor-owned retirement. This candidate replaces that split with one compiler-owned language.

The V1-L thesis is:

> Lifecycle models compose open, frozen symbolic predicates and pure policies around a small closed
> algebra of cell-structure transactions. The compiler proves finite reads, writes, emissions,
> conflicts, capacity, identity, and backend legality. CorePotts executes resolved plans and does not
> know named biological mechanisms.

V1-L is not a general rewrite system. It does not admit arbitrary mutation callbacks, recursive
event emission, dynamic registries, fusion, fragmentation, engulfment, arbitrary M-to-N rewrites,
sub-MCS lifecycle clocks, host fallback, or proof-model-specific executor branches.

## 2. Literal closed V1-L inventory

The following structural vocabulary is frozen for V1-L. A new item requires an explicit later
compiler/runtime contract; it cannot enter through ordinary operation registration.

### 2.1 Event domains

| Domain | Cardinality and identity | Admitted use |
|---|---|---|
| `cells(kind)` | finite active `(cell_id, generation)` identities | remove, retire, transition, divide |
| `model()` | exactly one qualified model identity | global creation or model-state event |

Relationship domains remain owned by the existing relationship-process contract. V1-L does not add
a general lifecycle query language. A process binds one explicit `CellBinding` or singleton model
anchor as applicable; qualified binding identity is resolved before analysis. Creation placement
may evaluate a finite site expression, but that does not create a site-iterated event domain.

### 2.2 Structural effects

| Effect | Identity arity | Required structural result |
|---|---:|---|
| `CreateCell` | 0 -> 1 | allocate and initialize one finite occupied identity |
| `RemoveCell` | 1 -> 0 | transfer all source sites to one declared medium and consume the identity |
| `Retire` | 1 -> 0 | consume an already empty identity without rewriting ownership |
| `Transition` | 1 -> 1 | retain identity/ownership and change kind and declared state |
| `Divide` | 1 -> 2 | partition the source sites between retained parent and allocated daughter |

The five effects lower to one closed cell-structure transaction IR. They are not five independent
runtime executors. Relationship `Create`, `Remove`, and `Retune` retain their separate bounded
relationship taxonomy and may be consequences of a cell transaction only through the policies in
Section 2.7.

### 2.3 Placement policies

- `SeedAt(site_expression)`
- `SeedStencil(site_expression, finite_offsets; relation)`

These are the complete built-in placement families, not a closed list of registered pure-policy
values. A downstream package may register a versioned placement operation under the Section 4.1
ABI; its public typed constructor returns a symbolic policy value used directly in
`CreateCell(...; placement = external_placement(...))`. Arbitrary callbacks and new structural
effects are not admitted through this slot.

Every selected site must be in bounds, admissible, and available in the common snapshot. Clipping,
partial creation, and declaration-order collision winners are forbidden. `SeedStencil` offsets are
finite compile-time data and must form one connected set under its explicitly bound relation.

### 2.4 Binary division geometry

- `RandomPlane(; point = CellCentroid(), draw = :division_normal)`
- `PrincipalAxisPlane(axis; point = CellCentroid())`, where `axis` is `:major` or `:minor`
- `SpecifiedNormalPlane(normal_expression; point = CellCentroid())`

These are the complete built-in binary-partition families. A downstream package may register a
versioned binary-partition operation under Section 4.1; its public typed constructor returns a
symbolic policy value used directly in `Divide(...; geometry = external_partition(...))`. It must
still bind the effect's explicit relation and side law and pass the same conservation/connectivity
validator. The slot does not admit an arbitrary callback or nonbinary structural effect.

Every geometry resolves to a point and a normal. For `PrincipalAxisPlane`, `axis` names the
principal axis used as the plane normal; it never ambiguously names an in-plane direction. One
explicit finite `relation` validates both daughter partitions. Both must be nonempty and connected,
their union must equal the parent sites, and they may not gain, lose, duplicate, or import sites.

Parent/daughter side identity is one of:

- `CanonicalSide()`
- `StableRandomSide(draw_identity)`

No hidden side assignment may introduce directional bias.

Division kind mapping is selected independently for the retained parent and new daughter:

- `PreserveKind()`; or
- `SetKind(kind)`.

The constructor default is the concrete, frozen, inspectable `PreserveKind()` for each descendant;
CorePotts never infers kind behavior from missing data.

### 2.5 State policy families

Each authoritative cell-owned state schema stores separate typed values for creation,
removal/retirement, transition, and division. A small schema container may group those values for
construction and inspection; it is not a behavioral superclass or second dispatch authority.

Creation:

- `InitializeFrom(expression)`
- `Unsupported()`

Removal/retirement:

- `RetireTo(expression)`
- `Unsupported()`

Transition:

- `Preserve()`
- `ResetTo(expression)`
- `Transform(expression)`
- `Unsupported()`

Division:

- `CopyToDaughters()`
- `PreserveParentResetDaughter(expression)`
- `ResetBoth(parent_expression, daughter_expression)`
- `SplitConservatively(fraction; rounding)`
- `TransformDaughters(parent_expression, daughter_expression)`
- `RedrawDaughters(parent_distribution, daughter_distribution;
  parent_draw, daughter_draw)`
- `Unsupported()`

`SplitConservatively` is admitted only for additive numeric state. `fraction` is dimensionless and
lies in `[0, 1]`; the parent receives the declared fraction and the daughter the exact remainder in
canonical parent-then-daughter arithmetic. Integer state requires an explicit deterministic or
semantic-stochastic remainder policy that preserves the exact total. `RedrawDaughters` uses two
distinct lexical lifecycle draw identities. `ResetBoth` expressions cannot read the former state;
`TransformDaughters` expressions may read the immutable before/planned-after policy views.

The list above is the complete built-in state-policy family inventory. A registered pure state
transform enters as the symbolic expression inside the applicable `InitializeFrom`, `Transform`,
`TransformDaughters`, or reset policy and uses Section 4.1's ABI; it does not register another
structural effect or bypass schema policy resolution. Likewise, a registered trigger operation
appears in `LifecycleProcess.expression`.

Policy resolution is exactly:

```text
compatible event override -> schema policy -> construction failure
```

The resolved policy and provenance are frozen. Custom and auxiliary state receives no implicit
clone, zero, reset, redraw, or conservation law. Derived trackers do not use biological state
policies; they declare invalidation and reconstruction/repair.

Site-owned state is spatial rather than inherited as cell state. Every affected `SiteState` schema
must explicitly select its existing ownership-change law:

- `PreserveOnOwnershipChange()`; or
- `ClearOnOwnershipChange()`.

Creation applies that law to medium-to-cell ownership, removal to cell-to-medium ownership, and
division to parent-to-daughter ownership. Missing site behavior is a construction failure. Fields
remain field state and are not rewritten merely because CPM ownership changes.

### 2.6 Extinction law

Every finite `CellKind` must explicitly resolve one ordinary CPM extinction law:

- `RetireAtZero(; priority = 0)`: completion synthesizes a qualified zero-volume
  `LifecycleProcess` using ordinary `Retire` with the declared priority and a frozen
  `ErrorOnInadmissible()` disposition; or
- `ForbidExtinction()`: completion synthesizes a generic proposal constraint preventing loss of
  the final owned site.

There is no unconditional executor scan and no undocumented global default. `RetireAtZero` is the
ordinary choice for kinds whose stochastic proposals may consume their last site.
`ForbidExtinction` is the ordinary choice for persistent identities. Both lower through generic
compiler primitives and must pass the same GPU and inspection gates. A cell kind with neither law
is incomplete; a medium kind cannot declare one.

The final-site proposal of a `ForbidExtinction` cell is rejected by the synthesized generic
constraint. If a zero-occupancy identity of that kind nevertheless reaches lifecycle planning, the
state is corrupt: this is a nonfilterable invariant failure, not retirement and not ordinary
inadmissibility. Only a due `RetireAtZero` transaction may consume the bounded pre-publication
zero-occupancy transient. No settled or published state contains an active zero-volume cell.

### 2.7 Relationship consequence policies

Creation:

- no incident relationships

Removal/retirement:

- `RejectWhileLinked()`
- `RemoveIncident()`

Transition:

- `PreserveCompatible()`
- `RemoveIncompatible()`
- `RejectIncompatible()`

Division:

- `RejectWhileLinked()`
- `RemoveIncident()`

Daughter relationship transfer is deferred. V1-L does not infer endpoint assignment, payload
transformation, attachment geometry, degree/capacity selection, or duplicate resolution.

Every relationship schema resolves separate endpoint behavior for removal/retirement, transition,
and division. An effect-level `relationships` tuple contains only explicit compatible overrides;
an empty tuple delegates to those schema policies. Missing reachable behavior fails construction.

### 2.8 Conflict and inadmissibility policies

The phase conflict policy is one of:

- `RejectLifecycleAmbiguity()`
- `StableLifecyclePriority()`

Every request carries an explicit signed `Int32` semantic priority. Exact duplicate requests are
deduplicated. Under stable priority the unique greatest priority wins each incompatible footprint
conflict; an equal greatest priority is an error. Rule order, tuple order, effect category, cell ID,
slot, compiler group, launch order, thread order, and atomic arrival are not biological priorities.

Every effect freezes one inadmissibility disposition:

- `FilterInadmissible()`
- `ErrorOnInadmissible()`

`on_inadmissible` is mandatory on every structural-effect constructor. There is no effect-specific
default whose scientific meaning can be inferred from omission. Inspection and the executable
fingerprint expose the explicitly realized value. Integrity failures in Section 7.3 are never
filterable.

## 3. Public symbolic surface

`LifecycleProcess` remains the sole cell-lifecycle statement. No `LifecycleRule` synonym or
macro-only DSL is introduced. Its authoritative shape is:

```julia
LifecycleProcess(
    name;
    domain,
    anchor = nothing,
    expression,
    effects,
    phase = Lifecycle(),
    cadence = EveryMCS(),
)
```

The expression must be a dimensionless Boolean. A cell-targeting V1-L process contains exactly one
of the five structural cell effects. Kind mapping, state mapping, relationship consequences, and
ownership-change behavior are policies inside that effect; they are not extra coincident structural
requests. General multi-effect composition is deferred. Existing relationship-only lifecycle
processes remain governed by their bounded relationship contract.

Representative forms are:

```julia
cell = CellBinding(:cell)

divide = LifecycleProcess(
    :divide_large_cells;
    domain = cells(epithelial),
    anchor = cell,
    expression = cell_volume(anchor_value(cell)) >= division_volume,
    effects = (Divide(
        cell;
        geometry = PrincipalAxisPlane(axis = :major),
        relation = :division_connectivity,
        side = StableRandomSide(:parent_side),
        parent_kind = PreserveKind(),
        daughter_kind = PreserveKind(),
        relationships = (RejectWhileLinked(),),
        priority = 10,
        on_inadmissible = FilterInadmissible(),
    ),),
    phase = Lifecycle(),
    cadence = EveryMCS(),
)
```

```julia
seed = LifecycleProcess(
    :recruit_one_cell;
    domain = model(),
    expression = recruitment_signal > threshold,
    effects = (CreateCell(
        epithelial;
        placement = SeedAt(seed_site),
        priority = 5,
        on_inadmissible = FilterInadmissible(),
    ),),
    phase = Lifecycle(),
)
```

The V1-L effect constructors are:

```julia
CreateCell(kind; placement, state = (), priority = 0, on_inadmissible)

RemoveCell(cell; replacement, state = (), relationships = (),
           priority = 0, on_inadmissible)

Retire(cell; state = (), relationships = (),
       priority = 0, on_inadmissible)

Transition(cell, kind; state = (), relationships = (),
           priority = 0, on_inadmissible)

Divide(cell; geometry, relation, side,
       parent_kind = PreserveKind(), daughter_kind = PreserveKind(),
       state = (), relationships = (),
       priority = 0, on_inadmissible)
```

`state` contains explicit compatible per-state overrides. Schema policies remain authoritative
otherwise. The branch has no migration obligation: the existing `Divide(cell; policy=...)` form may
be replaced rather than wrapped, and no alias for the hardcoded retirement path is required.

One phase conflict policy is frozen through the compiled protocol with this public spelling:

```julia
Protocol(
    Sweep(; temperature);
    lifecycle_conflicts = StableLifecyclePriority(),
)
```

Completion rejects a second incompatible lifecycle conflict policy in a composed system. The
realized policy, including the default `RejectLifecycleAmbiguity()`, is present in inspection and
the executable fingerprint.

## 4. Symbolic openness and registry freeze

Lifecycle predicates and pure policy expressions may compose:

- parameters and DynamicQuantities-checked units;
- cell, site, model, field, history, relationship, and tracker reads;
- explicit finite relations and bounded reductions;
- explicit semantic random draws; and
- registered pure operations with complete V1 schemas.

Analysis proves result type, units, purity, totality, read footprint, tracker requirements, finite
emission bound, RNG identities, and backend capabilities. Proposal-context operations, mutation,
unbounded queries, hidden random state, host closures, and live registry lookup are rejected.
Priority may be a pure symbolic integer expression; analysis proves that every admitted result is
representable as `Int32`.

External packages may register versioned, frozen pure trigger, placement, binary partition, and
state-transform policies. They may not register a new structural mutation verb. Completion uses the
minimal reachable frozen operation closure: reachable symbolic operations, required compiler-
synthesized operations, and used external operations only. Analysis and lowering never consult the
live registry after completion.

Every resolved schema includes the selected concrete callable value. Completion therefore freezes
registry membership, schema versions, and callable selection: later registration or registry
mutation cannot redirect analysis or lowering of that completed model. Julia method tables are part
of the executable environment, not captured data; later method additions, redefinitions, package
changes, or Julia changes may require recompilation and requalification. Executable compatibility
and provenance therefore identify the relevant code environment and never claim that a callable
value immunizes execution from method-table changes. The package-level literal V1 inventory remains
separate and is used for documentation and coverage audits, not copied into every model.

### 4.1 Pure lifecycle-policy ABI

Every registered trigger, placement, binary-partition, or state-transform operation uses the same
versioned operation-schema and frozen-callable path as ordinary expressions. Its schema declares:

- the admitted lifecycle role and exact input context (`PreLifecycleSnapshot`, one planned request,
  or the semantic before/after policy views appropriate to that role);
- concrete result type, shape, units, parameter domain, and totality behavior;
- purity, finite reads, write/emission footprint, workspace bound, tracker requirements, and any
  finite relation dependency;
- semantic RNG namespaces, entity/occurrence identity, and lexical draw identities;
- backend and numerical capabilities plus a concrete device-valid callable; and
- canonical serialization, qualified provenance, validators, and inspection metadata.

The trigger result is one Boolean per finite bound anchor. Placement returns one bounded finite site
selection conforming to the declared placement schema. Binary partition returns one bounded region
label for every source-owned site and must permit proof of exact two-way conservation. A state
transform returns the declared property value or fixed-width parent/daughter tuple. These are pure
results: an operation cannot mutate state, allocate an identity, commit ownership, emit an
additional structural verb, consult a live registry, or invoke an executor callback. Analysis
derives and validates the complete request footprint and emission bound; a schema assertion cannot
substitute for proof. Qualified source and binding identities are established before this analysis.

The semantic context/result contract is literal:

| Role | Exact semantic context | Concrete result and compiler validation |
|---|---|---|
| trigger | common snapshot, qualified domain anchor/identity, MCS, resolved parameters/resources, occurrence and addressed draws | one `Bool`; exactly one decision per finite bound anchor |
| placement | common snapshot/topology, qualified model/rule occurrence, resolved site expression and relation, parameters/resources, addressed draws | fixed-capacity isbits site selection with declared maximum; validate uniqueness, bounds, availability, admissibility, and connected stencil |
| binary partition | common snapshot, source ID/generation, canonical source-owned-site index, explicit relation, resolved point/normal/side, parameters/resources, addressed draws | one compact region label per source site; batch validation proves exactly two nonempty connected regions and exact ownership conservation |
| state transform | common snapshot, qualified state schema/source identity, old value, allocated destination identities/roles where required, semantic before/planned-after views, parameters/resources, addressed draws | one concrete schema value or fixed parent/daughter pair; validate type, units, parameter domain, and declared conservation/initialization law |

Contexts are compiler-owned immutable views with private physical layout. Partition evaluation may
be pointwise over the canonical source-site index; its whole-partition validator remains part of the
same resolved policy plan, not a second evaluator or trusted extension callback.

## 5. Closed phase and snapshot law

The ordinary MCS order is:

```text
Proposal and AcceptedCopy commits
    -> AfterMCS
    -> RelationshipCommit
    -> immutable PreLifecycleSnapshot
    -> Lifecycle plan/evaluate/commit/publication
    -> EquationStep
    -> Observe
    -> settled completed-MCS boundary
```

All due lifecycle triggers and pure policies read the same immutable snapshot. They cannot observe
another lifecycle result from that boundary. Newly created identities and daughters are ineligible
until a later lifecycle invocation. Cadence is an integer-MCS pure value; MCS zero remains
initialization, not an ordinary lifecycle event. V1-L does not add an independent or multirate
lifecycle clock.

Triggers read only `PreLifecycleSnapshot`. After conflict resolution, each surviving request may
also receive immutable compiler-owned semantic before and planned-after views. A policy may read
those views when its mathematics depends on the planned result, such as daughter volume, new kind,
or post-partition geometry. The after view is derived from the pre-snapshot and the validated
request plan; it is not published state and cannot contain another request's outcome. Concrete
private type names and layout are implementation choices. No policy mutates and rolls back runtime
state to calculate a result.

`Lifecycle` is a distinct compiled stage. Cell retirement is not an `AfterMCS` executor prepass.
Sequential and checkerboard engines invoke one shared immutable `LifecycleExecutionPlan`; there is
no engine-specific lifecycle semantics.

## 6. Identity, allocation, and generation

Compiled cell storage distinguishes `NeverUsed`, `Active`, and `Reusable` slots, or an exactly
equivalent high-water-plus-reusable representation.

Allocation follows this law:

1. resolve request-local snapshot-relative inadmissibility;
2. resolve conflicts among the remaining valid requests;
3. order surviving create/divide requests by canonical request identity;
4. form the free pool from the pre-lifecycle snapshot only;
5. allocate reusable IDs in ascending order, then fresh IDs above the high-water mark; and
6. abort the complete valid batch before mutation if capacity or generation range is insufficient.

IDs removed or retired in MCS `t` cannot be reused until MCS `t + 1`. A never-used slot has no live
generation; its first identity receives generation one. Retirement/removal preserves the consumed
generation in the reusable slot. Reallocation advances it exactly once after overflow preflight.
Transition and the retained parent preserve ID and generation. A daughter receives its allocated ID
and new/fresh generation.

This clause supersedes any interpretation that generation advances at retirement. An inactive
slot invalidates endpoints immediately through liveness; generation changes when the next identity
is created. Checkpoints record enough slot status/high-water information to distinguish never-used
from reusable slots.

## 7. Request, conflict, failure, and capacity law

### 7.1 Request identity and footprint

Every request contains value-level:

- qualified rule identity and compiled plan slot;
- target MCS;
- bound source entity and generation where applicable;
- canonical occurrence identity;
- structural effect and concrete policy-group slot;
- explicit priority and inadmissibility disposition;
- finite identity, ownership, site, state, relationship, and topology write footprints; and
- all resolved evaluator/policy values needed for planning.

Statement names, resource names, cell IDs, generations, occurrence counts, slots, and capacities do
not enter types. Only structural evaluator/effect/policy/storage group classes may specialize.

### 7.2 Canonical conflict resolution

Exact duplicates are deduplicated. Incompatible identity, ownership, site, state, relationship, or
topology writes form conflict sets derived from analyzed footprints. The selected phase policy
resolves those sets before slot allocation. There is no category precedence such as death over
division. An intended combined outcome is one explicitly composed effect with a proven law.

### 7.3 Failure classes

Expected snapshot-relative inadmissibility follows the effect's frozen disposition. Examples are an
invalid division partition, unavailable seed stencil, nonempty retire request, or linked endpoint
under a rejecting policy. A filtered request records a bounded diagnostic and does not suppress
unrelated valid requests.

The following are nonfilterable phase integrity failures:

- stale source or relationship generation;
- missing, incompatible, or illegal resolved policy;
- nonfinite or invalid evaluator result;
- request/emission/workspace bound violation;
- generation overflow;
- analyzed-footprint violation;
- device capability mismatch; and
- failed planned or post-commit invariant.

After filtering and conflict resolution, insufficient cell or relationship capacity aborts the
complete valid batch. Physical capacity never silently chooses a subset. A biological selection law
may explicitly reduce requests before capacity preflight and becomes fingerprinted model semantics.

## 8. Transaction IR and physical execution

The host compiler lowers symbolic lifecycle statements into immutable resolved descriptor groups.
CorePotts receives no Symbolics, units, registry, dictionary, closure, abstract descriptor vector,
or biological mechanism name.

The one logical pipeline is:

1. evaluate bounded trigger masks from `PreLifecycleSnapshot`;
2. emit effect-grouped structure-of-arrays request banks;
3. compact requests with reusable scan workspace;
4. construct canonical keys, stable-sort or otherwise canonically order, and deduplicate;
5. plan request-local placement/partition and structural preconditions, derive exact finite write
   footprints, and apply each explicit inadmissibility disposition;
6. derive conflict sets among the remaining valid requests and select permitted winners;
7. plan allocation, ownership destinations, state mappings, relationship consequences, tracker
   invalidation, and diagnostics for the winners;
8. preflight identities, generations, bounds, capacities, storage, and device status;
9. execute a commit that cannot encounter a modeled validation failure;
10. repair/reconstruct derived trackers and incident indexes;
11. validate bounded device status and postconditions; and
12. publish the complete semantic state and successful diagnostics together.

An inadmissible request cannot win a conflict and then disappear while suppressing a valid
competitor. Local geometry/placement rejection therefore precedes biological conflict selection;
allocation-dependent initialization and its draws remain after winner selection.

Authoritative state is never mutated and rolled back. Persistent scratch stages any destination
whose partial visibility would violate the contract. No model evaluator, observation, snapshot, or
checkpoint can see an intermediate kernel. A hardware/backend failure during commit is terminal and
recovers from the preceding completed checkpoint; V1-L atomicity is scientific publication
atomicity, not crash-consistent GPU rollback.

KernelAbstractions owns lifecycle-specific portable kernels. AcceleratedKernels owns qualified
scan/sort/map/reduction primitives when their semantics fit, using compiler-sized reusable
temporaries. Atomix may implement proven integer status or conflict operations, but atomic arrival
never defines scientific outcomes. Adapt remains the centralized storage adaptation boundary.

## 9. Locality, allocation, and specialization

Warm lifecycle execution performs zero host and device allocation. Compilation reports persistent,
scratch, and peak lifecycle storage plus expected launches, transfers, and synchronization.

The implementation must not scan the whole lattice once per request:

- creation touches one bounded stencil;
- retire and transition are cell-local;
- relationship work scales with incident degree;
- one fused lattice pass may apply an entire remove/divide batch; and
- principal-axis geometry uses generic declared trackers or one shared batch reduction.

At fixed structural group count, occurrence counts `1`, `32`, and `1024` preserve plan type depth,
evaluator signatures, and kernel-family count. Counts, identities, capacities, and values remain
buffers. No `@static`, generated function, or type parameter may encode arbitrary model identity or
occurrence count.

Correctness, boundedness, inference, zero warm allocation, and absence of catastrophic measured
regression block R2. Absolute laptop wall-clock thresholds do not. Compilation, first invocation,
warm phase time, memory, transfers, synchronizations, launches, and device-code metrics are reported
separately in focused qualification.

## 10. RNG contract

The versioned RNG address gains an explicit cell entity kind and closed lifecycle stream families
for:

- event triggers;
- conflict priority when explicitly stochastic;
- creation placement;
- division geometry and side assignment;
- property initialization/inheritance/redraw;
- conserved stochastic rounding; and
- stochastic transition.

A cell draw includes cell ID and generation; a site draw includes canonical logical site. A
model-domain creation draw uses the qualified rule and bounded occurrence before a runtime cell
exists. Destination initialization draws occur only for surviving allocated identities and include
destination ID/generation, descendant role, policy identity, and lexical draw identity.

Filtering, conflict loss, branch behavior, declaration permutation, grouping, workgroup tuning, and
backend launch decomposition cannot shift unrelated draws. The mapping is injective and
fingerprinted. Cells may not be disguised as generational site addresses; if the current packed
address cannot express the new domain, the RNG contract version changes.

## 11. GPU and backend qualification

Before R2, the shared backend-neutral harness executes actual device-resident transactions for all
five effects and every stable built-in policy family on one real GPU witness. It covers trigger
evaluation, compaction, conflicts, capacity, allocation, ownership, state, relationships,
generations, trackers/indexes, status, and publication. Compile-only probes and immutable
relationship reads are insufficient.

GPU scalar indexing is disabled. No scientific lifecycle value transfers to the host for planning
or commit. One explicit phase-end synchronization and bounded status transfer may report failure or
publication. Checkpoint/snapshot transfer is a separate declared boundary. V1-L qualifies the
accepted checkerboard GPU path; it does not introduce a sequential GPU algorithm claim.

Metal may be the first functional witness. CUDA and AMDGPU environments inject only discovery,
allocation, conversion, synchronization, capability facts, and error translation into the same
scientific harness. Their absence does not block R2 after one witness passes and no claim exceeds
evidence.

## 12. Diagnostics, inspection, and checkpoint

Host failures use stable `PottsDiagnostic` categories with qualified statement/policy identity,
source, expected/actual facts, alternatives, and deterministic ordering. Device execution writes a
fixed status containing a closed code, plan entry, canonical offender identity/generation,
required/available capacity, and bounded counters. Concurrent failures select the canonical first
semantic error, not first atomic arrival.

Inspection exposes lifecycle groups, effect/policy inventory, footprints, request bounds, memory,
RNG namespaces, required trackers/relationships, checkpoint policy, kernels, backend support, and
rejection reasons. It does not expose private IR layout, live registry, or backend events.

The closed device status categories are:

- `NoLifecycleFailure`;
- `LifecycleInadmissibilityFailure`;
- `LifecycleConflictFailure`;
- `CellCapacityFailure`;
- `RelationshipCapacityFailure`;
- `StaleGenerationFailure`;
- `GenerationOverflowFailure`;
- `LifecycleEvaluatorFailure`;
- `LifecycleFootprintFailure`;
- `LifecycleInvariantFailure`; and
- `LifecycleBackendFailure`.

The public failure mapping is complete and source-aware:

| Public failure | Runtime status or host diagnostic authority |
|---|---|
| filtered snapshot-relative inadmissibility | no phase failure; device-written bounded diagnostic/counter |
| snapshot-relative inadmissibility under `ErrorOnInadmissible` | device-written `LifecycleInadmissibilityFailure` |
| statically provable ambiguity or missing/illegal policy | host construction diagnostic; no executable is produced |
| runtime unresolved lifecycle conflict | device-written `LifecycleConflictFailure` |
| insufficient cell or relationship capacity | device-written `CellCapacityFailure` or `RelationshipCapacityFailure` |
| stale source/endpoint generation | device-written `StaleGenerationFailure` |
| generation-range exhaustion | device-written `GenerationOverflowFailure` |
| nonfinite, invalid, or partial evaluator result | device-written `LifecycleEvaluatorFailure` |
| request/emission/workspace bound or analyzed-footprint violation | device-written `LifecycleFootprintFailure` |
| failed planned/post-commit invariant, including impossible `ForbidExtinction` zero occupancy | device-written `LifecycleInvariantFailure` |
| capability mismatch known before launch | host compilation/admission diagnostic; no launch occurs |
| backend execution failure or runtime capability loss | host-synthesized `LifecycleBackendFailure`, preserving backend cause |

Device status is translated once at the declared phase boundary into the same stable
`PottsDiagnostic` categories used by host failures. A host may synthesize a status only for a
failure it alone can observe; it may not reinterpret a scientific device result or choose a
different offender.

Stable checkpoint capture remains limited to finalized MCS zero and the settled completed boundary
after lifecycle, equation, and required observation publication. Future-relevant state includes
ownership, slot status/high-water/reusable facts, kinds, generations, cell state/histories,
relationships with endpoint generations, tracker checkpoint state, MCS, parameters, seed/RNG
contract, compiled policy/stream identity, and executable fingerprint. Request queues, scan/sort
temporaries, staging buffers, and backend events reconstruct.

Exact same-profile continuation reproduces the uninterrupted lifecycle trajectory and trace. A
failed lifecycle phase creates no checkpoint and recovers only from the preceding settled boundary.

## 13. External extension proof

One test-only module outside CorePotts defines one versioned pure trigger operation, non-built-in
finite creation-placement policy, non-built-in binary partition policy, and non-built-in pure state
transform. Two compact neutral rules may cover them.

The module must complete through public registration, freeze concrete callable schemas, lower into
ordinary groups, run on sequential/checkerboard CPU and the functional GPU witness, adapt,
checkpoint/replay, infer, inspect, and diagnose. It requires zero edits to CorePotts program types,
engines, proposal loop, lifecycle executor, checkpoint machinery, operation switch, descriptor
union, or mechanism branches. It cannot register a structural verb.

## 14. Test architecture and exact exit matrix

### 14.1 Profiles

The fast default package profile contains small deterministic compiler rejection tests, exact CPU
effect/policy microfixtures, sequential/checkerboard direct-phase equivalence, independent
recomputation, conflict/capacity/generation properties, checkpoint replay, one warm allocation
assertion, and compact external-extension CPU coverage.

The explicit lifecycle qualification profile reuses those fixtures and adds the `1/32/1024`
growth panel, full inference/device inspection, workgroup and boundary sizes, real GPU execution,
no-fallback checks, and synchronized allocation/performance reports. Vendor runners contain no
scientific assertions. CorePotts tests transaction primitives once; PottsToolkit tests symbolic
admission/lowering/public execution once.

Every effect and stable policy receives one isolated exact test. Interactions use a risk-based
covering matrix, not the exhaustive effect-by-policy-by-engine-by-backend Cartesian product. No
evidence freshness, copied CI logs, renewed attestations, whole-object snapshots, legacy executable
oracle, or mandatory package-wide JET gate is introduced.

### 14.2 Required exit evidence

G5-L completes only when all of the following pass:

1. syntax, completion, closure, analysis, policy, bound, capability, and negative diagnostics;
2. one exact CPU microfixture for all five effects and every stable built-in policy;
3. common snapshot, invalid-high-priority versus valid-competitor, permutation, tie, complete
   capacity, no same-MCS reuse, ascending allocation, generation overflow, stale identity, and
   failure atomicity;
4. ownership conservation/transfer and independent tracker/relationship/invariant recomputation;
5. exact RNG addresses, stream isolation, replay, replica divergence, and checkpoint continuation;
6. direct lifecycle equivalence on sequential and checkerboard CPU from the same snapshot;
7. the external extension proof through CPU, checkpoint, inference, and real GPU;
8. functional Metal execution of every lifecycle effect/kernel/policy family with no host semantic
   work; and
9. warm allocation, bounded workspace, locality, specialization, inspection, and measured
   performance reports.

After the existing surface repair and G5-L pass, one fresh `R2Execution` reviews the complete G5
boundary. If it clears, work stops before G6. A blocker returns only to its earliest responsible
gate and does not authorize proof-model migration, a second production evaluator, or a new evidence
system.

## 15. Implementation ownership

Lifecycle implementation must be organized by compiler stage and runtime ownership. It must not be
added to `program/v1.jl`, `stage_plan.jl`, `sequential_program.jl`, or another growing catch-all
file as a collection of named effect branches.

The required responsibility split is semantic, not a mandatory file tree:

| Owner | Required responsibility |
|---|---|
| PottsToolkit public surface | effects, domains, policy values, and `LifecycleProcess` authoring |
| completion/normalization | extinction synthesis, qualified binding, frozen schemas, normalized lifecycle records |
| analysis | types, units, purity, totality, footprints, bounds, conflicts, policies, RNG, trackers, and capabilities |
| lowering/inspection | immutable CorePotts plans, descriptor groups, diagnostics, provenance, and public reports |
| CorePotts protocol | closed structural transactions and open pure-policy execution hooks |
| CorePotts transaction runtime | grouped requests, canonical conflict resolution, capacity/generation planning, staged commit, publication, and fixed status |
| shared runtime services | state/workspace, trackers, relationships, RNG, adaptation, checkpoint reconstruction, and backend launch machinery |
| tests | shared neutral fixtures, compiler rejection, transactions, checkpoint/RNG, external extension, and explicit qualification profiles |

Existing generic operation, evaluator, storage, tracker, relationship, RNG, checkpoint, and backend
protocols remain authoritative and are extended in their owned modules. The lifecycle directory may
call them but must not copy them. Vendor runners remain in their existing repository-owned backend
environments and include the shared lifecycle qualification module.

Exact files, directories, and private type names may follow the repository's evolving organization.
Ownership and compiler-stage boundaries must remain inspectable, and lifecycle work must not be
recombined into a catch-all monolith. No file or module may be named for Wortel, Merks, Act,
focal-point plasticity, apoptosis, mitosis, or another biological mechanism.

## 16. Bounded autonomous implementation checkpoints

These are engineering checkpoints inside G5, not new owner gates, CI workflows, releases, or
approval rounds.

### G5-L0 — Specification clearance

- independently review this candidate against the accepted construction spec and implementation;
- resolve every conflict in Section 17;
- amend the authoritative construction spec; and
- do not implement while a P0/P1 specification finding remains.

### G5-L1 — Surface, schemas, and compiler facts

- add the literal syntax/policy inventory and traversal;
- normalize qualified bindings and frozen reachable operation closure;
- analyze types, units, reads/writes, bounds, conflicts, policies, RNG, and capabilities;
- add exact negative diagnostics and inspection; and
- keep runtime execution unchanged until the compiler facts pass.

### G5-L2 — Transaction IR and sequential reference

- lower grouped request/policy/storage descriptors;
- implement slot status, capacity, generation, staging, commit, and checkpoint state;
- replace hardcoded retirement with synthesized `RetireAtZero`;
- implement all effects and policies through the sequential CPU reference; and
- pass local/global state, relationship, tracker, failure, RNG, and replay tests.

### G5-L3 — Shared checkerboard CPU path

- invoke the same lifecycle plan after checkerboard execution;
- implement canonical compaction/conflict/allocation with reusable workspaces;
- pass direct-phase equivalence, permutation, boundary, allocation, inference, and growth tests; and
- remove any duplicate engine-specific lifecycle authority.

### G5-L4 — Functional GPU and external extension

- adapt all lifecycle storage through the centralized boundary;
- run every effect/policy/kernel family on the Metal witness;
- prohibit scalar indexing, host semantic work, and host fallback;
- run the downstream extension proof; and
- qualify checkpoint transfer/restoration as an explicit boundary.

### G5-L5 — Qualification and R2 handoff

- run fast and qualification profiles without duplicated assertions;
- record inspection, allocation, locality, compilation, and performance reports;
- perform source audit for hardcoded mechanisms and old retirement paths;
- obtain fresh `R2Execution`; and
- stop before G6 on clearance.

## 17. Required authoritative reconciliations

The independent reviewer must confirm these exact dispositions before the construction spec is
amended:

| Existing authority or implementation | Conflict | Candidate disposition |
|---|---|---|
| `lib/CorePotts/src/execution/sequential_program.jl` | unconditional zero-volume scan, generation increment at retirement, full cell-state zeroing | remove; synthesize ordinary lifecycle plan, apply schema policies, advance generation on reuse |
| `src/compiler/lowering/stage_plan.jl` | cell lifecycle effects skipped; lifecycle relationship work folded into `AfterMCSStage` | add distinct lifecycle plan/stage and admit the closed cell effects |
| `spec/state-model.md` | generation advances on reuse | retain and sharpen with explicit slot status and first-generation law |
| Decision 0004 wording | may imply retired slots already carry incremented generation | interpret/supersede to mean increment on later allocation, not retirement |
| `spec/lifecycle.md` | optional division connectivity | V1-L requires the explicitly selected division relation and connected nonempty daughters |
| `spec/lifecycle.md` | parent type preserved by default | retain a documented constructor default that freezes explicit `PreserveKind()` values for both descendants; CorePotts never infers a missing kind law |
| historical open lifecycle effects | allows registered structural effects | V1-L closes structural mutation to the five verbs; only pure policies/operations extend |
| historical host-only lifecycle alternatives | permits synchronizing host triggers/actions | exclude from stable V1-L and from R2 claims; no hidden host facility in compiled lifecycle |
| historical multirate lifecycle | permits timed extra lifecycle boundaries | defer; V1-L has the one ordinary integer-MCS lifecycle phase |
| concrete RNG address | only global/site entity kinds | version and add honest cell/lifecycle semantic identities |
| current relationship GPU witness | proves reads but not mutation | retain read evidence but require complete lifecycle relationship mutation before R2 |
| current default test organization | expensive inspection mixed into everyday suite | share fixtures while separating fast and explicit qualification profiles |

This candidate must not silently edit every historical document. The authoritative construction
spec should state precedence for V1 and link historical documents as background. Normative conflicts
must be amended or explicitly superseded; duplicative prose should not create a second authority.

## 18. Independent review questions

The focused reviewer receives the accepted owner interview, this candidate, the authoritative
construction spec, the current diff, and relevant historical decisions. The reviewer treats the
following as questions, not findings:

1. Is the five-effect structural algebra closed, sufficient, and free of hidden named biology?
2. Does `RetireAtZero`/`ForbidExtinction` remove hardcoded retirement without creating an illusion
   of configurability or an unnecessary general rewrite language?
3. Are the domain, placement, division, state, relationship, conflict, and inadmissibility
   inventories literal, bounded, and mutually coherent?
4. Is every symbolic-to-policy/evaluator path canonical, frozen, and impossible to bypass through
   external registration?
5. Can every admitted effect and pure extension policy execute through one concrete engine-neutral
   plan on CPU and the real GPU witness without central CorePotts edits?
6. Are allocation, generation, same-MCS non-reuse, stale relationship, and checkpoint identities
   exact and internally consistent?
7. Does staged publication give the promised scientific atomicity without implying device crash
   rollback or requiring a full runtime shadow?
8. Are locality, allocation, specialization, and test-profile requirements strong enough to prevent
   architectural debt without recreating expensive evidence bureaucracy?
9. Does the exit matrix prove all claims with a risk-based covering set rather than a wasteful
   Cartesian product?
10. Are any accepted clauses missing, contradictory, unimplementable on Metal, or larger than the
    bounded G5-L goal?

The reviewer must cite the governing clause, smallest affected location, concrete counterexample or
static proof, and earliest repair checkpoint for every blocker. The review may recommend amendment,
but it must not implement production changes. P0/P1 findings block authoritative consolidation and
G5-L implementation; P2 findings require explicit disposition but need not expand scope.

## 19. Non-goals and stop condition

V1-L does not migrate Wortel, Merks, or focal models; add fusion/fragmentation; add daughter link
transfer; add lineage identity; add general event composition; add arbitrary callbacks; add a
second executor; qualify sequential GPU; introduce Dagger/Metatheory; create a legacy oracle; or add
new CI/evidence infrastructure.

After independent clearance, this candidate is folded once into the authoritative construction
spec and this audit remains decision provenance. Implementation then proceeds autonomously through
G5-L1 to G5-L5. R2 clearance ends the effort before G6 for owner review.

## 20. Consolidator-derived clarifications

The owner interview accepted the governing semantics but did not separately ballot every concrete
constructor or storage spelling. This candidate derives the following bounded clarifications. They
are hypotheses for independent review, not additional owner decisions smuggled into authority:

1. `model()` supplies the one finite singleton event domain needed by accepted global creation.
2. `RetireAtZero()` and `ForbidExtinction()` make the accepted phrase “cell kinds that permit
   stochastic extinction” explicit and remove the last hidden central retirement choice.
3. One cell-targeting `LifecycleProcess` contains exactly one structural effect; its resolved kind,
   state, relationship, and site-ownership policies provide bounded composition.
4. Immutable semantic before/planned-after policy views permit accepted post-partition state
   mathematics without mutation/rollback or visibility of unrelated same-phase results; their
   concrete private representation remains an implementation choice.
5. Slot status distinguishes never-used and reusable capacity so generation advances exactly at
   identity creation.
6. Both kind-preservation defaults are concrete frozen policy values shown in inspection;
   `on_inadmissible` is mandatory for every structural effect.
7. The literal device status categories and responsibility ownership make GPU failure and
   implementation boundaries reviewable without expanding scientific vocabulary.

If review shows that one clarification changes scientific scope rather than merely completing an
accepted contract, it returns to the owner as one bounded question. It must not be silently chosen
by implementation.

## 21. Accepted-decision traceability

| Decision | Consolidated clauses |
|---|---|
| LCI-R1-01 | Sections 1 and 2.2 |
| LCI-R1-02 | Section 3 |
| LCI-R1-03 | Sections 4 and 10 |
| LCI-R1-04 | Sections 2, 4, and 13 |
| LCI-R1-05 | Sections 14, 16, and 19 |
| LCI-R2-01 | Sections 2.5 and 2.7 |
| LCI-R2-02 | Sections 2.2 and 2.6 |
| LCI-R2-03 | Section 2.3 |
| LCI-R2-04 | Section 2.4 |
| LCI-R2-05 | Section 2.5 |
| LCI-R2-06 | Section 2.7 |
| LCI-R3-01 | Section 5 |
| LCI-R3-02 | Sections 2.8 and 7.2 |
| LCI-R3-03 | Section 7.3 |
| LCI-R3-04 | Section 6 |
| LCI-R3-05 | Section 8 |
| LCI-R3-06 | Section 10 |
| LCI-R3-07 | Section 12 |
| LCI-R4-01 | Sections 5 and 8 |
| LCI-R4-02 | Section 11 |
| LCI-R4-03 | Section 13 |
| LCI-R4-04 | Section 12 |
| LCI-R4-05 | Section 9 |
| LCI-R4-06 | Section 14 |
| LCI-R4-07 | Sections 14, 16, and 19 |
| LCI-X-01 | Sections 11 and 14 |
| LCI-X-02 | Sections 1 and 19 |
| LCI-R5-01 | Sections 2.6, 5, 7.3, and 12 |
| LCI-R5-02 | Sections 2.8 and 3 |
| LCI-R5-03 | Sections 2.1 and 3 |
| LCI-R5-04 | Sections 4 and 13 |
| LCI-R5-05 | Section 4 |
| LCI-R5-06 | Sections 2.7 and 3 |
| LCI-R5-07 | Sections 5, 12, and 15 |
