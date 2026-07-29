# Semantic-preserving consolidation candidate audit

Status: Local reconciliation candidate passes; exact-head platform qualification remains open

Date: 2026-07-28

Baseline: `d2f4d40e78fb68ee20da483d9784b55d25bf6147`

Candidate version: ProcessBigraphs `0.5.1`, unpublished internal beta

Machine-readable evidence:
[`local-reconciliation-v1.toml`](../evidence/consolidation-candidate/local-reconciliation-v1.toml)

## Outcome

The dependency-ordered consolidation implementation is complete locally. It changes organization,
canonical spelling, compatibility placement, test/tooling ownership, and duplicated implementation
structure without adding or removing an accepted feature, algorithm, backend, scientific claim, or
supported envelope.

The candidate is not yet consolidation-qualified. The repository contract requires committed
exact-head CI and trusted hardware evidence, which cannot be represented by an uncommitted local
tree.

## Consolidated architecture

- ProcessBigraphs composition, structural transactions, and persistence now expose small
  responsibility aggregators backed by domain-oriented implementation files.
- CorePotts continuous dynamics, dynamic state, polarity, and relationships are split by scientific
  responsibility. Only two source files exceed the 1,000-line review threshold, and both carry
  explicit waivers.
- PottsToolkit authoring normalization and rules are split into declaration, validation,
  fingerprint, reporting, evaluation, and macro responsibilities.
- Package edges remain `ProcessBigraphs <- CorePotts <- PottsToolkit`; MakiePotts and optional
  extensions retain their lower-layer dependencies.
- ProcessBigraphs still owns when and why computation occurs. Solvers and CPM kernels retain how
  authorized heavy computation occurs.

## Naming, API, and compatibility

Active paths, tests, CI jobs, benchmark entrypoints, and primary documentation use durable domain
names. The strengthened naming checker scans all living source, tests, documentation, workflows,
benchmarks, and scripts.

Milestone-coded values survive only as:

- compatibility aliases in dedicated compatibility authorities;
- serialized or evidence protocol identities;
- frozen benchmark record identities; or
- explicit consumers of indexed historical artifacts.

All 1,348 baseline exports remain. Fourteen approved canonical domain names accompany their
internal-beta compatibility aliases. No unrelated export was added. ProcessBigraphs advances from
the qualified `0.5.0` baseline to the backward-compatible `0.5.1` consolidation candidate.

## DRY and test reconciliation

The exact 16-line clone detector classifies 37 retained clusters and reports zero unresolved
production, test-fixture, or active-tooling candidates. Shared transaction commit logic, transition
CLI parsing, and parallel-algorithm replay assertions have one authority. Independent specification
oracles, custom adapters, backend realizations, legacy codecs, and bounded model specializations
remain separate where shared decisive logic would weaken evidence.

All 159 baseline test-file obligations map to surviving evidence; 84 moved paths have explicit
old-to-new mappings. Fixture and cross-implementation contract authorities are machine-readable.

## Local qualification

The final local candidate passed:

- ProcessBigraphs: 1,228 assertions;
- CorePotts: 3,868 assertions;
- PottsToolkit: 732 assertions;
- MakiePotts: 505 assertions;
- CPU cross-package integration: 4,793 assertions;
- benchmark contracts: 71 assertions;
- the independent ProcessBigraph specification oracle: 22 exact rows, 6 unit assertions, and 10
  mutation-sensitivity assertions;
- the frozen identity fixture, including semantic bytes, checkpoint bytes, fingerprints, and
  roundtrip equality;
- the authoring construction/lowering/runtime timing and allocation budgets;
- CPU and real-Metal native-field numerical, allocation, residency, and transfer checks;
- the macOS clean-install documentation smoke; and
- a complete local documentation build with doctests.

## Remaining closure work

Closure still requires a clean committed candidate, exact-head Linux x86_64 and macOS aarch64 CPU
attestations, trusted Metal and ROCm attestations, Linux and Windows clean-install documentation
smokes, and the required aggregate CI conclusion. The documentation quality checker intentionally
continues to reject the retained baseline platform-smoke artifacts until exact-head replacements
are supplied.

No roadmap redesign or new scientific work may begin until those rows are qualified and the final
zero-functional-delta attestation is recorded.
