# Semantic-Preserving Consolidation Owner Interview

Status: Complete; all ten recommendations accepted

Date: 2026-07-28

Decision authority: Decision 0041

Normative contract:
[`../../spec/semantic-preserving-consolidation-contract.md`](../../spec/semantic-preserving-consolidation-contract.md)

Qualification ledger:
[`../../spec/semantic-preserving-consolidation-qualification-v1.toml`](../../spec/semantic-preserving-consolidation-qualification-v1.toml)

## Purpose

This interview freezes the owner choices required to consolidate the Potts package family without
adding or removing functionality. It follows the qualified ProcessBigraphs 0.5.0 internal-beta
closure and precedes every consolidation implementation change.

The owner expects:

- a more DRY codebase;
- consolidated library and test responsibilities;
- better naming;
- removal of development-phase naming from the living architecture; and
- no functional gain or loss.

## Research basis

The interview was prepared from:

- the exact ProcessBigraphs 0.5.0 closure head
  `d2f4d40e78fb68ee20da483d9784b55d25bf6147`;
- the Phase 16 closure audit and evidence manifest;
- current package source, include, export, test, integration, and checker organization;
- the repository architecture, open-protocol, metaprogramming, JuliaGPU, and performance
  standards;
- accepted Decisions 0028, 0031, 0034, and 0036--0040;
- Julia Pkg compatibility behavior for pre-1.0 versions; and
- Julia `Project.toml` version guidance.

The structural audit measured 388 tracked Julia files, 87 phase-named Julia files, 22
ProcessBigraph quality scripts totaling 4,692 lines, and major source responsibility clusters in
ProcessBigraphs composition/persistence and CorePotts continuous/relationship implementation.

Julia Pkg treats patch releases within a nonzero pre-1.0 minor line as compatible and different
minor lines as potentially incompatible. Therefore, retaining the complete `0.5.0` behavior
through compatibility aliases supports a `0.5.1` consolidation attestation. An unavoidable
breaking rename requires stopping for a separate `0.6.0` decision.

Primary versioning sources reviewed:

- <https://pkgdocs.julialang.org/v1.9/compatibility/>
- <https://pkgdocs.julialang.org/v1/toml-files/>

## Round 1: scope, naming, and history

### Decision 1: repository-wide scope

**Recommendation:** Consolidate ProcessBigraphs, CorePotts, PottsToolkit, MakiePotts, tests,
integration, documentation, and quality tooling. Execute dependency-first, stabilizing
ProcessBigraphs before downstream consumers.

**Owner answer:** Accepted.

### Decision 2: public milestone names

**Recommendation:** Introduce canonical domain-oriented names. Retain exported historical names as
deprecated compatibility aliases for the remainder of the unpublished internal-beta cycle.
Exclude aliases from primary docs and examples. Require a separate API decision for removal.

**Owner answer:** Accepted.

### Decision 3: historical evidence

**Recommendation:** Preserve phase-named evidence, hashes, paths, protocol identifiers, and
attestation records exactly. Index them as historical authority without allowing them to dictate
living source, test, CI, or documentation names.

**Owner answer:** Accepted.

## Round 2: tooling, files, and DRY boundaries

### Decision 4: quality tooling

**Recommendation:** CI invokes one stable ProcessBigraph quality runner. Internally, retain at most
five focused components for architecture, current contracts, evidence, documentation, and
performance. Historical reproduction scripts are archived rather than active lifecycle
authorities.

**Owner answer:** Accepted.

### Decision 5: file responsibility

**Recommendation:** A production or test file exceeding 1,000 nonblank, noncomment lines triggers
mandatory responsibility review. Exceeding the threshold requires a waiver showing why a split
would reduce clarity. Responsibility, not line count, is the governing rule.

**Owner answer:** Accepted.

### Decision 6: DRY versus evidence independence

**Recommendation:** Eliminate accidental production and fixture duplication. Keep independent
oracles, the independent custom adapter, reference implementations, and qualified backend kernels
separate wherever shared decisive logic could produce the same wrong result. Classify every
intentional duplicate.

**Owner answer:** Accepted.

## Round 3: requalification, API, versioning, and roadmap

### Decision 7: hardware requalification

**Recommendation:** Rerun trusted CPU, Metal, and ROCm qualification for every exact-source claim
whose implementation or transitive qualified source changes. Retain unaffected evidence only
through a checked source-impact map.

**Owner answer:** Accepted.

### Decision 8: API and identity delta

**Recommendation:** Permit only enumerated canonical-name additions and historical compatibility
aliases. Add no capability, constructor family, backend, option, algorithm, or scientific claim.
Preserve fingerprints, current checkpoint bytes, traces, error codes, and qualified behavior.

**Owner answer:** Accepted.

### Decision 9: final version

**Recommendation:** Target ProcessBigraphs `0.5.1` when compatibility aliases preserve `0.5.0`
behavior. If any required rename cannot preserve compatibility, stop and request a separately
approved `0.6.0` breaking-change decision. Do not choose a minor bump merely because the
consolidation is large.

**Owner answer:** Accepted.

### Decision 10: roadmap boundary

**Recommendation:** Implement no deferred roadmap functionality during consolidation. Record
discoveries in a later opportunity register. Redesign the roadmap only after exact-head
consolidation qualification.

**Owner answer:** Accepted.

## Consistency resolutions

The accepted choices imply:

- “remove phase-based names” means remove them from the living architecture, with explicit
  historical, serialized-identity, and temporary API-compatibility exceptions;
- “DRY tests” does not permit coupling production and independent expected-value logic;
- “no functionality change” includes supported rejections, errors, persistence, identity,
  replay, backends, and performance budgets, not only successful numerical outputs;
- `0.5.1` is conditional on backward compatibility and is not an unconditional target; and
- source-only refactoring may still require hardware requalification because existing evidence is
  content-addressed.

## Final disposition

All ten recommendations are accepted. The consolidation contract is normative at version 1.0.0.
The qualification ledger entered `accepted_not_started` when the interview closed.

The `baseline_freeze` gate subsequently qualified on 2026-07-28. The next allowed action is the
`naming_and_archive` gate. No future-roadmap implementation or package-version change is
authorized before full consolidation qualification.
