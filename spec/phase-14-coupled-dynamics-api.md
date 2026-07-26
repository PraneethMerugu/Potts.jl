# Phase 14 Coupled Dynamics and ModelingToolkit API

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: This document does not define an independent Phase 14 contract. Its applicable
requirements are consolidated in the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md) and
[Contract Registry v2](phase-14-contract-registry-v2.toml).

## Scope

This document proposes the public API and observable coupling semantics for the dynamic biological
state required by the Phase 14 published-model corpus. It covers:

- independent scientific spatial roles;
- source-specific copy-attempt budgets without changing `SequentialCPM`;
- accepted-copy site state;
- per-MCS cell histories and ordinary differential equations;
- evolving fields, secretion, uptake, and operator splitting;
- dynamic relationship graphs;
- degradable lattice structures;
- composition with existing lifecycle events and observations; and
- optional ModelingToolkit and MethodOfLines authoring.

Focused normative candidates currently extracted from this umbrella are:

- [Coupled Execution and MCS Plan Semantics](phase-14-coupled-execution-semantics.md);
- [Dynamic State Ownership Semantics](phase-14-dynamic-state-semantics.md);
- [Spatial Roles and Source Attempt Semantics](phase-14-spatial-and-attempt-semantics.md);
- [Cell and Field Dynamics Semantics](phase-14-cell-and-field-dynamics-semantics.md);
- [Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md);
- [Relationship and Coupled Lifecycle Semantics](phase-14-relationship-and-lifecycle-semantics.md);
- [Coupled Persistence and Paper Observation Semantics](phase-14-coupled-persistence-and-observation-semantics.md); and
- the machine-readable [Phase 14 Contract Registry](phase-14-contract-registry-v1.toml).

The focused documents own normative detail. This umbrella remains the integrated API map and source
examples.

It extends the accepted
[PottsToolkit authoring](pottstoolkit-authoring-composition-and-api-semantics.md),
[SciML interface](sciml-interface-semantics.md), [lifecycle](lifecycle.md), and
[persistence](persistence.md) contracts. It does not reopen their frozen Phase 13 meanings.

The API in this document is a candidate final surface. Normative acceptance occurs capability by
capability after the corresponding source record supplies its exact update order, numerical law,
and comparison fixture.

## Design Decision

Coupled models continue to use:

```julia
PottsToolkit.PottsModel
CorePotts.PottsProblem
CorePotts.PottsIntegrator
CorePotts.PottsSolution
```

There is no `CoupledProblem`, `HybridPottsProblem`, parallel simulation engine, or
ModelingToolkit-owned runtime.

A coupled `PottsModel` contains immutable state declarations, process declarations, scientific
components, and one explicit `MCSPlan`. `PottsProblem` binds initial values, field arrays,
discretizations that depend on realized geometry, time span, capacity, and seed. The integrator
owns all mutable Potts, site, cell, field, relationship, process, and plan-position state.

ModelingToolkit MAY define continuous equations. Potts.jl always owns:

- the MCS boundary;
- attempt and accepted-copy semantics;
- snapshots visible to continuous systems;
- field/cell source and sink accumulation;
- process ordering and operator splitting;
- lifecycle transaction ordering;
- observation timing;
- persistence and restart;
- semantic randomness; and
- backend preflight and synchronization.

## Public API Layers

### Existing declarations retained

The following existing concepts remain the preferred declarations:

- `CellProperty` for scalar, static-vector, and other isbits per-cell state;
- `CellParameter` and `ModelParameter` for immutable parameters;
- `Field` for reusable field identity, placement, boundary, and interpolation;
- ordinary energy, drive, constraint, mechanical, and lifecycle components;
- `EveryMCS`, `AtMCS`, and the other accepted integer-MCS schedules; and
- `PottsProblem` for a realized experiment.

A vector cell state does not need a second property hierarchy. For example:

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

### New state declarations

The candidate new public state declarations are:

```julia
SiteProperty
CellHistory
RelationshipSet
GlobalProperty
MembraneProperty
DelayState
```

`SiteProperty` declares typed state associated with lattice sites rather than their current owner:

```julia
activity = SiteProperty(
    :activity;
    initial = 0.0f0,
    invariant = ClosedPropertyInterval(0.0f0, 1.0f0),
    persistence = CheckpointedProperty,
)
```

It MUST declare behavior for initialization, ownership change where applicable, clearing, and
checkpointing. Site state is never implicitly copied because ownership changes.

`CellHistory` declares a bounded, typed, checkpointed ring buffer derived from a named observable or
property:

```julia
centroid_history = CellHistory(
    :centroid_history,
    Tumor;
    source = Centroid(),
    length = 5,
    initial = RepeatInitialSample(),
)
```

Its declaration order does not determine when sampling happens. The `MCSPlan` names the sampling
phase.

`RelationshipSet` declares graph state whose edges carry a typed payload:

```julia
junctions = RelationshipSet(
    :junctions,
    Tumor => Tumor;
    edge = FocalPointEdge{Float32},
    maximum_degree = 4,
    persistence = CheckpointedProperty,
)
```

Endpoints use cell identity plus generation. Relationship storage MUST reject stale endpoints,
duplicate edges, and capacity overflow according to declared policies.

Degradable structures use `SiteProperty` when the state is a material label or concentration on
the lattice. A distinct structure type is introduced only if the CNV audit proves that site state
cannot express the required occupancy and mutation laws.

`GlobalProperty`, `MembraneProperty`, and `DelayState` provide typed model-global, per-cell
material-membrane, and clocked delay state for the general continuous-system contract. Their
remapping, lifecycle, scheduling, and persistence semantics are defined in
[Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md).

### New process declarations

The candidate process families are:

```julia
AcceptedCopyUpdate
HistorySample
CellDynamics
FieldDynamics
FieldExchange
RelationshipDynamics
SiteDynamics
ContinuousSystem
ContinuousEvent
SymbolMap
```

Each process is an immutable model declaration with a stable semantic identity. It declares:

- state and observables read;
- state written;
- required snapshot;
- legal plan phases;
- semantic RNG streams;
- synchronization and workspace requirements;
- persistence state;
- supported dimensions, algorithms, numerical modes, and backends; and
- component and process versions.

Processes do not receive an unrestricted mutable integrator.

### Multi-MCS staged protocols

Within-MCS order and across-MCS experimental stages are distinct. `MCSPlan` defines the former.
`StagedProtocol` defines named, non-overlapping ranges of target MCS values:

```julia
migration_protocol = StagedProtocol(
    ProtocolStage(:relax; mcs = MCSRange(1, 120)),
    ProtocolStage(:initial_adhesion; mcs = MCSRange(121, 210)),
    ProtocolStage(:switch_calibration; mcs = MCSRange(211, 211)),
    ProtocolStage(:stimulated; mcs = MCSRange(212, 500)),
)
```

These are normalized target-MCS ranges. The Wang source label is derived as
`source_mcs = target_mcs - 1`; it is not another scheduler clock. CompuCell3D source MCS `0:499`
therefore maps to target MCS `1:500`.

The stage for target MCS `m` is selected before the first phase that advances MCS `m`. Stage ranges
MUST be explicit, positive, ordered by their numerical boundaries, and non-overlapping. Gaps require
an explicit idle or default stage; tuple position cannot repair ambiguous ranges.

Piecewise model data uses `ScheduledParameter` rather than mutating `ModelParameter`:

```julia
focal_strength = ScheduledParameter(
    :focal_strength,
    migration_protocol;
    relax = 0.0f0,
    initial_adhesion = 20.0f0,
    switch_calibration = lambda_fpp,
    stimulated = lambda_fpp,
)
```

A process invocation MAY restrict itself to stages:

```julia
Advance(rac_dynamics; interval = OneMCS(), active = During(:stimulated))
```

Stage selection, scheduled values, and process enablement are immutable model semantics. The current
stage and local stage clock are checkpointed. Parameter changes inside an MCS require a separately
named process phase; they cannot be hidden in a stage transition.

Source protocols that run extra Potts sweeps only on a copied observation state—such as a possible
interpretation of the Graner--Glazier T=0 annealing—belong to a typed observation transform rather
than the main `MCSPlan`. If source review shows that those sweeps mutate the continuing trajectory,
they require an explicitly versioned algorithm/protocol contract; an ordinary plan cannot contain
an uncounted second `PottsAttempts` stage.

### Continuous clocks

An MCS is discrete algorithmic time and is not inherently a physical ODE/PDE interval. A continuous
process therefore references an explicit model declaration:

```julia
physical_time = ContinuousClock(
    :physical_time;
    per_mcs = 30.0f0,
    unit = :second,
)
```

`per_mcs` is the continuous interval corresponding to one completed MCS for this coupling. `unit`
is semantic metadata and is materialized in the manifest. The base API stores normalized numerical
values and does not require Unitful; an optional Unitful constructor MAY convert to the same
declaration.

`OneMCS()` and `HalfMCS()` in an `Advance` invocation mean one or one-half of the referenced
continuous clock's `per_mcs`, not an additional Potts MCS. A process MAY instead use an explicit
continuous interval:

```julia
Advance(rac_dynamics; interval = ContinuousInterval(15.0f0, :second))
```

Problem construction rejects an interval whose unit or clock is incompatible with the continuous
law. Continuous time does not alter public integer `integrator.t`, event schedules, or `saveat`.

## Explicit MCS Coupling

### MCSPlan

Every model with a dynamic process MUST declare exactly one `MCSPlan`. The candidate spelling is:

```julia
MCSPlan(
    Phase(:field_pre, ...),
    PottsAttempts(...),
    Phase(:cell_updates, ...),
    LifecyclePhase(),
    ObservationPhase(),
)
```

An uncoupled model does not need to declare a plan. Its current Phase 13 MCS behavior, fingerprint,
checkpoint, and result identity remain unchanged. Internally treating it as a legacy default plan
MUST NOT change any frozen artifact.

An `MCSPlan` is intentionally ordered. Dependencies validate the declared order but never infer,
topologically sort, or silently repair scientific execution order.

A model MAY additionally declare one `StagedProtocol`. `MCSPlan` remains the within-MCS schedule
used in every stage; stage restrictions and scheduled parameters determine which invocations and
values are active.

### Phase

A `Phase` contains one or more process invocations that:

1. read one common immutable phase snapshot;
2. plan or compute all writes;
3. validate conflicts and failure conditions; and
4. publish their writes atomically.

Processes in one phase do not see each other's writes. Sequential dependence requires two
separately named phases:

```julia
Phase(:field_exchange, Exchange(secretome_uptake)),
Phase(:cell_signaling, Advance(rac_dynamics; interval = 1.0f0)),
```

Tuple order within one `Phase` is representational and cannot resolve write conflicts. Phase names
are semantic identities and appear in inspection, fingerprints, checkpoints, and evidence.

A phase MAY declare an integer-MCS schedule. An omitted schedule means every MCS. The schedule is
evaluated before the phase snapshot is captured, and a phase that is not due performs no reads,
writes, clock advance, or publication. The normalized schedule is part of the plan fingerprint;
process-local frequency counters are not a second scheduling authority.

### PottsAttempts

`PottsAttempts()` is the one required plan stage that invokes the solve-selected CPM algorithm for
one normalized MCS. It MAY name typed accepted-copy effects:

```julia
PottsAttempts(on_accept = (activate_protrusion,))
```

Accepted-copy effects stage and commit atomically with the accepted ownership transaction. They:

- run only for an accepted actionable copy;
- do not run for boundary-null, same-owner, immutable-recipient, constraint-rejected, or
  Metropolis-rejected attempts;
- read the same pre-commit state and staged transaction data used by the owning attempt;
- publish only declared state writes; and
- cannot change the already completed acceptance decision.

An effect that influences acceptance is an energy, drive, modifier, constraint, or mechanical
component. It is not an accepted-copy update.

### LifecyclePhase

`LifecyclePhase()` invokes the existing accepted lifecycle transaction after all preceding
post-attempt auxiliary phases. It retains the existing `PreLifecycleSnapshot`, conflict, capacity,
planning, validation, and atomic commit laws.

An ordinary positional `MCSPlan` MUST contain exactly one lifecycle phase after `PottsAttempts`. A
model with no lifecycle declarations still retains the phase boundary as a no-op so observation and
restart timing remain unambiguous. The opt-in `MultirateSchedule` may add timed lifecycle
transactions while retaining one final completed-MCS lifecycle/observation boundary, as specified
by the continuous-system contract.

### ObservationPhase

`ObservationPhase()` is the completed-MCS observation and saving boundary. It occurs after
lifecycle commit. Ordinary SciML scheduled saving and callbacks retain their accepted relative
order.

Intermediate diagnostic observations MAY be declared through explicitly named process outputs, but
they are not ordinary completed-MCS `saveat` values.

### Plan validation

Normalization MUST reject:

- a dynamic process not referenced by the plan;
- a process invoked more than its declared multiplicity;
- two writes to the same state in one phase without an explicit conflict law;
- a read that precedes initialization or required production;
- instantaneous dependency cycles;
- a lifecycle or observation phase in an illegal position;
- an accepted-copy effect outside `PottsAttempts`;
- a field or continuous advance with an unmaterialized interval;
- a process whose required algorithm or backend is unsupported; and
- any plan whose restart position cannot be represented.

## Continuous Cell Dynamics

### CellDynamics

`CellDynamics` advances one continuous system independently for each eligible active cell:

```julia
rac_dynamics = CellDynamics(
    :rac_dynamics,
    Tumor,
    rac_system;
    state = (rac = rac,),
    inputs = (signal = sensed_secretome,),
    parameters = (activation = activation, decay = decay),
    clock = physical_time,
    stepping = FixedStep(RK4(); dt = 0.25f0, substeps = 4),
)
```

The `state`, `inputs`, and `parameters` mappings use semantic declarations, not positional columns
or mutable dictionaries.

The same system applies to every eligible cell unless the model explicitly declares a heterogeneous
law. Active-cell identity and generation determine state ownership. Division, transition, and
retirement behavior comes from the mapped `CellProperty` declarations.

Continuous dynamics cannot query live lattice storage while a numerical solver is taking internal
steps. All Potts-derived inputs are materialized from the declared phase snapshot. Feedback becomes
visible only after the phase publishes its result.

### Stepping policies

The initial stable stepping policy is:

```julia
FixedStep(algorithm; substeps)
```

It uses the process interval divided by the positive integer `substeps`, advances exactly the
declared endpoint, has bounded work, and supports an exact continuation contract when the numerical
algorithm does.

The candidate host-only policy is:

```julia
AdaptiveStep(algorithm; abstol, reltol, dtmin, dtmax, maxiters)
```

Adaptive stepping remains experimental. An exact-continuation profile must semantically serialize
every solver-controller, Jacobian, interpolation, event, and cache value that can change the future
trajectory, or prove deterministic reconstruction under its pinned execution identity. A state-only
restart MUST NOT be called exact continuation when hidden stepping state can change the trajectory.

General global/per-cell systems, synchronous rules, delays, multirate scheduling, sampled events,
root events, and lifecycle requests are defined in
[Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md).
`CellDynamics` remains the concise fixed-step per-cell spelling.

## Evolving Fields

### FieldDynamics

An existing `Field` declares field identity, placement, boundaries, and interpolation.
`FieldDynamics` adds evolution:

```julia
vegf_dynamics = FieldDynamics(
    :vegf_dynamics,
    vegf,
    vegf_system;
    clock = physical_time,
    discretization = MOLFiniteDifference(
        [x => field_spacing, y => field_spacing],
        t;
        approx_order = 2,
    ),
    stepping = FixedStep(TRBDF2(); dt = 0.5f0, substeps = 2),
)
```

Problem construction realizes geometry-dependent discretization and initial field values. The
model retains the reusable mathematical and numerical intent.

The `Field` boundary declaration remains authoritative Potts model semantics. A supplied
`PDESystem` boundary condition MUST be equivalent after normalization or problem construction
fails with a structured conflict. The adapter cannot silently prefer the symbolic system or the
Potts declaration.

The discretization identity, stencil/order, field layout, solver, interval, tolerances, precision,
continuous clock, and split placement appear in the manifest and model fingerprint.

Substep constraints are distinct from PDE forcing:

```julia
secretome_dynamics = FieldDynamics(
    :secretome_dynamics,
    secretome,
    ReactionDiffusion(diffusion = 1.0f0);
    stepping = FixedStep(ExplicitEuler(); substeps = 5),
    post_substep = (
        ConstantConcentration(Medium, 1.0f0),
    ),
)
```

Every internal substep reads the preceding staged field, applies its numerical law, applies the
ordered post-substep constraints, and feeds that constrained result to the next substep. All
internal substeps share the process-entry Potts snapshot and publish one field result at the
process boundary. The exact `post_substep` constructor spelling remains Provisional; its position,
order, reservoir accounting, and fingerprint meaning do not.

Strict process failure atomicity requires an authoritative grid plus enough staging grids to avoid
overwriting the authoritative input before every internal step validates. The Wang five-substep
profile uses two staging grids. Internal buffers, buffer roles, and substep counters are execution
workspace and are not stable checkpoint state.

### FieldExchange

Cell-dependent secretion, uptake, and source/sink behavior are declared independently of the PDE:

```julia
sensed_secretome = CellProperty(
    :sensed_secretome,
    Tumor;
    initial = 0.0f0,
    division = CopyToBoth(),
    transition = Preserve(),
    retirement = Reset(),
)

secretome_uptake = FieldExchange(
    :secretome_uptake,
    secretome;
    sinks = (
        Uptake(
            Tumor;
            maximum = 1.0f0,
            relative_rate = 0.0025f0,
            output = sensed_secretome,
            normalize = ByCellVolume(),
        ),
    ),
)
```

For Wang, `ConstantConcentration(Medium, 1.0f0)` belongs to the numerical profile of
`secretome_dynamics` as a post-substep reservoir constraint, where it is enforced after diffusion
in every scaled field substep. It is not an additive forcing array.
`secretome_uptake` therefore contains only the later Python-equivalent cell uptake. A model whose
source applies a concentration reservoir at a distinct exchange boundary may instead place that
constraint in its named exchange process; the two plan identities are not interchangeable.

An exchange phase reads one ownership, geometry, cell-property, and field snapshot. It constructs
source/sink contributions and cell outputs with an explicit reduction law. It then publishes all
declared outputs atomically.

An exchange that immediately removes field mass declares the field itself as a write, not a future
forcing array. If it also writes cell or global state, lowering constructs one typed cross-domain
write set. Candidate field values, per-cell outputs, global outputs, and status validate before
one logical publication epoch; later phases cannot observe a partially published exchange.

Time-dependent exchange behavior is supplied by the root plan. For Wang the same generic exchange
law admits four plan-resolved modes:

```julia
secretome_mode = PlanModeSchedule(
    MCSRange(1, 121) => InactiveExchange(),
    MCSRange(122, 210) => ResetOutput(0.0f0),
    MCSRange(211, 211) => CalibrateMaximum(target = 4.0f0),
    MCSRange(212, 500) => ApplyCalibration(),
)

Exchange(secretome_uptake; mode = secretome_mode)
```

This spelling is illustrative and Provisional. Canonical lowering MUST expose the exact mode table:
inactive on targets 1–121, reset-only on 122–210, calibrate on 211, and uptake/publish on
212–500. A process-local `if target_mcs ...` scheduler is rejected.

The calibration multiplier is normalized as one global property because the source writes the
same value to every cell. A zero or nonfinite maximum raw uptake causes structured failure before
the candidate field, multiplier, or signal publishes.

Source/sink accumulation MUST specify:

- site versus cell normalization;
- units or scale transformation;
- occupancy sampling;
- overlap and medium behavior;
- reduction order or reproducibility class;
- clipping and negativity behavior;
- whether concentration changes immediately or is an input to the next field advance; and
- behavior for inactive, dividing, newly created, and retired cells.

### Operator splitting

Splitting is expressed by the actual `MCSPlan`, not an opaque `coupling = :strang` symbol:

```julia
MCSPlan(
    Phase(:field_pre,
        Advance(vegf_dynamics; interval = HalfMCS())),
    PottsAttempts(),
    Phase(:exchange,
        Exchange(vegf_exchange)),
    Phase(:field_post,
        Advance(vegf_dynamics; interval = HalfMCS())),
    LifecyclePhase(),
    ObservationPhase(),
)
```

Named convenience constructors MAY expand to this representation:

```julia
StrangFieldSplit(vegf_dynamics; exchange = vegf_exchange)
LieFieldSplit(vegf_dynamics; exchange = vegf_exchange)
```

Inspection and normalization always show the expanded plan. Convenience names do not create a
second execution path.

Steady-state solves use an explicitly named `SteadyStateAdvance` process invocation with convergence
and failure criteria. It is not represented as an infinite transient step.

## Histories and Derived Cell State

Sampling a history is explicit:

```julia
centroid_sample = HistorySample(centroid_history)
```

A derived polarity update may then read the published history in a later phase:

```julia
polarity_update = PropertyUpdate(
    :polarity_from_history,
    polarity => NormalizedDisplacement(centroid_history; lag = 5),
    schedule = EveryMCS(),
)
```

The plan establishes whether the current post-attempt centroid is included:

```julia
Phase(:sample_centroids, centroid_sample),
Phase(:update_polarity, polarity_update),
```

Histories specify initial fill behavior, periodic unwrapping, missing/inactive samples, lifecycle
inheritance, observation timing, and ring-buffer checkpoint order.

## Dynamic Relationships

`RelationshipDynamics` mutates one `RelationshipSet` from a phase snapshot:

```julia
junction_update = RelationshipDynamics(
    :junction_update,
    junctions;
    create = ContactEligible(
        relation = polarity_neighbors,
        activation = -50.0f0,
    ),
    remove = BeyondMaximumLength(12.0f0),
    update = FocalParameters(
        strength = focal_strength,
        target_length = 8.0f0,
        maximum_length = 12.0f0,
    ),
    conflicts = StableRelationshipPriority(),
)
```

Relationship energy during Potts attempts reads the graph snapshot published by the preceding
relationship phase. Relationship mutation does not occur inside energy evaluation.

Creation, removal, and parameter updates plan against one graph and cell snapshot and commit
atomically. Endpoint death, division, retirement, and slot reuse are resolved through typed
lifecycle interaction policies. Tuple iteration, dictionary order, atomic arrival, and kernel
launch geometry are not graph semantics.

## Site Dynamics and Accepted-Copy State

The Act-CPM slice uses one site property, one accepted-copy update, and one decay process:

```julia
activate_protrusion = AcceptedCopyUpdate(
    :activate_protrusion,
    activity;
    when = ProtrusionInto(ActCell),
    gained = SetTo(1.0f0),
    lost = SetTo(0.0f0),
)

decay_activity = SiteDynamics(
    :decay_activity,
    activity;
    update = SaturatingSubtract(inv(max_act)),
    schedule = EveryMCS(),
)

plan = MCSPlan(
    PottsAttempts(on_accept = (activate_protrusion,)),
    Phase(:activity_decay, decay_activity),
    LifecyclePhase(),
    ObservationPhase(),
)
```

The exact `gained`, `lost`, decay, and phase order remain provisional until the pinned Artistoo
source transcription closes the corresponding source-record ambiguity.

`SiteDynamics` also supplies the likely reusable substrate for CNV material degradation. A
degradation process reads a phase snapshot and commits site mutations atomically; it cannot perform
untracked writes from a model script.

## ModelingToolkit Integration

### Dependency boundary

`SciMLBase` remains the mandatory common interface. ModelingToolkit, MethodOfLines,
OrdinaryDiffEq, NonlinearSolve, and SteadyStateDiffEq remain optional dependencies selected by the
user or published-model environment.

The intended package boundary is:

```text
CorePotts
    generic process, state, execution, persistence, and backend protocols

PottsToolkit
    ContinuousSystem, CellDynamics, FieldDynamics, mappings, events, MCSPlan,
    and SciMLBase problem acceptance

PottsToolkitModelingToolkitExt
    ODE/DAE/discrete/event/PDESystem normalization, symbolic mapping,
    generated functions, compatibility reports, and fingerprints

published-model environment
    exact ModelingToolkit, MethodOfLines, solver, and analysis versions
```

CorePotts MUST NOT depend on ModelingToolkit or inspect symbolic expression internals.

### Accepted symbolic inputs

The optional extension supplies constructors or methods accepting supported ModelingToolkit systems
for `ContinuousSystem` and a `PDESystem` for `FieldDynamics`.

It MUST:

- bind symbolic variables by explicit semantic mapping;
- reject unmapped states, inputs, parameters, defaults, and events;
- run the selected symbolic compilation explicitly;
- record the original and compiled system fingerprints;
- expose generated numerical function identity and initialization equations;
- validate units when the symbolic system provides them;
- lower supported assignments, callbacks/events, delays, stochastic equations, and DAEs through
  their separately versioned contracts, and reject every unsupported construct rather than silently
  dropping it; and
- report compilation and specialization in `explain(model)`.

The optional extension MAY use ModelingToolkit-generated `ODEFunction` values or runtime-generated
functions. It MUST NOT treat Julia object serialization or process-local generated-function
addresses as a scientific fingerprint.

### Direct SciML and ordinary Julia laws

ModelingToolkit is a convenience, not the only route. `CellDynamics` and `FieldDynamics` also accept:

- a qualified `SciMLBase.ODEFunction` or numerical problem template;
- a CorePotts continuous-law extension satisfying the public protocol; or
- a PottsToolkit built-in reaction, diffusion, or steady-state law.

Equivalent symbolic and direct numerical laws are judged by conformance fixtures and declared
metadata, not by requiring identical Julia types.

### GPU scope

A ModelingToolkit-authored law does not imply GPU support.

Every stable Phase 14 execution capability, and every capability used by a release published
model, requires all three of:

1. an ordinary sequential CPU reference implementation;
2. backend-resident production execution on Metal; and
3. backend-resident production execution on ROCm.

Implementation proceeds CPU first so the reference fixes semantics, but CPU-first does not permit
a CPU-only stable or release claim. Metal and ROCm are mandatory qualification targets for the
same canonical model. Qualification requires proof that:

- the compiled numerical function is device compatible;
- state and input arrays remain backend-resident;
- the selected stepping policy is qualified on that backend;
- source/sink reductions meet the declared reproducibility class;
- dynamic cell eligibility and relationship storage remain valid;
- no hidden host callback or scalar indexing occurs; and
- synchronization appears only at declared plan boundaries.

DiffEqGPU MAY implement a qualified cell-ensemble stepping backend. It does not define Potts
coupling semantics, and its supported solver set does not automatically become Potts.jl's supported
set.

## Spatial Roles and Attempt Budgets

### SpatialRoles

The Level 2 model receives an additive declaration:

```julia
roles = SpatialRoles(
    proposal = MooreRelation(order = 2),
    contact = MooreRelation(order = 4),
    surface = MooreRelation(order = 1),
    connectivity = VonNeumannRelation(),
    queries = (
        polarity_neighbors = VonNeumannRelation(),
        activity_neighbors = MooreRelation(order = 1),
    ),
)
```

The precise built-in relation constructors are resolved against the existing CorePotts role-typed
relation protocol. Omitting `SpatialRoles` retains current first-shell lowering and its current
fingerprint. Explicit roles materialize every offset set and boundary rule in inspection and
manifests.

Fields retain their independent discretization relation; a PDE stencil is not inferred from the
proposal or contact relation.

### BudgetedSequentialCPM

`SequentialCPM` retains exactly `N` attempts per normalized MCS.

Source-specific sequential budgets use a new algorithm identity:

```julia
solve(
    prob,
    BudgetedSequentialCPM(
        AttemptsPerSite(16);
        temperature = 10.0f0,
    ),
)
```

`BudgetedSequentialCPM` shares the conventional ordered current-state proposal and immediate-commit
law only where its own accepted contract says so. Its guarantee profile, RNG address, attempt
counter, terminal incomplete-MCS behavior, reports, fingerprints, and evidence are separately
versioned. Stable continuation begins only from a completed-MCS checkpoint.

Changing `SequentialCPM` v1 or describing 16N execution as ordinary normalized `SequentialCPM` is
prohibited.

## Representative Model Spellings

These examples show composition shape, not final paper parameters.

### Wortel Act-CPM

```julia
model = PottsModel(
    ActCell,
    Medium,
    activity,
    area,
    perimeter,
    ActMotility(activity; strength = lambda_act, neighborhood = activity_neighbors),
    activate_protrusion,
    decay_activity,
    SpatialRoles(
        proposal = source_proposal,
        contact = source_contact,
        surface = source_surface,
        queries = (activity_neighbors = source_activity_query,),
    ),
    MCSPlan(
        PottsAttempts(on_accept = (activate_protrusion,)),
        Phase(:activity_decay, decay_activity),
        LifecyclePhase(),
        ObservationPhase(),
    ),
)
```

### Merks vasculogenesis

```julia
chemo_coupling = ModelFragment(
    :chemo_coupling,
    chemo,
    chemo_dynamics,
    chemo_exchange;
    exports = (
        advance = chemo_dynamics,
        exchange = chemo_exchange,
        field = chemo,
    ),
)

vascular_mechanics = ModelFragment(
    :vascular_mechanics,
    Adhesion(...),
    Volume(...),
    Elongation(...),
    Chemotaxis(chemo_coupling.field, ...);
    requires = (chemo = chemo_coupling.field,),
)

vascular_plan = MCSPlan(
    Phase(:field_pre,
        Advance(chemo_coupling.advance; interval = HalfMCS())),
    PottsAttempts(),
    Phase(:field_exchange,
        Exchange(chemo_coupling.exchange)),
    Phase(:field_post,
        Advance(chemo_coupling.advance; interval = HalfMCS())),
    LifecyclePhase(),
    ObservationPhase(),
)

model = compose(
    PottsModel(Endothelial, Medium),
    chemo_coupling,
    vascular_mechanics,
    vascular_plan,
)
```

The actual paper split may be Lie rather than Strang and remains a source-audit question.

### Wang collective migration

```julia
secretome_coupling = ModelFragment(
    :secretome_coupling,
    secretome,
    sensed_secretome,
    secretome_dynamics,
    secretome_uptake;
    requires = (
        cells = migrating_cells,
        medium = extracellular_medium,
    ),
    exports = (
        advance = secretome_dynamics,
        uptake = secretome_uptake,
        signal = sensed_secretome,
    ),
)

intracellular_signaling = ModelFragment(
    :intracellular_signaling,
    rac,
    rac_dynamics;
    requires = (
        cells = migrating_cells,
        signal = secretome_coupling.signal,
    ),
    exports = (
        advance = rac_dynamics,
        activity = rac,
    ),
)

focal_adhesions = ModelFragment(
    :focal_adhesions,
    junctions,
    focal_strength,
    focal_topology_on_accept,
    focal_parameter_update;
    requires = (cells = migrating_cells,),
    exports = (
        relationships = junctions,
        topology = focal_topology_on_accept,
        retune = focal_parameter_update,
    ),
)

directed_motility = ModelFragment(
    :directed_motility,
    polarity,
    centroid_history,
    centroid_sample,
    polarity_from_history,
    neighbor_alignment,
    protrusion_drive;
    requires = (
        cells = migrating_cells,
        activity = intracellular_signaling.activity,
        adhesions = focal_adhesions.relationships,
    ),
    exports = (
        sample = centroid_sample,
        derive = polarity_from_history,
        align = neighbor_alignment,
        force = protrusion_drive,
    ),
)

migration_plan = MCSPlan(
    PottsAttempts(on_accept = (focal_adhesions.topology,)),
    Phase(:secretome_field_solve,
        Advance(secretome_coupling.advance; interval = OneMCS())),
    Phase(:sample_centroids,
        Sample(directed_motility.sample)),
    Phase(:update_self_polarity,
        Update(directed_motility.derive;
            active = PeriodicMCS(122, 1; stop = 500))),
    Phase(:secretome_uptake,
        Exchange(secretome_coupling.uptake;
            mode = secretome_mode)),
    Phase(:intracellular_dynamics,
        Advance(intracellular_signaling.advance;
            interval = OneMCS(),
            active = PeriodicMCS(122, 1; stop = 500))),
    Phase(:retune_focal_relationships,
        Update(focal_adhesions.retune);
        schedule = PeriodicMCS(1, 10; stop = 491)),
    Phase(:align_neighbor_polarity,
        Update(directed_motility.align;
            active = PeriodicMCS(122, 1; stop = 500))),
    Phase(:update_protrusion,
        Update(directed_motility.force;
            active = PeriodicMCS(122, 1; stop = 500))),
    LifecyclePhase(),
    ObservationPhase(migration_observations...),
)

model = compose(
    PottsModel(Tumor, Medium),
    secretome_coupling,
    intracellular_signaling,
    focal_adhesions,
    directed_motility,
    migration_protocol,
    migration_observations,
    migration_plan,
)
```

These are generic fragments and named typed exports, not Wang-specific library types. The same
field-coupling, fixed-step signaling, dynamic-relationship, history/motility, observation, and plan
composition mechanisms must serve unrelated models and Morpheus compatibility fixtures. A
paper-example module may package the complete assembly later, but that wrapper is not core API
evidence.

This is the accepted source-order lowering shape. The field solve follows Potts and precedes every
Wang cell process. Its CompuCell3D-compatible numerical profile performs diffusion and then the
medium `ConstantConcentration` operation inside every scaled field substep. The separately named
uptake phase runs only after the completed field solve and publishes calibration or signal state
before the same-MCS ODE advance.

The source's migration steppable is decomposed into separately named phases because current
centroids are appended before polarity is derived and uptake publishes before the ODE. This
decomposition preserves source visibility; combining these invocations into one immutable-snapshot
phase would not. Neighbor means and aligned-polarity writes remain one synchronous process so no
cell observes another cell's newly aligned polarity.

Focal-link creation and removal are accepted-copy relationship effects committed with Potts
ownership, not a post-Potts relationship phase. The ten-MCS focal phase only retunes the
relationships that already exist. Because source MCS `k` maps to target MCS `k+1`,
`PeriodicMCS(1, 10; stop = 491)` denotes source `mcs % 10 == 0` over source `0:499`. No source
`step()` retune is hidden in initialization.

The staged protocol uses `:initial_adhesion` from target MCS 121/source MCS 120,
`:switch_calibration` at target 211/source 210, and `:stimulated` from target 212/source 211.
Consequently, Potts at source MCS 120 still reads focal strength 0, Potts at source MCS 210 still
reads 20, and source MCS 211 is the first Potts step to read the scanned strength and force
published at source MCS 210. Direct fixtures at source 120/210/211 and target 121/211/212 are
mandatory.

`focal_strength` is the scheduled target read only by `focal_parameter_update`. Potts energy reads
the last published focal payload on each relationship, never the upcoming scheduled target.
Reading `focal_strength` directly from Potts would violate both the source MCS 120 and source MCS
210 boundaries.

This sketch is not a CPU-only reference target. Before the Wang vertical slice passes, every state,
law, process, plan entry, accepted-copy effect, observation reducer, and persistence block used
above MUST execute through the same canonical model on sequential CPU, Metal, and ROCm. GPU state
MUST remain backend resident during unobserved stepping; host field solves, host ODE loops,
host-managed relationship graphs, per-MCS transfers, and silent fallback are disqualifying.

### CNV

CNV composes the same generic fragment and named-port boundary at greater scale:

```julia
model = compose(
    PottsModel(retinal_cell_types...),
    oxygen_coupling,
    vegf_coupling,
    degradable_membrane,
    vascular_relationships,
    phenotype_and_lifecycle,
    cnv_observations,
    cnv_plan,
)
```

The paper model source MAY assemble many declarations and parameters, but it cannot implement a
private solver, hidden mutation callback, or uncheckpointed process state. Each fragment must expose
named typed operations used by `cnv_plan`, lower completely to the canonical kernel, and propagate
its CPU/Metal/ROCm requirements.

## Problem Construction and Solving

The existing problem form remains:

```julia
prob = PottsProblem(
    model,
    domain,
    layout;
    fields = (
        chemo => chemo_initial,
        oxygen => oxygen_initial,
    ),
    tspan = (0, 4_000),
    capacity = 4_096,
    seed = 42,
)

sol = solve(prob, SequentialCPM(temperature = 20.0f0))
```

Problem construction additionally realizes:

- site-property arrays;
- cell-history buffers;
- relationship storage and capacities;
- staged-protocol ranges and scheduled-parameter bindings;
- continuous-system state mappings;
- geometry-dependent PDE discretizations;
- source/sink workspaces;
- compiled plan phases; and
- capability/backend preflight requirements.

There is no solve-time callback that constructs or mutates scientific coupling.

## Inspection and Provenance

The existing inspection surface expands rather than forks:

```julia
validate(model)
normalize(model)
explain(model)
explain(prob)
capabilities(model)
```

Reports show:

- state ownership and schemas;
- process read/write sets;
- expanded MCS plan;
- staged protocol, current-stage rules, and scheduled parameters;
- accepted-copy effects;
- continuous laws and symbolic-system fingerprints;
- continuous clocks, discretizers, solvers, intervals, and tolerances;
- source/sink normalization and reduction;
- phase synchronization points;
- persistence blocks;
- backend support and rejection reasons; and
- changes relative to the uncoupled Phase 13 path.

Published-model manifests materialize every scientifically consequential default.

## Persistence and Continuation

Coupled execution uses the separately versioned `CoupledCheckpoint` envelope defined in
[Coupled Persistence and Paper Observation Semantics](phase-14-coupled-persistence-and-observation-semantics.md).
It contains an unchanged `CanonicalCheckpoint` v1 plus a typed `CoupledCheckpointExtension`. The
existing uncoupled checkpoint type, schema, checksum, storage payload, and byte identity remain
unchanged.

The coupled checkpoint contains, as applicable:

- ordinary logical Potts state and trackers;
- current completed MCS and completed plan identity;
- site-property arrays;
- cell properties and history ring-buffer heads;
- field values, semantic time, discretization identity, and solver state required by the
  continuation claim;
- relationship edges, payloads, and endpoint generations;
- continuous cell state and stepping state;
- lifecycle and process semantic RNG identities;
- staged-protocol position; and
- observation state needed to avoid duplicate or skipped output.

Stable public checkpoints occur only after `ObservationPhase` at a fully completed MCS. Mid-MCS and
mid-phase capture remain outside the stable paper contract.

## Failure and Synchronization

A process failure aborts the current phase before any of that phase's writes publish. The target MCS
does not complete, public time does not advance, and the integrator becomes terminal. Previously
completed phases in that failed MCS are not a stable checkpoint state; recovery uses the preceding
completed-MCS checkpoint or a new problem.

Structured failures include:

- continuous solver failure or maximum iterations;
- field convergence failure;
- invalid source/sink result;
- negative concentration under a rejecting policy;
- relationship capacity or conflict failure;
- stale cell generation;
- site-state invariant failure;
- unsupported backend/capability combination; and
- host synchronization required by a device-resident plan.

Host ModelingToolkit/SciML integration is an explicitly synchronized execution mode. It MUST report
the transfers and synchronization boundaries it introduces. A GPU-qualified mode keeps applicable
state and stepping backend-resident.

## Compatibility and Rejected Designs

The following designs are rejected:

- one mutable `model.dict` or cell dictionary for arbitrary biological state;
- unrestricted `before_mcs!`, `after_mcs!`, or accepted-copy callbacks as stable scientific APIs;
- a generic callback receiving the mutable integrator during an ODE or PDE step;
- inferring scientific order from declaration order, dependency sorting, or Julia dispatch;
- using SciML callbacks to implement lifecycle or hidden field coupling;
- letting a PDE solver read changing Potts occupancy during internal substeps without a declared
  coupling snapshot;
- a second coupled-problem or solution type;
- making ModelingToolkit a CorePotts dependency;
- changing `SequentialCPM`'s normalized-MCS contract;
- mutating fixed focal-point component semantics to obtain dynamic links; and
- automatically claiming GPU support because ModelingToolkit, MethodOfLines, or DiffEqGPU can
  compile a related standalone problem.

## Phase 13 Freeze Impact

This proposal is additive if implemented as written:

- existing uncoupled model normalization and fingerprints remain byte-identical;
- existing `SequentialCPM`, fixed focal points, immutable field snapshots, lifecycle phases, SciML
  time, callbacks, saving, checkpoints, and results keep their frozen meanings;
- coupled models use new process identities, an explicit plan, and a new coupled persistence block;
- ModelingToolkit support is an optional PottsToolkit extension; and
- every new capability starts with a sequential CPU reference and advertises only qualified
  backend combinations.

Any implementation discovery that contradicts these conditions triggers a D10 compatibility
decision before the affected code is merged.

## Acceptance Blockers

This candidate cannot become Accepted until:

1. the Wortel source fixes accepted protrusion, retraction, decay, and observation ordering;
2. the Merks source or an explicit ambiguity plan fixes its PDE stencil and split order;
3. the accepted Wang CompuCell3D order is encoded in one inspectable plan, source MCS `k` maps
   exactly to normalized target MCS `k+1`, and source 120/210/211 (target 121/211/212) visibility
   boundaries pass directly;
4. the CNV scenario audit identifies the minimum field, relationship, degradation, and lifecycle
   process set;
5. direct SciML and ModelingToolkit prototypes demonstrate stable mappings without symbolic object
   identity entering scientific fingerprints;
6. fixed-step cell ODE and field reference fixtures prove checkpoint continuation;
7. coupled-checkpoint prototypes validate the specified envelope against Memory, HDF5, and Zarr;
8. the stable continuous-system subset passes the pinned Morpheus time-scale, global/per-cell ODE,
   synchronous-rule, delay, sampled-event, mapper, field-coupling, and lifecycle microfixtures with
   complete compatibility reports;
9. multirate and timed-lifecycle prototypes preserve the ordinary positional-plan and Phase 13
   regression fixtures; and
10. the owner accepts the public names and proposed
   [D10 additive assessment](decisions/0030-phase-14-coupled-dynamics-and-freeze-impact.md).
