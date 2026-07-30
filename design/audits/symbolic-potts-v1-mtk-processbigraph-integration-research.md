# Symbolic Potts V1 ModelingToolkit and ProcessBigraphs Integration Research

Date: 2026-07-30

Branch: `codex/symbolic-potts-v1`

Status: complete research basis for the accepted integration amendment; no implementation
authorization

## Question

How should Symbolic Potts V1 be deeply native to the ModelingToolkit ecosystem while also
supporting Vivarium-style composition through ProcessBigraphs, without creating two symbolic
authorities, two schedulers, or a new cross-language runtime inside PottsToolkit?

The owner accepted the product direction in CI-017 through CI-021 and requested full research
before those decisions were consolidated into the normative specification.

## Research method

The audit covered:

- the current root and CorePotts dependency graphs;
- every current direct ProcessBigraphs use in PottsToolkit and CorePotts;
- the ProcessBigraphs process, port, schema, clock, engine, transaction, failure, and checkpoint
  protocols;
- the existing ProcessBigraphs SciML extension;
- current public ModelingToolkitBase and ModelingToolkit system, composition, input/output, event,
  and model-building interfaces;
- current SymbolicIndexingInterface problem, parameter, state, solution, and remake interfaces;
- Julia package weak-dependency and extension rules;
- ModelingToolkitStandardLibrary connector conventions;
- Catalyst's separation of domain statements from ordinary equations;
- the Process Bigraph paper and upstream Vivarium/process-bigraph component protocol; and
- the accepted Symbolic Potts V1 statement, completion, compiler, unit, stochastic, and
  clean-break contracts.

Primary and official external sources:

- [ModelingToolkit system API](https://docs.sciml.ai/ModelingToolkit/dev/API/System/)
- [ModelingToolkit composition](https://docs.sciml.ai/ModelingToolkit/stable/basics/Composition/)
- [ModelingToolkit input/output](https://docs.sciml.ai/ModelingToolkit/stable/basics/InputOutput/)
- [ModelingToolkit event handling](https://docs.sciml.ai/ModelingToolkit/dev/basics/Events/)
- [ModelingToolkit model-building API](https://docs.sciml.ai/ModelingToolkit/stable/API/model_building/)
- [ModelingToolkitStandardLibrary blocks](https://docs.sciml.ai/ModelingToolkitStandardLibrary/dev/API/blocks/)
- [SymbolicIndexingInterface API](https://docs.sciml.ai/SymbolicIndexingInterface/dev/api/)
- [Complete SymbolicIndexingInterface](https://docs.sciml.ai/SymbolicIndexingInterface/stable/complete_sii/)
- [SciMLBase problem interfaces](https://docs.sciml.ai/SciMLBase/dev/interfaces/Problems/)
- [Julia package extensions](https://pkgdocs.julialang.org/dev/creating-packages/)
- [Catalyst source](https://github.com/SciML/Catalyst.jl)
- [Process Bigraphs paper](https://arxiv.org/abs/2512.23754)
- [upstream process-bigraph](https://github.com/vivarium-collective/process-bigraph)
- [Vivarium process interface](https://vivarium-core.readthedocs.io/en/latest/tutorials/write_process.html)

Repository sources:

- `Project.toml`
- `lib/CorePotts/Project.toml`
- `lib/ProcessBigraphs/Project.toml`
- `lib/ProcessBigraphs/src/declarations.jl`
- `lib/ProcessBigraphs/src/schemas.jl`
- `lib/ProcessBigraphs/src/time.jl`
- `lib/ProcessBigraphs/src/engine_protocol.jl`
- `lib/ProcessBigraphs/src/managed_engine.jl`
- `lib/ProcessBigraphs/src/coupled_checkpoint.jl`
- `lib/ProcessBigraphs/src/logical_codec.jl`
- `lib/ProcessBigraphs/ext/ProcessBigraphsSciMLExt.jl`
- `src/reference_models/merks_2006.jl`
- `src/reference_models/wortel_2021.jl`

## Executive conclusion

The accepted two-level architecture is sound and strengthens, rather than distracts from, deep
ModelingToolkit integration:

```text
ModelingToolkit symbolic ecosystem
        |
        | public AbstractSystem accessors, namespaces, IO metadata, SII
        v
PottsSystem + EquationComponent
        |
        | Potts completion: CPM effects, phases, units, bounds, RNG, capabilities
        v
PottsExecutable -> PottsProblem -> CorePotts execution
        |
        | optional derived managed-engine adapter
        v
ProcessBigraphs runtime orchestration
        |
        +-- MTK/SciML peer
        +-- Vivarium/cross-language peer
        +-- service or independent simulator peer
```

The key is to distinguish **symbolic assimilation** from **runtime orchestration**:

- equations that must participate in Potts access analysis, scheduling, atomic publication, and
  indexing are assimilated through `EquationComponent`; and
- independently scheduled models remain peer components under ProcessBigraphs.

This yields one symbolic authority and one scheduling owner at each level. It also matches the
Process Bigraph distinction between composition interfaces and orchestration.

## Finding 1 — A custom `PottsSystem` is the native MTK design

ModelingToolkit's public architecture is explicitly based on `AbstractSystem` implementations.
The public interface distinguishes local accessors such as `get_eqs`, `get_unknowns`, `get_ps`,
`get_systems`, and `get_observed` from recursive, namespaced accessors such as `equations`,
`unknowns`, `parameters`, and `observed`.

Potts requires semantic information that a generic equation system cannot infer:

- proposal-context reads;
- synchronous, accepted-copy, relationship, and lifecycle effects;
- bounded structural mutation;
- semantic RNG draw sites;
- MCS phase ordering;
- lattice and relationship storage;
- checkerboard conflict safety; and
- backend and kernel capability.

Representing those facts as opaque `System` metadata would make them invisible to ordinary
symbolic traversal and would reproduce the old split authority. A Potts-owned
`PottsSystem <: ModelingToolkitBase.AbstractSystem` is therefore the equivalent of Catalyst owning
reaction-domain nodes and a reaction system while interoperating with ModelingToolkit equations.

Deep integration means implementing documented contracts thoroughly. It does not mean using
ModelingToolkit's concrete `System` layout or delegating Potts completion to generic equation
completion.

## Finding 2 — ModelingToolkitBase should be strong; full ModelingToolkit should be weak

The base package needs the common system contract on every load. It also needs Symbolics,
SymbolicIndexingInterface, DynamicQuantities, and SciMLBase for the already accepted authoring,
unit, problem, remake, and solution behavior.

Full ModelingToolkit is materially larger and is required only for higher-level transformations
and integration methods. Julia package extensions are designed for exactly this case: a weak
dependency is not installed automatically, and extension code loads when both packages are
present.

The final topology should be:

```text
PottsToolkit strong dependencies
    CorePotts
    ModelingToolkitBase
    Symbolics
    SymbolicIndexingInterface
    DynamicQuantities
    SciMLBase

PottsToolkit weak dependencies
    ModelingToolkit
    ProcessBigraphs
    Unitful

PottsToolkit extensions
    PottsToolkitModelingToolkitExt
    PottsToolkitProcessBigraphsExt
    PottsToolkitUnitfulExt
```

`EquationComponent` and `process_component` must be parent-owned public entry points. Extension
types are implementation details and should not become the public API because Julia does not make
extension-owned names ordinary parent-package bindings.

ModelingToolkitStandardLibrary does not need to be a weak dependency. Its components implement
ModelingToolkit system and connector conventions. It belongs in integration tests and examples;
the ModelingToolkit extension can ingest its supported systems without package-specific code.

## Finding 3 — `EquationComponent` should return a homogeneous Potts component

Introducing a second stored subsystem type would complicate composition, namespacing, completion,
and reconstruction. `EquationComponent` should instead be a public assimilation constructor whose
result is an incomplete `PottsSystem`.

The explicit shape should be:

```julia
@named field = EquationComponent(
    external_system,
    EquationProcess(
        :chemoattractant,
        equations(external_system);
        writes = [c],
        solver = ExplicitDiffusion(),
        cadence = EveryMCS(),
        duration_per_mcs = 30us"s",
        substeps = 15,
        phase = Before(Proposal()),
    ),
)
```

The constructor:

1. reads the external system through public local and recursive accessors;
2. creates a Potts subsystem with copied equations, unknowns, parameters, defaults, observations,
   supported events, inputs, outputs, and hierarchy;
3. constructs a source-to-assimilated symbolic identity map;
4. adds the explicit `EquationProcess`; and
5. returns an incomplete `PottsSystem` suitable for ordinary Potts composition and completion.

It must not retain an external numerical integrator or opaque runtime callback. It must not
silently call `mtkcompile`, `structural_simplify`, or another transformation. The caller passes the
exact symbolic system intended for assimilation and may explicitly transform it first.

This is important for auditability: hidden structural simplification could eliminate coupling
variables, rewrite event behavior, or change index identities before Potts completion sees them.

## Finding 4 — The supported external-system envelope must be closed

V1 should accept equation content that Potts completion can validate and schedule:

- scalar or symbolic-array algebraic equations;
- ordinary differential equations with zero or one continuous independent variable;
- declared unknowns, parameters, defaults, initial conditions, and observed equations;
- public input/output declarations;
- symbolic continuous and discrete events whose conditions, reads, writes, and effects can be
  lowered into the accepted Potts event/effect language; and
- nested supported systems, including ModelingToolkitStandardLibrary blocks and connectors after
  their connection equations are part of the supplied system.

V1 should reject, with qualified diagnostics:

- functional or opaque callback affects;
- noise equations, Brownian variables, and SDE semantics;
- jump systems or reactions that have not been explicitly converted into accepted Potts
  stochastic statements;
- delays and history semantics outside the accepted `HistoryState`/`lag` contract;
- PDE domains or discretization objects that have not been reduced to supported finite symbolic
  equations or arrays;
- initialization programs with executable callbacks;
- foreign code-generation, tearing, or solver caches;
- multiple continuous independent variables; and
- any event, connection, or equation whose writes, units, bounds, phase, or publication behavior
  cannot be proved.

Unsupported content must not be dropped or converted to a host callback fallback.

## Finding 5 — MTK input/output metadata should be the sole external-port declaration

The accepted constructor did not yet include explicit `inputs` and `outputs`, but deep MTK and
ProcessBigraph integration require an intentional external interface. Compiler read/write sets are
not sufficient: they include internal state and reveal implementation details that should not
become ports.

ModelingToolkit already provides `inputs(sys)`, `outputs(sys)`, `bound_inputs`,
`unbound_inputs`, `bound_outputs`, and `unbound_outputs`. Variables may carry input/output metadata,
and ModelingToolkitStandardLibrary connectors use the same concepts.

Therefore V1 should add `inputs` and `outputs` keyword collections to `PottsSystem` and implement
the public ModelingToolkitBase IO accessors. This is a narrow amendment to the accepted
keyword-oriented constructor, not a second port DSL.

The rules should be:

- `inputs` and `outputs` contain symbolic identities, not strings or path names;
- ordinary composition and equations determine which IO values are internally bound;
- only unbound IO values form the external executable interface;
- completion infers reads and writes and rejects a declared input that is written by Potts or a
  declared output that has no settled value;
- an output is either stored state at a valid publication boundary or an accepted observed value;
- array symbolics remain one shaped interface value unless explicitly indexed;
- exact unit and shape metadata are preserved;
- a symbol cannot be both an unbound input and a mutable Potts-owned output; and
- internal compiler reads/writes never become public ports merely because they were inferred.

This makes the same symbolic declaration authoritative for MTK composition, symbolic indexing,
and ProcessBigraph port derivation.

## Finding 6 — Current ProcessBigraphs already contains the correct runtime substrate

The local ProcessBigraphs package already provides:

- typed `PortSpec` inputs and outputs;
- `LeafSchema` shape, units, ownership, update law, persistence, residency, and codec metadata;
- immutable versioned `PortView` and `EngineInputProjection` snapshots;
- exact rational `TimeScale`, integer `LogicalTime`, and integer `Duration`;
- `AbstractEngineAdapter`, `EngineDeclaration`, and declared capability envelopes;
- `IntervalAdvance`, `BoundarySolve`, and `DiscreteBatch` operations;
- staged candidates, validation, publication, discard, early return, event requests, and failure;
- settled/fail-stop managed-engine runtime behavior;
- typed deltas rather than direct shared-state mutation; and
- replay-classed logical checkpoint components with adapter-owned checkpoint and restore hooks.

Those facilities align with the Process Bigraph and Vivarium principle that processes read an
input snapshot and emit typed updates rather than directly mutating shared state.

The existing Potts reference-model adapters bypass this intended boundary by defining bespoke
private PB processes in paper-model files, and CorePotts currently depends directly on
ProcessBigraphs. V1 should delete those paths and derive one generic adapter in
`PottsToolkitProcessBigraphsExt`.

## Finding 7 — A runnable PB component is constructed from `PottsProblem`

The accepted direction correctly says that schemas and capabilities derive from
`PottsExecutable`. A runnable process also needs initial state, parameters, seed, replica identity,
and a permitted horizon. Those values belong to `PottsProblem`, not `PottsExecutable`.

The exact public entry should therefore be:

```julia
component = process_component(prob::PottsProblem)
```

The extension derives the interface manifest and engine declaration from
`prob.executable`, while the problem supplies runtime initialization. This prevents initial state
and seed from leaking into symbolic completion or executable fingerprints.

The returned value should be an ordinary ProcessBigraphs process/component through public PB
interfaces. A private extension-owned `AbstractEngineAdapter` subtype may implement it internally;
users must not need to name or access that private type.

The adapter should use the managed-engine transaction protocol because a compiled Potts simulator
has internal state, resources, RNG, checkpoints, and atomic publication. Treating it as a simple
stateless Julia function would discard those guarantees.

## Finding 8 — MCS is the only legal V1 publication quantum

CorePotts execution is stochastic and has meaningful internal attempt, phase, and transaction
boundaries. ProcessBigraphs must not inspect or publish those incomplete states.

V1 bridge behavior should be:

- one invocation advances exactly one complete MCS;
- the adapter declares ProcessBigraphs `:interval_advance`, with the authorized interval equal to
  exactly one MCS;
- the PB input snapshot is frozen for that MCS;
- all output values are published together after the MCS commits;
- its process schedule declares partial interval advance unsupported;
- PB may invoke the component repeatedly for multirate orchestration;
- a native `:mcs` logical scale maps one tick to one MCS; and
- a physical PB time scale is admitted only when `duration_per_mcs` provides an exact conversion
  and every invocation boundary is an exact MCS multiple.

A nonintegral physical-time request is rejected before execution. Rounding, fractional MCS,
interpolation of Potts state, and mid-MCS callbacks are not V1 semantics.

This deliberately chooses semantic clarity over a premature multi-MCS batching API. A later
version may admit a batch only after specifying how external input changes, events, observations,
and failure boundaries behave inside the batch.

## Finding 9 — Port and checkpoint manifests should be derived

The bridge manifest derives from the completed and executable inspection records:

- qualified symbolic identity and a stable external endpoint `Symbol` derived from canonical
  qualified-identity serialization rather than source order;
- direction and inferred access;
- scalar type or array element type;
- exact shape or declared dynamic dimensions;
- canonical unit string and reference-unit conversion;
- ownership, persistence, update law, residency, and codec;
- input interval behavior;
- valid publication cadence;
- selected engine, backend, precision, and capability envelope;
- replay class;
- checkpoint schema version; and
- diagnostic and failure identities.

PB path placement remains a composition concern. The bridge exposes stable endpoint names and
schemas; the surrounding PB composite binds them to hierarchical store paths.

At invocation, external numerical inputs are validated against their declared type, shape, and
unit, then converted into the executable reference-unit system before being staged. Validation or
conversion failure leaves published Potts state unchanged. Outputs are read only after a complete
MCS commit and converted from executable reference units to their declared external units before
atomic PB publication. Requests beyond the problem horizon fail before execution.

Checkpoint capture is legal only when both runtimes are settled after a complete MCS publication.
The Potts adapter checkpoint contains logical CorePotts state, RNG continuation, completed-MCS
time, parameters required for continuation, executable identity, and schema identity. It does not
serialize an incomplete kernel, workspace scratch, Symbolics object graph, or external system.

Restore verifies executable fingerprint, schema, units, selected capability envelope, and replay
class before reconstructing runtime-owned buffers.

## Finding 10 — Cross-language compatibility belongs above the Potts bridge

The Process Bigraph paper describes language-agnostic JSON typing and independently developed
processes. The upstream process-bigraph implementation likewise uses explicit port schemas,
hierarchical stores, typed updates, and orchestrated execution.

A future cross-language boundary needs a language-neutral manifest and protocol for:

- component identity and protocol version;
- hierarchical port names;
- scalar/array schema and canonical unit strings;
- requested logical interval;
- immutable input snapshot and snapshot identity;
- typed output update;
- status, diagnostics, and failure;
- checkpoint capture and restore; and
- deterministic publication and replay classification.

The current local PB logical codec is a Julia logical-checkpoint codec, not by itself a complete
cross-language transport protocol. V1 must not claim that serializing Julia objects creates
Vivarium compatibility.

Python, Vivarium, JSON-RPC, Arrow, IPC, container, or service transport belongs in a future
ProcessBigraphs extension/package. PottsToolkit and CorePotts remain transport-neutral.

## Alternatives rejected

### Encode Potts semantics in ordinary `System` metadata

Rejected because it hides proposal, effect, phase, stochastic, relationship, and capability
meaning from a typed Potts completion pass.

### Strongly depend on full ModelingToolkit

Rejected because the base system and symbolic contracts live below it, while higher-level
operations are optional. A strong dependency would increase installation/load cost without
improving the core semantic boundary.

### Make `EquationComponent` an opaque simulator wrapper

Rejected because equations would not participate in Potts units, access analysis, phase
scheduling, atomic publication, or symbolic indexing.

### Automatically call `mtkcompile` during assimilation

Rejected because hidden transformation may eliminate coupling identities and change semantics
before Potts completion audits them.

### Derive ports from every inferred read and write

Rejected because internal implementation state would become public interface accidentally.
Explicit MTK IO metadata plus inferred validation is the correct separation.

### Implement the Potts bridge as a paper-model-specific `AbstractProcess`

Rejected because it duplicates interface descriptions and loses the generic executable,
transaction, checkpoint, and capability contracts.

### Allow fractional or mid-MCS PB publication

Rejected because incomplete stochastic phases are not settled Potts states and do not satisfy the
accepted scientific transaction semantics.

### Put Vivarium/Python dependencies in PottsToolkit

Rejected because cross-language transport is an orchestration concern and would reverse the
dependency direction.

## Conflict audit

| Accepted decision | Apparent conflict | Resolution |
|:--|:--|:--|
| One canonical `PottsSystem` | `EquationComponent` sounds like a second system | It is an assimilation constructor returning an incomplete `PottsSystem` |
| Exact keyword constructor | External ports were not listed | Add `inputs` and `outputs` as the integration amendment; no second port DSL |
| Potts-owned completion | Deep MTK integration | Implement public MTK interfaces; do not delegate Potts semantics to generic completion |
| Full MTK weak dependency | `EquationComponent` is public | Define the entry point in PottsToolkit; extension adds methods requiring full MTK |
| PB bridge derives from executable | Runnable state is not in executable | Interface derives from executable; `process_component` accepts `PottsProblem` for initialization |
| ProcessBigraphs owns global time | Potts owns MCS | PB schedules whole-MCS invocations; Potts owns execution inside each MCS |
| One scheduling owner | An MTK system might also be a PB component | Assimilated systems are Potts-scheduled; independent systems are PB-scheduled, never both |
| Cross-language product vision | V1 has no transport scope | Freeze the future protocol boundary but defer transport implementation |
| No migration work | Existing paper adapters exist | Delete and replace them; do not wrap or preserve their API |

No unresolved architectural conflict remains in the accepted integration direction.

## Required implementation acceptance

The later autonomous implementation phase must prove:

1. PottsToolkit loads and core authoring works without full ModelingToolkit, ProcessBigraphs, or
   Unitful installed.
2. Loading ModelingToolkit activates only the intended extension methods.
3. `@named`, property access, hierarchy, namespaces, variables, parameters, equations, defaults,
   observations, supported events, inputs, and outputs behave through public interfaces.
4. Source identities from a supported external system map to problem, remake, solution, and
   diagnostic identities after assimilation.
5. A representative ModelingToolkitStandardLibrary component can be connected and assimilated
   without package-specific internal access.
6. Unsupported external callbacks, stochastic systems, delays, PDE domains, and events fail with
   qualified diagnostics.
7. Loading ProcessBigraphs activates `process_component(prob)` without introducing a CorePotts PB
   dependency.
8. Derived PB schemas exactly match executable IO shape, unit, direction, and publication policy.
9. A PB invocation publishes one complete MCS atomically and rejects nonintegral time mapping.
10. Settled checkpoint/restore reproduces the declared replay contract.
11. The same component cannot be assimilated and independently scheduled simultaneously.
12. Absence/loading tests detect extension leakage, piracy, stale strong dependencies, and private
    API use.

These are ordinary package and integration tests. They do not require a freshness ledger,
one-time qualification system, compatibility oracle, or bespoke CI bureaucracy.

## Readiness judgment

The integration architecture is ready to become normative. It is compatible with the accepted
Symbolic Potts V1 compiler and strengthens the ProcessBigraphs product vision.

This research does not authorize implementation. The remaining project work is to finish the
consolidation interview and implementation-grade specification, audit the complete specification,
and receive explicit owner send-off.
