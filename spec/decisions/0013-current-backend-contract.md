# Decision 0013: Current First-Class Backend Contract

Status: Accepted

Current disposition: the backend-neutral, fail-closed, and real-hardware principles remain active.
The blanket requirement that every phase or release claim pass both Metal and ROCm is superseded by
[Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md). G5H qualifies explicit capability
profiles using CPU reference evidence and at least one real GPU witness; unqualified vendors report
`Unsupported` without fallback.

Date: 2026-07-18

## Context

The project remains committed to hardware-agnostic design, but a scientific support claim requires
real-hardware conformance, numerical, synchronization, allocation, and performance evidence. The
project currently has reliable CPU, Apple Metal, and AMD ROCm validation capacity. Treating an
unavailable CUDA runner as a release requirement blocks honest qualification without improving the
architecture or the validated user experience.

## Decision

Until superseded by another accepted semantic decision, CPU, Apple Metal, and AMD ROCm are the only
first-class backends. CUDA is deferred and unqualified.

Backend capabilities distinguish runtime functionality from contract status. A functional but
deferred backend MUST fail during execution-plan preflight, before model state is adapted or a
scientific kernel is launched. CUDA extensions, environments, and guarded workflows MAY remain so
future qualification work does not require architectural reconstruction, but their presence MUST
NOT imply support.

Reinstating CUDA requires an explicit semantic decision plus current real-hardware evidence for the
same conformance, RNG, numerical, synchronization, allocation, and benchmark gates applied to the
other first-class backends.

## Consequences

- Phase and release gates require CPU, Metal, and ROCm evidence.
- CUDA results are experimental diagnostics and are excluded from public scientific and performance
  claims.
- Shared kernels and state representations remain backend-neutral; no first-class backend may
  become the semantic definition of an operation.
- Adding or removing a first-class backend is a reviewed contract change, not an incidental CI edit.

## Alternatives Considered

- Keep four first-class backends and leave Phase 5 indefinitely blocked on unavailable hardware.
- Remove CUDA code and environments entirely, increasing the cost of future reinstatement.
- Treat successful compilation as support, which is insufficient for a GPU scientific library.

## Required Conformance Evidence

- A typed preflight failure for deferred backends.
- Machine-readable capability reports that expose contract status separately from functionality.
- Real-hardware CPU, Metal, and ROCm results for every backend-scoped phase or release claim.
