# ProcessBigraphs High-Level Authoring Semantics

Status: Normative specification; Phase 16.HC qualified

Version: 1.0.0

Date: 2026-07-28

Authority: Decision 0040, the Phase 16.HC owner interview, Decision 0037, Decision 0039, and the
Phase 16 qualification control plane

## 1. Purpose and claim boundary

This specification defines the ordinary Julia authoring contract for `ProcessBigraphs.jl`. It
adds an author-facing semantic model above the qualified canonical ACSet and execution-plan
layers. It does not create another scheduler, state authority, runtime, checkpoint format, or
numerical solver.

The specification is required by Phase 16.HC before Phase 16.I reconciliation. Specification
passage authorizes implementation planning; it is not implementation, migration, or qualification
evidence.

The keywords MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, and MAY are normative.

The governing principles are:

> ProcessBigraphs owns when and why computation occurs. Optimized solver and CPM kernels own how
> authorized heavy computation occurs.

> Ordinary scientific models must be authorable, inspectable, validatable, lowerable, and
> executable without direct construction of canonical IR.

## 2. Semantic layers and lifecycle

### 2.1 Distinct objects

The stable lifecycle has five distinct layers:

1. a temporary transactional builder;
2. an immutable hierarchical `CompositeModel`;
3. a deterministic `LoweredModel` containing canonical ProcessBigraph structure and an origin map;
4. a backend-specific immutable `ExecutionPlan`; and
5. a run-specific mutable runtime containing committed state and private solver sessions.

These layers MUST NOT be aliases for one mutable object.

The `CompositeModel` is the author-facing source of scientific and compositional meaning. The
canonical ProcessBigraph ACSet remains the canonical lowered structural representation selected by
Decision 0036. The execution plan remains the sole runtime routing representation. This staged
model does not authorize a second structural or execution authority.

### 2.2 Transactional construction

The primary construction form is ordinary Julia:

```julia
model = compose(:ModelName) do builder
    # declarations
end
```

The builder MAY be temporarily incomplete inside the block. Closing the block MUST:

1. normalize local declarations;
2. validate the complete semantic model;
3. accumulate all independent global diagnostics;
4. throw one structured validation error if errors remain; and
5. otherwise return an immutable `CompositeModel`.

A completed model MUST NOT retain a live mutable builder. Builder handles MUST NOT authorize
mutation after finalization.

### 2.3 Derivation and compilation

Changes to a completed object use `remake`, composition, or a new builder transaction. Lowering and
compilation are explicit and nonmutating:

```julia
lowered = lower(model)
plan = compile(lowered; backend)
```

`compile(model; backend)` MAY be a convenience that invokes `lower` internally, but the semantic
and lowering stages remain separately inspectable.

## 3. Ordinary Julia authoring surface

### 3.1 Primary vocabulary

The Phase 16.HC programmatic vocabulary is:

```text
compose
store!
mount!
connect!
attach!
expose!
schedule!
parameter!
observable!
allow_instances!
lower
compile
validate
describe
diagram
explain
remake
```

Exact exported versus public-unexported disposition is governed by the Phase 16 API registry.
Implementation helper types and canonical IR constructors are not admitted merely because the
operation above requires them internally.

Builder operations use `!` because they mutate the temporary builder. They MUST NOT mutate a
completed model.

### 3.2 Explicit names and typed handles

Every declaration has an explicit semantic name and returns a typed handle:

```julia
labels = store!(m, :labels, LabelField(domain))
cpm = mount!(m, :cpm, CPMSolver(config))
```

Renaming the Julia local variable MUST NOT change semantic identity. Local-variable capture is not
an identity mechanism.

Ordinary authoring and problem binding use typed handles such as store, port, component, parameter,
observable, mounted-composite, and runtime-instance handles. String paths, tuple parent traversal,
ACSet row numbers, generated integer indices, and raw port-binding records MUST NOT be required.

Property access MAY expose named children and ports when it is compatible with ordinary Julia
reflection:

```julia
cpm.labels
model.parameters.adhesion
```

`propertynames`, documented accessor functions, and concise display MUST reveal the available
surface. Property access MUST NOT expose private mounted internals.

### 3.3 Ordinary Julia is the metaprogramming language

Reusable helpers, loops, conditions, generated families, dispatch, and configuration are ordinary
Julia. The authoring system MUST NOT parse general Julia control flow into a second language.

Bulk construction accepts ordinary Julia named and indexed collections and returns corresponding
collections of handles. A proprietary container hierarchy requires a demonstrated need.

### 3.4 Macro boundary

Every stable construct expressible with a macro MUST be expressible through documented ordinary
functions. A macro may provide mechanically transparent naming or genuine domain notation only.
It MUST NOT:

- infer scientific connections;
- infer schedules from lexical order;
- search scope for matching values;
- construct raw IR as its only meaning;
- hide generated components or stores; or
- make a model impossible to express programmatically.

A full `@compose` language is excluded from the Phase 16.HC requirement. If later admitted, it
must expand to the same public builder functions and produce the same immutable semantic model,
diagnostics, origin information, and fingerprint.

Domain packages retain ownership of domain notation such as Catalyst reaction networks,
ModelingToolkit equations, or CPM energy declarations. ProcessBigraphs composes their resulting
components or adapters.

## 4. Stores, ports, and connection semantics

### 4.1 Store junctions are topology truth

A named shared-store junction is the normative connection object. A connection joins one store and
one or more compatible component ports:

```julia
connect!(m, labels, cpm.labels, secretion.labels)
```

The store owns shared state, update-law reconciliation, persistence, and state-transfer semantics.
Ports declare access direction and their required contract.

A connection does not imply left-to-right execution or Julia assignment. Execution order is
declared separately by scheduling.

### 4.2 Logical ports

The author-facing protocol supports logical:

- `Read`;
- `Write(update_law)`;
- `ReadWrite(update_law)`; and
- explicitly optional variants.

A logical `ReadWrite` port is one author-facing port. Lowering MAY split it into canonical read and
write entities and MUST retain their common origin.

Multiple ports MAY connect to one compatible store. One logical port MUST NOT be silently split
across unrelated stores.

### 4.3 Exact bulk attachment

`attach!` is an explicit bulk-binding operation. It MAY match exact names only after complete
contract compatibility and MUST return an expansion report. Approximate name matching, silent
autowiring, position-based wiring, and precedence rules are forbidden.

Every convenience expansion becomes explicit semantic connections before final validation and can
be inspected with `explain`.

### 4.4 Compatibility

Joined endpoints agree on every applicable contract dimension, including:

- value type, element type, rank, and shape;
- units or declared normalization;
- ontology or scientific meaning;
- access direction;
- update and merge law;
- ownership and persistence;
- residency and accepted representation;
- transfer and conversion requirements; and
- division or other structural-transfer behavior.

Conversion is an explicit component or planned bridge. It is never inferred by connection.

## 5. State, schema, parameters, and initialization

### 5.1 Inferred storage facts

The schema MAY infer unambiguous storage facts from Julia values, including concrete type, element
type, rank, shape, immutable defensive default, and named hierarchy.

Scientific semantics MUST be explicit when applicable, including:

- units or dimensionless normalization;
- ontology meaning;
- residency and transfer;
- ownership and aliasing;
- persistence;
- division or structural transfer;
- update and merge law; and
- authorization for lossy conversion.

### 5.2 Update laws and writers

A store may state its update law explicitly. Otherwise, a law may be derived only when every
writer requires one identical, unambiguous law. No writer, incompatible writers, or multiple
possible laws require an explicit declaration.

Order-sensitive laws require an explicit semantic order. A floating-point reduction may claim
exact reproducibility only with a qualified deterministic reduction policy.

### 5.3 Defaults and initial conditions

Reusable schema/default values and run-specific initial conditions are distinct.

A model declares required state and scientifically meaningful defaults. A
`SimulationProblem` supplies run-specific initial state. Missing required state MUST NOT be
silently zero-filled unless zero is the declared default.

Initialization precedence is:

```text
exact problem binding
    overrides problem preset
    overrides model default
```

Derived initializers declare read/write sets, parameters, randomness, identity, and portability.
Initialization produces a provenance report showing the source of every resolved value.

### 5.4 Model constants and run parameters

A model constant changes the model definition and normally requires `remake(model; ...)`,
lowering, and possibly recompilation.

A declared parameter is a typed scientific input that may vary between problems without changing
model topology:

```julia
variant = remake(problem;
    parameters=[model.parameters.adhesion => 18.0])
```

Parameter bindings use handles and validate type, units, domain, ownership, duplication, and
completeness. Recursive dictionary merge is not a binding protocol.

## 6. Component and solver protocol

### 6.1 Open functional protocol

Components and solver adapters participate through small functions and capability traits.
Optional abstract types may communicate genuine semantic categories but subtyping alone is not
conformance.

The conceptual adapter lifecycle is:

```text
interface
capabilities
initialize
advance!
checkpoint
restore
finalize!
```

An external solver need not adopt ProcessBigraphs storage or inherit from a ProcessBigraphs
implementation type.

### 6.2 Shared versus private state

A component MAY own a mutable private session, workspace, cache, device buffer, foreign handle, or
integrator. It MUST NOT directly mutate committed shared state.

An invocation receives an exact `Advance(from, to, trigger)` request plus immutable or
contract-bounded inputs. It returns typed state effects, structural effects, a typed early result,
or structured failure. ProcessBigraphs validates and commits shared effects.

Scientific algorithm and configuration choices belong to the component or adapter declaration.
ProcessBigraphs scheduling does not select or reimplement the solver's internal numerical method.

### 6.3 Capabilities

Capabilities are typed, explicit, narrow, and additive. They may include:

- fixed or adaptive continuous time;
- root-located events and early return;
- interpolation;
- checkpoint and restore;
- session cloning;
- dynamic structural replication;
- residency and accepted layouts;
- thread safety and resource use;
- differentiability;
- cancellation; and
- deterministic replay class.

Preflight inspects claims before mutation. Method failure or `try`/`catch` probing is not
capability negotiation.

### 6.4 Fingerprint contribution

An adapter declaration fingerprint covers interface, semantic version, scientific parameters,
algorithm and bounded options, adapter version, continuation policy, and applicable capability
envelope. Memory addresses and live cache layout are excluded.

An anonymous or unregistered callable MAY be used interactively. Reproducible or portable profiles
require a stable semantic identity, parameters, version, and codec. Validation reports the missing
profile capability rather than universally rejecting interactive use.

## 7. Time, orchestration, and execution

### 7.1 Communication boundaries

ProcessBigraphs owns exact semantic synchronization and publication boundaries. A solver owns
adaptive steps, fixed internal steps, root finding, Monte Carlo sweeps, device kernels, and local
iterations within one authorized interval.

`Advance(t0, t1)` means “produce a valid published result at the requested communication
boundary.” It MUST NOT mean “perform one Euler step.”

A solver reaches the exact target, or returns a typed early result with the reached time and
reason. Silent overshoot, undershoot, extrapolation, rounding, or interpolation-as-publication is
forbidden.

### 7.2 Scheduling vocabulary

The semantic schedule supports:

- periodic `Every`;
- exact `At`;
- event `On`;
- dependency `After`;
- explicit bounded or convergence-checked iteration; and
- adapter-proposed wakeups.

Internal numerical events remain private unless they affect global state, structure, visibility,
or scheduling. Globally relevant events are surfaced as typed requests.

Logical time is authoritative and exact. Conversion to a solver time representation is checked at
the adapter boundary.

### 7.3 Staged dataflow

Compilation creates deterministic orchestration stages. Components in one parallel stage read the
same committed snapshot and publish one combined transaction. A serial dependency creates another
stage and commit boundary, even at the same logical time.

Task completion order is nonsemantic. Effects commit in canonical semantic order or through the
store's declared reduction law.

Concurrent invocations use immutable inputs, private sessions, and private effect accumulators.
They do not mutate shared Julia collections or stores under incidental locks.

### 7.4 Iterative regions

Cycles are invalid unless enclosed in an explicit iterative region with convergence or bounded
termination semantics.

Implicit repeated coupling is legal only when every participant can repeat an iteration through
exact checkpoint/restore or pure reconstructible evaluation. Intermediate iterates remain private
to the region. Universal optimistic rollback, distributed co-simulation, and general acceleration
schemes are outside Phase 16.HC.

## 8. Hierarchy, exports, and runtime structure

### 8.1 Lexical hierarchy

Hierarchy is lexically scoped. Mounted internals are private by default. A reusable composite
exposes selected boundary handles explicitly:

```julia
tissue = mount!(m, :tissue, TissueModel(config))
expose!(m, :field, tissue.field)
```

The same immutable definition may be mounted repeatedly with distinct explicit mount keys.
Definition identity and mounted-instance identity are distinct.

Canonical semantic identity derives from the root identity and mount chain. Ordinary authors do
not use `..` traversal or manual path strings.

The semantic model preserves hierarchy. Lowering MAY flatten executable entities but retains a
complete author-origin map.

Closed and open models are the same semantic model category with zero or more exports; they are not
unrelated construction systems.

### 8.2 Structural templates and instances

Dynamic structural changes instantiate immutable named templates declared by the semantic model.
Definitions and runtime instances are distinct.

Components propose typed structural effects such as:

- spawn;
- binary divide;
- remove;
- move; and
- replace only when a qualified model requires it.

ProcessBigraphs alone validates and atomically commits topology.

Runtime instance identities derive from replay-stable semantic information and do not depend on
memory addresses, thread order, dictionary order, or random UUIDs. A moved runtime instance
retains its identity even though its displayed location changes.

### 8.3 Structural transactions

At one structural boundary, the runtime:

1. collects ordinary and structural effects;
2. validates the complete batch;
3. constructs candidate post-update state;
4. applies structural transfer to that candidate state;
5. validates resulting topology and contracts; and
6. atomically publishes state and structure.

Division therefore uses post-update candidate state unless an explicit orchestration phase states
otherwise.

Store contracts own copy, split, partition, move, reinitialize, or explicit-drop behavior.
Mutable state MUST NOT be accidentally shared. Solver sessions declare clone, checkpoint/restore,
reinitialize, single-transfer, or unsupported replication behavior.

Dynamic creation uses templates admitted before compilation. Manufacturing arbitrary new Julia
model definitions during a run is outside Phase 16.HC.

Conflicting operations are errors unless the model declares a deterministic resolver. Move,
remove, and division validate external references and dangling-connection policies.

## 9. Validation and diagnostics

### 9.1 Timing

Locally invalid operations fail immediately. Temporary global incompleteness is allowed within the
builder. Finalization accumulates independent global diagnostics and suppresses dependent cascades.

Validation phases include:

1. declarations;
2. hierarchy and exports;
3. connectivity;
4. schema and scientific contracts;
5. writers and update laws;
6. schedules, stages, and cycles;
7. time and event capabilities;
8. residency, representation, and transfers;
9. checkpoint and replay requirements;
10. determinism requirements;
11. structural templates and transfer;
12. lowering consistency; and
13. requested qualification profiles.

### 9.2 Structured report

`validate(model)` returns a structured report. Every diagnostic contains:

- stable code;
- severity;
- author-facing handle and hierarchical location;
- related objects;
- expected and actual contract;
- concise explanation; and
- actionable suggestion where possible.

IR row numbers MAY appear as secondary debugging data only when accompanied by author origin.

Requirement profiles such as checkpointable, deterministic, portable, serializable, or
GPU-compatible add explicit requirements. They do not silently change model meaning. Environment
warnings do not alter semantic fingerprints.

## 10. Lowering, provenance, identity, and serialization

### 10.1 Deterministic lowering

`lower(model)` is pure, deterministic, and independent of backend availability. It may:

- resolve mounts and exports;
- expand explicit attachments;
- split logical read/write ports;
- flatten hierarchy where canonical IR requires;
- normalize update laws and schedules; and
- generate canonical semantic identifiers.

It MUST NOT select hardware, tune a solver, inspect local devices, or mutate the model.

Canonical ordering ignores builder insertion order whenever order is semantically irrelevant.
Declared orchestration order remains semantic.

### 10.2 Origin map

Every canonical IR entity maps to one or more author-facing origins. Origin survives lowering,
compilation, diagnostics, checkpoints, traces, and profiling.

`explain(model_or_handle)` and an explicit lowering explanation MUST report attachment expansion,
logical-port splitting, hierarchy flattening, conversions, and generated schedule stages.

Raw IR is a supported diagnostic and expert conformance surface, not an ordinary authoring
requirement.

### 10.3 Layered fingerprints

Identity is layered:

- `semantic_fingerprint(model)` identifies scientific and compositional meaning;
- `ir_fingerprint(lowered)` identifies exact canonical IR, schema, and lowering contract;
- `plan_fingerprint(plan)` adds backend, compiler, adapter, resource, and implementation choices;
- `problem_fingerprint(problem)` adds parameter bindings, initialization specification,
  interventions, time span, and seed policy; and
- checkpoint/run identity adds plan, runtime, and checkpoint-format versions.

The same semantic model compiled for CPU and GPU retains one semantic fingerprint and has distinct
plan fingerprints.

Caches use the dependencies of the artifact being cached. A semantic fingerprint alone is not a
plan-cache key.

### 10.4 Versioning and serialization

The following versions are distinct:

- semantic API contract;
- semantic serialization format;
- canonical IR schema;
- lowering contract;
- execution-plan ABI; and
- checkpoint format.

Migrations are explicit and tested. No layer silently reinterprets another.

Supported semantic serialization round trips preserve meaning and semantic fingerprint, not the
exact sequence of builder calls or macro spelling.

Canonical IR may be a stable audit/interchange representation. It does not reconstruct syntactic
intent erased by lowering. Compiled plans are rebuildable artifacts and are not the primary
portable serialization format.

## 11. Models, problems, experiments, and observation

### 11.1 Model versus problem

A `CompositeModel` contains reusable scientific and compositional meaning. A
`SimulationProblem` binds one run:

```julia
problem = SimulationProblem(model;
    tspan,
    parameters,
    initial,
    interventions,
    seed)
```

Run-specific output destinations, plot names, and transient runtime resources are not model
meaning.

Interventions are typed run protocol. They may alter declared parameters, state, schedules, or
structure only through the same validation and transaction boundaries as components.

### 11.2 Observables and recording

A model may declare pure typed observables. A problem or solve call chooses which observables to
record and when. Output sinks are separate.

Recording semantics state whether samples occur:

- at published boundaries;
- at exact requested times through declared adapter interpolation;
- at the latest committed state; and
- before or after a same-time intervention.

Observation MUST NOT force a numerical solver into fixed internal timesteps.

Required observations participate in atomic publication. External sinks retain the existing
staging, idempotency, delivery, backpressure, and recovery contracts.

### 11.3 Randomness and ensembles

A problem owns a master seed. ProcessBigraphs derives independent deterministic streams from the
master seed, semantic component identity, runtime instance identity, event sequence, and randomness
domain. Components MUST NOT rely on Julia's global RNG.

Problem variants use immutable `remake`. Ensemble support follows applicable SciML/CommonSolve
conventions through the optional integration extension. Threaded, distributed, or GPU ensemble
claims require separate qualification and do not follow from method naming alone.

## 12. Ecosystem and dependency boundary

### 12.1 Solver-neutral core

ProcessBigraphs core MUST NOT hard-depend on SciMLBase, CommonSolve, ModelingToolkit,
OrdinaryDiffEq, CUDA, or a concrete scientific solver.

SciMLBase and CommonSolve remain weak dependencies and extension triggers. The extension adds
applicable common solve, remake, indexing, and ensemble integration when installed. A wrapper MAY
subtype a SciML abstract type when a genuine subtype contract is required; the solver-neutral core
model MUST NOT be distorted solely to inherit from a foreign type.

ProcessBigraphs MUST NOT define numerical solve methods whose function and argument types are both
foreign. A SciML adapter passes real SciML problems to methods owned by the selected solver
ecosystem.

### 12.2 Extension ownership

Generic bridges may live in ProcessBigraphs package extensions. Solver-specific adapters should
normally live with the solver or in a dedicated adapter package. Domain packages own domain
semantics.

Normal execution uses explicit adapter values and multiple dispatch. A limited versioned registry
may support portable codecs and reconstruction. It MUST NOT become global string-based runtime
dispatch.

### 12.3 Progressive extension tiers

A small pure process may use a functional-component helper. A reusable Julia component defines a
concrete type and protocol methods. A heavy external solver defines a full adapter lifecycle and
capabilities.

Required work scales with claimed behavior. A simple component is not forced to implement
checkpoint, GPU, structural replication, or serialization methods it does not claim.

ProcessBigraphs supplies an adapter conformance kit that tests every applicable capability,
including isolation, exact interval behavior, typed effects, session independence, checkpoint,
events, resources, determinism, failure atomicity, and cleanup.

Protocol compatibility is versioned independently from internal implementation. Deprecations
include a replacement, compatibility window, conformance coverage, and clear unsupported-version
error.

## 13. Representation, concurrency, and performance

### 13.1 Representation negotiation

Scientific contracts describe logical values. Execution planning resolves concrete CPU, GPU,
distributed, or foreign representations.

Adapters declare element type, layout, residency, mutability, ownership, and retention. Bindings
distinguish borrowed read-only views, adapter-owned copies, exclusive mutable outputs,
runtime-owned storage, foreign handles, and ephemeral staging buffers.

Conversions and transfers are explicit planned operations with semantic origin, validation,
profiling, and fingerprint contribution. Lossy conversion requires authorization.

### 13.2 Resource scheduling

Adapters declare internal threads, devices, streams, memory, and exclusivity. ProcessBigraphs
coordinates outer resource use and does not parallelize inside optimized solver or CPM kernels.

Asynchronous work returns completion tokens. Publication waits for declared dependencies, not
after every device operation.

Stage failure cancels siblings where safe, discards stage effects, preserves the last committed
boundary, and marks or restores sessions according to capability. Irreversible scientific external
effects during `advance!` are forbidden unless explicitly declared nontransactional and
orchestrated outside atomic publication.

### 13.3 Cache and optimization boundary

Semantic/lowering caches, execution-plan caches, and run-local solver caches are distinct.
Mutable runtime state is not a compile cache.

Phase 16.HC uses conservative dependency, residency, resource, and buffer-liveness planning. A
speculative cost optimizer, universal auto-tuner, Dagger executor, and distributed rollback are
excluded.

### 13.4 Performance evidence

Benchmarks separate model construction, validation, lowering, compilation, initialization, warm
execution, observation, and checkpointing.

Authoring is not required to be allocation-free. A high-level model that lowers to the same plan
MUST NOT slow steady solver or CPM kernels merely because it originated from the semantic API.

Performance reports use semantic handles and distinguish waiting, transfers, solver advance,
effect validation, commit, structural transactions, allocations, and synchronization.

## 14. Raw IR boundary and migration

### 14.1 Allowed direct IR use

Direct canonical IR construction is allowed only in:

- lowering implementation tests;
- canonical schema conformance tests;
- serialization and compatibility migration tests;
- independent lowering or runtime oracles; and
- explicitly marked expert/internal tooling.

Scientific library models, examples, documentation, and ordinary behavioral tests MUST use the
semantic API after migration.

A scientific model that requires raw IR is an authoring API defect unless the missing capability
is explicitly excluded.

### 14.2 Controlled migration

Before migration, each raw model path is frozen as a differential oracle. Migration order is:

1. tiny composition fixtures;
2. hierarchy and export fixtures;
3. scheduling and iteration fixtures;
4. structural templates;
5. adapter fixtures;
6. Merks;
7. reduced CNV fixtures;
8. full bounded CNV construction;
9. examples and documentation; and
10. remaining behavioral tests.

Equivalence compares semantic declarations, canonical structure where unchanged, fingerprints,
initial state, bounded trace, observations, checkpoint/restart, failure rollback, and scientific
invariants.

After one slice qualifies, the semantic model is its sole production authoring path. The raw path
may remain as a frozen test-only oracle or is removed. Silent production fallback is forbidden.

An allowlist-based static guard enforces the boundary. A broad directory exemption is not
sufficient.

## 15. Phase 16.HC qualification and exclusions

### 15.1 Qualification obligations

Phase 16.HC is qualified only when:

- the semantic lifecycle and public API are implemented;
- builder, hierarchy, connections, schedules, templates, and problem binding pass contract tests;
- structured diagnostics and lowering origin maps pass;
- deterministic lowering, layered fingerprints, and serialization migrations pass;
- the optional SciML/CommonSolve extension remains real-solver based, piracy-free, and
  independently tested;
- adapter conformance and negative-capability fixtures pass;
- Merks and CNV use the semantic API and retain their qualified bounded behavior;
- the raw-IR inventory contains only explicit allowlisted purposes;
- ProcessBigraphs and CorePotts pass clean independent package tests;
- Aqua, documentation, doctests, and public-API checks pass;
- authoring and steady-runtime benchmarks satisfy frozen workload-specific budgets; and
- no previously qualified Phase 16 semantic, failure, persistence, backend, or model row is
  silently invalidated.

Tests alone do not create a `qualified` status. Evidence and the existing Phase 16 closure
discipline remain required.

### 15.2 Explicit exclusions

Phase 16.HC excludes:

- a full `@compose` language;
- graphical authoring;
- arbitrary closure serialization;
- a universal implicit co-simulation engine;
- full ModelingToolkit symbolic composition;
- reimplementation of qualified optimized kernels without a demonstrated defect;
- replacement of the canonical ProcessBigraph ACSet;
- full Merks or CNV publication analysis; and
- public `1.x` stability.

### 15.3 Exit condition

Phase 16.HC exits only when:

> Every shipped scientific ProcessBigraph model can be authored, inspected, validated, lowered,
> and executed without direct IR construction; every remaining direct IR use is explicitly
> internal, tested, and allowlisted.

Phase 16.I MUST NOT attest the internal beta before Phase 16.HC is qualified. The independent real
Metal and ROCm obligations in Phase 16.C remain open until their own exact-head evidence qualifies.
