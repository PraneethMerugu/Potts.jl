# Symbolic Potts V1 Consolidation Owner Interview

Date opened: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: complete; Rounds 1 through 4 and the MTK/ProcessBigraphs integration direction accepted

Research basis:

- [`symbolic-potts-v1-consolidation-research.md`](symbolic-potts-v1-consolidation-research.md)
- [`symbolic-potts-v1-round-3-research.md`](symbolic-potts-v1-round-3-research.md)
- [`symbolic-potts-v1-round-4-research.md`](symbolic-potts-v1-round-4-research.md)
- [`symbolic-potts-v1-mtk-processbigraph-integration-research.md`](symbolic-potts-v1-mtk-processbigraph-integration-research.md)
- [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md)

## Purpose

This interview freezes the remaining implementation decisions required to turn the accepted
Symbolic Potts V1 product decisions into one autonomous, clean-break consolidation specification.
Accepted answers are owner authority for that specification. They do not authorize implementation
before the interview closes, the consolidation specification is written and audited, and the owner
gives explicit implementation send-off.

## Round 1 — Authority and ownership

Owner response: **accept all**

### CI-001 — Specification authority and clean break

Accepted.

Symbolic Potts V1 explicitly supersedes conflicting portions of the old authoring,
coupled-modeling, engine, dependency, and compatibility specifications.

- Existing scientific semantics for energy, topology, stochasticity, lifecycle, persistence, and
  reproducibility remain authoritative unless V1 explicitly changes them.
- Old `PottsModel`, `ModelFragment`, rule-expression, Lottery, tiled-engine, and coupled
  semantic-kernel requirements lose living authority.
- Historical specifications and evidence remain unchanged but are indexed as superseded.
- V1 provides no aliases, deprecated constructors, migration wrappers, compatibility tests, or
  dual compiler paths.

### CI-002 — Final package dependency direction

Accepted.

- PottsToolkit strongly depends on CorePotts, ModelingToolkitBase, Symbolics,
  SymbolicIndexingInterface, DynamicQuantities, and SciMLBase.
- ProcessBigraphs is a PottsToolkit weak dependency.
- Unitful is a PottsToolkit weak dependency.
- Full ModelingToolkit is an integration/test dependency unless a documented public production
  operation requires it.
- CorePotts does not strongly depend on ProcessBigraphs.
- CorePotts remains free of ModelingToolkitBase, ModelingToolkit, Symbolics,
  SymbolicIndexingInterface, and DynamicQuantities.
- ProcessBigraphs remains domain-neutral and independent of Potts packages.

The intended direction is:

```text
ModelingToolkitBase ─┐
Symbolics ───────────┤
SII ─────────────────┤
DynamicQuantities ───┼──> PottsToolkit ──> CorePotts
SciMLBase ───────────┘          │
                                └── optional ProcessBigraphs extension
```

### CI-003 — Model and executable ownership

Accepted.

- `PottsToolkit.PottsSystem` is the sole public symbolic model.
- `PottsToolkit.PottsExecutable` is the public compilation result and supports inspection and
  `PottsProblem` construction.
- CorePotts owns the lower-level `CorePotts.CompiledPottsProgram`.
- PottsToolkit does not re-export concrete CorePotts storage or kernel internals.
- Both current `PottsModel` types are removed.
- `compile` returns a new executable and never mutates the system.

### CI-004 — System lifecycle and value semantics

Accepted.

The explicit lifecycle is:

```julia
sys = PottsSystem(...)
completed = complete(sys)
executable = compile(completed; engine, backend, scalar_type)
prob = PottsProblem(executable, initial_state, tspan; p, seed, replica)
sol = solve(prob)
```

- Incomplete and completed models use the same `PottsSystem` type with private completion data.
- Transformations return new values.
- Constructors defensively copy mutable input containers.
- Completed systems cannot be composed, extended, or structurally modified.
- `compile` rejects incomplete systems instead of silently completing them.
- Engine, backend, precision, seed, initial spatial layout, runtime interval, and save schedule do
  not enter completion.
- `iscomplete(sys)` is public.
- A completed system cannot be renamed or structurally reconstructed by patching completion data;
  the operation must start from its incomplete symbolic source.

### CI-005 — Registered-statement registry

Accepted.

- `StatementRegistry` is an explicit host-side value.
- PottsToolkit provides `default_statement_registry()` for ordinary package-extension ergonomics.
- `complete(sys; registry=default_statement_registry())` accepts an explicit registry.
- Registration is idempotent only for an exactly matching schema identity, semantic version, and
  implementation definition.
- A conflicting registration is an immediate error.
- Completion resolves and freezes an immutable registry snapshot.
- Later registry mutation cannot change a completed system or executable.
- Compilation and runtime perform no registry lookup.
- Built-in statement families and symbolic operations do not use this registry.
- The registry exists only for `RegisteredStatement`.

## Round 2 — System and statement model

Owner response: the Round 2 direction and proposed simplifications are accepted except that the
legacy implementation MUST NOT become a temporary oracle. Equivalent tests, the rock-solid
specification, and a read-only temporary clone of the main branch replace that proposal.

### CI-006 — Canonical `PottsSystem` constructor

Accepted.

The canonical public constructor is keyword-oriented:

```julia
@named merks = PottsSystem(
    statements = @statements begin
        Lattice(...)
        CellKind(...)
        Volume(...)
        EquationProcess(...)
        Protocol(...)
    end,
    equations = field_equations,
    unknowns = [c],
    parameters = [D, α, ε, T],
    independent_variables = [t],
    systems = PottsSystem[],
    initial_conditions = Dict(),
    observed = Equation[],
    events = [],
)
```

- `name` is mandatory and is normally supplied by ModelingToolkit's `@named`.
- All fields except `name` default to empty collections.
- There is no positional constructor with a second public meaning.
- Continuous independent variables are explicit when equations require them. Normalized MCS
  remains a Potts clock rather than an implicit continuous independent variable.
- Construction performs cheap structural checks only.
- Completion performs semantic discovery and validation.
- A private reconstruction path supports documented ModelingToolkit operations without exposing
  concrete fields.
- A tested field inventory forces reconstruction, equality, fingerprinting, and inspection code
  to be considered whenever system storage changes.
- Arbitrary metadata cannot alter scientific semantics.

### CI-007 — Statement identity and optional source capture

Accepted with the source-capture simplification.

- Every declaration, state, process, observation, protocol, and registered statement receives a
  namespace-local `StatementID`.
- Processes and mutable resources require explicit names.
- Simple scientific terms may receive deterministic defaults derived from statement family and
  target.
- When a deterministic default is not unique, construction requires an explicit name. It does not
  append a source-order counter.
- Equations receive canonical structural identities after normalization. Duplicate normalized
  equations are errors.
- Identity never depends on vector position, object address, hash randomization, or source order.
- Fully qualified identity is the system namespace path plus local identity.

`@statements begin ... end` is an optional thin source-capture and collection macro:

- it does not parse scientific meaning;
- it does not infer schedules or effects;
- it evaluates ordinary constructors and attaches file, line, module, and displayed expression;
- direct constructor use is equally valid and records `UnknownSource()` unless `source=` is
  supplied; and
- compilation never depends on ASTs or on source information.

Diagnostics always report qualified identity and the rendered originating expression. They add an
exact source location when one was captured. Canonical handwritten fixtures use `@statements`;
programmatically generated models need not.

### CI-008 — Namespacing, composition, extension, and flattening

Accepted.

- `compose(parent, children...)` preserves hierarchy.
- Every child is an incomplete `PottsSystem` with a unique local system name.
- ModelingToolkit-compatible namespacing applies to variables, parameters, equations, statement
  expressions, resources, observations, and process references.
- `flatten(sys)` explicitly produces a new incomplete flat system containing qualified identities.
  Ordinary composition does not silently flatten.
- Hierarchical and explicitly flattened equivalents share a semantic fingerprint but may have
  different completed-system fingerprints.
- `extend(a, b)` merges two incomplete systems into one scope.
- Variables and parameters unify only by symbolic identity.
- The same printed name with different symbolic identity is an error.
- Duplicate statements, resources, processes, observations, protocols, events, or normalized
  equations are errors even when their definitions are identical.
- Conflicting initial conditions are errors; neither input silently wins.
- Completed systems are rejected by `compose`, `extend`, `flatten`, and rename operations.

### CI-009 — Closed built-in statement inventory

Accepted.

The stored V1 semantic nodes are:

1. `CellKind`;
2. `MediumKind`;
3. `LatticeDomain`;
4. `SpatialRelation`;
5. `SiteState`;
6. `CellState`;
7. `MediumState`;
8. `ModelState`;
9. `FieldState`;
10. `HistoryState`;
11. `RelationshipState`;
12. `ProposalEnergy`;
13. `ProposalDrive`;
14. `ProposalConstraint`;
15. `ProposalModifier`;
16. `SynchronousProcess`;
17. `AcceptedCopyProcess`;
18. `RelationshipProcess`;
19. `LifecycleProcess`;
20. `EquationProcess`;
21. `Observation`;
22. `Protocol`; and
23. `RegisteredStatement`.

Supporting boundaries, ownership policies, phases, relationship effects, lifecycle effects, solver
policies, cadences, and layouts are typed arguments rather than additional semantic authorities.

Pretty public constructors may have shorter names such as `Lattice`, `Volume`,
`LocalConnectivity`, and `AcceptedCopy`. High-level components contain no runtime or executable
closure. A component that expands into multiple statements returns a transparent `StatementSet`.
Its full expansion is available through `statements(component)` and is flattened immediately by
`PottsSystem`. `StatementSet` has no completion, compilation, execution, identity, or scheduling
authority.

Internally, related public statement constructors MAY share carefully chosen parametric storage
implementations. The public constructor names and diagnostic statement kinds remain distinct. The
implementation MUST NOT introduce a generic tagged node that moves ordinary dispatch into a
central behavioral switch.

### CI-010 — One ordinary-Julia structural interface

Accepted as a simplification of the proposed universal `StatementSchema`.

V1 does not begin with a public or universal statement-schema framework. Every built-in statement
implements one small internal structural traversal/reconstruction operation, conceptually:

```julia
map_symbolics(f, statement)
```

Generic code derives namespacing, substitution, symbolic discovery, and reconstruction from this
single operation. Ordinary methods own canonical identity, serialization, display, unit rules,
access/effect inference, boundedness, phase legality, reference semantics, capability inference,
and lowering.

The implementation MAY introduce a small internal immutable schema later only if concrete
repetition in the implemented statement types justifies it. Such a schema cannot become a second
semantic registry or public extension boundary. `RegisteredStatement` receives equivalent
traversal behavior from its frozen registry definition.

### CI-011 — No legacy oracle framework

Accepted.

- The old authoring/compiler/runtime path MUST NOT be retained, copied, wrapped, or reconstructed as
  a differential oracle.
- The consolidation MUST NOT add an oracle package, parity harness, qualification ledger,
  evidence-freshness system, dual-execution mode, or committed dependency on old production code.
- Existing logically equivalent scientific tests are rewritten against the V1 public path and
  retain their scientific assertions.
- The accepted specification is the semantic authority.
- During implementation an unmodified clone of the main branch MAY exist under a temporary
  directory as read-only reference material and for developer-run spot comparisons.
- The temporary clone is not a test dependency, release artifact, conformance authority, or
  repository deliverable.
- All living acceptance evidence executes only the new V1 path.

### Round 2 implementation strategy

The one autonomous phase proceeds through vertical internal slices:

```text
minimal PottsSystem
    -> volume/contact model
    -> sequential execution
    -> checkerboard execution
    -> Wortel activity
    -> Merks equations and field coupling
    -> focal relationships
    -> complete legacy deletion and QA
```

These slices are not owner review gates or separate product phases.

## Round 3 — Symbolic analysis and qualified IR

Owner response: **accept all**

### CI-012 — Closed symbolic operation vocabulary

Accepted.

V1 expressions support ordinary Symbolics arithmetic, comparisons, Boolean operations,
conditionals, indexing, and mathematical functions plus these closed Potts operation families:

- proposal bindings: `source_site`, `target_site`, `source_cell`, `target_cell`, `source_kind`,
  `target_kind`, `is_extension`, `is_retraction`, `new_contact`, and `lost_contact`;
- cell geometry: `cell_volume`, `cell_surface`, `cell_center`, `unwrapped_center`, and `distance`;
- spatial queries: `contact_measure`, `boundary_measure`, `neighbor_count`, `neighbor_sum`,
  `neighbor_mean`, and `neighbor_geomean`;
- fields: `field_value`, `field_gradient`, `laplacian`, and `occupancy`;
- relationships: `linked`, `degree`, `endpoint_a`, `endpoint_b`, and `edge_payload`;
- history: `lag` and `history_value`; and
- randomness: `draw` with the supported declarative `Bernoulli`, `Uniform`, `Normal`, and
  `UnitVector` distributions.

Binding values MAY provide readable property syntax such as `copy.source_cell`, `copy.target_site`,
`edge.a`, `edge.b`, and `edge.strength`. Such syntax constructs registered symbolic operations; it
does not access runtime object fields.

Bounded domains are typed statement arguments rather than scalar symbolic operations:

```julia
sites(domain)
cells(endothelial)
contacts(relation)
edges(focal_links)
incident_edges(focal_links, cell)
```

Effects are typed values outside Symbolics:

```julia
Assign(...)
Create(...)
Remove(...)
Retune(...)
Transition(...)
Divide(...)
Retire(...)
```

Mutation, allocation, iteration, and scheduling cannot be hidden in a symbolic function. Adding a
built-in Potts symbolic operation requires a PottsToolkit release. Third-party statement behavior
enters through `RegisteredStatement`, not an open symbolic-operation registry.

### CI-013 — DynamicQuantities and reference-unit policy

Accepted.

- Canonical declarations use symbolic units such as `us"μm"` and `us"s"`.
- Bare numerical values are dimensionless.
- Canonical model definitions do not use `u"..."` because it eagerly expands scale.
- Exact declared scale and dimensions survive construction, composition, substitution, completion,
  and inspection.
- ModelingToolkit unit validation is supplementary. Potts completion owns statement-specific unit
  validation and reference conversion planning.
- MCS is a discrete dimensionless semantic clock rather than a physical DynamicQuantities unit.
- Physical equation time enters through an explicit conversion such as
  `duration_per_mcs = 30us"s"`.

Completion accepts:

```julia
complete(
    sys;
    reference_units = DeclaredReferenceUnits(),
    registry = default_statement_registry(),
)
```

`DeclaredReferenceUnits()` selects units from explicit semantic anchors:

- lattice spacing anchors length;
- equation independent-variable metadata anchors physical time;
- temperature or Hamiltonian declarations anchor energy when dimensional; and
- state declarations anchor their stored quantity dimensions.

If a required dimension has no unique declared anchor, completion reports the candidates and
requires an explicit `ReferenceUnits` override. Reference-unit selection changes the
completed-system and executable fingerprints but not the semantic fingerprint. Runtime parameters
are converted into the selected reference units before execution. Symbolics and
DynamicQuantities do not reach device data.

### CI-014 — Inference owns accesses, effects, and bounds

Accepted.

- Expressions determine reads.
- Assignment and effect targets determine writes.
- Statement family and phase determine the permitted effect class.
- Typed iteration domains determine candidate bounds.
- Declared capacities and maximum degrees determine structural bounds.
- Explicit draws and reserved algorithm operations determine RNG sites.
- Compiler analysis determines engine and backend capabilities.

Users MAY declare ownership, storage policy, capacity, persistence, lifecycle policy, and intended
spatial relation. They cannot assert unchecked purity, boundedness, write sets, checkerboard
safety, or GPU compatibility.

If completion cannot prove an access, effect, unit, or bound, it fails with contextual diagnostics.
It does not fall back to arbitrary sequential host execution. A proven model MAY explicitly compile
only for sequential execution when checkerboard conflict safety is not established.

### CI-015 — Exact `EquationProcess` boundary

Accepted.

The canonical shape is:

```julia
EquationProcess(
    :chemoattractant,
    field_equations;
    writes = [c],
    solver = ExplicitDiffusion(),
    cadence = EveryMCS(),
    duration_per_mcs = 30us"s",
    substeps = 15,
    phase = Before(Proposal()),
)
```

- Referenced equations are present in the system equation collection.
- Written state is explicit and reads are inferred.
- Every written value has exactly one process owner in a phase.
- The process reads one declared immutable snapshot and atomically publishes its completed step.
- Substeps and cadence are structural protocol choices. Solver tolerances and coefficients MAY be
  runtime parameters where replacement does not change structure or capability.
- Supported native policies lower to CorePotts field or cell mechanisms.
- A user-supplied SciML algorithm MAY pass through a typed host solver policy without
  PottsToolkit depending on its algorithm package.
- An external ModelingToolkit system enters only through an explicit equation-component adapter
  exposing equations, unknowns, parameters, events, and coupling.
- Independently scheduled opaque simulators remain ProcessBigraphs components.
- `DirectLaw`, arbitrary callbacks, and hidden solver closures are not accepted.

### CI-016 — Qualified IR, fingerprints, and inspection

Accepted.

Completion produces immutable qualified statement records containing:

- fully qualified identity;
- statement kind and schema version;
- source and provenance;
- normalized Symbolics payload;
- inferred result type and units;
- reference-unit conversion;
- reads and writes;
- effect class and bound;
- RNG operations;
- phase and ordering dependencies;
- resource and storage requirements;
- admitted and rejected engines with reasons; and
- concrete lowering identity.

Fingerprints use versioned canonical bytes and SHA-256 rather than Julia `hash`, object identity, or
opaque `Serialization` output:

1. `SemanticFingerprint`;
2. `CompletedSystemFingerprint`; and
3. `ExecutableFingerprint`.

The public inspection selectors include:

```julia
inspect(sys, Statements())
inspect(sys, Variables())
inspect(sys, Effects())
inspect(sys, RandomOperations())
inspect(sys, Schedule())
inspect(sys, Capabilities())
inspect(sys, Fingerprints())

inspect(executable, StoragePlan())
inspect(executable, Kernels())
inspect(executable, Fingerprints())
```

Completed-system and executable inspection MAY retain host-side Symbolics, units, source strings,
and reports. `CompiledPottsProgram` and device storage contain none of them. Canonical semantic
serialization is implemented directly from versioned semantic fields and is not a general
checkpoint or migration format.

## Integration amendment — ModelingToolkit and ProcessBigraphs

Owner response: **accepted; research and consolidate these decisions into the specification before
continuing the interview**

Research resolution:

- [`symbolic-potts-v1-mtk-processbigraph-integration-research.md`](symbolic-potts-v1-mtk-processbigraph-integration-research.md)
- normative consolidation in SPV1-034 through SPV1-042 of
  [`spec/symbolic-potts-v1.md`](../../spec/symbolic-potts-v1.md)

### CI-017 — Deep ModelingToolkit integration through public seams

Accepted. The requested implementation-contract research is complete and incorporated through the
research resolution above.

- A custom Potts-owned `PottsSystem <: ModelingToolkitBase.AbstractSystem` and Potts-owned
  completion do not weaken ModelingToolkit integration. They are required because generic
  equation-system completion cannot infer Potts proposal, effect, stochastic, relationship, and
  spatial-storage semantics.
- ModelingToolkitBase remains a strong dependency.
- Full ModelingToolkit becomes a weak dependency with a dedicated
  `PottsToolkitModelingToolkitExt`.
- The base package owns the common `AbstractSystem`, Symbolics, SymbolicIndexingInterface, SciML,
  and DynamicQuantities behavior.
- The full-ModelingToolkit extension owns higher-level system ingestion and transformations that
  genuinely require ModelingToolkit.
- Integration uses documented public accessors and transformations rather than concrete system
  fields or compiler internals.

The V1 integration gate covers:

- `@named`, property access, nested composition, and flattening;
- unknowns, parameters, equations, observed equations, defaults, and supported events;
- substitution across Potts and equation components;
- symbolic problem and solution indexing;
- `remake` with symbolic keys;
- ingestion of a supported ModelingToolkit system;
- ingestion of a supported ModelingToolkitStandardLibrary component;
- namespaced diagnostics; and
- extension loading without private ModelingToolkit access.

### CI-018 — First-class `EquationComponent`

Accepted. The requested implementation-contract research is complete and incorporated through the
research resolution above.

`EquationComponent` is the explicit symbolic-assimilation boundary for a supported external
`AbstractSystem`. It exposes and preserves:

- hierarchy and namespaces;
- equations;
- unknowns and parameters;
- defaults;
- observed equations;
- supported continuous and discrete events;
- inputs and outputs;
- unit metadata; and
- symbolic indexing identities.

It produces a homogeneous Potts symbolic component with an explicit `EquationProcess`. Unsupported
external semantics are rejected contextually rather than silently dropped. The originating
symbolic identities remain valid for problem construction, `remake`, solution indexing, and
diagnostics.

`EquationComponent` is not a general runtime wrapper. Assimilated equations participate in Potts
completion, units, access analysis, phase scheduling, compilation, and atomic publication.

### CI-019 — Two-level composition model

Accepted. The requested implementation-contract research is complete and incorporated through the
research resolution above.

The ecosystem has two intentionally different composition levels:

1. `PottsSystem` and `EquationComponent` provide compile-time symbolic composition for tightly
   coupled mathematics under one Potts completion and execution protocol.
2. ProcessBigraphs provides runtime orchestration for independently scheduled engines,
   simulators, components, services, or language runtimes.

A component chooses exactly one scheduling owner:

- an assimilated `EquationComponent` is scheduled and published by the Potts executable; or
- an external ProcessBigraphs component is invoked, exchanged, failed, checkpointed, and published
  by ProcessBigraphs.

The same component cannot be scheduled at both levels.

### CI-020 — Derived Potts-to-ProcessBigraphs bridge

Accepted. The requested implementation-contract research is complete and incorporated through the
research resolution above.

The PottsToolkit ProcessBigraphs extension derives a ProcessBigraphs-compatible component from a
`PottsExecutable` and its qualified inspection model. The bridge derives, rather than asks the user
to redescribe:

- qualified inputs and outputs;
- schemas and units;
- reads and writes;
- time and MCS relationships;
- valid publication boundaries;
- logical checkpoint behavior; and
- capability and failure information.

ProcessBigraphs owns paths, external schemas, invocation, global or multirate time, reconciliation,
failure, checkpoint coordination, and publication. CorePotts owns Potts state, copy attempts,
kernels, workspaces, transactions, and numerical execution. ProcessBigraphs never reaches into an
incomplete MCS or kernel schedule.

### CI-021 — Cross-language components remain ProcessBigraphs peers

Accepted product direction; cross-language transport implementation is not automatically V1 branch
scope.

A future Vivarium or other cross-language component enters through a language-neutral
ProcessBigraphs component boundary with typed hierarchical ports, schemas and units, requested
time, immutable input snapshot, output update, status/failure, logical checkpoint, and
deterministic publication.

Python, Vivarium, IPC, and service dependencies do not enter PottsToolkit or CorePotts. A compiled
Potts component, an MTK/SciML solver component, and a Vivarium component are peers under
ProcessBigraphs orchestration.

### Integration research clarification

The accepted amendment is frozen with these implementation-contract clarifications:

- `EquationComponent` is a public assimilation constructor that returns an incomplete
  `PottsSystem`; it is not a second stored system type.
- The full ModelingToolkit extension adds only behavior that genuinely requires ModelingToolkit;
  base system and SII behavior remains parent-owned.
- `inputs` and `outputs` are added to the canonical `PottsSystem` keyword constructor and use the
  public ModelingToolkit IO model. No Potts-specific port DSL is added.
- The external interface consists only of unbound declared IO, validated against inferred
  accesses. Internal reads and writes do not become ports.
- Interface metadata derives from `PottsExecutable`, while the runnable public bridge is
  `process_component(prob::PottsProblem)` because initialization and seed are runtime values.
- The PB adapter uses the managed-engine transaction and logical-checkpoint protocols and advances
  exactly one complete MCS per invocation.
- A physical PB clock is admitted only through exact `duration_per_mcs` conversion at integral MCS
  boundaries.
- Cross-language transport remains deferred and cannot be claimed from the Julia checkpoint codec
  alone.

These clarifications refine CI-017 through CI-021 without changing their accepted product
direction.

## Round 4 — Runtime and clean-break consolidation

Owner response: **accept all**

Research basis:
[`symbolic-potts-v1-round-4-research.md`](symbolic-potts-v1-round-4-research.md).

### CI-022 — Executable and compilation contract

Accepted.

The canonical compilation boundary is:

```julia
completed = complete(sys)
executable = compile(
    completed;
    engine = SequentialEngine(),
    backend = CPUBackend(),
    scalar_type = Float32,
)
```

- `engine`, `backend`, and `scalar_type` are mandatory explicit selections.
- V1 has `SequentialEngine()` and `CheckerboardEngine()`. Backend extensions may provide
  Potts-owned immutable descriptors such as `MetalBackend()`, `ROCmBackend()`, and
  `CUDABackend()`.
- Compilation fixes engine semantics, backend and device target, scalar and accumulator policy,
  storage layout and capacity, schedules, RNG sites, transactions, equation policies, observation
  kernels, capabilities, and checkpoint schema.
- `PottsExecutable` is immutable and privately laid out. Its public accessors and `inspect`
  surface expose configuration, fingerprints, qualified manifests, symbolic indices, runtime
  parameter and initial-state schemas, external IO, storage/workspace/kernel reports, capabilities,
  checkpoint/replay information, and diagnostics. It privately owns one
  `CorePotts.CompiledPottsProgram`.
- A compiled executable contains no unresolved registry lookup, external ModelingToolkit system,
  quantity object, Symbolics expression, source AST, or executable host closure.
- `solve` and `init` cannot replace the executable's engine, backend, precision, capacity, or
  numerical policies.
- V1 has no public compilation cache and no hidden PottsToolkit global or disk compilation cache.
  Users compile once and reuse the immutable executable.
- Compilation reports all independent validation and capability failures that can be discovered
  safely in one pass, with stable identities and source context, rather than exposing only the
  first arbitrary failure.

### CI-023 — Parameters, initial state, problem, and RNG

Accepted.

- The compiler proves whether each symbolic parameter is structural or runtime-replaceable.
  `tunable` metadata is author intent only and cannot override dependency analysis.
- A value is structural when it can affect topology, dimensions, shape, element or storage type,
  capacity, maximum degree, statement/equation/event/RNG-site existence, phase, cadence,
  substeps, iteration, accesses, effects, bounds, conflicts, solver or workspace structure,
  generated code, or capability admission.
- Every structural value resolves by default or substitution before completion and enters the
  completed-system and executable fingerprints. Changing one requires substituting an incomplete
  system, completing it, and compiling a new executable.
- A runtime parameter changes only a validated numerical leaf without changing units, shape,
  storage, analysis, scheduling, solver family, or capability. It is normalized into a typed
  executable-owned parameter buffer and does not change the executable fingerprint.
- Capacity is structural and is never guessed or resized by `PottsProblem`.

The canonical host-side initialization and problem surface is:

```julia
initial = PottsInitialState(
    ownership = LabelledCells(
        labels;
        cells = [1 => endothelial, 2 => endothelial],
        medium = extracellular,
    ),
    values = [
        activity => activity0,
        chemoattractant => concentration0,
    ],
)

prob = PottsProblem(
    executable,
    initial,
    (0, 1000);
    p = [
        temperature => 20.0,
        diffusion => 1.0us"μm^2/s",
    ],
    seed = 0x1234,
    replica = 1,
)
```

- `ownership` is either `LabelledCells` or an `OwnershipLayout` made from accepted
  `CellPlacement`, `MediumPlacement`, or procedural placement declarations.
- Mutable initialization inputs are defensively copied. Defaults fill missing values; conflicting,
  unknown, duplicate, unit-incompatible, shape-incompatible, structural, and unresolved values
  are contextual errors.
- `p` accepts a symbolic pair collection or dictionary and is immediately normalized into an
  immutable typed `PottsParameters` value.
- `PottsProblem` contains the executable, normalized initial state, runtime parameters, absolute
  integer MCS span, `UInt64` seed, and positive bounded replica identity. It contains no algorithm,
  backend, capacity guess, callback, saving policy, compilation cache, or host realization
  function.
- Every `init(prob)` creates independent mutable runtime state.
- Simulation randomness is addressed by seed, replica, semantic stream, absolute MCS, operation,
  entity, invocation, and draw. Thread, worker, device, scheduling, and completion order never
  enter the address.
- Procedural initialization uses a separate semantic stream and cannot shift simulation draw
  sites.
- SciML ensemble `sim_id` supplies replica identity unless an explicit valid replica is returned.
  Ensemble-repeat identity remains a distinct deterministic RNG address component rather than
  replacing the master seed.

### CI-024 — SciML runtime, solution, and checkpoint

Accepted.

The canonical runtime relation is:

```julia
sol = solve(prob; saveat = 10, observables = [cell_area, concentration])
solve(prob; kwargs...) = solve!(init(prob; kwargs...))
```

- There is no positional solve algorithm. `init` validates and allocates but does not advance.
  `step!` advances exactly one complete MCS; `solve!` repeats that same operation.
- Accepted solve controls are saving (`saveat`, `save_start`, `save_end`, and
  `save_everystep`), observations, `maxiters`, progress controls, and verbosity.
- Generic adaptivity, `dt`, tolerances, `sensealg`, continuous callbacks, and arbitrary host
  callbacks are rejected. Equation processes own typed numerical policy; model mutation uses
  accepted events, protocols, runtime-parameter transactions, or external inputs.
- `remake` may replace only `u0`, runtime `p`, integer `tspan`, seed, and replica. It cannot replace
  the executable or structural choices.
- A running integrator accepts SII `setp` only at a settled complete-MCS boundary, only for
  compiler-proven runtime parameters, and only as an atomic validated transaction effective at the
  next MCS. The update is checkpointed and recorded in parameter provenance.
- `PottsSolution` is a real `SciMLBase.AbstractTimeseriesSolution` with the expected collection,
  return-code, statistics, provenance, and SII contracts. It supports exact saved-integer-MCS and
  symbolic indexing, has no dense or fractional interpolation, and never silently recomputes or
  transfers an unsaved observable.

The V1 checkpoint surface is:

```julia
cp = checkpoint(integrator)
integrator = init(prob; checkpoint = cp)
```

- `PottsCheckpoint` is captured only at a settled complete-MCS boundary.
- It contains executable identity, logical state, runtime parameters and history, RNG seed,
  replica and continuation state, completed MCS, schema, replay class, and integrity checksum.
- It excludes scratch workspaces, live kernels, Symbolics graphs, external systems, registries,
  and arbitrary Julia serialization.
- Restore validates the exact required executable, schema, unit, capability, and replay envelope
  before reconstructing private runtime buffers.
- V1 provides no reader, converter, alias, migration path, or compatibility wrapper for a previous
  checkpoint schema. Applicable scientific checkpoint assertions are rewritten against the new
  schema.

### CI-025 — Public API and clean-break source disposition

Accepted.

- Names needed in ordinary model source are exported. Structured diagnostics, qualified IR and
  manifests, fingerprints, canonical serialization needed by extensions, SII support, traversal
  and registered-statement hooks, and backend/ProcessBigraph adapter hooks are qualified `public`
  names. Compiler passes, builders, storage, workspaces, kernels, concrete adapters, cache keys,
  namespace internals, and CorePotts transaction implementations are private.
- Source `export` and `public` blocks are the API authority. V1 has no generated API ledger,
  migration registry, or compatibility alias inventory.
- CorePotts exposes a narrow qualified interface centered on `CompiledPottsProgram`, runtime
  initialization and whole-MCS advance, logical state/checkpoint import and export, capability and
  execution reports, and required backend hooks. PottsToolkit does not re-export CorePotts
  storage, workspace, kernel, tracker, request, transaction, or schedule types.
- Root `src/authoring/**` and the SciML interface are replaced around V1. Root reference-model
  builders and compatibility code are deleted; Merks, Wortel, and focal-link behavior becomes
  visible test fixtures rather than package-owned hidden builders.
- Lottery and tiled-checkerboard engines, CorePotts ProcessBigraph adapters and conversion code,
  paper-specific CorePotts assemblies, compatibility aliases, and legacy checkpoint readers are
  deleted.
- Qualified relationship, field, lifecycle, history, observation, transaction, initialization,
  persistence, sequential, checkerboard, checkpoint-integrity, and capability mechanisms are
  extracted behind `CompiledPottsProgram` before the old coupled declarations, plans, schedules,
  semantic-kernel authority, and public dispatch are removed.
- MakiePotts may be adapted to the new runtime and solution interfaces to keep the package family
  coherent. That work does not authorize tutorials or other user-facing documentation on this
  branch.
- ProcessBigraphs itself remains outside the clean-break rewrite except for a minimal public
  protocol change proven necessary for the optional PottsToolkit extension.

### CI-026 — Tests, CI, main reference, and supersession

Accepted.

The required gate is ordinary Julia package QA:

- Linux package tests for PottsToolkit and CorePotts;
- the repository's normal ProcessBigraphs and MakiePotts package tests;
- ModelingToolkit, ModelingToolkitStandardLibrary, ProcessBigraphs, Unitful, and optional-extension
  integration tests;
- fresh macOS and Windows load plus one tiny sequential CPU trajectory;
- Aqua and ExplicitImports checks;
- stale old surface and dependency-boundary checks;
- targeted inference and warmed CPU allocation checks at owned function barriers;
- same-seed/same-replica replay and different-replica divergence;
- Merks, Wortel, and focal-link end-to-end scientific fixtures; and
- one black-box public flow from authoring through solution access.

The gate explicitly excludes evidence freshness, one-time release qualification, a legacy parity
oracle, expected-output archives, package-wide mandatory JET, hard wall-clock budgets, GPU
availability as a prerequisite for CPU work, documentation/browser QA, per-file coverage, and a
coverage ratchet. Performance and real-hardware GPU qualification are manual or hardware-specific.
If a hard coverage threshold remains, it is one simple project threshold no higher than 90%.

An implementation agent may clone the exact main branch into a temporary directory only for
read-only inspection and spot reference. The clone is not a parity authority, CI dependency,
generated oracle, evidence archive, or retained repository artifact.

Historical specifications and evidence remain indexed, but conflicting legacy authoring,
compiler, SciML, API-inventory, compatibility, migration, adapter-ownership, checkpoint-migration,
and evidence-system clauses are explicitly superseded by the Symbolic Potts V1 specification.
Scientific CPM, published-model, and ProcessBigraphs semantics survive where the V1 specification
does not explicitly replace them.

Because user-facing documentation is excluded from this branch, a merge that intentionally breaks
living public documentation must wait for or be paired with the later V1 documentation phase. This
branch itself adds no migration documentation, replacement tutorials, or browser gate.

## Interview closure

CI-001 through CI-026, including the MTK/ProcessBigraphs amendment, are accepted. No owner product
decision remains open from this interview.

Acceptance closes the interview but does not authorize production implementation. Before
implementation, the accepted decisions must be assembled into the implementation-grade
consolidation specification, audited against the repository and surviving scientific authorities,
and explicitly sent off by the project owner.
