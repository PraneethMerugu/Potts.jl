# Symbolic Potts V1 Compiler Construction Contract

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: implementation-grade through the cleared G5 surface and completed G5-L1 lifecycle-language
boundary; G5-L2 may begin, while G5-L3/R2/G6/proof-model work remains unauthorized

## Authority

This contract records CCI-001 through CCI-023 from the accepted
[compiler-consolidation owner interview](../design/audits/symbolic-potts-v1-compiler-consolidation-owner-interview.md).
It freezes the remaining compiler-construction decisions required by the
[Architecture Redirection Contract](symbolic-potts-v1-architecture-redirection.md).
It also incorporates the owner's accepted
[quick confidence-test research](../design/audits/symbolic-potts-v1-quick-confidence-test-research.md)
and [execution-control audit](../design/audits/symbolic-potts-v1-execution-control-audit.md).
It also records LCI-R1-01 through LCI-R5-07 from the accepted
[lifecycle-language owner interview](../design/audits/symbolic-potts-v1-lifecycle-language-owner-interview.md).
CCV1-027 received fresh independent G5-L0 clearance in the
[lifecycle-language rereview](../design/audits/symbolic-potts-v1-lifecycle-language-g5-l0-rereview.md).

For compiler construction, descriptor execution, state/workspace layout, spatial planning,
relationship transactions, backend qualification, and autonomous implementation order, authority
is:

1. this contract;
2. the [Architecture Redirection Contract](symbolic-potts-v1-architecture-redirection.md);
3. the [Autonomous Consolidation Contract](symbolic-potts-v1-consolidation.md);
4. [Symbolic Potts V1](symbolic-potts-v1.md);
5. compatible scientific specifications and accepted decisions; and
6. historical implementation or design evidence.

This contract supersedes lower authority only where it explicitly tightens those implementation
areas. Accepted product syntax, scientific semantics, stochastic meaning, units, lifecycle,
SciML/ModelingToolkit/ProcessBigraphs boundaries, clean-break requirements, and phase exclusions
survive unless this contract explicitly resolves an ambiguity.

The words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** have the meanings defined
in [the specification index](README.md).

## Governing compiler invariant

The compiler has two deliberately different optimization boundaries:

```text
PottsSystem + Symbolics + typed Potts statements
    │
    ▼
FrozenSourceGraph
    │
    ▼
NormalizedTermGraph                 host-only, indexed, non-specializing data
    │
    ▼
AnalyzedTermIR
    │
    ▼
DescriptorCandidates
    │
    ▼
DescriptorGroups + layouts         repeated instances are data
    │
    ▼
ExecutionPlan
    │
    ▼
CompiledPottsProgram               concrete, typed, backend-adaptable execution
```

The host compiler MUST NOT encode complete model topology or every statement occurrence in Julia
types. The executable MUST NOT interpret a host graph dynamically. Host analysis is data-oriented;
device execution is concrete and typed.

CorePotts knows how to execute typed CPM programs. It does not know which biological mechanisms
exist.

## CCV1-001 — Frozen source graph and indexed host IR

Completion MUST freeze a qualified source graph containing:

- unique qualified identities;
- hierarchy, namespace, and source ordering;
- statement, equation, variable, parameter, relation, state, observation, protocol, and external
  IO references;
- source/provenance chains;
- minimal reachable frozen schema/callable closure; and
- links needed for diagnostics, inspection, and symbolic indexing.

Completion MUST NOT select an engine, backend, scalar type, device, layout, RNG seed, initial
state, or solve interval.

The package-level literal V1 operation inventory is separate documentation and audit data. A
completed model stores only reachable symbolic operations, actually required compiler-synthesized
operations, and used external operations. The closure freezes complete schemas and selected
callables; unused operations MUST NOT scale per-model graph size. Analysis and lowering MUST NOT
consult the live registry.

Compilation MUST lower the frozen source graph into a private indexed `NormalizedTermGraph` or an
equivalent private type. The graph MUST store model structure as host data rather than recursive
whole-model type parameters.

Every expression node MUST have or reference:

- a stable compiler-local node identity;
- canonical operation identity and schema version;
- ordered operand identities;
- literal, parameter, variable, proposal-context, state, relation, observation, or stochastic
  payload kind;
- canonical structural key;
- qualified source/provenance identity; and
- slots for required analysis facts.

Analysis facts MUST be stored in explicit node/record-indexed tables or an equivalently
non-type-exploding representation. Host compiler passes MUST use function barriers and MUST NOT
specialize on the concrete type topology of a complete `PottsSystem`.

The graph is private lowered compiler data. It is not a public authoring algebra, does not replace
Symbolics at the completed-system boundary, and is not a stable downstream-construction API.

## CCV1-002 — Order-aware normalization

Symbolics remains the sole canonical public scalar and array expression tree through construction
and completion. The private host graph begins execution lowering.

Normalization MAY:

- qualify and resolve symbolic references;
- canonicalize literals, parameter references, identities, and registered operation names;
- represent source-level associative syntax as ordered n-ary nodes;
- intern repeated pure subexpressions when identity, draws, and stage snapshots are unaffected;
- perform exact constant folding; and
- apply a rewrite proven valid for the selected numerical and replay policies.

Normalization MUST NOT:

- reorder floating-point operands solely because an operation is mathematically commutative;
- reassociate a reduction whose order contributes to a replay claim;
- merge, duplicate, eliminate, or reorder semantic stochastic draws;
- move a read across a snapshot or stage boundary;
- treat stateful, partial, or effectful operations as ordinary pure algebra;
- make source traversal order accidentally semantic; or
- define canonical meaning through unbounded or nondeterministic rewriting.

Every structural rewrite MUST preserve source traceability. Structural choices that can change
execution or replay MUST enter the completed or executable fingerprint as appropriate.

Canonical fingerprints MUST encode every structural type fact completely. For a concrete
parameterized Julia type this includes its defining module, type name, and recursively encoded type
parameters. Two payload, handle, evaluator, descriptor, or policy types that can produce different
executable structure MUST NOT collide because their outer type names match.

## CCV1-003 — Complete analyzed term IR

The compiler MUST compute explicit facts for every relevant expression node and scientific record:

- result type and shape;
- dimensions, units, and reference-unit conversion;
- structural or runtime parameter role;
- purity and totality;
- state/resource reads and writes;
- spatial and relationship locality;
- bounded affected region or deferred-stage requirement;
- effect class and emission bound;
- scientific category;
- stage, ordering, and dependency;
- semantic RNG sites;
- state, workspace, adaptation, and checkpoint participation;
- engine/backend admission or rejection with reason; and
- originating source diagnostic chain.

Analyses MUST be explicit deterministic passes. Mutually dependent facts MAY use a bounded monotone
fixpoint. The implementation MUST detect nonconvergence or unresolved facts and reject compilation
with qualified diagnostics.

Built-in and registered schemas provide typed transfer rules. A schema result MUST be validated
against the expression, declared resources, stage, effect bound, engine, and backend. A user or
extension assertion MUST NOT override failed purity, totality, units, boundedness, footprint,
stochastic, or device-legality analysis.

Engine and backend admission are compositional expression facts. A node is admitted only when its
own versioned transfer and every operand node are admitted. A rejected descendant MUST propagate a
qualified rejection reason to every enclosing expression and descriptor; an admitted root
operation MUST NOT hide an unsupported nested operation.

Safe independent diagnostic failures SHOULD be aggregated.

## CCV1-004 — Stable semantic extension surface, private compiler machinery

The qualified public extension surface MUST include only what downstream semantic extensions need:

- Potts statement and symbolic-operation construction;
- versioned registration schemas;
- qualified identity, provenance, diagnostic, and read-only inspection records;
- typed state, workspace, resource, footprint, stage, effect, RNG, adaptation, and checkpoint
  schemas;
- inert descriptor-payload and declared-resource construction hooks; and
- CorePotts's qualified runtime descriptor protocol.

Concrete host graph nodes, mutable graph builders, analysis caches, fact-table storage, grouping
keys, schedule builders, kernel builders, and compiler pass types MUST remain private.

Read-only inspection MAY expose normalized and analyzed meaning without promising the concrete
storage or pass implementation.

## CCV1-005 — MetaTheory disposition

MetaTheory MUST NOT be a V1 dependency or weak dependency of PottsToolkit or CorePotts.

V1 normalization MUST use explicit deterministic rules with documented semantics and bounded
complexity. TermInterface compatibility MAY be implemented where independently useful.

A later research environment MAY evaluate MetaTheory or another equality-saturation optimizer only
for pure, total, unit-compatible, RNG-free, stage-local expressions. Adoption requires:

- a bounded saturation policy;
- an explicitly sound rewrite theory;
- a device-aware extraction cost model;
- numerical and property qualification;
- cross-backend lowering qualification; and
- a material measured compile-time, generated-code, or runtime benefit.

An optional optimizer MUST NOT own semantic analysis, stochastic identity, resource inference,
scheduling, transactions, checkpoints, or device execution. The baseline compiler MUST remain
complete without it.

## CCV1-006 — Open concrete descriptor protocol

CorePotts MUST define qualified generic operations equivalent to:

- state requirements;
- workspace requirements;
- resource access and bounded footprint;
- stage participation and dependencies;
- engine/backend support;
- proposal evaluation;
- bounded effect or request emission;
- stage application;
- adaptation;
- logical checkpoint encode/reconstruct; and
- inspection metadata.

Exact private names MAY differ. All central executors and engines MUST depend only on these generic
contracts.

CorePotts MUST NOT contain:

- a closed union of all scientific descriptor families;
- a mechanism enum;
- a biological `isa` ladder;
- a mechanism-name switch; or
- a callback fallback for unknown descriptors.

A mechanism-specific callable tag, evaluator operation identity, program field, capability bit, or
descriptor-role subtype inside CorePotts is a mechanism branch even when dispatch replaces an
explicit `if` statement. Moving named science from an engine loop into
`ResourceOperation{:mechanism_name}` or an equivalent CorePotts tag does not satisfy this clause.
CorePotts operation vocabulary MUST describe structural execution primitives only: proposal views,
resource reads, bounded traversal, storage/workspace access, footprints, requests, transactions,
adaptation, and canonical folding. PottsToolkit or an external module owns scientific callables
composed over those primitives.

This boundary is judged by replaceability, not naming. If an external package cannot express a
new mechanism with the same shape of reads, traversal, contribution, rejection, or request using
the public primitive vocabulary, the compiler is missing a primitive or the engine has absorbed
scientific policy. Adding that missing primitive is valid only when its contract is mechanism-
neutral and independently reusable; adding a renamed operation for the mechanism is not.

CorePotts MUST own the universal descriptor and evaluation method for symbolically defined
proposal terms. Downstream extensions MAY contribute only versioned operations, inert isbits
occurrence/payload metadata, resource declarations, and qualified inspection metadata to that
descriptor. They MUST NOT replace or ignore the compiler-supplied evaluator.

Every registered statement contract that may contribute descriptor metadata MUST declare one
concrete isbits `descriptor_payload_type` for that schema version. Every occurrence payload MUST
have exactly that type. The declared type is a structural schema fact; payload field values are
occurrence data. A payload constructor MUST NOT derive a new concrete type from a statement ID,
resource name, runtime parameter value, declaration position, or other occurrence identity.

Registered provenance MUST originate only from successful lowering against the supplied frozen
registry. Public statement constructors MUST reject reserved internal provenance option names.
Completion MUST authenticate every internal origin against the exact registry definition for its
schema/version, including serialization identity, lowering identity, and descriptor payload type,
before the origin can affect qualified records, fingerprints, or compilation. Presence of an
internal-looking metadata key is never authority by itself.

Non-proposal stages MAY admit downstream scientific descriptors conforming to the same protocol
only when their accepted stage specification requires distinct execution semantics. Such a
descriptor MUST NOT create an alternate symbolic proposal-evaluator path.

For CCV1-027 lifecycle, this allowance cannot admit a structural verb, imperative callback, or
alternate trigger/policy evaluator. External lifecycle triggers, placement, binary partition, and
state transforms MUST enter through CCV1-009's frozen operation-schema/callable route and lower into
the compiler-owned lifecycle transaction descriptors.

## CCV1-007 — Descriptor grouping and specialization boundary

The compiler MUST group descriptor occurrences by structural execution facts. A group key MAY
include:

- concrete descriptor/evaluator strategy;
- lowered expression structure;
- stage and resource-access policy;
- state/workspace layout class;
- request/effect strategy; and
- selected backend-kernel strategy.

Numerical coefficients, runtime parameter indices, kind identities, targets, statement IDs,
relation handles, and other occurrence values MUST remain fields in homogeneous
backend-compatible instance buffers. They MUST NOT become type parameters merely because their
values differ.

The concrete type of inert extension metadata MUST be frozen by its registered schema version.
The compiler MUST reject a payload whose concrete type differs from that declaration before
descriptor grouping, even when both the declared and observed types are otherwise isbits and
contain no executable value.

State/workspace bank type identities MUST derive canonically from storage representation. Resource
names, declaration count, first encounter, and semantically irrelevant declaration order MUST NOT
change bank types or kernel specialization.

The representation marker in a handle type MUST be a function of that representation alone. A
model-relative ordinal is insufficient even when its input representations are sorted, because
adding or removing a different representation could renumber an existing handle type. Physical
bank ordinals and resource slots MUST remain value-level fields. Runtime storage lookup MAY
specialize on the representation marker, but adding another bank MUST NOT change an existing
representation's evaluator, descriptor, or kernel-strategy type.

Let `N` be descriptor occurrences and `G` distinct structural execution strategies. The executable
MAY use a heterogeneous tuple or equivalent concrete structure of `G` groups. It MUST NOT use a
heterogeneous tuple of `N` occurrences when occurrences share a group strategy.

Inspection MUST report:

- `N` and `G`;
- instance count per group;
- evaluator node count per expression group;
- expected kernel specializations; and
- structural facts responsible for every group split.

Increasing repeated instances at fixed `G` MUST NOT deepen a program type or produce one evaluator
specialization per occurrence.

## CCV1-008 — Qualification-selected static evaluator

The static expression evaluator semantics and operation protocol are fixed. The exact private Julia
representation MUST be selected through a bounded implementation experiment before scientific
mechanisms are rebuilt.

The experiment MUST compare:

1. recursive typed trees grouped by structural shape;
2. balanced or bounded n-ary typed trees; and
3. a compile-time-unrolled static instruction or SSA representation.

All candidates MUST use the same host semantic fixture, occurrence data, evaluation context,
semantic RNG addresses, and ordered test vectors. If operation execution itself is under
comparison, every representation MUST receive semantically identical concrete operations.

The experiment MUST vary at least:

- expression node count;
- expression depth;
- occurrence count at fixed evaluator shape; and
- distinct evaluator-group count.

It MUST measure:

- host construction and compilation growth;
- method-instance or equivalent specialization growth;
- generated host/device code size;
- inference quality;
- CPU and available-GPU kernel compilation;
- registers/local memory where available;
- first launch and warmed execution; and
- numerical/stochastic equivalence under the declared policy.

The selected candidate MUST:

- contain no runtime opcode dispatch;
- contain no device allocation, exception, closure, Symbolics value, or abstract dispatch;
- reuse one evaluator specialization for repeated instances sharing structure;
- avoid pathological compiler recursion with increasing expression depth;
- admit registered device-valid operations without a central operation switch; and
- compile for every backend required by its claimed support level.

Selection order is:

1. discard any candidate failing a mandatory semantic/device gate;
2. prefer lower asymptotic specialization and generated-code growth;
3. prefer lower compilation latency;
4. prefer lower representative warm runtime without a material regression elsewhere; and
5. prefer the simplest maintainable private implementation.

The selection and evidence MUST be recorded in a short design decision before mechanism lowering
continues. RuntimeGeneratedFunctions and Symbolics `build_function` are host-codegen controls only
unless separately proven device-valid across the claimed backends.

## CCV1-009 — Versioned operation schemas and concrete callables

Every ordinary expression operation MUST define:

- stable semantic identity and schema version;
- arity and operand constraints;
- type, shape, and unit transfer;
- purity and totality;
- resource and locality transfer;
- backend capability;
- canonical serialization; and
- concrete device-valid callable lowering.

Ordinary scalar mathematics MUST lower to Julia's named singleton functions. Flattened associative
arithmetic MUST use the compiler-owned bounded `OrderedFold` callable so source-order
floating-point semantics remain explicit. Context, resource, and downstream CPM operations MUST
lower to concrete isbits callable structs. A registered operation MUST supply its frozen host
schema and concrete callable implementation before completion.

An executable MUST NOT contain an operation symbol switch, dictionary, registry lookup, callback,
closure, or unresolved operation identity. CorePotts MUST NOT reimplement the meaning of ordinary
Julia arithmetic. Unsupported backend operations MUST fail compilation without host fallback.

The versioned operation schema and `operation_callable` lowering MUST be the sole supported route
by which executable callable behavior enters a symbolic evaluator. Descriptor payload hooks are
inert metadata: they MUST reject functions, evaluator/expression objects, contextual operations,
and any attempt to replace proposal evaluation. Recursive concrete-boundary checks are
defense-in-depth and MUST NOT be treated as callable or backend certification.

## CCV1-010 — Group kernel baseline and measured fusion

The baseline execution boundary is one descriptor group or a small compiler-owned family of
compatible groups.

KernelAbstractions kernels MUST specialize on concrete group strategy and execution context.
Repeated instances MUST execute through the homogeneous group buffer.

Adjacent groups MAY be fused only when:

- snapshots and stage ordering are preserved;
- RNG addressing is unchanged;
- resource and transaction semantics are preserved;
- numerical/reduction order satisfies the declared replay policy;
- diagnostic traceability remains available; and
- measurement shows a material launch, transfer, or memory benefit without unacceptable
  compilation, register, occupancy, or code-size growth.

The unfused plan remains the inspectable semantic reference. A backend-specific measured kernel MAY
replace a portable kernel only while preserving the same descriptor/stage contract.

The compiler MUST NOT construct one giant model-shaped kernel type or launch one kernel per
individual statement occurrence by default.

## CCV1-011 — Device totality and validation boundary

Production device evaluators and kernels MUST NOT throw.

Structural invalidity, unsupported operations, units, capacities, parameter roles, and backend
incompatibility MUST fail before launch. Runtime parameter constraints that can be checked before
launch MUST be validated during `init`, `remake`, or settled parameter update.

Expected proposal invalidity MUST produce typed rejection, null-attempt, request disposition, or
another specified value. A genuinely data-dependent stage failure MUST use a preallocated status
buffer with stable error identity and MUST be surfaced after synchronization without partial stage
publication.

A qualified debug kernel policy MAY add bounds or invariant instrumentation. Production semantics
MUST NOT depend on device exceptions.

## CCV1-012 — Universal state and typed auxiliary blocks

CorePotts directly owns only universal CPM state:

- lattice ownership and topology;
- entity identity, kind, generation, and liveness required by ownership semantics;
- settled MCS, engine batch, and proposal position;
- semantic RNG continuation;
- universal proposal outcome accounting; and
- universal validity/capacity data required by both engines.

Scientific state MUST use typed auxiliary blocks. Every block schema MUST define:

- stable semantic identity and version;
- entity domain/index space;
- element type, shape, capacity, and layout constraints;
- initialization and validation;
- persistence and lifecycle;
- permitted read/write policies;
- backend adaptation;
- settled-state export;
- logical checkpoint encode/reconstruct; and
- inspection.

The compiler MUST resolve semantic state identities to compact typed handles or concrete block
views. Device code MUST NOT perform state lookup by dictionary or symbol.

Program state, checkpointing, adaptation, validation, and inspection MUST recurse over the general
block structure. Adding scientific state MUST NOT add a central program/runtime/checkpoint field.

## CCV1-013 — Declared reusable workspace

Every descriptor group and engine stage MUST declare workspace before executable construction.

A workspace schema MUST specify:

- concrete element/container type;
- structural dimensions/capacity;
- initialization/reset policy;
- stage lifetime;
- access/concurrency policy;
- backend adaptation; and
- whether safe sharing is permitted.

Runtime workspaces MUST be allocated during executable construction or `init`. Warming proposal,
resolve, commit, and declared stage execution MUST NOT allocate host heap workspace.

The compiler MAY alias workspaces only when lifetime and access analysis prove non-overlap.
Otherwise, workspaces remain distinct and inspectable.

Workspaces MUST NOT enter logical checkpoint or scientific saved state. V1 MUST NOT introduce a
general device allocator, arbitrary byte arena, or user-visible scratch dictionary.

## CCV1-014 — Canonical spatial relations

The canonical finite translation-invariant constructors are:

- `VonNeumann(r)`: every nonzero integer offset `δ` where `sum(abs, δ) ≤ r`;
- `Moore(r)`: every nonzero integer offset `δ` where `maximum(abs, δ) ≤ r`;
- `AxialRays(r)`: exactly one nonzero coordinate with absolute value in `1:r`;
- `DistanceShells(k)`: offsets in the first `k` distinct positive squared Euclidean distances on
  the integer lattice; and
- `ExplicitOffsets(offsets)`: one validated finite offset set.

Relations MUST:

- exclude zero unless a separate operation explicitly admits self-access;
- remove duplicates and canonicalize lexicographically;
- validate dimensionality and bounded representation;
- keep boundary/topology handling separate from the offset set; and
- preserve exact constructor meaning in inspection and fingerprints.

Historical axial-ray behavior for `VonNeumann(r > 1)` is `AxialRays(r)`. It MUST NOT survive under
the Von Neumann name.

Models MAY bind different named relations for proposal, contact, surface/boundary, connectivity,
state/query, field stencil/gradient, and relationship contact/creation roles.

The checkerboard conflict relation MUST be compiler-derived from analyzed read/write footprints. It
is not a user scientific relation and MUST NOT be hard-coded as Moore.

## CCV1-015 — Closed footprint algebra

All locality required for engine admission MUST lower into a closed footprint algebra containing:

- finite spatial offsets relative to source, target, or a named anchor;
- union and Minkowski sum of finite spatial footprints;
- owner/entity access induced by spatial observations;
- bounded incident-relationship access;
- exact entity-index access;
- exclusive-owner access;
- global deterministic reduction;
- ordered bounded deferred emission; and
- host equation/process boundary.

Built-in operations MUST derive footprints compositionally. Registered transfer rules MUST produce
values in this algebra and MUST be validated against state, stage, effects, and bounds.

An unbounded or data-dependent proposal footprint MUST lower to an admitted deferred stage with
bounded emission or be rejected by checkerboard.

Shared reads MUST NOT become exclusive conflicts. Exclusive writes, exact commutative integer
effects, deterministic reductions, exclusive-owner effects, and deferred requests MUST remain
distinct policies.

## CCV1-016 — Deterministic realized-domain coloring

The V1 checkerboard baseline MUST derive a finite conflict displacement set from every spatially
exclusive proposal footprint.

For the selected finite lattice and boundary topology, planning MUST:

1. visit sites in canonical linear-index order;
2. derive already-colored conflicts from the displacement set without a general graph edge list;
3. assign the smallest available color deterministically;
4. verify every conflict edge has different endpoint colors;
5. group sites by color in backend-compatible buffers; and
6. report and fingerprint the algorithm identity, displacement set, site order, and color count.

Baseline planning SHOULD be `O(V × D)` time and `O(V)` storage for `V` sites and `D` conflict
displacements. It occurs per executable structural configuration, not per MCS.

A formulaic coloring MAY replace the baseline only when proven correct for the exact shape,
periodicity, and displacement set. Periodic seams MUST be included in the proof.

Residual exclusive conflicts MUST use the canonical
`(priority_draw, semantic_proposal_id)` winner rule for every claimed resource. Device completion
order MUST NOT select a winner.

## CCV1-017 — Incremental tracker protocol

A derived quantity used in a proposal hot path MUST use a typed tracker or another proven local
representation. It MUST NOT scan unrelated whole-lattice or whole-relationship state per proposal.

A tracker MUST declare:

- source state and relation;
- maintained domain/storage;
- initialization/rebuild algorithm;
- local proposal delta/update;
- snapshot/commit visibility;
- concurrency policy;
- independent recomputation oracle for tests;
- adaptation and checkpoint/reconstruction policy; and
- inspection/cost facts.

Volume, boundary/surface, moments, centroids, elongation tensors, field summaries, history indices,
and relationship incident indices MAY use this general protocol. They MUST NOT become named central
executor caches.

Tracker updates MAY fuse with commit after semantic proof and measurement. The unfused reference
update MUST remain independently testable.

## CCV1-018 — Relationship state and transactions

Relationship state MUST be an auxiliary typed block containing:

- structural capacity and active-slot state;
- normalized endpoint identities and generations;
- schema-declared typed payload columns;
- bounded incident indices;
- maximum-degree and endpoint-kind policy;
- deterministic free-slot state; and
- lifecycle/checkpoint metadata.

Proposal evaluation reads an immutable batch snapshot. Incident access MUST make ordinary local
relationship energy/constraints proportional to endpoint degree rather than total edge count.

Relationship mutation MUST use preallocated typed requests containing:

- request schema/type;
- originating stage and emitter;
- canonical request identity and bounded emission position;
- normalized endpoints/generations;
- payload/update;
- admission/disposition policy.

Every `RelationshipCommit` MUST:

1. deterministically sort/group by semantic key;
2. normalize endpoints;
3. collapse identical duplicates;
4. resolve contradictions through a closed declared policy;
5. validate liveness, generation, kind, degree, capacity, and lifecycle;
6. stage removals before admitted creations;
7. assign new edges the lowest available slots in canonical request order;
8. validate the complete staged result; and
9. atomically publish edge state and incident indices.

An accepted-copy request that cannot veto an already accepted lattice copy MUST declare a
deterministic filtered disposition. A process requiring atomic success MUST use an unpublished
stage transaction and fail without partial publication. An implicit relationship rollback MUST NOT
retroactively reinterpret a committed copy.

Sequential uses the same protocol with batch size one where immediate visibility is required.

## CCV1-019 — Logical checkpoints and replay classes

The checkpoint schema MUST be constructed recursively from:

- universal logical CPM state;
- auxiliary blocks' logical codecs;
- runtime parameters and parameter history;
- semantic RNG seed, replica, continuation, and counters;
- completed MCS and admitted settled position;
- executable/checkpoint schema identity;
- replay class/configuration scope; and
- integrity checksum.

Every descriptor/tracker state MUST declare one of:

- persist logical state;
- reconstruct exactly from persisted logical state; or
- exclude because it is workspace-only.

Restore MUST validate schema, executable compatibility, unit/reference policy, capacities,
configuration, and replay class before reconstructing private buffers.

Replay classes are:

1. `ExactConfigurationReplay`: exact continuation for the declared engine, backend, scalar/math
   policy, schedule, and executable/compiler identity;
2. `PortableLogicalRestart`: valid logical reconstruction on a different admitted configuration
   without trajectory identity; and
3. `StatisticalRestart`: only explicitly declared statistical/scientific invariants.

Checkpoints MUST NOT contain Symbolics, units, registries, external systems, closures, live
kernels, events/tasks, or workspace buffers.

## CCV1-020 — Backend support and backend-agnostic qualification

Support MUST be reported per backend and protocol surface:

1. `InterfaceOnly`: adapter exists; no execution claim;
2. `Compiles`: representative admitted descriptors/kernels compile;
3. `Functional`: bounded stochastic execution and semantic/property tests pass without fallback;
4. `ReplayQualified`: declared exact-configuration replay passes; and
5. `PerformanceQualified`: current allocation, transfer, synchronization, and warm-performance
   evidence exists.

Phase exit requires:

- CPU sequential at `ReplayQualified`;
- CPU checkerboard at `ReplayQualified`;
- the generic KernelAbstractions checkerboard/adaptation path;
- at least one available GPU backend at `Functional`; and
- no backend claim above obtained evidence.

CUDA, AMDGPU, and Metal remain extensions. Extra GPU vendors are not mandatory pull-request
matrix rows. Qualification beyond the functional witness is manual, scheduled, or release-level.

Every GPU compiler, semantic, conformance, stochastic, replay, checkpoint, and execution test MUST
be authored once against a backend-agnostic test contract. A small backend harness MAY inject only:

- backend selection/device discovery;
- allocation and adaptation;
- synchronization;
- supported scalar/math features;
- expected support level; and
- vendor-specific error/capability translation.

Scientific model construction, fixtures, assertions, seeds, semantic schedules, and compiler
conformance logic MUST NOT be duplicated in vendor-specific suites.

The same suite MUST run locally against any available backend, qualify V1's functional witness,
and support a later release CI matrix by supplying backend harness/environment rows without
changing shared tests.

Vendor-specific adapter tests MAY cover allocation, synchronization, discovery, and error
translation. They MUST NOT fork scientific or compiler conformance.

If no usable GPU environment can provide the one required functional witness, phase exit is
blocked. The absence of an additional optional vendor after one witness qualifies is not a
blocker.

## CCV1-021 — Independent downstream fixtures

A test-only module outside CorePotts source MUST define `ExternalWeightedSiteTerm` or an
equivalently neutral fixture containing:

- registered statement family;
- registered pure symbolic site-read operation;
- versioned Hamiltonian descriptor;
- auxiliary per-site scalar state;
- bounded affected-region rule;
- reusable observation/reduction workspace;
- adaptation and logical checkpoint behavior;
- qualified inspection/diagnostics; and
- sequential/checkerboard capability rules.

The term assigns a declared spatial weight to site ownership and therefore has an independently
calculable local copy delta. Its observation performs a declared weighted-occupancy reduction.
The fixture MUST NOT disguise an existing biological mechanism.

It MUST:

- complete/compile through public registration;
- run through public system, executable, problem, and solve flow;
- match independent delta/observation calculations;
- execute on sequential CPU and checkerboard CPU;
- adapt, checkpoint, restore, and satisfy replay claims;
- compile/run on the functional GPU witness through the shared backend-agnostic suite; and
- require zero edits to CorePotts central program, engines, proposal loop, checkpoint machinery,
  operation switch, enum, or descriptor union.

A second test-only module outside CorePotts source MUST define `ExternalBoundedPairTerm` or an
equivalently neutral relationship fixture containing:

- typed undirected relationship state with one scalar payload;
- an independently calculable pair contribution that does not use focal distance mechanics;
- bounded incident-relationship access;
- at most one bounded accepted-copy create or update request;
- one bounded lifecycle remove request;
- capacity, degree, generation, duplicate, conflict, and canonical-order behavior;
- adaptation and logical checkpoint reconstruction;
- qualified inspection/diagnostics; and
- sequential/checkerboard capability rules.

The relationship fixture MUST:

- complete and compile through the same public registration, compiler, and descriptor protocols as
  built-in relationship terms;
- run through public system, executable, problem, and solve flow;
- match independent pair-energy, request, lifecycle, incident-index, and transaction calculations;
- execute on sequential CPU and checkerboard CPU;
- adapt, checkpoint, restore, and satisfy its declared replay claims;
- execute on the functional GPU witness for every relationship kernel family claimed
  `Functional`; and
- require zero edits to CorePotts central program, engines, proposal loop, relationship commit
  machinery, checkpoint machinery, operation switch, enum, descriptor union, or mechanism branch.

It MUST NOT be focal-point plasticity, a distance spring, or another accepted proof model under a
neutral name.

Both neutral fixtures MUST be authored as soon as public registration and descriptor construction
exist. They MUST be qualified progressively through analysis/lowering, grouping, sequential CPU,
checkerboard CPU, adaptation/checkpoint/replay, and functional GPU execution. Both fixtures MUST
fully pass before focal, Wortel, or Merks mechanism lowering resumes.

## CCV1-022 — Autonomous implementation order

After explicit owner send-off, one autonomous phase MUST proceed through G0 through G9. These gates
are dependency boundaries, not separate phases, owner approvals, releases, or CI workflows.

### G0 — Authority and recovery baseline

- Freeze the surviving semantic/test inventory and source-disposition map.
- Record dirty-worktree ownership and preserve unrelated user changes.
- Extract reusable semantic tests before deleting incorrect execution paths.
- Create an intentional specification/baseline checkpoint commit.
- Keep any temporary `main` clone read-only and non-authoritative.

### G1 — Host compiler facts

- Implement the frozen source graph, normalized host DAG, analyzed fact tables, diagnostics, and
  verifiers.
- Pass completion/normalization idempotence, provenance, and valid/invalid transfer-rule tests.
- Use no private ModelingToolkit/Symbolics representation as authority.
- Make both CCV1-021 neutral fixtures reach analyzed descriptor candidates through public
  registration.

### G2 — Descriptor, grouping, evaluator, state, and workspace boundary

- Implement descriptor grouping, layouts, handles, state, workspace, adaptation schema, and
  inspection.
- Run evaluator qualification and record the selected private representation.
- Pass fixed-`G`, expression-growth, inference, device-compilation, and compiler-algebra tests.
- Make the external site fixture reach a complete executable plan.
- Compile-probe the evaluator and concrete launch arguments on the available GPU witness.
- Complete the R1 compiler review and checkpoint the cleared compiler boundary.

Runtime and proof-model work MUST NOT begin while G1 or G2 has a blocking failure.

### G3 — Sequential reference and finite transition authority

- Implement generic sequential CPU execution through descriptor protocols only.
- Run the external site fixture through the public problem/solve/checkpoint flow.
- Pass finite transition-matrix, local/global delta, rejection atomicity, tracker rebuild, RNG,
  access-count, inference, and allocation gates.
- Establish the minimal public SciML lifecycle spine.
- Complete the independent R1.5 sequential-authority review on the exact G3 implementation
  checkpoint and checkpoint the cleared sequential boundary.

G4 MUST NOT begin while R1.5 has a P0 or P1 finding. A finding that invalidates a cleared compiler
fact returns work to G1 or G2; an acceptance, RNG, atomicity, tracker, lifecycle, or sequential
execution finding returns work to G3.

### G4 — Checkerboard and first functional GPU witness

- Implement realized coloring, footprint verification, priorities, claims, reductions, and
  deterministic commit.
- Run the external site fixture on checkerboard CPU.
- Pass kernel boundary/workgroup, adaptation, no-fallback, and deterministic CPU/GPU differential
  fixtures.
- Reach `Functional` on the selected GPU for the generic site/state/workspace surface.

Host fallback, scalar indexing, device completion-order semantics, or a device-illegal
representation MUST return work to G2 or G4 and MUST NOT be accepted as a reduced substitute.

### G5 — Generic trackers, relationships, lifecycle, and checkpoint

- Implement generic tracker, incident-index, relationship, request, lifecycle, and checkpoint
  protocols.
- Before cell-lifecycle implementation, clear G5-L0 against CCV1-027. Then implement the closed
  cell-structure transaction language through bounded G5-L1--G5-L5 checkpoints, including the
  blocking G5-L2Q review, without opening G6.
- Pass the neutral external relationship fixture on sequential CPU and checkerboard CPU.
- Pass incident-locality, bounded-request, canonical conflict, capacity, degree, generation,
  failure-atomicity, lifecycle, checkpoint, and permutation properties.
- Execute every applicable relationship kernel family on the functional GPU witness.
- Complete the R2 execution/concurrency/GPU review and checkpoint the cleared execution boundary.

Focal, Wortel, and Merks lowering MUST NOT begin while either neutral fixture or R2 has a blocking
failure.

### G6 — Public integration spine

- Complete the public system, executable, problem, integrator, solution, checkpoint, and
  SymbolicIndexingInterface lifecycle on neutral fixtures.
- Pass namespacing, composition, units, parameters, equations, observations, remake, and extension
  load-order checks.
- Cross ProcessBigraphs only through the accepted public protocol.

### G7 — Proof-model reconstruction and scientific qualification

- Rebuild focal, Wortel, and Merks only through the generic compiler and public lifecycle.
- Pass exact paper/source-qualified microfixtures before bounded statistical endpoints.
- Calibrate statistics separately from frozen validation seeds and retain one primary endpoint per
  proof model.
- Require zero new CorePotts mechanism branches or executor categories.
- Complete the R3 scientific review and checkpoint the cleared scientific boundary.

### G8 — Clean break and complete integration

- Remove named-mechanism, obsolete-engine, compatibility, oracle, old-checkpoint, and superseded
  paths only after replacement authority passes.
- Run the complete in-scope integration and platform matrix.
- Pass package loading, stale-name, Aqua, ExplicitImports, fresh-process, allocation,
  specialization, dependency, and source audits.
- Create an intentional clean-break checkpoint commit.

### G9 — Terminal qualification

- Pass every CCV1-023 phase-exit condition and the full ordinary Julia CI surface.
- Run all shared backend-agnostic functional tests on the selected GPU witness.
- Pass one fresh-process public black-box authoring-through-solution flow.
- Produce the final source/API/coverage/limits/backend/deferred-docs audit.
- Complete the R4 terminal review and create the final implementation checkpoint only after its
  blocking findings are cleared.

G0 through G9 are the sole authoritative execution order. SPV1-032, ACV1-021, and ARV1-020 remain
requirement history but are superseded for implementation ordering.

Work MAY move within one gate or between adjacent gates to preserve a coherent implementation.
Dependent work MUST pause on a failed gate and return to the earliest violated abstraction.
Mechanism work MUST NOT bypass a failed architecture, device, relationship, public-lifecycle, or
external-fixture gate.

A read-only temporary clone of `main` MAY provide algorithm, performance, and test-intent evidence.
It MUST NOT be executed as an oracle, linked, imported, or treated as compatibility authority.

Migration, wrappers, user documentation, polished examples, Dagger, a third engine, and broad
literature reproduction remain outside this phase.

## CCV1-023 — Stopping rule and phase exit

Execution-control outcomes are distinct:

1. `GateFailure`: dependent work pauses and the implementation repairs the earliest violated
   abstraction autonomously;
2. `ArchitectureInvalidation`: work returns to an intentional earlier checkpoint because a central
   invariant such as fixed-`G`, no fallback, bounded mutation, deterministic commit, or
   zero-Core-edit extensibility failed; and
3. `OwnerBlocker`: only one of the owner-input conditions below.

A gate failure or architecture invalidation MUST NOT authorize a biological special case, weaker
checkerboard semantics, private upstream coupling, host fallback, reduced external-extension
surface, or a support claim above obtained evidence.

Autonomous implementation MUST stop for owner input only when:

- accepted requirements are contradictory after applying authority;
- a required public upstream capability is absent and only private coupling could proceed;
- every evaluator candidate fails a mandatory gate;
- either neutral downstream fixture cannot fit the accepted extension boundary;
- no available execution environment can provide the required functional GPU witness; or
- a material uncovered product/scientific choice is required.

Ordinary implementation difficulty, test failure, performance regression, internal API design,
source movement, optimization, or prototype rewriting is not a stopping condition. The absence of
an optional GPU vendor is not a stopping condition after one functional witness qualifies.

### Independent review boundaries

Five fresh-context, read-only reviews are required:

- `R1Compiler` after G2 reviews host/device separation, inference, specialization, diagnostics,
  grouping, evaluator selection, and external lowering;
- `R1.5Sequential` after G3 reviews descriptor-only proposal execution, role and acceptance
  semantics, finite transition authority, RNG addressing, rejection atomicity, tracker invariants,
  checkpoint continuation, warm-path inference/allocation, the external public fixture, and a
  mechanism-leakage inventory of CorePotts types, fields, operation identities, dispatch methods,
  capability flags, and executor branches;
- `R2Execution` after G5 reviews footprints, deterministic checkerboard commit, relationship and
  cell-lifecycle transactions, adaptation, GPU legality, checkpoint continuation, external
  extension equality, and no fallback;
- `R3Science` after G7 reviews paper/source-qualified equations, stage order, exact
  microfixtures, and statistical calibration; and
- `R4Terminal` after G9 reviews the public black-box flow, stale/private APIs, package loading,
  scope, and phase-exit completeness.

A reviewer MUST:

- not have authored the slice under review;
- receive the accepted specifications, gate definition, current diff, and test commands;
- treat no informal implementation rationale as authority;
- inspect production and test code while remaining read-only;
- cite the exact normative clause, smallest code location, reproducer/failing test or static proof,
  violated invariant, and earliest repair gate for every blocking finding; and
- neither expand V1 scope nor weaken an accepted invariant.

Review findings are:

- `P0`: scientific corruption, data loss, nondeterministic integrity failure, or direct
  contradiction; blocks the gate;
- `P1`: compiler invariant, extensibility, GPU legality, concurrency, replay, or public-boundary
  failure; blocks the gate;
- `P2`: localized correctness, diagnostics, tests, maintainability, or package-quality defect
  within accepted scope; fixed autonomously before G9; and
- `P3`: optional improvement, style, or future-scope suggestion; nonblocking.

A P0 or P1 returns work to the earliest owning gate. A P2 does not require owner input. A reviewer
preference cannot become a requirement. A genuinely uncovered material scientific/product choice
uses the existing owner-blocker rule.

### Recovery and implementation-control record

Intentional, semantically coherent Git checkpoint commits are required after cleared R1, R1.5, R2,
and R3, before broad legacy deletion, after the clean break, and after cleared R4. Ordinary
failure recovery MUST repair or revert a bounded coherent slice and MUST NOT use destructive reset
as the default response.

After explicit implementation send-off, one living
`design/audits/symbolic-potts-v1-implementation-control.md` MUST record:

- each gate as `pending`, `in_progress`, `passed`, or `reopened`;
- the exact tests/static checks establishing it;
- its intentional checkpoint commit;
- unresolved P2 findings;
- required reviewer result; and
- the earliest gate reopened by a later regression.

The record MUST NOT contain freshness deadlines, renewed attestations, copied CI logs,
expected-output archives, hardware ledgers, manually renewed hashes, duplicated vendor suites, or
a second definition of scientific semantics. It becomes input to the final implementation audit,
not recurring CI authority.

### Failure routing

The implementation MUST return to the earliest wrong artifact:

- missing/incorrect compiler facts or provenance return to G1;
- occurrence-driven specialization, abstract evaluator/device arguments, or illegal layouts return
  to G2;
- local delta, transition, rejection, tracker, or RNG defects return to G1 through G3 according to
  the first incorrect artifact;
- whole-lattice/whole-graph access returns to G2 or G5;
- checkerboard completion-order or proposal-order dependence returns to G4;
- host fallback, scalar indexing, or kernel-shape failure returns to G2 or G4;
- unbounded, noncanonical, or partially published relationship mutation returns to G5;
- public MTK/SciML/extension lifecycle failure returns to G6;
- a proof model requiring a CorePotts special case returns to G1, G2, or G5;
- paper/source disagreement returns to G7;
- dual old/new runtime authority returns to G8; and
- a terminal package/black-box failure reopens its earliest owning gate rather than only G9.

Phase exit requires:

1. all IR, layout, schedule, and transaction verifiers pass;
2. CorePotts program/engine/proposal/checkpoint/capability paths contain no named biological
   mechanism, including mechanism-specific callable tags or operation identities disguised as
   generic descriptor machinery;
3. no Symbolics, units, registry, dictionary, closure, or abstract descriptor collection reaches
   the executable;
4. fixed-`G` specialization remains bounded as occurrences grow;
5. warmed proposal/stage execution satisfies allocation and locality requirements;
6. local terms/trackers avoid unrelated whole-state scans;
7. replay and stochastic divergence match declared scopes;
8. both neutral downstream fixtures pass every required surface and the GPU witness;
9. relationship/lifecycle ordering, capacity, generation, failure-atomicity, and integrity
   properties pass;
10. focal, Wortel, and Merks run stochastically through complete visible public definitions;
11. SciML, ModelingToolkit, equation, observation, ProcessBigraphs, Unitful, and in-scope
    MakiePotts integration gates pass;
12. every GPU test uses the shared backend-agnostic harness and is ready for later release-matrix
    rows;
13. ordinary Julia CI passes without evidence freshness machinery; and
14. the final audit reports source disposition, public surface, scientific coverage, performance
    limits, backend support levels, and deferred documentation.

Implementation completion does not authorize merge or publication. Those remain explicit owner
actions.

## CCV1-024 — Focused compiler guarantee tests

Compiler conformance MUST use ordinary Julia `Test` entry points and the package's normal
`Pkg.test` flow. The required compiler guarantees are:

1. every compiler layer runs its verifier on valid and deliberately invalid fixtures;
2. normalized/analyzed records preserve qualified source and diagnostic provenance;
3. type, shape, unit, parameter-role, resource, footprint, effect, RNG, stage, and backend facts
   have exact focused tests;
4. local Hamiltonian deltas match independent total-energy recomputation on small systems;
5. tracker updates match independent rebuild/recomputation;
6. the downstream fixtures prove zero-Core-edit statement, operation, descriptor, state,
   workspace, relationship, request, lifecycle, adaptation, checkpoint, engine, and GPU
   extensibility;
7. targeted inference/device-compilation tests prove that qualified hot paths contain no abstract
   dispatch, host closure, Symbolics value, registry lookup, or device exception;
8. warmed CPU proposal/stage paths satisfy their zero-host-allocation contract;
9. backend harnesses prove that qualified device paths do not silently execute or transfer through
   the host; and
10. compilation inspection reports `N`, `G`, group splits, evaluator sizes, kernel inventory, and
    backend rejection reasons;
11. normalization/completion idempotence, legal alpha-renaming/namespacing, semantically unordered
    statement permutation, and repeated compilation have exact structural-equivalence tests;
12. RNG-free Hamiltonian term permutation, zero-term insertion, algebraically equivalent term
    splitting, and repeated-occurrence regrouping preserve total energy, local deltas, and
    transition probabilities under the declared numerical policy;
13. counting-access sentinels prove that proposal deltas remain lattice-size independent, tracker
    updates do not scan the lattice, and relationship work scales with incident degree rather than
    total edge count;
14. the package-owned counter RNG has raw-integer known-answer vectors, exhaustive small-domain
    semantic-address uniqueness tests, evaluation/workgroup-order invariance, and exact checkpoint
    continuation;
15. every kernel family runs boundary-size and workgroup-shape fixtures on the
    KernelAbstractions CPU backend and through the functional GPU witness;
16. synthetic adaptation and functional device round trips preserve descriptor/wrapper structure,
    and deterministic conflict-free CPU/GPU microprograms agree under the declared numerical
    policy;
17. fresh-process tests cover precompilation, base-only loading, optional-dependency load order,
    extension activation, and composition of two independent external descriptor families; and
18. Aqua, targeted ExplicitImports, and a compact invalid-fixture matrix cover ordinary package
    hygiene and stable diagnostic code/category plus source provenance.

Compiler algebra tests MUST compare public semantic/inspection fields and scientific results. They
MUST NOT make statement order irrelevant where ordering is part of the declared semantics, and they
MUST NOT compare private host-IR object layout.

Specialization-growth tests MUST vary occurrence count at fixed `G`. They MUST assert structural
invariants:

- group count and evaluator structures remain fixed;
- repeated values remain instance-buffer data;
- program type nesting does not grow once group structure is fixed; and
- no evaluator or kernel is generated per repeated occurrence.

At minimum, a structurally identical fixture MUST be exercised at occurrence counts `1`, `32`, and
`1024`, plus a parameter-value-only change. The compiler-owned report MUST retain the same `G`,
descriptor-group identities, evaluator signatures, and kernel-family set. Exact Julia
`MethodInstance` counts are not contract authority.

Expression-growth tests MUST vary evaluator node count and distinct evaluator-group count. They
MUST detect compiler recursion failure, invalid device code, and unexpected specialization-class
growth.

Counting-access sentinels MUST compare the same local operation on at least two lattice sizes and at
least two total relationship counts while holding the relevant local footprint or incident degree
fixed. They are structural complexity checks, not timing benchmarks.

Kernel-shape fixtures MUST include logical sizes `1`, `W-1`, `W`, `W+1`, another nonmultiple of
`W`, and a rectangular multidimensional domain for an admitted workgroup size `W`. They MUST vary
legal workgroup size, synchronize before observation, exercise rare qualified kernel branches, and
make scalar indexing or host fallback fail. Exact discrete state, raw RNG words, proposal
identities, canonical request order, and integer trackers MUST agree between deterministic
conflict-free CPU/GPU fixtures. Floating fields, energies, and reductions follow CCV1-019's
numerical/replay class.

Fresh-process checks MUST use ordinary isolated Julia processes. Base-package loading MUST NOT
require a vendor backend. Optional dependencies MUST activate their extensions whether loaded
before or after PottsToolkit according to Julia package-extension semantics.

Timing, native/device-code size, register use, first-launch cost, and warm throughput SHOULD be
recorded by focused benchmark/development jobs. They MUST NOT become brittle absolute wall-clock PR
thresholds. A regression identified by those reports MUST be investigated before a performance
claim is raised or retained.

Targeted JET, SnoopCompile invalidation/reinference trends, AllocCheck, compile latency,
`--trace-compile` volume, native/device-code size, and GPU register/occupancy reports are
development, scheduled, or release qualification. They MUST NOT become universal blocking PR
gates.

Compiler tests MUST NOT rely on:

- whole-object or whole-IR textual snapshots;
- exact LLVM/native instruction text;
- exact internal method-instance counts;
- private ModelingToolkit/Symbolics representations;
- a legacy executable oracle;
- mandatory package-wide JET;
- universal bitwise floating reduction equality beyond the declared numerical policy;
- evidence freshness or manually renewed attestations; or
- duplicated vendor-specific scientific suites.

Small stable semantic inspection fields MAY use golden expectations when they are public or
qualified contract values rather than private layout dumps.

## CCV1-025 — Focused stochastic and statistical guarantees

Exact semantics MUST use exact or property tests whenever possible. Statistical tests MUST NOT be
used to excuse an incorrect local delta, RNG address, acceptance calculation, transaction,
checkpoint, or tracker.

Each blocking statistical claim MUST declare:

- the scientific or transition-level statistic;
- the initial condition and runtime horizon;
- engine/backend/replay scope;
- a fixed reproducible seed/replica panel;
- independently derived analytic expectation or scientifically justified acceptance envelope;
- sample size and aggregation rule;
- tolerance, confidence rule, or effect-size threshold; and
- a concise failure report containing observed values and the seed panel.

The fixed seed panel makes the CI result reproducible. Tests MUST NOT rerun with new seeds until
they pass.

Tolerance/envelope selection MUST be independent of the frozen validation seed panel. A claim MAY
use an analytic derivation or a separate calibration seed set, but MUST NOT inspect the validation
panel and then choose a passing threshold. Each blocking statistical test MUST demonstrate during
test development that it rejects at least one scientifically relevant biased alternative, such as
an incorrect acceptance probability, missing directional contribution, wrong noise scale, or
reversed response. The calibration/power exercise is development evidence, not a recurring CI
ledger.

Preferred statistical authority, in order, is:

1. an exact finite-state or transition probability;
2. an analytic expectation or variance on a small model;
3. a conservation/symmetry or other metamorphic distributional property;
4. an independently implemented reference calculation; and
5. a bounded scientific envelope for a proof model.

Same-configuration replay, stream isolation, and checkpoint continuation MUST be tested exactly
where promised. Different seeds/replicas MUST demonstrate nondegenerate divergence, but divergence
alone is not evidence that a scientific distribution is correct.

Sequential and checkerboard statistics MUST be judged against their specified kinetics. They MUST
NOT be required to share trajectories or distributions unless a separate accepted contract makes
that claim. Backend rows running the same engine semantics MUST use the same backend-agnostic
statistical experiment; exact equality is required only at `ReplayQualified`, otherwise the
declared distributional envelope governs.

The V1 blocking suite MUST remain bounded and focused:

- analytic or independently calculable proposal/acceptance statistics cover the stochastic
  kernel;
- one primary nondegenerate scientific statistic covers each focal, Wortel, and Merks fixture;
- exact property tests cover positivity, capacity, conservation, generation, lifecycle, and other
  invariants that do not require sampling; and
- secondary exploratory observables are reported without multiplying blocking hypotheses.

The three proof-model primary endpoints are:

- Wortel: an independently calibrated speed–persistence contrast central to the Act mechanism;
  activity-strength speed ordering MAY be a secondary nonblocking observation but MUST NOT create a
  second blocking campaign;
- Merks: short-lag displacement variance projected onto the initial major/minor axes MUST
  distinguish an elongated single-cell fixture from its matched round ablation; and
- focal-point plasticity: eligible-candidate identities in a symmetric finite fixture MUST satisfy
  the independently calculated exchangeable distribution and detect enumeration-order bias.

The Merks and focal endpoints remain subject to the same independent calibration, frozen validation
panel, detection-power demonstration, and failure-report requirements as every other blocking
statistic. They MUST use a small fixture and MUST NOT be replaced by a full vascular-network or
stationary-link campaign.

Larger replica campaigns, sensitivity studies, paper reproduction, multi-vendor performance
statistics, and publication plots are manual, scheduled, release-level, or later-phase work. They
MUST NOT become ordinary PR gates or evidence-freshness machinery.

## CCV1-026 — Analytic and biophysical conformance catalog

The V1 blocking suite MUST cover the following small, independently interpretable experiments.
Exact/property authority takes precedence over sampling whenever both are possible.

### Universal transition kernel

- A two- to four-site finite enumerable lattice fixture MUST independently construct every row of
  the transition matrix `P`, including actionable, same-owner, boundary, constraint-rejected, and
  other declared null outcomes. Every entry MUST be nonnegative, every row MUST sum to one,
  forbidden transitions MUST be zero, null mass and proposal multiplicities MUST be exact, and the
  compiled one-step executor MUST agree with every row.
- Independently enumerated two-step probabilities MUST agree with `P * P`.
- Acceptance MUST match the declared function of `ΔH` and temperature on a controlled symmetric
  fixture.
- Scripted uniform draws immediately below, equal to, and immediately above the acceptance
  threshold MUST pin comparison direction, rounding, underflow, favorable/neutral branches,
  probability zero/one, zero-temperature behavior, and admitted proposal-ratio behavior.
- Same-owner/null attempts, rejected moves, failed constraints, and losing conflicts MUST leave
  lattice, tracker, auxiliary, relationship, generation, request, lifecycle, and observation state
  exactly unchanged. RNG-address consumption MUST separately match its declared policy.
- Increasing unfavorable `ΔH` MUST reduce acceptance, and increasing positive temperature over a
  declared nonsaturated range MUST increase it.
- Adding a constant Hamiltonian offset MUST NOT change transitions.
- Scaling all Hamiltonian contributions and temperature by the same positive factor MUST preserve
  the acceptance law where the declared numerical policy admits that equivalence.
- Translation, rotation, and reflection of a model within the admitted topology symmetry group
  MUST produce the corresponding transformed distribution.
- With no directional contribution, ensemble drift MUST be consistent with zero; reversing a
  declared drive MUST reverse the drift statistic.

Detailed balance MUST be asserted only for a fixture whose proposal law is proven symmetric or
whose acceptance includes the required proposal-ratio correction. General CPM execution MUST NOT be
certified against an equilibrium property it does not claim. For the proven-reversible
microfixture, the independently calculated Gibbs weights MUST satisfy both `πP = π` and pairwise
flux equality.

### State, geometry, and interfaces

- Incremental volume, boundary, moment, centroid, elongation, and other retained tracker values
  MUST match independent recomputation after accepted copies.
- The volume partition identity MUST hold: the sum of cell volumes equals occupied lattice sites,
  and execution MUST NOT create undeclared owner identities.
- Connected polyominoes up to a small fixed area MUST exercise every candidate add/remove against
  independent volume, boundary-bond, centroid, moment, elongation, energy-delta, and connectivity
  calculations.
- Increasing a positive volume penalty over a declared range MUST reduce deviations from the
  target volume.
- For `H_V = λ(V - V*)²`, exact add/remove deltas and second finite difference `2λ` MUST agree with
  the compiled term. In a passive zero-temperature fixture, every accepted move MUST have
  nonincreasing independently recomputed total energy.
- A positive surface/interface penalty in an isolated relaxation fixture MUST reduce its declared
  perimeter or circularity defect statistic.
- A connectivity-protected cell MUST remain connected under every admitted proposal.
- Neighborhood counts and local energy deltas MUST respect the exact
  `VonNeumann`, `Moore`, `AxialRays`, `DistanceShells`, and explicit-offset definitions.
- Each named neighborhood MUST have an exact discrete lattice-anisotropy fingerprint over admitted
  lattice-symmetry orientations and periodic seams. Arbitrary-angle continuum isotropy MUST NOT be
  asserted.
- Accepted proposals with disjoint declared footprints MUST commute under every within-color
  permutation. A conflicting pair MUST resolve to an independently calculated deterministic
  winner, with identical lattice, trackers, relationship state, canonical requests, and
  observations.

### Fields and chemotaxis

- A uniform field MUST remain uniform under pure diffusion.
- Periodic or no-flux pure diffusion MUST conserve total field mass within the declared numerical
  tolerance.
- An impulse or another small analytic initial condition MUST match the selected discrete
  diffusion stencil's independently calculated evolution.
- On a periodic grid, a discrete Fourier mode MUST follow the independently calculated one-step
  amplification factor and multi-step power for the selected Laplacian.
- Every admitted explicit field step MUST satisfy its declared stability condition and exact
  source, sink, and boundary mass budget. Positivity or a maximum principle MUST be asserted only
  where the selected scheme guarantees it.
- Pure decay MUST follow its exact discrete-step or admitted analytic curve.
- Zero chemotactic strength MUST remove field-dependent drift.
- Reversing a controlled field gradient MUST reverse chemotactic drift.
- Increasing chemotactic strength over a declared nonsaturated range MUST increase the directional
  response statistic.
- For a declared linear difference response, a constant field contributes exactly zero, adding a
  constant field offset preserves `ΔH`, reversing strength or gradient reverses `ΔH`, and inverse
  scaling of field and strength preserves it. These identities MUST NOT be applied to a nonlinear
  sensing law that does not claim them.

### Wortel/Act fixture

- An admitted extension MUST initialize the copied site to the declared activity value.
- Activity MUST decay at the exact declared cadence and remain in its valid range.
- Hand-built source/target Moore neighborhoods MUST match an independent same-cell geometric-mean
  calculation for equal and unequal activity, zero activity, unequal same-cell counts, foreign-cell
  pixels, and periodic wrapping, including the exact declared Act `ΔH`.
- A forced trace containing accepted extension, accepted retraction, rejection, same-owner attempt,
  and completed-MCS decay MUST pin activation, clearing, write visibility, one decay per positive
  value, and flooring at zero after every stage.
- Zero activity strength MUST reduce to the corresponding baseline CPM behavior.
- Rotating an initialized activity pattern MUST rotate the migration-bias distribution.
- A small independently calibrated parameter contrast MUST show the declared persistence ordering;
  the primary Wortel statistical endpoint SHOULD test the speed–persistence relationship central
  to the proof model.

### Merks fixture

- Zero elongation strength MUST remove the elongation contribution.
- Small analytic shapes and their translations, rotations, and reflections MUST match independently
  calculated moments, largest inertia eigenvalue, inferred cell length, target energy, and local
  add/remove elongation `ΔH`.
- Increasing elongation strength over a declared range MUST move the aspect-ratio statistic toward
  its target.
- Rotating the initial cell/field configuration MUST rotate the orientation distribution.
- Zero chemotactic strength and gradient reversal MUST satisfy the general chemotaxis controls.
- A controlled Merks field MUST match the paper-qualified chemotaxis sign, magnitude, extension
  predicate, constant-offset invariance, and strength linearity.
- Source removal MUST produce the declared field decay behavior.
- A mixed endothelial/ECM mask MUST satisfy the independently calculated one-substep field mass
  balance, with secretion only at declared cell sites and decay only at declared ECM sites.
- Every local-connectivity pattern in the accepted Merks rule, including its documented
  conservative false-rejection case, MUST match an independent truth table.
- The primary Merks statistical endpoint is the elongated-versus-round major/minor displacement
  variance contrast declared by CCV1-025.

Full vascular-network morphology, remodeling curves, branch distributions, and paper-sized
parameter sweeps are scheduled or release-level rather than ordinary blocking CI.

### Focal relationship fixture

- Focal elastic energy MUST be minimal at target length and restoring on both sides.
- Local focal `ΔH` MUST match complete relationship-energy recomputation.
- Undirected endpoint exchange MUST preserve energy and request meaning.
- Creation MUST obey contact, endpoint-kind, degree, generation, and capacity rules.
- A proposal/accepted-copy truth table MUST independently cover medium, self, unsupported-kind,
  existing-link, saturated-degree/capacity, rejected, and accepted candidates, plus same-cluster
  exclusion where the qualified focal profile declares cluster identity.
  Activation energy MUST be visible at proposal time, MUST NOT double-count the ordinary spring
  path on the activation proposal, and only acceptance may create exactly one canonical link with
  the declared payload.
- Links below or exactly at the inclusive maximum MUST persist and links strictly above it MUST be
  removed at the declared stage. Endpoint extinction MUST remove every incident link. Per accepted
  copy, creation/removal visibility, gaining-before-losing endpoint order, and the declared
  per-endpoint removal bound MUST match the qualified lifecycle profile.
- Duplicate/conflicting requests and request permutations MUST resolve to the declared canonical
  transaction.
- Endpoint retirement and checkpoint/restore MUST preserve lifecycle, generation, and payload
  invariants.
- Translating a linked pair across a periodic seam or reversing endpoint order MUST preserve
  energy, local delta, and break behavior relative to independent unwrapped geometry.
- A Wang-qualified fixture MUST pin its source-defined retuning cadence and old/new payload
  visibility without making that cadence universal focal semantics.
- The primary focal statistical endpoint is the eligible-candidate exchangeability experiment
  declared by CCV1-025.

A stationary link-length statistic MAY be blocking only when the isolated fixture has an
independently justified expectation. Exact energy and transaction tests remain authoritative.

These experiments MUST reuse public model/compiler/runtime paths. A test helper MAY calculate an
expectation or transform input data, but MUST NOT construct a hidden privileged model or call a
mechanism-specific CorePotts path.

Manufactured PDE convergence, equilibrium droplet fluctuations, full Wortel curves, Merks network
morphology, stationary focal-link distributions without a proven law, multi-vendor performance,
and compiler/GPU profiling are scheduled, release-level, or later-phase checks. They MUST NOT
become ordinary PR gates or evidence-freshness obligations.

The blocking suite MUST NOT assert general detailed balance, sequential/checkerboard distribution
equality, arbitrary-angle continuum isotropy, universal linear mean-squared displacement,
finite-temperature short-run monotonic relaxation, early-time continuum-Gaussian equality for a
discrete stencil, unqualified linear chemotaxis, or fluctuation-response identities without proven
reversibility and equilibration.

## CCV1-027 — Closed cell-lifecycle language and transaction boundary

This clause is the V1 authority for compiled finite-cell creation, occupied removal, retirement,
kind transition, and binary division. It supersedes lower-authority lifecycle text where that text
implies unconditional executor retirement, generation advancement at retirement, open structural
mutation verbs, a site-iterated event domain, host lifecycle fallback, or a second lifecycle clock.
It does not broaden G6 or authorize proof-model migration.

### Closed structural algebra and public surface

`LifecycleProcess` is the sole public cell-lifecycle statement. Its stable V1 target domains are:

- `cells(kind)`, over finite active `(cell_id, generation)` identities; and
- `model()`, over exactly one qualified completed-model identity.

Creation placement MAY evaluate bounded finite site expressions, but V1 does not admit a
site-iterated lifecycle event domain or a general lifecycle query language. Qualified bindings and
resource identities MUST be resolved before analysis; symbolic-name prefixes are capture syntax,
not analysis authority.

The public statement shape is:

```julia
LifecycleProcess(name; domain, anchor = nothing, expression, effects,
                 phase = Lifecycle(), cadence = EveryMCS())
```

`expression` MUST be a dimensionless Boolean. `effects` contains exactly one structural effect for
a cell-lifecycle statement. Model-domain `CreateCell` has required `placement`;
cell-domain `RemoveCell` has required source and replacement medium; `Retire` has required source;
`Transition` has required source and destination kind; and `Divide` has required source, geometry,
relation, and side identity. State and relationship overrides are canonical tuples. Every effect
contains its explicit priority and mandatory inadmissibility disposition. Compatible public
constructor conveniences MUST normalize to these facts before completion.

The closed cell-structure effect algebra is exactly:

- `CreateCell`, `0 -> 1`;
- `RemoveCell`, `1 -> 0`, transferring all owned sites to one declared medium;
- `Retire`, `1 -> 0`, consuming an already empty identity;
- `Transition`, `1 -> 1`, preserving identity and ownership while changing kind/state; and
- `Divide`, `1 -> 2`, retaining the parent identity and allocating one daughter.

A cell-targeting process contains exactly one structural effect. Kind mapping, state mapping, site
ownership-change behavior, relationship consequences, priority, and inadmissibility disposition
are policies within that effect, not coincident mutation verbs. The five effects lower to one
closed cell-structure transaction IR. V1 excludes fusion, fragmentation, arbitrary M-to-N rewrite,
recursive emission, dynamic structural registration, and imperative mutation callbacks.

Every effect MUST carry explicit signed-`Int32` semantic priority and an explicit
`FilterInadmissible()` or `ErrorOnInadmissible()` value. `on_inadmissible` is mandatory: omission
MUST fail construction. Integrity failures are never filterable. Binary division MAY default both
descendant kind mappings to concrete frozen `PreserveKind()` values; CorePotts MUST NOT infer any
policy from missing runtime data.

### Built-in V1 policy inventory and pure extension slots

The complete built-in creation-placement inventory is `SeedAt(site_expression)` and
`SeedStencil(site_expression, finite_offsets; relation)`. A registered external placement operation
MAY occupy the same public `placement` field as a typed symbolic policy value and MUST satisfy the
pure ABI below. Every selected site MUST be in bounds, available, and admissible in the common
snapshot; partial placement, clipping, and declaration-order winners are forbidden. A stencil is
finite compile-time data and connected under its bound relation.

The complete built-in binary-partition inventory is `RandomPlane`,
`PrincipalAxisPlane(:major|:minor)`, and `SpecifiedNormalPlane`, each with an explicit point and
normal. A registered external binary-partition operation MAY occupy the same public `geometry`
field as a typed symbolic policy value and MUST satisfy the pure ABI below. Side identity is
`CanonicalSide()` or `StableRandomSide(draw_identity)`. One explicit finite relation validates both
descendants. Their site sets MUST be nonempty, connected, disjoint, and exactly conserve the
parent's sites. External placement/partition slots admit neither arbitrary callbacks nor new
structural effects.

Retained-parent and daughter kind mapping are independent typed values: `PreserveKind()` or
`SetKind(kind)`. Both normalized values are frozen and inspectable. Omitting them at the public
constructor realizes explicit `PreserveKind()` values for both descendants before completion;
CorePotts never interprets a missing kind field.

Authoritative cell-owned state uses separate creation, removal/retirement, transition, and division
policies. V1 built-in families are:

- creation: `InitializeFrom`, `Unsupported`;
- removal/retirement: `RetireTo`, `Unsupported`;
- transition: `Preserve`, `ResetTo`, `Transform`, `Unsupported`; and
- division: `CopyToDaughters`, `PreserveParentResetDaughter`, `ResetBoth`,
  `SplitConservatively`, `TransformDaughters`, `RedrawDaughters`, `Unsupported`.

These are the complete built-in state-policy families. A registered pure state-transform operation
enters as the symbolic expression inside an applicable initialization, transform, daughter-
transform, or reset policy. A registered trigger operation enters
`LifecycleProcess.expression`. Neither slot registers another structural effect or bypasses schema
policy resolution.

Resolution is `compatible explicit event override -> schema policy -> construction failure`.
Custom and auxiliary state has no implicit clone, zero, reset, redraw, or conservation law.
Derived trackers declare invalidation and repair/reconstruction rather than biological inheritance.
Affected site-owned state explicitly uses `PreserveOnOwnershipChange()` or
`ClearOnOwnershipChange()`. Fields are not rewritten merely because ownership changes. A missing
reachable site-ownership law fails construction.

Relationship consequences remain within the existing bounded relationship transaction protocol.
Creation adds no incident relationship. Removal/retirement uses `RejectWhileLinked` or
`RemoveIncident`; transition uses `PreserveCompatible`, `RemoveIncompatible`, or
`RejectIncompatible`; division uses `RejectWhileLinked` or `RemoveIncident`. Daughter transfer is
deferred. Every relationship schema resolves separate removal/retirement, transition, and division
behavior; a missing reachable behavior fails construction. Effect-level relationship overrides MUST
be canonical tuples before completion and fingerprinting; any scalar authoring convenience MUST
normalize before it reaches frozen source.

### Extinction invariant

Every finite cell kind MUST resolve exactly one ordinary CPM extinction law:

- `RetireAtZero`, which completion lowers to a qualified ordinary `LifecycleProcess` containing
  `Retire`, its declared priority, and frozen `ErrorOnInadmissible()`; or
- `ForbidExtinction`, which completion lowers to a generic proposal constraint preventing loss of
  the final owned site.

A medium kind cannot declare either law. There is no unconditional CorePotts scan and no
undocumented global default. If an active `ForbidExtinction` identity nevertheless has zero
occupancy at lifecycle planning, execution MUST report a nonfilterable invariant failure. It MUST
NOT synthesize retirement. Only a due `RetireAtZero` transaction may consume the bounded
pre-publication zero-occupancy transient. No finalized or published state may contain an active
zero-volume cell.

### Pure lifecycle-policy ABI and frozen closure

External packages MAY register versioned pure trigger, placement, binary-partition, and
state-transform operations. They MUST NOT register a structural mutation verb. Every such operation
uses CCV1-009's sole symbolic-to-callable route and declares:

- admitted lifecycle role and exact semantic input context;
- concrete result type/shape, units, parameter domain, and totality;
- purity, finite reads, footprints/emission, workspace, tracker, and relation requirements;
- semantic RNG namespace, entity/occurrence identity, and lexical draw identities;
- backend/numerical capabilities and one concrete device-valid callable; and
- canonical serialization, validators, qualified provenance, and inspection metadata.

Triggers return one Boolean per bound finite anchor. Placement returns one bounded finite site
selection. Binary partition returns bounded region labels covering every source-owned site and
supports proof of exact two-way conservation. State transforms return their declared fixed
property value or parent/daughter result. These operations cannot mutate state, allocate identity,
commit ownership, emit another structural verb, consult a live registry, or invoke an executor
callback. Assertions MAY supply declared facts but MUST NOT substitute for compiler proof.

The semantic context/result ABI is:

| Role | Exact immutable semantic context | Result and mandatory validation |
|---|---|---|
| trigger | common snapshot, qualified domain anchor/identity, MCS, resolved parameters/resources, occurrence and addressed draws | one `Bool` for each finite bound anchor |
| placement | common snapshot/topology, qualified model/rule occurrence, resolved site expression and relation, parameters/resources, addressed draws | fixed-capacity isbits site selection with declared maximum; prove uniqueness, bounds, availability, admissibility, and stencil connectivity |
| binary partition | common snapshot, source ID/generation, canonical source-owned-site index, explicit relation, resolved point/normal/side, parameters/resources, addressed draws | one compact label per source site; prove exactly two nonempty connected regions and exact ownership conservation |
| state transform | common snapshot, qualified state schema/source identity, old value, allocated destination identities/roles where required, semantic before/planned-after views, parameters/resources, addressed draws | one concrete schema value or fixed parent/daughter pair; validate type, units, domain, and declared conservation/initialization law |

Concrete context/view layout is private. Partition evaluation MAY be pointwise over canonical source
sites; whole-partition validation belongs to that same resolved policy plan and MUST NOT be a second
production evaluator or a trusted extension callback.

Completion freezes the minimal reachable schema closure: reachable symbolic operations, only the
compiler-synthesized operations actually required by the model, and used external operations. It
freezes complete schemas and selected concrete callable values. Analysis and lowering MUST never
consult the live registry. Unused package vocabulary MUST NOT be copied into each normalized model.
The package-level literal inventory remains separate for documentation and coverage audits.

The freeze guarantees registry/schema/callable selection. It does not claim immunity from later
Julia method additions or redefinitions. Julia, package, dependency, and compiler environment
identity participates in executable compatibility, provenance, recompilation, and requalification.

### Snapshot, planning, conflict, and publication law

The ordinary order is:

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

Every due trigger and pure policy reads the common snapshot. Newly created cells and daughters are
ineligible until a later lifecycle invocation. V1 uses integer-MCS cadence only; MCS zero is
initialization. After conflict resolution, a surviving request MAY receive immutable semantic
before and planned-after views derived from the common snapshot and its validated plan. Those views
cannot contain another request's result. Their concrete private representation is not public API.
Mutation-and-rollback evaluation is forbidden.

Exact duplicate requests are deduplicated. Request-local placement/partition and structural
preconditions are planned from the common snapshot, exact finite write footprints are derived, and
the explicit inadmissibility disposition is applied before biological conflict selection. An
inadmissible high-priority request therefore cannot suppress a valid competing request. Incompatible
identity, ownership, site, state, relationship, and topology write footprints of the remaining
requests form compiler-derived conflict sets. The phase policy is `RejectLifecycleAmbiguity` or
`StableLifecyclePriority`. Stable priority selects the unique greatest explicit priority; an equal
greatest priority is an error. Declaration order, effect category, tuple order, ID, slot, group,
launch order, and atomic arrival are not priority. Allocation-dependent state initialization and
its draws occur only after winner selection.

Expected snapshot-relative inadmissibility follows the effect's explicit disposition and produces a
bounded diagnostic. Stale generation, illegal policy, invalid/nonfinite evaluator result,
request/emission/workspace bound violation, generation overflow, analyzed-footprint violation,
backend mismatch, and failed planned/post-commit invariant are nonfilterable. After filtering and
conflict resolution, insufficient cell or relationship capacity aborts the complete valid batch.

Commit is staged publication, not device-crash rollback: validate the complete plan and capacity;
write authoritative ownership, identity, kind, state, relationship, and tracker/index updates in
declared order; validate postconditions; then publish the completed boundary. A failure before
publication exposes no partial scientific state. CorePotts executes resolved structural plans and
contains no biological mechanism branch.

### Identity, workspace, RNG, checkpoint, and status

Cell storage distinguishes never-used, active, and reusable slots, or an exactly equivalent
high-water representation. Allocation uses the common pre-lifecycle free pool, orders surviving
requests by canonical request identity, selects reusable IDs ascending, then fresh IDs above the
high-water mark, and preflights capacity and generation range before mutation. IDs retired in MCS
`t` cannot be reused until MCS `t + 1`. A fresh identity receives generation one; a reused identity
advances the consumed generation exactly once at allocation. Transition and the retained parent
preserve identity/generation.

Every compiled model has one positive, structurally resolved `max_cells` capacity, defaulting to
the number of lattice sites and never exceeding that number. CPU and GPU identity tables,
cell-owned state, allocation plans, and transaction workspaces are allocated to this fixed capacity
before execution and MUST NOT resize. Initialization fails when its finite-cell identities exceed
`max_cells`. If a complete surviving transaction batch needs more identities than the common
pre-lifecycle free pool, execution reports `CellCapacityFailure` and gracefully terminates at the
phase boundary with the previously published scientific state unchanged. Host allocation, dynamic
growth, partial admission, and a CPU-only fallback are forbidden.

Lifecycle request banks, compaction/sort/conflict storage, allocation plans, policy plans, tracker
repair, relationship consequences, and status storage MUST have finite compiler-proven bounds and
reusable backend-adaptable workspace. Statement names, resource names, IDs, generations,
occurrences, slots, and capacities remain values. Only structural policy/evaluator/storage/plan
classes may specialize.

Lifecycle randomness extends the semantic address contract with honest cell and lifecycle/model
entities. Cell draws include ID and generation. Model-domain creation uses qualified rule and
bounded occurrence before allocation. Destination initialization occurs only for survivors and
includes destination identity/generation, descendant role, policy, and lexical draw. Filtering,
conflict loss, grouping, declaration permutation, and launch decomposition cannot shift unrelated
draws. Address representation changes require an RNG contract-version change.

Stable checkpoints occur only at finalized MCS zero or settled completed-MCS boundaries. They
include ownership, slot status/high-water/reuse, kinds, generations, cell/auxiliary state,
relationships and endpoint generations, reconstructible tracker facts, MCS, parameters, seed/RNG
contract, frozen policy/stream identity, and executable fingerprint. Request queues, staging,
workspace, and backend events reconstruct. Same-profile continuation reproduces uninterrupted
lifecycle state and trace.

The closed status translation is:

| Failure class | Authority |
|---|---|
| filtered inadmissibility | device bounded diagnostic; no phase failure |
| inadmissibility under `ErrorOnInadmissible` | device `LifecycleInadmissibilityFailure` |
| static ambiguity, missing/illegal policy, prelaunch capability mismatch | host construction/admission diagnostic |
| runtime conflict | device `LifecycleConflictFailure` |
| cell/relationship capacity | device `CellCapacityFailure` / `RelationshipCapacityFailure` |
| stale generation | device `StaleGenerationFailure` |
| generation exhaustion | device `GenerationOverflowFailure` |
| invalid/nonfinite evaluator | device `LifecycleEvaluatorFailure` |
| bound or footprint violation | device `LifecycleFootprintFailure` |
| planned/post-commit invariant failure | device `LifecycleInvariantFailure` |
| backend execution failure/runtime capability loss | host-synthesized `LifecycleBackendFailure` with original cause |

The host translates status once at the declared phase boundary. It cannot reinterpret device
science or choose a different semantic offender.

### Portability, ownership, conformance, and stop rule

Sequential and checkerboard invoke one immutable engine-neutral lifecycle plan. KernelAbstractions
is the portable kernel boundary; AcceleratedKernels or custom kernels may implement bounded
compaction, scans, and sorting when they preserve the contract. GPU planning and commit perform no
host scientific work, scalar indexing, or fallback. One explicit phase-end synchronization and
bounded status transfer is permitted. The backend-neutral lifecycle harness MUST functionally run
all five effects and every admitted built-in policy family on the selected real GPU witness.

Compiler responsibilities remain visibly separated among public syntax, completion/normalization,
analysis, lowering/inspection, CorePotts structural protocol, transaction runtime, shared
state/workspace/tracker/relationship/RNG/checkpoint services, and tests. Exact private files and
type names are not normative. Lifecycle work MUST NOT be placed in a mechanism-named module or
recombined into a central catch-all executor.

G5-L uses these bounded checkpoints:

1. G5-L0: independent specification clearance; no implementation with a P0/P1 finding.
2. G5-L1: syntax, schemas, qualified binding, frozen closure, analysis, diagnostics, inspection.
3. G5-L2: transaction IR and complete sequential CPU reference.
4. G5-L2Q: one fresh-context code-quality, architecture-quality, and semantic/test-DRYness review
   of the exact G5-L2 checkpoint, as specified by the
   [G5-L2Q gate](../design/audits/symbolic-potts-v1-g5-l2-quality-gate.md). G5-L3 remains closed
   until the review returns zero P0 and zero P1 findings.
5. G5-L3: shared checkerboard CPU execution and deterministic bounded workspaces.
6. G5-L4: real functional GPU witness and neutral downstream extension proof.
7. G5-L5: fast/qualification profiles, source/performance audit, and R2 handoff.

Required exit evidence covers exact compiler rejection and inspection; every effect/policy on CPU;
snapshot, inadmissible-competitor, conflict, capacity, allocation, generation, failure atomicity,
ownership and independent
tracker/relationship recomputation; RNG/replay/checkpoint; sequential/checkerboard equivalence;
one external module exercising trigger, placement, partition, and state transform with zero central
executor edits; real GPU execution; and bounded allocation, locality, inference, specialization,
workspace, and measured performance. Fast tests share fixtures with explicit expensive
qualification rather than duplicating assertions or creating evidence-freshness bureaucracy.

When G5-L and the existing G5 surface/relationship work pass, one fresh `R2Execution` reviews the
whole boundary. If R2 clears, work MUST stop before G6 for owner review. Wortel, Merks, focal-model
migration, polished docs, a second evaluator, a legacy oracle, a new CI evidence system, and broader
lifecycle vocabulary are outside G5-L.

G5-L2Q is deliberately narrower than R2. It reviews the complete sequential transaction runtime
before concurrency can multiply a weak abstraction. It does not require checkerboard, GPU, long
statistical, or documentation evidence. It MUST NOT create a second evidence system or reopen
accepted lifecycle semantics. Clearance authorizes only G5-L3.
