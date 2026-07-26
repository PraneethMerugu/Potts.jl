# Phase 14 Single Semantic Kernel

Version: `0.2-provisional`

Status: Accepted architecture; individual Phase 14.1 contracts remain Provisional until their
registered vertical-slice gates pass

Implementation evidence: the Wortel Act-CPM CPU-reference slice passed on 2026-07-24 and its
real-hardware Metal/ROCm G2 closure passed on 2026-07-25. Wang G3-B sequential CPU closure is
attested complete at implementation commit `a82b0c4`; its
[closure ledger](../design/audits/phase-14-g3b-closure-ledger-v1.toml) records
`overall_status = "passed"`. The exact
[source/runtime order](../design/audits/phase-14-wang-order-audit.md) and revision-7
[G3-B closure contract](../design/audits/phase-14-g3b-entry-packet.md) govern that evidence.
This proves the bounded Wortel slice and Wang sequential CPU model. Decision 0035 retires the
assembled Wang Metal/ROCm promotion because the paper-faithful sequential algorithm is not an
appropriate GPU target; G4 is current. Contracts outside the proven slices remain Provisional.

Governing decisions:
[Decision 0031](decisions/0031-phase-14-single-semantic-kernel.md) and
[Decision 0032](decisions/0032-phase-14-gpu-native-promotion.md), plus the generic authoring
boundary in
[Decision 0033](decisions/0033-phase-14-generic-hierarchical-authoring.md)
and the Wang algorithm-suitability boundary in
[Decision 0035](decisions/0035-wang-sequential-gpu-disposition.md)

Registry:
[Phase 14 Contract Registry v2](phase-14-contract-registry-v2.toml)

## Authority

This document is the sole normative architecture for the existing Potts-owned Phase 14
coupled-model path. The earlier Phase 14 domain specifications are retained as source and prototype
evidence, but they do not define independent Potts runtimes or contracts. When an earlier Phase 14
document conflicts with this one, this document and Decision 0031 control.

Decision 0034 separately establishes the domain-neutral `ProcessBigraphs.jl` runtime. During the
strangler migration, this kernel remains authoritative for unmigrated Potts models; migrated slices
lower through the runtime and must pass old/new serial differential evidence. The migration MUST
end dual execution authority for each cut-over slice rather than leave two Potts schedulers.

The specification defines observable semantics, not concrete Julia storage layouts. Candidate type
names illustrate the intended API and remain Provisional until the corresponding vertical slice is
accepted.

## Goals

The kernel must:

- express every mechanism required by the frozen six-model portfolio;
- support the required Morpheus semantic microfixtures without copying Morpheus's internal object
  hierarchy;
- preserve exact update order, transaction atomicity, lifecycle safety, continuation, and
  qualification boundaries;
- provide natural biological authoring façades;
- support generic hierarchical composition whose root complexity follows meaningful subsystems
  rather than private declaration leaves;
- have one canonical model representation before execution; and
- leave every Phase 13 meaning unchanged for models that do not opt into Phase 14 declarations.

It must not become:

- a second Potts problem/integrator hierarchy;
- a general mutable callback system;
- a second ModelingToolkit or symbolic algebra system;
- an author-authored checkpoint/backend/compatibility language; or
- an implicit commitment to Mermaid.jl, automatic MorpheusML import, or the complete SBML
  formalism envelope.

## Canonical Model

Every authoring route MUST lower to one immutable `SemanticModel`-equivalent record containing:

1. ordered state declarations;
2. ordered process declarations;
3. one execution plan;
4. one lifecycle policy;
5. ordered observation declarations;
6. spatial-role declarations;
7. one Potts algorithm identity; and
8. canonical identities and versions for every referenced law, solver, relation, and policy.

The record is called the canonical model in this specification. The concrete Julia type name is not
yet frozen.

The canonical model MUST be inspectable without running the simulation. Validation, fingerprinting,
continuation requirements, backend preflight, and compatibility reporting MUST consume this same
record.

An authoring façade MUST either lower completely or reject with an actionable diagnostic. Runtime
lexical lookup, untyped symbol dictionaries, hidden closures with unregistered semantics, and
partially lowered adapter objects are prohibited.

Authoring hierarchy is not canonical runtime hierarchy. `ModelFragment` composition, lexical
namespaces, named requirements, and named exports are resolved before execution. The canonical
model retains qualified identities and authoring provenance but has no fragment-local clock,
scheduler, persistence store, backend state, or runtime dispatch boundary.

## Contract 1: State

### State declaration

Each state declaration contains:

- `id`: a stable, qualified semantic identity;
- `owner`: the semantic owner domain;
- `schema`: value type, shape, units when applicable, and invariants;
- `storage`: current, bounded-history, delayed-history, or a registered specialized storage policy;
- `initialization`: deterministic initialization law and required inputs;
- `lifecycle`: create, division, transition, retirement, and slot-reuse policies;
- `persistence`: future-relevant values and solver/storage metadata;
- `adaptation`: supported backend storage/adaptation capabilities; and
- `version`: the state contract or façade version.

Candidate owner descriptors are global, cell, site, field, membrane, and relationship. Extension
owners MAY be registered through the same protocol.

Owner descriptors define identity and lifecycle semantics. They do not require one physical
container. In particular:

- field state MAY use backend-resident grids;
- relationship state MAY use canonical graph storage;
- membrane state MAY use generation-aware material coordinates;
- cell state MUST distinguish slot from cell identity and generation; and
- site state MUST define ownership-change behavior for accepted copies.

### Snapshots

A process never reads an unspecified "current" state. Each read refers to a snapshot identity
provided by its plan entry:

- phase-entry snapshot;
- accepted-copy transaction snapshot;
- process-entry snapshot;
- completed-process snapshot; or
- completed-MCS snapshot.

All reads in one synchronous process invocation observe the same declared snapshot. A state write is
invisible until the process's commit boundary.

### History and delay

History is a state storage policy, not a separate runtime. A history policy defines:

- sample trigger and clock;
- capacity or retention interval;
- ordering;
- initialization before a full window exists;
- interpolation for off-grid delay reads;
- lifecycle inheritance/reset behavior; and
- continuation payload.

Exact-sample, piecewise-constant, and linear interpolation MAY be registered read policies. Their
identities and boundary behavior are fingerprinted.

### State façade examples

`SiteProperty`, cell properties, evolving fields, membrane properties, bounded cell histories, delay
buffers, and relationship sets MAY remain public authoring values. Each MUST lower to a state
declaration and MUST NOT define independent scheduling, persistence, or identity behavior.

## Contract 2: Process

### Process declaration

Each process declaration contains:

- `id` and `version`;
- ordered `reads`;
- ordered `writes`;
- a `law` with canonical identity;
- a trigger supplied by the plan;
- a read snapshot;
- a commit mode;
- numerical stepping or convergence policy when applicable;
- semantic RNG namespaces when applicable;
- conflict and priority metadata;
- lifecycle-request capability;
- failure behavior; and
- backend requirements.

The stable commit modes are:

- atomic synchronous commit;
- accepted-copy transactional commit;
- ordered sequential commit; and
- read-only evaluation.

New commit modes require an explicit D9 contract amendment.

### Process law families

The process protocol admits explicit law families, including:

- accepted-copy state transfer or update;
- deterministic site decay or degradation;
- fixed-step ODE advancement;
- synchronous recurrence rules;
- acyclic algebraic assignments;
- pure cross-domain mappings and reductions;
- transient or steady-state field evolution;
- cell/field secretion, uptake, and exchange;
- relationship create, remove, and retune laws;
- sampled triggered assignments; and
- lifecycle-request generation.

These families may have natural public constructors. They do not acquire independent clocks,
schedulers, runtimes, or checkpoint formats.

### Numerical processes

A numerical process MUST declare:

- semantic time interval supplied by the plan;
- fixed step, subcycle count, or convergence policy;
- method identity and version;
- tolerances where applicable;
- state and input mappings;
- failure/non-convergence behavior; and
- all future-relevant solver state.

The initial stable Phase 14 subset is fixed-step and explicit unless a proving model requires
otherwise. Adaptive integration is Experimental. A solver may take multiple internal steps, but it
may publish state only at the process commit boundary.

### Synchronous rules and assignments

All rules in one synchronous invocation read one common pre-invocation snapshot and commit
together. Rule source order cannot create implicit sequential semantics.

Reactive assignments MUST form an acyclic dependency graph. Pure functions own no state and may be
inlined into a law's canonical representation.

### Fields and exchange

Field evolution and exchange are process laws over field and cell/site state. Geometry, boundary
conditions, diffusion/reaction law, source/sink reduction order, units, split order, and failure
behavior MUST be explicit.

Internal field substeps may feed later internal substeps but remain staging operations. They do not
create process commits, plan entries, semantic clocks, or checkpoint positions. If preserving the
pre-process authoritative field through all internal steps requires additional staging storage,
that storage is a declared preallocated workspace rather than hidden allocation.

An exchange that mutates field state and produces cell/global outputs owns one typed cross-domain
write set. Every candidate output and status validates before one logical publication epoch. A
process-specific execution view may address only those declared targets; it is not an unrestricted
integrator callback.

Phase-local forcing that has no future relevance MUST disappear at its declared commit boundary.
Any accumulator that affects future execution is state and therefore must be declared and
checkpointed.

### Accepted-copy processes

An accepted-copy process runs only after an ordinary Potts proposal has been accepted and before
the transaction becomes visible. It reads the accepted-copy transaction snapshot and either commits
atomically with the Potts transaction or fails the entire transaction according to the registered
failure law.

Rejected and no-op proposals MUST NOT mutate accepted-copy state or consume accepted-copy RNG
addresses.

### Events

A sampled event is a triggered process. Its declaration defines:

- evaluation cadence;
- trigger memory and edge/level behavior;
- assignment snapshot;
- priority;
- cascade policy;
- optional delay;
- conflict behavior; and
- lifecycle requests.

Same-time event ordering belongs to the plan. An `EventBatch`-like value MAY exist as an internal
execution record but is not a separate model contract.

Solver-located root events remain Experimental until their root-location, tolerance, simultaneous
root, restart, and lifecycle timing contracts pass a source-backed gate.

### Mapping and symbol references

Every process read and write resolves during lowering to a qualified state identity. Public
qualified references are required only when authoring is ambiguous or crosses domains.

A mapping law declares source snapshot, domain, filter, aggregation, empty behavior, normalization,
destination, and timing. General runtime name lookup and shadowing are prohibited.

### Experimental process families

Adaptive solvers, DAEs, SDEs, deterministic reaction systems, discrete jumps, hybrid reactions, and
root events have extension points but are not stable Phase 14 contracts. Unsupported use MUST fail
during lowering or preflight. It must never be approximated silently.

## Contract 3: Plan

### One clock

The plan owns one exact global time coordinate. It declares the exact duration represented by one
completed Potts MCS. Integer MCS remains the public Potts progress coordinate.

For completed MCS index `m` and exact MCS duration `Δt`, the corresponding global interval is:

```text
[(m - 1)Δt, mΔt]
```

Process steps, subcycles, and convergence iterations are local numerical policies within that
interval. They are not additional semantic clocks.

Time values used for identity, scheduling, and checkpoint position MUST be exact decimal/rational
values or another canonical exact representation. Floating-point solver time MAY be derived from
them but cannot be the scheduling authority.

### Plan entries

One ordered plan contains entries for:

- Potts attempt stages;
- accepted-copy hooks associated with those stages;
- ordinary processes;
- lifecycle commits;
- observations; and
- stable checkpoint boundaries.

Each entry declares:

- identity;
- activation window;
- cadence or exact times;
- priority and deterministic tie-break identity;
- read snapshot;
- commit boundary; and
- enabled stage or parameter bindings.

Positional MCS plans, staged protocols, `During`-style activation, sampled events, and multirate
schedules MUST lower to these entries.

### Ordering and conflict validation

The compiler constructs a dependency graph from entry order, reads, writes, snapshots, and commit
boundaries.

It MUST reject:

- two same-boundary writes without an explicit composition or priority law;
- a read whose required producer has no preceding visible commit;
- conflicting lifecycle requests without a resolution law;
- ambiguous same-time events;
- missing stable checkpoint boundaries;
- a plan with no Potts attempt stage when Potts evolution is requested; and
- multiple authorities for global time or MCS duration.

Source order is semantic only when materialized as plan order. Container iteration order is never
semantic.

### Stages and scheduled parameters

A stage is an activation window plus parameter/process bindings on the same plan. Stage selection
for a target MCS occurs before that MCS's first entry and remains immutable through the MCS unless
the plan explicitly defines a finer global-time boundary.

Parameter schedules MUST resolve to immutable values for each invocation and belong in the
fingerprint.

### Stable boundary

The completed-MCS boundary after required observation remains the only stable checkpoint boundary
in the initial contract. A process failure before that point is terminal unless its law defines a
scientifically valid rollback. Partial-MCS restart is not supported.

## Contract 4: Lifecycle

### Requests and commit

Processes emit typed requests for create, divide, transform, remove, or another registered
lifecycle effect. Requests do not mutate authoritative cell identity/state immediately.

One lifecycle plan entry:

1. collects requests visible at its snapshot;
2. validates identities and generations;
3. resolves conflicts by the registered deterministic policy;
4. stages geometry, state inheritance, relationship cleanup, and tracker effects;
5. commits atomically using the frozen lifecycle transaction law; and
6. records diagnostics and continuation-relevant results.

There is no independent lifecycle clock or scheduler.

### State obligations

Every state declaration whose owner can be affected by lifecycle MUST provide the relevant policy:

- initialization for new identities;
- division inheritance or recomputation;
- type-transition behavior;
- retirement cleanup; and
- slot-reuse reset with generation validation.

Missing policies are compile-time/preflight failures, not defaults inferred from storage.

### Relationship and pending-event cleanup

Retiring an identity MUST resolve all incident relationships, queued lifecycle requests, delayed
events, and generation-scoped histories according to their registered policies. Stale endpoints or
events cannot silently attach to a reused slot.

## Contract 5: Observation

An observation declaration contains:

- identity and version;
- read snapshot;
- cadence or exact plan times;
- typed inputs;
- pure transform/reduction law;
- output schema and units;
- provenance and evidence role;
- missing/empty behavior; and
- failure policy.

Observations never mutate scientific state.

Required scientific observations are fatal on failure. Only explicitly non-scientific,
best-effort telemetry may be nonfatal, and it cannot contribute to validation or reproduction
claims.

Paper-specific compositions and downstream statistical analysis belong in published-model source,
but their primitive observables, schedule, transforms, and source authority MUST remain
fingerprinted and inspectable.

## Contract 6: Spatial Roles

The accepted focused spatial-role contract remains:

- proposal;
- contact;
- surface;
- connectivity;
- query; and
- field relations

are independently declared and fingerprinted. Omission preserves the existing Phase 13 first-shell
lowering exactly.

The canonical model stores each role's relation identity, realized offsets, metric, boundary
behavior, and version. Domain façades may provide concise relation constructors but cannot infer a
source simulator's neighborhood silently.

## Contract 7: Potts Algorithm Identities

`SequentialCPM` v1 remains exactly `N` independent sequential attempts per MCS.

A source-specific attempt budget uses a separately named algorithm identity, initially
`BudgetedSequentialCPM` with an `AttemptsPerSite`-equivalent exact multiplier. Its identity includes:

- attempt-budget law;
- proposal law;
- acceptance law;
- update/transaction law;
- semantic RNG contract; and
- version.

The new algorithm begins as a sequential CPU reference and does not inherit any backend claim from
`SequentialCPM`. Stable promotion requires its own backend-resident Metal and ROCm implementation,
real-hardware evidence, and GPU-native qualification under Decision 0032.

## Biological Authoring Façades

The recommended user API is hybrid:

- Level 1 biological declarations for common mechanisms;
- Level 2 explicit law/state/process declarations; and
- direct CorePotts kernel protocols for extension authors.

Candidate façades include activity state, site decay, cell dynamics, field dynamics, field
exchange, relationship dynamics, staged protocols, equation-style continuous systems, delays,
events, and paper observations.

Every façade MUST expose its lowered canonical representation through inspection. It MAY add
defaults only when those defaults are stable, documented, fingerprinted, and source-appropriate.

### Generic hierarchical composition

Flat `PottsModel(declarations...)` remains the concise spelling for small models and all frozen
Phase 13 use. Complex coupled models compose through the existing `ModelFragment` concept. No
separate `CoupledModel`, `Subsystem`, field runtime, relationship runtime, or paper-specific core
model type is introduced.

A fragment provides:

- one stable identity, version, and lexical namespace;
- named typed requirements;
- private declarations and nested fragments;
- named typed exports;
- compatibility, provenance, and backend requirements; and
- no independent clock, scheduler, persistence format, or runtime state.

A named requirement describes the semantic category and all compatibility information necessary
to validate a binding, including owner, schema, units, lifecycle obligations, capabilities, and
backend requirements where applicable. A named export refers to one admitted state, process
operation, observation, relation, parameter, or other registered semantic value. Neither boundary
uses untyped runtime name lookup.

The exact requirement/export constructor names remain Provisional. The stable semantic rule is
that fragments connect through named typed ports and lower those references to canonical qualified
identities before fingerprinting or execution.

Plans reference exported process operations:

```julia
Phase(:field, Advance(secretome.advance))
Phase(:uptake, Exchange(secretome.uptake))
Phase(:signaling, Advance(signaling.advance))
```

The property-like spelling denotes an immutable exported semantic reference, never mutable
fragment storage. Private declarations cannot be referenced outside the fragment.

There is still exactly one normalized root plan. Fragments may export operations, and a documented
convenience façade may contribute fully inspectable plan entries, but no fragment owns a hidden
local scheduler. Convenience entries are expanded and conflict-checked in the root plan.
Dependencies validate explicit order and never topologically choose scientific order.

Equivalent explicit leaves and fragment-packaged declarations normalize to the same scientific
fingerprint. Fragment paths remain in composition reports and diagnostics. A different binding,
namespace, law, schedule, or exported declaration changes canonical identity normally.

Paper-specific builders may be supplied in tutorial or paper-example modules only after the same
model is expressed through this generic API. Selected paper or author names MUST NOT enter the
stable CorePotts or PottsToolkit export surface merely to hide authoring complexity.

Backend requirements are derived transitively after complete fragment lowering. A fragment cannot
hide host fallback, synchronization, transfer, allocation, unsupported storage, or an unqualified
law. Decision 0032 applies unchanged to every stable execution capability reached through a
fragment.

### Illustrative direct-kernel spelling

The exact Julia constructors are Provisional, but the semantic shape is:

```julia
state = StateSpec(
    id = :activity,
    owner = SiteOwner(),
    schema = ScalarSchema(Float64; lower = 0),
    storage = CurrentStorage(),
    lifecycle = SiteOwnershipPolicy(...),
)

copy_update = ProcessSpec(
    id = :activity_on_accept,
    reads = (read(state, TransactionSnapshot()),),
    writes = (write(state),),
    law = AcceptedCopyActivity(...),
    commit = AcceptedCopyCommit(),
)

decay = ProcessSpec(
    id = :activity_decay,
    reads = (read(state, ProcessSnapshot()),),
    writes = (write(state),),
    law = GeometricDecay(...),
    commit = SynchronousCommit(),
)

plan = ExecutionPlan(
    mcs_duration = ExactTime(1),
    entries = (
        PottsEntry(...; accepted = (copy_update,)),
        ProcessEntry(decay; every = EveryMCS(1)),
        LifecycleEntry(...),
        ObservationEntry(...),
        StableBoundary(),
    ),
)
```

A Level 1 `Act(...)` declaration may generate the same records. If it does, both spellings have the
same canonical identity.

## Continuous-System Façade

An equation/rule-oriented `ContinuousSystem`-equivalent declaration MAY remain available for
authors and adapters. Lowering decomposes it into:

- state declarations for unknowns and histories;
- process laws for equations, rules, assignments, mappings, and sampled events;
- plan entries for cadence and ordering;
- lifecycle requests and policies; and
- observation declarations.

No `ContinuousSystem` object remains as an independent runtime authority after lowering.

ModelingToolkit may produce this façade or the kernel records directly through an optional
PottsToolkit extension. CorePotts MUST NOT depend on ModelingToolkit and MUST NOT store
ModelingToolkit objects as authoritative runtime state.

## Derived Projections

### Fingerprint

The scientific fingerprint is a canonical digest over the normalized kernel, including:

- all state/process/plan/lifecycle/observation identities and versions;
- spatial roles and realized relations;
- algorithm and RNG contracts;
- exact times, ordering, activation windows, priorities, and bindings;
- law/solver identities and parameters;
- lifecycle and history policies; and
- adapter source checksums and compatibility dispositions when an adapter was used.

Derived report formatting and physical storage layout are not fingerprint inputs.

### Persistence

For uncoupled Phase 13 models, `CanonicalCheckpoint` v1 bytes and behavior remain unchanged.

Coupled models use an additive versioned envelope containing the unchanged canonical checkpoint plus
blocks derived from declared future-relevant state, process solver state, plan position, lifecycle
queues, observation continuation state, and semantic time.

Authors do not enumerate checkpoint blocks separately. The compiler derives them from kernel
metadata and fails if a required state/process lacks a continuation codec.

### Backend preflight

Backend requirements are the union of the selected algorithm, storage policies, process laws,
solvers, relations, lifecycle effects, and observations. Preflight reports each unsupported
contract/law pair before mutation.

No coupled mechanism inherits a Phase 13 GPU claim. Every stable Phase 14 execution capability
requires its own backend-resident Metal and ROCm qualification. Host fallback cannot satisfy that
gate, even when separately named; silent fallback is prohibited.

GPU-native execution keeps simulation state, dynamic fields, relationship graphs, event and
lifecycle queues, histories, and accumulators on the selected device for the simulation interval.
Scalar host loops, hidden fallback, per-MCS state transfer, and steady-state allocation fail
qualification. Host execution is permitted for model authoring and complete lowering before
launch, and at explicit observation, checkpoint, user snapshot, and analysis boundaries with
bounded, measured transfers. The portable floating-point qualification profile is `Float32`; CPU
`Float64` paper-fidelity evidence remains a separate profile and cannot substitute for Metal
evidence.

### Compatibility reports

Adapters and compatibility checkers compare source constructs to the normalized kernel and report:

- exact semantic mapping;
- qualified numerical mapping;
- explicit approximation;
- partial mapping; or
- rejected mapping.

These are tooling results, not model state. An approximation or partial mapping cannot be promoted
to exact by successful execution.

## Six-Model Lowering Sketches

### Graner--Glazier 1992 sorting

- state: existing CPM state;
- process: existing contact/volume laws;
- plan: source attempt stage and boundary observation cadence;
- lifecycle: ordinary completed-MCS lifecycle;
- observation: boundary-length kinetics;
- spatial: explicit proposal/contact relations;
- algorithm: `BudgetedSequentialCPM` with the registered `16N` budget.

### Mombach 1995 three-dimensional sorting

- state: existing 3D CPM state;
- process: contact/volume laws and temperature-dependent acceptance;
- plan: registered temperature conditions and observation schedule;
- lifecycle: ordinary completed-MCS lifecycle;
- observation: experimental/simulation boundary trajectories;
- spatial: explicit 3D role relations;
- algorithm: source-budget identity after source closure.

### Merks 2006 vasculogenesis

- state: CPM state and extracellular field state;
- process: diffusion/decay, secretion, chemotaxis, and Potts laws;
- plan: one exact MCS interval with explicit field/CPM splitting;
- lifecycle: ordinary lifecycle unless the accepted source envelope requires more;
- observation: lacunae and branch-point definitions;
- spatial: proposal, contact, surface, query, and field relations;
- algorithm: source-attempt identity.

### Wortel 2021 Act-CPM

- state: site-owned activity plus existing CPM state;
- process: accepted-copy activity update and per-MCS decay;
- plan: 500-MCS burn-in, measurement window, output cadence, and exact phase order;
- lifecycle: reset/ownership policy even though the primary one-cell slice does not divide;
- observation: position, speed, persistence, and mode-map primitives;
- spatial: source activity-neighborhood and Potts relations;
- algorithm: source-attempt identity.

### Shirinifard 2012 CNV

- state: CPM, oxygen/VEGF fields, degradable structures, cell properties, histories, and
  relationships;
- process: field solvers/exchange, degradation, phenotype/timer rules, relationship updates, and
  lifecycle requests;
- plan: exact subcycling, source plugin order, stages, observations, and stable boundary;
- lifecycle: growth, division, death, transition, inheritance, and cleanup;
- observation: scenario-38 ensemble and Figure 7 primitives;
- spatial: explicit x/y periodic and z no-flux relations per role;
- algorithm: source-attempt identity.

### Wang 2025 collective tumor migration

- state: cell ODE state, bounded centroid history with registered source/paper offset variants,
  field state, and focal relationships;
- process: fixed-step ODE/rules, uptake, focal creation/retuning, polarity alignment, and
  protrusion-drive mapping;
- plan: relaxation/switch stages, per-MCS history and ten-MCS focal cadence, source plugin order,
  and observations at source MCS 90 and 270 / normalized target MCS 91 and 271;
- lifecycle: generation-safe state and relationship cleanup;
- observation: geometric features, migration modes, and parameter-map primitives;
- spatial: distinct proposal/contact/focal/field/query relations;
- algorithm: source-attempt identity.

The generic authoring fixture groups Wang's leaves into reusable field-coupling, intracellular
signaling, focal-relationship, motility/history, observation, and protocol fragments. These are
ordinary `ModelFragment` values with named typed requirements and exports; none has a Wang-specific
CorePotts or PottsToolkit type. One root plan references their exported operations and makes the
complete source order visible.

The Wang lowering MUST encode the accepted order as Potts and accepted-copy focal-topology commit;
scaled secretome field solve with diffusion followed by constant-medium concentration in each
substep; centroid sampling; self-polarity derivation; secretome uptake/calibration; same-MCS ODE
advance; ten-MCS focal retuning; synchronous neighbor-polarity alignment; protrusion-force
publication; lifecycle; and observations.

CompuCell3D's source label MCS `k` maps to normalized Potts.jl target MCS `k+1`: Potts.jl MCS 0 is
the finalized initial condition, whereas CompuCell3D executes a real Potts/field/Python iteration
labelled MCS 0. Source labels are exactly derived observation/provenance metadata, not a second
clock. No source `step()` work may be hidden in initialization. Consequently, source MCS 120, 210,
and 211 correspond to normalized target MCS 121, 211, and 212 and are direct read/write visibility
fixtures.

The five Wang field substeps are one numerical process. They read one immutable post-Potts
ownership/type snapshot, stage through two scratch grids, and publish only once after all five
substeps validate. A Medium constant-concentration operation is an exact post-substep reservoir
constraint, not additive forcing. Internal substeps and post-field/post-exchange phases are not
stable checkpoints.

Wang exchange mode is resolved by the root plan: inactive, reset-only, calibrate, or publish. The
exchange law may not branch on an undeclared process-local MCS scheduler. Calibrate and publish
atomically couple a staged field mutation, per-cell uptake reduction, cell-signal output, and one
global multiplier/status. A deterministic reduction profile and zero/nonfinite calibration
failure policy are mandatory.

Wang is one indivisible paper-faithful sequential CPU reference slice. Its secretome field,
histories, relationships, intracellular dynamics, and exact accepted-copy order are part of that
reference and cannot be substituted by a checkerboard algorithm while retaining the paper claim.
Decision 0035 deliberately makes the assembled Wang backend profile unsupported. Reusable state
and law families introduced by the slice remain subject to focused CPU/Metal/ROCm promotion when
they stabilize, beginning with the algorithm-suitable G4 field-model gate.

Each sketch MUST become an executable lowering fixture before its vertical slice is considered
complete.

## Morpheus Compatibility Boundary

Morpheus parity is construct-level semantic compatibility, not identical XML, GUI, plotting, or job
workflow.

Generic authoring parity additionally requires that nested Morpheus-style systems map to the same
`ModelFragment` requirement/export boundary used by hand-authored Wang and CNV models. An adapter
may construct fragments and bindings but cannot introduce adapter-only hierarchy, symbol lookup,
or scheduling semantics.

The stable initial kernel targets:

- global and per-cell typed state;
- field state and evolution;
- fixed-step ODEs;
- synchronous rules;
- reactive acyclic assignments and pure functions;
- histories and fixed delays;
- sampled events;
- typed mappings/reductions;
- lifecycle requests;
- exact MCS/global-time mapping; and
- exact completed-MCS continuation.

Membrane state is permitted by the state protocol but stabilizes only after its remapping fixture.
Automatic MorpheusML and SBML import remain optional adapter work. Advanced formalism rows keep
their Experimental status.

## Validation and Implementation Gate

### Architecture gate

Before runtime implementation resumes broadly:

- Registry v2 and the architecture checker pass.
- Every old contract has a recorded v2 disposition.
- Every capability and Morpheus row maps to the kernel or derived adapter boundary.
- The six lowering sketches above remain complete and unambiguous.
- No selected-model or author name is a stable CorePotts or PottsToolkit export.
- Complex Wang, CNV, and Morpheus fixtures use the same nested-fragment, named-requirement,
  named-export, and one-root-plan semantics.
- Fragment packaging versus equivalent explicit declarations has canonical fingerprint identity.
- Private access, incompatible bindings, and hidden plan authorities reject before execution.
- The candidate kernel API has canonicalization and conflict-validation tests.
- Registry v1 prototype exports are removed, internalized, or deliberately retained only as
  registry v2 façades; they are not added to the frozen Phase 13 surface.
- The Phase 13 API inventory and non-regression tests pass without regenerating the frozen
  inventory around obsolete v1 spellings.

### Wortel gate

The first vertical slice MUST prove:

- one accepted copy updates activity exactly once;
- rejected and no-op copies do not update activity;
- decay and neighborhood reduction occur at the declared plan positions;
- direct-kernel and `Act` façade spellings normalize identically;
- state, process, plan, observation, persistence, preflight, and inspection derive from one model;
- restart matches uninterrupted execution; and
- unsupported backends reject before mutation.

The CPU-reference evidence closed the first half of this gate. Real-hardware Metal and ROCm
evidence closed the second half on 2026-07-25 by proving:

- backend-resident activity state, accepted-copy updates, per-MCS decay, and neighborhood
  reductions without scalar host loops or hidden fallback;
- the exact attempt budget and semantic RNG addressing for the GPU algorithm identity;
- direct-kernel/façade equivalence, observation, checkpoint/restart, and replay or declared
  statistical equivalence on both backends;
- no per-MCS transfer or steady-state allocation, with declared synchronization and bounded
  observation/checkpoint transfers; and
- actionable preflight rejection for any unqualified law, storage policy, precision, or backend.

### Expansion gates

Wortel has passed both its CPU reference and Metal/ROCm closure, and Wang G3-B has passed its
sequential CPU gate. Decision 0035 retires G3-C assembled-model GPU qualification and opens G4 as
the current gate for broader boundary, solver, and exchange work on CPU, Metal, and ROCm. Every
later stable execution capability follows the same reference-then-device promotion rule, using an
algorithm-suitable fixture rather than requiring every paper reference assembly to be a GPU
workload.

## Phase 13 Freeze Impact

For a model with no Phase 14 declarations:

- normalization and fingerprint are byte-identical;
- `SequentialCPM` remains exactly `N` attempts;
- lifecycle and transaction semantics are unchanged;
- SciML integer-MCS stepping and saving are unchanged;
- `CanonicalCheckpoint` v1 is unchanged;
- existing RNG namespaces are unchanged; and
- CPU, Metal, and ROCm qualification claims are unchanged.

Any implementation that violates one of these statements requires a new incompatible D10 decision
and cannot merge under Phase 14.
