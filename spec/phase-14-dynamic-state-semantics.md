# Phase 14 Dynamic State Ownership Semantics

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: Site, cell-history, relationship, and delay requirements now specialize the single
`state` and `process` contracts in the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md).

## Purpose

This document defines the additional authoritative state families required by the Phase 14
published-model corpus: site properties, bounded cell histories, and dynamic relationship sets. It
also defines how existing `CellProperty` state participates in continuous and coupled processes.

Execution order belongs to
[Phase 14 Coupled Execution and MCS Plan Semantics](phase-14-coupled-execution-semantics.md).
Continuous laws, field evolution, relationship mutation, and coupled persistence receive focused
contracts separately.

This document extends the accepted [State Model](state-model.md),
[Auxiliary State Semantics](auxiliary-state-semantics.md),
[Lifecycle](lifecycle.md), and [Persistence](persistence.md) contracts.

## State Design Rules

Every authoritative dynamic value MUST have:

- one stable semantic identity;
- one owner domain;
- one concrete normalized value schema;
- explicit initialization;
- invariants and failure behavior;
- explicit writers and legal snapshot readers;
- lifecycle or ownership-change behavior;
- persistence and observability;
- backend storage and adaptation requirements;
- a semantic version; and
- conformance evidence.

No state is created by first assignment. A misspelled or undeclared identity fails normalization.

Mutable dictionaries, arbitrary per-cell object graphs, closure-captured state, process-local global
variables, and unregistered arrays are not stable scientific state.

## State Categories

The candidate stable surface governed by this document contains:

| State | Owner domain | Existing or new | Typical use |
| --- | --- | --- | --- |
| `CellProperty` | finite cell identity and generation | existing | scalar/vector polarity, intracellular species, target values |
| `SiteProperty` | realized lattice site | new | Act activity, material state, degradation state |
| `CellHistory` | finite cell identity/generation plus sample slot | new | centroid or property history |
| `Field` execution state | field lattice and semantic field time | existing identity; evolving contract new | chemoattractant, oxygen, VEGF |
| `RelationshipSet` | canonical generation-aware cell pairs | new | focal links, adhesion relationships |
| staged-protocol position | model execution | new execution state | relax/stimulated stage |

`GlobalProperty`, `MembraneProperty`, and general `DelayState` belong to the expanded
[Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md)
contract because their ownership and clocks are inseparable from that system language.

Model-global immutable scientific data remains `ModelParameter` or `ScheduledParameter`. This
document does not introduce a general mutable model dictionary.

## CellProperty Reuse

`CellProperty` already accepts any declared isbits value satisfying its normalized type and
invariant contract. `SVector`, small immutable structs, and scalar values therefore share the
existing property family:

```julia
polarity = CellProperty(
    :polarity,
    Tumor;
    initial = SVector(0.0f0, 0.0f0),
    division = CopyToBoth(),
    transition = Preserve(),
    retirement = Reset(),
)
```

Phase 14 does not add `VectorCellProperty`, `ODEStateProperty`, or other redundant categories.

Continuous processes write mapped `CellProperty` values through declared phase transactions. They
cannot retain an independent authoritative state array that diverges from the property schema.
Solver workspaces and reconstructible caches remain non-authoritative unless a continuation profile
requires their exact state.

## SiteProperty

### Identity and schema

A `SiteProperty` declares state indexed by every realized lattice site:

```julia
activity = SiteProperty(
    :activity;
    initial = 0.0f0,
    invariant = ClosedPropertyInterval(0.0f0, 1.0f0),
    ownership = AcceptedCopyManaged(),
    visibility = PublicProperty,
    persistence = CheckpointedProperty,
)
```

The normalized fields are:

- `SemanticName`;
- concrete isbits value type;
- typed initializer;
- invariant;
- ownership-change policy;
- visibility;
- persistence;
- optionality if a capability can be absent; and
- semantic version.

A site property's realized shape exactly matches the ownership lattice unless a distinct
coarse-field contract is used. It follows the lattice's canonical site order in logical snapshots
and persistence.

### Initialization

The first stable initialization policies are:

```julia
FillSites(value)
SiteValues(array)
InitializeFromOwnership(law)
```

`FillSites` uses one validated value. `SiteValues` requires exact dimensionality and records the
source checksum when used in a published model. `InitializeFromOwnership` is a pure typed law over
the finalized initial ownership snapshot.

Initialization occurs after ownership layout finalization and before MCS 0 becomes observable. It
does not run accepted-copy or per-MCS processes.

### Ownership-change policy

Every `SiteProperty` MUST choose exactly one ownership-change policy:

```julia
PreserveAtSite()
ResetChangedSites(value)
AcceptedCopyManaged()
```

`PreserveAtSite` leaves site values unchanged when ownership changes.

`ResetChangedSites(value)` stages the validated reset value for every site whose owner changes and
commits it with the ownership transaction.

`AcceptedCopyManaged` requires one compatible accepted-copy writer for every ownership-change path
under each admitted algorithm. Model normalization rejects the property if gained/lost behavior can
be left undefined.

No default policy is inferred because this choice changes model dynamics.

The first stable slice does not permit different hidden behavior for CPU and GPU. A backend unable
to implement the selected policy rejects the model during preflight.

### Reads and writes

Site properties are read through typed site-state accessors. A process declares whether it reads:

- one proposal recipient/donor site;
- a static spatial relation around one site;
- all sites;
- ownership-filtered sites; or
- a declared reduction.

Writers are limited to:

- accepted-copy transaction effects;
- `SiteDynamics` phase transactions;
- lifecycle effects whose contract explicitly admits site writes; and
- initialization or restore.

Energy evaluation cannot mutate a site property.

### Invariants

Constructor validation checks literal initializer compatibility. Runtime commit validates any
invariant not guaranteed by the compiled update law.

Invariant failure aborts the owning transaction or phase before publication. Silent clipping is
prohibited unless the update law explicitly declares and fingerprints a clipping policy.

### Persistence

An authoritative checkpoint stores:

- property identity and version;
- value schema and invariant identity;
- ownership-change policy;
- canonical values;
- semantic update time if not derivable; and
- checksum and compatibility metadata.

Ephemeral site properties cannot influence future scientific execution. If a future process reads
the value, persistence is required for exact continuation.

## CellHistory

### Identity and schema

A `CellHistory` is a bounded generation-aware ring buffer:

```julia
centroid_history = CellHistory(
    :centroid_history,
    Tumor;
    source = Centroid(),
    length = 5,
    initial = RepeatInitialSample(),
    division = ResetChildHistory(),
    transition = PreserveHistory(),
    retirement = ResetHistory(),
)
```

It declares:

- semantic identity and version;
- eligible owner scope;
- source property or observable;
- concrete sample type;
- positive fixed length;
- initial-fill policy;
- division, transition, and retirement policies;
- visibility and persistence; and
- periodic-coordinate or unwrapping requirements where applicable.

History length is model semantics. It is not a solver or memory-tuning parameter.

### Sampling

Sampling occurs only through a named `HistorySample` invocation in an `MCSPlan` phase:

```julia
centroid_sample = HistorySample(centroid_history)
```

All eligible cells read the same phase snapshot. Samples publish simultaneously. Cell ID order,
thread scheduling, workgroup layout, and active-slot compaction do not change sample meaning.

One invocation appends at most one sample per eligible cell. A future multi-sample phase requires an
explicit multiplicity and subinterval contract.

### Initial-fill policies

The first stable policies are:

```julia
RepeatInitialSample()
MissingUntilFull()
ExplicitInitialHistory(values)
```

`RepeatInitialSample` fills every slot from the MCS 0 source value and marks the history full.

`MissingUntilFull` tracks a fill count. Reads requiring unavailable lags fail validation or return
an explicitly typed missing result according to the consuming law; they never read uninitialized
memory.

`ExplicitInitialHistory` validates exactly `length` chronologically ordered samples per initialized
cell and records their source/checksum where applicable.

No initial-fill policy is implicit for a published model.

### Chronological meaning

Logical history order is oldest to newest. Physical ring layout and head position are internal.
Snapshot access exposes semantic lag:

```julia
history_value(history, cell, Lag(0))  # newest
history_value(history, cell, Lag(4))  # five samples including newest
```

`Lag(n)` requires a nonnegative integer. `history_value(state, history, cell, Lag(n))` returns the
concrete sample value when available and raises a structured `HistoryLagUnavailableError` before
the consuming transaction publishes otherwise. A rule that permits unavailable history uses
`maybe_history_value`, which returns the concrete isbits `HistoryValue{T}` tagged with
`available::Bool`; it does not return `missing` or expose uninitialized memory. The consuming law
must declare its unavailable-value policy.

### Cell generations

A history belongs to `(CellID, CellGeneration)`, not a reusable slot alone. Reads and writes reject
stale generations.

Retirement clears authoritative fill/head metadata before the slot can be reused. A newly allocated
cell receives state solely through the declared division/initialization policy.

### Lifecycle policies

Candidate division policies are:

```julia
ResetChildHistory()
CopyParentHistory()
TransformHistories(law)
```

The parent behavior is also explicit when a division geometry changes the meaning of the recorded
observable.

Candidate transition policies are `PreserveHistory()`, `ResetHistory()`, or a typed transform.
Retirement resets by default, but the explicit policy remains visible in normalized meaning.

Newly created cells do not sample again during the lifecycle phase that created them. Their first
ordinary history sample occurs at the next plan invocation for which they are eligible.

### Periodic positions

A centroid history declares whether it stores:

- wrapped positions;
- unwrapped positions under one accepted unwrapping tracker; or
- displacements already resolved under a named minimum-image law.

Mixing wrapped samples with ordinary subtraction is rejected when the domain has periodic axes.
The Wang polarity calculation must select one of these meanings explicitly.

### Persistence

The canonical checkpoint stores:

- history identity and version;
- sample schema and declared length;
- canonical oldest-to-newest samples or an equivalent canonical encoding;
- fill counts;
- ring heads if the payload is physically ring ordered;
- owner generations;
- lifecycle policies; and
- latest successful sample phase/time.

Restore validates that logical history order is identical regardless of backend storage layout.

## RelationshipSet

### Identity and endpoint domain

A `RelationshipSet` is a bounded graph whose endpoints are finite cell identities plus generations:

```julia
junctions = RelationshipSet(
    :junctions,
    Tumor => Tumor;
    edge = FocalPointEdge{Float32},
    maximum_degree = 4,
    capacity = RelationshipCapacity(512),
    endpoint_lifecycle = RemoveIncidentEdges(),
    persistence = CheckpointedProperty,
)
```

It declares:

- semantic identity and version;
- allowed left and right endpoint scopes;
- directed or undirected meaning;
- concrete isbits edge payload schema;
- global capacity and optional maximum degree;
- duplicate-edge policy;
- endpoint lifecycle policies;
- visibility and persistence; and
- canonical ordering.

### Canonical edge identity

An undirected edge identity is:

```text
min((cell_id, generation), (cell_id, generation))
max((cell_id, generation), (cell_id, generation))
```

A directed edge preserves declared source and destination roles.

Cell IDs alone are insufficient. Reuse of a retired slot never revives an old edge.

Self-edges reject by default. A relationship family requiring self-edges needs a separate explicit
contract.

### Payload

The payload is one concrete isbits value or small immutable struct. A focal-point payload may
contain strength, target length, maximum length, or source-specific metadata.

Mutable dictionaries, abstract payloads, heap object references, and backend handles are invalid
authoritative payloads.

Payload invariants are declared and checked before edge creation or retuning commits.

### Capacity and degree

Capacity is explicit problem/model data. Exhaustion is a structured scientific execution failure
unless the relationship declares a deterministic bounded rejection policy.

`maximum_degree` constrains the logical graph. Simultaneous create requests that would exceed it
use an explicit conflict resolver. Atomic arrival, relationship-array order, or cell iteration order
cannot determine the winners.

### Readers and writers

Energy components and processes read one immutable graph snapshot. The existing fixed
`FocalPointSpringHamiltonian` continues to read its fixed tuple and is not reinterpreted as a
relationship set.

Only:

- a declared relationship transaction;
- lifecycle endpoint handling;
- initialization; or
- restore

may write a dynamic set.

Energy evaluation cannot create, remove, or retune edges.

### Lifecycle

Endpoint retirement MUST select one policy, initially:

```julia
RemoveIncidentEdges()
RejectEndpointRetirement()
TransferEdges(law)
```

Division MUST specify whether:

- neither child inherits;
- one identified continuation cell retains applicable edges;
- edges copy under a bounded rule; or
- a typed transform replans relationships after division.

The default for a dynamic set is to remove edges incident to a retired generation. No silent
transfer to a reused ID is permitted.

Relationship lifecycle writes commit with the applicable lifecycle transaction or an explicitly
ordered subsequent phase accepted by the lifecycle contract. The selected rule must prevent an
observable state with stale endpoints.

### Persistence

Canonical persistence stores:

- relationship identity and version;
- endpoint and payload schemas;
- capacities and policies;
- edges in canonical semantic order;
- endpoint generations;
- payloads;
- lifecycle policies; and
- checksums.

Internal adjacency arrays, free lists, hash tables, sort buffers, and device layouts are
reconstructible unless the exact continuation profile proves otherwise.

## Staged-Protocol State

The current `StagedProtocol` identity and stage-local clock are execution state rather than mutable
user model data.

At a completed MCS they are derivable from the target/completed MCS and immutable stage ranges.
Checkpoints nevertheless record them and restore verifies the derivation. A mismatch is corruption
or contract incompatibility.

`ScheduledParameter` values are immutable model data and are not checkpoint payloads except through
the model fingerprint/reconstruction record.

## Field and Continuous State Boundary

Evolving field values and continuous solver state are authoritative coupled state but receive their
numerical and splitting laws in the focused cell/field dynamics specification.

The state boundary is:

- mapped cell ODE variables live in `CellProperty`;
- field variables live in the realized field state;
- materialized process inputs are phase-local unless required for restart at a stable boundary;
- solver caches are reconstructible unless the declared exact continuation profile requires them;
  and
- a ModelingToolkit symbolic object or generated function address is never authoritative runtime
  state.

## State Access and Extension

CorePotts exposes typed, allocation-free scientific accessors for qualified readers:

```julia
site_property_value(state, property, site)
history_value(state, history, cell, lag)
relationship_edges(state, relationships, cell)
relationship_payload(state, relationships, edge)
```

`maybe_history_value` is the tagged nonthrowing history accessor described above.
`relationship_edges` exposes canonical semantic order in host snapshots; device consumers declare
bounded reductions and do not depend on physical adjacency order. These accessors hide physical
array paths, property offsets, ring layouts, graph storage, and backend handles.

A downstream state family is admitted only if it:

- owns a distinct scientific domain not expressible by existing state;
- supplies initialization, access, mutation, persistence, inspection, and conformance protocols;
- declares backend capabilities conservatively;
- works through public CorePotts extension points without source edits; and
- does not introduce arbitrary mutation into existing components.

## Inspection

`explain(model)` and `explain(prob)` show for every state declaration:

- identity, category, version, and owner domain;
- concrete logical schema;
- initializer;
- invariants;
- writers and readers;
- ownership/lifecycle policies;
- visibility and persistence;
- memory scaling;
- backend residency/support;
- checkpoint payload; and
- unresolved capability restrictions.

For a realized problem, reports include site count, history capacity/length, relationship capacity,
estimated authoritative bytes, workspace bytes, and host/device placement.

## Failure Semantics

State-related failures are structured and include:

- invariant violation;
- missing required initializer;
- incompatible value conversion;
- undefined ownership-change behavior;
- stale cell generation;
- missing history lag;
- relationship duplicate;
- relationship capacity or degree exhaustion;
- invalid payload;
- unsupported lifecycle interaction;
- checkpoint schema mismatch; and
- backend capability failure.

Failures occur before the owning transaction publishes. A state accessor encountering a stale
generation or invalid identity does not return a default value.

## Compatibility

This contract is additive if:

- existing `CellProperty`, field snapshots, fixed focal points, logical state, and uncoupled
  checkpoint meanings remain unchanged;
- new state appears only in models that declare the applicable capability;
- uncoupled model fingerprints and checkpoint bytes do not acquire empty dynamic-state blocks;
- fixed focal-point source remains accepted independently of `RelationshipSet`;
- new public state identities are separately versioned; and
- every backend claim is capability-specific.

Any need to change existing property slot-generation, checkpoint, fingerprint, or lifecycle
semantics requires a D10 decision before implementation.

## Conformance

Before acceptance, this contract requires:

1. constructor, schema, invariant, and unsafe-conversion tests;
2. declaration-order and normalization-canonicality tests;
3. site-property initialization and all ownership-change policy truth tables;
4. accepted-copy versus phase-write conflict tests;
5. history initial-fill, lag, wraparound, generation, division, transition, and retirement tests;
6. periodic centroid history tests;
7. relationship directed/undirected identity, duplicate, capacity, degree, payload, and generation
   tests;
8. lifecycle endpoint and slot-reuse tests;
9. memory, HDF5, and Zarr canonical round trips;
10. exact completed-MCS restart tests;
11. downstream state-access and relationship-payload fixtures;
12. backend preflight rejection for every unqualified state family; and
13. bounded memory/allocation measurements for realistic site, history, and relationship sizes.

## Closed Surface Decisions

- The first stable site ownership policies are exactly `PreserveAtSite`,
  `ResetChangedSites(value)`, and `AcceptedCopyManaged`.
- `AcceptedCopyManaged` remains distinct. Normalization validates complete writer coverage; it does
  not infer scientific ownership behavior from the incidental presence of a writer.
- History access uses nonnegative `Lag`, strict `history_value`, and tagged
  `maybe_history_value` as defined above.
- A `RelationshipSet` owns scientific degree/edge bounds in the model; `PottsProblem` owns realized
  physical storage capacity and must satisfy those bounds. State-dependent exhaustion aborts the
  complete phase unless a separately declared biological selection law bounds the accepted set.

The remaining questions are source requirements, not state architecture:

- Wang must select wrapped positions, accepted unwrapped tracking, or minimum-image displacements;
- CNV must select its exact vascular-relationship division policy; and
- the CNV audit must confirm whether one bounded `SiteProperty` fully represents its degradable
  structure.
