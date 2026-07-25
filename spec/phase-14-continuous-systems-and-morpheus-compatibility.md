# Phase 14 Continuous Systems and Morpheus Semantic Compatibility

Status: Superseded by Decision 0031; retained as historical design and compatibility evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: Equation-style continuous systems are authoring façades over the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md), never a separate runtime.
Advanced adaptive, root, DAE, SDE, reaction, and jump families remain Experimental.

## Purpose

This document expands Phase 14 from small per-cell ODE coupling to a general continuous and
rule-based system contract capable of expressing the ordinary model semantics of Morpheus without
copying its XML language, GUI, scheduler implementation, or plugin internals.

It governs:

- global, per-cell, field, and membrane state domains;
- coupled differential equations, synchronous recurrence rules, reactive assignments, functions,
  deterministic/stochastic reactions, jump processes, stochastic systems, fixed delays, and DAEs;
- global, MCS, and system-local time;
- sampled and root-located events;
- typed mappings and reductions across state domains;
- continuous-system requests for lifecycle transactions;
- ModelingToolkit, SBML, and future MorpheusML adapters; and
- semantic compatibility reports and fixtures.

The machine-readable
[Morpheus continuous-semantics matrix](../design/audits/phase-14-morpheus-continuous-semantics-v1.toml)
defines the parity target.

This document specializes
[Coupled Execution](phase-14-coupled-execution-semantics.md),
[Dynamic State](phase-14-dynamic-state-semantics.md),
[Cell and Field Dynamics](phase-14-cell-and-field-dynamics-semantics.md),
[Coupled Lifecycle](phase-14-relationship-and-lifecycle-semantics.md), and
[Coupled Persistence](phase-14-coupled-persistence-and-observation-semantics.md).
Where the earlier cell/field document describes only `CellDynamics` or `FieldDynamics`, this
document supplies the general contract to which those conveniences lower.

## Compatibility Claim

### Model-semantic compatibility

Potts.jl has Morpheus model-semantic compatibility for a feature only when it can express:

- the same authoritative state domains;
- the same mathematical update law;
- the same snapshots and synchronous/asynchronous visibility;
- the same time scales and evaluation schedule;
- the same trigger memory and event assignment timing;
- the same cross-domain aggregation;
- the same lifecycle coupling;
- the same stochastic law and operation identity;
- the same initialization and inheritance meaning; and
- the same observable outputs within declared numerical tolerances.

Names that resemble Morpheus elements are not evidence. Qualification requires a pinned Morpheus
model or microfixture and a versioned translation manifest.

Automatic MorpheusML import is useful but is not required for hand-authored model-semantic
compatibility. GUI behavior, XML editing, plotting, parameter-sweep UI, job queues, and remote
execution are product features outside this claim.

### Compatibility levels

Every translated model reports one of:

- `ExactSemanticMapping` — every source construct has the same declared observable semantics;
- `QualifiedNumericalMapping` — semantics agree but numerical solvers differ within registered
  tolerances;
- `ExplicitApproximation` — one or more constructs use named, user-approved approximations;
- `PartialMapping` — unsupported constructs are omitted and the result is not the source model; or
- `RejectedMapping` — execution is prohibited.

Only the first two qualify as semantic compatibility. A model-level claim is the minimum of all
construct mappings.

## One Runtime, One Continuous-System Abstraction

The reusable declaration is:

```julia
ContinuousSystem(
    :cell_cycle;
    domain = CellDomain(Proliferating),
    state = (
        StateVariable(:cdk1, property = :cdk1),
        StateVariable(:plk1, property = :plk1),
        StateVariable(:apc, property = :apc),
    ),
    parameters = (...),
    inputs = (...),
    statements = (
        DifferentialEquation(:cdk1, cdk1_rate),
        DifferentialEquation(:plk1, plk1_rate),
        DifferentialEquation(:apc, apc_rate),
    ),
    events = (...),
    solver = FixedStep(RK4(); step = SystemStep(0.01)),
    clock = SystemClock(:cell_cycle_time; scale = 1.0),
)
```

`CellDynamics`, `FieldDynamics`, and `GlobalDynamics` are authoring conveniences that normalize to
`ContinuousSystem`. They are not separate runtimes. `PottsProblem`, `PottsIntegrator`, and
`PottsSolution` remain the only problem, integrator, and solution families.

A continuous system is an immutable model declaration. Its mutable state lives only in registered
state declarations. It cannot retain an independent authoritative dictionary, solver object,
closure environment, or ModelingToolkit object.

## State Domains

### Domain protocol

Every system declares exactly one owner domain:

```julia
GlobalDomain()
CellDomain(cell_scope)
FieldDomain(field)
MembraneDomain(cell_scope, membrane_discretization)
```

A domain defines instance identity, state indexing, lifecycle, geometry, adaptation, persistence,
parallel iteration, and legal mappings. A downstream domain may extend the protocol only with those
complete semantics.

### Global state

`GlobalProperty` is typed mutable model-level state:

```julia
stimulus = GlobalProperty(
    :stimulus;
    initial = 0.0,
    invariant = Nonnegative(),
    persistence = CheckpointedProperty,
)
```

It is distinct from immutable `ModelParameter` and piecewise immutable `ScheduledParameter`.
Global state has one logical instance, explicit writers, a concrete isbits schema, initialization,
invariants, persistence, and semantic version.

Global state does not receive cell lifecycle policies. A global system may read aggregate cell,
field, relationship, or membrane values only through declared mappings.

### Per-cell state

Per-cell state continues to use `CellProperty` and belongs to `(CellID, CellGeneration)`.
`CellDomain(scope)` creates one system instance for each eligible active cell. All instances invoked
at one tick read one common cross-cell input snapshot and commit together.

Division, transition, death, retirement, and generation reuse use the mapped properties' explicit
policies. New cells begin system evolution at the lifecycle commit time with the state produced by
those policies. No hidden solver state is cloned.

### Field state

`FieldDomain(field)` uses the existing field descriptor and evolving-field state. A system statement
may represent reaction, diffusion, advection where accepted, algebraic field assignment, or a
synchronous field rule. Spatial operators name their discretization, placement, boundary, and
numerical policy.

### Membrane state

`MembraneProperty` is generation-aware state over a per-cell material membrane coordinate:

```julia
receptor = MembraneProperty(
    :receptor,
    Endothelial;
    discretization = AngularMembrane(128),
    initial = FillMembrane(0.0f0),
    remap = ConservativeMembraneRemap(),
    division = PartitionMembraneByGeometry(),
    transition = PreserveMembrane(),
    retirement = ResetMembrane(),
)
```

Its descriptor includes dimensional applicability, material coordinate, orientation, resolution,
interpolation, diffusion relation, remapping under accepted-copy shape changes, division,
transition, retirement, invariants, and persistence.

An accepted ownership copy does not directly add or remove membrane-array entries. It changes cell
geometry; the named remapping law updates the material representation at its declared phase. A
remapping law reports mass/concentration conservation and rejects degenerate geometry.

The first implementation may be CPU-only. The public contract is specified now so ODE systems do
not assume that every cell-local value is spatially uniform.

## Stable Symbol Identity and Scope

### Qualified references

Every declaration receives a stable `SymbolIdentity`, conceptually:

```text
(model namespace, domain identity, system identity, declaration name, semantic version)
```

Public expressions resolve through `SymbolRef`. The compiler stores resolved identities, not
unqualified strings. System-local declarations may intentionally shadow domain or global spellings,
but the normalized dependency graph records the resolved target explicitly.

The native authoring API rejects accidental ambiguity. A Morpheus compatibility adapter may accept
Morpheus lexical shadowing rules, but it must lower them into the same explicit resolved graph and
report every shadowed reference.

### Declaration kinds

The continuous language distinguishes:

- `Constant` — immutable within a system invocation or protocol stage;
- `StateVariable` — authoritative mutable state;
- `InputVariable` — immutable materialized input for one tick or solver interval;
- `IntermediateVariable` — pure event/system-local temporary;
- `FunctionDefinition` — pure parametric expression with no state;
- `ObservableVariable` — derived read-only value; and
- `TimeVariable` — global, MCS-relative, system-local, or stage-local time.

One spelling cannot silently change kind across scopes. Units, scalar/vector shape, domain, and
value type are part of identity and validation.

### Dependency graph

Normalization builds a dependency graph over all resolved reads and writes. It detects:

- missing or ambiguous symbols;
- dimension, type, and unit mismatch;
- illegal cross-domain reads without a mapping;
- multiple writers without an explicit resolver;
- reactive assignment cycles;
- unsupported DAE structure;
- stochastic operations without semantic labels; and
- history or delay use without sufficient initialization.

Inspection exposes both the complete graph and a reduced scientific graph. Declaration order never
resolves a dependency.

## Mathematical Statement Families

### Differential equations

`DifferentialEquation(target, rhs)` participates in one tightly coupled ODE or PDE system. Every RHS
evaluation at one solver stage reads the same stage state. All stage outputs commit according to the
selected method.

The stable CPU reference methods include fixed-step Euler, Heun, and classical RK4. A fixed method
declares an exact global step or positive integer substep count, scalar type, tableau, endpoint
alignment, and failure behavior. A requested step must tile the scheduled interval exactly within
the clock's canonical rational representation; the solver does not silently shorten the final step.
`FixedStep` accepts exactly one of `step = SystemStep(value)` or `substeps = positive_integer`.

Adaptive methods are separately identified. Exact continuation requires every future-relevant
controller, interpolation, Jacobian, event, and rejection state or a proved deterministic
reconstruction profile.

### Synchronous recurrence rules

`SynchronousRule(target, expression)` executes on a declared tick:

1. all rules read the same pre-tick system and mapped-input snapshot;
2. all stochastic draws use their declared tick and operation addresses;
3. all results validate; and
4. all targets commit together.

Rules may form recurrence cycles because they read old values. They may not observe another rule's
new value in the same tick. This supports Morpheus-style `Rule` semantics and bounded synchronous
cellular automata without confusing them with ODEs.

### Reactive algebraic assignments

`AlgebraicAssignment(target, expression)` defines an acyclic derived assignment. It is recomputed
when a declared dependency snapshot changes and before any consumer phase that requires it.
Assignments follow the normalized dependency graph, not declaration order.

An assignment does not own an independent historical value unless its target is explicitly
authoritative. A cycle is not broken by iteration or previous values; it requires a synchronous
rule or an `AlgebraicConstraint`.

### Pure functions

`FunctionDefinition(name, arguments, expression)` is pure and evaluated where used. It has no
schedule, storage, RNG, or side effect. Recursion is rejected in the first stable contract.

### Algebraic constraints and DAEs

`AlgebraicConstraint(residual)` belongs to an explicitly declared DAE system. It specifies
consistent initialization, differential/algebraic partition, solver, tolerances, event interaction,
and continuation profile.

DAEs begin Experimental and CPU-only but are part of the final architecture. Unsupported index or
singular initialization fails rather than being approximated as a reactive assignment.

### Stochastic systems

`StochasticDifferentialEquation` and stochastic rules declare noise dimension, interpretation
(including Itô or Stratonovich where applicable), numerical method, and named RNG operations.
Draw addresses include system identity, instance identity/generation, global tick or accepted
solver-step identity, stage, noise coordinate, and retry coordinate.

Changing an adaptive step path may change stochastic draws unless the method has a qualified
path-independent contract. The achieved reproducibility profile states this explicitly.

### Reactions and jump processes

`ReactionStatement` declares reactants, products, stoichiometry, compartment/domain, propensity or
rate law, and parameter identities. Its execution interpretation is explicit:

- `DeterministicReaction()` contributes the declared reaction rates to an ODE/PDE system;
- `DiscreteJumpProcess()` changes integer-valued state through a qualified exact or approximate
  jump algorithm; and
- `HybridReaction()` declares the partition and synchronization between deterministic and jump
  species.

An adapter cannot replace a discrete reaction network with deterministic mass action without an
`ExplicitApproximation` compatibility downgrade. Jump draws use reaction identity, domain
instance/generation, accepted event count, and retry coordinates rather than solver or container
order. Hybrid partitions, tau selection, negative-population prevention, event interaction, and
checkpoint continuation are fingerprinted.

## Fixed Delay State

`DelayState` wraps an authoritative state source with a constant semantic delay:

```julia
past_angle = DelayState(
    :past_angle,
    source = :angle,
    delay = 1.0,
    sampling = EveryGlobal(0.1),
    interpolation = ExactSample(),
    initial = RepeatInitialDelay(),
)
```

It declares:

- source domain and schema;
- positive delay;
- sample schedule and clock;
- interpolation or exact-grid requirement;
- initialization before the delay window fills;
- cell lifecycle and generation policies where applicable;
- bounded storage;
- persistence and canonical order; and
- backend support.

`ExactSample` requires delay to be an integer multiple of the sample interval.
`PiecewiseConstantDelay` and `LinearDelayInterpolation` are distinct identities. A delay never reads
uninitialized memory or infers interpolation from the solver.

For cell state, delay history belongs to the cell generation and uses explicit division,
transition, and retirement policies. `CellHistory` may lower to `DelayState` when its MCS sampling
and lag have exactly the same semantics; identity collapse requires a registered equivalence.

## Global and Multirate Time

### Clocks

The time hierarchy is:

```julia
GlobalClock(:physical_time; start, unit)
MCSDuration(global_interval)
SystemClock(:name; global = :physical_time, scale = scale)
SystemStep(step_in_system_time)
```

For completed MCS `m`:

```text
global_time(m) = global_start + m * MCSDuration
system_time = system_start + scale * (global_time - global_start)
```

The public Potts time remains integer MCS. `global_time(integrator)` is observable at completed-MCS
boundaries. Continuous ticks inside the current MCS are semantic internal boundaries, not
fractional public Potts steps.

Clock values use a canonical exact representation where schedules must coincide, ordinarily a
rational count plus a declared unit scale. Floating evaluation values may be derived for numerical
laws but do not decide tick equality.

### Multirate schedule

`MCSPlan` accepts an optional `MultirateSchedule`:

```julia
MCSPlan(
    timeline = MultirateSchedule(
        global_clock = physical_time,
        mcs_duration = MCSDuration(1.0),
        entries = (
            ScheduledSystem(cell_cycle, EveryGlobal(0.01), priority = 10),
            ScheduledEvent(reset_event, EveryGlobal(0.01), priority = 20),
            ScheduledPotts(PottsAttempts(), AtMCSEnd(), priority = 30),
            ScheduledLifecycle(LifecyclePhase(), AtMCSEnd(), priority = 40),
        ),
    ),
    observation = ObservationPhase(),
)
```

The ordinary positional `MCSPlan` is a simpler spelling that lowers to a timeline whose entries
occur only at named relative MCS boundaries.

Within one MCS interval the scheduler:

1. computes the next exact scheduled time among all enabled entries;
2. advances due continuous systems to that time from their own clocks;
3. materializes the common snapshot for entries at that time;
4. orders same-time entry groups by explicit semantic priority;
5. evaluates and atomically commits each group;
6. repeats until the MCS endpoint;
7. validates every clock and pending request;
8. runs the final required observation boundary; and
9. publishes the completed integer MCS.

Entry declaration order is irrelevant. Equal priorities with conflicting writes fail construction.
Independent equal-time entries may execute together from one snapshot.

Exactly one `PottsAttempts` entry occurs per public MCS. Its relative location is explicit:
`AtMCSStart`, `AtMCSEnd`, or a declared rational offset. Source compatibility must name which
continuous/event ticks occur before and after it.

### Internal commit and failure

Each scheduled tick or event batch is an atomic subtransaction. Earlier internal subtransactions in
a target MCS may already have committed when a later one fails. As with ordinary coupled phases, the
target MCS then remains unpublished, the integrator becomes terminal, and recovery uses the
preceding completed-MCS checkpoint.

Stable checkpointing remains completed-MCS only. The checkpoint stores no in-flight timeline.
Exact restore reconstructs the next tick of every schedule from completed clocks and schedule
identities.

## Continuous Events

### Event declaration

```julia
ContinuousEvent(
    :reset_voltage;
    domain = GlobalDomain(),
    trigger = SampledTrigger(:voltage >= :threshold, OnRising()),
    schedule = EveryGlobal(0.1),
    assignments = (
        EventAssignment(:voltage, 0.0),
    ),
    values = FromTriggerSnapshot(),
)
```

An event declares domain, condition, trigger memory, evaluation schedule or root function, delay,
priority, assignments/requests, assignment-value time, cascade policy, RNG operations, and
persistence.

### Sampled events

`SampledTrigger` is the stable Morpheus-compatibility baseline. It evaluates only on its exact
declared scheduler ticks. It does not claim to locate a mathematical crossing between ticks.

Trigger-memory policies are:

- `WhileTrue()` — execute on every due tick whose condition is true;
- `OnRising()` — execute only when the sampled condition changes false to true;
- `OnceWhenTrue()` — execute once and remain latched; and
- `PersistentTrigger()` — once triggered, retain the event even if the condition later becomes
  false before a delayed commit.

The previous sampled condition and latch state are authoritative event state and checkpointed.
Morpheus `trigger`, `history`, and `persistent` spellings lower to one explicit combination and are
recorded in the compatibility report.

### Root events

`RootTrigger(root_function; direction, tolerance, locator)` asks the selected continuous solver to
locate a crossing inside an interval. It specifies:

- rising, falling, or either direction;
- root-location method and tolerances;
- behavior at an initial zero;
- simultaneous-root grouping and priority;
- maximum root/event iterations;
- assignment and restart behavior; and
- exact-continuation state.

Root events are Experimental until qualified. An adapter must not translate a sampled source event
to `RootTrigger` merely because root finding appears more accurate; that changes model semantics.

### Assignment snapshot

All assignments in one event read a common snapshot and commit together.

`FromTriggerSnapshot()` evaluates right-hand sides when the trigger is detected and stores the
results through any delay. `FromExecutionSnapshot()` evaluates them at commit time. This choice is
fingerprinted.

Intermediate event variables are evaluated once from the selected snapshot and may be referenced
by multiple assignments. They are phase-local unless delayed assignment values must persist.

### Delays, priority, and cascades

An event delay uses the global or system clock explicitly. Delayed events enter a bounded,
canonical priority queue containing event identity, domain instance/generation, trigger time,
execution time, stored trigger values where applicable, and semantic RNG coordinates.

Events due at one time form an `EventBatch`. Conflicting assignments require explicit stable
priority or a typed resolver. Atomic arrival and declaration order are prohibited.

The default `NoImmediateCascade()` makes new conditions visible at the next scheduled evaluation.
`CascadeUntilStable(max_iterations)` reevaluates declared event dependencies after each committed
batch at the same semantic time. It fails on cycles or the iteration bound. Cascade policy is
required for SBML event mappings that depend on same-time event chains.

## Lifecycle Requests and Timed Lifecycle Boundaries

Continuous systems and events cannot mutate ownership or cell identity directly. They emit typed:

```julia
LifecycleRequest(
    event_identity,
    target_identity_and_generation,
    effect,
    trigger_time,
    payload,
)
```

A `ScheduledLifecycle` entry consumes due requests through the accepted lifecycle planner,
validation, capacity preflight, conflict resolution, and atomic commit. Its snapshot is the state at
that explicit global scheduler time.

The ordinary `LifecyclePhase()` remains once at the completed-MCS boundary. A multirate model may
add `TimedLifecyclePhase()` entries inside the MCS interval. This is a new opt-in contract:

- only effects and auxiliary-state policies declaring `TimedLifecycleCapability` are admitted;
  existing MCS-boundary lifecycle declarations do not become timed-compatible automatically;
- each boundary has one common `PreLifecycleSnapshot(global_time, target_mcs)`;
- requests cannot see outcomes of other requests in the same boundary;
- cell IDs retired anywhere in public MCS `m` are not reused until MCS `m + 1`;
- new cells become eligible for later scheduled systems and Potts attempts in the same MCS only
  when their commit precedes those entries;
- property, delay, membrane, relationship, and solver policies apply at the exact commit time;
- lifecycle schedules and requests are fingerprinted; and
- no intermediate lifecycle state is a stable checkpoint.

This extends lifecycle timing only for models that declare the multirate contract. Existing
Phase 13 and ordinary Phase 14 lifecycle meaning is unchanged.

## Typed Mappers and Reporters

### Symbol map

`SymbolMap` maps one declared source value into one destination input or state:

```julia
oxygen_input = SymbolMap(
    :oxygen_to_cell;
    source = MeanField(:oxygen, SitesOfCell()),
    destination = InputRef(cell_cycle, :oxygen),
    schedule = Every(0.1),
)
```

It declares source/destination domains, snapshot, schedule, interpolation, unit conversion, empty
behavior, and write category.

### Domain reductions

Reusable mapping families include:

- cell-to-global count, sum, mean, minimum, maximum, and histogram;
- global-to-cell broadcast;
- field-to-cell point, centroid, site mean, integral, and boundary sampling;
- cell-to-field conservative deposition and other accepted exchange laws;
- neighbor-cell distinct-identity reductions over an explicit query relation;
- site-to-cell and cell-to-site reductions;
- membrane-to-cell integral, mean, extrema, and modes; and
- cell/field-to-membrane sampling.

Every reduction declares filtering, weighting, normalization, empty law, numerical accumulation,
determinism profile, and destination visibility time. A mapper never receives arbitrary storage.

Morpheus-style lexical/spatial symbol lookup lowers to explicit mappings. It is not reproduced as
runtime name resolution.

## ModelingToolkit and SBML Adapters

### Adapter protocol

An optional `ContinuousModelAdapter` lowers an external system into declarations in this document:

```julia
adapt_continuous_model(
    source;
    domain,
    profile = MorpheusSemanticProfile(),
    identity,
)
```

It returns:

- normalized continuous systems, state declarations, mappings, events, and schedules;
- a construct-by-construct `CompatibilityReport`;
- source format/version and content checksum;
- adapter and dependency versions;
- canonical source-to-target identity map;
- transformations and numerical choices;
- unsupported or approximated constructs; and
- required extensions and backend capabilities.

An adapter cannot execute a partially translated model unless the caller explicitly selects
`ExplicitApproximation` or `PartialMapping`. Paper and compatibility claims reject both.

### ModelingToolkit

The optional ModelingToolkit extension may lower ODE, DAE, discrete, event, reaction, and supported
PDE systems. It maps each symbolic variable to a registered state or input and each callback/event
to the event contract above.

ModelingToolkit remains an authoring/compiler dependency, not authoritative runtime state or a
fingerprint by object identity. Potts.jl owns multirate order, lifecycle requests, checkpoints,
semantic RNG, and compatibility reporting.

### SBML

An SBML adapter may use the SciML ecosystem or another qualified parser, but its output must use the
same adapter protocol. It reports support separately for compartments, species, parameters,
reactions, rate rules, assignment rules, algebraic rules, functions, initial assignments, events,
delays, priorities, units, and stochastic packages.

“SBML imported” is not one Boolean capability. A construct omitted or numerically reinterpreted
downgrades the whole model claim.

### MorpheusML

A future MorpheusML adapter parses a pinned schema/release and lowers:

- scopes and symbols;
- systems, equations, rules, functions, delays, and events;
- mappers/reporters;
- lifecycle plugins;
- CPM and field declarations; and
- analysis schedules where supported.

Automatic import is optional after the semantic core. It cannot define the core semantics by
copying implementation accidents from Morpheus.

## Persistence

The coupled checkpoint envelope adds canonical blocks for:

- global properties;
- membrane properties and material-coordinate metadata;
- delay histories;
- system clocks and fixed/adaptive continuation state;
- event trigger memory;
- delayed-event queues and stored trigger-time values;
- multirate schedule positions derivable from completed clocks but stored for validation;
- pending lifecycle requests only when a completed-MCS boundary intentionally carries them; and
- adapter/compatibility identities required for exact restore.

The default completed-MCS invariant requires no due event or lifecycle request at or before the
checkpoint time. A model that intentionally carries a future delayed event stores it. Phase-local
solver stages and mapper workspaces remain reconstructible.

Canonical ordering uses state-family identity, system identity, domain instance/generation, event
time, priority, and event identity. Backend heap or queue layout is not persistent meaning.

## Fingerprints and Inspection

The scientific fingerprint covers:

- domain and state schemas;
- fully resolved symbol dependency graph;
- mathematical statements and expression identities;
- schedules, clocks, scale, step, and solver contract;
- event conditions, memory, delays, priority, snapshots, and cascades;
- mapper/reporter laws;
- lifecycle-request and timed-boundary semantics;
- delay and membrane policies;
- stochastic namespaces;
- adapter identity and source checksum; and
- compatibility-profile version.

`explain(model)` and `explain(prob)` show all of the above plus memory scaling, backend support,
source-to-target mappings, and every downgraded compatibility row.

## Backend Contract

The full reference contract is CPU-first. Metal and ROCm are capability-specific. A GPU-qualified
continuous system requires bounded backend-resident state, device-lowerable statements and events,
qualified solvers, deterministic conflict handling, no undeclared host synchronization, and
real-hardware evidence.

Global host ODE execution may be explicitly synchronized without implying that per-cell, field, or
membrane systems are GPU-compatible. A plan never silently migrates unsupported ticks to the host.

Membrane systems, DAEs, adaptive/root events, and general SBML adapters begin CPU-only or
Experimental. This affects implementation maturity, not the final public architecture.

## Failure Semantics

Construction fails for unresolved symbols, invalid scopes, dependency cycles, conflicting writers,
clock incommensurability, unsupported solver/statements, insufficient delay/event capacity, invalid
lifecycle policies, adapter loss, or unqualified backend use.

At runtime, one scheduled subtransaction fails atomically for nonfinite state, invariant violation,
solver failure, event iteration overflow, delayed-queue capacity, stale generation, mapping failure,
or lifecycle capacity. The target MCS remains incomplete and the integrator becomes terminal.

## Required Conformance Evidence

### Language and state

- global, per-cell, field, and membrane scope fixtures;
- qualified symbol resolution and compatibility shadowing;
- differential, synchronous-rule, assignment, function, DAE, and stochastic microfixtures;
- deterministic reaction, exact jump, and hybrid reaction fixtures;
- rule and declaration permutation invariance;
- fixed-delay initialization, interpolation, lifecycle, and restart;
- membrane remapping and conservation under copy, division, and death.

### Time and events

- exact global/MCS/system clock conversion;
- incommensurate schedule rejection;
- multiple system ticks per MCS and multiple MCS per global unit;
- explicit same-time priority and independent batching;
- sampled `WhileTrue`, `OnRising`, one-shot, persistent, delayed, and cascade events;
- root-event direction, tolerance, simultaneous root, and restart fixtures;
- deterministic semantic RNG under reordered scheduling;
- timed lifecycle request, division, death, transition, and ID-reuse fixtures.

### Mappings

- global/cell, field/cell, neighbor/cell, site/cell, and membrane/cell reductions;
- empty, boundary, periodic, unit, and normalization cases;
- common snapshot and destination visibility tests;
- conservation fixtures for source/deposition mappings.

### Compatibility

- Morpheus integrate-and-fire event;
- Morpheus per-cell cell-cycle ODE driving division;
- Morpheus run-and-tumble sampled stochastic event;
- Morpheus field-cell consumption;
- one synchronous-rule/CA model;
- one delay-property model;
- one membrane-state model;
- one pinned SBML oscillator and supported semantic-suite subset;
- complete compatibility reports with intentional rejection fixtures; and
- no regression in ordinary uncoupled or positional-Phase 14 plans.

## Acceptance Boundary

The public architecture may be accepted before every adapter or advanced solver is implemented, but
the following must be stable and reference implemented before claiming Morpheus continuous-system
parity:

- global and per-cell systems;
- differential equations, synchronous rules, assignments, and functions;
- fixed delays;
- sampled events and multirate scheduling;
- typed cross-domain mappings;
- lifecycle requests at explicit boundaries;
- field coupling;
- complete persistence and compatibility reporting; and
- the named Morpheus microfixtures.

DAEs, exact root events, membrane systems, stochastic differential/jump/hybrid systems, and
automatic MorpheusML import may ship later with explicit maturity, but their state domains and
extension contracts are fixed here so they do not require a second runtime or another architectural
rewrite.
