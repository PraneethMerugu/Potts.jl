# [Capability status](@id capability-status)

Support is a conjunction. Evidence for one algorithm, backend, scalar,
component scope, solver, or replay class does not authorize another.

| Profile | Status | Exact boundary |
|:--|:--:|:--|
| Sequential CPM, CPU | replay-qualified or functional | 2D closed/periodic, `Float32`/`Float64`; exact replay requires a reviewed environment |
| Checkerboard sweep CPM, CPU | replay-qualified or functional | Same 2D/scalar boundary, with independent checkerboard evidence |
| Checkerboard sweep CPM, Metal | replay-qualified | Apple Metal, 2D closed/periodic, `Float32`, reviewed device mechanisms |
| Sequential CPM on Metal | unsupported | Fails preflight; Metal requires checkerboard execution |
| 3D CPM execution | unsupported | Structural construction is retained, but `init` rejects `dimension=3` |
| CUDA or ROCm | unsupported | No public selector or qualifying real-device extension |
| Global native ODE, serial CPU | replay-qualified bounded row | Fixed-step, deterministic, event-free reviewed MTK/SciML stack |
| Per-cell native ODE, serial CPU | replay-qualified bounded row | Fixed-capacity generation-safe pool and admitted lifecycle policy |
| Per-cell native ODE, batched CPU | replay-qualified bounded row | `BatchedNativeExecution(width)`; distinct from trajectory ensembles |
| Global/per-cell native ODE, Metal | replay-qualified bounded row | `Float32`, fixed-step `GPUTsit5`, closed dependency/device evidence |
| `DiscreteFieldEuler` | replay-qualified bounded row | CPU periodic/closed/frozen-border oracle; checked native field has a separate Metal row |
| MethodOfLines field | replay-qualified bounded row | CPU-only checked 2D grid, `symbolic_discretize`, upstream `mtkcompile`, fixed-step reviewed solver |
| SciML ensembles | supported CPU rows | `EnsembleSerial`, `EnsembleThreads`, and `EnsembleDistributed`; inner trajectory must itself be admitted |
| Dagger | deferred | User-owned coarse orchestration only; never Potts scheduler or checkpoint authority |

Native DAEs may retain structure and construct an upstream problem, but coupled
DAE execution is unsupported. Native continuous/discrete events, adaptive GPU
solves, arbitrary callbacks, MethodOfLines on GPU, remeshing, generic native
fields without their evidence authority, and unreviewed solvers fail closed.

Exact replay additionally binds system, state, algorithm/backend/scalar,
native profile, dependency environment, observation mode, and checkpoint
identity. A functional run is not automatically an exact-continuation claim.

The exhaustive machine-facing disposition is recorded in the repository's
[`design/hardening/g5h4-capability-matrix.md`](https://github.com/PraneethMerugu/Potts.jl/blob/main/design/hardening/g5h4-capability-matrix.md).
