# CorePotts compiler targeting LocalMath

CorePotts compiles bounded proposal and mechanical semantics into LocalMath.
This document defines the target architecture, ownership boundary, direct
cutover order, and qualification requirements. Development chronology is not
part of the resulting API, runtime identity, or checkpoint schema.

## Architecture and ownership

The production execution path is:

```text
DescriptorExecutionPlan + ResourceAccess + StageExecutionPlan
        ↓
CorePotts scientific compiler
        ↓
ordinary LocalMath Fields, Relations, Stages, and LocalLaw
        ↓
Plan / PreparedPlan
        ↓
one packed KernelAbstractions CPU/GPU executor
```

CorePotts owns Hamiltonian and proposal meaning, canonical descriptor order,
before/after overlays, semantic RNG, Metropolis acceptance, checkerboard
scheduling, tracker formulas, relationship meaning, lifecycle transactions,
rollback, bank authorization, and checkpoints. LocalMath owns bounded access,
routing, validation, ordering, conflict laws, publication, workspace, and
physical execution. SequentialCPM remains the independent scientific
reference.

No runtime compiler object, symbolic expression, descriptor plan, unpacked
relationship state, or array-capturing evaluator may reach a LocalMath kernel.
No compatibility executor, selector, migration representation, scheduler, or
backend-specific authoring path is permitted.

The checkerboard device program retains only executable scientific resources.
In particular, the host `DescriptorExecutionPlan`, compiled proposal plan, and
`StateLayout` are consumed before preparation and never enter a Core or
LocalMath kernel argument. Lifecycle and stage evaluators receive the adapted
domain-resource tables directly. Extinction policies and packed relationship
bank offsets, counts, and payload arities are derived cold from the host program
and carried as immutable tuples; preparation never indexes adapted arrays on
the host. Fixed topology copied to an accelerator is materialized explicitly as
cold `Allocate(source)` storage before planning.

## Compiler inputs and qualification

`ResourceAccess` is an aggregate coverage proof, not a positional gather plan.
The compiler recursively traverses every `StaticEvaluator` operation in exact
`source_table` order and qualifies it against:

- its descriptor role and source provenance;
- declared state handles and tracker quantities;
- the aggregate read footprint;
- Hamiltonian domain-resource tables;
- checkerboard geometry and state layouts.

Each required gather has a canonical key containing its resource identity,
anchor, relation or normalized offsets, before/after mode, required or
sample-aware mode, ordering, and relationship slot. Equal gathers are
deduplicated in first-use order. Distinct scientific meanings are never merged.

Unknown contextual operations reject during cold compilation unless they have
an explicit gathered-context implementation and all required bounded resources
are declared. Errors identify the source descriptor, operation, footprint, and
missing contract. Cold vectors, dictionaries, and records used during lowering
must disappear after the LocalMath law and bindings are constructed.

The executable representation consists only of concrete isbits compiled terms,
typed positional bindings, ordinary scalar operations, and bounded read views.
Scientific parameters and temperature use LocalMath submission parameters so
their values may change without re-preparation.

## Topology lowering

One maximum-color proposal space is shared by the law schema. A single
tuple-valued padded schedule stores every color at each proposal lane. The
submitted color selects one tuple component and `batch_size` limits the active
lanes. Color is therefore a value, not a separately planned program.
Geometry publishes target, source, semantic identity, priority, and other
derived keys through multi-port `Unique`.

Every prefix-controlled scratch publication declares `PartialCoverage` with
`PreserveEmpty`: lanes beyond `batch_size` are intentionally untouched and
cannot truthfully claim total destination coverage. When its reads are proven
infallible and its routes are identity-pointwise, LocalMath executes the whole
heterogeneous multi-port stage with its existing one-launch direct executor.
Resolve, Reduce, routed publication, relationship validation, and ordered-state
stages retain their explicit buffered barriers.

Successive data-dependent keys use explicit stage boundaries:

```text
publish site key
→ IndexRelation into ownership
→ publish owner key
→ IndexRelation into owner-scoped resources
```

This preserves LocalMath's stage-entry visibility rule.

Footprints lower as follows:

- local geometry uses identity and affine relations;
- finite spatial neighborhoods use affine relations with periodic or exterior
  boundary policies;
- footprint unions become several first-use-deduplicated accesses, not a
  Cartesian `ProductRelation`;
- Minkowski footprints become cold-materialized summed offsets or genuine
  relation composition when the static degree bound permits it;
- reverse affected neighborhoods use the corresponding reversed offsets;
- owner and other runtime keys use `IndexRelation`;
- contact duplicate removal remains in the Core evaluator and preserves
  canonical relation order.

Core variable-degree owner-to-edge incidence reads the canonical whole-bank
`incident_edges` Field used by relationship settlement. A cold `FixedRelation`
maps each owner to the store's global flattened incident slots and is selected
through the owner-key injection. One following `Unique` stage translates the
stored local edge IDs into bank-global edge keys for an optional
`IndexRelation` over the canonical whole-bank active, endpoint, and payload
Fields. The science path and `OrderedFold` therefore bind each mutable packed
leaf once; neither a second per-store Field set nor an aliasing stored inverse
relation exists. It is not represented by `PackedRelation`, whose fixed-lane
meaning is different. No packing occurs on a warm path.

Relationship endpoint geometry requires one explicit derived-key boundary.
The selected incidence gather publishes the bounded endpoint-owner keys, and a
following stage uses an optional `IndexRelation` to gather endpoint volumes and
moment components. This is necessary because a relationship endpoint owner is
not necessarily the proposal's old or new owner. Inactive incidence lanes use
ordinary absent keys; packed-bank integrity remains the authority proving that
active endpoint keys are valid. The evaluator never fabricates zero geometry
for a third endpoint owner.

## Gathered scientific evaluation

CorePotts defines a narrow scientific-access protocol shared by the sequential
runtime context and the gathered checkerboard context. It covers parameters,
ownership, owner kind, tracker values, descriptor state, spatial neighbors,
relationship incidence/endpoints/payload, and semantic RNG.

The gathered context contains only proposal geometry, bounded reads, fixed
tuples, positional bindings, submission parameters, and local before/after
overlays. Existing Hamiltonian role algorithms operate through the narrow
protocol rather than through a complete runtime object.

Compiled terms are stored in increasing source-handle order. Their recursive
accumulation performs the same fieldwise operations in the same order as the
reference evaluator. Terms may not be regrouped by role, relation, or resource.
Non-associative cases such as `(1e16, -1e16, 1)` are part of the numerical
contract.

## Prepared mechanics

One semantic law and lowering schema is constructed. It is prepared exactly
once against each state bank. Both preparations have the same concrete type
and specialization families; schedule contents and bank identity remain
bindings, while color, scientific step coordinates, and batch size remain
submission values. No color causes another planning or lowering pass.

One color submission contains this ordered structure:

```text
Core status gate
→ proposal geometry and semantic RNG
→ derived keys and bounded gathers
→ canonical scientific evaluation, acceptance, and pure accepted-effect evaluation
→ deterministic acceptance-failure publication
→ refreshed Core status gate
→ owner Resolve
→ mutual-maxima conjunction
→ accepted-effect selection from typed scratch
→ relationship shadow settlement
→ final scientific publication
```

One Core status bridge follows each LocalMath submission. It translates a
LocalMath receipt failure into Core's `ProgramStatus`; this is domain status
translation, not a second executor.

## Accepted effects and final publication

Core effects lower according to their existing meaning:

| Core meaning | LocalMath lowering |
|---|---|
| accepted target assignment | target-routed `Unique` |
| synchronous site assignment | total identity `Unique` |
| scalar model assignment | singleton partial `Unique` |
| fixed synchronous recurrence | a finite ordered sequence of `Unique` stages |
| history shift and append | buffered dimension-preserving publication |
| exact integer aggregation | deterministic `Reduce(+)` |
| deferred relationship request | bounded request publication plus `OrderedFold` |

No current Core write policy denotes generic resolution. Unsupported future
policies reject cold rather than being guessed.

Assignments targeting the same state handle preserve descriptor order. Pure
accepted-effect expressions are evaluated against the gathered proposal
context in the same stage that already owns that context. Their typed results
are stored as descriptor-local scratch and selected only after mutual-maxima
acceptance. The gathered context itself is never materialized as a field: that
would duplicate semantic state, create a large structured-storage ABI, and
retain values that later stages do not need. The terminal evaluator starts from
the stage-entry value, applies ownership-change clearing, then applies selected
assignments and publishes one final result. Ownership, tracker, auxiliary-state,
report, and relationship results are computed in scratch before scientific
publication.

All fallible stages write scratch. The terminal publication section contains
only previously validated writes. Several infallible identity stages may be
used when destination arrays have different physical extents; they remain one
ordered commit section on the sole executor.

Failure prevents authorization of the destination bank. Earlier successful
colors may have changed that inactive bank, so the contract is unchanged
authoritative state, not byte-for-byte restoration of inactive storage.

## Packed relationship settlement

Create, remove, and retune effects publish a bounded Core request record with
logical store, kind, edge or endpoints, endpoint generations, payload,
priority, semantic identity, and participation.

For each physical packed bank, `OrderedFold` initializes package-owned shadow
components from the live bank, orders requests canonically, applies a
Core-owned transition, and leaves final shadow leaves for the terminal
publication section. Canonical order is:

```text
logical store
→ Remove / Retune / Create
→ priority
→ canonical edge or endpoints
→ semantic identity
```

The transition retains Core's capacity, generation, endpoint-admission,
duplicate, contradiction, idempotence, and conflict semantics. A status shadow
component records deterministic Core failures and may halt the recurrence.
LocalMath structural validation continues through receipt diagnostics.

Schema-specific fold step size and update count are checked during preparation.
The current degree and bounded-write limits remain authoritative until a real
supported schema demonstrates that a LocalMath bound must be raised.

## Lifecycle boundaries

The final queue order is:

```text
LocalMath state initialization and report reset
→ cumulative color mechanics
→ optional before-lifecycle LocalMath law
→ Core lifecycle transaction
→ optional after-lifecycle LocalMath law
→ Core bank authorization and publication
```

Lifecycle planning, selection, staging, validation, rollback, failure stamping,
checkpoint materialization, and bank publication remain Core-owned. Provider
queue ordering and explicit Core status gates connect these regions; no native
event fiction or LocalMath scheduler is introduced.

The Core stage compiler consumes `StageExecutionPlan` directly. It does not
adapt that plan into a device representation or expose a complete Core runtime
as an evaluator input. Its bounded source domains are determined by durable
effect meaning:

- synchronous site assignments evaluate over the lattice and publish through
  identity-routed `Unique`;
- scalar model assignments evaluate over a singleton model space;
- relationship remove and retune operations evaluate over the bounded active
  lanes of their canonical packed bank and settle through `OrderedFold`;
- fixed-count site recurrences expand into a finite sequence of synchronous
  LocalMath stages, so each iteration observes the preceding publication;
- history shift and append lower to a buffered, dimension-preserving
  publication whose reads all observe stage-entry state.

State, ownership, kind, tracker, neighborhood, and relationship metadata are
ordinary typed LocalMath reads selected from each descriptor's existing
`ResourceAccess`. Conditions and values are concrete isbits Core callables over
those reads. A nonfinite value or non-Boolean condition fails before the
terminal publication and closes the existing Core status gate.

The before- and after-lifecycle programs are prepared once per destination
bank and use the same law schema on CPU and GPU. After this compiler owns every
after-MCS family, `StageKernelPlan`, adapted stage descriptors, after-MCS
scratch buffers, and the synchronizing checkerboard host-stage fallback have no
remaining semantic owner and are deleted together. `StageExecutionPlan`
remains the Core scientific, checkpoint, and SequentialCPM authority.

## Receipt ownership

Each bank owns one cumulative mechanics receipt vector plus receipts for actual
lifecycle boundaries. The latest receipt is the logical dependency tail, but
all outstanding receipts remain retained until settlement because waiting on a
dependent receipt does not release predecessor leases.

Settlement flattens receipts in deterministic scientific order, calls
`waitall`, performs at most the existing provider synchronization, decodes
failure, releases every lease, and then clears the vectors. Per-family proposal,
claim, validation, effect, and relationship receipt banks are forbidden.

## Direct cutovers and deletion

Implementation follows dependency order, with each production replacement and
its old machinery deleted together:

1. Introduce the shared scientific-access protocol and make the existing
   reference/runtime contexts consume it.
2. Implement recursive operation qualification, gather inventory, topology
   construction, and the gathered evaluator.
3. Compose proposal, acceptance, owner resolution, and mutual maxima into one
   prepared color law; switch production and delete the raw proposal and
   standalone selection paths.
4. Add accepted-effect scratch and final publication; delete accepted
   evaluation, validation, application, and ownership-commit kernels.
5. Move packed relationship mechanics beneath `OrderedFold`; delete custom
   reset, sort, fold, and packed-copy execution.
6. Compile before- and after-lifecycle effect groups; delete device
   `StageKernelPlan` machinery and obsolete host crossings.
7. Shrink checkerboard workspace/state, inspection, execution identity, and
   checkpoint schema; retain no obsolete decoder.

The removed machinery includes the opaque checkerboard science wrapper, raw
proposal preparation/kernel, accepted-copy buffers, separate accepted
validation, ownership/tracker commit kernel, custom relationship ordering and
fold execution, relationship staged copies, device-only descriptor and stage
adaptations, obsolete inspection slogans, and their internal-structure tests.

`DescriptorExecutionPlan` and `StageExecutionPlan` remain Core host-side
scientific/compiler/checkpoint authorities and SequentialCPM inputs.

## Qualification

Ordinary tests and existing benchmarks must establish:

- every supported contextual operation and footprint lowering;
- first-use gather deduplication and strict stage-entry visibility;
- source-located rejection of unsupported or unbounded access;
- identical evaluator and prepared-plan types across compatible colors/banks;
- exact source-order Hamiltonian folding and all proposal roles;
- before/after overlays, periodic and closed boundaries, contact deduplication,
  and incident relationships;
- null, extinction, rejection, zero-temperature, and nonfinite behavior;
- mutual maxima rather than greedy matching;
- semantic RNG identity across queuing, replay, and checkpoint continuation;
- accepted ownership, tracker, auxiliary, clearing, relationship, history, and
  lifecycle-bound effects against SequentialCPM or independent oracles;
- relationship capacity, generation, duplicate, contradiction, and rollback
  behavior;
- failure suppressing bank and report publication;
- deterministic receipt failure, complete lease recovery, idempotent
  settlement, and one provider settlement boundary;
- no runtime compiler object, symbolic tree, unpacked relationship state,
  warm planning, packing, allocation, compilation, or host synchronization;
- identical law construction and packed KernelAbstractions execution on CPU
  and real Metal under the repository Julia version.

Tests asserting removed preparation types, order buffers, launch slogans, or
incidental workspace layout are replaced by scientific, transaction,
inspection, and CPU/GPU contracts.

The standalone CorePotts test-environment source-resolution issue is ordinary
repository tooling debt and is corrected separately. It must not introduce a
runtime dependency, compiler workaround, or special milestone script.
