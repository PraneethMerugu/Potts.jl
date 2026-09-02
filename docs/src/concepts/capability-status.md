# [Capability status](@id capability-status)

Support is a conjunction. Evidence for one algorithm, backend, scalar,
component scope, solver, or replay class does not authorize another.

| Profile | Status | Exact boundary |
|:--|:--:|:--|
| Sequential CPM, CPU | supported; exact replay available | 2D closed/periodic, `Float32`/`Float64`; exact replay requires a matching environment |
| Checkerboard sweep CPM, CPU | supported; exact replay available | Same 2D/scalar boundary |
| Checkerboard sweep CPM, Metal | hardware-tested functional support | Apple Metal, 2D closed/periodic, `Float32`, mechanisms exercised by the real-device runner; no CI-hosted exact-replay claim |
| Sequential CPM on Metal | unsupported | Fails preflight; Metal requires checkerboard execution |
| 3D CPM execution | unsupported | Structural construction is retained, but `init` rejects `dimension=3` |
| CUDA or ROCm | unsupported | No public selector or qualifying real-device extension |
| Global native ODE, serial CPU | functional; optional exact replay | Event-free structural and solver preflight; exact replay requires the pinned stack |
| Global native DAE, serial CPU | functional only | Structural construction and solve are exercised; native DAE checkpoint replay is not admitted |
| Per-cell native ODE, serial CPU | functional; optional exact replay | Fixed-capacity generation-safe pool and admitted lifecycle policy |
| Per-cell native ODE, batched CPU | functional; optional exact replay | `BatchedNativeExecution(width)`; distinct from trajectory ensembles |
| Global/per-cell native ODE, Metal | hardware-tested functional support | `Float32`, fixed-step `GPUTsit5`; the ordinary real-device runner does not establish a CI-hosted exact-replay guarantee |
| `DiscreteFieldEuler` | supported; exact replay available | CPU periodic/closed/frozen-border oracle; checked native field has a separate Metal path |
| MethodOfLines field | functional; optional exact replay | CPU-only checked 2D grid, `symbolic_discretize`, upstream `mtkcompile`, fixed-step solver |
| SciML ensembles | supported CPU rows | `EnsembleSerial`, `EnsembleThreads`, and `EnsembleDistributed`; inner trajectory must itself be admitted |
| Dagger | deferred | User-owned coarse orchestration only; never Potts scheduler or checkpoint authority |

Native continuous/discrete events, adaptive GPU
solves, arbitrary callbacks, MethodOfLines on GPU, remeshing, generic native
fields with invalid shape or endpoint structure, and unsupported solvers fail
closed.

Exact replay additionally binds system, state, algorithm/backend/scalar,
native profile, dependency environment, observation mode, and checkpoint
identity. A functional run is not automatically an exact-continuation claim.

The ordinary package and integration tests exercise these boundaries,
including intentionally rejected profiles.
