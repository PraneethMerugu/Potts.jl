# Decision 0032: GPU-Native Promotion for Phase 14

Status: Accepted

Date: 2026-07-24

## Context

Decision 0031 required a CPU reference before a new Phase 14 semantic family could stabilize, but
allowed Metal and ROCm to remain Unsupported indefinitely. The first Wortel slice demonstrated that
this policy makes it easy to prove semantics while leaving auxiliary state, accepted-copy effects,
site dynamics, and coupled execution on a host-only path.

That is insufficient for the intended library. Phase 14 introduces paper-scale fields, per-cell
dynamics, histories, relationships, degradation, events, mappings, and observations. If stable
versions of those capabilities can silently remain CPU-only, models assembled from the new API
cannot inherit the project’s existing first-class GPU character.

## Decision

Every Phase 14 execution capability promoted to stable or used by a release published model MUST
have:

1. an ordinary CPU reference implementation;
2. backend-resident production execution on Metal and ROCm;
3. no scalar host iteration, hidden host fallback, or per-MCS state transfer during unobserved
   stepping;
4. device-adaptable authoritative state, workspaces, queues, and solver storage;
5. explicit synchronization only at declared observation, checkpoint, or user-requested access
   boundaries;
6. backend preflight derived from the canonical semantic model;
7. same-backend replay and restart evidence;
8. CPU/Metal/ROCm numerical or statistical conformance appropriate to the law; and
9. real-hardware correctness, residency, allocation, transfer, and performance evidence.

This policy covers the stable subset of state, process, plan, lifecycle, observation primitives,
spatial roles, and Potts algorithm identities. A capability may remain Experimental and
unsupported, but it cannot be called stable, production implemented, or release ready until both
Metal and ROCm gates pass.

### Meaning of GPU native

The simulation data plane is GPU native when all future-relevant state remains on the selected
device and every state transition is performed by backend-native kernels or qualified device
primitives. Kernel launch orchestration may remain on the host; that is the normal JuliaGPU control
plane and does not constitute fallback.

Host work is permitted only for:

- model construction, validation, lowering, compilation, and adapter translation before launch;
- required observations at their fingerprinted synchronization boundary;
- checkpoint serialization and restore at a completed-MCS boundary;
- explicit user requests for host snapshots; and
- downstream analysis after declared output publication.

Those operations may transfer only their declared payload. They may not become an implicit
per-process or per-MCS execution path.

### Backend and precision scope

Metal and ROCm remain the required first-class GPU targets under Decision 0013. CUDA remains
deferred.

Portable Phase 14 GPU qualification uses `Float32` unless a backend/law pair separately qualifies
another precision. Paper-faithful CPU `Float64` runs and GPU `Float32` runs are distinct numerical
profiles. Metal’s lack of general `Float64` support must never be hidden by conversion or host
fallback.

### Vertical-slice order

The revised proving order is:

1. close Wortel Act on Metal and ROCm;
2. implement and close Wang on CPU, Metal, and ROCm;
3. implement and close one field model on CPU, Metal, and ROCm; and
4. close the remaining selected-model capabilities on all three required backends.

Wang does not open until the Wortel GPU gate passes. A later slice may reuse already qualified
storage, scheduling, observation, and persistence infrastructure, but it must qualify every new
law/storage pair it introduces.

## Consequences

- The existing Wortel CPU slice remains valid reference evidence but is no longer sufficient to
  open Wang.
- `BudgetedSequentialCPM`, accepted-copy site state, Act energy, decay, observation, and
  continuation must receive device-native implementations and real-hardware evidence.
- Bounded device-native representations are required for histories, relationship graphs, delayed
  queues, lifecycle requests, and field/exchange accumulators.
- Stable observations may reduce on device and transfer a bounded result at their declared
  boundary; checkpoints may transfer authoritative state only at the stable boundary.
- Advanced adaptive, root-event, DAE, SDE, reaction, jump, and hybrid families remain
  Experimental. This decision does not force their implementation, but it applies if they are
  later promoted.
- No Phase 13 meaning or qualification record changes.

## Required Evidence

- device adaptation and storage-tree validation for every authoritative state family;
- CPU/device primitive truth tables and hand-worked fixtures;
- device code inspection for required kernels;
- zero steady-state allocation and zero hidden transfer/synchronization during unobserved stepping;
- same-backend deterministic replay where the algorithm promises it;
- exact or tolerance-qualified checkpoint/restart continuation;
- CPU/Metal/ROCm cross-backend conformance with preregistered numerical/statistical tests;
- real-hardware Metal and ROCm CI artifacts with environment and device identity;
- paper-scale memory and performance measurements; and
- unchanged Phase 13 API, fingerprints, checkpoints, results, and backend evidence.
