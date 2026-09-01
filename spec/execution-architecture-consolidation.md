# Execution Architecture Consolidation

Date: 2026-08-15; execution-graph amendment 2026-08-16

Status: Owner-approved direct-breaking end state. The original consolidation
was implemented and accepted by the final multi-pass review committee; the
2026-08-16 execution-graph amendment below supersedes its bank-specific
preparation and K02/K03 sequencing choices and requires a fresh
post-implementation review.

## Authority and supersession

This specification defines the direct breaking consolidation of the
LocalWorksets execution architecture and the CorePotts-to-LocalWorksets
boundary. It is later and more specific than the implementation-family,
compatibility, and preservation clauses in the following records:

- [LocalWorksets V1 Normative Contract](localworksets-v1.md);
- [LocalWorksets Post-LW-R1 Roadmap](localworksets-post-lwr1-roadmap.md);
- [LW-5A representability inventory](../design/hardening/lw5a-representability-and-preservation.md);
- [LW-5C adoption matrix](../design/hardening/lw5c-adoption-matrix.md);
- [LW-5D promotion evidence](../design/hardening/lw5d-final-evidence.md);
- [IC-R0 internal-complexity review](../design/hardening/icr0-internal-complexity-review.md); and
- [post-CA simplification audit](../design/hardening/post-ca-full-simplification-audit.md).

Those records remain evidence for scientific meaning, direct-oracle behavior,
backend qualification, lifetime, failure, replay, and performance. They no
longer require preservation of:

- legacy resolved declarations or lowerings;
- separate direct, buffered, resolved, single-resolved, and conjunctive
  preparation/evidence lifecycles;
- candidate, promoted, claim-only, direct, or automatic checkerboard selectors;
- CorePotts method-world adapters around LocalWorksets public calls;
- old private checkpoint execution-profile identities; or
- direct production K02, K03, or K05 kernels after their replacement is the
  sole production execution graph.

This specification does not weaken any surviving scientific invariant or
expand any public backend claim. CPU and the already qualified Metal profile
remain the runtime qualification boundary until separately expanded.

## Decision

The implementation MUST be rewritten directly to have:

1. one public LocalWorksets lifecycle;
2. one internal typed phase-pipeline architecture;
3. one provider/completion lifecycle;
4. one production CorePotts checkerboard execution graph;
5. one CorePotts execution identity used by capability, checkpoint, replay,
   inspection, and settlement; and
6. direct/reference implementations retained only as independent test oracles
   where production no longer selects them;
7. one fused K02/K03 proposal operation and launch per color submission;
8. exactly one dynamic-storage proposal preparation and one dynamic-storage
   claim preparation shared by both state banks, with one cumulative tail event
   retained for each preparation; and
9. one backend-portable CorePotts K06 transaction path used by CPU and every
   qualified accelerator, without a host fallback.

The implementation MUST NOT add migration adapters, compatibility constructors,
dual execution toggles, fallback selectors, old-checkpoint decoders, or a new
migration test suite. Existing tests and benchmarks are to be rewritten around
the final architecture and remain the validation substrate.

The direct edit is allowed to change private types, private method signatures,
private inspection layouts, private checkpoint identities, LocalWorksets'
pre-1.0 exported `masked` spelling, and the legacy `resolved` constructor
profile. Observable scientific behavior and explicitly retained public
LocalWorksets meanings MUST remain.

## Motivation

The repository already has one coherent public lifecycle:

```text
localwork -> plan -> prepare -> run! -> WorkEvent -> wait / waitall
```

Execution-path proliferation occurs below `plan`. Several lowering families
independently implement the same responsibilities:

- central admission;
- topology validation, fingerprinting, preparation, and inspection;
- required binding and access derivation;
- workspace schema, allocation, validation, identity, and byte evidence;
- operation result validation;
- active-prefix validation;
- kernel preparation and launch accounting;
- provider/compiler and determinism evidence; and
- runtime inspection.

CorePotts then adds another wrapper lifecycle, selectable direct/candidate/
promoted profiles, another method-world firewall, repeated inspection-derived
profiles, parallel capability/checkpoint encodings, and profile-specific
settlement.

The problem is not that specialized kernels exist. Specialized kernels are
necessary. The problem is that every kernel schedule owns a parallel
architecture.

## Goals

The implementation MUST achieve all of the following:

- preserve one concise declarative authoring surface;
- preserve specialized direct, buffered, atomic, resolved, and conjunctive
  kernels where their semantic or performance laws differ;
- derive common facts once and consume them everywhere;
- make absent phases disappear through concrete Julia specialization;
- make CorePotts an ordinary, thin LocalWorksets consumer;
- eliminate production selection history;
- retain exact scientific failure, RNG, transaction, lifecycle, checkpoint,
  and settlement ownership in CorePotts;
- make future replacement of mechanical CorePotts work possible without adding
  another execution family; and
- materially reduce synchronized edit sites and production source size.

## Non-goals

This change MUST NOT:

- merge all kernels into one generic kernel;
- introduce a public scheduler, stream, command buffer, task graph, or pool;
- introduce a second LocalWorksets declaration lifecycle;
- introduce an opaque callback-based execution IR;
- transfer Hamiltonian folding, acceptance, RNG, clocks, transactions,
  lifecycle meaning, or checkpoint policy into LocalWorksets;
- force K04 acceptance-status semantics into LocalWorksets merely to obtain one
  literal `PreparedWork`;
- transfer K06 accepted-copy transaction meaning, K07 commit, K08 reporting,
  K09 bank publication, lifecycle commit, or host callbacks out of CorePotts;
- preserve the host-only K06 implementation or its CPU-only capability gate;
- claim CUDA, ROCm, multi-device, or cross-backend bitwise support; or
- use physical line count as a correctness gate.

## Normative ownership boundary

### CorePotts MUST own

- checkerboard color permutation and attempt ordering;
- semantic RNG streams, addresses, replica/repeat identity, and draw meaning;
- target/source proposal construction meaning;
- descriptor schedule and source-handle validation;
- canonical source-order Hamiltonian folding;
- constraint, nonfinite, zero-temperature, Metropolis, and extinction laws;
- the K04 scientific failure cut and `ProgramStatus` meaning;
- accepted-copy scientific preparation and publication;
- ownership, tracker, relationship, and lifecycle transaction meaning;
- state-bank selection and publication;
- MCS and lifecycle clocks;
- capability admission decisions and scientific evidence identity;
- checkpoint meaning and settled-boundary policy;
- failure translation into `LifecycleBackendFailure`; and
- final settlement, materialization, and receipt publication.

### LocalWorksets MUST own

- declaration validation for local work and output laws;
- topology host validation, fingerprinting, preparation, and device identity;
- binding schemas, access modes, representation checks, and alias rejection;
- workspace specification, construction, validation, and accounting;
- backend-qualified mechanical lowering;
- concrete kernel phase preparation and submission;
- provider ordering and cumulative completion;
- submission leases, task ownership, poison state, and mandatory tail drain;
- backend/provider/compiler execution facts; and
- declaration, plan, preparation, phase, memory, and completion inspection.

Executing a CorePotts-owned callable does not transfer ownership of its
scientific meaning to LocalWorksets.

## Public LocalWorksets lifecycle

The surviving public lifecycle is unchanged:

```text
LocalWork / sequence
    -> plan(work, topology; backend)
    -> prepare(workplan, storage; submission, workspace, lease_capacity)
    -> run!(prepared, values)
    -> WorkEvent
    -> wait / waitall
```

The following public concepts survive:

- `LocalWork`, `WorkPlan`, `PreparedWork`, and `WorkEvent`;
- `localwork`, `sequence`, `topology`, `plan`, `prepare`, `run!`, `waitall`;
- `workspace_requirements` and `allocate_workspace`;
- `identity_route`, `fixed_offset_route`, `bounded_read`, `GatheredValues`,
  `active_indices`, `value_slot`, and `storage_slot`;
- `independent`, `combined`, and generic `resolved` outputs;
- `deterministic` and `fast` combination laws; and
- `emit` and `candidate` operation results.

The following public compatibility surface is removed directly:

- `masked`;
- the `_MaskedEmission` result model;
- legacy `resolved(capacity=..., key_type=..., mask=...)`; and
- named operation declarations whose family is `:resolved_selection`.

Conditional resolved emission MUST use:

```julia
candidate(rank, value, condition)
```

Existing witnesses using `masked` MUST be rewritten to the generic candidate
form without removing their semantic assertions.

## Canonical internal architecture

### One lowered-work representation

Every declaration, including a flattened sequence, MUST lower to one
package-owned immutable value conceptually equivalent to:

```julia
struct _LoweredWork{M,B,W,P}
    mechanism::M
    bindings::B
    workspace::W
    phases::P
end
```

The exact field spelling MAY differ, but the following laws are mandatory:

- `WorkPlan.work` is the sole authority for the original operation, reads, and
  output declarations.
- `WorkPlan.topology` is the sole authority for canonical host topology.
- `_LoweredWork` stores only validated or canonical derived facts needed after
  planning.
- No lowering may duplicate the original operation, reads, outputs, or complete
  topology merely for family-specific convenience.
- `phases` is the sole concrete tuple of immutable phase-plan descriptors. Its
  element types completely determine the launch schedule before preparation.
- Mechanism values may retain compact, mechanism-specific validated policy
  needed to prepare those descriptors. They MUST NOT expose a second phase
  plan, binding schema, workspace schema, or topology owner.
- No phase list may use `Vector`, `AbstractPhase`, `Function`, `Any`, opaque
  callbacks, or runtime strategy symbols.

### One prepared-pipeline representation

Every lowering MUST prepare to one package-owned immutable pipeline
conceptually equivalent to:

```julia
struct _PreparedPipeline{P,T}
    phases::P
    topology::T
end
```

The exact storage MAY be nested when needed for inference, but:

- prepared kernel and topology references MUST be immutable;
- `PreparedWork` is the sole owner of the prepared workspace, provider lane,
  leases, submission counters, poison state, and operation-method identity;
- `_PreparedPipeline` MUST NOT duplicate the workspace or provider lane;
- only counters, leases, poison state, cached external-operation identity, and
  equivalent runtime state MAY be mutable;
- each phase MUST retain its concrete kernel and launch argument types;
- absent phases MUST not allocate storage or execute a runtime branch; and
- a phase throw after crossing the submission boundary MUST trigger the
  mandatory provider-tail drain described below before control returns.

### Typed phases

The phase vocabulary is private. It SHOULD consist of small concrete values
with ordinary multiple-dispatch methods. Expected roles include:

```text
ApplyDirect
ClearBuffered
ApplyBuffered
PublishCanonical
ApplyFastAtomic
ApplySingleResolved
PublishSingleResolved
ClearWinners
ClaimRanks
ClaimIdentities
PublishConjunctive
```

Names MAY change. Their laws may not.

`_execute_phases!` MUST recurse or map over a concrete tuple. It MUST NOT
perform runtime type tests over a type-erased collection.

## Execution strategies and laws

### Direct independent

Direct independent publication remains a specialization with:

- exactly one apply launch;
- no algorithmic record workspace;
- no clear or publish launch;
- exact fixed-route validation;
- full-coverage validation where requested; and
- partial coverage preserving destinations for false emissions.

It is a phase schedule, not a separate planning/preparation/evidence family.

### Fast combined

Fast combined execution retains:

- its explicitly relaxed determinism contract;
- centrally qualified atomic operations by backend, value type, operation, and
  address space;
- no accidental promotion to replay or cross-backend bitwise claims; and
- the exact output identity and empty behavior declared by the combination law.

### Deterministic combined

Deterministic combined execution retains:

- fixed record slots;
- canonical destination segments;
- canonical item/lane fold order;
- deterministic empty and publication behavior; and
- no backend-scheduling dependence in the canonical fold.

### Generic resolved

Generic resolved execution is the sole ordinary public resolved mechanism. It
retains:

- explicit rank type, total order, and bounds;
- explicit canonical semantic identity type and minimum tie-break;
- uniqueness of semantic identities per destination;
- explicit empty result;
- fixed maximum candidate lanes;
- conditional candidates through `candidate(..., condition)`; and
- canonical resolved publication.

The existing hard-coded value-type lists SHOULD be replaced by centrally
derived store/record capability queries where doing so removes duplicated
profile authority. Unsupported backend/type combinations MUST still reject at
planning or preparation before launch.

### Single-resolved specialization

Single-resolved is not an execution family. The specialized implementation MAY
remain only for the measured profile:

- one resolved port;
- maximum one candidate per item;
- minimum rank;
- complete active domain; and
- the currently justified bounded flattened-read shapes.

The specialized path MUST be selected by dispatch from the generic resolved
lowering and MUST share its declaration, topology, binding, workspace,
evidence, inspection, and completion authorities.

All nonmatching profiles MUST use the ordinary buffered resolved phases.
General fallback kernels and a second prepared-runtime shell in
`localworksets_single_resolved.jl` MUST be removed.

### Conjunctive resolution

Conjunctive resolution retains its exact semantics:

- an item may claim up to two dynamic positive destination keys;
- nonpositive keys are skipped exactly as currently defined;
- rank is maximum priority;
- equal rank resolves to the minimum canonical semantic identity;
- an item survives only if it wins every nonzero claimed key;
- zero-claim, selected, ineligible, and gated values preserve their current
  meanings; and
- publication updates item-layout disposition storage exactly once.

Conjunctive resolution MUST NOT be re-expressed as two independent ordinary
resolved ports. That would select each key independently and lose the all-wins
law.

The current four kernels MAY remain, but they MUST be emitted as concrete
phases under the common lowering, preparation, workspace, evidence, inspection,
and completion machinery. A conjunctive policy is a semantic specialization,
not another lifecycle.

## Common derived authorities

### Binding authority

One immutable binding-requirement tuple on `_LoweredWork` MUST be the sole
derived authority for:

- logical name;
- access mode;
- static versus submission storage;
- value or array representation;
- element type and dimensions;
- shape and strides;
- backend and device requirements;
- semantic role;
- component-record physical leaves; and
- inspection facts.

Required binding names, merged access, schema validation, alias validation, and
inspection MUST be derived from this tuple. Output bindings and closed
scientific profiles MUST carry their exact element type and shape at planning.
Generic read bindings whose declaration intentionally omits type and shape MUST
be explicitly represented as `fixed_at_prepare`; preparation freezes their
concrete schema before any launch. Family-specific methods MUST NOT
hand-maintain parallel type, shape, or access lists. A specialized physical
layout proof, such as checking every leaf of a qualified `StructArray`, MAY
remain family-aware, but it consumes the central representation/component
requirement and does not constitute a second logical binding schema.

### Workspace authority

One `_WorkspaceLeaf` specification MUST derive:

- allocation;
- caller-owned construction;
- validation;
- concrete type, shape, and stride requirements;
- backend/device placement;
- identity and alias checks;
- semantic role;
- byte accounting; and
- inspection.

### Topology authority

One canonical topology-payload description MUST derive:

- host-residency validation;
- structural fingerprinting;
- device copy;
- prepared topology arrays;
- backend/device/type/shape/stride validation;
- aliases;
- transfer bytes; and
- inspection.

### Phase evidence

Mechanical schedule means phase membership, order, count, and identity; those
facts MUST derive from `_LoweredWork.phases`. Preparation maps that tuple by
dispatch to a same-length tuple of concrete launch phases; it MUST NOT select a
later family or create a second schedule. A `WorkPlan.work` output law selects
which descriptor in that schedule publishes each port, and the selected
descriptor type derives post-launch visibility. Family evidence MUST NOT carry
a second publication schedule.

The tuple MUST NOT duplicate semantic state merely to make all evidence appear
phase-owned. Active-domain capacity and selector identity derive once from
`WorkPlan.work`; the per-submission active prefix derives through the one
central bounds check from the submitted scalar value. Determinism derives once
from the mechanism's scientific law conjoined with the qualified backend and
compiler facts. Family evidence MAY define these semantic laws, but MUST NOT
hard-code phase names, phase order, launch counts, publication phase, or
failure visibility. Workspace and topology evidence MUST derive from their
authoritative specifications.

Inspection MAY organize these facts for readers, but it MUST NOT construct a
second evidence graph.

## Sequence semantics

`sequence(a, b, ...)` remains a public combinator that supplies provider program
order without an intermediate host wait.

Internally, sequence SHOULD be represented by a distinct immutable sequence
value or immediately flattened to a tuple of stage plans. It SHOULD NOT fake a
single `LocalWork` by storing tuples in every `LocalWork` field.

Nested sequences MUST flatten at planning. Each stage retains its own:

- item domain;
- active selector;
- operation;
- reads and outputs;
- topology requirements; and
- phase schedule.

The production checkerboard proposal does not use `sequence`: K02 proposal
construction and K03 Hamiltonian evaluation are one item-local operation with
two outputs and one launch. K04 remains the Core-owned boundary between that
proposal preparation and the separate K05 claim preparation. A literal
K02--K08 LocalWorksets sequence is not the target architecture. If broader
cross-domain sequences are implemented for unrelated consumers, they MUST
preserve concrete phase domains and MUST NOT normalize all phases to an
inflated maximum domain.

### Ordered in-place updates

The architecture MAY later admit a repeated output name in one sequence as an
explicit ordered in-place update. Removing the unique-output check alone is
forbidden.

A repeated output is valid only when:

1. the later stage explicitly reads the prior logical binding;
2. the later stage writes the exact same logical and physical binding;
3. element type, shape, capacity, backend, device, and representation match;
4. merged access is `:readwrite`;
5. reads resolve to the nearest preceding writer;
6. the later output law explicitly preserves unselected values; and
7. ordinary distinct writable aliases remain rejected.

Inspection MUST report the ordered writer history and final declaration.

This feature is not required by the production checkerboard graph. K03 and K05
therefore MUST NOT be forced into one sequence merely to create one literal
`PreparedWork`; doing so would require either a second disposition array or a
new state-threading law without deleting scientific machinery.

## Method ownership and world-age policy

The current private-helper method firewall is removed.

The final implementation MUST retain exactly the safeguards that protect
scientific preparation or asynchronous lifetime:

1. one central plan-time admission boundary proving that external dispatch did
   not authorize a lowering or backend capability;
2. the external scientific operation's applicable method identity captured at
   preparation and rechecked when the Julia world changes;
3. immutable prepared kernel/topology/provider identities;
4. task ownership and submission serialization;
5. topology, representation, backend, device, shape, stride, access, and alias
   validation;
6. lease capacity and retention;
7. provider poison state; and
8. unconditional, nonrejecting synchronization of an already-submitted tail.

The final implementation MUST remove:

- method-owner checks for private helpers;
- cached method objects for binding, submission, execution, inspection, and
  other package-owned internals;
- generic trusted-callback registries;
- repeated exact `invoke` calls used only to bypass possible piracy of private
  methods;
- CorePotts' `_LocalWorksetsTrustedAdapter`; and
- CorePotts hostile-entry tests whose only contract is interception resistance
  for another package's public entrypoint.

Private underscored Julia methods are not a security boundary. A package MUST
still fail closed against unqualified declarations and backend claims, but it
does not promise to execute correctly after malicious replacement of its exact
public methods in the same Julia process.

## CorePotts production execution graph

### One execution type

CorePotts MUST have one production checkerboard execution type. Its conceptual
shape is:

```julia
mutable struct CheckerboardExecution{W,P,C,S,G,E,I,R}
    workspace::W
    proposal::P
    claims::C
    science_banks::S
    open_gates::G
    last_events::E
    identity::I
    capability_report::R
end
```

The exact fields MAY differ, but it MUST NOT carry type parameters selecting a
direct versus LocalWorksets proposal or claim implementation. `proposal` and
`claims` are the two `PreparedWork` values themselves, not segment wrappers or
tuples of bank-specific preparations. `last_events` contains exactly the latest
cumulative proposal event and latest cumulative claim event.

The two state-bank science projections and two Core open-gate projections have
one exact type and backend representation per pair. The proposal submission
schema MUST declare its science binding through
`storage_slot(template_science; access=:read)`. The claim submission schema MUST
declare its open gate through `storage_slot(template_gate; access=:read)`.
Each `run!` supplies the projection for the selected destination bank; the
submission lease retains that dynamic storage through completion.

Each preparation owns the full checked capacity
`queue_mcs_capacity * attempts_per_site * color_count`. Bank-halved capacities,
`cld(queue_mcs_capacity, 2)`, duplicated bank preparations, duplicated event
tuples, and separate proposal/claim bank selectors are forbidden. One
Core-owned bank selector validates the destination state against the two
authoritative banks and selects both dynamic projections.

`PreparedWork.workplan` already keeps the declaration and plan alive;
CorePotts MUST NOT wrap and repeat them in `_PreparedCoreLocalWorkPhase`, a
proposal segment type, or a claim segment type.

The proposal submission consists exactly of dynamic `science` plus bounded
`color::Int32`, `attempt_round::Int32`, `active_count::Int32`, and `mcs::Int64`
values. The claim submission consists exactly of dynamic `execution_open` plus
bounded `active_count::Int32`. All proposal/claim output arrays remain static
prepared storage shared by the two banks. Dynamic reads are read-only and MUST
pass the same representation, backend, device, shape, stride, alias, method,
lease, and poison checks as any other `storage_slot` submission.

### Fused K02/K03 proposal

K02 and K03 MUST be one direct LocalWorksets operation and one backend launch
per color submission. For each active item it MUST:

1. construct the exact proposal record from the selected state bank, semantic
   RNG address, checkerboard color, and attempt round;
2. evaluate extinction, descriptor contributions, Hamiltonian terms, drives,
   modifiers, constraints, and acceptance in canonical source order using that
   record; and
3. return both the proposal record and disposition as independent
   partial-coverage outputs over the same identity route.

The declaration has one fixed item domain `1:maximum_batch`, one
`active_prefix(:active_count)`, the dynamic `science` read, and exactly the
`proposal` and `dispositions` outputs. Its topology is one ordinary direct
topology with one logical identity route and destination count
`maximum_batch` for each output; it is not sequence topology. A closed Core gate
emits neither output. Every active open item publishes exactly one proposal and
one disposition, including null and constraint dispositions.

The proposal record remains a no-copy `StructArray` projection over the
authoritative target, source, old-owner, new-owner, priority, and semantic-ID
arrays because K04, K05, K06, and K07 consume those fields. K03 MAY consume the
register value within the fused operation, but publication of every proposal
field remains required and independently tested. There is no scientific
visibility or failure cut between K02 and K03; K04 is the first such cut.

The production graph MUST NOT retain `_CheckerboardProposalInputOperation`, a
separate proposal-evaluation operation, `LocalWorksets.sequence` for K02/K03,
or a two-stage proposal inspection identity. The fused operation SHOULD remain
a thin composition of separately reviewable pure proposal-construction and
disposition helpers so source-order science and oracle independence remain
clear.

### Exact per-color order

The production graph MUST preserve:

```text
K02/K03 proposal + Hamiltonian/acceptance          one LocalWorksets launch
K04  canonical acceptance-status reduction       CorePotts scientific boundary
K05  old/new-owner conjunctive claims             one LocalWorksets preparation
K06a accepted-copy evaluation/transaction staging CorePotts, when present
K07  ownership/tracker commit                     CorePotts
K06b accepted-copy publication                    CorePotts, when present
K08  report/counter update                        CorePotts
```

K04 MUST remain between K03 and K05. It chooses the smallest semantic identity
among nonfinite or zero-temperature failures, publishes the exact sticky
`ProgramStatus`, and closes the gate observed by K05. Reordering, omitting, or
folding this status into provider poison is a scientific correctness failure.

### K04 disposition

The amended end state MUST retain K04 as the existing CorePotts-owned scientific
kernel between the two LocalWorksets preparations. One production execution
graph is the requirement; one literal `PreparedWork` is not.

K04 MAY move into LocalWorksets later only through a separately demonstrated
general mechanism, preferably a single-destination deterministic reduction
that:

- reduces `(semantic_identity, failure_code)` in canonical order;
- selects the minimum failing semantic identity;
- publishes the exact sticky `ProgramStatus`;
- preserves the current launch and synchronization behavior; and
- has at least one unrelated non-CPM consumer or a clear reduction in generic
  LocalWorksets machinery.

A CorePotts-specific kernel callback embedded in LocalWorksets is forbidden.

### K06 and K07 disposition

K07 remains the compact CorePotts ownership/tracker/descriptor-state commit
kernel. Runtime-keyed independent publication is a legitimate general
LocalWorksets law, but the current K07 transaction spans heterogeneous site,
owner, tracker-group, moment, and descriptor-state representations. It MUST NOT
be replaced by an arbitrary-effect output wrapper or a larger Core-specific
adapter merely to place K07 inside one `PreparedWork`.

K06 transaction meaning likewise remains CorePotts-owned, but its physical
implementation MUST be backend-portable and shared by CPU and qualified GPU
backends. The final path MUST:

1. retain backend-resident candidate-indexed `StageEvaluation` storage;
2. emit relationship-create requests to fixed descriptor-by-candidate slots in
   concrete backend-compatible storage rather than a host `Vector{Union}` or a
   mutable host append counter;
3. evaluate every enabled accepted-copy descriptor against the pre-K07 state;
4. deterministically validate and prepare relationship transactions in their
   canonical request order: malformed/nonfinite evaluator output and storage-
   integrity defects publish through fixed-size Core `ProgramStatus` storage,
   while `RelationshipFailureFilter` continues to count and omit ordinary
   scientific admission rejections such as self edges, inactive or stale
   endpoints, contradictory generations, maximum degree, and exhausted edge
   capacity;
5. run K07 only while the Core program/lifecycle gate remains open; and
6. publish saved site assignments and staged relationship state only after K07
   in the same order and visibility contract as the sequential reference.

The same KernelAbstractions kernels and Core scientific helpers MUST execute on
CPU and qualified accelerators. Host candidate loops, host relationship
transaction publication, scalar indexing of device storage, implicit
device-to-host transfers, and backend fallback are forbidden. A provider
failure remains a provider failure. An expected, policy-filterable scientific
transaction rejection remains a counted omission, while an evaluator or
integrity failure remains a Core status; neither case may poison LocalWorksets.

### Operation restrictions

Before the direct production path is removed, the sole execution graph MUST
support every currently supported checkerboard configuration.

In particular:

- `attempts_per_site > 1` MUST use the existing Core color/attempt loop and
  submission values rather than select another proposal implementation;
- accepted-copy stages MUST remain around K07 and use the same backend-portable
  Core path without excluding the LocalWorksets proposal or claim
  preparations;
- inert and active lifecycle plans MUST coexist with the same proposal/claim
  implementation when their science views are representable;
- after-MCS behavior MUST NOT select a different K02/K03/K05 implementation;
  any after-MCS profile not yet device-qualified remains an explicit capability
  rejection rather than a host fallback; and
- unsupported backend conjunctions MUST reject explicitly rather than fall back
  to host or direct execution.

If a supported configuration exposes a missing representation, that
representation MUST be added to the one final execution vocabulary before the
old production implementation is deleted. The selector hierarchy MUST NOT be
retained as a workaround.

### GPU qualification boundary

Completion of this amendment requires the complete K02--K08 checkerboard path,
including accepted-copy site assignment and relationship creation, to execute
without host fallback on CPU and the already qualified real-Metal environment.
The existing accepted-copy adaptation and non-CPU execution rejections are
superseded and MUST be deleted only after the backend-resident K06 path above is
present.

This does not silently broaden the public GPU claim. In particular:

- an after-MCS effect that has no device lowering remains an explicit
  capability rejection, and the release MUST NOT describe the complete model
  surface as GPU-compatible while such a retained public effect remains
  device-ineligible;
- three-dimensional checkerboard code may be dimension-generic, but a qualified
  3D GPU claim requires removal of the current 2D-only backend evidence gate and
  a new real-device 3D evidence row; and
- CUDA, ROCm, another Metal device family, wider scalar profiles, or external
  code identities require their own capability conjunctions.

Capability checks MUST describe the exact unsupported conjunction. They MUST
not select the sequential engine, execute host transaction loops against device
arrays, copy an MCS to the host, or advertise adaptation as execution evidence.

## CorePotts boundary deletion

The following file MUST be deleted:

```text
lib/CorePotts/src/execution/localworksets_adapter.jl
```

Delete its include and all of:

- `_PreparedCoreLocalWorkPhase`;
- `_PlannedCoreLocalWorkPhase`;
- `_localworksets_owned_call`;
- `_validate_core_localwork_provenance`;
- `_plan_core_localwork`;
- `_prepare_core_localwork`;
- `_plan_core_localwork_sequence`;
- `_run_core_localwork_phase!`; and
- `_inspect_core_localwork_phase`.

CorePotts MUST call `LocalWorksets.sequence`, `topology`, `plan`, `prepare`,
`run!`, `wait`, `waitall`, and `inspect` through ordinary public Julia calls.

Delete from checkerboard execution:

- `_LocalWorksetsTrustedAdapter` and every prepare/validate/run/wait wrapper;
- abstract direct/LocalWorksets claim strategy types;
- abstract direct/LocalWorksets proposal strategy types;
- candidate and promoted qualification types;
- `_LocalWorksetsExecutionProfile` and parallel qualification records;
- candidate, replay-candidate, promoted, direct, and automatic selection entry
  points;
- `_CheckerboardProposalSegment`, `_CheckerboardClaimSegment`, their preparation
  tuples, bank ownership tuple, bank-specific event tuples, and proposal/claim
  bank-selection helpers;
- the separate K02 input operation, K03 sequence operation, K02/K03 sequence,
  and their superseded source files or includes once retained proposal science
  is placed in one coherent owner; and
- profile- or bank-specific capacity, completion, inspection, and settlement
  dispatch.

These are direct deletions in the same breaking edit. No adapter, old-field
facade, alternate inspection path, feature flag, or checkpoint translation may
remain after their callers are rewritten.

## Direct oracle disposition

After the sole production graph passes the existing evidence, direct K02, K03,
and K05 implementations MUST leave production source and remain available only
as independent test/reference oracles.

Move or recreate in test support:

- `_checkerboard_candidates_kernel!`;
- `_checkerboard_evaluate_kernel!`;
- `_checkerboard_claim_priorities_kernel!`;
- `_checkerboard_claim_identities_kernel!`; and
- `_checkerboard_select_kernel!`.

The test oracle MUST remain independent of the LocalWorksets lowering. It MAY
use CorePotts private scientific functions, but it MUST NOT invoke the
production LocalWorksets phases it is intended to check.

Fusion requires a two-leg proposal witness. First, a manually constructed
proposal must equal the record published to the authoritative `StructArray`.
Second, the independent disposition oracle must consume that published record
and equal the fused disposition. This prevents a storage-publication defect
from being hidden because fused K03 consumed the correct register value. The
oracle MUST NOT call the production proposal-construction, scheduled-fold, or
disposition helper.

Production kernels that remain CorePotts-owned include:

- K01 MCS/report clearing when the selected K08 representation still requires
  it;
- K04 acceptance-status publication;
- backend-portable K06 accepted-copy staging/publication;
- K07 commit;
- K08 reporting;
- K09 state-bank and lifecycle mechanics;
- lifecycle execution; and
- bank publication.

After direct K05 removal, delete direct-only claim workspace and clearing state,
including cell maximum-priority and minimum-identity arrays where no surviving
consumer exists. After direct K03 removal, delete direct-only contribution
scratch where no accepted-copy or diagnostic consumer remains. Every deletion
MUST be justified by a complete reference search, not by its historical K
label alone.

## Core scientific views

CorePotts MUST retain device-compatible scientific views, but duplicated
delegation layers SHOULD be collapsed.

The target is one concrete program view and one concrete runtime/state view
containing exactly the fields required for:

- proposal construction;
- descriptor evaluation;
- parameters and temperature;
- ownership and kinds;
- trackers and relationships;
- extinction policy;
- lifecycle/open status; and
- semantic RNG context.

`_CheckerboardScienceRead` MAY remain while LocalWorksets requires an array-like
binding. It is a valid one-element device projection, not execution scaffolding.

The proposal record SHOULD be a direct no-copy `StructArray` projection over
the authoritative arrays. Intermediate record types that are immediately
deconstructed into another record SHOULD be removed when the direct projection
is equally concrete and GPU-compatible.

## Capability, checkpoint, and replay

CorePotts MUST define one immutable checkerboard execution identity containing:

- schema/version;
- Core scientific mechanism ABI;
- descriptor and capability fingerprint;
- checkerboard topology/RNG identity;
- fused LocalWorksets proposal and conjunctive claim lowering/phase identities;
- provider and provider-compiler identity;
- queue capacity/policy; and
- checkpoint protocol version.

Scientific capability admission precedes provider preparation: the one
authoritative `ProgramCapabilityReport` MUST be admitted exactly once, and its
key fingerprint MUST be embedded in the execution identity without minting a
post-admission replacement report or allowing the queue graph to authorize
itself. The completed execution identity then MUST drive:

- checkpoint execution identity;
- restore mismatch rejection;
- execution inspection;
- settlement event extraction; and
- replay qualification.

The identity MUST be derived once from the two shared plans and their two
preparations. Dynamic state-bank storage is a submission value constrained by
the preparation schema; it does not create a second lowering identity and MUST
not require re-parsing duplicated inspection trees.

The checkpoint execution schema MUST be bumped. Old private candidate,
claim-only, direct, or promoted execution checkpoints MUST reject directly. No
translation or compatibility decoder is permitted.

The amended identity MUST also use a new scientific ABI and mechanism identity
that names the fused proposal and dynamic two-preparation graph. It MUST NOT
reuse the prior K02/K03-sequence identity. Queue policy reports one MCS
capacity, one proposal-submission count per MCS, one claim-submission count per
MCS, and cumulative grouped completion; it reports no bank capacity.

Execution inspection MUST expose one proposal preparation, one claim
preparation, their lowering/launch facts, and
`completion_events=(proposal=..., claims=...)`. It MUST NOT reconstruct bank
preparation tuples, separate K02/K03 stage plans, or historical segment types
for presentation compatibility.

Prepared kernels, provider lanes, leases, and device workspace MUST NOT be
serialized. Restore reconstructs preparations from the compiled program,
restored state banks, execution identity, and current qualified environment.

## Queueing, completion, and settlement

CorePotts owns the atomic whole-MCS preflight. Before the first launch of an
MCS, it MUST select one authorized destination bank and prove that each of the
two LocalWorksets preparations has capacity for every color/attempt submission
required by that MCS. Preflight is independent of which bank is selected
because each preparation owns the full queue capacity.

LocalWorksets MUST expose one compact, allocation-free `submission_capacity`
query rather than require CorePotts to reproduce submitted/drained/lease
arithmetic. That query reports mechanical capacity only; CorePotts computes the
number and placement of submissions in an MCS.

LocalWorksets has one grouped completion operation:

```julia
waitall(events...; release = true)
```

Ordinary `release=true` validates one owner/provider event group, snapshots the
submitted prefix of every participating preparation, synchronizes the current
cumulative provider tail exactly once, and releases those prefixes only after
successful synchronization. `release=false` is the retaining-fence policy of
that same operation: it MUST perform a fresh synchronization of the current
provider tail even when every supplied receipt is older than an already-drained
prefix, and MUST leave `submitted`, `drained`, and every lease unchanged. There
is no second public synchronization API and no selective-event completion
claim.

Both policies MUST share one event-group validator and one provider-tail drain.
On synchronization failure, the shared provider scope and every participating
preparation are poisoned while counters and leases remain unchanged. An
ordinary `waitall` after a successful retaining fence MUST synchronize again
before release; the early fence is visibility, not final settlement.

Poison is sticky admission state. Ordinary `wait` and both `waitall` policies
MUST reject a poisoned preparation or provider scope before idempotence checks,
before attempting another synchronization, and before releasing any lease.
The nonrejecting provider-tail primitive is reserved exclusively for mandatory
cleanup after a submission crossed its launch boundary; public settlement MUST
enter through the healthy-lane validator. A later successful backend call can
never erase or mask an earlier provider failure.

The final settlement path MUST be one CorePotts method. It MUST:

1. collect exactly the latest proposal event and latest claim event;
2. validate that their provider scopes admit grouped cumulative settlement;
3. perform the minimum truthful provider synchronization;
4. guarantee completion of later CorePotts K04/K06/K07/K08/publication kernels
   ordered in the same provider scope;
5. retain all leases on synchronization failure;
6. translate failure to the exact submitted/drained MCS range;
7. release completed prefixes only after successful synchronization; and
8. publish committed/drained MCS state only after the complete graph is known
   complete.

The normal device-only path MUST use one ordinary grouped `waitall`, producing
one provider synchronization and one Core settlement. It MUST NOT append a raw
backend synchronization that bypasses LocalWorksets poison and lease handling.

The host-after-MCS path MUST:

1. complete the same whole-MCS capacity and scientific preflight as the normal
   path, including accepted-copy representation/backend qualification and
   workgroup-size validity;
2. set `runtime.settled = false` immediately before its first state-copy
   launch;
3. enqueue the ordinary fused-K02/K03-through-K08 device graph;
4. use `waitall(...; release=false)` to make that graph visible while retaining
   all LocalWorksets leases and submitted prefixes;
5. execute the host callback and enqueue any resulting publication; and
6. finish through the same ordinary grouped `waitall` as normal settlement.

Consequently, normal execution records one synchronization and one settlement;
successful host-after-MCS execution records two synchronizations and one
settlement. A host preflight rejection leaves the runtime settled and submits
nothing. A callback or final synchronization failure leaves it unsettled and
retains the old coherent boundary until explicit successful settlement.
Initial or repeated settlement with no undrained receipt performs no provider
synchronization and MUST NOT increment the synchronization counter.

## Failure semantics

The implementation MUST distinguish:

- scientific proposal failure, published by K04 into CorePotts program status;
- LocalWorksets declaration/preparation rejection before launch;
- provider execution failure after a possible launch;
- provider synchronization failure; and
- CorePotts transaction or lifecycle failure.

A K04 scientific nonfinite or zero-temperature failure MUST NOT poison
LocalWorksets. A LocalWorksets provider failure MUST NOT be rewritten as a
scientific proposal result.

`run!` MUST reserve the lease and advance `submitted` before entering the first
possibly launching phase. A throw after that boundary MUST invoke a
nonrejecting mandatory drain primitive that ignores existing poison state but
still enforces owner-task scope:

- if the provider-tail drain succeeds, advance `drained` through that serial,
  release its lease, poison the shared scope, and rethrow the original execution
  error;
- if the drain also fails, keep `drained` unchanged and every lease retained,
  poison the shared scope, and throw a `CompositeException` containing the
  execution and drain failures.

This accounting is conservative about whether the throwing phase appended a
kernel while still proving that no completed lease is stranded after a
successful mandatory drain.

## File-level implementation map

### LocalWorksets

`lib/LocalWorksets/src/model.jl`

- retain independent, combined, generic resolved, emit, and candidate;
- move the generic resolved constructor here or to one adjacent declaration
  file;
- remove `_MaskedEmission` and `masked`;
- replace the fake sequence-as-LocalWork representation if doing so reduces
  special cases; and
- retain concise single-output authoring.

`lib/LocalWorksets/src/planning.jl`

- own the sole central admission boundary;
- construct `_LoweredWork` and flattened sequence plans;
- derive phase evidence from concrete phase tuples;
- remove the repeated family protocol dispatch; and
- retain topology freshness and backend qualification.

`lib/LocalWorksets/src/preparation.jl`

- prepare every lowering through one pipeline path;
- use one binding, workspace, topology, operation-method, and provider
  validation flow;
- simplify `PreparedWork` by grouping immutable preparation facts and mutable
  submission state; and
- remove internal method-cache registries.

`lib/LocalWorksets/src/execution.jl`

- execute one concrete phase tuple;
- retain owner-task, lease, poison, and cumulative completion laws;
- retain a guaranteed nonrejecting drain path;
- remove internal method-world dispatch armor; and
- keep `run!`, `wait`, and `waitall` as the sole public runtime lifecycle.

`lib/LocalWorksets/src/execution/localworksets_generic.jl` and
`lib/LocalWorksets/src/execution/localworksets_combined.jl`

- consolidate route validation, binding derivation, active counts, topology
  preparation, evidence, and inspection;
- retain direct and buffered kernel implementations as phases; and
- remove duplicate copies of work, operation, reads, outputs, and topology.

`lib/LocalWorksets/src/execution/localworksets_single_resolved.jl`

- retain only the narrow measured specialization;
- emit ordinary typed phases; and
- delete the general alternate implementation.

`lib/LocalWorksets/src/execution/localworksets_resolved.jl` and
`lib/LocalWorksets/src/execution/localworksets_resolved_evidence.jl`

- move the generic resolved declaration/admission pieces;
- delete the legacy path; and
- delete both files if no coherent generic support remains in them.

`lib/LocalWorksets/src/execution/localworksets_conjunctive.jl`

- retain exact declaration/policy validation and specialized kernels;
- emit common pipeline phases; and
- delete its parallel binding/workspace/preparation/evidence/inspection shell.

`lib/LocalWorksets/src/execution/localworksets_combined_workspace.jl` and
`lib/LocalWorksets/src/execution/localworksets_combined_evidence.jl`

- fold common machinery into pipeline support;
- retain only genuinely specialized record construction or evidence laws; and
- delete the files if their remaining contents no longer form coherent owners.

`lib/LocalWorksets/src/execution/fixed_lane_support.jl` and
`lib/LocalWorksets/src/execution/record_storage_support.jl`

- retain as cross-cutting representation support;
- do not promote them to execution families; and
- rename only if the resulting ownership becomes clearer.

### CorePotts

`lib/CorePotts/src/program/v1.jl`

- remove the `localworksets_adapter.jl` include; and
- include only the final checkerboard LocalWorksets operation/view/builder
  owners.

`lib/CorePotts/src/execution/checkerboard_program.jl`

- define the one production execution graph;
- own exactly one proposal preparation, one claim preparation, one bank
  selector, and their two cumulative tail events;
- bind bank science/open-gate projections through dynamic storage submissions;
- retain K04, backend-portable K06, K07, K08, and Core transaction ordering;
- delete strategy types and trusted adapters;
- remove direct-only workspace after oracle extraction; and
- make execution/capacity/completion dispatch independent of historical
  qualification modes.

`lib/CorePotts/src/execution/checkerboard_proposal.jl`

- replace the K02/K03 sequence with one fused proposal operation, one direct
  work plan, one dynamic-storage preparation, direct submission, and compact
  inspection;
- remove candidate/promoted qualification state, proposal-segment state, and
  bank-specific preparation/event state; and
- rename or merge the file with proposal record/generation owners when that
  produces one coherent `checkerboard_proposal.jl` rather than retaining
  historical stage boundaries in filenames.

`lib/CorePotts/src/execution/checkerboard_kernels.jl`

- retain small Core-owned K04, K07, K08, and report-clear kernels where still
  required;
- add the backend-portable K06 evaluation, deterministic relationship
  transaction, and publication kernels; and
- contain no host/device selector, fallback, or scalar device access.

`lib/CorePotts/src/execution/sequential_program.jl`

- delete all execution selectors and fallback logic;
- construct the one checkerboard execution directly;
- use one capability/checkpoint identity; and
- retain sequential-reference and host transaction responsibilities unrelated
  to this consolidation.

`lib/CorePotts/src/execution/program_settlement.jl`

- settle exactly the proposal and claim cumulative tails through one method;
  and
- preserve exact failure translation, materialization, and receipt publication.

`lib/CorePotts/src/program/runtime.jl`

- restore only the new checkpoint execution schema; and
- reject obsolete private mechanism identities without translation.

## Direct implementation order

The work MUST occur on one breaking architectural branch. The following order
is an edit dependency order, not a compatibility migration:

1. Introduce the canonical lowered-work and prepared-pipeline types.
2. Make binding, workspace, topology, phase evidence, and inspection derive
   from single authorities.
3. Route direct independent and buffered combined/generic resolved through the
   common pipeline.
4. Delete legacy resolved and rewrite its existing witnesses with generic
   candidates.
5. Narrow the single-resolved specialization.
6. Move conjunctive resolution under common pipeline phases without changing
   its four-kernel semantics.
7. Remove the private-helper method firewall while retaining the narrow
   scientific-operation and lifetime safeguards.
8. Replace the K02/K03 sequence with the fused two-output proposal operation and
   delete the superseded operations, topology, inspection, and source ownership
   immediately.
9. Make proposal science and the K05 open gate dynamic storage submissions;
   build one full-capacity proposal preparation and one full-capacity claim
   preparation, then delete bank-specific preparations and selectors.
10. Replace proposal/claim segment wrappers with the one mutable checkerboard
    execution graph, one bank selector, and two cumulative tail events; rewrite
    preflight, inspection, identity, checkpoint, and settlement against those
    direct fields and delete old field paths immediately.
11. Implement backend-resident K06 evaluation, deterministic relationship
    preparation, status, and publication through the same CPU/GPU kernels;
    delete host K06 loops and accepted-copy CPU-only gates immediately.
12. Delete Core adapters, selectors, candidate/promoted profiles, fallback,
    parallel capability/checkpoint records, and profile-specific settlement.
13. Move direct K02/K03/K05 implementations to independent test support and
    delete direct-only workspace and clearing machinery with no surviving
    consumer.
14. Bump the execution and checkpoint ABI once; rewrite existing tests,
    conformance witnesses, inspection expectations, and benchmarks for the
    final architecture. Restore accepts only the new identity.
15. Run the existing focused, complete, backend, GPU, and benchmark evidence in
    the order defined below.

No step may introduce a temporary public compatibility API. Temporary private
code used inside the branch MUST be gone from the final diff.

## Validation plan

No new large migration suite is required. Existing authoritative evidence MUST
be updated to exercise the final path.

### Static and package-quality evidence

- package parse/load;
- Aqua and package-owned ambiguity checks;
- ExplicitImports;
- authoritative public API inventory reflecting removal of `masked`;
- active include/test inventory;
- no obsolete selector, qualification, adapter, legacy resolved, or direct
  production references;
- inference checks for representative direct, buffered, resolved, conjunctive,
  sequence, fused proposal, dynamic bank submission, and checkerboard phase
  tuples; and
- formatting and `git diff --check`.

### LocalWorksets semantic evidence

- direct independent full and partial coverage;
- heterogeneous outputs and fixed lanes;
- deterministic combined canonical fold;
- fast combined relaxed contract;
- generic resolved minimum/maximum ranks, endpoint bounds, equal-rank ties,
  canonical identity, empty behavior, and conditional candidates;
- the narrow single-resolved specialization against generic resolved;
- conjunctive two-key, one-key, zero-key, ineligible, gate, rank, identity, and
  preservation behavior;
- ordered sequence visibility without intermediate waits;
- topology freshness and prepared topology identity;
- static and dynamic binding representation and alias rejection;
- caller and automatic workspace construction;
- task ownership, queue capacity, lease exhaustion, poison, older-event wait,
  `waitall`, and failed-wait retention; and
- scientific operation method change after preparation.

### Cross-domain evidence

The existing LBM, deterministic/fast springs, matrix-free FEM, z-buffer, and
other external LocalWorksets witnesses MUST remain. Legacy z-buffer syntax is
rewritten to generic resolved rather than deleted.

### CorePotts scientific evidence

- direct-oracle parity for K02 candidate fields and RNG identity;
- exact K03 descriptor source order and Hamiltonian fold using a nonempty,
  multi-source, floating-point-order-sensitive descriptor plan;
- the fused two-leg oracle: manual proposal versus stored proposal, then an
  independent disposition calculated from that stored proposal versus the
  fused disposition;
- constraint, energy, accepted, null, nonfinite, and zero-temperature
  dispositions;
- exact K04 earliest semantic failure identity and sticky status;
- K05 old/new-owner conjunctive winner behavior;
- attempts-per-site greater than one;
- accepted-copy precommit evaluation and postcommit publication ordering,
  including site assignment, relationship creation, transaction rejection, and
  fixed Core status translation;
- no-, inert-, and active-lifecycle configurations;
- host after-MCS behavior where supported;
- bank alternation, queued MCS continuation, and whole-MCS preflight;
- failure cut, poison distinction, and no partial scientific publication;
- capability, checkpoint, restore, replay, and mismatch rejection; and
- final settlement and receipt publication.

### Backend and performance evidence

- complete CPU LocalWorksets and CorePotts suites;
- complete PottsToolkit and integration suites;
- the qualified real-Metal semantic/lifetime/failure suite, extended to fused
  proposal dynamic-bank submissions and accepted-copy site/relationship
  effects with scalar device access disabled;
- exactly one proposal launch and the retained four K05 launches per color,
  together with truthful K04/K06/K07/K08 launch accounting;
- alternating-bank queued execution at full capacity through the same two
  preparations, including dynamic-storage lifetime, retaining fences, final
  release, and provider failure;
- zero intermediate host waits inside a color or MCS;
- one truthful final settlement synchronization;
- zero warm workspace growth and no hidden topology transfer;
- existing inference and allocation bounds, plus real-device compilation/cache
  evidence that fusion does not introduce a material compile-size or warm-cache
  regression; and
- the existing paired CPU and Metal checkerboard performance protocols.

Benchmarks validate the final implementation. They do not decide whether old
private architecture remains available.

## Acceptance criteria

The consolidation passes only when all of the following are true:

1. one LocalWorksets planning/preparation/execution/evidence lifecycle remains;
2. direct independent still compiles to one launch and zero record workspace;
3. legacy resolved and `masked` are absent from production and public API;
4. single-resolved is only a specialization of generic resolved;
5. conjunctive semantics retain specialized kernels but no parallel lifecycle;
6. common binding, workspace, topology, phase, and inspection facts each have
   one authority;
7. private-helper method-world armor and the Core trusted adapter are absent;
8. operation identity, backend/device/alias checks, task ownership, leases,
   poisoning, and mandatory drain remain, including exact release-on-success
   and retain-on-drain-failure accounting;
9. one production checkerboard execution graph supports every retained public
   checkerboard configuration;
10. that graph owns exactly one dynamic-storage proposal preparation, one
    dynamic-storage claim preparation, and their two latest cumulative events;
11. both preparations serve both banks, own full checked queue capacity, and no
    segment wrapper, bank preparation tuple, or bank-specific selector remains;
12. K02/K03 is one two-output launch whose stored proposal and disposition pass
    the two-leg independent oracle;
13. K04 remains exactly between fused K02/K03 and K05 as a Core scientific
    status kernel;
14. K06 preserves precommit evaluation and postcommit publication through one
    backend-resident CPU/GPU path, with accepted-copy host loops and CPU-only
    gates absent;
15. K07 remains a compact Core transaction kernel rather than an arbitrary-
    effect LocalWorksets adapter;
16. direct K02/K03/K05 production selection is impossible;
17. one admitted capability report fingerprints one execution identity, and
    that identity drives checkpoint, replay, inspection, and settlement;
18. old private checkpoint mechanisms reject directly;
19. retaining and releasing `waitall` policies share one validator and provider
    drain, and Core has no raw final synchronization bypass;
20. host-after-MCS execution becomes unsettled before its first launch and uses
    exactly one retaining visibility fence followed by ordinary final
    settlement;
21. independent scalar oracles cover K02/K03 proposal science and the complete
    conjunctive all-wins K05 law without calling the production phase methods;
22. the existing CPU, Metal, scientific, lifetime, allocation, inference, and
    performance evidence passes; and
23. the final architecture has materially fewer production-path owners and
    synchronized edit sites, contains no unreachable retired machinery, and
    reports its source-size ledger with any growth explained.

Line reduction is a required review metric, not a correctness gate. A hard net
line-count threshold would reward deleting independent science or failure
proofs, compressing formatting, or merging unrelated responsibilities. A
change passes this criterion only when its retained lines have clear owners and
no parallel lifecycle remains; it fails regardless of net size if it preserves
obsolete selectors, adapters, duplicate authorities, or unreachable production
machinery.

The original implementation-candidate ledger against its pre-consolidation
`HEAD`, counting new production files, was approximately:

- LocalWorksets: 266 fewer production lines;
- CorePotts: 265 additional production lines, including explicit K02/K03
  LocalWorksets declarations, bank identity, atomic preflight, retained-fence
  failure accounting, and the independent graph boundary; and
- combined: 1 fewer production line.

These figures are historical evidence, not the acceptance ledger for the
2026-08-16 amendment. The amended implementation MUST report a fresh production
census that includes backend-portable K06 and separately identifies deletions
from proposal fusion, dynamic preparations, segment removal, and settlement
simplification.

The focused proposal-boundary compactness pass removed 308 lines, about 43% of
the first consolidated bridge, by deleting view wrappers, nested bridge state,
no-op runtimes, selector helpers, duplicate validation, and redundant identity
construction. The remaining growth is accepted only with the committee's
finding that it implements retained functionality or explicit scientific and
lifetime contracts rather than another execution path.

### 2026-08-16 implementation census

The amended implementation has four production-path owners at the former
CorePotts/LocalWorksets boundary: the outer checkerboard executor, one fused
proposal unit, one narrow science-view unit, and one accepted-copy transaction
unit. The proposal and claim segment wrappers, their bank tuples and selectors,
and the separate proposal-generation/proposal-stage source units are absent.
The active amendment-owned units contain:

- 309 lines in `checkerboard_proposal.jl`;
- 69 lines in `localworksets_checkerboard_view.jl`; and
- 903 lines in `checkerboard_accepted_copy.jl`, including the complete bounded
  relationship transaction law and CPU/GPU kernels.

The cumulative working-tree production census against repository `HEAD`, which
also includes the preceding LocalWorksets mechanical-law expansion, is:

- CorePotts: 1,186 tracked additions and 1,418 tracked deletions, plus 1,281
  lines in the three new amendment-owned units, for a net `+1,049` lines;
- LocalWorksets: 3,049 tracked additions and 4,063 tracked deletions, plus 2,082
  lines in the four new common pipeline/law units, for a net `+1,068` lines;
  and
- combined CorePotts/LocalWorksets production source: net `+2,117` lines.

That cumulative net is not presented as line reduction: it includes the new
fixed-lane, keyed, record-storage, common-pipeline, and backend-resident K06
capabilities. The meaningful simplification is the deletion of parallel
execution owners and synchronized edit sites. The proposal/claim runtime now
has two `PreparedWork` values and two cumulative events, independent of bank
count, with no compatibility execution path. Review MUST reject the result if
any of the deleted owners remains reachable even if the net line count falls.

The implementation evidence run for this amendment includes the complete
CorePotts program-v1 scientific/lifetime/checkpoint suite and the real-Metal
12-MCS fused-graph CPU/device parity and cache-reuse witness with scalar device
access disabled. The Metal accepted-copy evidence covers site assignment,
successful relationship creation, deliberately noncanonical multi-request
input order, policy-filtered rejection, unequal color sizes, and a nonfinite
payload or endpoint translated into an unpoisoned Core evaluator status. It
also proves finite evaluator payload conversion into the relationship schema's
scalar type before fixed-scratch assignment. Relationship
activity, endpoints, generations, payload, degree, and incident-edge indexes,
plus auxiliary-state banks, are compared structurally against CPU. No
performance benchmark was rerun for this amendment, per owner direction; the
existing benchmark suite remains the release-performance gate.

## Explicit rejection list

The implementation MUST reject the following approaches:

- one universal kernel;
- a type-erased phase vector;
- closures or `Function` fields as internal launch nodes;
- a second normalized IR that coexists with the old family lowerings;
- compatibility wrappers around legacy resolved or `masked`;
- preserving candidate/promoted/direct selection for caution;
- retaining the K02/K03 sequence or two bank-bound preparations per mechanism;
- retaining proposal/claim segment wrappers or four bank-specific event tails;
- treating K04 scientific failure as provider poison;
- running K05 before K04;
- forcing K04--K08 into one literal `PreparedWork` merely for visual uniformity;
- replacing K07 with a custom LocalWorksets output wrapper that performs
  arbitrary Core tracker/descriptor mutations;
- relaxing all writable alias rules to permit repeated dispositions;
- a CorePotts-specific kernel callback extension in LocalWorksets;
- serializing `PreparedWork` or device workspace;
- selective-event claims not supported by the provider;
- host accepted-copy loops, scalar device indexing, or hidden host fallback;
- inflated maximum-domain execution to force unrelated phases into one launch
  model;
- retaining direct production kernels solely because tests refer to them; and
- deleting independent reference-oracle coverage merely to reduce lines.

## Follow-on replacement opportunities

After this specification is implemented, the following become credible
separate candidates because they can reuse the same phase pipeline:

- K04 through a general single-destination deterministic reduction;
- fixed-topology tracker accumulation through combined outputs;
- proposal-local statistics and report reductions;
- lifecycle request conflict arbitration through generalized resolution;
- fixed-topology relationship/contact work;
- local accepted-copy preprocessing while Core retains transaction authority;
  and
- local ownership/tracker delta calculation before Core publication.

Runtime-keyed independent publication is a legitimate future LocalWorksets law
for bounded permutations, unique-slot migration, and matching-based graph work.
It is admitted only as the orthogonal combination of runtime address source and
independent conflict semantics, with deterministic prepublication key-domain
and uniqueness validation. It does not authorize K07 replacement. K07 becomes
eligible only when the already independently justified law represents its
heterogeneous site/owner/tracker/descriptor outputs without an arbitrary-effect
callback and a complete source census proves that the Core adapter deletes more
machinery than it adds.

The following remain CorePotts responsibilities unless a later architecture
decision explicitly changes ownership:

- dynamic state-bank publication;
- lifecycle transaction commit;
- checkpoint/state materialization;
- host callbacks;
- MCS clock advancement;
- program settlement and failure translation; and
- scientific capability qualification.

Future adoption is accepted only when it deletes more CorePotts mechanical
machinery than the adapter it introduces and does not add another LocalWorksets
execution lifecycle.

## Committee disposition

### Original consolidation review

The multi-pass architecture and final implementation reviews approved:

- the typed phase-pipeline architecture;
- direct deletion of legacy resolved and `masked`;
- narrowing single-resolved to a measured specialization;
- moving conjunctive kernels under the common lifecycle;
- deletion of the Core adapter and broad method-world firewall;
- one production checkerboard execution;
- one capability/checkpoint/settlement identity; and
- one direct breaking implementation validated through existing evidence.

The original final committee reported P0=0, P1=0, and P2=0 after remediation.
Its read-only acceptance covered the sole typed plan and prepared pipeline,
workspace/binding/topology authorities, sticky poison and mandatory drain,
retaining/final settlement, the then-current K02--K08 graph and identity,
GPU-safe descriptor scheduling, atomic preflight, independent K02/K03/K05
oracles, checkpoint rejection, documentation consistency, active-tree stale
references, and the production-size ledger. Per owner direction, the final
committee did not rerun tests or benchmarks.

That P0/P1/P2 result remains evidence for the common LocalWorksets pipeline and
scientific contracts. It is not acceptance evidence for the superseding fused
proposal, dynamic preparations, two-event settlement, or backend-portable K06.

### 2026-08-16 execution-graph amendment

The amendment review approved:

- fusing K02/K03 because there is no scientific cut between them, subject to
  the two-leg oracle and real-device compiler-size evidence;
- one dynamic proposal preparation and one dynamic claim preparation across
  both banks;
- deletion of proposal/claim segment wrappers and settlement reduction to two
  cumulative events;
- retention of Core K04, K07, K08, lifecycle, and publication ownership; and
- replacement of host-only K06 mechanics by one Core-owned backend-portable
  transaction path.

It rejected a literal K02--K08 `PreparedWork`, K04 through the current two-launch
singleton-resolved lowering, and K07 through a Core-specific exclusive-scatter
adapter. Those designs add state-threading, heterogeneous transaction, launch,
and adapter machinery without deleting more Core code than they introduce.

The original and amended committees both reject a naive K02 -> K03 -> K05 merge
because it omits K04. The normative end state instead retains K04 between the
fused proposal preparation and the conjunctive claim preparation.

The fresh post-implementation committee completed three independent read-only
passes over the final amended source and evidence: Julian architecture,
scientific semantics/adversarial failure behavior, and GPU/backend execution.
After remediation of endpoint conversion, request provenance, GPU structural
admission, capability-direction wording, and expanded Metal evidence, all three
reviewers returned PASS with P0=0, P1=0, and P2=0. The amendment is therefore
implemented and accepted within the explicitly qualified backend/scope limits
of this specification.
