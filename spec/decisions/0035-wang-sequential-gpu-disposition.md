# Decision 0035: Wang Sequential Reference and GPU Suitability Disposition

Status: Accepted

Current disposition: the Wang paper-faithful sequential CPU scientific result and the rejection of
an assembled Wang GPU claim remain accepted. G3/G4 routing, “current gate” language, and blanket
Metal-and-ROCm requirements below are historical and superseded for current work by
[Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md).

Date: 2026-07-26

## Context

The Wang paper model was reproduced as a source-faithful sequential CPU reference in G3-B. Its
Potts step performs one ordered stream of copy attempts, and the coupled model observes accepted
copies in that exact order. Running this unchanged process on a GPU preserves the reference
semantics but exposes essentially no parallel Potts work: one device work item executes the entire
attempt stream while numerous coupled phases add kernel-launch overhead.

Metal and ROCm execution experiments therefore measured the cost of placing a serial algorithm on
a device, not the quality of the reusable field, history, intracellular, relationship, or coupling
primitives. Promoting that assembly as a GPU target would turn algorithm mismatch into a permanent
release gate.

A checkerboard CPM could expose useful parallelism, but it is a different stochastic process. The
current checkerboard path also lacks equivalent moment-dependent coupling and deterministic
accepted-copy relationship conflict semantics. It cannot replace the paper-faithful Wang oracle
without a separately specified scientific profile.

## Decision

1. The paper-faithful Wang model remains a sequential CPU reference governed by the passed G3-B
   contract and attested evidence.
2. The assembled Wang model has no Metal or ROCm qualification claim. Its G3-C qualification
   harness, device-code capture, evidence ledger, CI jobs, and closure gate are retired.
3. G3-C is retired by owner disposition, not recorded as passed or failed. Experimental hardware
   output from the abandoned gate is not admissible Phase 14 closure evidence.
4. Generic Phase 14 state, process, field, ODE, history, relationship, observation, adaptation, and
   persistence primitives remain subject to CPU/Metal/ROCm qualification when promoted to stable.
   Their qualification uses focused microfixtures and algorithm-suitable vertical slices.
5. G4 is the current Potts gate. It must qualify the reusable field-model substrate on CPU, Metal,
   and ROCm without claiming that the assembled sequential Wang model is GPU native.
6. A future checkerboard Wang experiment, if pursued, must have its own algorithm identity,
   moment-tracking and relationship-conflict semantics, statistical registration, evidence, and
   documentation. It is not part of this decision and is not a paper-reproduction replacement.

This decision partially supersedes Decision 0032 only at the assembled-model boundary. Decision
0032 continues to govern stable reusable execution capabilities and vertical slices whose
algorithms are suitable for the required backends.

## Consequences

- The Wang scientific result remains the source-faithful sequential CPU implementation and its
  order, restart, failure-atomicity, and observation evidence.
- Backend preflight must reject an attempted assembled Wang GPU promotion before mutation.
- Metal and ROCm CI continue to qualify the existing Potts algorithms, Wortel slice, and future G4
  field capabilities.
- Phase 14 no longer spends release-gate time proving that a serial Potts algorithm is slow on a
  GPU.
- Removing the assembled gate does not permit host fallback or weaken GPU requirements for generic
  primitives that are promoted as stable.

## Required Conformance Evidence

- the G3-B attested CPU evidence remains content-addressed and passing;
- the canonical Wang fixture is CPU-qualified and fails closed under an alleged GPU backend;
- no Wang G3-C harness, profiling script, evidence ledger, workflow step, or completion claim
  remains;
- real-hardware GPU workflows retain Wortel and generic backend qualification; and
- G4 specifications retain CPU, Metal, and ROCm acceptance requirements.
