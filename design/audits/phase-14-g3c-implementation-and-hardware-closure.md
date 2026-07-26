# Phase 14 G3-C Implementation and Hardware Closure

Status: implementation and fail-closed qualification harness complete; real Metal and ROCm evidence pending

Date: 2026-07-26

## Frozen boundary

G3-C inherits revision 7 of the G3-B entry contract. It does not change the Wang state ABI,
eleven-process identity, plan order, RNG addressing, transaction/publication semantics, launch
topology, observation schedules, or checkpoint boundary. The canonical implementation remains the
same descriptor-free KernelAbstractions process tree accepted by G3-B.

## Implemented closure machinery

- Exact Wang recognition now qualifies only the admitted Float32 law/storage profile on a
  functional, qualified, ordered Metal or ROCm backend with semantic RNG v1.
- The recognizer walks every heap-backed array in the coupled plan and state and rejects any
  host-owned or mixed-backend leaf.
- The canonical fixture constructs the same model on `Array`, `Metal.MtlArray`, or
  `AMDGPU.ROCArray`; all execution workspaces are allocated from the authoritative backend
  prototypes.
- The paper profile runs the specified 256×256 model through target MCS 500. The smoke profile
  runs 32×32 through target MCS 212 and therefore crosses reset, calibrate, and first publish.
- The runner proves same-backend replay, exact completed-MCS restart, bounded observations,
  schedule/epoch invariants, CPU Float32 numerical tolerances, storage bytes, warm performance,
  allocation counters, and the observation-free target-MCS-2 transfer contract.
- Target MCS 2 performs exactly nine registered device-to-host status-scalar transfers across five
  declared status boundaries, zero scientific-payload transfers, zero host-to-device transfers,
  and zero CorePotts device allocations.
- Metal AIR and ROCm device-code scripts capture target MCS 211, which exercises Potts, field,
  history, calibration, intracellular, retune, alignment, force, cleanup, and bounded observation
  kernels.

## Hardware commands

Metal:

```text
JULIA_LOAD_PATH="benchmark/backends/metal:benchmark:@stdlib" julia --project=benchmark/backends/metal --startup-file=no --check-bounds=yes benchmark/phase14_wang_g3c_qualification.jl --backend=metal --profile=paper
JULIA_LOAD_PATH="benchmark/backends/metal:benchmark:@stdlib" julia --project=benchmark/backends/metal --startup-file=no benchmark/profile_phase14_wang_g3c_metal.jl
```

ROCm:

```text
JULIA_LOAD_PATH="benchmark/backends/amdgpu:benchmark:@stdlib" julia --project=benchmark/backends/amdgpu --startup-file=no --check-bounds=yes benchmark/phase14_wang_g3c_qualification.jl --backend=amdgpu --profile=paper
JULIA_LOAD_PATH="benchmark/backends/amdgpu:benchmark:@stdlib" julia --project=benchmark/backends/amdgpu --startup-file=no benchmark/profile_phase14_wang_g3c_amdgpu.jl
```

The shared GPU workflow must add both commands to the corresponding self-hosted jobs and upload the
result TOML plus device-code directory. No CPU artifact, emulated backend, structural inspection, or
G3-B KernelAbstractions CPU run substitutes for either hardware record.

## Closure rule

Run `scripts/attest_phase14_g3c.jl` from the clean implementation commit with the two downloaded
paper result TOMLs and two device-code artifacts. It first invokes the closure checker in
evidence-only mode, rejects mismatched commits or trees, hashes and archives every artifact, emits
`design/evidence/phase-14/g3c-closure/manifest-v1.toml`, and deterministically advances every
ledger/process row. Commit only those evidence and ledger changes. The ordinary closure checker
then requires a clean attestation checkout, verifies the complete manifest, and proves every change
since the implementation commit is attestation-only.

Until that final check passes, the machine-readable ledger remains `hardware_pending`, Wang remains
Provisional, and G4 does not open.
