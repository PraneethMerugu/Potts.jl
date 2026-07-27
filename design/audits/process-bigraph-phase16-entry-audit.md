# ProcessBigraphs Phase 16 Entry Audit

Status: Historical entry passed; Phase 16.A/B/D/E qualified, C hardware and F–I open

Date: 2026-07-27

## Entry result

The pre-implementation architecture is complete:

- the owner accepted all 481 interview decisions;
- Decision 0039 records the consolidated authority and scope;
- the normative specification defines engine, field, structure, adapter, persistence, failure,
  observation, migration, model, backend, and evidence semantics;
- the entry contract freezes subgates A–I and explicit exclusions;
- qualification, backend, migration, and model-scope registries are machine-readable; and
- the entry checker validates internal consistency while the closure checker remains honestly open.

The completed Phase 15.C internal alpha and frozen Phase 13/G3-B evidence satisfy entry. G4 is not
an external entry condition: it is the mandatory Phase 16.C gate.

## Claim discipline

At entry:

- no Phase 16 runtime feature is implemented or qualified;
- every required qualification row is only `specified`;
- ProcessBigraphs remains version `0.4.0`;
- `internal_beta = false`;
- `public_release = false`; and
- Merks and CNV have only bounded runnable targets, not reproduction claims.

## Required first action

Phase 16.A must add actual compatible dependency bounds and freeze the bounded API before Phase
16.B runtime implementation. The entry checker passing authorizes this work; it does not authorize
marking any implementation row qualified.

## Current amendment

Phase 16.A/B/D/E have since qualified. Phase 16.C remains independently open for trusted
exact-head Metal/ROCm artifacts. The first 16.F implementation at commit `7217f9b` is retained as
an unqualified prototype, not admitted evidence. The
[16.F solver-integration consolidation](process-bigraph-phase16f-solver-integration-consolidation-research.md)
requires a real injected SciML algorithm, standard solver interfaces, numerical replay by default,
an external-style independent custom fixture, and restored API containment before F01–F03 can
qualify. Phase 16.G/H must wait for that qualification.

## Risks already controlled

- one scheduler/lifecycle/publication authority is explicit;
- solver and CPM performance ownership is preserved;
- arbitrary solver support is an open protocol with per-envelope qualification;
- device and transfer claims are matrix-scoped;
- dynamic orchestration and high-volume Potts topology are separated;
- checkpoint conversion is non-destructive and versioned;
- G4 cannot be skipped;
- full model analyses and universal GPU claims are excluded; and
- final closure requires real Metal/ROCm and exact-tree evidence.
