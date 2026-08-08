# G5H-4 Metal native and field evidence

Status: qualified bounded real-device rows

Date: 2026-08-08

## Admitted conjunctions

The Metal extension admits only 2D checkerboard CPM on a functional Apple Metal device with
`Float32`, accurate/deterministic/checked Core math, closed or periodic topology, and a reviewed
Core mechanism family. Native components additionally require a fixed-shape explicit ODE,
`DiffEqGPU.GPUTsit5()`, `adaptive=false`, a positive `Float32` `dt`, exact replay, deterministic
execution, and `MetalNativeExecution(width)`. No CPU fallback is permitted: one-lane problems are
padded to two identical GPU trajectories because DiffEqGPU otherwise selects `EnsembleSerial`.

Qualified native evidence identities are:

- `g5h4_global_metal_native_ode_exact_replay` for global scalar outputs;
- `g5h4_per_cell_metal_native_ode_exact_replay` for fixed-capacity per-cell pools; and
- `g5h4_native_field_metal_exact_replay` for a checked fixed-grid `NativeFieldOutput`.

CUDA, ROCm, adaptive solvers, non-`Float32` state, callbacks, unreviewed events, dynamic state
shape, unreviewed external mechanisms, and MethodOfLines-on-GPU remain unsupported. Compilation or
storage adaptation does not promote those rows.

## Correctness and replay

Environment: Apple M1 Pro, Julia 1.12.1, Metal 1.10.0, DiffEqGPU 3.16.0, one Julia thread.

Command:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=benchmark/backends/metal --startup-file=no --threads=1 \
  -e 'using Metal, PottsToolkit; Metal.functional() || error("Metal unavailable"); Metal.allowscalar(false); include("benchmark/backends/metal/native_component_execution.jl")'
```

Result: 37/37 passed in 3m07.1s after the final closed-stack, composed-identity, and capability-rejection audit. The suite covers:

- global and per-cell coupled advancement through real `EnsembleGPUKernel(MetalBackend())` solves;
- exact target-time arrival, deterministic replay, logical checkpoint continuation, live lane
  identity, pool capacity, and field/scalar output agreement;
- rollback when the fixed step cannot reach the next coupled boundary;
- explicit rejection of sequential-on-Metal, unsupported algorithm, adaptive mode, `Float64`
  Core execution, and MethodOfLines-provenance fields on GPU; and
- exact equality with the reviewed DiffEqGPU, Metal, MTK/SciML, Symbolics, StaticArrays, Julia,
  and target-platform stack before a native evidence row can be issued; and
- inclusion of the native evidence identity in the complete public capability-key fingerprint;
  and
- settlement instrumentation. One public step records one settlement, two synchronizations (the
  prevalidated transaction boundary and settlement drain), one control transfer, one snapshot
  transfer, and one lifecycle-receipt transfer for the lifecycle-enabled fixtures.

The checked field row publishes a 4 x 4 scalarized MTK ODE state into a `FieldState`, proves the
coordinate/shape mapping, and resumes exactly from a logical checkpoint. It is a native fixed-grid
field row, not MethodOfLines GPU support.

The remaining built-in Core Metal conformance rows were rerun after migrating their fixtures to
`mtkcompile` plus late algorithm/backend selection. Checkerboard boundary sizes 1, 255, 256, 257,
and 17 x 19 passed at workgroup sizes 32, 64, 128, and 256. Lifecycle execution, queued MCS,
capacity failure, canonical evaluator failure, public solve/checkpoint/parameter mutation,
state policies, planned trackers, eight partition variants, relationship policies, retirement,
forbidden extinction, and conflict resolution passed. External descriptor, relationship, surface,
and lifecycle-operation fixtures have explicit capability-rejection rows because their code lacks
a reviewed package/evidence identity.

## Post-warmup measurement

Command:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=benchmark/backends/metal --startup-file=no --threads=1 \
  benchmark/backends/metal/native_component_performance.jl
```

Fixture: the exact per-cell evidence row, two live lanes in capacity four, one warm public MCS,
then six measured public MCS. Result:

| Measure | Value |
|:--|--:|
| elapsed | 0.108327792 s |
| elapsed per MCS | 0.018054632 s |
| allocated | 7,284,112 bytes |
| GC | 0.0 s |
| settlements | 7 total |
| synchronizations | 14 total |
| control transfers | 7 total |
| snapshot transfers | 7 total |
| lifecycle transfers | 7 total |

This is a bounded latency/transfer record, not a claim that two tiny ODE lanes outperform CPU.
The profile exists to provide correct device-total native execution and scale to larger fixed lane
sets; CPU-versus-GPU crossover remains workload dependent.
