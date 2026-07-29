# Decision 0041: Semantic-Preserving Repository Consolidation

Status: Accepted architecture and qualification policy; local reconciliation candidate implemented, exact-head platform qualification pending

Date: 2026-07-28

## Context

ProcessBigraphs 0.5.0 is a qualified unpublished internal beta. Its behavioral evidence is strong,
but the package family retains development scaffolding accumulated across prior phases:
phase-organized tests and quality scripts, milestone-coded identifiers, repeated checker
infrastructure, overlapping persistence and composition responsibilities, and several large
CorePotts scientific responsibility clusters.

The owner requires a more DRY, consistently named, domain-oriented codebase without adding or
removing functionality. A cleanup based only on line count or existing test success would be
unsafe: independent oracles deliberately duplicate some behavior, public phase-coded names are
observable API, checkpoint and fingerprint identities are frozen, and trusted device evidence is
content-addressed.

The completed ten-decision owner interview resolves the required scope, compatibility, evidence,
tooling, file, DRY, hardware, API, versioning, and roadmap questions.

## Decision

### Repository-wide, dependency-first consolidation

Consolidation covers ProcessBigraphs, CorePotts, PottsToolkit, MakiePotts, tests, integration,
documentation, and quality tooling. It proceeds from ProcessBigraphs foundations through CorePotts
and downstream frontends.

### Zero unapproved functional delta

The consolidation adds and removes no feature, algorithm, backend, semantic option, scientific
claim, or supported/rejected envelope. It preserves public behavior, ownership, fingerprints,
serialization, checkpoints, traces, semantic RNG, failures, replay, backend qualification, and
performance budgets.

### Domain-oriented living architecture

Living source, tests, fixtures, CI, and primary documentation use domain names rather than project
milestones. Historical evidence and frozen serialized/protocol identities remain exact and are
indexed as history.

Exported milestone names receive canonical domain replacements and remain as deprecated
compatibility aliases during the unpublished internal-beta cycle. Alias removal requires a
separate versioned API decision.

### One authority and bounded DRY

Every accepted concept has one production authority. Accidental production and fixture
duplication is removed. Independent oracles, independent adapters, reference implementations, and
backend kernels remain separate when sharing decisive logic would weaken qualification.

### Stable tooling and responsibility boundaries

ProcessBigraph quality tooling converges to one ordinary CI runner and at most five focused
components. Historical lifecycle checkers become reproduction/archive tools.

A source or test file exceeding 1,000 nonblank, noncomment lines requires responsibility review
and a waiver if retained. The threshold does not justify artificial abstractions.

### Requalification and version

Every invalidated exact-source CPU, Metal, or ROCm claim is rerun. Unaffected evidence is retained
only through a checked impact map.

Backward-compatible consolidation targets ProcessBigraphs `0.5.1`. If canonical naming cannot
preserve `0.5.0` behavior through aliases, work stops for a separate `0.6.0` breaking-change
decision.

### Roadmap boundary

No deferred roadmap feature is implemented during consolidation. Roadmap redesign begins only
after exact-head consolidation qualification.

## Consequences

- The qualified baseline consists of exact inventories, equivalence fixtures, performance
  observations, duplicate classifications, and hardware impact maps. The consolidated production
  candidate is now implemented against that frozen authority.
- Historical evidence remains legible but no longer shapes living naming or CI topology.
- Test assertion and file counts may change, but the complete behavior matrix may not shrink.
- Some apparent duplication will remain because it is part of the proof structure.
- Large implementation changes are split into dependency-ordered, independently reviewable
  structure or deduplication passes.
- Source movement may require trusted hardware reruns even when behavior is unchanged.
- ProcessBigraphs remains unpublished throughout consolidation.
- Later scientific and ecosystem work remains deferred.

## Qualification progression

The `baseline_freeze` gate qualified on 2026-07-28. Its authority is
[`semantic-preserving-consolidation-baseline-freeze.md`](../../design/audits/semantic-preserving-consolidation-baseline-freeze.md)
and the machine-readable
[`baseline-freeze-v1.toml`](../../design/evidence/consolidation-baseline/baseline-freeze-v1.toml).

Naming, archive, test-harness, ProcessBigraphs, CorePotts, and frontend gates pass locally. The
candidate is in final reconciliation; exact-head CPU-platform, trusted-device, documentation-smoke,
and aggregate CI evidence remain required before closure.

## Alternatives considered

### ProcessBigraphs-only cleanup

Rejected because phase naming, fixture duplication, and large responsibility clusters span the
whole package family and its integration/evidence tooling.

### Delete all historical phase names

Rejected because evidence, serialized identities, content hashes, and public compatibility would
be damaged.

### Preserve all names indefinitely

Rejected because development chronology would remain part of the living architecture.

### Maximal DRY through shared oracle logic

Rejected because production and comparator paths could then share the same defect.

### Immediate `0.6.0`

Rejected as the default because compatibility aliases permit a backward-compatible `0.5.1`
consolidation. A minor bump remains the required stop condition for an unavoidable breaking
change.

### Consolidate while beginning later-roadmap work

Rejected because functional changes would make equivalence impossible to prove.

## Required conformance evidence

Closure requires every row in
`spec/semantic-preserving-consolidation-qualification-v1.toml` to be qualified, including:

- exact-head baseline and API inventories;
- complete behavior-coverage reconciliation;
- canonical bytes, fingerprints, traces, checkpoints, and model outputs;
- checked domain naming and historical allowlists;
- one-authority and duplication audits;
- domain-organized test and quality tooling;
- package and integration equivalence;
- frozen performance and allocation budgets;
- CPU and every invalidated trusted hardware qualification;
- documentation and limitation reconciliation; and
- exact-head zero-functional-delta attestation.
