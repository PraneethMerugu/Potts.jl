# ProcessBigraphs Phase 16.I Reconciliation Audit

Status: qualified unpublished internal beta

Date: 2026-07-28

Package version: `0.5.0`

## Outcome

All implementation subgates from 16.A through 16.HC are qualified. Phase 16.C is backed by one
content-addressed source identity across CPU, trusted real Metal, and trusted real ROCm execution.
Phase 16.I reconciles those results without adding a new scheduler, numerical solver, runtime
mechanism, scientific model, or backend claim.

The exact-head candidate was generated from a clean commit after the complete CI,
independent-package, integration, hardware, documentation, static-guard, and frozen-performance
gates passed. Its content-addressed artifact and performance report are admitted by the Phase 16
evidence manifest. The final promotion changes only metadata, compatibility declarations and
tracked manifests, registries, documentation status, evidence, and lifecycle-aware attestation
checkers. `internal_beta = true`; `public_release = false`.

## Documentation and claim reconciliation

- The user-facing internal-beta guide explains ordinary Julia authoring, qualified scope,
  stability, and explicit exclusions.
- The adapter guide freezes the when/why versus how ownership boundary, exact-target lifecycle,
  SciML extension policy, and independent-adapter requirements.
- The failure and persistence guide covers every transactional stage, settled checkpoints,
  engine continuation, invalidation, retry, and non-destructive legacy conversion.
- The generated capability page derives backend envelopes, API families, model bounds, open rows,
  and exclusions directly from the normative TOML registries.
- README, internal contracts, roadmap, entry contract, backend matrix, API registry, migration
  registry, model scope, qualification ledger, and local/root parity registries use one maturity
  vocabulary.

## Package and compatibility reconciliation

CI tests ProcessBigraphs, CorePotts, PottsToolkit, and integration independently on Linux x86_64
and macOS ARM64. The package matrix also develops each package into a clean temporary project,
instantiates exact compatibility bounds, loads it, exercises public behavior, and then runs its
independent package suite.

ProcessBigraphs core retains only ACSets, AlgebraicRewriting, Catlab, and SHA as hard dependencies.
CommonSolve and SciMLBase remain weak extension triggers. CorePotts depends on ProcessBigraphs;
ProcessBigraphs does not depend on CorePotts, PottsToolkit, a concrete SciML algorithm, Metal, or
AMDGPU.

## Performance reconciliation

The candidate reruns the frozen Phase 16.HC stage-separated benchmark. Construction, validation,
lowering, compilation, initialization, and warm execution are reported separately. The semantic
and direct-IR routes must compile to identical plans; warm time and allocation ratios must remain
within the frozen workload-specific budgets. No fastest-runtime claim is made.

The real-hardware evidence separately guards the native field against hidden host fallback,
staging transfer, warm device allocation, and publication allocation. Construction and requested
observation transfers remain explicitly counted.

## Exact-tree protocol

1. Commit the candidate implementation, documentation, generated pages, CI wiring, and checkers
   with version `0.4.0` and `internal_beta = false`.
2. Run every required CI job and the trusted Phase 16.C hardware workflow.
3. Generate a content-addressed candidate artifact from a clean checkout. Record commit, tree,
   base, merge base, prospective merge tree, resolution hashes, environment, evidence hashes,
   performance, commands, and limitations.
4. Require candidate-tree identity with the prospective merge tree.
5. Land only metadata/version/evidence/attestation changes to set version `0.5.0`,
   `internal_beta = true`, and `public_release = false`.

Complete Process-Bigraph parity, public release, Dagger/distributed execution, CUDA, universal
solver GPU support, full Merks/CNV analyses, broad scientific ecosystems, and whole-cell
qualification remain open.
