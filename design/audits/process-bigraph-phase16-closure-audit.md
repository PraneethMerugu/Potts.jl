# ProcessBigraphs Phase 16 Closure Audit

Status: qualified unpublished internal beta

Date: 2026-07-28

ProcessBigraphs version: `0.5.0`

## Outcome

Phase 16 closes the bounded internal-beta scope defined by Decisions 0039 and 0040. ProcessBigraphs
owns when and why computation occurs; optimized solver and CPM kernels retain control over how
authorized heavy computation occurs. The closed implementation includes the solver-neutral engine
protocol, transactional field publication, native CPU/Metal/ROCm Cartesian fields, dynamic
AlgebraicRewriting hierarchy, the CorePotts strangler adapter, logical checkpoint conversion, CPU
SciML and independent custom adapters, bounded runnable Merks and CNV assemblies, and the ordinary
Julia high-level authoring API.

All 38 qualification rows are `qualified`. This attestation promotes the package from the
qualified `0.4.0` candidate tree to unpublished `0.5.0` internal beta. It does not claim public
release, complete pinned parity, full Merks/CNV analyses, broad SciML ecosystem coverage,
distributed execution, CUDA, or whole-cell qualification.

## Exact-head candidate

The admitted candidate is commit
`6a8deb7886761ea7a4142f09a742cb66ebc1f3ee`, tree
`71597c3e206928c01eaf9fc7936243ad2f56d3cd`. Its prospective merge tree against base commit
`536ba7d29173bf619f82c58c64eb22ff965cbe75` is the same tree, proving that candidate content and
prospective merged content are identical.

The checked-in candidate is byte-for-byte the GitHub artifact. Its SHA-256 is
`7028751add514adb5613d53d115fe2125e26dc5fbe21932e5ee0675c454f02a7`. The complete frozen
performance report is also retained; its SHA-256 is
`050dc8965785e7a190909d62fd6222b766f5abc4221257501d0a6a6dd69dc0f0`.

The candidate records 19 tracked dependency-resolution inputs, 35 already-qualified rows, three
Phase 16.I rows at `oracle_passing`, and a clean exact-head tree. Its nine-repetition authoring
benchmark compiled the semantic and direct-IR routes to identical plans. The semantic route used
`1.0034816214967597×` the direct-IR median runtime and `1.0×` the allocations, passing every frozen
budget without making a fastest-runtime claim.

## CI qualification and retry

Required CI run
[`30381477071`](https://github.com/PraneethMerugu/Potts.jl/actions/runs/30381477071)
finished successfully on the exact candidate head. The Phase 16.I candidate job
`90396593892` generated the artifact on attempt 1.

The attempt-1 self-hosted macOS runner disconnected while its package test step was still marked
`in_progress`. GitHub recorded no failing step, produced no job log, and never started that job's
integration step. No source change was made. Attempt 2 reran the unchanged head: macOS ARM64 job
`90396590755` passed both independent packages and complete cross-package integration, and Required
job `90401767505` passed. Linux x86_64, all independent packages, all integration shards, Makie
rendering, project integrity, Phase 15.C oracle/candidate, and Phase 16.I candidate evidence were
also successful.

Trusted native-field hardware evidence remains independently anchored by GPU workflow run
`30360086075`, with exact-source CPU, real Metal, and real ROCm qualification and no hidden host
fallback.

## Metadata-only attestation boundary

The promotion changes package and compatibility metadata, tracked environment manifests,
registries, ledger status, generated and status documentation, evidence, and lifecycle-aware
integrity checkers. It does not change runtime source, scientific model source, tests, fixtures,
workflow logic, dependency sets, algorithms, backend kernels, or numerical semantics.

CorePotts and the integration environment widen their ProcessBigraphs compatibility from `0.4` to
`0.4, 0.5`; this admits the attested package without dropping compatibility with the qualified
internal alpha. Tracked manifests record the new path-package identity.

The machine-readable authority is the
[Phase 16.I evidence manifest](../evidence/process-bigraph-phase16i-evidence-v1.toml), bound to the
checked-in [candidate](../evidence/phase-16/phase16i-candidate.toml) and
[performance report](../evidence/phase-16/phase16i-authoring-performance.toml).

## Remaining boundary

Post-Phase-16 consolidation will be planned separately and must preserve this qualified semantic
surface unless a later specification explicitly changes it. Complete parity, public release,
full-source publication analyses, broad scientific ecosystems, alternate executors, and
whole-cell-style acceptance remain future decisions rather than implied internal-beta claims.
