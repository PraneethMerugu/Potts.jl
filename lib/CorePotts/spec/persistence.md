# Snapshots, Checkpoints, Restore, and Logical Storage

Status: Accepted

## Purpose

Persistence preserves scientific meaning without treating a backend cache, Julia object graph, or
storage format as the model. This document defines observable snapshots, exact-continuation
checkpoints, logical state import, integrity, model reconstruction, and the common storage contract
used by memory, HDF5, and Zarr.

## Persistence Boundary

A stable checkpoint is created only after a completed positive integer MCS has published its final
state and diagnostics. MCS `0` MAY be checkpointed after initialization finalization has completed
and every state invariant passes.

Stable persistence does not capture an in-flight proposal, checkerboard color, lottery round,
mechanical half-step, lifecycle plan, kernel, command queue, or partially committed transaction.
Mid-MCS checkpointing is outside the paper contract. Observation or persistence that materializes
device state synchronizes explicitly at the named MCS boundary.

This boundary makes execution workspaces, temporary queues, kernel scheduling state, and replaceable
caches reconstructible machinery rather than persistent scientific state.

## Snapshot and Checkpoint Types

An **analysis snapshot** is an immutable logical view or immutable handle to observable scientific
state at one named MCS. It contains only the fields selected by its observation contract and MUST NOT
claim exact continuation merely because its storage resembles a checkpoint.

An **exact checkpoint** is an immutable logical record containing or identifying everything required
to continue under one declared compatibility profile. Its completeness is a validated contract, not
a user-facing Boolean assertion.

Snapshots and checkpoints MAY share canonical arrays, encoding helpers, and storage adapters. They
remain distinct public semantic types and operations.

## Canonical Logical Checkpoint

The canonical checkpoint schema is independent of CPU, Metal, ROCm, array storage layout, memory
address, workgroup configuration, and file format. It contains or identifies at least:

- checkpoint schema version and completeness profile;
- current completed integer MCS and accepted semantic phase;
- canonical lattice ownership, active identities, reusable identities, and slot generations;
- complete authoritative biological and auxiliary state;
- any derived state that cannot be deterministically reconstructed under the declared profile;
- model, property-schema, topology, initialization, and initial-state fingerprints;
- algorithm identity, guarantee profile, and any algorithm-defined semantic counter needed after an
  integer-MCS boundary;
- realized master seed, RNG contract version, component namespaces, and stochastic contract
  versions;
- numerical mode, scalar and index types, backend/device restrictions, and continuation profile;
- Potts.jl, Julia, extension, and dependency identities required by that profile;
- checkpoint ancestry, creation MCS, integrity metadata, and provenance warnings; and
- canonical checksums for the record and its material payloads.

Transient workspaces, reusable scratch arrays, compiled kernels, command queues, device pointers,
thread state, backend handles, observation buffers, and reconstructible caches MUST NOT be required
to interpret a stable checkpoint. On restore they are rebuilt through the normal validation,
compilation, and initialization boundary.

A derived cache MAY be stored as an optimization, but it is non-authoritative: restore verifies it
or reconstructs it from authoritative state. Omitting such a cache cannot weaken continuation.

## Model Reconstruction

Every checkpoint records a canonical model and schema fingerprint. The minimum stable restore form
accepts an explicitly supplied problem or model, validates its fingerprint and compatibility, and
then restores the checkpoint state.

A checkpoint MAY additionally contain a versioned declarative reconstruction payload when every
model component, extension identity, topology, schedule, policy, and parameter has a qualified
semantic serialization. Such a payload permits standalone reconstruction only under its declared
package and contract requirements.

Arbitrary Julia object graphs, closures, generated executable code, method tables, and raw Julia
`Serialization` output are not durable paper formats. A custom extension that lacks semantic
serialization remains usable with explicit compatible-model restore; it is not silently omitted or
reconstructed from a type name alone.

## Exact Resume and Logical Import

Exact resume is permitted only when the checkpoint's compatibility predicate and trajectory profile
are satisfied by the requested model, algorithm, RNG contract, numerical mode, packages, and
execution environment. A stronger exactness claim across devices or backends requires explicit
conformance evidence for that profile.

Otherwise, a user MAY explicitly request a **logical state import** when the canonical state is
semantically compatible. Import:

1. verifies record integrity and logical schema compatibility;
2. validates or explicitly maps model and property identities;
3. reconstructs derived state, caches, compiled descriptors, and workspaces;
4. validates every state invariant before execution;
5. records checkpoint ancestry and the changed execution profile; and
6. reports the achieved, generally weaker reproducibility guarantee.

Changing backend, device constraint, numerical mode, algorithm, or an exact-profile dependency MUST
NOT silently convert import into exact continuation. An incompatible exact resume fails before
mutating a live integrator.

## Transactional Write and Defensive Load

A writer first creates an explicitly incomplete staged record. It writes canonical data and
metadata, computes integrity checks, validates the staged record, and only then publishes it as
complete. Readers reject incomplete or unverifiable records.

The physical publication mechanism is format-specific. An HDF5 extension may validate a temporary
file before atomic replacement. A Zarr extension may validate a staging store before publishing a
completion record or atomically switching a local reference. Remote atomicity is not implied by the
Phase 8 local-storage contract.

Loading performs bounded structural checks before allocating large payloads where the storage API
permits. It validates dimensions, types, capacities, checksums, versions, identities, and requested
compatibility before altering simulation state. Corruption, truncation, unknown required fields,
capacity mismatch, or unsupported contracts produce structured errors.

## Storage Interface

CorePotts owns one small logical snapshot/checkpoint reader-writer protocol. Ordinary methods operate
on canonical logical records. Optional formats integrate through Julia package extensions and weak
dependencies rather than a runtime storage registry.

The required paper storage implementations are:

- immutable in-memory logical records;
- HDF5; and
- Zarr.

HDF5 and Zarr encode the same versioned logical field meanings, canonical identities, array element
types, tables, metadata, and checksums. Format-specific chunking, compression, grouping, and file
layout are implementation choices recorded where relevant; they MUST NOT change the reconstructed
logical record.

A reusable conformance suite compares each adapter against the in-memory canonical representation.
An additional future format defines methods on the same logical interface and does not receive
access to simulator internals or permission to reinterpret scientific fields.

## Minimal Phase 8 Surface

Phase 8 implements:

- immutable snapshot and checkpoint values;
- completed-MCS capture;
- compatible exact resume and explicit logical import;
- canonical fingerprints and checksums;
- in-memory, HDF5, and Zarr round-trip; and
- construction-time diagnostics and provenance required by the paper.

It does not implement mid-MCS capture, arbitrary Julia serialization, remote checkpoint services,
automatic environment installation, a universal artifact manager, every output format, or unproven
cross-backend bitwise continuation.

## Required Conformance Evidence

- Snapshot omission tests proving it cannot be mistaken for a checkpoint.
- Exact uninterrupted-versus-restored continuation for every claimed algorithm profile.
- MCS `0` and completed-positive-MCS capture; rejection of in-flight capture.
- Full biological, auxiliary, generation, RNG, schema, and semantic-counter round-trip.
- Cache/workspace omission followed by deterministic reconstruction and invariant validation.
- Compatible-model restore, model-fingerprint rejection, and qualified standalone declarative
  reconstruction.
- Explicit logical import with ancestry and downgraded reproducibility report.
- Incomplete, truncated, corrupted, unknown-version, wrong-capacity, and checksum-failure fixtures.
- Canonical logical equality across in-memory, HDF5, and Zarr adapters.
- Transactional publication failure injection proving no incomplete artifact appears complete.
- Package-extension loading tests without optional storage dependencies in the CorePotts runtime.
- Save/load latency, peak memory, allocation, transfer, size, and compression measurements for paper
  workloads.
