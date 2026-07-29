# Semantic-preserving consolidation closure audit

Status: Consolidation qualified; 37 of 37 contract rows closed

Date: 2026-07-29

Qualified baseline: `d2f4d40e78fb68ee20da483d9784b55d25bf6147`

Consolidated candidate: `3e4946d9aac8ed4b1fadd1455a148b27620fdad6`

Candidate tree: `6a74b82ffbdfb92a501323d377c976a495e40904`

Tested pull-request merge: `55449c6c8d12de5dc7c7963c0d7e947019dcb92a`

Machine-readable evidence:
[`exact-head-v1.toml`](../evidence/consolidation-qualified/exact-head-v1.toml)

## Outcome

The dependency-ordered consolidation is qualified and closed. The tested pull-request merge has
the same tree as the candidate, so qualification exercised exactly the repository content
described here. All 37 contract rows pass.

ProcessBigraphs remains version `0.5.1`, an unpublished internal beta. This work changes repository
organization, canonical spelling, compatibility placement, test and tooling ownership, and
duplicated implementation structure. It does not add or remove an accepted feature, algorithm,
backend, scientific claim, numerical default, or supported envelope.

## Architecture and DRY result

- Eight responsibility aggregators expose smaller domain-oriented implementation files.
- Two files over the 1,000-line review threshold remain under explicit responsibility waivers.
- The exact clone inventory classifies 37 retained clusters and has zero unresolved candidates.
- One-way package dependencies and one production authority per accepted concept are preserved.
- Independent specification oracles, custom adapters, reference implementations, compatibility
  codecs, and backend kernels remain separate where sharing decisive logic would weaken evidence.
- ProcessBigraphs owns when and why computation occurs; injected solvers and CPM kernels continue
  to own how their authorized heavy computation occurs.

The candidate changes 296 files from the production-consolidation start, with 19,541 insertions and
15,297 deletions. It contains 125 Julia path renames, 47 Julia additions, and no Julia deletions.
All 159 baseline test-file obligations are reconciled, including explicit mappings for 84 moved
test paths.

## Naming, API, and compatibility

Living source, tests, workflows, benchmarks, and primary documentation use domain-oriented names.
Milestone-coded values remain only at indexed historical, frozen-protocol, evidence, or explicit
compatibility boundaries.

All 1,348 baseline exports remain. Fourteen canonical domain names accompany fourteen retained
internal-beta compatibility aliases, and there are zero unapproved exports. Alias removal remains
a separate versioned API decision.

## Behavior, identity, and persistence

The candidate passed the complete local reconciliation:

- ProcessBigraphs: 1,228 assertions;
- CorePotts: 3,868 assertions;
- PottsToolkit: 732 assertions;
- MakiePotts: 505 assertions;
- CPU cross-package integration: 4,793 assertions;
- benchmark contracts: 71 assertions; and
- the stdlib-isolated ProcessBigraph specification oracle: 22 exact rows, 6 unit assertions, and
  10 mutation-sensitivity assertions.

Frozen semantic-model bytes, checkpoint bytes, fingerprints, replay behavior, and checkpoint
roundtrips remain exact. The frozen artifact itself retains its exact SHA-256; regenerated
semantic identity is portable across the recorded capture architecture.

## Performance, platforms, and hardware

The candidate has passed clean-install smokes on Linux x86_64, macOS aarch64, and Windows x86_64
with Julia 1.12.6, followed by the strict documentation build. The exact artifacts are archived
beside the machine-readable manifest.

Trusted Metal and ROCm runners passed tiled execution, device invariants, the Wortel model
GPU-native slice, device-code capture, and the native-field numerical, allocation, residency, and
transfer checks. Both native-field artifacts report zero maximum absolute error, zero warm device
allocations, zero publication host allocations, and no hidden host fallback. CUDA remains
explicitly outside the accepted qualification boundary.

Exact-head Linux x86_64 and macOS aarch64 CPU suites passed independently on Julia 1.12.6. The
authoring performance job also passed every frozen construction, validation, lowering,
compilation, initialization, steady-runtime, and allocation budget. Across 9 repetitions and 128
events, semantic authoring had a 0.051910816-second median versus 0.051804277 seconds for direct IR,
a ratio of 1.0020565676459494; both paths allocated 19,402,672 bytes, a ratio of 1.0.

## Qualification repairs

Two qualification-infrastructure defects were exposed and repaired transparently:

1. Candidate `5191cfa73bb1e1842003eb71b8277b92fad86138` reached a fresh runner without first
   instantiating the ProcessBigraphs qualification environment. Commit
   `57456a11d59674a35130ac0120c4b4edf1d71cd8` added that explicit setup step.
2. The next run compared the frozen capture machine's `aarch64` provenance as semantic identity
   on an `x86_64` runner. Commit `3e4946d9aac8ed4b1fadd1455a148b27620fdad6`
   continues to verify the frozen artifact's exact SHA-256 and normalizes only the regenerated
   capture-architecture field before semantic comparison.

Neither repair changes runtime or scientific source, tests, dependency inputs, numerical
semantics, or the claim boundary.

## Zero-functional-delta boundary

The closure changes after candidate `3e4946d9aac8ed4b1fadd1455a148b27620fdad6` are limited to
this audit, qualification ledgers and decisions, documentation-quality evidence routing, and
content-addressed exact-head artifacts. They do not modify runtime source, scientific models,
tests or fixtures, workflows, dependency resolution inputs, algorithms, backend kernels, or
numerical semantics.

## Closure disposition

All 37 ledger rows are qualified. CI run `30421465406`, documentation run `30421465423`, and GPU
validation run `30421465343` concluded successfully. The required CI aggregate is job
`90483841103`; exact-head identity is job `90482397886`. Artifact identifiers, hashes, every CI job
identifier and conclusion, dependency-resolution inputs, content trees, API disposition, and
limitations are recorded in the machine-readable evidence.

The metadata-only closure preserves the qualified scientific candidate exactly. Consolidation is
complete; later roadmap redesign or scientific work requires its own explicit contract and claim
boundary.
