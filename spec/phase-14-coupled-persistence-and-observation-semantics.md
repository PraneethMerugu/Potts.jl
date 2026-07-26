# Phase 14 Coupled Persistence and Paper Observation Semantics

Status: Superseded by Decision 0031; retained as historical design and prototype evidence

GPU promotion note: Decision 0032 supersedes any CPU-only or optional-GPU promotion language in
this historical document; stable Phase 14 execution requires qualified Metal and ROCm paths.

Implementation maturity: Specified only

Date: 2026-07-24

Authority note: Observation is one kernel contract. Persistence, checkpoint extensions,
fingerprints, and reports are derived projections of the
[Phase 14 Single Semantic Kernel](phase-14-semantic-kernel.md), not separately authored model
semantics.

## Purpose

This document defines exact-continuation persistence for Phase 14 auxiliary state and the observation
contract used by close published-model reproductions. It extends the accepted
[Persistence](persistence.md) and
[Randomness and Reproducibility](randomness-and-reproducibility.md) contracts without changing the
frozen `CanonicalCheckpoint` v1 schema.

## Persistence Compatibility Decision

The concrete Phase 13 `CanonicalCheckpoint` v1 has no versioned extension slot. Adding fields would
change its type, canonical digest, storage payload, HDF5/Zarr layout, and uncoupled bytes. Phase 14
therefore introduces an additive envelope:

```julia
CoupledCheckpoint(
    base::CanonicalCheckpoint,
    extension::CoupledCheckpointExtension,
)
```

The base is the ordinary v1 checkpoint captured at the same completed MCS. Its bytes and checksum
are exactly those produced for the Potts state by the frozen implementation. The extension contains
only additive authoritative state and identities. `CoupledCheckpoint` has its own schema and
checksum and does not masquerade as `CanonicalCheckpoint` v1.

For an uncoupled Phase 13 integrator:

- `capture_checkpoint` returns the same `CanonicalCheckpoint` type;
- canonical bytes, checksums, storage groups, restore, and import are unchanged;
- no empty coupled envelope is inserted; and
- every frozen persistence and fingerprint fixture remains byte-identical.

For an integrator with any coupled authoritative state, `capture_checkpoint` returns a
`CoupledCheckpoint`. Dispatch remains through the same public operation. Code that explicitly
requires `CanonicalCheckpoint` continues to accept uncoupled checkpoints and rejects the distinct
coupled record rather than silently losing auxiliary state.

## Capture Boundary

Stable coupled capture is permitted only:

- after finalized MCS `0` initialization; or
- after `ObservationPhase` has completed and the positive integer MCS is published.

There is no mid-phase or mid-MCS stable checkpoint. A failed target MCS cannot be checkpointed.
Transient phase snapshots, pending relationship transactions, field solver workspaces, staged
lifecycle plans, pending accepted-copy effects, and observation transform workspaces are not stable
checkpoint state.

Every authoritative process clock, field time, stage position, schedule state, and synchronization
epoch must agree with the completed MCS. Capture validates this cross-family invariant before
producing either record.

## Coupled Envelope Schema

### Version and canonical header

The initial envelope uses independent constants:

```julia
COUPLED_CHECKPOINT_SCHEMA_VERSION = v"1.0.0"
COUPLED_EXTENSION_BLOCK_VERSION = v"1.0.0"
```

The envelope header contains:

- coupled schema version and completeness marker;
- completed MCS and semantic phase;
- base checkpoint checksum;
- coupled model fingerprint;
- coupled state-schema fingerprint;
- canonical ordered extension-block directory;
- exact-continuation profile additions;
- initial coupled-state fingerprint;
- ancestry envelope checksum;
- coupled-state fingerprint;
- warnings; and
- envelope checksum.

The envelope MCS and base MCS must match. The envelope checksum covers the base checksum, header, and
all material extension blocks. The base checksum remains independently valid.

### Typed extension blocks

Each block has:

- stable state-family identity and instance identity;
- block contract name and version;
- scalar/index/schema metadata;
- canonical dimensions or capacities;
- authoritative payload;
- semantic time or generation metadata;
- block checksum; and
- required/optional compatibility disposition.

The first required block families are:

```text
site-property
cell-history
relationship-set
evolving-field
global-property
membrane-property
delay-state
cell-dynamics
field-dynamics
continuous-system
continuous-event
delayed-event-queue
protocol-position
observation-schedule
extension-defined
```

Blocks are ordered by canonical family identity and stable instance identity, never declaration
order or container iteration. Two blocks with the same canonical identity are invalid.

An extension-defined authoritative state family may register a block only with a durable semantic
serializer, validator, restore method, version, and compatibility policy. A Julia object graph,
function closure, device array layout, solver object, or package `Serialization` payload is not a
canonical block.

### Family payload requirements

`site-property` stores the complete logical site array, site schema, initialization/ownership policy
identities, and semantic epoch.

`cell-history` stores canonical capacity-indexed samples, head/fill state, endpoint cell generations,
sampling phase, and last completed sample MCS.

`relationship-set` stores canonical endpoint identities and generations, directedness, payloads,
scientific bounds, realized capacity, and graph schema. Derived adjacency indexes are omitted and
rebuilt.

`evolving-field` stores logical field values in canonical axis order, field descriptor identity,
semantic time, precision, and any authoritative accumulated forcing. Physical ping-pong/staging
buffers, active-buffer indices whose normalization cannot change future arithmetic, internal
substep counters, per-site exchange contributions, and reduction scratch are workspace and are
omitted. Wang has no authoritative accumulated forcing: its Medium reservoir is a post-substep
constraint and its uptake is an immediate atomic field mutation.

`cell-dynamics` and `field-dynamics` store process clocks and only the numerical stepping state
required by the claimed continuation profile. The stable fixed-step profile has no hidden solver
object. Experimental adaptive state must have a qualified semantic serializer before it can claim
exact continuation.

`global-property` stores typed mutable model-level values. `membrane-property` stores
generation-aware material-coordinate state and remapping metadata. `delay-state` stores canonical
logical histories and interpolation state.

`continuous-system` stores clocks and every future-relevant fixed/adaptive, DAE, stochastic, or
root-location value required by the continuation profile. `continuous-event` stores trigger memory,
latches, and cascade state. `delayed-event-queue` stores future event identity, domain
instance/generation, trigger and execution times, priority, stored trigger-time values, and semantic
RNG coordinates in canonical order.

`protocol-position` stores stage identity, stage-local clock, scheduled-parameter selection,
completed plan identity, global/MCS/system clocks, multirate schedule identity, last completed
timeline position, and process synchronization epochs. Values that are derivable from MCS are still
stored and cross-validated to detect incompatible protocol changes. No in-flight timeline is stable.

`observation-schedule` stores each stateful observation identity and its last successfully published
sample coordinate. Output paths and visualization preferences are excluded.

## Fingerprints and Compatibility

The coupled scientific fingerprint includes:

- the unchanged base model fingerprint;
- all Phase 14 state, process, plan, clock, protocol, lifecycle, and observation identities;
- explicit spatial roles and source attempt algorithm;
- extension semantic versions and RNG namespaces;
- authoring-law canonical identities, including ModelingToolkit adapter records; and
- initial authoritative coupled-state fingerprint.

The execution fingerprint additionally includes numerical method, dependency, generated-law,
backend runtime, scalar/index, and other identities required by the requested continuation profile.

Exact restore requires:

- valid base and envelope integrity;
- exact base-model and coupled-model fingerprints;
- compatible base and extension schema versions;
- every required extension block exactly once;
- no unknown required block;
- matching algorithm, RNG, numerical, dependency, and backend continuation identities;
- matching realized capacities where exact storage order matters; and
- successful reconstruction and validation of all omitted derived state.

An unknown optional block may be ignored only if its block contract proves that it is observational
and cannot influence future scientific execution. Authoritative state is always required.

## Capture, Restore, and Logical Import

`capture_checkpoint(coupled_integrator)` logically:

1. synchronizes at the completed-MCS observation boundary;
2. validates plan, clock, stage, field, graph, property, and schedule invariants;
3. captures and validates the ordinary base checkpoint;
4. captures authoritative blocks in canonical order;
5. computes block, state, initial-state, ancestry, and envelope checksums;
6. validates the complete in-memory envelope; and
7. returns an immutable `CoupledCheckpoint`.

`restore_checkpoint(coupled_checkpoint, problem)` validates everything before mutating a live
integrator, reconstructs derived indexes and workspaces, installs base and extension state
atomically, then reruns cross-family invariants.

`import_checkpoint` may map a logically compatible coupled record to a different execution profile
only through explicit family-specific mappings. It reports every changed identity and achieved
weaker guarantee. Missing a required target family, dropping authoritative source state, changing
field geometry without an explicit conservative mapping, or remapping live relationship generations
is incompatible.

A `CanonicalCheckpoint` cannot exactly restore a model that requires coupled authoritative state.
A `CoupledCheckpoint` may import only its base into an uncoupled model through an explicit
base-state-only operation whose report states that coupled state was discarded; this is never exact
continuation.

## Storage Adapters

Memory, HDF5, and Zarr encode one logical envelope. The physical representation uses:

- the existing untouched base checkpoint payload;
- one coupled header;
- one canonical group/table per extension block;
- explicit completeness markers;
- per-block and envelope checksums; and
- transactional publication.

Writers stage the base and every block, validate the complete record, and publish the envelope
completion marker last. Readers bound dimensions and capacities before allocation where supported,
reject incomplete or duplicate blocks, validate nested checksums, and do not mutate an integrator
during load.

The envelope schema is independent of file format and backend array layout. Chunking, compression,
device transfer, and cache representation are not scientific identity, though they may appear in
storage diagnostics.

## Observation Contract

### Phase observation

The reusable declaration is:

```julia
PhaseObservation(
    :sorting_index,
    observable;
    phase = CompletedMCS(),
    schedule = EveryMCS(),
    schema = SortingIndexRecordV1(),
)
```

An observation identity includes observable law/version, snapshot phase, schedule, output schema,
aggregation and numerical policy, and any transform. Declaration order and output path do not affect
scientific identity.

`CompletedMCS()` is the default and observes state after coupled phases and lifecycle. A named
intermediate phase is permitted only when that phase declares an immutable observable snapshot and
the source model requires it. An observation cannot acquire an unrestricted live integrator.

Observation computation is read-only with respect to the continuing trajectory. It may materialize
host data at the declared observation boundary and reports that synchronization. Failure to compute
or durably publish a required paper observation makes the target MCS failed before it becomes a
stable checkpoint boundary.

Only `BestEffortTelemetry` may be nonfatal. It cannot perform solution saving, checkpoint
publication, paper evidence, or any write read by later execution. Its failure is retained in
diagnostics.

### Schedules and restart

A stateful observation records its last successfully published sample coordinate in the checkpoint.
On restore:

- an already published sample is not duplicated;
- the next due sample is not skipped;
- exactly-once refers to the logical run record, not arbitrary external filesystem delivery; and
- publication identity includes run identity, observation identity, MCS, phase, and schema version.

Storage adapters SHOULD use idempotent content-addressed records or transactional keys. Reusing an
output directory for a different model/run identity fails rather than interleaving data.

Pure observations whose due coordinates are wholly derivable may omit mutable schedule state, but
restore validates the derivation against the completed MCS.

## Observation Transforms

`ObservationTransform` runs a read-only derived experiment on a private logical copy:

```julia
ObservationTransform(
    :zero_temperature_anneal,
    input = CompletedMCS(),
    transform = PottsRelaxation(
        algorithm = BudgetedSequentialCPM(AttemptsPerSite(1)),
        acceptance = ZeroTemperature(),
        steps = 5,
    ),
)
```

The transform:

- cannot mutate the continuing integrator;
- receives an explicitly identified immutable source snapshot;
- owns independent semantic RNG namespaces and an explicit algorithm/time interpretation;
- declares bounded work, failure, and backend behavior;
- produces an immutable observation record; and
- is fingerprinted with its input phase, algorithm, parameters, steps, and version.

Transform time is not public simulation MCS and does not trigger lifecycle, field, cell, or protocol
phases unless the transform explicitly defines a separate derived simulation. Its results are
analysis products, never continuation checkpoints for the main trajectory.

If source review establishes that an apparent annealing step mutates the continuing experiment, it
must instead be represented by a source protocol and separately versioned attempt semantics.

## Paper Analysis Schemas

Each published model owns a versioned analysis schema beside its model source. The schema declares:

- record identity and version;
- exact input phase and schedule;
- axes, units, labels, missing/empty behavior, and numerical type;
- ensemble/run/seed coordinates;
- raw primitive observables;
- derived statistics and estimator definitions;
- binning, smoothing, normalization, and confidence-interval laws;
- expected source-data or digitized-data identities;
- exclusions and stopping rules;
- output serialization; and
- validation target and tolerance provenance.

Reusable primitives such as contact matrices, segregation indices, centroid tracks, sprout graph
morphology, activity distributions, field mass, and relationship statistics belong in
PottsToolkit only after their general meaning is specified. Figure-specific combinations remain in
the paper example and do not become stable core API by accident.

Classifiers or learned transforms require architecture, weights checksum, preprocessing,
dependency/runtime identity, and an interpretable replacement plan where feasible. An opaque pickle
or undocumented external service is insufficient for archival evidence.

### Evidence levels

Every paper result labels its evidence:

- `law_fixture` — exact hand-worked or analytic contract check;
- `foreign_microfixture` — comparison with source simulator or source output on a minimal state;
- `paper_statistical` — ensemble comparison to published/source data;
- `qualitative_only` — visual or behavioral resemblance without quantitative qualification; or
- `blocked_source_ambiguity` — exact target cannot be selected from available evidence.

No plot or tutorial upgrades an implementation/backend contract. Paper evidence names the exact
model, algorithm, backend, package versions, seed set, analysis schema, and source record.

## Failure Semantics

Capture or restore fails structurally for schema mismatch, duplicate/missing required blocks,
checksum failure, inconsistent MCS, stale generations, invalid field clocks, incompatible capacities,
or unsupported dependencies. A failed restore leaves the destination unmodified.

Required observation failure is terminal for the target MCS. A transform failure does not mutate the
trajectory but prevents publication of that required observation. Retrying an idempotent observation
uses the same snapshot identity and semantic draws.

## Required Conformance Evidence

- byte-identical uncoupled `CanonicalCheckpoint` and storage regression fixtures;
- coupled envelope capture at MCS `0` and completed positive MCS only;
- canonical block ordering and declaration-order invariance;
- nested checksum, truncation, duplication, unknown-version, and missing-block failures;
- exact restart for site state, histories, relationships, fields, fixed-step dynamics, protocol,
  lifecycle, and observation schedules;
- atomic failed restore and transactional Memory/HDF5/Zarr publication;
- explicit logical import with downgraded reports;
- completed and named-intermediate phase observation fixtures;
- interruption before/after publication with no duplicate or skipped logical samples;
- transform isolation proving unchanged continuing state and RNG streams;
- hand-worked reusable analysis primitives;
- schema-validated per-paper records and content-addressed outputs; and
- complete provenance replay for every paper evidence claim.

## Acceptance Boundary

D9 may accept the envelope and observation protocols independently of any paper qualification. D11
accepts each paper's concrete schemas, target values, tolerances, ensembles, ambiguity dispositions,
and stopping rules. No source-specific uncertainty is allowed to leak into the reusable envelope
semantics.
