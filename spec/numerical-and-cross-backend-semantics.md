# Numerical and Cross-Backend Semantics

Status: Accepted

## Purpose

This document defines numeric types, precision, conversion, arithmetic, reductions, atomics,
overflow, cross-backend comparison, specialization, automatic differentiation boundaries, and
numerical reporting for Potts.jl.

Scientific source code is generic Julia. Compiled execution is concrete, type-stable, backend
qualified, and governed by an explicit numerical policy.

## Generic Julia Numeric Design

Scientific APIs do not hard-code `Float32` or `Float64`. Ordinary functions use generic arithmetic
and the narrowest meaningful numeric requirements.

Scientific configuration and compiled hot-path structs use concrete parametric fields:

```julia
struct VolumeConstraint{T}
    strength::T
end
```

Fields such as `value::Real`, `array::AbstractArray`, and `f::Function` are forbidden in compiled hot
structures. Public functions MAY accept abstract interfaces; function barriers lower them to
concrete storage and callables.

Numeric types and small structural facts MAY appear as type parameters. Scientific values such as
temperature, penalty strengths, targets, and rates remain fields. Arbitrary values are not promoted
into types.

Generic arithmetic avoids literals that accidentally force `Float64`. Code uses `zero`, `one`,
`oftype`, explicit policy conversion, or another type-preserving construction where appropriate.

Algorithms allocate through `similar`, backend allocation, or compiled workspaces rather than
hard-coded `Array`, `Vector`, or `zeros` constructors.

## Primary Real Type

Each compiled model has one primary real type inherited by continuous properties, parameters,
energy values, and fields unless a declaration explicitly selects another type.

The Level 1 portable default is `Float32`. This choice is visible in normalized
reports and documentation. CPU is the ordinary portable execution profile;
bounded Metal mechanisms have separate real-device evidence. AMDGPU, CUDA, and
ROCm are not current public PottsToolkit backend profiles.

Explicit `Float64` scientific input or policy is never silently narrowed to `Float32`. It is
preserved on qualified backends or rejected with a capability diagnostic. Backends do not choose
different precision automatically.

Untyped decimal literals in Level 1 declarations are converted through the selected model real type.
The normalized value is visible, and diagnostics retain enough authoring context to report
consequential rounding.

`Float64` is a supported scientific option on qualified CPU and GPU backends. `Float16` and
`BFloat16` core scientific state remain Experimental until component-specific range, error,
accumulation, and statistical validation exists.

## Numerical Policy

Numerical behavior is represented by typed orthogonal settings, conceptually:

```julia
NumericalPolicy(
    real = Float32,
    accumulation = Float32,
    math = AccurateMath(),
    reductions = DeterministicReductions(),
    overflow = CheckedModelBounds(),
)
```

The final field and type names may be refined, but the choices remain separate semantic data rather
than one opaque symbol.

Named presets MAY provide concise bundles. Their complete expansion appears in model and run reports.

### Portable default

The default portable policy selects:

- `Float32` primary real storage
- `Float32` energy accumulation
- Accurate/default math without fast-math annotations
- Explicit reduction types and neutral values
- Fixed reduction laws where results are observable
- Checked preflight bounds
- No silent precision or host fallback

### Publication preset

A publication preset requests the strongest supported reproducibility, fixed numerical choices,
complete provenance, and strict backend preflight. It does not automatically mean `Float64`; the
chosen types and backend evidence are explicit.

### Performance preset

A performance preset enables only qualified numerical and execution choices. It cannot silently
replace an exact scientific algorithm with an approximate one or weaken reproducibility beyond its
reported contract.

Scientific precision, accumulation, math, reduction, and overflow choices participate in run
identity and any fingerprint used for trajectory claims. Workgroup size and pure execution tuning do
not.

## Storage and Accumulation

Storage, accumulator, and result types are distinct policy concepts.

Examples include a `Float32` field with wider accumulation, an integer site count with a wider
temporary sum, or a deterministic fixed representation where scientifically valid.

The default energy accumulator is the primary real type, normally `Float32`. CorePotts does not hide
a universal `Float64` accumulator because that would change portability, performance, and backend
behavior.

Wider accumulation is explicit and never selected silently by backend. Energy components MAY
produce different internal scalar types, but compilation establishes one deterministic promoted
energy type independent of component order.

Acceptance probability uses the energy accumulation type by default. A policy MAY explicitly select
another evaluation type for the acceptance function after domain and backend qualification.

Reference validation has two distinct forms:

- A type-matched reference using the production storage and accumulation types
- A higher-precision or analytic oracle for numerical error analysis where meaningful

CPU `Float64` is not automatically scientific truth.

## Conversion

Exact safe conversions MAY be automatic. The following require explicit policy and reporting:

- Numeric narrowing
- Floating-to-integer conversion
- Rounding or saturation
- Missing-value conversion
- Precision loss

User-defined `convert` methods do not automatically define scientific conversion semantics.

Backend adaptation preserves selected scientific types. Saving and loading do not silently widen or
narrow stored values.

## Exact Integer State

The following remain exact integer quantities:

- Lattice ownership IDs
- Cell type IDs
- Cell generations
- Volumes measured as site counts
- Proposal, acceptance, and event counts
- MCS and schedule counters
- Capacity and free-list counts
- Canonical direction IDs

Device owner and cell IDs use `UInt32` initially where capacity validation proves safety. Zero is a
sentinel only in the explicitly documented representations permitted by the state contract.

Device signed counts, indices, and offsets prefer 32-bit types when their full valid range,
intermediate products, offsets, and sentinel representation are proven safe. Public Levels 1–3 use
typed semantic identifiers rather than exposing these compiled integer choices.

Host MCS time normally uses `Int`; device execution uses a validated fixed-width representation.

Preflight validates every relevant maximum, product, offset, count, and sentinel—not merely lattice
length. Predictable overflow is rejected before execution. Unexpected runtime overflow triggers the
structured device error mechanism and aborts the transaction. It never wraps silently.

Qualified release kernels use efficient arithmetic after bounds are proven rather than adding
checked branches to every operation. Debug and boundary tests exercise the proof assumptions.

## Floating-Point Math

Fast math is disabled by default. Scientific component code does not contain scattered `@fastmath`
annotations. An explicit qualified policy controls approximate functions, reassociation, contraction,
and subnormal behavior centrally.

Backend-standard fused multiply-add contraction MAY occur in the normal portable policy only within
the documented numerical tolerance. A bitwise profile specifies contraction more strictly.

NaN and infinity are invalid in core model state unless a property schema explicitly permits them.
Host-known parameters are validated before execution. Runtime production uses a structured error and
does not silently propagate through state.

Subnormal flushing is not silent. It may be permitted by a fast policy and then appears in
provenance. Potts.jl does not alter process-wide floating rounding mode.

Exact comparisons remain exact. Approximate comparison requires an explicitly declared tolerance or
scientific operation; Potts.jl does not insert a universal epsilon.

Zero temperature is implemented as a named accepted zero-temperature law. It is not an accidental
division-by-zero outcome.

## Reductions

Every reduction declares:

- Input and mapped types
- Accumulator and result type
- Initial value
- Mathematically valid neutral element
- Empty-input behavior
- Required algebraic laws
- Permitted ordering sensitivity
- Numerical and reproducibility profile

This applies to custom kernels and AcceleratedKernels primitives.

Floating-point reductions do not promise identical results under arbitrary scheduling. A
deterministic reduction fixes the grouping or tree required by its guarantee. If a result affects
state, acceptance, events, or promised trajectory reproducibility, changes in workgroup decomposition
cannot change the contracted result.

Diagnostic-only reductions MAY use a faster schedule-dependent order when they declare a justified
tolerance and never feed simulation state.

## Atomics

Integer atomic counters are exact within preflight-proven ranges. Their memory ordering and overflow
contracts remain explicit.

Floating-point atomic addition is avoided in strict trajectory paths because arrival order changes
rounding. Strict implementations use deterministic ownership, sorting, segmented or fixed-tree
reduction, or another qualified construction.

Floating atomics MAY be used by statistically qualified paths when numerical error and stochastic
validity are measured and documented.

Atomic memory ordering governs visibility; it does not make floating arithmetic associative or
deterministic.

## Cross-Backend Guarantees

The following match bit-for-bit across release-conforming backends under the applicable contract:

- Exact integer state and diagnostics
- Raw counter-based RNG output
- Semantic identifiers and schedules
- Canonical topology integer data
- Deterministic serialization fields

Floating state is not universally bit-identical across qualified backend
profiles by default. It
satisfies the selected numerical and reproducibility profile's per-quantity tolerances, invariants,
and statistical tests.

Repeated runs on the same qualified backend match exactly when the selected algorithm and profile
promise trajectory reproducibility.

An unsupported mathematical function or precision does not silently use a lower-precision
approximation or CPU fallback. An explicitly selected approximate policy may use only named,
qualified approximations.

Transcendental functions are qualified by backend and scalar type. Successful compilation alone is
not numerical evidence.

GPU scalar indexing remains disabled in production. Backend reports include device, scalar types,
math and reduction policies, relevant dependency versions, and qualification limitations.

## Specialization and Compilation

CorePotts specializes on numeric types, component structure, and other facts when runtime benefit
justifies it. It does not promise to encode an entire model and all parameter values into one giant
type.

Specialization policy is initially an internal measured decision. A SciML-like user-selectable
specialization policy MAY later be exposed at Levels 2–3 when use cases justify it.

Package load time, model compilation, kernel compilation, and time to first MCS are performance
metrics distinct from steady-state throughput.

Compiled hot fields carry concrete storage types. Public signatures MAY remain generic and cross a
function barrier before hot execution.

## Workspaces and Preallocation

Stable GPU execution does not allocate lazily during the first MCS. `init` computes workspace needs
and allocates backend-owned buffers before steady-state execution.

Cache types follow the state scalar, accumulator, storage, and backend types. A hidden
`Vector{Float64}` is not valid behind a generic interface.

PreallocationTools MAY support demonstrated SciML or AD cache use cases. Core GPU workspaces remain
explicit rather than wrapping every buffer in a general lazy cache.

## Automatic Differentiation

Host reference and suitable Level 2 numerical code avoid gratuitous conversions that block dual or
other generic numbers.

Potts.jl does not claim that all CPM execution is differentiable. Copy acceptance, stochastic
discrete state, topology changes, lifecycle events, and fragmentation introduce discontinuities.

Differentiable subsets declare:

- The differentiated mathematical quantity
- Treatment of discrete state and randomness
- Supported numeric and backend types
- Required ChainRules, Enzyme, or other implementation
- Validation evidence

AD support does not impose caches, allocations, dynamic dispatch, or unsupported operations on the
primary simulation path. AD-specific caches are created only when an enabled capability requires
them. Compilation success alone is not a differentiability claim.

## Performance Qualification

`Float32` is the portable default, not an unmeasured universal speed claim. `Float64` remains a valid
scientific option on qualified hardware.

Mixed precision requires both end-to-end MCS benefit and numerical/statistical validation. A faster
isolated operation is insufficient.

Changes to numeric types, static arrays, or unrolling are inspected for register use, occupancy,
spilling, memory traffic, compile latency, and total throughput.

CPU and GPU MAY use different measured storage layouts behind stable accessors while preserving
scientific behavior.

Performance preferences never silently change precision, fast math, accumulation, reduction order,
overflow behavior, or scientific algorithm family.

## Numerical Conformance Matrix

Continuous integration covers at minimum:

- CPU `Float32`
- CPU `Float64`
- Every release-conforming GPU with `Float32`
- `Float64` on each backend that claims support
- Every accepted deterministic path
- Selected fast-policy statistical validation

Identical conformance workloads run across backends. Exclusions are explicit and prevent a backend
from claiming support for the excluded feature.

Tests cover local energy differences, acceptance boundaries, tracker updates, reductions, events,
exact invariants, RNG bits, conversions, and final statistical behavior—not only final images.

Tolerances are selected per quantity and numerical policy from analysis or empirical qualification.
There is no one package-wide `atol` and `rtol`.

Analytic results, integer invariants, higher-precision calculations, and versioned literature or
external fixtures serve as oracles where appropriate.

## Numerical Report

Every compiled run can report:

- Storage type for each state category
- Accumulator and result types
- Math policy
- Reduction policy and grouping guarantee
- Overflow and conversion rules
- Backend qualification
- Fast-math, subnormal, and contraction behavior
- Applicable tolerances and reproducibility level
- Every mixed-precision operation

Changing a policy recompiles when it changes types, arithmetic lowering, reduction order, or kernel
behavior. Reporting-only changes do not.

## Conformance Requirements

- Scientific code is generic while compiled hot structures are concrete.
- `Float32` is the visible portable default; explicit wider precision is preserved or rejected.
- Backends never choose precision or approximations silently.
- Storage, accumulator, and result types are explicit.
- Integer state and raw RNG contracts remain exact.
- Overflow never wraps silently.
- Fast math is opt-in and reported.
- Reductions specify types, identities, empty behavior, and ordering guarantees.
- Strict paths avoid schedule-dependent floating atomics.
- Cross-backend floating comparison follows per-quantity numerical contracts.
- Unsupported precision and functions fail preflight without host fallback.
- Workspaces are concrete, preallocated, and backend owned.
- AD remains capability-scoped and does not burden the default engine.
- Numerical changes are judged by correctness, end-to-end performance, and compile cost.

## Primary Guidance

- [SciML Style Guide](https://docs.sciml.ai/SciMLStyle/)
- [SciML specialization levels](https://docs.sciml.ai/SciMLBase/stable/interfaces/Problems/)
- [Julia performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [CUDA.jl performance guidance](https://cuda.juliagpu.org/stable/tutorials/performance/)
- [KernelAbstractions kernel guidance](https://juliagpu.github.io/KernelAbstractions.jl/stable/kernels/)
- [AcceleratedKernels map-reduce](https://juliagpu.github.io/AcceleratedKernels.jl/stable/api/mapreduce/)
