# G5H-4 implementation and capability matrix

Status: qualification record for the active G5H-4 candidate

Date: 2026-08-08

This matrix is the authoritative disposition of the implementation produced by
G5H-4. A row is a conjunction: evidence for one algorithm, backend, scalar,
component scope, or replay class does not authorize another. `RQ` means
`Supported` and `ReplayQualified`; `F` means functionally supported without an
exact-replay claim; `U` means fail-closed and unsupported.

## CPM execution

| Algorithm | Backend/device | Lattice | Scalar | Mechanisms | Disposition | Evidence or rejection boundary |
|:--|:--|:--|:--|:--|:--:|:--|
| `SequentialCPM` | `CPUBackend`, host | 2D; each axis closed or periodic | `Float32`, `Float64` | Package-owned or reviewed evidenced execution protocols; no lifecycle or `core_lifecycle_v1` | RQ in a reviewed exact environment; otherwise F | Core sequential CPU capability family, logical continuation, fast and full root suites |
| `CheckerboardSweepCPM` | `CPUBackend`, host | 2D; each axis closed or periodic | `Float32`, `Float64` | Same bounded package-owned families | RQ in a reviewed exact environment; otherwise F | Independent checkerboard CPU capability family and conformance suite |
| `CheckerboardSweepCPM` | `MetalBackend`, Apple Metal | 2D; each axis closed or periodic | `Float32` only | Package-owned or independently evidenced device mechanisms; no lifecycle or `core_lifecycle_v1` | RQ | Real M1 Pro runner, including odd sizes and workgroups; `g5h4-metal-native-evidence.md` |
| `SequentialCPM` | Metal | Any | Any | Any | U | Metal requires checkerboard execution; an explicit real-device rejection checks the public diagnostic |
| Either public CPM algorithm | CPU or Metal | 3D or other dimension | Any | Any | U | A public 3D problem compiles structurally but `init` rejects its `dimension=3` capability row. Makie 3D rendering does not change this disposition |
| Either public CPM algorithm | CPU | 2D closed/periodic | Other scalar | Any | U | Exact scalar policy is restricted to `Float32`/`Float64` |
| Checkerboard Metal | Metal | 2D closed/periodic | `Float64` or other scalar | Any | U | Real-device row is `Float32` only |
| Either | CUDA or ROCm | Any | Any | Any | U | No vendor extension or real-device evidence; adaptation/runner compilation is non-authorizing |
| Either | CPU | Admitted 2D/scalar | External execution mechanism | F only when Core recognizes `external_execution_protocol_v1`; otherwise U | External code has no package/code/environment replay identity |
| Checkerboard Metal | Metal | Admitted 2D/`Float32` | External descriptor, relationship, surface, lifecycle, or other unreviewed device code | U | Final real-Metal runner proves explicit `ProgramCapabilityError` rows |

`FrozenBorder` is a modeling policy whose compiled lattice topology is closed;
it is not a third backend boundary topology. Its field semantics have their own
oracle below.

## Native MTK component execution

All supported rows below require one completed `PottsSystem`, late
`NativeSolveProfile` selection, `CPMThenComponents`, a finite scalar
`FixedPhysicalTime`, event-free explicit ODEs, deterministic exact-replay
profiles, pinned public solver identity, and positive fixed `dt`. Native DAE
construction is retained for interoperability but coupled DAE execution is not
admitted.

| Scope/family | CPM algorithm | Backend/device | Scalar and execution | Lifecycle | Disposition | Evidence or rejection boundary |
|:--|:--|:--|:--|:--|:--:|:--|
| Global ODE | `SequentialCPM` | CPU | `Float64`, `Tsit5`, `SerialNativeExecution` | Global fixed identity | RQ | G5H-3 global exact replay and failure-atomicity suites rerun under G5H-4 |
| Per-cell ODE | `SequentialCPM` | CPU | `Float64`, `Tsit5`, `SerialNativeExecution` | Fixed-capacity generation-safe pool; explicit create, transition, division, retirement, and deletion policies | RQ | Per-cell runtime, stale-generation, publication, SII, and checkpoint tests |
| Per-cell explicit ODE | `SequentialCPM` | CPU | `Float64`, `Tsit5`, `BatchedNativeExecution(width)` | Same pool and lifecycle contract | RQ | Independent batched suite, serial parity, live counts and capacity edges; measured width 8/16 benefit |
| Global or per-cell ODE | `CheckerboardSweepCPM` | CPU | Any native CPU mode | Any | U | Explicit `NativeCapabilityError(:execution_profile)` regression; sequential component evidence is not reused |
| Global ODE | `CheckerboardSweepCPM` | Metal | `Float32`, `GPUTsit5`, `MetalNativeExecution(width)` | Global fixed identity | RQ | Real-Metal global component and exact restart rows |
| Per-cell explicit ODE | `CheckerboardSweepCPM` | Metal | `Float32`, `GPUTsit5`, fixed-capacity `MetalNativeExecution(width)` | Device-resident masks plus admitted fixed-capacity lifecycle receipts | RQ | Real-Metal per-cell, lifecycle, restart, transfer, synchronization, and performance rows |
| Any native component | Sequential CPU and checkerboard Metal | Supported inner profile only | As above | Multiple components | RQ only when every component row is independently RQ | One unsupported component makes the composed capability unsupported; CPU and Metal modes cannot be mixed in one runtime |
| Any native component | Any | Any | Adaptive stepping, solver defaults, unreviewed algorithms, opaque/non-audited equations, non-identity mass matrix, delay/discrete systems | Any | U | Preflight occurs before native problem construction/solver initialization |
| DAE | Any | Any | Any | Any | U | Original and compiled DAE semantics are retained and standard `DAEProblem` construction is tested; coupled execution rejects |
| ODE with MTK continuous/discrete event | Any | Any | Any | Any | U | Events are structurally retained, but event-bearing runtime profiles reject |
| Any native component plus outer Potts callback | Any | Any | Any | Any | U | Callback identity/state is absent from the native checkpoint key; explicit callback rejection is tested |
| Any failed or terminated native integrator | Any | Any | Any | Any | U for checkpoint/continuation | Failure and termination are atomic terminal states and have no admitted continuation codec |

The CPU implementation batches per-cell component lanes, not trajectories.
Global components remain separately scheduled simultaneous islands. Pool
capacity and lane width are runtime data and do not create generated model
topology.

## Fields and PDE adapters

| Field path | Algorithm/backend | Grid and scalar | Disposition | Evidence or rejection boundary |
|:--|:--|:--|:--:|:--|
| `DiscreteFieldEuler` | CPU CPM | 2D scalar lattice field; explicit `duration_per_mcs` and substeps | RQ for the tested built-in mechanism conjunction | Independent stencil oracle covers periodic, closed, `FrozenBorder`, non-negativity, and exact checkpoint restart |
| `DiscreteFieldEuler` | Metal or another GPU | Any | U | Its operation transfer declares `gpu=false`; native-field Metal evidence does not authorize this host stencil |
| Checked generic `NativeFieldOutput` | Checkerboard Metal native component | Fixed 2D grid matching the Potts lattice, `Float32` | RQ | Real 4×4 field publication, coordinate/shape agreement, evidence identity, and restart |
| Checked generic `NativeFieldOutput` | Sequential CPU native component | Any | U unless constructed by the MethodOfLines adapter below | An explicit generic-field profile reaches preflight and rejects for missing exact replay evidence |
| `MethodOfLinesComponent` | Sequential CPU native component | One scalarized fixed grid, exact coordinate lengths/order, `Float64`, fixed-step pinned `Tsit5` | RQ | MethodOfLines 0.11.19 weak extension: `symbolic_discretize`, upstream `mtkcompile`, standard ODE problem, publication, restart, and shape rejection |
| `MethodOfLinesComponent` | Metal/GPU | Any | U | Package-owned MOL provenance is distinct from generic native fields and is explicitly excluded from Metal evidence |
| MethodOfLines | Any | Remeshing, interpolation, incompatible lattice/PDE grids, multiple field outputs, native inputs, event-bearing or unreviewed PDE/solver profiles | U | Adapter requires one output-only global scalarized fixed grid and an exact coordinate-to-lattice map |

The internal MethodOfLines provenance policy is part of the scheduled
fingerprint. Loading MethodOfLines cannot accidentally promote an arbitrary
`NativeFieldOutput` to the MOL evidence row, and a MOL-produced field cannot
borrow the generic Metal field row.

## Lifecycle, observation, checkpoint, and callbacks

| Feature conjunction | Pure CPM | Supported native component row |
|:--|:--|:--|
| Create, transition, divide/duplicate, retire/remove/delete within declared fixed capacity | RQ for package-owned lifecycle families | RQ with explicit per-cell native policies and generation-safe pools |
| Capacity overflow, forbidden extinction, stale identity, unsupported lifecycle policy | Deterministic tested failure | Deterministic tested failure before publication; current and candidate banks remain atomic |
| Default settled state and named observations; `saveat`, start/end/every-step policies | RQ | RQ when the complete native conjunction is RQ |
| SII state/parameter access and staged parameter update | Supported | Supported for model, cell identity, native state, and saved solution access in admitted rows |
| Logical checkpoint and exact continuation | RQ rows only | RQ rows only; includes inactive generations, live lane state, native `u/p/t/du`, and component evidence identity |
| Imperative host discrete callback, no native component | F in-process; termination and failures surface | U with native components |
| Continuous outer callback | U | U |
| Checkpoint with any outer callback or after termination/failure | U | U |

## Whole-trajectory ensembles and orchestration

| Outer execution | Inner trajectory | Device | Disposition | Evidence or boundary |
|:--|:--|:--|:--:|:--|
| `EnsembleSerial` | Any independently admitted Potts profile | CPU | Supported | Replica/repeat identity, retry, output and reduction behavior |
| `EnsembleThreads` | Any independently admitted thread-safe Potts profile | CPU | Supported | Exact addressed parity with serial; scheduling order is not semantic identity |
| `EnsembleDistributed` | Serializable independently admitted Potts profile and functions | CPU workers in the same pinned environment | Supported | Clean-worker parity, reduction early stop, and worker exception propagation |
| Any SciML ensemble | Unsupported inner algorithm/backend/native conjunction | Any | U | An outer executor never upgrades inner capability and is distinct from per-cell batching |
| Dagger | User-owned coarse orchestration only | CPU/GPU as chosen by user | Deferred, outside package semantics | Eight-trajectory measurement: serial 2.744703 s, SciML threads 0.699338417 s, Dagger tasks 1.013743167 s, exact final-state parity |

Dagger therefore adds no dependency, scheduler abstraction, checkpoint
authority, or semantic surface. SciML owns trajectory identity, retries,
reductions, early termination, and failure propagation.

G5H-4 advertises serial, threaded, and distributed whole-trajectory execution
only for the evidenced CPU rows. It makes no separate cross-trajectory GPU
ensemble or GPU-vectorization claim; native Metal component kernels remain an
inner-trajectory capability and cannot be cited as such evidence.

## Qualification closure

The active candidate passed CorePotts, the 275-test pinned integration suite,
the complete 1,446-test root package surface (including the 404/404 runner-
closure surface), MakiePotts 501/501, strict docs,
the 68-operation inventory, specialization growth 12/12, the independent
static evaluator, scientific witnesses, and the complete real-Metal runner,
whose native block passed 37/37.
The quantitative records are `g5h4-native-cpu-evidence.md`,
`g5h4-metal-native-evidence.md`, and `g5h4-dagger-evidence.md`.

Formal gate closure still requires freezing these exact sources and manifests
in a clean commit. No row in this document is a compatibility promise for an
unsupported conjunction or an unpublished pre-V1 spelling.
