# JuliaGPU and Performance Programming Standard

Status: Draft engineering standard for the refactor

Current disposition: use this as compatible implementation guidance only. Backend promotion,
component scopes, and evidence profiles are governed by
[Decision 0044](../spec/decisions/0044-pre-g6-cohesion-and-mtk-hardening.md) and the
[G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md); simultaneous AMDGPU/Metal
qualification language in this draft is not a current phase gate.

## Authority and Scope

This document governs performance-portable implementation in CorePotts and PottsToolkit. It applies
to the current CPU, AMDGPU, and Metal execution contract and to the use of KernelAbstractions,
AcceleratedKernels, KernelIntrinsics, Atomix, Adapt, StructArrays, StaticArrays, and related
performance tools.

This is an engineering standard, not a scientific semantics document. The contracts in `spec/`
remain authoritative. An optimization is conforming only when it preserves the applicable
scientific, stochastic, temporal, and numerical contracts.

The words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are normative within engineering work.
Deviations require a design note containing a benchmark, affected backends, semantic-risk analysis,
fallback behavior, and tests.

## Governing Principles

1. Correctness is established by a simple reference implementation before performance is claimed.
2. Hardware agnosticism means one public model and semantic contract, not identical low-level code.
3. GPU-resident execution is the normal GPU path. Host transfers and host synchronization are
   explicit boundaries, never incidental helper behavior.
4. The highest-level primitive that meets the semantic and performance requirements is preferred.
5. Every low-level optimization has a portable fallback and measured reason to exist.
6. CPU is a first-class target with its own tuning; it is not merely a GPU kernel emulator.
7. Performance claims are workload-, version-, backend-, and hardware-specific measurements.
8. Backend differences are capabilities to validate, not branches scattered through scientific
   code.

## Required Abstraction Ladder

Implementations SHOULD be attempted in this order:

1. Julia array operations, fused broadcast, or a mature library primitive
2. AcceleratedKernels primitive
3. A portable KernelAbstractions kernel
4. A KernelIntrinsics-powered specialization behind an internal interface
5. A backend-specific implementation in a package extension

Moving down the ladder requires evidence that the higher level cannot express the required
semantics or misses a material performance target. Backend-specific code MUST have the same public
contract and a portable fallback.

This ladder is not a rule to compose many high-level operations blindly. Extra materializations,
kernel launches, synchronization, or global-memory passes can justify a fused lower-level kernel.

## Ecosystem Roles

Each dependency has one primary architectural role:

| Package or facility | Approved role |
| --- | --- |
| KernelAbstractions | Portable custom kernel language, backend discovery, launch, allocation helpers |
| AcceleratedKernels | Qualified cross-backend parallel primitives |
| KernelIntrinsics | Isolated low-level subgroup and memory-operation specializations |
| Atomix | Portable atomic array operations with explicit ordering |
| Adapt | Recursive storage adaptation for parametric engine aggregates |
| StructArrays | Structure-of-arrays representation where access patterns justify it |
| StaticArrays | Small fixed-size values and bounded local computation |
| GPUArraysCore/GPUArrays | Array/backend interfaces and scalar-indexing safeguards, usually transitively |
| GPUCompiler | Compiler infrastructure and developer inspection, not a scientific API |
| CUDA, AMDGPU, Metal | Backend arrays, profiling, diagnostics, and extension implementations |
| Preferences | Recorded execution tuning only, never hidden semantic policy |
| PrecompileTools/SnoopCompile | Latency analysis and deliberate precompile workloads |
| BenchmarkTools and backend timers | Reproducible host and synchronized device measurement |

New performance dependencies require a demonstrated gap in these roles, maintenance and backend
assessment, compat policy, and an exit strategy. Overlapping packages are not added merely to offer
another spelling of an existing primitive.

Automatic differentiation packages such as ChainRulesCore or Enzyme are governed by a separate AD
capability contract. AD support MUST NOT force the primary simulation path to retain allocations,
dynamic dispatch, or unsupported device operations.

## Backend and Capability Model

### Backend discovery

The backend is obtained from owned storage with `KernelAbstractions.get_backend`. Public APIs MAY
also accept an explicit backend or device selection at construction time. Core scientific code MUST
NOT dispatch directly on `CuArray`, `ROCArray`, or `MtlArray`.

Backend-specific imports, allocation policy, diagnostics, and optimized implementations belong in
package extensions. The core package depends on backend-neutral interfaces.

### Capabilities

A compiled execution plan records the capabilities it requires, including as applicable:

- Atomic operation, element type, and memory ordering
- Subgroup operations and subgroup width behavior
- Required precision and mathematical operations
- Static or dynamic shared/local memory
- Maximum workgroup resources
- Asynchronous copy or library-operation behavior
- Device-side error-reporting support

Capabilities are checked during backend preflight. Unsupported required capabilities produce an
actionable error before the first MCS. Silent CPU fallback, scalar device indexing, precision
downgrade, or algorithm substitution is forbidden.

### Scalar indexing

Production tests MUST keep GPU scalar indexing disabled. Code MUST NOT temporarily enable scalar
indexing to make a GPU path work. Scalar reads are allowed only at a declared host-observation
boundary and must use an explicit transfer.

### Backend support levels

Each release publishes, per backend and algorithm family:

- `conforming`: full conformance and performance test coverage
- `experimental`: expected to run but not release-qualified
- `unsupported`: rejected during preflight

Availability of a JuliaGPU package is not itself evidence that Potts.jl supports that backend.

## KernelAbstractions Standard

KernelAbstractions is the default language for fused, domain-specific, and transactional kernels.

### Kernel boundaries and arguments

A kernel MUST receive concrete, device-compatible arguments. Kernel argument aggregates must be
immutable and ultimately bitstypes after adaptation. Abstract fields, host closures, dictionaries,
strings, exceptions as control flow, and host pointers are forbidden in device code.

Validation occurs on the host before launch. `@inbounds` is permitted only where the launcher or an
explicit kernel guard proves every access valid. Read-only non-aliasing arguments SHOULD use
`@Const` when its stronger non-aliasing contract is true.

Small callable structs are preferred to anonymous closures for reusable device behavior. Any
captured value must be concrete and visible to inference.

### Indexing and memory access

Linear indexing is the default when it produces contiguous access for Julia's column-major layout.
Multidimensional indexing is used when it improves locality or expresses a tiled algorithm.

Every launch specifies its logical `ndrange`. Workgroup sizes are tuning parameters, not scientific
parameters and not universal constants. A single global default such as 256 MUST NOT be assumed
optimal across CPU, NVIDIA, AMD, and Apple hardware.

Kernels using local memory or workgroup barriers MUST obey convergent execution: every active lane
in the workgroup reaches each barrier in the same dynamic order. Early return and divergent control
flow around `@synchronize` are forbidden. Partial final workgroups require explicit tests.

Local memory must have a statically bounded size, and its effect on occupancy and CPU lowering must
be benchmarked. Register pressure, spilling, and code size are review criteria, especially for
unrolled loops and static arrays.

### Launch ordering and synchronization

KernelAbstractions 0.9 uses implicitly ordered asynchronous launches and removed its former event
system. Code written for an event-bearing KA API MUST NOT be carried forward through compatibility
wrappers without version-specific verification.

The internal launch API MUST reflect the semantics of the supported KA version. It MUST NOT invent
dependency tokens or accept keywords the pinned version does not support. Cross-stream or
cross-device execution requires a separately designed dependency model; it must not be inferred
from obsolete KA events.

Kernel launches are asynchronous. Helpers launch work and return without a host wait unless their
documented result is a host value. `KernelAbstractions.synchronize` is allowed only at a declared
boundary:

- A host observation, callback, save, or checkpoint that needs completed device data
- Final solution materialization
- A validated error-report readback
- A backend transfer whose consumer is the host
- Correctly synchronized benchmarking or profiling
- Initialization when the host must consume its result before execution continues

Synchronization inside an energy, tracker, event, lifecycle, or workspace helper is forbidden by
default. An unavoidable synchronous third-party primitive must be isolated, documented, counted,
and exposed in the execution report.

“Zero-sync execution” means no host synchronization or host data dependency occurs between the
start and end of an MCS, except a user-requested observation boundary. It does not mean kernels lack
device-side barriers or ordered dependencies.

### Kernel construction

Kernel construction, backend selection, workgroup choice, and launch diagnostics go through one
small internal launch service. Scientific components provide an operation and logical domain; they
do not each reinvent dispatch policy.

The launch service records, in debug or profiling mode, kernel identity, backend, `ndrange`,
workgroup size, temporary memory, and synchronization boundaries.

## AcceleratedKernels Standard

AcceleratedKernels is preferred for established portable primitives such as index loops, sorting,
reductions, scans, searches, and fills when its exact contract matches the operation.

### General use

Code using `foreachindex` or `foraxes` MUST run inside a function with concrete captured values.
Global arrays and type-unstable captures are forbidden. A fused broadcast MAY be clearer and faster
for simple elementwise arithmetic and should be benchmarked.

GPU `block_size` and CPU `max_tasks`/`min_elems` are execution-policy values. Defaults are accepted
only after representative measurement; otherwise they are supplied by the tuning policy.

### Reductions

Every reduction explicitly defines:

- Mapped element type
- Accumulator and result type through `init`
- Mathematically valid `neutral` element
- Associativity assumptions
- Empty-input behavior
- Permitted ordering sensitivity
- Reproducibility class

The result type MUST NOT be left to an incidental input type when overflow or precision can change
scientific behavior. Floating-point parallel reductions are not treated as bitwise deterministic
unless a deterministic reduction algorithm says so explicitly.

A scalar GPU reduction returns data to the host and is therefore a host-observation boundary. A
device-resident intermediate SHOULD use a dimensioned or custom device reduction that avoids scalar
materialization when the value is consumed by later device work.

### Sorting and temporary storage

Sort stability, comparator semantics, tie handling, and output ordering are explicit requirements.
They are tested against the reference operation, including repeated keys.

Temporary buffers for sorting and reductions are allocated in a workspace and reused. Per-MCS
temporary allocation is forbidden in steady state. A primitive whose completion or ordering cannot
be safely composed without host synchronization is treated as a synchronization boundary until its
pinned implementation is proven otherwise.

### Primitive qualification

Each AcceleratedKernels primitive used by the engine has a qualification test covering all supported
backends, edge sizes, empty inputs, non-multiple workgroups, aliases, and relevant data types. The
test records whether the operation allocates, transfers, or synchronizes.

## KernelIntrinsics Standard

KernelIntrinsics is an expert-only optimization layer for subgroup collectives, voting, shuffles,
memory fences, and similar low-level operations. It MUST NOT appear throughout scientific component
code.

The standalone `KernelIntrinsics` dependency and any same-named internal module exposed by a future
KernelAbstractions release are distinct APIs. Source code, compat bounds, and design notes must
identify the exact package UUID/module path and version being qualified; names alone are
insufficient.

All use goes through a CorePotts internal interface such as `SubgroupOps`. That interface provides:

- A generic KernelAbstractions implementation
- Capability detection and a safe fallback
- Public, version-qualified intrinsic calls
- Explicit active-lane masks and participation rules
- Tests for partial groups, divergence, and every supported subgroup width
- Equivalence and statistical tests against the generic algorithm

Hard-coded warp width, NVIDIA-only terminology as behavior, and assumptions that a subgroup has 32
lanes are forbidden. Private names such as `_warpsize` are forbidden outside a single temporary
compatibility shim with an exact dependency pin and removal issue.

Subgroup aggregation MAY reduce atomic contention, but it does not alter proposal identity,
acceptance semantics, tracker timing, or RNG addressing. A subgroup optimization is enabled only
where backend qualification demonstrates correctness and a material end-to-end benefit. Register
use, occupancy, and code size are included in its benchmark.

KernelIntrinsics is not part of the user API and never becomes the sole implementation of an
accepted scientific feature.

## Atomics and Memory Ordering

Atomix is used only for genuine concurrent updates. An atomic operation is not a substitute for a
well-designed ownership or segmented-reduction scheme.

Every atomic site documents:

- The protected invariant
- Operation and element type
- Expected contention
- Required memory ordering
- Overflow behavior
- Meaning of the expression's returned value
- Effect on reproducibility
- Supported backend matrix

Sequential consistency is the default when correctness has not yet been proven under a weaker
ordering. `monotonic` MAY be used for an isolated counter or commutative accumulation only after a
happens-before analysis proves the atomic does not publish or guard other memory. Acquire, release,
or acquire-release orderings require the same written analysis and cross-backend tests.

Code MUST use the documented return semantics of the pinned Atomix/Julia API; comments or algorithms
must not guess whether an atomic update returns the old or new value.

Floating-point atomics generally have schedule-dependent accumulation order. They are allowed only
under a declared statistical/numerical reproducibility contract. Deterministic modes use a
deterministic reduction, integer or exactly representable accumulation where valid, or another
specified algorithm.

High-contention atomics are profiled. Alternatives include ownership partitioning, local/subgroup
aggregation, sorting and segmented reduction, coloring, and multi-pass algorithms. The alternative
is selected by end-to-end measurements, not atomic count alone.

## Adaptation and Device Data

Adapt is the sole recursive mechanism for moving engine aggregates between storage domains.
Custom aggregates implement `Adapt.adapt_structure` or use `Adapt.@adapt_structure` when the
generated behavior is exactly correct.

Types remain parametric in their storage. Adaptation changes storage, not scientific meaning,
precision policy, identifiers, or schema. Backend-specific convenience constructors that silently
change element type MUST NOT be used in semantic adaptation.

There is one explicit engine adaptation entry point. After adaptation it validates that all kernel
arguments are concrete, device-compatible, and free of host arrays or host-only objects. Rebuilding
types through internals such as `Base.typename(typeof(x)).wrapper` is prohibited in new code;
ConstructionBase, Functors, or an explicit constructor is preferred.

Mixed-device aggregates are rejected unless a documented multi-device execution plan owns them.

## Data Layout

### StructArrays and structure of arrays

Structure-of-arrays is the default for large per-cell tables when kernels usually access a subset
of properties across many cells. StructArrays MAY provide the user-facing row abstraction while its
component arrays provide coalesced device storage.

Layout is chosen from measured access patterns. Small immutable records whose fields are always
loaded together MAY use array-of-structs. A conversion to StructArray is not automatically faster
and can copy data; layout conversions must be explicit and outside the MCS hot path.

The compiled property schema fixes column element types, alignment-relevant representation, and
capacity before GPU execution. Abstract or union-heavy columns are forbidden in device-resident hot
state.

### StaticArrays

StaticArrays are used for genuinely small, fixed-size values such as 2D/3D coordinates, tiny
matrices, and short topology offsets. They are not a general container for model-sized data.

The use of a static array requires measurement of compile latency, native code size, registers, and
spills. Large or highly variable static dimensions are forbidden because unrolling and
specialization can explode. Runtime topology tables, arbitrary neighborhoods, property schemas, and
cell populations remain descriptor or component arrays.

Immutable static values are preferred in kernels. Mutable static arrays are used only as bounded
local scratch whose allocation and lowering have been inspected.

### Index and numeric representation

Device index width is an explicit storage policy. `Int32`/`UInt32` MAY be used only after host-side
capacity validation proves every index, product, offset, and sentinel representation safe.
Intermediate arithmetic must not overflow before conversion. Exceeding a fixed capacity is an error
under the accepted lifecycle contract, never wraparound.

Booleans and bit-packed representations require special care: concurrent writes to distinct logical
bits may share a storage word. Bit packing is used only with a race-free update design and benchmark.

Graph-like relations use bounded flat layouts such as CSR/CSC-style offsets and values where
appropriate; device arrays of heap-like nested containers are forbidden.

## Allocation and Workspace Policy

Steady-state MCS execution performs no host or device allocation. Algorithms declare their scratch
requirements during plan compilation, and a backend-owned workspace allocates reusable buffers.

Workspace sizing depends on validated maximum lattice size, cell capacity, topology, algorithm,
precision, and compiled model features. The normalized model report includes estimated persistent,
scratch, and peak memory.

Buffer reuse must respect launch ordering and aliasing. Two logically concurrent operations cannot
reuse the same scratch region without a proven dependency. Initialization, resizing, and deliberate
checkpoint staging are measured separately from steady state.

## Numerical Performance Policy

Precision, accumulator types, fast-math behavior, and reduction ordering are semantic or numerical
policy, not hidden compiler switches.

Fast math is off by default. It MAY be enabled by an explicitly named numerical mode whose permitted
transformations and validation tolerances are documented. Optimizations that reassociate operations,
contract operations, flush subnormals, approximate transcendental functions, or change NaN behavior
must be included in that contract.

Integer arithmetic is checked where overflow would corrupt state. Floating-point comparisons avoid
backend-sensitive algebraic rewrites unless validated. CPU and GPU need not be bitwise identical
unless the selected reproducibility class promises it, but all backends must satisfy the accepted
numerical and statistical tests.

## CPU Performance

Portable GPU code does not excuse poor CPU performance. CPU paths are profiled independently for
threading overhead, vectorization, cache locality, false sharing, and NUMA effects where relevant.

AcceleratedKernels or KernelAbstractions is the default portable CPU path. A CPU-specific optional
implementation using Base threads, SIMD tooling, or another package MAY be introduced behind the
same internal operation interface when it is materially faster and equivalence-tested.

CPU work partitioning uses minimum useful grain sizes and avoids spawning a task per small item.
Thread count and scheduling are execution policy. The scientific result does not depend on Julia
thread scheduling beyond its declared reproducibility class.

## Profiling and Benchmarking Contract

### Measure the simulation first

Optimization starts with an end-to-end profile. Microbenchmarks justify a mechanism only after the
operation is shown to matter to total MCS time.

GPU timing synchronizes immediately outside the measured region or uses backend timing facilities
that correctly account for asynchronous execution. Compilation, adaptation, allocation, warm-up,
and first-use library initialization are reported separately from steady-state execution.

### Required workload matrix

Release and regression benchmarks cover representative combinations of:

- 2D and 3D
- Small, medium, and publication-scale lattices
- Low and high cell occupancy
- Low and high interface density
- Sparse and dense enabled components
- Each stable algorithm family
- CPU and each supported GPU backend

Workloads are versioned and include fixed semantic configuration and seeds. Benchmark results record
Julia, package, driver, compiler, operating system, device, thread count, precision, and tuning
policy.

### Required metrics

At minimum report:

- MCS per second and accepted/proposed attempts per second
- Time per lattice site or proposal where meaningful
- Host synchronizations and host-device transfers per MCS
- Kernel launches per MCS
- Persistent, scratch, and peak device memory
- Steady-state allocations
- Compile latency and time to first MCS
- Generic versus optimized implementation speedup
- Register use, occupancy, spills, and local memory for critical GPU kernels
- CPU scaling and parallel efficiency for critical workloads

Performance regressions use explicit thresholds and repeated statistically summarized runs. A
single best timing is not evidence.

### Profiling tools

Use Julia-level profiles to find host bottlenecks and backend tools for device behavior. CUDA work
uses CUDA profiling macros and NVIDIA tools; AMDGPU work uses ROCm profiling tools; Metal work uses
Metal profiling support and Instruments. Device-code inspection is backend-specific and remains in
extensions or developer tooling.

## Tuning Policy

Workgroup size, CPU grain size, algorithm crossover, tile size, and scratch strategy are execution
policy. They MUST NOT change scientific semantics or RNG identity.

Defaults are conservative and portable. Optional autotuning:

- Runs only outside timed scientific execution
- Searches a finite validated set
- Uses representative generated or user-approved workloads
- Caches by operation, backend, device architecture, data class, and package version
- Records the chosen values in the run report
- Never changes exact versus approximate algorithm selection

Preferences MAY store performance policy, but semantic choices must remain explicit model or solve
configuration.

## Dependency and API Governance

Every direct dependency has a compat bound in the owning `Project.toml`. GPU-sensitive updates are
qualified on the backend test matrix before release. The release report records exact package and
driver versions.

Private dependency APIs are forbidden. A temporary private-API shim requires:

- Isolation in one file
- An exact compatible version range
- A linked removal issue
- A public fallback
- Tests that fail clearly when the dependency changes

Dependency upgrades inspect release notes for launch ordering, synchronization, atomics, adaptation,
and numerical changes. Passing unit tests on CPU alone is insufficient.

## Testing Requirements

Every optimized operation has:

1. A clear host reference implementation
2. Deterministic edge-case and invariant tests
3. Generic portable implementation tests
4. Optimized-versus-generic equivalence tests
5. Supported-backend compilation and execution tests
6. Statistical tests where scheduling or floating-point order is permitted to differ
7. Allocation and synchronization checks for hot paths
8. Performance regression coverage where the optimization is retained for speed

Test sizes include zero where valid, one, below/at/above workgroup size, non-power-of-two sizes,
partial final groups, capacity boundaries, and pathological contention. Bounds-checking and debug
builds are part of CI. Backend hardware CI is required for a backend to be release-conforming.

## Review Checklist for Hot Code

Before merging a kernel or performance primitive, reviewers answer:

- Which accepted semantic contract does it implement?
- Where is the reference implementation?
- Why is this abstraction level necessary?
- Are all argument and captured types concrete and device-compatible?
- Are indexing, aliasing, bounds, partial groups, and barriers proven safe?
- Are allocation, transfer, and synchronization behavior explicit?
- Are atomic operation, ordering, contention, overflow, and return semantics documented?
- Does RNG identity remain independent of scheduling and tuning?
- Are numeric types, neutral values, and reduction order intentional?
- What are the portable fallback and capability failure behavior?
- Which CPU/GPU backends compile and pass equivalence tests?
- What end-to-end benchmark justifies the complexity?
- What happens to compile time, registers, occupancy, and memory?

## Current-Code Migration Audit

The following are refactor targets discovered in the current CorePotts tree. They are not accepted
behavior and must not be copied into new architecture.

### P0: launch model mismatch

`Base/dispatch.jl` presents an explicit dependency/event abstraction and passes `dependencies=` to
selected launches. The resolved KernelAbstractions version is 0.9.42, while KA 0.9 removed its event
system in favor of implicitly ordered launches. The launch layer must be redesigned for the pinned
API before “zero-sync” behavior can be trusted. Tests must prove ordering on CPU, AMDGPU, and Metal
under the current first-class backend contract rather than encode backend folklore.

### P0: host synchronization in execution paths

The simulator, length and focal-point penalties, and property/lifecycle kernels contain direct
`KernelAbstractions.synchronize` calls. Each site must be classified as a true observation boundary,
an error-readback boundary, or removable engineering debt. The target is no incidental host wait
inside an MCS.

### P1: primitive composition

The property pipeline calls `AcceleratedKernels.sort!` and then immediately synchronizes. Qualify the
pinned sort implementation, reuse its temporary buffer, and redesign the pipeline so a host wait is
not assumed to be the only safe composition mechanism. Until proven, the execution report must mark
it as a synchronous boundary.

### P1: private and reflective APIs

Tracker code calls `KernelIntrinsics._warpsize`, and adaptation reconstructs types through
`Base.typename(...).wrapper`. Both violate the public-API rule. Replace them with qualified public
capability/adaptation interfaces and generic fallbacks.

### P1: atomic inventory

Current volume, surface, accumulator, event-count, and mitosis paths use Atomix. Each site needs the
atomic contract described above, contention measurement, overflow tests, and a reproducibility
classification. Comments about returned values must be verified against the pinned API.

### P1: dependency compatibility

CorePotts currently lacks compat entries for several direct performance dependencies, including
KernelAbstractions, AcceleratedKernels, Adapt, Atomix, StaticArrays, and StructArrays. Add compatible
ranges only after the current combination is qualified, then test controlled upgrades across the
backend matrix.

### P2: tuning and layout evidence

Replace universal workgroup assumptions with operation-specific tuning policy. Audit StructArray and
StaticArray use from actual access patterns, register behavior, and allocation evidence rather than
type aesthetics.

## Adoption Sequence

1. Freeze and qualify the dependency set; add compat bounds.
2. Build backend capability and preflight reporting.
3. Replace the obsolete launch/dependency wrapper and instrument synchronization.
4. Establish reference operations and backend equivalence tests.
5. Move scratch allocation into explicit reusable workspaces.
6. Isolate KernelIntrinsics and atomic policies behind internal interfaces.
7. Remove incidental host waits from the MCS execution graph.
8. Establish the workload matrix and reproducible benchmark baselines.
9. Optimize only measured bottlenecks, recording generic and specialized results.

## Primary References

- [KernelAbstractions documentation](https://juliagpu.github.io/KernelAbstractions.jl/)
- [KernelAbstractions quickstart and synchronization](https://juliagpu.github.io/KernelAbstractions.jl/stable/quickstart/)
- [KernelAbstractions kernel language](https://juliagpu.github.io/KernelAbstractions.jl/stable/kernels/)
- [AcceleratedKernels general loops](https://juliagpu.github.io/AcceleratedKernels.jl/stable/api/foreachindex/)
- [AcceleratedKernels sorting](https://juliagpu.github.io/AcceleratedKernels.jl/stable/api/sort/)
- [AcceleratedKernels map-reduce](https://juliagpu.github.io/AcceleratedKernels.jl/stable/api/mapreduce/)
- [Atomix documentation](https://juliaconcurrent.github.io/Atomix.jl/dev/)
- [CUDA.jl performance guidance](https://cuda.juliagpu.org/stable/tutorials/performance/)
- [CUDA.jl custom structures and Adapt](https://cuda.juliagpu.org/dev/tutorials/custom_structs/)
- [StructArrays documentation](https://juliaarrays.github.io/StructArrays.jl/stable/)
- [StaticArrays guidance](https://juliaarrays.github.io/StaticArrays.jl/stable/)
- [Julia performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
