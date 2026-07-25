# Phase 14 Coupled Execution and MCS Plan Semantics

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: Clock, scheduling, stage, event, and phase requirements now specialize the single
`plan` contract in the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md). This document is not a second
scheduler authority.

## Purpose

This document defines how Potts copy attempts, accepted-copy effects, auxiliary biological
processes, lifecycle events, staged experiments, continuous clocks, observations, failures, and
backends compose into one MCS. It specializes the architecture proposed by the
[Phase 14 Coupled Dynamics and ModelingToolkit API](phase-14-coupled-dynamics-api.md).

It is governed by the accepted [Time and MCS](time-and-mcs.md),
[Lifecycle](lifecycle.md), [SciML Interface](sciml-interface-semantics.md),
[Persistence](persistence.md), and
[Randomness and Reproducibility](randomness-and-reproducibility.md) contracts.
Where this provisional document conflicts with an accepted contract, the accepted contract wins
until an explicit D10 release decision says otherwise.

## Goals

The coupled execution contract MUST:

- preserve public integer-MCS time;
- make every scientifically meaningful order explicit;
- preserve the existing proposal, acceptance, transaction, lifecycle, saving, and callback laws;
- permit source-faithful pre-attempt, post-attempt, continuous, field, history, graph, and site
  processes;
- reject hidden or ambiguous read/write coupling;
- keep uncoupled Phase 13 behavior and artifact identities unchanged;
- expose all synchronization and backend limitations; and
- support exact continuation from completed-MCS checkpoints.

It MUST NOT become an unrestricted callback scheduler.

## Terms

**Current MCS**
: The last fully completed public integer MCS, exposed as `integrator.t`.

**Target MCS**
: `current_mcs + 1`, the MCS whose plan is being executed.

**Plan**
: One immutable, versioned, explicitly ordered `MCSPlan` declaration.

**Phase**
: One named atomic auxiliary-process boundary. Every invocation in a phase reads one common phase
  snapshot and publishes its validated writes together.

**Potts stage**
: The one `PottsAttempts` stage that executes the solve-selected CPM algorithm's complete
  normalized attempt budget for the target MCS.

**Completed-MCS boundary**
: The state after lifecycle, observation bookkeeping, required diagnostics, and all accepted
  completed-MCS operations have succeeded for the target MCS.

**Accepted-copy effect**
: A typed state update staged and committed with an already accepted actionable ownership
  transaction.

**Protocol stage**
: A named across-MCS range selected before execution of one target MCS.

## Public Values

The candidate Level 2 values are:

```julia
MCSPlan
Phase
PottsAttempts
LifecyclePhase
ObservationPhase
AcceptedCopyUpdate
StagedProtocol
ProtocolStage
MCSRange
ScheduledParameter
During
ContinuousClock
ContinuousInterval
OneMCS
HalfMCS
```

The exact exported inventory remains provisional, but any replacement MUST preserve the semantic
categories in this document.

## Plan Shape

A coupled model declares exactly one plan. This section defines the ordinary positional plan:

```julia
plan = MCSPlan(
    Phase(:field_pre,
        Advance(field_dynamics; interval = HalfMCS())),
    PottsAttempts(on_accept = (activate_site,)),
    Phase(:history,
        Sample(centroid_history)),
    Phase(:cell_dynamics,
        Advance(rac_dynamics; interval = OneMCS())),
    Phase(:relationships,
        Update(junction_dynamics)),
    Phase(:field_post,
        Advance(field_dynamics; interval = HalfMCS())),
    LifecyclePhase(),
    ObservationPhase(),
)
```

A valid plan MUST contain:

- exactly one `PottsAttempts`;
- exactly one `LifecyclePhase` after `PottsAttempts`;
- exactly one `ObservationPhase` after `LifecyclePhase`; and
- every required process invocation exactly as declared by that process's multiplicity contract.

A plan MAY contain zero or more named `Phase` values before `PottsAttempts` and zero or more after
it but before lifecycle.

The opt-in `MultirateSchedule` form, including continuous ticks and `TimedLifecyclePhase` values
inside one public MCS, is defined in
[Continuous Systems and Morpheus Semantic Compatibility](phase-14-continuous-systems-and-morpheus-compatibility.md).
It retains exactly one `PottsAttempts` and one final completed-MCS observation, but may contain
additional explicitly scheduled lifecycle transactions. It does not change this positional plan or
the behavior of models that omit a multirate schedule.

No auxiliary phase occurs between the final lifecycle commit and ordinary completed-MCS
observation.

An uncoupled model does not need an `MCSPlan`. It retains the Phase 13 path and artifact identities.
The implementation MUST NOT normalize an omitted plan into new semantic data that changes an
uncoupled model fingerprint.

## Positional One-MCS State Machine

For current MCS `m`, `step!(integrator, 1)` executes:

1. calculate target MCS `m + 1`;
2. select the protocol stage and scheduled values for target MCS `m + 1`;
3. execute each pre-attempt phase in declared plan order;
4. execute the complete `PottsAttempts` stage for target MCS `m + 1`;
5. execute each post-attempt phase in declared plan order;
6. construct the existing `PreLifecycleSnapshot`;
7. plan, validate, resolve, and atomically commit lifecycle effects;
8. execute completed-MCS observation bookkeeping and ordinary scheduled saving/callback ordering;
9. validate completed-MCS invariants and diagnostics; and
10. publish public time `integrator.t = m + 1`.

Public time MUST NOT advance earlier. A process MAY maintain a separate continuous semantic clock,
but it cannot alter public MCS time.

All semantic RNG addresses use the target MCS and the owning contract's accepted subinterval,
process, entity, invocation, and draw identities. Declaration order, phase tuple storage, device
launch order, thread scheduling, and completion order are not implicit RNG identities.

## Phase Semantics

### Common snapshot

Every invocation in one `Phase` reads one common immutable logical snapshot taken after all preceding
phases have published and before any invocation in the current phase publishes.

The snapshot contains only the state and observables declared by the phase's compiled read union.
An implementation MAY provide efficient typed views rather than materializing a full host copy.
Logical immutability does not imply host residency.

### Planning and commit

One phase executes:

1. snapshot construction or binding;
2. invocation planning/computation;
3. local invariant validation;
4. write-conflict resolution under an explicit typed policy;
5. resource and capacity validation;
6. atomic publication of the resolved write set;
7. derived-state repair owned by the applicable state contract; and
8. phase diagnostics publication.

If any required validation fails, none of that phase's writes publish.

Atomic publication is semantic. A backend MAY use multiple kernels if no observation can expose a
partial state and failure handling preserves the declared phase result.

### Simultaneous versus sequential behavior

Invocations in one phase cannot see each other's writes. Tuple position inside a phase is
representational.

Sequential dependence requires separate phases:

```julia
Phase(:sample, Sample(history)),
Phase(:derive, Update(polarity_from_history)),
```

It is invalid to place these processes in the same phase if `derive` requires the new sample.

### Phase identities

A phase has a stable semantic name and version. Renaming a phase changes model meaning whenever
the identity participates in process scheduling, RNG addressing, checkpoint compatibility,
observations, or evidence.

Phase names MUST be unique within one normalized plan. A convenience constructor MAY generate
names from a versioned preset, but the expanded names appear in inspection and the fingerprint.

## Read and Write Validation

Every process declares typed read and write sets. A read/write entry includes:

- semantic state identity;
- owner scope;
- state generation where applicable;
- access mode;
- snapshot requirement;
- effect category;
- reduction or conflict policy where applicable; and
- persistence and backend requirements.

Normalization rejects:

- a read of undeclared state;
- a write to immutable parameter or component data;
- two phase writes to the same target without a compatible explicit resolver;
- a read that requires a value produced later in the plan;
- a process invoked in a phase category it does not support;
- a dynamic declaration absent from the plan;
- an invocation of an undeclared process;
- an instantaneous dependency cycle;
- phase-local mutation through an alias not present in the write set; and
- a downstream extension whose access declaration is incomplete.

Dependency analysis validates the user-declared plan. It MUST NOT topologically sort processes or
silently insert phases. A correction report MAY propose an order, but applying it requires a new
model value.

## PottsAttempts

`PottsAttempts` delegates proposal selection, acceptance, attempt accounting, transaction staging,
commit, tracker repair, and algorithm diagnostics to the solve-selected algorithm and its frozen or
newly accepted contract.

The plan does not redefine an MCS attempt budget. `SequentialCPM` remains exactly `N` attempts.
The proposed `BudgetedSequentialCPM` is a separately identified algorithm.

Auxiliary state visible to energy, drive, constraint, modifier, and mechanical components is the
state published by the latest preceding plan phase. These components retain the accepted proposal
snapshot and transaction rules.

`PottsAttempts` cannot be conditionally disabled by a protocol stage in a stable coupled model. A
source protocol with a no-Potts interval requires a separately specified experiment-time contract
rather than pretending that a no-op is one normalized MCS.

## Accepted-Copy Effects

### Eligibility

An `AcceptedCopyUpdate` runs only when:

- the proposal is actionable;
- every hard constraint permits it;
- its acceptance law accepts it; and
- the ownership transaction is ready to commit.

It does not run for:

- boundary-null attempts;
- same-owner attempts;
- immutable-recipient attempts;
- invalid proposals;
- constraint rejections;
- Metropolis or Hastings rejections;
- scheduler conflicts; or
- aborted transactions.

### Snapshot and writes

The effect reads the attempt's accepted precommit snapshot and staged transaction data. It may read
the losing/gaining owners, recipient/donor sites, cell types, direction identity, target MCS,
semantic proposal identity, and explicitly declared auxiliary state.

It may write only declared local state through the owning transaction machinery. Typical writes are
the recipient site, donor site, losing/gaining cell properties, or a bounded local auxiliary
record.

An accepted-copy effect:

- cannot change the completed acceptance decision;
- cannot submit another proposal;
- cannot run a field solver, lifecycle event, or host callback;
- cannot synchronize the device implicitly;
- cannot allocate dynamically on a qualified device path; and
- cannot publish if the ownership transaction aborts.

### Multiple effects

Multiple accepted-copy effects read one common precommit state. Their writes are combined under
declared state-family conflict laws. Tuple order is not priority.

A static conflicting write with no resolver fails model normalization. A dynamic conflict aborts
the attempt before ownership or auxiliary state commits and produces bounded diagnostics.

### Artistoo Act slice

The Wortel slice is expected to use:

```julia
PottsAttempts(on_accept = (activate_protrusion,))
```

The exact gained-site, lost-site, protrusion eligibility, maximum activity, and subsequent decay
law remain provisional until transcription of the pinned Artistoo release. This uncertainty affects
the model binding, not the accepted-copy transaction boundary.

## Lifecycle Ordering

The existing lifecycle contract remains authoritative.

The `PreLifecycleSnapshot` is taken after:

- every Potts attempt for the target MCS;
- all accepted-copy commits;
- every declared post-attempt auxiliary phase; and
- all required derived-state repair from those phases.

Lifecycle triggers read that common snapshot. Lifecycle effects plan, resolve, validate, and commit
under the existing closed transaction-category ordering.

Newly created or retired cell identities do not participate in earlier phases of the same target
MCS. Process-specific lifecycle policies determine the state of new cells after lifecycle commit
and before the next target MCS.

## Observation Ordering

`ObservationPhase` is the ordinary completed-MCS observation boundary after lifecycle commit.
Existing SciML saving and callback relative order remains unchanged.

A model MAY declare an explicitly named intermediate diagnostic observation attached to one phase.
Such an observation:

- identifies the exact phase snapshot;
- reports any synchronization and transfer;
- cannot masquerade as ordinary `saveat` at the completed MCS;
- cannot mutate scientific state;
- has a separate schema and fingerprint; and
- cannot serve as an exact checkpoint.

A transformation that clones a snapshot and runs source-specific annealing or analysis is an
`ObservationTransform`, not a hidden second Potts stage. Whether the Graner--Glazier two-step
annealing is such a transform or continuing trajectory dynamics remains a source-record blocker.

## StagedProtocol

### Ranges

A `StagedProtocol` contains named `ProtocolStage` values over explicit target-MCS ranges:

```julia
protocol = StagedProtocol(
    ProtocolStage(:relax; mcs = MCSRange(1, 119)),
    ProtocolStage(:initial_adhesion; mcs = MCSRange(120, 209)),
    ProtocolStage(:switch_calibration; mcs = MCSRange(210, 210)),
    ProtocolStage(:stimulated; mcs = MCSRange(211, 500)),
)
```

Ranges are inclusive. They MUST:

- use positive integer MCS values;
- be nonempty;
- not overlap;
- cover every MCS in the problem time span through an explicit stage or explicit default; and
- remain independent of tuple ordering.

Normalization canonicalizes stages by numerical start and rejects ambiguous or conflicting ranges.
Canonicalization does not change user-declared boundaries.

### Selection

The stage for target MCS `m` is selected before the first plan phase for `m` and remains fixed until
that MCS completes or fails.

The stage-local clock starts at one for the first target MCS in the range. Both target MCS and
stage-local clock are available to qualified scheduled laws.

### Scheduled parameters

`ScheduledParameter` is immutable piecewise model data:

```julia
focal_strength = ScheduledParameter(
    :focal_strength,
    protocol;
    relax = 0.0f0,
    initial_adhesion = 20.0f0,
    switch_calibration = scanned_strength,
    stimulated = scanned_strength,
)
```

It is not a mutable `ModelParameter`. Its complete stage/value table is part of normalized model
meaning. Every covered stage has exactly one compatible value.

Components and processes read the value selected for the target MCS. A value change is visible from
the first phase of the new stage unless the source requires a separately named in-MCS update phase.
Wang uses the latter rule: the scheduled value is an input to its ten-MCS focal-retuning phase,
while Potts reads the previously published per-relationship payload. Thus MCS 120 Potts reads 0,
MCS 210 Potts reads 20, and MCS 211 is the first Potts step to read the scanned payload.

### Process activation

An invocation MAY declare `active = During(...)`. Disabled invocations perform no reads, writes,
RNG draws, solver advances, or diagnostics other than bounded inactive accounting.

Activation is determined from the selected protocol stage, not from runtime declaration order or an
arbitrary predicate. State-dependent conditions belong to triggers or process eligibility laws.

## Continuous Clocks

Public Potts time remains integer MCS. A continuous process references a `ContinuousClock`:

```julia
physical_time = ContinuousClock(
    :physical_time;
    per_mcs = 30.0f0,
    unit = :second,
)
```

The clock declares:

- stable identity;
- positive finite continuous interval per MCS;
- semantic unit metadata;
- numerical type and conversion policy; and
- origin if it differs from zero.

`OneMCS()` and `HalfMCS()` are exact rational multiples of the process's clock interval. They do not
alter the count of Potts attempts or public MCS values.

An explicit `ContinuousInterval(value, unit)` MUST be compatible with the process clock. Floating
conversion follows the model numerical policy and is materialized in inspection.

Each continuous process records its own semantic continuous time. The following invariant holds at
every completed MCS:

```text
process_time =
    initial_process_time + sum(successfully published advance intervals)
```

An inactive or failed advance contributes no published interval.

## Failure Semantics

### Phase failure

If a phase fails validation or execution:

- none of that phase's writes publish;
- later phases do not run;
- target MCS does not complete;
- `integrator.t` remains the previous completed MCS;
- the integrator enters a terminal failed state;
- a structured failure identifies target MCS, protocol stage, phase, process, backend, and cause;
  and
- `solve!` returns the applicable unsuccessful SciML return code.

Earlier phases of the failed target MCS may already have published internally. They are not an
observable completed-MCS state, cannot be saved as an ordinary solution point, and cannot be
captured as a stable checkpoint.

The failed integrator cannot continue. Recovery uses a previous completed-MCS checkpoint or a new
problem. A future whole-MCS rollback facility would require its own memory, performance, and
atomicity contract.

### Potts-stage failure

An algorithm failure retains its accepted terminal semantics. No post-attempt phase or lifecycle
work runs, and public time does not advance.

### Observation failure

Failure while producing required completed-MCS observation or persistence output prevents the MCS
from being published as completed when that output is part of the problem's required execution
contract. Only an explicitly declared `BestEffortTelemetry` sink may be nonfatal. It cannot contain
required solution saving, checkpoint publication, paper evidence, or state used by later execution,
and its failure is recorded in diagnostics. Every other observation sink is required and fatal.

## Persistence

The accepted persistence boundary remains a fully completed MCS. A stable checkpoint is captured
only after `ObservationPhase` and completed-MCS invariant validation.

The checkpoint records or identifies:

- expanded plan identity and versions;
- completed protocol stage and stage-local clock;
- every process contract version;
- continuous-clock identities and process times;
- all authoritative coupled state;
- lifecycle and observation state required for continuation; and
- the algorithm and ordinary Phase 13 checkpoint data.

No pending phase write set, in-flight solver advance, accepted-copy effect, Potts attempt, lifecycle
plan, or incomplete observation becomes a stable checkpoint.

Derivable stage identity and clock values are recorded and verified on restore rather than silently
trusted.

## Backend and Synchronization

Every process declares whether its snapshot, computation, writes, and diagnostics are:

- backend resident;
- host synchronized;
- host only; or
- unsupported.

Plan compilation computes the union of required synchronization boundaries and reports it before
execution.

A host process in an otherwise device-resident plan is permitted only through an explicitly
synchronized mode. It reports:

- state transferred;
- transfer direction and volume;
- synchronization points;
- whether device workspaces are invalidated or reconstructed; and
- performance and backend-claim consequences.

A ModelingToolkit-authored process has no automatic GPU claim. Backend qualification applies to the
compiled process and full plan path.

## Inspection

`explain(model)` and `explain(prob)` show:

- canonical plan order;
- protocol ranges and scheduled values;
- per-phase read/write sets;
- accepted-copy effects;
- continuous clocks and materialized intervals;
- active/inactive stage restrictions;
- lifecycle and observation positions;
- synchronization boundaries;
- persistence payload requirements;
- algorithm requirements; and
- unsupported backend reasons.

The report MUST make simultaneous versus sequential phases visually distinguishable.

## Conformance

Before acceptance, the contract requires:

1. exact phase-order tests over hand-derived state transitions;
2. declaration-order permutation tests within simultaneous phases;
3. read/write conflict and dependency-cycle rejection fixtures;
4. accepted, rejected, null, conflict, and aborted-copy effect truth tables;
5. protocol range, gap, overlap, boundary, and stage-local-clock tests;
6. continuous-clock interval and conversion tests;
7. lifecycle snapshot-order tests;
8. observation and SciML callback-order tests;
9. terminal failure tests for every phase category;
10. completed-MCS checkpoint/restart tests at every protocol boundary;
11. an external downstream process fixture using only public protocols;
12. sequential CPU reference plus backend-resident Metal and ROCm execution through every complete
    release vertical slice, including all Wang field, ODE, history, relationship, plan,
    observation, and persistence capabilities; and
13. backend preflight tests that reject every unqualified process/backend combination before
    execution.

## Closed Surface Decisions

- `Phase` reuses the existing PottsToolkit phase identity and ordering concept; Phase 14 does not
  export a competing coupling-specific phase type.
- One immutable process declaration may be invoked in more than one phase. Each invocation has a
  distinct semantic identity derived from process identity, phase identity, and explicit invocation
  label. Continuous intervals for the same process cannot overlap, and its completed clock must
  equal the plan-implied endpoint.
- `AcceptedCopyUpdate` targets one or more declared `SiteProperty` instances at transaction-local
  gained or lost sites. Wang additionally requires a distinct typed accepted-copy relationship
  effect that emits bounded focal-topology requests and commits them atomically with ownership.
  This does not authorize arbitrary cell, field, lifecycle, solver, or observation mutation inside
  Potts evaluation; each admitted state family has its own read/write, capacity, conflict, and
  backend contract.
- Only `BestEffortTelemetry` may use nonfatal observation failure, under the restrictions above.

The remaining open items are implementation or source-transcription closures rather than
architectural choices:

- executable CPU/Metal/ROCm lowering of the accepted Wang CompuCell3D order and boundary fixtures;
- CompuCell3D attempt-budget accounting for the Wang source profile; and
- whether Graner--Glazier observation annealing mutates the continuing source trajectory.
