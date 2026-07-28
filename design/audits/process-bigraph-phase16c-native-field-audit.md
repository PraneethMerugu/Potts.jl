# ProcessBigraphs Phase 16.C Native Field Audit

Status: Qualified on CPU, real Metal, and real ROCm

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

## Qualified evidence

Trusted self-hosted workflow run
[`30360086075`](https://github.com/PraneethMerugu/Potts.jl/actions/runs/30360086075)
qualified exact commit `83f7aea20a85bb3855a5976ee64e738be15b1866`. The Metal and ROCm jobs
both passed the pre-existing tiled, device-invariant, and Wortel gates before running the Phase 16
native-field workload and uploading backend-specific artifacts.

The final evidence uses one source identity across CPU, Metal, and ROCm:
`46b5f430b8774080a2b8f3fd8437795c9cbad6e9699e8c5b2833c4f4715a7c25`. Both
the periodic 2D and mixed-boundary 3D cases have zero error against the Float32 CPU reference,
zero staging transfers, zero warm device allocations, zero publication allocations, exact target
ticks, and the expected publication epoch. Construction, completion, and requested observation
transfers remain explicit in the artifact rather than being misreported as a zero-transfer
lifecycle.

The content-addressed CPU, Metal, and ROCm artifacts and GitHub job provenance are recorded in the
[Phase 16.C evidence manifest](../evidence/process-bigraph-phase16c-evidence-v1.toml). Existing
Wang or Wortel GPU artifacts were not reused as Phase 16 native-field evidence.

## Limits

- The native engine is scalar; multiple named species use independently declared engine instances.
- Adaptive time stepping, implicit methods, FEM, AMR, moving meshes, multi-GPU, and CUDA
  qualification are excluded.
- ProcessBigraphs-to-CorePotts adapter publication is Phase 16.E.
- No SciML/custom cross-adapter, assembled-model, internal-beta, or public-release claim is made.
