# ProcessBigraphs.jl Runtime Semantics

Status: Normative design; implementation and parity status are tracked separately

Version: 1.5.0

Date: 2026-07-28

Implementation disposition: Phase 15.C C0--C7 passed. ProcessBigraphs 0.4.0 is a qualified
immutable-topology serial internal alpha with `internal_alpha = true` and
`public_release = false`. Phase 16.A/B/D/E/F/G/H are qualified on the working branch: the
solver-neutral protocol, dynamic orchestration transactions, first CorePotts field cutover,
typed domain requests, V3 logical checkpoint, real solver plurality, and bounded runnable
Merks/CNV assemblies and Phase 16.HC high-level authoring pass. Phase 16.C is qualified with
trusted exact-head CPU/Metal/ROCm evidence. Phase 16.I reconciliation and internal-beta
attestation remain open.

Authority: Decisions 0034 and 0036–0040,
`process-bigraph-parity-registry-v1.toml`,
`process-bigraph-high-level-authoring-semantics.md`, and the Phase 15.C and Phase 16 entry
contracts

## Purpose

This specification defines the domain-neutral runtime semantics for `ProcessBigraphs.jl`. The
runtime is an independent Julia implementation targeting feature and observable behavioral parity
with a pinned Process-Bigraph 2.0 baseline. It is also intended to support future whole-cell
development, GPU-resident processes, and deterministic coarse-grained execution through Dagger.

The specification defines behavior, not final constructor spelling. A Julia API may evolve without
changing the contract when canonical model identity and every observable result remain equivalent.

The keywords MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, and MAY are normative.

## Scope and authority

The initial runtime parity pins are:

| Source | Revision | Role |
|---|---|---|
| Process-Bigraph | `305ea826191e9f897f0c6e207bc303bbc44a9eef` (`1.5.0`) | Source-audited behavior and test intent |
| Bigraph-Schema | `4b208e13620e09e877af52ea07273bc9429a3a17` (`1.4.3`) | Source-audited schema, state, apply, divide, and serialization behavior |
| Process-Bigraph paper | arXiv `2512.23754` | Architectural intent and discrepancy research |

The exact feature inventory and evidence status are machine-readable in
`process-bigraph-parity-registry-v1.toml`. A floating branch, unrecorded package installation, or
unversioned web documentation cannot establish or invalidate parity.

Vivarium 1.x is not a compatibility target. Spatio-Flux and vEcoli are pinned application
references, not additional runtime authorities.

CI, tests, examples, attestations, and release tooling MUST NOT install or execute Vivarium,
Process-Bigraph Python, or Bigraph-Schema Python. Exact source pins remain traceability and
semantic-research authorities. Conformance claims are therefore **source-audited feature and
semantic parity**, not live upstream-runtime equivalence.

When pinned paper, code, and tests disagree:

1. the discrepancy MUST be reproduced in a minimal fixture;
2. the Julia project MUST make an explicit, versioned semantic decision;
3. normative Julia behavior MUST be selected for scientific coherence, determinism, and
   composability;
4. materially useful upstream behavior MAY be retained under a named compatibility mode; and
5. reports MUST distinguish normative parity, a Julia improvement, and compatibility behavior.

## Semantic layers

The runtime has five semantic layers:

1. **declaration** — schemas, paths, ports, process/step laws, composites, topology, schedules,
   capabilities, and policies;
2. **compilation** — name resolution, topology validation, exact-time normalization, effect
   validation, placement preflight, and canonical fingerprinting;
3. **execution** — immutable projections, runnable batches, process or step computation, and typed
   effect production;
4. **publication** — deterministic reconciliation, atomic state commit, structural transaction,
   and settled-boundary formation; and
5. **evidence** — observation, checkpoint, diagnostics, replay classification, and conformance
   records.

No façade, adapter, executor, emitter, or device representation may become a second state,
scheduler, topology, or persistence authority.

## AlgebraicJulia structural foundation

The canonical authoring structure is one versioned ProcessBigraph ACSet schema. `ACSets.jl` and
`Catlab.jl` are required Phase 15 dependencies; `AlgebraicRewriting.jl` is required when Phase 16
dynamic structure begins; and `AlgebraicDynamics.jl` is a Phase 17 weak-dependency scientific
extension. AlgebraicJulia supplies structural mathematics and composition, not runtime execution
authority.

The integrated ACSet represents composites, nodes, stores, processes, steps, ports, links,
containment, structural schemas, and stable semantic identities. Structured cospans define typed
open-composite interfaces and composition. Directed wiring diagrams are derived dataflow and
visualization views. Neither structured cospans nor wiring diagrams form a second canonical model.

Ordinary typed Julia constructors and AlgebraicJulia-native authoring MUST lower to the same
canonical ACSet and scientific fingerprint. Category-theory knowledge is not required for ordinary
use. Public APIs MAY accept ACSets and wiring diagrams and expose read-only canonical structure;
semantic mutation, compilation, execution, commit, and persistence remain ProcessBigraphs APIs.

Stable ProcessBigraph identities and canonical paths are semantic. ACSet row numbers, row order,
and traversal order are storage-local and MUST NOT enter canonical ordering, fingerprints, RNG
coordinates, persistence identities, or scientific diagnostics.

Compilation MUST:

1. validate and canonicalize the authoring ACSet;
2. freeze an immutable structural epoch;
3. create indexed execution tables and an exact provenance map from semantic identities to
   compiled locations; and
4. reject ambiguity before any state mutation.

Ordinary numerical hot paths MUST NOT traverse, match, or mutate the authoring ACSet or allocate
because of AlgebraicJulia structure. Committed numerical values and backend-resident arrays remain
ProcessBigraphs-owned state. The canonical ACSet is host-side, placement-independent topology and
metadata; every CPU/device bridge remains explicit, bounded, synchronized, measured, and
fingerprinted.

## Open-composite semantics

### Boundaries and endpoints

An open-composite boundary is a constrained fragment of the versioned ProcessBigraph ACSet schema
with structure-preserving maps into a canonical component ACSet. It is not a separate interface
authority. An ordinary typed Julia declaration MUST lower to this representation before structural
composition.

A boundary exposes selected typed stores as named endpoints. Internal process and step ports remain
bound to those stores. Each endpoint has exactly one declared role:

- `import` permits state to be supplied through a parent or joined component;
- `export` permits state to be exposed to a parent or joined component; or
- `bidirectional` permits both uses.

The role constrains composition but does not duplicate committed state or replace actor-port
direction and effect declarations. For composition validation, `import` is consumer-capable,
`export` is provider-capable, and `bidirectional` is both. A junction that is private in the result
MUST contain at least one provider-capable and one consumer-capable endpoint. A junction explicitly
re-exported as a parent `import` MAY omit an internal provider; one re-exported as a parent `export`
MAY omit an internal consumer. An explicitly declared parent `bidirectional` endpoint supplies both
external capabilities. Multiple providers and consumers are legal only when the ordinary
compatibility and initialization rules pass. Boundary roles do not infer whether an internal actor
reads or writes; actor port effects remain authoritative.

Every connection is an explicit semantic wiring declaration. A name-matching convenience MAY
construct such a declaration, but compilation MUST record and validate the resulting explicit
mapping. Equal names, declaration position, ACSet rows, and traversal order never imply a
connection.

Endpoints joined at one junction MUST agree exactly on every applicable semantic property,
including value type and shape, unit, ontology meaning, update law, persistence, residency, and
transfer requirements. A conversion or bridge with scientific or numerical meaning MUST be an
explicit process or step. Structural composition MUST NOT infer or insert one.

### Mounts, junctions, exports, and initialization

The canonical semantic composition declaration is n-ary and contains:

1. one explicit root semantic identity;
2. a finite set of component definitions mounted under explicit mount keys;
3. explicit semantic junctions connecting compatible exposed endpoints;
4. explicit re-exports, including their roles, that define the resulting parent boundary; and
5. explicit initialization overrides where component defaults do not resolve uniquely.

Pairwise composition, operators, and mutable authoring conveniences MAY exist, but they MUST lower
to this n-ary declaration before validation, canonicalization, identity derivation, or
fingerprinting. Their operation history is nonsemantic.

A component definition identity is distinct from a mounted-instance identity. Each mounted identity
derives canonically from the parent semantic identity and its explicit mount key. Mounting retains
the child's internal namespace below that key; only explicit re-exports enter the parent boundary.
Duplicate mount keys, semantic identities, canonical paths, or incompatible exports in one
namespace MUST fail. Silent renaming, precedence, and collision repair are forbidden.

Every junction has an explicit semantic identity and may join any finite number of compatible
endpoints. The resulting shared store receives the junction identity rather than an identity
selected from a left or right operand.

Initialization is resolved once at the composed root. Component-provided values are defaults or
requirements, not ordered writes. Identical compatible defaults MAY converge. Conflicting defaults
MUST fail unless the parent supplies an explicit valid override. Every resulting store MUST have
exactly one resolved initializer before compilation.

Composition is a pure candidate operation: inputs remain unchanged, the complete candidate is
validated, and no result is published on failure. Joining MUST retain many-to-one provenance from
the junction, originating component and store identities, and boundary maps to the final compiled
location. Provenance is excluded from execution-order decisions.

### Hierarchy, invariance, and lowering

The canonical ACSet preserves arbitrary finite immutable composite containment, mounted identities,
local paths, boundary maps, junctions, and exports. Compilation flattens executable stores, routes,
processes, and steps into indexed tables while retaining exact hierarchical provenance. Ordinary
runtime and checkpoint paths MUST NOT traverse an authoring hierarchy, structured cospan, wiring
view, or composition history.

For equal root identity, mounts, junctions, exports, and resolved initialization, the following are
nonsemantic:

- ACSet row numbering and traversal order;
- declaration, mount, endpoint, and junction order;
- binary composition order and parenthesization; and
- the choice among supported typed, direct ACSet, cospan, or annotated-wiring authoring paths.

Equivalent declarations MUST produce identical canonical structure, structural and model
fingerprints, semantic provenance, compiled execution plans, initial committed state, settled
checkpoints, and serial runtime traces. Optional construction logs MAY differ but are not semantic
provenance or checkpoint data.

### Directed wiring profile

A directed wiring diagram is a read-only derived dataflow and inspection view.
ProcessBigraphs defines a versioned lossless annotated profile containing every semantic identity,
schema, endpoint, effect, boundary map, and route required for exact re-import. Only a diagram that
fully validates against that profile MAY be accepted for canonical lowering. A generic or
information-losing diagram MAY be displayed or analyzed, but compilation MUST reject it rather than
infer missing runtime meaning.

### Static and dynamic boundary

Phase 15 static semantics admit arbitrary-depth immutable open composition and explicit bounded or
convergence-checked iterative regions over fixed structure. Undeclared cycles remain invalid.
Runtime add, remove, divide, move, and rewire operations are Phase 16 structural transactions that
publish a new structural epoch. They may not redefine exact time, same-time visibility, iteration,
reconciliation, or commit semantics established by the serial runtime.

Phase 16 distinguishes canonical orchestration topology from optimized domain topology. The
ProcessBigraph ACSet remains canonical for composites, stores, processes, ports, schedules, and
orchestration relationships. A CorePotts adapter MAY keep cells, lattice sites, domain
relationships, and materials in optimized leaf storage; one ACSet row per cell or voxel is not
required. ProcessBigraphs still owns authorization and atomic publication of changes to either
layer.

## Core semantic values

Final Julia names remain subject to API qualification, but the runtime MUST represent these
semantic values:

- `LogicalTime`, `TimeScale`, `Duration`, and `Deadline`;
- `Path`, `PathSegment`, and stable semantic identity;
- `Schema`, `LeafSchema`, ownership, persistence, residency, update, and division policies;
- `Store`, `CommittedSnapshot`, and typed projection;
- `InputPort`, `OutputPort`, port mapping, bridge, place topology, and link topology;
- temporal `Process` and zero-time `Step`;
- `Composite`, process instance, step instance, and continuation;
- `Delta`, update-law identity, and reconciliation result;
- `StructuralRequest` and `StructuralTransaction`;
- process and state capability declarations;
- `SerialExecutor`, executor protocol, and runnable batch;
- observer, emission record, checkpoint, diagnostic, and failure; and
- canonical model, continuation, and parity fingerprints.

All identity-bearing values MUST have canonical, versioned encodings independent of Julia object
address, dictionary iteration order, thread order, task completion order, and device allocation.

## Exact logical time

### Representation

Global logical time is:

```text
LogicalTime = tick::Integer × TimeScale
TimeScale   = rational physical duration per tick + unit identity
```

The implementation SHOULD use a checked fixed-width integer fast path and MUST either promote or
reject overflow before mutation. Floating-point time is not authoritative.

At model compilation:

1. every declared rational cadence, offset, horizon, delay, and exact adapter boundary is converted
   to a common normalized tick scale;
2. the compiler computes the least common exact scale when it is representable within configured
   limits;
3. non-exact floating declarations MUST provide an explicit quantization policy and tolerance;
4. quantization results become fingerprinted semantic data; and
5. unrepresentable or ambiguous ordering fails compilation.

Physical solvers and device kernels MAY receive `Float32`, `Float64`, or another declared scalar
duration converted from exact ticks. Such conversion cannot alter scheduler ordering or deadline
identity.

### Process timing contract

Each temporal process instance declares:

- stable identity and version;
- last successfully committed logical time;
- next due logical time;
- cadence or a versioned adaptive deadline law;
- whether forced partial intervals are supported;
- minimum and maximum supported interval where applicable;
- input behavior over an interval; and
- continuation needed to reproduce its next deadline.

The next due time MUST be strictly greater than the last committed invocation time. Zero-time
reactive work is a `Step`, not a temporal process.

An adaptive process returns its proposed next deadline as part of a successfully validated effect.
The deadline becomes visible only with that event's atomic commit. Invalid, past, non-finite after
conversion, or unrepresentable deadlines fail the event.

### Horizon and partial intervals

For a requested end time `T`:

- if the next due event is at or before `T`, it executes normally;
- if completion at exactly `T` requires advancing a process from its last committed time by less
  than its nominal interval, the process receives the actual elapsed duration;
- a process that declares partial advancement unsupported is not invoked partially; the selected
  horizon policy MUST either stop at the prior settled boundary or reject the request before
  mutation; and
- passing the nominal interval while committing at a shorter time is forbidden in normative mode.

## Imminent-event scheduler

### Normative event algorithm

At a settled boundary with current logical time `t` and target horizon `T`, the production serial
reference executor follows:

```text
while t < T:
    t_event = minimum eligible process deadline, constrained by the horizon policy
    due = all process instances with deadline == t_event
    event_identity = derive without advancing committed event position

    common = immutable committed-state projection carried to t_event
    invocations = validate and bind every due process against common
    process_results = executor.compute(invocations)

    candidate = reconcile all temporal deltas deterministically
    validate all proposed deadlines and process continuations into candidate
    execute changed-input Step layers and admitted iterative regions within candidate
    validate required observations and checkpoint eligibility within candidate
    atomically publish candidate state, clocks, continuations, event position, and records

    t = committed t_event
```

State has no implicit evolution between events. “Snapshot at `t_event`” means the state resulting
from every committed event strictly before `t_event`, carried to that logical time.

No intermediate temporal result, Step layer, iteration, required observation, or checkpoint hook is
a settled commit. They form one unpublished candidate. Internal candidate snapshots may feed later
Step layers, but a failure anywhere before final publication leaves the previously settled runtime
unchanged. An exact horizon with no
process event MAY publish an unchanged settled snapshot at that time; it does not create a process
event or consume semantic RNG identity.

The pinned upstream deferred sample-and-hold behavior is not normative. If implemented, it MUST be
selected by a fingerprinted compatibility mode and MUST NOT share normative conformance results.

### Same-time process batch

Every process due at one event time:

- reads one common immutable pre-commit snapshot;
- receives only its declared input projection;
- cannot observe another same-time process's delta;
- returns effects without publishing them;
- is semantically unordered relative to other compatible processes in the batch; and
- is reconciled by semantic identity and update law, never completion order.

If a process requires another process's new value at the same logical time, the dependency MUST be
modeled as a `Step`, an explicit subsequent event, or a declared iterative construct.

Priorities MAY select among otherwise independent future deadlines or define an explicit
noncommutative law where the specification permits it. Priority MUST NOT silently grant
same-batch read-after-write visibility.

## Process and Step

### Process

A `Process` represents temporal evolution over a positive interval. It declares typed ports,
timing, capabilities, effects, continuation, RNG use, failure behavior, and interval input
semantics.

A process invocation is conceptually:

```text
invoke(process, immutable_inputs, t_start, t_end, semantic_context)
    -> deltas, structural_requests, next_deadline, continuation, diagnostics
```

The invocation MAY mutate private scratch memory and engine-owned transaction buffers. It MUST NOT
mutate committed store leaves, published topology, another process continuation, or an observer.

### Step

A `Step` is zero-time ordered or reactive computation at a logical time. Steps share the port,
snapshot, delta, capability, failure, and continuation contracts of processes, but are scheduled
by an explicit dependency DAG rather than a temporal deadline.

Step dependencies are compiled from declared data dependencies and explicit workflow edges. At
runtime:

1. steps whose declared inputs changed become eligible;
2. all ready eligible steps in one DAG layer read one common candidate-layer snapshot;
3. the executor may compute the layer concurrently;
4. the runtime reconciles the layer into the unpublished event candidate;
5. downstream steps become eligible only through declared changed inputs;
6. the workflow reaches quiescence before event publication; and
7. a fingerprinted activation bound fails the event if quiescence is not reached.

Silent inputs may establish dependencies without appearing in an adapter's user payload, but they
remain visible in inspection and fingerprinting.

Undeclared cycles fail compilation. Iteration requires a named, fingerprinted construct that
declares initial state, body graph, deterministic order, maximum iterations, convergence predicate,
norm/tolerance when applicable, and nonconvergence policy. Bounded-only iteration omits the
predicate but not the hard bound. Executor priority is not a cycle-breaking semantic.

## Hierarchical state and schemas

### Store

The logical store is a rooted, versioned hierarchy addressed by stable typed paths. A path is a
sequence of canonical segments; text display is not its identity. Paths MUST support deterministic
comparison, hashing, serialization, and prefix queries.

Committed snapshots are immutable in meaning. The runtime MAY implement them through structural
sharing, copy-on-write leaves, versioned buffers, or device-resident storage, provided no process
can observe a partial commit or mutate an earlier snapshot.

Each committed version records:

- monotonically ordered commit identity;
- exact logical time;
- canonical model and topology identity;
- parent version where applicable; and
- state and structural transaction fingerprints.

### Structural schemas

Every state node has a structural schema. A leaf schema independently declares:

- canonical value or element type;
- scalar, shape, rank, and permitted dynamic dimensions;
- default or required initialization;
- optional nominal semantic identity;
- unit and ontology metadata;
- owner and access policy;
- conservation or balance law;
- update-law identity and version;
- division/partition law;
- persistence and continuation class;
- residency and allowed projection policy;
- validation constraints; and
- canonical serialization codec.

Julia type alone is insufficient as the runtime schema. Unitful wrappers are not required in hot
arrays; canonical numeric values and unit metadata are validated at boundaries.

Schema realization, defaulting, validation, migration, and canonical encoding MUST be deterministic.
Missing required values, incompatible shapes, illegal ownership, or unavailable codecs fail before
the affected commit.

## Ports, topology, and composites

### Ports and wiring

Processes and steps declare named, typed input and output ports. A port includes schema
requirements, access/effect mode, interval input behavior, optionality, cardinality, residency
requirements, and semantic identity.

Composite wiring binds ports to stable store paths or admitted bridge transformations. Compilation
rejects:

- unbound required ports;
- direction, schema, unit, ownership, or cardinality mismatches;
- writes through read-only inputs;
- ambiguous wildcard expansion;
- hidden unit or residency conversions;
- topology references outside the composite interface; and
- multiple writers without a compatible update law.

Bridges are typed, versioned transformations. Their computation, transfer, loss, precision, and
failure behavior are visible and fingerprinted.

### Place and link topology

The canonical ACSet maintains distinct, jointly validated views:

- **place topology** describes containment, parent/child relationships, and the hierarchical state
  namespace; and
- **link topology** describes port connectivity, shared references, bridges, and non-containment
  relationships.

Changing one view does not implicitly change the other. Every coupled change is an explicit
structural transaction.

### Composites

A composite owns declarations and interfaces, not an independent clock. Nested composites lower
into one canonical runtime graph with one logical-time authority and one transaction protocol.
Private paths remain inaccessible outside the declared interface.

Equivalent explicit and nested constructions MUST have the same scientific fingerprint after
canonical lowering. Structured-cospan composition and ordinary typed constructors MUST produce
isomorphic canonical ACSets and identical semantic fingerprints. Authoring provenance MAY retain
the original nesting and presentation form.

## Typed deltas and update algebra

### Delta

Every state effect is a typed delta containing:

- target path and target schema identity;
- update-law identity and version;
- typed payload or transaction-buffer reference;
- producing process/step and event identity;
- optional algebraic key or index domain;
- residency and precision classification; and
- canonical evidence metadata.

A delta is not permission to mutate. Publication occurs only after complete batch reconciliation
and validation.

### Update-law declarations

The built-in algebra MUST remain small and versioned. It is expected to include, at minimum,
validated forms of:

- additive accumulation;
- multiplicative accumulation where scientifically justified;
- unique single-writer replacement;
- keyed map or record update;
- indexed array update with explicit overlap rules;
- set insertion/removal;
- append with a declared stable order; and
- structural-request collection.

Every built-in and extension update law declares:

- input and output schemas;
- identity element;
- whether it is associative;
- whether it is commutative;
- whether it is idempotent;
- conflict and overlap detection;
- a total ordering rule if noncommutative combination is admitted;
- determinism and numerical-reduction guarantees;
- CPU and named device support;
- persistence encoding;
- interaction with division or ownership changes; and
- semantic version.

Arbitrary merge functions without these declarations are invalid.

### Reconciliation

Reconciliation groups deltas by target and update-law identity. It MUST be invariant to executor
completion order.

- A commutative and associative law MAY use parallel reduction, subject to its declared numerical
  guarantee.
- A noncommutative law MUST provide a scientifically meaningful stable total order or reject
  multiple writers.
- Unique replacement with more than one writer is a conflict unless an explicit winner law is
  declared.
- Mixed update laws on one target are invalid unless a versioned composition law explicitly admits
  them.
- Conflict diagnostics name every producer, path, law, and event.

The reconciled batch is validated as a whole and publishes atomically.

## Structural transactions

Structural requests are computed from the common snapshot and do not alter topology during process
or step computation. After ordinary state/step publication, the runtime validates one structural
transaction against the current committed version and publishes it atomically.

Beginning in Phase 16, typed ProcessBigraphs structural operations lower to
AlgebraicRewriting rules. AlgebraicRewriting may discover candidate matches, but ProcessBigraphs
assigns semantic match identities, validates preconditions, deterministically orders conflicts,
selects the committed match set, and owns publication. Raw unrestricted rewrites are not the stable
runtime or biological API.

The first stable request families are:

- `add`: create a schema-valid node, process, step, port binding, or composite member with a fresh
  stable identity;
- `remove`: retire a target and all explicitly declared owned descendants, continuations, bindings,
  and observations;
- `divide`: create daughters using declared state partition, continuation reconstruction, topology,
  and lineage laws;
- `move`: change place parent while retaining or explicitly transforming stable identity and
  admissible links; and
- `rewire`: change link topology or port bindings without implicit place movement.

Requests are ordered by structural dependency and stable semantic identity, not arrival order.
Validation detects missing targets, stale generations, identity collision, dangling required
links, ownership violations, capacity violations, illegal request combinations, and failed daughter
construction.

If any request or derived repair fails, no part of the structural transaction publishes. `merge`,
`engulf`, `burst`, and unrestricted graph rewrite are deferred until separately specified and
promoted. A successful transaction creates one new immutable structural epoch, canonical
fingerprint, and semantic-identity map. Matching and partial rewrite application are never
observable settled states.

## Continuation, checkpoint, and replay

### Settled boundary

A settled commit boundary exists only after:

1. the temporal batch has committed;
2. the Step DAG has reached declared quiescence;
3. the structural transaction has committed;
4. required invariant checks have passed; and
5. required observer positions have been recorded.

Exact restart is REQUIRED at every supported settled boundary.

### Checkpoint contents

A canonical checkpoint includes:

- schema and format versions;
- upstream parity pins and runtime version;
- canonical model, topology, and capability fingerprints;
- exact logical time and time scale;
- canonical event ordinal and event position;
- committed hierarchical state;
- place and link topology;
- every process and step deadline, timing state, and versioned continuation;
- observer identities, schedules, positions, and typed continuations needed to avoid duplication or
  omission;
- semantic RNG algorithm, address-schema and root-seed identities, plus solver-owned RNG
  continuation where declared;
- lineage and stable identity allocators;
- placement-independent residency requirements;
- compatibility mode and quantization policies; and
- structural epoch, compiled-plan, runtime/observation, continuation, and integrity fingerprints.

The checkpoint is a ProcessBigraphs-owned, versioned envelope. Raw ACSet, structured-cospan, or
wiring-diagram serialization MAY be offered for structural interchange and inspection, but is not
a runtime checkpoint, scheduler continuation, or replay contract. A checkpoint may occur before or
after a complete structural transaction, never during matching or partial rewrite application.

The canonical logical envelope has deterministic encode and decode and is independent from Julia
object serialization and any storage extension. Every already attested reader remains supported;
new authoritative fields require a distinct format version. Phase 15.C qualifies exact compatible
serial restore only.

Every stateful process, step, and observer declares a typed continuation schema, semantic owner
version, canonical codec, validation and fingerprint rules, restore compatibility, and invalidation
rules. Migration requires an explicit registered migration. Serialization of an arbitrary Julia
closure, task, pointer, solver object, device allocation, or untracked `Any` is not an
alpha-qualified continuation contract.

Mid-event checkpoint/restart is not claimed unless every runnable work item, partial result,
transaction buffer, external solver state, and retry disposition has a registered canonical codec.

### Replay classes

Claims use these classes:

- `exact`: identical committed canonical state and semantic diagnostics;
- `numerical`: values satisfy registered error, conservation, and event-order bounds;
- `statistical`: registered ensemble tests pass; and
- `unsupported`: no replay equivalence claim.

Executor-order invariance is REQUIRED. Same-engine/backend exact replay is REQUIRED when declared by
the process and update laws. Cross-backend bitwise identity is not generally required.

## Semantic randomness

Runtime-addressed randomness derives draws from:

```text
(model fingerprint, normalized root seed, process identity, logical time,
 event identity, entity/lineage identity, stable draw site,
 explicit draw index, RNG algorithm and address-schema versions)
```

Thread, worker, task, device lane, declaration storage order, and completion order are not semantic
RNG coordinates.

The core RNG is counter-based. Source line, call order, and an implicit mutable draw counter are not
coordinates. Core bit, integer, and uniform draws are exact under their pinned algorithm.
Transformed distributions declare exact, numerical, or statistical replay. A failed unpublished
event consumes no RNG identity, and retry from the unchanged settled boundary reproduces the same
draws. Observer analysis uses a separate namespace and cannot consume or perturb model RNG.

A process may retain solver-owned RNG state only when the external algorithm requires sequential
continuation. It MUST:

- declare and version that continuation;
- declare invalidation and rescheduling behavior;
- prevent retries from consuming a different semantic stream;
- reconstruct daughter streams through the declared lineage law; and
- publish its replay class.

## Failure and retry

Execution is transactional. Failure during invocation, invocation-result validation,
reconciliation, apply, step execution, continuation validation, structural validation, required
observation, checkpoint formation, or required-record publication MUST NOT expose partial committed
state, clocks, continuation, RNG/event position, observer position, or required records for that
boundary.

A structured failure includes:

- stage and exact logical time;
- model, process/step, path, law, and executor identities where applicable;
- whether computation may have performed external side effects;
- last settled checkpoint identity;
- retry eligibility;
- invalidated continuations; and
- deterministic diagnostic payload.

The Phase 15.C serial policy is deterministic fail-stop and performs no implicit retry. Explicit
retry may begin from the unchanged settled boundary. A later physical executor may automate retry
only for work declared pure and idempotent and only when retry preserves semantic RNG and output
identity. Universal rollback of files, databases, services, or arbitrary foreign code is not
promised.

## Observation and emission

Core provides a declarative read-only observer protocol. Before execution, an observation plan
assigns every observer a stable identity, exact schedule, declared projection, output schema,
typed continuation, and required or optional policy. An observer:

- sees only its declared immutable candidate-snapshot projection at an eligible settled boundary;
- cannot mutate state, topology, scheduler, RNG, or process continuation;
- has versioned output identity and continuation;
- declares whether failure is fatal, retryable, or noncritical; and
- cannot make task completion order scientifically observable.

Required in-memory records are validated and published atomically with the event. Observation does
not change the scientific model fingerprint; a separate runtime/observation fingerprint records the
plan. Memory sinks beyond the required core record, SQLite, Parquet, dashboards, networks, and
visualization emitters are non-atomic extensions with explicit idempotency and retry behavior.
Output volume, backpressure, duplication avoidance, and restart position are qualified per emitter.

## Capability, residency, and placement

### Capability declaration

Every process, step, update law, bridge, structural law, state leaf, and executor declares:

- supported execution domains and device families;
- element/precision restrictions;
- current and required residency;
- allowed projections and transfers;
- scratch and steady-state allocation behavior;
- synchronization and status-publication boundaries;
- retry/purity capability;
- continuation codec availability; and
- exact, numerical, or statistical equivalence class.

Composition preflight takes the transitive intersection of these declarations. Unsupported
combinations, hidden conversions, and unavailable codecs fail before mutation.

### Transfer policy

Every cross-residency movement is an explicit bridge or projection with:

- source and destination domain;
- schema and bounded size;
- cadence;
- synchronization point;
- conversion and precision behavior;
- measured bytes and time; and
- failure policy.

Implicit scalar indexing, automatic materialization, unbounded host collection, hidden fallback,
and executor-selected transfer absent from the compiled plan are errors. A small transfer is not
exempt merely because it is cheap.

GPU-native does not mean every process is GPU-executable. It means device-resident state and laws
can remain resident across events, GPU-capable work has qualified native paths, and CPU-only work
is explicit with measured boundaries.

## Executor protocol and Dagger boundary

`SerialExecutor` is the Phase 15.C execution policy over `SerialRuntime` state and is the
equivalence reference for alternate physical executors. It is not the independent specification
oracle. An executor receives a fully selected runnable batch:

- exact event and interval identities;
- immutable typed input projections;
- stable invocation identities;
- placement and residency constraints;
- semantic RNG contexts; and
- expected effect schemas.

It returns typed invocation results. It cannot commit, reschedule other processes, choose conflict
resolution, rewrite topology, emit settled observations, or alter logical time.

`ThreadsExecutor` and `DaggerExecutor` qualify only by equivalence to serial semantics. Dagger tasks
are coarse process ticks, solver calls, field advances, or partition batches. Dagger automatic data
movement is disabled or constrained so all movement remains declared and measured.

The runtime MAY spike Dagger placement before parity, but production `DaggerExecutor`
qualification waits for stable:

- runnable-batch formation;
- snapshot projection;
- update reconciliation;
- atomic state and timing commit;
- Step DAG layers;
- structural barriers;
- failure identities; and
- settled checkpoint semantics.

## Scientific adapter contract

Adapters lower external scientific systems into ordinary processes and steps. External libraries
do not become runtime semantic authorities.

Decision 0039 introduces a solver-neutral Phase 16 engine protocol. ProcessBigraphs owns when and
why an operation occurs: logical time, reason, immutable inputs, identity, validation,
authorization, publication, failure, checkpoint, and replay. The adapter owns how the heavy
operation occurs: algorithms, internal steps and callbacks, arrays, workspaces, caches, device
buffers, streams, kernels, and raw diagnostics.

The core does not hard-depend on SciML. An immutable adapter declaration and a lineage-local opaque
engine instance implement interval advance, boundary solve, discrete batch, or a typed extension.
The engine returns a completion handle and staged opaque candidate, typed early return, typed
global-impact request, or structured failure. Publication performs no allocation, transfer,
synchronization, or numerical work.

Phase 16 qualifies the native CorePotts field engine, one bounded CPU SciML field adapter, and one
minimal independent CPU custom field adapter. This proves that arbitrary solvers may join through
open Julia dispatch and per-envelope qualification; it does not claim universal solver/backend
support. Phase 17 generalizes the proven boundary to broad ODE/DAE and scientific ecosystems.

Every solver-backed adapter declares:

- state mapping and canonical units;
- whether interval inputs are `frozen`, `interpolated`, `event_updated`, or
  `continuously_callable`;
- initialization and reinitialization;
- cache invalidation after external state changes;
- discontinuity and event handling;
- requested tolerance and accepted result policy;
- continuation and checkpoint codec;
- failure, timeout, and cancellation behavior;
- RNG and replay class;
- supported residency and transfers; and
- next-deadline behavior.

Specific policies are:

- ModelingToolkit is an optional authoring/compiler frontend lowering to standard SciML adapters.
- OrdinaryDiffEq and related SciML solvers retain their algorithms behind explicit continuation,
  reinitialization, input, tolerance, and event contracts.
- Catalyst and JumpProcesses declare propensity-cache invalidation, rescheduling, discontinuity,
  and semantic RNG behavior.
- COBREXA/JuMP pins optimizer, tolerances, warm-start policy, and deterministic solution selection;
  nonunique, infeasible, unbounded, timeout, and solver failure are tested outcomes.
- SBMLImporter, SBMLFBCModels, and libSBML expose exact supported-feature matrices. Unsupported
  SBML constructs fail or are explicitly approximated; they are never silently discarded.

## Potts adapter and parallel migration

`ProcessBigraphs.jl` MUST NOT depend on CorePotts or PottsToolkit. CorePotts adapts:

- Potts state and specialized storage as schema-valid runtime leaves;
- an MCS or qualified substage as a coarse temporal process or explicit workflow;
- lifecycle changes as structural requests;
- existing semantic RNG into runtime-addressed identities;
- device adaptation and residency through declared capabilities; and
- existing checkpoints through versioned readers and a bounded conversion.

Decision 0039 absorbs G4 as mandatory Phase 16.C without changing the locked G3-B ABI. Decision
0035 still retires assembled Wang GPU qualification. Phase 16.B freezes the generic engine/field
protocol; Phase 16.C then pressure-tests the native field engine on sequential CPU, real Metal,
and real ROCm. Neither SciML nor assembled-model evidence substitutes for that hardware gate.

Migration is slice-by-slice:

1. preserve frozen Phase 13 and attested G3-B artifacts;
2. implement the generic serial path without changing the old path;
3. compare old and new serial state, order, RNG, lifecycle, checkpoint, and diagnostics;
4. qualify the registered field and lifecycle slice equivalence;
5. cut over only the passing slice; and
6. retain readers for attested checkpoint formats.

No production model may have two active runtime authorities.

## Parity, maturity, and release

Registry statuses are:

- `not_started`;
- `specified`;
- `implemented`;
- `oracle_passing`;
- `qualified`;
- `blocked`;
- `excluded`; and
- `not_applicable`.

`qualified` requires the registered specification, implementation, direct tests, independent
source-derived Julia oracle where applicable, failure and persistence evidence, documentation, and
applicable backend matrix. An unimplemented compatibility spelling cannot satisfy a behavioral
feature; an example run alone cannot qualify a semantic family.

Maturity gates are:

- **internal alpha** — the exact immutable-topology serial allowlist, supporting-oracle rows,
  fixtures, exclusions, and two-stage closure in `process-bigraph-phase15c-entry-v1.toml`;
- **internal beta** — the exact Phase 16 entry/ledger scope: solver-neutral field engines, absorbed
  G4 native CPU/Metal/ROCm qualification, dynamic hierarchy, a CorePotts cutover, CPU
  SciML/custom adapters, and runnable source-bounded Merks/CNV models; and
- **first public release** — every required pinned-parity registry item qualified plus a passing
  whole-cell-style composite.

There is no public partial-parity release.

Passing the Phase 15.C independent specification oracle does not pass later dynamic-lineage,
executor-equivalence, hardware, application, adapter, or whole-cell oracles attached to the same
feature. Registry evidence must retain that scope rather than collapsing an internal-alpha result
into full pinned parity.

## Whole-cell acceptance ladder

The runtime progresses through:

1. runtime microfixtures;
2. a Julia Catalyst/JumpProcesses gene-expression process, SciML regulation process, and
   COBREXA/JuMP E. coli core FBA process in one multirate composite;
3. selected pinned vEcoli process slices with source-derived registered traces;
4. a well-stirred JCVI-Syn3A CME/ODE composition;
5. a full pinned vEcoli generation; and
6. population/environment composition with PottsToolkit.

Historical Karr/Covert *M. genitalium* semantic coverage may inform the scientific roadmap but does
not replace the accepted ladder.

## Minimum conformance suite

The checked Julia specification oracle MUST be a test-only, small, auditable module structurally
independent from the production executor. Expected results MUST be traced to exact pinned-source
locations, hand-checkable derivations, or explicit mathematical definitions, including uncertainty
records where sources disagree. It MUST NOT import ProcessBigraphs or invoke production scheduling,
reconciliation, update, RNG, continuation, observation, checkpoint, fingerprint, or runtime
implementations. Production and oracle may share only neutral machine-readable fixture inputs and
result schemas.

Phase 15.C additionally requires static dependency enforcement and mutation-sensitivity fixtures
that perturb scheduler, update, RNG, failure, and checkpoint behavior. Bounded generated cases
record seeds and retained minimal counterexamples. Every reachable settled boundary in each
bounded Phase 15.C fixture is a required restart cut.

Before public release, evidence MUST cover:

- ACSet schema validity, naturality, canonical isomorphism, structured-cospan composition,
  wiring-diagram equivalence, hierarchy compilation, and exact constructor/ACSet round trips;
- invariance under ACSet row renumbering, declaration and hash-table order, path aliases,
  equivalent composite parenthesization, task completion order, and worker count;
- exhaustive finite truth tables where feasible plus property, metamorphic, fuzz, and
  failure-injection tests;
- interval-one and interval-two processes sharing state;
- forced partial final intervals;
- same-time numeric, overwrite, map, array, add/remove, and divide conflicts in reversed execution
  orders;
- fork/join steps, silent inputs, wildcard bindings, same-layer writes, and cycle rejection;
- nested composites, bridges, privacy, and canonical lowering;
- dynamic add, execute, move, rewire, divide, daughter reconstruction, and remove;
- lineage-stable RNG and worker-count invariance;
- settled-boundary checkpoint and replay;
- failure during invoke, reconcile, apply, structural commit, required observation, and checkpoint;
- serial/threads/Dagger equivalence where those executors are claimed;
- residency tracing and hidden-transfer rejection;
- external-solver invalidation and jump-propensity reset;
- FBA nonunique, infeasible, unbounded, timeout, and solver-failure behavior;
- applicable SBML conformance cases;
- requester-to-allocator-to-evolver workflow behavior;
- the registered vEcoli and Spatio-Flux application fixtures;
- long-run leak and output-volume budgets; and
- compile latency, memory, event throughput, and checkpoint budgets.

No conformance command may install or execute Vivarium, Process-Bigraph Python, or Bigraph-Schema
Python. Upstream source and test files may be inspected and cited as derivation authorities.

Every result records the runtime commit, source pins, model fingerprint, compatibility mode,
executor, backend, hardware, numerical/replay class, and evidence artifact.

## Explicit non-goals for the first parity release

- Vivarium 1.x API or behavior compatibility;
- exact Python API spelling or object representation;
- complete Python/JSON interchange;
- direct upstream-runtime-equivalence claims without executing that runtime;
- REST, Ray, EC2, Python multiprocessing, or Nextflow backend parity;
- mandatory SQLite, Parquet, dashboard, or visualization implementations in core;
- formal support for every Milner-bigraph encoding;
- universal GPU execution of every whole-cell process;
- merge, engulf, burst, or unrestricted structural rewrite without promotion evidence;
- arbitrary mid-event restart; and
- endorsement or design approval by Eran Agmon or the Vivarium project.
