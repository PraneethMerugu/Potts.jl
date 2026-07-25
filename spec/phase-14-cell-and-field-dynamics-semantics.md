# Phase 14 Cell and Field Dynamics Semantics

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: Cell, field, exchange, solver, and splitting requirements now specialize the single
`state`, `process`, and `plan` contracts in the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md).

## Purpose

This document defines deterministic per-cell continuous dynamics, evolving spatial fields,
cell--field exchange, and the optional ModelingToolkit authoring boundary. It composes with
[Coupled Execution and MCS Plan Semantics](phase-14-coupled-execution-semantics.md),
[Dynamic State Ownership Semantics](phase-14-dynamic-state-semantics.md), and the accepted
[Cartesian field contract](cartesian-surface-queries-and-fields.md).

The general system language, global/membrane domains, synchronous rules, delays, events, multirate
scheduling, and Morpheus compatibility profile are defined in
[Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md).
`CellDynamics` and `FieldDynamics` are focused conveniences that lower to that contract.

The Potts integrator remains the sole runtime owner. ModelingToolkit and SciML solvers may describe
or advance one declared process; they do not own MCS scheduling, lifecycle, observations,
checkpointing, semantic randomness, or CPM transactions.

## Common Continuous-Process Contract

Every `CellDynamics` or `FieldDynamics` declaration contains:

- a stable process identity and semantic version;
- authoritative state mappings;
- immutable parameter mappings;
- materialized input mappings from one named phase snapshot;
- one `ContinuousClock`;
- an advance law and numerical method;
- declared reads, writes, invariants, and failure policy;
- process-local semantic time;
- continuation and backend profiles; and
- optional authoring-system provenance.

An `Advance(process; interval, active)` invocation receives the continuous interval implied by the
selected clock and target MCS. The interval is materialized before advancement. A process cannot
read a live integrator or observe state written after its phase snapshot.

All declared inputs are gathered into typed, bounded storage before calling a numerical law.
Materialization uses explicit units and aggregation rules. Empty reductions, invalid identities,
nonfinite inputs, or unsupported interpolation fail before any authoritative output is committed.

An advance is atomic at the process level:

1. validate state, input, interval, and workspace;
2. advance into staging storage;
3. validate solver status and output invariants;
4. commit all mapped state and the process clock together; or
5. commit nothing and make the target MCS terminally failed.

## Cell Dynamics

### State and input mappings

`CellDynamics` maps one or more existing `CellProperty` declarations into a fixed-shape state:

```julia
rac = CellDynamics(
    :rac,
    state = StateMap(RacState => :rac_state),
    parameters = ParameterMap(RacParameters => (:kon, :koff)),
    inputs = InputMap(
        :signal => MeanField(signal, SitesOfCell()),
        :speed => CellSpeed(:centroid_history),
    ),
    law = DirectCellRHS(rac_rhs!; identity = :wang_rac_rhs, version = v"1.0.0"),
    method = FixedStep(RK4(); substeps = 4),
    clock = :physical_time,
)
```

A mapping names each component and its scalar type, shape, unit annotation, and valid domain.
Mapping by array position without names is rejected. Every active cell of a selected type is
advanced exactly once in canonical generation-aware identity order for the CPU reference.
Inactive slots are neither advanced nor passed to user laws.

Inputs are immutable over one invocation. A field mean, centroid-derived quantity, relationship
reduction, or cell-neighbor reduction therefore reflects the phase snapshot even if other cells are
committed earlier in the CPU loop. Cell laws cannot couple through freshly written same-phase cell
state; such coupling requires a separately declared aggregate and a later phase.

### Direct law protocol

The stable reference protocol is an in-place, allocation-free law over typed values:

```julia
cell_rhs!(du, u, inputs, parameters, continuous_time, context)
```

`context` exposes only immutable identity, type, generation, declared constants, and addressed RNG
access when the process explicitly declares a stochastic law. It is not an integrator handle.

The law identity is not inferred from a Julia function name or method pointer. A reusable law
supplies an explicit semantic name, version, state schema, input schema, and parameter schema.
Closures and anonymous functions may be used experimentally but are not eligible for durable
paper reconstruction or stable fingerprints.

### Numerical methods

The first stable profile is `FixedStep` with a fixed positive integer number of substeps per process
invocation. The exact tableau or stepping algorithm, substep count, scalar type, and arithmetic mode
are semantic fingerprint inputs. Internal continuous time begins at the process clock's recorded
time and ends exactly at the requested interval endpoint.

An `AdaptiveStep` profile is Experimental. It records tolerances, method, event/root handling,
accepted and rejected step state, interpolation state, and every solver option needed for exact
continuation. It MUST NOT claim exact checkpoint continuation until uninterrupted-versus-restored
tests establish it under a pinned dependency profile. Phase 14 paper baselines use fixed stepping
unless an audited source requires adaptive behavior.

State invariants are validated after every accepted fixed substep when violation could poison later
arithmetic, and again before atomic commit. A configured projection is a named numerical law and is
not silently applied.

### Division, death, and type transition

Each mapped `CellProperty` retains its existing lifecycle policy. `CellDynamics` adds no implicit
inheritance. New cells begin with the property values produced by the accepted division transaction
and are first eligible at the next process phase. Retired cells cease to advance immediately after
the lifecycle transaction. A type transition changes eligibility only after its transaction
commits.

## Optional ModelingToolkit Authoring

### Extension boundary

ModelingToolkit support belongs to a PottsToolkit package extension and is absent from the
CorePotts dependency graph. It lowers an `ODESystem` or supported symbolic system into the same
`CellDynamics` declaration and direct numerical protocol:

```julia
cell_dynamics(
    :rac,
    rac_system;
    state = Dict(x => :rac_x, y => :rac_y),
    inputs = Dict(signal(t) => MeanField(:signal, SitesOfCell())),
    parameters = Dict(kon => :kon, koff => :koff),
    method = FixedStep(RK4(); substeps = 4),
    clock = :physical_time,
    identity = ContinuousLawIdentity(:wang_rac, v"1.0.0"),
)
```

Every symbolic state, input, parameter, and independent variable is mapped explicitly. Supported
equations, algebraic constraints, delays, callbacks/events, stochastic equations, and
discontinuities lower through the general continuous-system contracts. Unmapped or unsupported
constructs and unit inconsistencies fail at lowering; no construct is treated as an ODE merely
because it appears in a symbolic system.

### Semantic identity

Arbitrary internal ModelingToolkit serialization is not a durable scientific identity. The lowered
record contains:

- the user-supplied `ContinuousLawIdentity`;
- adapter contract version;
- canonical variable and equation representation produced by that adapter;
- explicit state/input/parameter maps;
- simplification and compilation choices;
- generated numerical-law checksum;
- ModelingToolkit and relevant SciML package versions; and
- the selected numerical method.

The scientific fingerprint includes the adapter-canonical equations and all mappings. The execution
fingerprint additionally pins dependency and generated-code identities required by the continuation
profile. A change in symbolic simplification that preserves mathematics but changes the adapter
canonical form produces a new fingerprint unless an accepted canonical-equivalence rule proves
otherwise.

Direct and ModelingToolkit-authored laws may be declared scientifically equivalent only through a
registered equivalence fixture. Similar generated numerical results do not cause automatic identity
collapse.

## Field Dynamics

### Authoritative field state

The existing `Field` descriptor remains scientific identity. An evolving field adds authoritative
values, a semantic field time, and one `FieldDynamics` process:

```julia
vegf_dynamics = FieldDynamics(
    :vegf_dynamics,
    field = :vegf,
    law = ReactionDiffusion(diffusion = D, decay = gamma),
    forcing = :vegf_exchange,
    method = FixedStep(ExplicitEuler(); substeps = 20),
    clock = :physical_time,
)
```

The field placement, grid, physical coordinates, spacing, boundary conditions, interpolation, and
field-discretization relation come from the accepted field contract. CPM ownership boundaries never
imply field boundaries.

One process owns one field's advancement in a phase. Multiple species may use a single typed
multi-species field or an explicitly coupled field system. Two independent processes cannot write
the same field in one phase.

### Transient advance

A transient law advances from the phase's immutable field and forcing snapshot. The numerical method
declares stability requirements, substeps, spatial operator, reaction evaluation, flux convention,
positivity behavior, scalar type, and reduction policy. Preflight validates any known CFL or method
constraints. Crossing a known stability limit fails; the runtime does not silently add substeps.

Boundary conditions are applied by the declared discretization at every substep. Source and sink
units are converted through explicit cell/field volume measures. Clipping or positivity projection
is a named, fingerprinted law and must report the amount corrected.

### Steady-state advance

`SteadyStateAdvance` solves the declared stationary field equation at one phase:

```julia
SteadyStateAdvance(
    method;
    absolute_tolerance,
    relative_tolerance,
    maximum_iterations,
    residual_norm,
)
```

Convergence requires the declared residual criterion. Maximum-iteration exhaustion, nonfinite
residuals, or a singular unsupported problem causes atomic failure. A previous field is an initial
guess only; it is not an accepted solution merely because the solver stopped.

Steady-state fields still carry the target phase time and solver diagnostics. A source model must
choose transient or steady-state semantics explicitly.

### MethodOfLines lowering

A ModelingToolkit `PDESystem` may lower through the optional extension when it maps to a supported
fixed domain, field placement, spatial discretization, boundary set, and time law. PottsToolkit's
`Field` descriptor is authoritative for grid and boundary identity. The extension validates symbolic
equivalence to those declarations and rejects disagreement; it never silently rebuilds the Potts
field from symbolic defaults.

Moving meshes, remeshing, free boundaries, arbitrary finite-element spaces, and topology-changing
domains are outside the initial contract. MethodOfLines is an authoring path, not a requirement for
native reaction--diffusion laws.

## Cell--Field Exchange

### Declaration and staging

`FieldExchange` maps a phase snapshot into a typed field forcing array and optional per-cell outputs:

```julia
vegf_exchange = FieldExchange(
    :vegf_exchange,
    field = :vegf,
    sources = (
        Secretion(Hypoxic; rate = :vegf_rate, distribution = ByCellVolume()),
    ),
    sinks = (
        Uptake(Endothelial; law = MichaelisMenten(:vmax, :km)),
    ),
)
```

Exchange does not directly integrate the field. It stages source/sink rates for a later
`FieldDynamics` invocation or, for a separately named clamped law, atomically sets concentration.
The plan makes this ordering visible.

Every law states:

- eligible owner categories and sites;
- whether rates are per cell, per occupied CPM site, per physical volume, or per field volume;
- CPM-to-field deposition/interpolation;
- treatment of partially covered coarse field cells;
- medium and obstacle behavior;
- concentration and cell-state sampling time;
- reduction ordering and numerical policy;
- saturation, clipping, and insufficient-mass behavior; and
- optional outputs written to named cell properties.

### Balance law

For conservative exchange, the integrated field removal and cell acquisition agree within the
declared numerical tolerance after unit conversion. A sink cannot remove more available material
than its policy permits. Competing cells use one snapshot and a declared allocation law; canonical
serial order is not an implicit allocation policy.

Nonconservative production, degradation, or reservoir coupling is explicitly categorized and
reports produced or removed mass. `ConstantConcentration` is a boundary/reservoir constraint, not
secretion with an infinite rate.

Pending forcing is reconstructible only when it is a pure function of the same completed phase
snapshot. Stable checkpoints occur after observation and contain no pending exchange. If a source
event accumulates forcing across MCS values, that accumulator becomes named authoritative state and
is checkpointed.

## Splitting and Snapshot Examples

The plan, not the field declaration, chooses a split:

```julia
MCSPlan(
    Phase(:exchange_pre, Accumulate(vegf_exchange)),
    Phase(:field_half_pre, Advance(vegf_dynamics; interval = HalfMCS())),
    PottsAttempts(),
    Phase(:field_half_post, Advance(vegf_dynamics; interval = HalfMCS())),
    Phase(:cell_post, Advance(rac; interval = OneMCS())),
    LifecyclePhase(),
    ObservationPhase(),
)
```

This is a named symmetric split only if the two field advances use the declared half intervals and
the second observes ownership and exchange inputs from its named post-attempt snapshot. A single
post-Potts advance, pre-Potts advance, predictor--corrector, or source-specific update order uses a
different plan identity.

No phase may advance the same process clock over overlapping intervals. At the completed MCS, every
required process clock must equal the time implied by its plan and stage. Preflight proves this for
static plans; runtime validates conditional stages.

## Backend and Synchronization

The first required implementation is the ordinary CPU reference. Metal and ROCm support is
capability-specific and requires:

- backend-resident authoritative state and staging;
- no undeclared host synchronization during stepping;
- qualified kernels or solver integration;
- reduction and numerical conformance;
- device failure propagation; and
- real-hardware restart and scientific fixtures.

ModelingToolkit construction and compilation may run on the host. This does not authorize
per-MCS host materialization of device fields or cell state. DiffEqGPU or another accelerator
package is never selected automatically from a GPU Potts backend.

## Failure and Diagnostics

Construction fails for incomplete mappings, incompatible units, ambiguous clocks, unsupported
symbolic features, overlapping writers, invalid discretization, or unavailable backend support.
Advancement fails atomically for solver failure, nonfinite output, invariant violation, invalid
source balance, or process-clock mismatch.

Diagnostics include method identity, interval, substeps or iterations, residual/error summary,
conservation summary, projection amount, and achieved backend profile. Diagnostics are observational
state and need not be checkpointed unless they influence future execution.

## Required Conformance Evidence

- direct-law analytic scalar and vector ODE solutions;
- identical results under active-slot holes and slot reuse;
- immutable same-phase input and cell-order fixtures;
- division, retirement, and type-transition eligibility;
- fixed-step uninterrupted-versus-checkpoint continuation;
- ModelingToolkit mapping, canonicalization, dependency, and rejection fixtures;
- direct-versus-symbolic registered equivalence fixture;
- analytic diffusion/decay and manufactured 2D/3D field solutions;
- periodic, Dirichlet, Neumann, and mixed-boundary fixtures;
- transient stability and steady-state convergence failures;
- coarse/fine CPM-to-field deposition and sampling;
- conservative exchange balance and competing-uptake fixtures;
- every named split order and process-clock invariant;
- MethodOfLines agreement for the supported subset; and
- backend preflight plus real-hardware evidence before any GPU claim.

## Source Closure Required for Paper Qualification

The reusable contracts do not guess paper numerics. Each model record must still close:

- Merks field equation, solver family, boundary, step size, and update order;
- CNV species, steady/transient choice, ECM-bound species, exchange units, and lifecycle sampling;
- Wang intracellular equations, exact time mapping, numerical method, and field coupling; and
- every source's concentration normalization and observation time.

An unresolved item blocks close paper reproduction but does not block implementation of the
well-defined reusable reference contracts above.
