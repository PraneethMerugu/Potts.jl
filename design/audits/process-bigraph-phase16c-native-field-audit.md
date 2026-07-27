# ProcessBigraphs Phase 16.C Native Field Audit

Status: Implementation candidate awaiting exact-head Metal and ROCm artifacts

Date: 2026-07-27

Authority: Decision 0039, absorbed G4, and the Phase 16 normative specification

## Production implementation

`CorePotts.NativeFieldEngine` is a solver-owned, KernelAbstractions-backed realization of the
Phase 16 field envelope. It is not the ProcessBigraphs adapter—that boundary is Phase 16.E.

The engine provides:

- Cartesian 2D and 3D scalar fields with anisotropic spacing;
- periodic, Dirichlet, zero-Neumann, mixed/Robin, and per-face combinations;
- Float32 device and Float64 CPU profiles;
- explicit-Euler diffusion, decay, and forcing with multidimensional stability preflight;
- engine-owned published, candidate, scratch, forcing, status, and failure buffers;
- staged asynchronous device launches and explicit semantic-boundary completion;
- atomic failure status with no partial publication;
- allocation-free, transfer-free, synchronization-free publication by buffer pointer swap; and
- exact integer target ticks and publication epochs.

CPU execution has an allocation-free specialized loop. Metal and ROCm use the identical generated
stencil through KernelAbstractions. Construction-time adaptation records all device allocations and
host-to-device transfers. Staging records no transfers or allocations. Completion transfers only
the two declared status scalars; observation transfers only the requested field payload.

## Oracles

The CPU test matrix includes:

- an independent anisotropic periodic finite-difference reference;
- 2D and 3D constant-state invariance;
- periodic, Dirichlet, zero-Neumann, mixed, and heterogeneous-face fixtures;
- periodic mass conservation and positivity;
- a periodic Fourier manufactured solution with 16-to-32 refinement;
- nonfinite and unstable-step atomic failure;
- zero warm staging and publication allocation; and
- every restart cut in a four-tick bounded trajectory.

`benchmark/phase16_native_field_qualification.jl` runs both 2D periodic and 3D heterogeneous-face
cases on CPU, Metal, or ROCm. It compares real-device output with the Float32 CPU reference and
records residency, transfers, allocations, launches, synchronization, exact target time, source
hash, runtime, architecture, and hardware identity.

## Current evidence boundary

The CPU oracle and a local real-Metal execution pass. The production candidate is wired into the
existing trusted self-hosted Metal and ROCm workflow, but Phase 16.C remains open until exact-head
artifacts from both required runners are ingested and checked. Existing Wang or Wortel GPU
artifacts are not reused as Phase 16 native-field evidence.

## Limits

- The native engine is scalar; multiple named species use independently declared engine instances.
- Adaptive time stepping, implicit methods, FEM, AMR, moving meshes, multi-GPU, and CUDA
  qualification are excluded.
- ProcessBigraphs-to-CorePotts adapter publication is Phase 16.E.
- No SciML/custom cross-adapter, assembled-model, internal-beta, or public-release claim is made.
