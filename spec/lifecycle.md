# Cell Lifecycle

Status: Accepted except family-specific auxiliary distributions that remain required evidence

For Symbolic Potts V1 compiler construction, CCV1-027 in the
[compiler construction contract](symbolic-potts-v1-compiler-construction.md) is authoritative where
this historical Phase 8 specification is broader or ambiguous. In particular, V1 closes structural
cell mutation to five effects, closes event domains to active cells and one model singleton,
requires one explicit division relation, excludes host fallback and a second lifecycle clock,
advances generation on reuse rather than retirement, and replaces unconditional zero-volume
retirement with the explicit `RetireAtZero`/`ForbidExtinction` law.

## Lifecycle Phase

Lifecycle and property events occur at integer-MCS boundaries. All event triggers for MCS `t` MUST
observe one common event-phase snapshot after the MCS proposal and auxiliary work and before any
lifecycle mutation at that boundary.

Event declaration order, tuple order, thread scheduling, and backend scheduling MUST NOT implicitly
determine biological conflict resolution.

The Symbolic Potts V1 lifecycle engine MUST evaluate bounded triggers, emit and canonicalize
requests, plan request-local placement/partition and filter or fail inadmissibility, resolve
conflicts among valid requests, plan and validate the complete batch, preflight identity/generation/
relationship capacity, stage authoritative and derived-state updates, validate postconditions, and
then publish once. There is no effect-category precedence and no unconditional zero-volume scan.

IDs retired during MCS `t` MUST NOT be reused until MCS `t + 1`.

## Event Scheduling

Each event owns a reusable integer-MCS schedule value. Schedule membership is a pure query of the
completed MCS boundary and MUST NOT depend on launch count, internal algorithm rounds, wall-clock
time, declaration order, or mutable iteration state.

The required built-in schedule meanings are:

- every positive integer-MCS boundary;
- exactly one positive integer MCS;
- an explicit finite collection of positive integer MCS values; and
- a periodic schedule with an inclusive positive start, positive period, and optional inclusive
  stop.

MCS `0` denotes the finalized initial condition. It is not an ordinary lifecycle boundary, and a
stable lifecycle schedule MUST reject MCS `0` and negative times during construction. Initialization
behavior belongs to the initialization protocol rather than a lifecycle event disguised as a
zero-time callback.

Schedule families are an open Julia protocol. A host schedule MAY use convenient construction-time
state, but a GPU-qualified schedule MUST lower to an immutable bitstype-compatible descriptor with
stable identity and semantic serialization. Built-in forms are conveniences rather than an
exhaustive enum. A single global `check_interval` is not normative.

Lower-level scheduling rounds remain internal and MUST NOT be used as biological event time.

## Event Structure and Pre-Event Snapshot

A lifecycle event composes four independently typed semantic values:

1. a target domain;
2. a schedule;
3. a trigger; and
4. an effect.

Conflict resolution is a typed phase-level policy rather than an incidental property of container
order. Stable Symbolic Potts V1 target domains are active finite cells and one qualified global
model target. Additional cell-lifecycle event domains are deferred. Finite site expressions may be
used by placement policy without becoming site-iterated event domains. Relationship processes
retain their separately bounded domains.

Every due trigger at MCS `t` observes the same immutable `PreLifecycleSnapshot(t)`. A trigger MUST
declare its target domain, required reads, stochastic operation labels, workspace bound, and
capabilities. Trigger evaluation is side-effect free: it returns a compact decision or mask and
MUST NOT mutate model state. Stochastic triggers MAY use only semantically addressed lifecycle RNG;
their addressed draws remain pure functions of the accepted randomness contract.

Post-event values do not exist for trigger evaluation. They become observable only after the entire
validated lifecycle transaction commits. An event cannot read a value written by another event at
the same boundary unless the model expresses both operations as one explicitly composed effect with
defined internal semantics.

Host-only triggers are outside stable Symbolic Potts V1 and its R2 claims.

## Effect Planning and Commit

Stable lifecycle effects are typed transactions. An effect MUST declare, as applicable:

- target, read, write, identity-change, and conflict scopes;
- required properties, observables, relations, fields, and auxiliary families;
- capacity, workspace, reduction, atomic, RNG, and synchronization requirements;
- supported dimensions, algorithms, numerical modes, and backends; and
- its reference planning, validation, and commit behavior.

For Symbolic Potts V1, the top-level cell-structure taxonomy is exactly `CreateCell`, `RemoveCell`,
`Retire`, `Transition`, and binary `Divide`. Pure trigger, placement, partition, and state-transform
operations remain open only through the frozen versioned ABI in CCV1-027. A new structural family
cannot enter through ordinary operation registration.

Planning reads only the common `PreLifecycleSnapshot`. Validation completes before any affected
state mutates. Commit occurs only through category-owned transaction machinery so declared writes,
identity changes, capacity use, derived-state repair, diagnostics, failure atomicity, and the single
publication boundary cannot be bypassed.

Arbitrary imperative mutation is outside Symbolic Potts V1. It MUST NOT be silently lowered,
treated as a stable effect, or executed between planning and commit kernels.

## Event Conflicts

At most one identity-changing outcome MAY apply to one finite cell at one MCS boundary. Identity-
changing outcomes include division, immediate death, and type transition.

Models with potentially overlapping identity-changing triggers MUST provide an explicit resolver or
an explicitly composed lifecycle event. Silent vector-order priority is prohibited.

Conflict resolution is an open typed policy under the closed one-outcome and atomicity laws. The
required Phase 8 built-in meanings are reject ambiguity and resolve by an explicit stable semantic
priority. An explicitly typed composition MAY be added when a concrete model requires combined
behavior; Phase 8 does not implement a general resolver-composition algebra. A priority key is model
semantics; declaration position, tuple layout, cell ID, compiler batching, workgroup size, launch
decomposition, thread scheduling, and atomic arrival order are not implicit priority keys.

The default policy rejects ambiguity; it does not assign universal category priority. Statically
detectable unresolved conflicts MUST fail model construction. Intended overlap requires an explicit
typed resolver such as stable semantic priority. A conflict discovered only from the runtime trigger
set MUST abort the affected phase before any lifecycle mutation and produce a bounded structured
diagnostic or error.

For the same pre-snapshot, trigger decisions, semantic identities, and explicit resolver, the
resolved transaction set MUST be invariant under permutation of declarations, tuple representation,
homogeneous compilation batches, and device launch tuning. Atomics may implement a proven resolver;
they do not define its scientific outcome.

Property updates MAY coexist if their snapshot, read, write, and conflict behavior is valid under the
future rule-language specification.

## Division Eligibility

Division triggers are evaluated from the event-phase snapshot. Newly created cells MUST NOT become
eligible again during the same event phase.

Surviving requests MUST be canonically ordered by qualified request identity after conflict
resolution. Parent-child ID assignment MUST be deterministic for the same model, seed, backend,
and package version.

## Division Identity

For a successful division:

- The parent retains its cell ID.
- The new daughter receives the lowest available reusable ID or the next valid fresh ID.
- The child slot generation is incremented when a reusable ID is assigned.
- Both resulting cells preserve the parent's type by default.
- A division rule MAY explicitly assign different valid parent and daughter types.

No public permanent lineage identity is required in specification version `0.2-draft`.

## Division Geometry

Symbolic Potts V1 admits the closed built-in plane inventory and versioned pure external binary
partition operations specified by CCV1-027. A host geometry value declares its scientific meaning,
requirements, capabilities, and lowering. A GPU-qualified geometry lowers to an immutable
bitstype-compatible descriptor and an allocation-free device method that assigns each parent-owned
site a compact descendant-region label.

Phase 8 qualifies binary division: every valid proposal must contain exactly two nonempty descendant
regions, one retaining the parent identity and one receiving the new child identity. The compiled
partition result MUST NOT be represented by a permanently binary Boolean contract; compact region
labels preserve a future path to additional arities without claiming or implementing them in Phase
8.

Required V1 built-in geometries are random plane, specified-normal plane, and major/minor
principal-axis plane. A non-built-in external binary partition may be admitted only through the
same frozen pure-policy ABI and transaction invariants; V1 does not promise a general geometry
catalog.

Phase 8 implements the four required families and one non-built-in conformance geometry. Other
geometry catalogs and nonbinary division remain deferred even though the protocol must not prevent
their later addition.

A successful division MUST satisfy:

1. Parent and daughter each own at least one site.
2. Their combined post-division sites equal exactly the parent's pre-division sites.
3. No site is lost, duplicated, or transferred from an unrelated owner.
4. Any configured minimum daughter-volume requirement is satisfied.
5. Both descendants are connected under the division's explicitly selected finite relation.

The minimum daughter volume is one site. The division relation is mandatory and frozen model
semantics; the runtime does not select a hidden connectivity relation.

A geometrically invalid division affects only that parent and is rejected before child-ID
allocation. Other valid divisions MAY proceed. The failed parent receives no child ID and remains
eligible for reevaluation at a later scheduled event. The failure MUST be recorded in diagnostics.

## Division Transaction and Capacity

Division is a transaction. Its logical order is:

1. Snapshot and stably compact eligible parents.
2. Compute and validate proposed geometry.
3. Count geometrically valid divisions.
4. Preflight fixed capacity.
5. Allocate child IDs deterministically.
6. Commit lattice ownership changes.
7. Apply biological property inheritance.
8. Recompute derived properties.
9. Initialize auxiliary properties.
10. Validate division invariants.

If capacity cannot accommodate the complete valid batch, the complete batch MUST abort without
mutation and a structured `CellCapacityError` MUST be raised. Committing only a deterministic subset
is prohibited.

A synchronization required to surface a capacity exception is permitted. Zero-sync execution MUST
NOT leave a partially committed biological transaction.

## Property Inheritance

Every biological property has a schema-level typed division policy. Division events MAY explicitly
override compatible policies. The schema value is used otherwise; declaration order never resolves
two competing overrides.

Division, type transition, and retirement use separate operation-specific policy protocols. Policy
behavior is selected by multiple dispatch on the owned policy value, not a behavioral enum, one
large callback object, or a central concrete-family switch. The property schema described in
`state-model.md` is the only lifecycle-policy authority.

Supported policy families MAY include:

- Clone parent state to the child
- Preserve parent and reset child
- Reset both
- Asymmetrically reset parent and child
- Conservatively split
- Apply an explicit device-compatible transformation

Arbitrary user properties MUST NOT receive an undocumented global inheritance default. A custom
property must select a documented division policy or explicitly mark division unsupported. If an
unsupported operation is reachable in the compiled model, construction fails with the property,
requesting event, and compatible policy requirements.

Derived properties, including volume, surface area, centroid, inertia, current length, contact
counts, and neighbor summaries, have no ordinary inheritance policy. They MUST be recomputed or
incrementally repaired from authoritative committed post-division state through their declared
derived-property protocol.

For conserved integer properties split by a fraction, the policy MUST explicitly select keyed
stochastic rounding or a deterministic remainder law while preserving the exact total. A stochastic
draw MUST use the lifecycle RNG stream and remain repeatable under the accepted reproducibility
contract. There is no undocumented global rounding default.

## Auxiliary State After Division

Every auxiliary family owns explicit typed policies for initialization, division, type transition,
progressive death, immediate death, extinction, retirement, and slot reuse wherever those operations
can affect its state. Family policy methods use the ordinary lifecycle transaction and schema
protocols; they do not introduce a second inheritance engine.

For an equilibrium auxiliary constraint, both daughters are sampled from the derived joint
conditional distribution after the post-division lattice and derived observables are final. Blind
cloning is prohibited. A conditional-mean initializer MAY be used only as an explicitly selected,
documented policy.

Mechanical auxiliary components MAY define conservation, inheritance, transformation, or reset
policies, but each policy MUST state its physical meaning and MUST NOT inherit an equilibrium claim.
Focal-link auxiliary state is created only after both endpoint generations and link geometry commit;
link removal retires its state in the same transaction. Extinction clears auxiliary state atomically,
and slot reuse creates a new generation, initialization event, and semantic RNG identity.

The family-specific distributions remain required Phase 8 evidence. A family whose lifecycle law is
not derived is incompatible with that lifecycle operation rather than silently applying a generic
clone, reset, zero, or conservation fallback. Missing family behavior MUST fail model construction
when the operation is reachable.

### Property-policy planning

A compiled property or auxiliary policy plans from the common `PreLifecycleSnapshot` and returns a
compact update description without mutating model state. The plan declares all written slots,
parent/descendant roles, RNG operation labels, invalidated derived state, and bounded workspace.
Variable-sized work uses preallocated capacity established during model compilation.

All applicable property and family plans are validated before the enclosing lifecycle transaction
commits. A failure aborts that transaction without partially applying another property's update.
GPU-qualified planning and commit are allocation-free, statically specialized, and device-resident
under the accepted lifecycle execution contract.

## Type Transitions

A type transition is transactional. Before mutation, the engine MUST:

1. Validate the destination type.
2. Resolve transition behavior for every affected property.
3. Verify destination requirements.
4. Compute transformed or reset values.
5. Commit the type and property changes together.

Property transition policies include preserving the current value, resetting to the destination
type's default, applying an explicit transformation, invalidating an unsupported transition, or
recomputing derived state.

Each custom biological property selects one of these documented policy families, defines another
conforming typed policy, or explicitly declares transition unsupported. Derived state is repaired
through its derived-property protocol rather than an ordinary transition policy.

Type-level rigid parameters use the destination type immediately after commit. Per-cell flexible
parameters follow their property transition policies.

## Death Modes

Progressive shrink death and immediate death are distinct public concepts.

**Shrink death** initiates a model-defined progressive process, commonly by reducing target volume
and optionally changing mechanical properties. The cell remains active until its occupancy reaches
zero or an explicit terminal condition invokes immediate removal.

**Immediate death** removes all ownership of the cell at one MCS boundary and retires its slot as a
single transaction.

The generic term apoptosis MUST NOT obscure which death mode is being modeled.

## Extinction and Retirement

Every finite cell kind MUST resolve either `RetireAtZero` or `ForbidExtinction`. The former
synthesizes an ordinary qualified retirement process. The latter synthesizes a generic proposal
constraint preventing loss of the final site. A zero-occupancy `ForbidExtinction` identity at
lifecycle planning is a nonfilterable invariant failure. No active zero-volume identity is
published.

Retirement MUST:

1. Remove the ID from the active set.
2. Reset all device properties to their schema-defined retired state.
3. Preserve no stale biological values visible in snapshots.
4. Preserve the consumed generation until future allocation preflight.
5. Add the ID to the next-MCS reusable collection exactly once.

Retirement cleanup is exhaustive and schema-driven. Each authoritative biological property and
auxiliary family supplies its explicit canonical retired value or retirement operation; derived
state is invalidated and cleared or recomputed by its family. Missing cleanup behavior is invalid at
model construction, not a request for a universal zeroing fallback.

Retirement causes SHOULD distinguish programmed death, immediate death, completed shrink death, and
stochastic extinction.

## Lifecycle Execution Locations

The stable GPU lifecycle path accepts compiled device-executable schedules, target domains,
triggers, planners, conflict resolvers, validators, transformations, and commit operations. The
public host object need not itself be a bitstype, but every GPU-qualified value MUST lower to an
immutable bitstype-compatible descriptor and bounded device storage.

The device path MUST use concrete argument types, static specialization, preallocated workspaces,
and portable KernelAbstractions behavior before optional backend specialization. It MUST NOT use
runtime device dispatch, per-event allocation, device exceptions, reflection, heap-backed policy
objects, or unbounded retry. Accelerated operations and intrinsics are implementation choices and
must separately satisfy transaction, reproducibility, and CPU/Metal/ROCm qualification.

Host lifecycle actions and arbitrary host callbacks are outside stable Symbolic Potts V1.

Kernel launch order is execution machinery, not event precedence. No GPU lifecycle compatibility
claim is valid unless the complete schedule-through-commit path compiles and runs on every claimed
backend without hidden host fallback or synchronization.

## Diagnostics

Lifecycle diagnostics MUST expose inexpensive counters including, where applicable:

- Births
- Death-program initiations
- Immediate deaths
- Completed shrink deaths
- Stochastic extinctions
- Successful divisions
- Failed division geometry
- Capacity failures
- Type transitions
- Active finite cells
- Free slots

Detailed event logs and lineage histories MAY be optional output backends rather than mandatory
in-memory state.

## Phase 8 Minimal Implementation Boundary

The accepted semantics do not require Phase 8 to implement every family admitted by these open
protocols. Production scope is limited by the
[Phase 8 Minimality Pass](../design/audits/phase-8-minimality-pass.md): paper-required built-ins, one
combined downstream extension fixture, and the generic behavior shared by them. Dynamic-link
events, general conflict-composition algebra, nonbinary division, arbitrary host callbacks,
lineage-history infrastructure, and a universal equilibrium-auxiliary system are deferred.
