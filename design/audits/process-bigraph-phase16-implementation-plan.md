# ProcessBigraphs Phase 16 Implementation Plan

Status: Accepted plan; implementation not started

Date: 2026-07-27

## Outcome

Phase 16 will produce one unpublished `0.5.0` internal beta in nine bounded subgates. G4 is
implemented and qualified inside 16.C. The generic engine/field protocol precedes both its native
device qualification and dynamic hierarchy; Merks and CNV then exercise the common path.

## Work sequence

### 16.A — freeze entry and dependencies

- Keep the entry packet and checker green.
- Add `AlgebraicRewriting.jl` as a direct dependency with an exact compatible range.
- Define SciML integration through a package extension or adapter package; keep core solver-neutral.
- Freeze the smallest public/internal-beta API allowlist and generate limitations from registries.
- Add a closure checker that reports open until all ledger rows qualify.

### 16.B — engine and field vertical slice

- Implement declaration, instance, operation, completion, candidate, status, diagnostic, and
  continuation protocols.
- Implement logical field descriptors and a small CPU Cartesian reference path.
- Close one complete transaction: exact interval, immutable input, staged field candidate,
  validation, publication, required observation, checkpoint, restore, and injected failure.
- Prove sampling, deposition, exchange, conservation, boundaries, and named split behavior.

### 16.C and 16.D — parallel independent gates

16.C:

- Move the native field implementation behind the protocol.
- Qualify CPU, then real Metal and ROCm.
- Enforce residency, transfer, synchronization, allocation, and performance guards.

16.D:

- Implement add/remove/binary divide/move/rewire using bounded AlgebraicRewriting rules.
- Build the independent Julia structural oracle and exhaustive small fixtures.
- Add compiled CorePotts-rule equivalence, conflict, capacity, fuzz, failure, and restart evidence.

### 16.E — adapter and first cutover

- Implement typed CorePotts requests and opaque engine candidates.
- Add Phase 16 logical checkpointing and non-destructive legacy conversion.
- Select the smallest useful field/lifecycle slice, run old/new differential execution, then
  remove the old production authority for that slice.

### 16.F — solver plurality

- Implement and qualify the CPU SciML field adapter.
- Implement a deliberately independent custom CPU adapter.
- Compare all three adapters on the same analytic/manufactured problems and failure/restart cases.

### 16.G — Merks

- Assemble the corrected 2006 source contract from generic components.
- Pass mechanism microfixtures, canonical startup, bounded schedule, native/SciML execution,
  observation, checkpoint, restart, and rollback.
- Label the result only “runnable source-bounded reimplementation.”

### 16.H — CNV

- Build generated reduced fixtures for field, phenotype, lifecycle, relationship, and degradation
  transitions.
- Assemble the full 40 by 40 by 35 configuration and pass startup plus bounded execution.
- Keep Text S6 fetching in a separate checksum-verified lane.

### 16.I — reconcile and attest

- Require every ledger row to be qualified.
- Run clean package and integration tests, full static guards, real hardware, frozen performance
  workloads, and documentation checks.
- Produce exact-head content-addressed candidate evidence.
- Verify the merged tree, then land only metadata/version/attestation changes for internal beta.

## Parallelism and joins

16.B is the first code join. After it passes, 16.C and 16.D may run independently. 16.E joins both
where a dynamic field slice needs them. 16.F requires 16.B but may overlap late 16.C/16.D work.
16.G requires B, C CPU/native correctness, E's adapter path, and F. 16.H additionally requires D.
16.I joins everything.

No branch's evidence can compensate for another branch. Hardware unavailability leaves only the
relevant hardware gate open and does not prevent useful CPU or structural progress.

## Estimated difficulty

Overall difficulty is 9/10. The planning estimate is 18–28 engineer-weeks, or approximately 13–20
calendar weeks with disciplined overlap and dependable Metal/ROCm access. The largest risk is CNV's
combined 3D fields, lifecycle, relationships, degradation, and persistence; the next is hardware
qualification availability.

## First implementation task

Begin with 16.A dependency bounds and the bounded protocol/API skeleton. Do not begin with a model
loop. The first executable proof should be the 16.B CPU field microfixture completing the entire
transaction and restart path.

