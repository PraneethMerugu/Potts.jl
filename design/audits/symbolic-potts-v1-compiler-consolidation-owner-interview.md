# Symbolic Potts V1 Compiler Consolidation Owner Interview

Date opened: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: complete; Rounds 1 through 4 accepted

Research basis:

- [`symbolic-potts-v1-compiler-capability-and-construction-audit.md`](symbolic-potts-v1-compiler-capability-and-construction-audit.md)
- [`symbolic-potts-v1-architecture-redirection-owner-interview.md`](symbolic-potts-v1-architecture-redirection-owner-interview.md)
- [`symbolic-potts-v1-architecture-redirection-spec-audit.md`](symbolic-potts-v1-architecture-redirection-spec-audit.md)
- [`spec/symbolic-potts-v1-architecture-redirection.md`](../../spec/symbolic-potts-v1-architecture-redirection.md)
- [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md)

## Purpose

This bounded interview freezes the remaining compiler-construction decisions required for an
autonomous Symbolic Potts V1 implementation. It does not reopen the accepted product, scientific
taxonomy, two-engine architecture, ModelingToolkit/ProcessBigraphs boundary, clean-break mandate,
or proof-model scope.

Accepted answers become design authority for a normative compiler-construction specification.
They do not authorize implementation until:

1. all interview rounds close;
2. the compiler-construction specification is written;
3. the specification passes an autonomy and contradiction audit; and
4. the owner gives explicit implementation send-off.

## Fixed context

The following are already accepted and are not interview choices:

- Symbolics is the canonical public expression representation.
- CorePotts contains no Symbolics, units, registries, source ASTs, or host closures.
- Runtime device execution has no mechanism-name switch or primary opcode interpreter.
- Built-in and external science lower through one qualified descriptor protocol.
- Repeated scientific instances remain data rather than one heterogeneous tuple element per
  occurrence.
- Sequential CPU and portable checkerboard consume the same descriptors.
- KernelAbstractions is the portable custom-kernel boundary.
- Wortel, Merks, and focal-point plasticity are integration fixtures, not runtime concepts.

## Planned rounds

1. host IR, analysis, and public/private compiler boundary;
2. descriptor groups and static expression evaluators;
3. state, workspace, relations, and checkerboard planning; and
4. transactions, backend support, conformance fixture, and autonomous send-off gates.

## Round 1 — Host IR, analysis, and compiler boundary

Owner response: **accept all**

### CCI-001 — Indexed host DAG and fact tables

Accepted.

Recommended option: accept.

Completion freezes a qualified source graph. Compilation lowers it into a private indexed
`NormalizedTermGraph` whose model structure is stored as ordinary host data rather than recursive
Julia type parameters.

- Nodes have stable compiler-local IDs, canonical operation identity/version, ordered operands,
  payload/reference kind, canonical key, and source provenance.
- Analysis facts live in explicit tables keyed by node or record ID.
- Host compiler passes use function barriers and avoid specializing on the complete source payload
  or model topology.
- Construction may use host dictionaries and vectors; the executable may not contain them.
- The graph is lowered private compiler data, not a second authoring algebra or public model.

Alternatives considered:

1. retain a recursive typed expression tree as both host and device IR; rejected because compiler
   specialization grows with arbitrary source expression structure;
2. retain Symbolics objects through executable construction; rejected because resource, device,
   canonicalization, and backend legality need an explicit Potts-owned lowering boundary; or
3. reuse private ModelingToolkit compiler IR; rejected because its internals are not a stable
   package integration contract.

### CCI-002 — Semantics-preserving, order-aware normalization

Accepted.

Recommended option: accept.

Symbolics remains canonical through public construction and completion. The private host DAG begins
the execution-lowering boundary.

Normalization may:

- qualify and resolve references;
- canonicalize literals, parameters, identities, and operation names;
- represent source-level associative forms as ordered n-ary nodes;
- intern repeated pure subexpressions where identity and stochastic behavior are unaffected; and
- fold expressions only where exact type, unit, numerical, and replay semantics permit it.

Normalization may not:

- reorder floating-point operands merely because an operation is mathematically commutative;
- reassociate reductions whose order contributes to replay;
- merge or duplicate stochastic draws;
- move reads across a snapshot/stage boundary;
- rewrite stateful operations as pure algebra; or
- use equality saturation as the definition of canonical meaning.

Alternative: enable broad mathematical canonicalization and recover exact replay later. Rejected
because scientific meaning, numerical policy, and executable identity must be preserved by every
compiler pass.

### CCI-003 — Explicit analysis passes with a bounded fact fixpoint

Accepted.

Recommended option: accept.

The compiler runs explicit deterministic analyses for:

- type and shape;
- units and reference conversion;
- parameter role;
- purity and totality;
- resource reads/writes;
- spatial and relationship locality;
- effect class and bound;
- scientific category;
- stage and ordering;
- RNG sites;
- state/workspace/checkpoint participation; and
- engine/backend capability with rejection reasons.

Analyses may use a bounded monotone fixpoint where facts are mutually dependent. An unresolved
safety fact is a compilation rejection, not an implicit conservative success.

Built-in and registered operation schemas contribute typed transfer rules. The compiler validates
their results against the expression, declared resources, selected engine, and backend. A schema
cannot bypass analysis by asserting purity, boundedness, or device legality.

Alternatives considered:

1. infer through ad hoc recursive traits directly on public statement types; rejected because it
   couples analysis to source representation and obscures pass invariants; or
2. allow arbitrary plugin analysis callbacks to return trusted booleans; rejected because the
   extension boundary must remain analyzable and auditable.

### CCI-004 — Public semantic extension schema, private compiler IR

Accepted.

Recommended option: accept.

The stable extension surface consists of:

- public Potts statement and symbolic-operation construction;
- versioned registration schemas;
- qualified identity, provenance, diagnostic, and inspection records required by extensions;
- typed state, workspace, resource, footprint, stage, effect, RNG, adaptation, and checkpoint
  schemas;
- descriptor/group construction hooks; and
- CorePotts's qualified runtime descriptor protocol.

Concrete host graph nodes, mutable builders, analysis caches, grouping keys, schedules, kernel
builders, and compiler pass types remain private.

The package may publicly expose read-only qualified inspection views without making the internal IR
representation an API promise.

Alternative: publish and stabilize the concrete compiler IR so downstream extensions construct it
directly. Rejected because it would prevent internal compiler evolution and repeat the coupling
problem the clean break is intended to solve.

### CCI-005 — MetaTheory excluded from V1

Accepted.

Recommended option: accept.

- MetaTheory is not added to PottsToolkit or CorePotts dependencies or weak dependencies in V1.
- V1 normalization uses explicit deterministic rules with documented semantics and complexity.
- TermInterface compatibility may be implemented where independently useful.
- A post-V1 research environment may evaluate bounded equality saturation only for pure, total,
  unit-compatible, RNG-free, stage-local expressions.
- Any future adoption requires a device-aware cost model and measured compile/runtime improvement.
- MetaTheory can never own semantic analysis, stochastic identity, resource inference, scheduling,
  transactions, checkpointing, or device execution.

Alternatives considered:

1. a MetaTheory weak-dependency optimizer in V1; rejected because it adds another compiler path
   before a baseline and cost model exist; or
2. MetaTheory as the canonical normalizer; rejected because equality saturation is not the product
   semantics and its current recommended API line is still moving.

## Round 1 response format

The owner may:

- accept all five recommendations;
- accept selected decisions by ID; or
- replace any recommendation with a concrete alternative and rationale.

Owner accepted all five recommendations.

## Round 2 — Descriptor groups and static expression evaluators

Owner response: **accept all**

### CCI-006 — Open concrete descriptor protocol

Accepted.

Recommended option: accept.

CorePotts defines a qualified generic descriptor protocol, not a closed biological descriptor
inventory.

Each descriptor or descriptor group provides concrete methods equivalent to:

- state and workspace requirements;
- resource access and bounded footprint;
- stage participation and dependencies;
- engine/backend support;
- proposal evaluation;
- bounded effect or request emission;
- stage application;
- adaptation;
- logical checkpoint encoding/reconstruction; and
- inspection metadata.

The central executor dispatches only through these generic operations. It contains no concrete
family union, mechanism enum, biological `isa` ladder, or fallback callback.

Built-in descriptor types may live in CorePotts only when they express general execution semantics
rather than a named biological mechanism. Scientific descriptor types may be defined by
PottsToolkit or a downstream extension.

Alternative: keep a central union of all descriptor types to simplify GPU inference. Rejected
because every extension would require editing CorePotts, making the accepted downstream
conformance test impossible.

### CCI-007 — Homogeneous groups; occurrence data never shapes the program type

Accepted.

Recommended option: accept.

A descriptor group key includes only structural execution facts such as:

- concrete descriptor/evaluator strategy;
- expression structure where relevant;
- stage and access policy;
- state/workspace layout class;
- request/effect strategy; and
- selected backend-kernel strategy.

Numerical coefficients, runtime parameter indices, cell kinds, targets, qualified statement IDs,
relation handles, and other occurrence values remain fields in a homogeneous backend-compatible
instance buffer.

The program may contain a heterogeneous tuple of groups because specialization proportional to
distinct strategies `G` is intentional. It may not contain a heterogeneous tuple of all statement
occurrences `N`.

The compiler reports:

- total occurrences `N`;
- group count `G`;
- instance count per group;
- evaluator node count per expression group;
- expected kernel specializations; and
- the exact group key facts responsible for separation.

Alternative: place every descriptor occurrence in a generated tuple for maximum inlining. Rejected
because compile time and code size then scale with model size even when execution strategy is
identical.

### CCI-008 — Qualification-selected static evaluator representation

Accepted.

Recommended option: accept.

The external contract freezes the static evaluator semantics and protocol, but does not prematurely
freeze one private Julia representation.

Before biological mechanisms are rebuilt, an implementation slice compares:

1. recursive typed trees grouped by structural shape;
2. balanced or bounded n-ary typed trees; and
3. a compile-time-unrolled static instruction/SSA representation.

The comparison uses the same operation tags, instance data, evaluation context, and semantic test
vectors. It measures:

- host construction and compilation growth versus expression nodes and group count;
- method-instance or equivalent specialization growth;
- generated host and device code size;
- inference quality;
- register and local-memory use where available;
- CPU and available-GPU kernel compilation;
- first-launch and warmed runtime; and
- numerical and stochastic equivalence under the declared policy.

The autonomous implementation selects the simplest candidate satisfying all mandatory gates. The
selection and evidence are recorded in a short design decision record before mechanism work
continues.

Mandatory gates:

- no runtime opcode dispatch;
- no device allocation, exception, closure, Symbolics value, or abstract dispatch;
- repeated instances sharing structure reuse one evaluator specialization;
- expression depth does not create pathological compiler recursion;
- registered device-valid operations can participate without editing a central operation switch;
- every claimed backend compiles the representative evaluator fixture; and
- the choice stays private so a later equivalent representation can replace it.

RuntimeGeneratedFunctions and Symbolics `build_function` are controls for host equation/codegen
comparison only. They are not candidates for the CPM device evaluator unless a separate
cross-backend proof establishes that use.

Alternative: choose the current recursive tree immediately. Rejected because the existing branch
has not measured its specialization growth or device behavior, which is precisely the
half-finished-IR risk this interview exists to remove.

### CCI-009 — Versioned operation tags, with no runtime registry

Accepted.

Recommended option: accept.

Every ordinary expression operation has:

- a stable semantic identity and schema version;
- arity and operand constraints;
- result type/shape/unit transfer rules;
- purity and totality rules;
- state/resource/locality inference;
- backend capability;
- canonical serialization; and
- one or more concrete device-valid operation tags.

Built-in tags use ordinary methods. A registered symbolic operation supplies its host schema and
concrete tag implementation before completion freezes the registry snapshot.

Lowering resolves operation identity to a concrete tag. The executable contains tags and data, not
symbols, dictionaries, callbacks, or registry lookups.

External operation tags must satisfy the same evaluator qualification tests as built-ins. A tag
may declare a backend unsupported, but no unsupported operation may silently fall back to host
execution.

Alternative: retain one central operation-symbol switch in CorePotts. Rejected because it makes the
ordinary vocabulary nominally closed in exactly the way that blocked external scientific terms.

### CCI-010 — Group-level kernel baseline and evidence-driven fusion

Accepted.

Recommended option: accept.

The baseline execution boundary is a descriptor group or a small compiler-owned family of
compatible groups.

- KernelAbstractions kernels specialize on concrete group strategy and execution context.
- Repeated instances execute through the group's homogeneous buffer.
- Adjacent groups may be fused only when snapshot, stage, RNG, resource, numerical-order, and
  diagnostic semantics are preserved.
- Fusion must reduce measured launch, transfer, or memory cost without unacceptable compile-time,
  register, occupancy, or code-size growth.
- The unfused execution plan remains semantically authoritative and inspectable.
- A backend extension may substitute a measured kernel while preserving the same descriptor and
  stage contract.

The compiler does not generate one bespoke giant kernel type containing the complete scientific
model. It also does not force one kernel launch for every individual statement occurrence.

Alternative: whole-model fusion by default. Rejected because it recreates model-shaped types,
causes broad recompilation, complicates extensions, and makes backend performance fragile.

### CCI-011 — Device totality and runtime-validation boundary

Accepted.

Recommended option: accept.

Device evaluators and kernels do not throw.

- Structural invalidity, unsupported operations, units, capacities, and backend incompatibility
  fail during completion or compilation.
- Runtime parameter constraints that can be checked before launch are validated during `init`,
  `remake`, or settled parameter update.
- Expected proposal invalidity becomes a typed result such as rejection, null attempt, or bounded
  request disposition rather than an exception.
- A genuinely data-dependent stage failure uses a preallocated status buffer with stable error
  identity and is surfaced after synchronization without partially publishing the stage.
- Debug bounds/invariant checks may use a qualified debug kernel policy, but production device
  semantics cannot depend on exceptions.

Alternative: leave defensive `throw` calls in evaluator methods and rely on GPU compiler behavior.
Rejected because exception paths impair portability and make failure semantics backend-dependent.

## Round 2 response format

The owner may:

- accept all six recommendations;
- accept selected decisions by ID; or
- replace any recommendation with a concrete alternative and rationale.

Owner accepted all six recommendations.

## Round 3 — State, workspace, relations, and checkerboard planning

Owner response: **accept all 6**

### CCI-012 — Universal state plus typed auxiliary blocks

Accepted.

Recommended option: accept.

CorePotts directly owns only state required to interpret every CPM program safely:

- lattice ownership and topology;
- entity identity, kind, generation, and liveness/retirement status required by ownership
  semantics;
- settled MCS, batch, and proposal position;
- semantic RNG continuation state;
- accepted/rejected/null counters where universally required; and
- universal capacity/validity data required by both engines.

Scientific state is declared as typed auxiliary blocks. A block schema includes:

- stable semantic identity and schema version;
- entity domain and index space;
- element type, shape, capacity, and layout constraints;
- initialization and validation;
- persistence and lifecycle behavior;
- allowed read/write policies;
- backend adaptation;
- settled-state export;
- logical checkpoint encode/reconstruct; and
- inspection rendering.

The host compiler resolves semantic state identities to compact typed handles. Device evaluators
receive handles or concrete block views, not dictionaries or symbols.

Program, runtime state, checkpoint, adaptation, and inspection recurse over the general block
structure. Adding activity, a field, history, elongation data, relationships, or downstream state
does not add a central program/runtime/checkpoint field.

Alternative: one generic runtime dictionary of arbitrary state blocks. Rejected because it creates
dynamic lookup and abstract storage at the device boundary.

### CCI-013 — Declared reusable workspaces with explicit lifetimes

Accepted.

Recommended option: accept.

Every descriptor group and engine stage declares its workspace requirements before executable
construction.

A workspace requirement specifies:

- concrete element and container type;
- dimensions/capacity as structural expressions;
- initialization/reset policy;
- stage lifetime;
- access ownership and concurrency policy;
- backend adaptation; and
- whether safe sharing is permitted.

The compiler allocates all runtime workspaces during executable construction or `init`, never
inside warmed proposal or stage execution. It may alias workspace only when lifetime and access
analysis prove non-overlap. Otherwise, blocks remain separate and inspectable.

Workspaces never enter logical checkpoints or scientific saved state. There is no general-purpose
device allocator, arbitrary byte arena, or user-visible scratch dictionary in V1.

Alternative: manually reuse a few named global scratch arrays. Rejected because new descriptors
would require central workspace edits and accidental lifetime overlap would be invisible.

### CCI-014 — Exact spatial-relation semantics and named roles

Accepted.

Recommended option: accept.

V1 admits these canonical finite translation-invariant neighborhood constructors:

- `VonNeumann(r)` contains every nonzero integer offset `δ` with
  `sum(abs, δ) ≤ r`;
- `Moore(r)` contains every nonzero integer offset `δ` with
  `maximum(abs, δ) ≤ r`;
- `AxialRays(r)` contains offsets with exactly one nonzero coordinate whose absolute value is in
  `1:r`;
- `DistanceShells(k)` contains offsets belonging to the first `k` distinct positive squared
  Euclidean distances on the integer lattice; and
- `ExplicitOffsets(offsets)` stores a validated finite offset set.

All relations:

- exclude the zero offset unless a separate operation explicitly permits self-access;
- canonicalize offsets lexicographically after removing duplicates;
- validate dimensionality and bounded representability;
- define boundary handling separately from their offset set; and
- preserve their exact constructor semantics in inspection and fingerprints.

This resolves the current ambiguity: historical axial-ray behavior for `VonNeumann(r > 1)` becomes
`AxialRays(r)`. It is not silently retained under the Von Neumann name.

Models bind distinct named relations to roles such as:

- proposal;
- contact;
- surface/boundary;
- connectivity;
- state or neighborhood query;
- field stencil/gradient; and
- relationship contact or creation.

The checkerboard conflict relation is compiler-derived from actual read/write footprints. It is
not a user-authored scientific relation and is never assumed to equal Moore.

Alternative: retain only Von Neumann and Moore and let each mechanism reinterpret radius.
Rejected because identical syntax would then have mechanism-dependent meaning and the compiler
could not derive trustworthy footprints.

### CCI-015 — Closed footprint algebra

Accepted.

Recommended option: accept.

The compiler represents locality through a small closed footprint algebra:

- finite spatial offsets relative to source, target, or an explicitly named anchor;
- unions and Minkowski sums of finite spatial footprints;
- per-entity owner/cell access induced by spatial observations;
- bounded incident-relationship access;
- exact entity-index access;
- exclusive-owner access;
- global deterministic reduction;
- ordered bounded deferred emission; and
- host equation/process boundary.

Built-in operation schemas derive footprints compositionally. Registered schemas provide typed
transfer rules whose result must be expressible in this algebra and validated against declared
state, stage, and effect bounds.

An expression whose access remains data-dependent or unbounded cannot execute as an ordinary
checkerboard proposal term. It must lower to a qualified deferred stage with bounded emission or
declare checkerboard incompatibility.

The compiler distinguishes reads from exclusive writes, commutative integer effects,
deterministic reductions, and deferred requests. Shared reads do not become write conflicts.

Alternative: have each descriptor return an opaque “safety radius.” Rejected because one radius
cannot express anchors, asymmetric stencils, entity/relationship access, or different concurrency
policies.

### CCI-016 — Deterministic realized-domain coloring

Accepted.

Recommended option: accept.

The V1 correctness baseline derives a finite conflict displacement set from the union and
composition of all spatially exclusive proposal footprints.

For a selected lattice shape and boundary topology, the compiler:

1. visits sites in canonical linear-index order;
2. computes already-colored conflicting sites from the displacement set without materializing a
   general graph edge list;
3. assigns the smallest available color deterministically;
4. verifies every conflict edge has distinct endpoint colors;
5. groups sites by color in backend-compatible buffers; and
6. includes the coloring algorithm identity, displacement set, color count, and site ordering in
   inspection and executable identity.

The expected planning complexity is `O(V × D)` time and `O(V)` storage for `V` lattice sites and
`D` conflict displacements. Coloring is constructed once per executable structural configuration,
not per MCS.

A formulaic modular coloring may replace this baseline only when the compiler proves it correct for
the exact finite shape, periodicity, and displacement set and reports the qualified algorithm
identity. It must not assume that a radius-based modulus is safe across a periodic seam.

Residual exclusive conflicts not eliminated by coloring use the accepted canonical
`(priority_draw, semantic_proposal_id)` winner rule over every claimed resource. Device completion
order never selects a winner.

Alternative: hard-code two-color or four-color checkerboards. Rejected because configurable
proposal, contact, connectivity, field, and external footprints require derived scheduling.

### CCI-017 — General incremental tracker protocol

Accepted.

Recommended option: accept.

Derived quantities used in proposal hot paths must be maintained by typed tracker descriptors
rather than recomputed through whole-lattice or whole-relationship scans.

A tracker declares:

- source state and relation;
- maintained value domain and storage;
- initialization/rebuild algorithm;
- local proposal delta/update rule;
- stage snapshot and commit visibility;
- concurrency policy;
- validation/recomputation oracle for tests;
- adaptation and checkpoint policy; and
- inspection/cost information.

Volume, boundary/surface, moments, centroids, elongation tensors, field summaries, history indices,
and relationship incident indices may use this protocol. They are not named fields in the central
program.

Trackers whose state is a deterministic function of logical state may either be checkpointed or
reconstructed according to their declared policy. The choice is included in checkpoint and replay
inspection.

The compiler may fuse tracker updates with commit kernels when semantics and measurement justify
it. The reference unfused update remains testable.

Alternative: special-case the common trackers in the proposal loop. Rejected because every new
scientific term would pressure the central executor to acquire another mechanism-shaped cache.

## Round 3 response format

The owner may:

- accept all six recommendations;
- accept selected decisions by ID; or
- replace any recommendation with a concrete alternative and rationale.

Owner accepted all six recommendations.

## Round 4 — Transactions, backend claims, conformance, and send-off gates

Owner response: **accept all 6**, with the correction that all GPU tests are backend-agnostic so
the same suite can support a release CI backend matrix later

### CCI-018 — Indexed relationship state and deterministic transactions

Accepted.

Recommended option: accept.

Relationship state is an auxiliary typed block, not a central runtime field. Its general V1
representation contains:

- fixed structural capacity;
- active-slot state;
- normalized endpoint identities and endpoint generations;
- typed payload columns declared by the relationship schema;
- a bounded incident index for each endpoint;
- maximum-degree and endpoint-kind policy;
- deterministic free-slot state; and
- lifecycle/checkpoint metadata.

Proposal evaluation reads the immutable relationship snapshot for its engine batch. Incident
indices make energy and constraint cost proportional to endpoint degree rather than total edge
count.

Mutation uses preallocated typed request buffers. Every request contains:

- request schema/type;
- originating stage and semantic emitter identity;
- canonical request identity;
- normalized endpoints and generations;
- payload or payload update;
- admission/disposition policy; and
- bounded emission position.

At each `RelationshipCommit`, the compiler-selected transaction:

1. deterministically sorts or groups requests by semantic key;
2. normalizes endpoint ordering;
3. collapses identical duplicates;
4. resolves contradictory requests by the declared closed policy;
5. validates endpoint liveness, generation, kind, degree, capacity, and lifecycle;
6. applies removals to the staged index before admitted creations;
7. assigns admitted creations the lowest available slots in canonical request order;
8. validates the complete staged result; and
9. atomically publishes edge state and incident indices.

Accepted-copy creation whose failure does not veto the already accepted lattice copy uses an
explicit deterministic filtered disposition. A process requiring atomic success uses an
unpublished-stage transaction and fails without partial publication. V1 does not retroactively
reinterpret a committed copy through an implicit relationship rollback.

Sequential uses the same transaction with batch size one where immediate sequential visibility is
required. Checkerboard uses snapshot reads and ordered batch publication.

Alternative: copy the complete relationship block and scan every edge for each proposal. Rejected
for both asymptotic and portability reasons.

### CCI-019 — Recursive logical checkpoint and explicit replay classes

Accepted.

Recommended option: accept.

The compiler constructs the checkpoint schema from:

- universal logical CPM state;
- every auxiliary state block's declared logical codec;
- runtime parameters and parameter history;
- semantic RNG seed, replica, stream continuation, and counters;
- completed MCS and settled stage position;
- executable/checkpoint schema identity;
- replay class and backend/configuration scope; and
- integrity checksum.

A descriptor or tracker must declare one of:

- persist its logical state;
- reconstruct it exactly from persisted logical state; or
- exclude it because it is workspace-only.

Restore validates schema, executable compatibility, units/reference policy, capacities,
configuration, and replay class before allocating/adapting private buffers. It reconstructs
workspaces and permitted derived trackers rather than serializing live kernels or scratch state.

The replay classes are:

1. `ExactConfigurationReplay`: exact continuation for the declared engine, backend, scalar/math
   policy, schedule, and compiler/executable identity;
2. `PortableLogicalRestart`: scientifically valid reconstruction on a different admitted
   configuration without trajectory-identity promise; and
3. `StatisticalRestart`: only the explicitly declared distributional/scientific invariants are
   promised.

Checkpoint bytes never contain Symbolics, units, registries, external systems, host closures, live
kernels, events, tasks, or workspace buffers.

Alternative: serialize the complete runtime object graph. Rejected because it would freeze private
storage/kernel implementation and make portability claims accidental.

### CCI-020 — Honest backend support levels

Accepted with a backend-agnostic test-suite correction.

Recommended option: accept.

Backend support is reported per backend and protocol surface, not as one package-wide boolean.

The support levels are:

1. `InterfaceOnly`: adapter or extension exists, but no execution claim is published;
2. `Compiles`: representative admitted descriptors and kernels compile for the backend;
3. `Functional`: bounded stochastic sequential/checkerboard claims applicable to that backend run
   and pass semantic/property tests without host fallback;
4. `ReplayQualified`: the backend passes its declared exact-configuration replay tests; and
5. `PerformanceQualified`: representative workloads have current allocation, transfer,
   synchronization, and warm-execution evidence.

V1 phase exit requires:

- CPU sequential at `ReplayQualified`;
- CPU checkerboard at `ReplayQualified`;
- the generic KernelAbstractions checkerboard path and adaptation protocol implemented;
- at least one available GPU backend at `Functional`, proving the portable device architecture;
  and
- no claim above the evidence actually obtained for CUDA, AMDGPU, or Metal.

CUDA, AMDGPU, and Metal remain package extensions. An extension may remain `InterfaceOnly` or
`Compiles` without being advertised as functional. GPU qualification beyond the one portable
witness is manual, scheduled, or release-level rather than a mandatory multi-vendor pull-request
matrix.

All GPU semantic, conformance, stochastic, replay, checkpoint, and execution tests MUST be authored
once against a backend-agnostic test contract. Backend selection, allocation, adaptation,
synchronization, device discovery, and support-level expectations are injected by a small backend
harness. Scientific model construction, assertions, seeds, semantic schedules, and fixture logic
MUST NOT be copied into CUDA-, AMDGPU-, or Metal-specific test files.

The backend-agnostic suite MUST be runnable:

- locally against any available backend;
- in V1 against the selected functional GPU witness; and
- later as a release CI matrix whose rows supply backend harnesses and environments without
  changing the shared tests.

Backend extensions may add narrowly scoped adapter tests for vendor-specific allocation,
synchronization, error translation, or capability discovery. They may not fork the scientific or
compiler conformance suite.

If no usable GPU execution environment is available during the autonomous phase, lack of the
required portable witness is a genuine external blocker to phase exit; it is not replaced with a
freshness ledger or self-attestation.

Alternative: declare all KA-compatible backends supported after CPU tests. Rejected because source
portability is not device compilation or functional evidence.

### CCI-021 — Exact independent downstream conformance fixture

Accepted with the backend-agnostic GPU-test correction.

Recommended option: accept.

A test-only module outside CorePotts source defines `ExternalWeightedSiteTerm` or an equivalently
simple neutral fixture with:

- a registered statement family;
- one registered pure symbolic site-read operation;
- a versioned concrete Hamiltonian descriptor;
- a declared auxiliary per-site scalar state block;
- a bounded local affected-region rule;
- one reusable observation/reduction workspace;
- adaptation and logical checkpoint behavior;
- qualified inspection and diagnostic rendering; and
- sequential/checkerboard capability rules.

Its Hamiltonian assigns a declared spatial weight to ownership of a site, giving an independently
calculable local copy delta. Its observation reduces weighted occupancy through the declared
workspace. The fixture is deliberately not activity, chemotaxis, volume, contact, elongation,
connectivity, or focal adhesion under another name.

The fixture must:

- complete and compile through the public registration boundary;
- run through public `PottsSystem → executable → problem → solve` flow;
- match independently calculated deltas and observations;
- execute on sequential CPU and checkerboard CPU;
- adapt, checkpoint, restore, and preserve its declared replay behavior;
- compile and run on the phase's functional GPU witness through the same backend-agnostic
  conformance suite intended for later release-matrix rows; and
- require zero edits to CorePotts's central program, engines, proposal loop, checkpoint machinery,
  operation switch, enum, or concrete-family union.

This fixture lands before Wortel, Merks, or focal mechanisms are rebuilt. Failure stops mechanism
work and corrects the compiler boundary.

Alternative: use Wortel as the extension proof. Rejected because a built-in proof model cannot
demonstrate downstream extensibility.

### CCI-022 — Architecture-first autonomous implementation gates

Accepted.

Recommended option: accept.

The autonomous implementation order is:

1. write and audit the normative compiler-construction specification;
2. extract reusable semantic tests before deleting incorrect execution paths;
3. implement host DAG, analyses, diagnostics, and verifiers;
4. implement descriptor/group/state/workspace protocols;
5. run the evaluator qualification slice and record its private representation decision;
6. implement sequential CPU reference execution;
7. implement generic KA checkerboard planning and execution;
8. implement tracker, relationship, lifecycle, and checkpoint protocols;
9. pass the independent downstream conformance fixture, including the GPU witness;
10. rebuild focal, Wortel, and Merks only through the accepted general compiler;
11. complete SciML, ModelingToolkit, equation, observation, and ProcessBigraphs integration
    required by the existing V1 specification;
12. remove the named-mechanism program/runtime and obsolete paths;
13. run functional, exact, property, stochastic, allocation, specialization-growth, backend, and
    integration gates; and
14. audit phase-exit source and public API.

Mechanism work may not move ahead of a failed architecture or external-fixture gate merely to show
visible progress.

The read-only temporary clone of `main` may be inspected for algorithms, performance lessons, and
test intent. It is not executed as an oracle, linked, imported, or used to define compatibility.

V1 on this branch still includes no migration layer, compatibility wrappers, user documentation,
or polished examples. Those remain explicitly outside the phase.

### CCI-023 — Bounded stopping rule and terminal quality audit

Accepted with the backend-agnostic GPU-test correction.

Recommended option: accept.

The autonomous implementation stops for owner input only when:

- two accepted requirements are genuinely contradictory and the normative precedence rules do not
  resolve them;
- an upstream public API required by the accepted design does not exist and only private coupling
  could continue;
- the evaluator qualification candidates all fail a mandatory gate;
- the independent external fixture cannot be expressed without changing the accepted extension
  boundary;
- the required functional GPU witness cannot be obtained from any available execution
  environment; or
- continuing would require a material product or scientific decision not covered by the accepted
  specifications.

Ordinary implementation difficulty, test failures, performance regressions, API details beneath
private boundaries, or a need to rewrite current prototype code are not stopping conditions.

The terminal audit requires:

- all IR and schedule verifiers pass;
- no named biological mechanism appears in CorePotts program, engine, proposal, checkpoint, or
  capability branches;
- no Symbolics, units, registry, dictionary, closure, or abstract descriptor collection reaches
  the executable;
- fixed-`G` specialization growth remains bounded as occurrences increase;
- warmed proposal/stage execution satisfies allocation requirements;
- local terms and trackers avoid unrelated whole-state scans;
- same-configuration replay and stochastic divergence tests match their claims;
- the external conformance fixture passes every required surface;
- Wortel and Merks run stochastically through visible complete public definitions;
- focal relationship transactions pass ordering, capacity, generation, rollback, and lifecycle
  properties;
- SciML/ModelingToolkit/ProcessBigraphs integration gates pass;
- every GPU compiler, semantic, fixture, checkpoint, replay, and stochastic test is shared through
  the backend-agnostic harness and is ready to populate a later release CI backend matrix;
- standard Julia CI passes without evidence freshness machinery; and
- the phase-exit report lists every unsupported backend/operation honestly.

Only after this audit passes may the owner be asked for merge or publication authority.

## Round 4 response format

The owner may:

- accept all six recommendations;
- accept selected decisions by ID; or
- replace any recommendation with a concrete alternative and rationale.

Owner accepted all six recommendations with the backend-agnostic GPU-test correction recorded in
CCI-020, CCI-021, and CCI-023.
