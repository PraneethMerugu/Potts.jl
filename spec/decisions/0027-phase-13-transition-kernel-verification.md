# Decision 0027: Phase 13 Uses Transition Kernels to Characterize Algorithms

Status: Accepted

Date: 2026-07-22

## Context

`CheckerboardSweepCPM` has a normalized MCS and reproducible production implementation, but its
scheduled-without-replacement, snapshot, and color-pass dynamics are not ordinary sequential
with-replacement CPM kinetics. Aggregate ensemble agreement alone cannot identify which microscopic
transition probabilities change or whether equilibrium, kinetics, or both are affected.

Small CPM fixtures have finite enumerable state spaces. Their proposal, acceptance, scheduler, and
commit laws can therefore be assembled into complete transition kernels and compared with the
production implementation. This evidence is especially valuable before Phase 13 freezes public
algorithm guarantees.

## Decision

Phase 13 adds an independent small-state transition oracle and algorithm-characterization gate. It
constructs proposal/sub-round and normalized-MCS kernels, models scheduler phase explicitly,
validates sequential behavior, and characterizes the production checkerboard scheduler without
assuming equivalence in advance.

The accepted contract is
[Transition-Kernel Verification and Algorithm Characterization](../transition-kernel-verification.md).
The first implementation slice is frozen, discrete, and paper-core. It uses ordinary typed Julia,
sparse matrices, rational arithmetic where possible, bounded high precision otherwise, independent
replica sampling on CPU/Metal/ROCm, and larger ensemble corroboration.

Phase 13 implementation remains blocked behind Phase 12.CPU, remaining Phase 12 closure, and the
Phase 12.5 disposition. Lottery and any retained tiled algorithm later consume the same protocol but
do not block the first sequential--checkerboard characterization unless required by a paper claim.

## Consequences

- Checkerboard receives a scoped evidence label rather than an inherited or marketing guarantee.
- Microscopic transition differences can be connected to probability currents, relaxation, and
  observable drift or diffusion.
- Production algorithms remain free of oracle dependencies and instrumentation overhead.
- Algorithm-semantic changes invalidate affected evidence automatically.
- Exact tiny-state results are never extrapolated to realistic tissues without ensemble evidence.

## Alternatives Considered

- Use only emergent-model ensemble comparisons. Rejected because they can miss compensating local
  errors and do not explain a difference's mechanism.
- Treat checkerboard as an optimization of sequential execution. Rejected because its proposal
  schedule and snapshot law are scientifically observable.
- Require a symbolic closed form for every model. Rejected because high-precision sparse finite
  kernels provide auditable qualification without imposing symbolic infrastructure.
- Put the oracle in CorePotts production code. Rejected because exhaustive-state machinery is test
  and research infrastructure.

## Required Conformance Evidence

- One complete hand-auditable derivation reproduced by the generated oracle.
- Independent sequential kernel agreement and applicable equilibrium-law checks.
- Lifted-state production checkerboard kernels and sequential discrepancy reports.
- Adversarial-state fixtures and bounded parameter characterization.
- Independent-replica CPU, Metal, and ROCm empirical transition results.
- Larger ensemble corroboration for every realistic-model claim.

