# ProcessBigraphs Phase 16 Implementation Plan

Status: In progress; Phase 16.A/B/D/E/F/G/H/HC qualified, C hardware and I open

Date: 2026-07-28

## Outcome

Phase 16 will produce one unpublished `0.5.0` internal beta in ten bounded subgates. G4 is
absorbed and must qualify inside 16.C. The generic engine/field protocol precedes both its native
device qualification and dynamic hierarchy; Merks and CNV then exercise the common path. Phase
16.HC hardens ordinary Julia authoring and migrates those models before final reconciliation.

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

Qualified at implementation commit `9f9daf1` with the
[solver-plurality audit](process-bigraph-phase16f-solver-plurality-audit.md) and
[evidence manifest](../evidence/process-bigraph-phase16f-evidence-v1.toml).

Complete a mandatory 16.F0 repair before qualification:

- remove the prototype `P16FixedEuler`, custom SciML solution, and
  `solve(::SciMLBase.ODEProblem, ...)` implementation;
- make the declaration accept an explicit real solver algorithm and bounded canonical options;
- construct/remake a real SciML problem from published state, advance with the solver's
  exact-target interface, and use standard return/error handling;
- default to reconstructing solver state on every invocation with numerical replay;
- move the independent custom adapter into an external-style conformance fixture with no SciML
  dependency or shared numerical helper;
- restore the admitted API boundary and keep concrete instances/candidates internal; and
- preserve all qualified A–E tests and evidence.

Then:

- qualify the CPU SciML field adapter using a concrete solver package in the test environment;
- qualify the deliberately independent custom CPU adapter;
- compare native, SciML, and custom paths against analytic/manufactured solutions, refinement and
  convergence expectations, declared tolerances, negative capabilities, failure, and restart;
- record algorithm, options, package resolution, continuation, replay, and split accuracy in
  fingerprints and evidence.

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

### 16.HC — high-level composition hardening

Specification and API freeze precede implementation:

- implement a transactional ordinary Julia `compose` builder that returns an immutable semantic
  `CompositeModel`;
- add typed store, port, component, parameter, observable, mount, and runtime-instance handles;
- use shared-store junctions, explicit schedules, lexical hierarchy, exports, and declared
  structural templates;
- implement structured diagnostics, deterministic lowering, a complete author-origin map, and
  layered fingerprints;
- retain the solver-neutral core and qualify applicable SciML/CommonSolve behavior through the
  existing weak-dependency extension;
- freeze direct-IR Merks, CNV, and bounded behavioral fixtures as migration oracles, then migrate
  the smallest fixtures before the full scientific assemblies;
- enforce a path-and-purpose raw-IR allowlist;
- qualify documentation, doctests, Aqua, clean environments, compatibility, and stage-separated
  authoring/runtime benchmarks; and
- preserve all applicable qualified Phase 15 and Phase 16 evidence.

The uncommitted `scheduled`/`reactive`/`@compose` implementation is a research spike, not
qualification evidence. A full macro DSL is not required. Implementation and migration begin only
after explicit owner authorization.

### 16.I — reconcile and attest

- Require Phase 16.HC to be qualified.
- Require every ledger row to be qualified.
- Run clean package and integration tests, full static guards, real hardware, frozen performance
  workloads, and documentation checks.
- Produce exact-head content-addressed candidate evidence.
- Verify the merged tree, then land only metadata/version/attestation changes for internal beta.

## Parallelism and joins

16.B is the first code join. After it passes, 16.C and 16.D may run independently. 16.E joins both
where a dynamic field slice needs them. 16.F requires 16.B but may overlap unresolved 16.C
hardware work. 16.G requires B, C CPU/native correctness, E's adapter path, and qualified F.
16.H additionally requires D and qualified F. 16.HC follows G/H but can be specified while the
independent 16.C hardware lane remains open. 16.I joins everything and cannot attest before HC and
the hardware rows qualify.

No branch's evidence can compensate for another branch. Hardware unavailability leaves only the
relevant hardware gate open and does not prevent useful CPU or structural progress.

## Estimated difficulty

Overall difficulty is 9/10. The planning estimate is 18–28 engineer-weeks, or approximately 13–20
calendar weeks with disciplined overlap and dependable Metal/ROCm access. The largest risk is CNV's
combined 3D fields, lifecycle, relationships, degradation, and persistence; the next is hardware
qualification availability.

## Current implementation task

Complete the Phase 16.HC specification amendment. Do not begin its implementation or scientific
migration until the owner explicitly authorizes code work. Keep Phase 16.C real-hardware evidence
independently open and do not broaden either bounded model claim into full publication analysis or
quantitative reproduction.
