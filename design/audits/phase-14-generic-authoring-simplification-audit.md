# Phase 14 Generic Authoring and Composition Simplification Audit

Status: Complete; generic hierarchical composition is the accepted correction

Date: 2026-07-25

Governing architecture:

- [Decision 0031](../../spec/decisions/0031-phase-14-single-semantic-kernel.md)
- [Decision 0032](../../spec/decisions/0032-phase-14-gpu-native-promotion.md)
- [Decision 0033](../../spec/decisions/0033-phase-14-generic-hierarchical-authoring.md)

## Verdict

The seven-area semantic kernel is appropriately small, but the proposed complex-model authoring
surface is not yet sufficiently abstract.

The Wang sketch exposed the problem by passing roughly twenty leaf declarations positionally to
`PottsModel`, then referring to many of the same process values again inside `MCSPlan`. Although
those arguments are technically order-independent declaration varargs, the spelling presents
implementation leaves rather than biological subsystems. The CNV sketch has the same scaling
problem.

A paper-specific `Wang2025(...)` constructor would shorten the example without solving the library
design. It would hide a weak general composition boundary behind a model-specific wrapper.

The accepted correction is:

1. retain flat declarations for small models and Phase 13 compatibility;
2. use the existing `ModelFragment` concept as the one generic hierarchical composition unit;
3. extend fragments with named, typed requirements and named, typed exports;
4. let plans reference exported process operations rather than private leaf declarations;
5. retain exactly one explicit normalized execution plan;
6. lower the hierarchy completely to the seven-area semantic kernel before execution; and
7. permit paper-specific builders only in tutorials or paper-example modules after the same model
   has been demonstrated through the generic API.

This changes authoring organization, not runtime semantics. It does not add a `CoupledModel`,
domain-specific runtime, second scheduler, or paper-specific CorePotts/PottsToolkit API.

## Evidence

### Flat construction was designed for smaller models

The Phase 11 authoring contract intentionally made `PottsModel` accept a flat, order-independent
sequence of typed declarations. That remains effective for a small CPM model:

```julia
PottsModel(medium, Tumor, volume, adhesion)
```

It does not scale naturally to a coupled model containing multiple fields, histories, ODEs,
relationship processes, observations, and an exact multi-stage schedule. The issue is not a
numerical argument-count threshold. The issue is that the root model exposes private implementation
leaves and requires the reader to reconstruct subsystem boundaries mentally.

### `ModelFragment` already owns most of the right semantics

The existing fragment contract provides:

- immutable declaration bundles;
- lexical namespaces;
- private declarations;
- reusable typed roles;
- binding;
- nested composition;
- normalized flattening; and
- collision and dependency validation.

Creating a new `Subsystem`, `CoupledModule`, or paper-specific model class would duplicate these
semantics. The missing capability is a strong, ergonomic port boundary:

- requirements must be named and typed beyond only cell and field roles;
- exports must be named operations or state references, not an anonymous identity tuple;
- binding must validate semantic category, owner domain, schema, units, and required capabilities;
  and
- plans must be able to reference exported operations without exposing fragment-private values.

The exact Julia constructor spelling remains Provisional. This audit freezes the semantic
requirements, not an unnecessary family of port wrapper types.

## What “powerful” means

The goal is not merely a shorter Wang example. The generic API must support:

- arbitrary nesting without global-name conventions;
- reusable fragments parameterized by typed biological roles and semantic inputs;
- substitution of a field solver, continuous law, relationship law, observation, or process
  implementation without rebuilding unrelated subsystems;
- coupling across cell, site, field, membrane, relationship, global, history, and lifecycle
  domains through checked ports;
- exact sequential, synchronous, staged, periodic, and multirate workflows through one plan;
- independent third-party law and fragment extension without editing a central paper taxonomy;
- direct Julia, ModelingToolkit, and future MorpheusML authoring routes that normalize to the same
  model;
- complete inspection, provenance, continuation, and failure diagnostics after composition; and
- transitive CPU/Metal/ROCm preflight and qualification without hidden host execution.

This is the relevant path beyond Morpheus-level workflow expressiveness: typed reusable
composition, open Julia law extension, explicit execution semantics, and production GPU lowering.
It is not achieved by mirroring Morpheus XML or by claiming compatibility before the registered
fixtures pass.

## Accepted generic composition model

### Fragment

A fragment is the only hierarchical authoring boundary. It may contain declarations and nested
fragments. It owns:

- one stable identity and lexical namespace;
- named typed requirements;
- private declarations;
- named typed exports;
- compatibility and backend requirements;
- provenance and version; and
- no independent runtime, clock, scheduler, checkpoint format, or backend state.

### Requirement

A requirement describes the semantic contract that a binding must satisfy. Depending on category,
that includes:

- state/process/observation/spatial/algorithm category;
- owner domain;
- value schema and units;
- read/write or operation kind;
- lifecycle obligations;
- capabilities; and
- backend requirements.

A requirement is never an untyped string or runtime dictionary lookup.

### Export

An export is a stable local name mapped to one declaration, process operation, observation, or
other admitted semantic reference. Exporting a value does not expose mutable runtime storage.

Named exports support readable composition such as:

```julia
Advance(secretome.advance)
Exchange(secretome.uptake)
Update(adhesions.retune)
```

The names are lexical authoring paths. Lowering resolves them to canonical qualified identities
before fingerprinting or execution.

### Root plan

There is exactly one normalized global plan. It references fragment exports and remains the sole
authority for order, cadence, stages, snapshots, lifecycle commit, observations, and stable
boundaries.

Fragments may provide operation exports and documented convenience expansions. They cannot own
hidden local schedulers. A convenience façade may contribute plan entries only when its complete
expansion is inspectable, conflict-checked, and merged into the one root plan. Dependency sorting
cannot silently choose scientific order.

### Lowering

Normalization:

1. resolves and validates fragment bindings;
2. qualifies private identities;
3. resolves named export paths;
4. expands admitted convenience entries;
5. produces one flat canonical state/process/plan/lifecycle/observation model;
6. derives backend requirements and continuation obligations; and
7. erases authoring hierarchy from runtime authority while retaining it in provenance and
   inspection.

Two models that differ only by valid fragment packaging normalize to the same scientific
fingerprint. Authoring paths remain available in composition and diagnostic reports but do not
change scientific identity unless a namespace or binding changes a canonical declaration.

## Illustrative generic spelling

This spelling is illustrative; constructor names for typed requirements and named exports remain
Provisional.

```julia
secretome = ModelFragment(
    :secretome,
    secretome_field,
    secretome_dynamics,
    secretome_uptake;
    requires = (
        cells = cell_population_requirement,
        medium = medium_requirement,
    ),
    exports = (
        advance = secretome_dynamics,
        uptake = secretome_uptake,
        signal = sensed_secretome,
    ),
)

signaling = ModelFragment(
    :signaling,
    rac_state,
    rac_dynamics;
    requires = (
        cells = cell_population_requirement,
        signal = secretome.signal,
    ),
    exports = (
        advance = rac_dynamics,
        activity = rac_state,
    ),
)

adhesions = ModelFragment(
    :adhesions,
    focal_relationships,
    focal_topology,
    focal_retuning;
    requires = (cells = cell_population_requirement,),
    exports = (
        relationships = focal_relationships,
        topology = focal_topology,
        retune = focal_retuning,
    ),
)

motility = ModelFragment(
    :motility,
    polarity,
    centroid_history,
    centroid_sample,
    polarity_from_history,
    neighbor_alignment,
    protrusion_drive;
    requires = (
        cells = cell_population_requirement,
        activity = signaling.activity,
        adhesions = adhesions.relationships,
    ),
    exports = (
        sample = centroid_sample,
        derive = polarity_from_history,
        align = neighbor_alignment,
        force = protrusion_drive,
    ),
)
```

The root plan remains explicit:

```julia
workflow = MCSPlan(
    PottsAttempts(on_accept = (adhesions.topology,)),
    Phase(:field, Advance(secretome.advance)),
    Phase(:history, Sample(motility.sample)),
    Phase(:self_polarity, Update(motility.derive)),
    Phase(:uptake, Exchange(secretome.uptake)),
    Phase(:signaling, Advance(signaling.advance)),
    Phase(:retune, Update(adhesions.retune);
        schedule = PeriodicMCS(10, 10)),
    Phase(:alignment, Update(motility.align)),
    Phase(:force, Update(motility.force)),
    LifecyclePhase(),
    ObservationPhase(outputs),
)

model = compose(
    PottsModel(Tumor, Medium),
    secretome,
    signaling,
    adhesions,
    motility,
    outputs,
    workflow,
)
```

None of these fragment identities or exports is Wang-specific. The same composition mechanisms
must express the Morpheus compatibility fixtures and CNV workflow.

## Rejected simplifications

### Paper-specific public constructors

`Wang2025`, `CNV2012`, or similar constructors may exist in paper-example modules. They cannot
serve as evidence that the core authoring API is generic, and no selected-model name may enter the
CorePotts or PottsToolkit stable export surface.

### Category buckets on `PottsModel`

Keywords such as `states=`, `fields=`, `processes=`, and `events=` merely rearrange the flattened
list. They create another public taxonomy and do not provide namespace, reuse, private internals,
or typed coupling.

### Independent domain systems

Separate cell, field, relationship, event, or ODE runtimes duplicate clocks, scheduling,
persistence, and backend authority. Domain-specific law façades remain acceptable only when they
lower completely through fragments to the same kernel.

### Automatic dependency ordering

Dependencies validate a declared plan but cannot infer a scientifically meaningful order.
Especially for Wang, two valid dependency orders can have different MCS 120/210/211 behavior.

### Opaque convenience bundles

A fragment cannot hide declarations, defaults, capability failures, synchronization, or schedule
entries from inspection. Encapsulation is not opacity.

## Acceptance gates

The generic authoring pass is complete only when:

1. no selected-model name is exported by CorePotts or PottsToolkit;
2. flat `PottsModel` construction remains valid for small and all frozen Phase 13 models;
3. nested fragments support named typed requirements and exports;
4. type/category/schema/unit/capability mismatches reject before lowering;
5. private declarations cannot be referenced outside their fragment;
6. plans reference exported operations and normalize to one ordered plan;
7. fragment packaging versus explicit leaf construction has canonical fingerprint identity;
8. fragment substitution changes only the dependent canonical declarations and capabilities;
9. backend preflight is the transitive union of the fully lowered fragment graph;
10. Wang, CNV, and the required Morpheus fixtures each have a generic fragment-based lowering
    fixture;
11. every such stable execution fixture passes sequential CPU, Metal, and ROCm gates under
    Decision 0032; and
12. documentation presents paper-specific builders only after the equivalent generic construction
    and labels them as example-layer conveniences.

These gates measure abstraction quality through reuse, substitution, lowering identity, and
backend honesty rather than an arbitrary maximum argument count.
