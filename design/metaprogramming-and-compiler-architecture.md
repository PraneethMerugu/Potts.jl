# Metaprogramming and Compiler Architecture Standard

Status: Draft engineering standard for the refactor

Current disposition: use this as compatible implementation guidance only. The public lifecycle,
late-lowering boundary, native MTK-component ownership, and current work order are governed by
[Decision 0044](../spec/decisions/0044-pre-g6-cohesion-and-mtk-hardening.md) and the
[G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md).

## Authority and Scope

This document governs how PottsToolkit authoring syntax is compiled into CorePotts execution. It is
an engineering standard, not a scientific semantics document. Implementations MAY change when
benchmarks or JuliaGPU capabilities change, but they MUST continue to realize the authoritative
contracts in `spec/`.

Device lowering, backend capabilities, synchronization, memory layout, and performance validation
are governed by the companion
[JuliaGPU and Performance Programming Standard](juliagpu-and-performance-programming-standard.md).

Deviations require a design note containing motivation, measured benefit, semantic-risk analysis,
fallback behavior, and tests.

## Governing Principle

> Macros provide syntax; typed IR provides meaning; ordinary functions provide behavior;
> specialization provides speed.

Metaprogramming is used to remove user boilerplate, not to hide scientific choices or substitute for
an explicit compiler pipeline.

## Package Responsibilities

### PottsToolkit

PottsToolkit owns:

- Friendly authoring objects and DSL syntax
- Parsing and source maps
- Typed semantic IR
- Model validation
- Unit and symbol resolution
- Dependency and effect analysis
- Compatibility preset expansion
- Normalized model reports
- Lowering to CorePotts descriptors

### CorePotts

CorePotts owns:

- Concrete compiled schemas and descriptors
- Reference scalar operations
- Transaction primitives
- Backend-neutral kernel algorithms
- Backend adaptation
- Execution diagnostics
- Conformance hooks

CorePotts MUST NOT parse user ASTs or depend on PottsToolkit macros.

### Extensions

Optional integrations live in package extensions and register explicit compiler or runtime
capabilities. Loading an extension MUST NOT redefine the meaning of an already compiled semantic node
without changing its registered version and semantic fingerprint.

## Compilation Pipeline

The required stages are:

```text
authoring syntax and objects
    -> parsed syntax with source locations
    -> typed semantic IR
    -> normalized validated model IR
    -> execution plan and dependency graph
    -> CorePotts compiled descriptors
    -> backend adaptation
    -> kernel compilation and preflight
    -> execution
```

Each stage has an inspectable data product and may emit diagnostics. A stage MUST NOT depend on
incidental AST shape from an earlier stage after typed IR exists.

## Macro Standard

Macros are thin syntax adapters. A macro SHOULD:

1. Capture input syntax without evaluating it.
2. Record `__source__` and `__module__`.
3. Escape user expressions exactly once at the intentional boundary.
4. Use hygienic internal bindings or `gensym`.
5. Call ordinary parsing or builder functions.
6. Return a small expression.

Macros MUST NOT:

- Call `eval` or `Meta.parse` on user content
- Define methods dynamically during model construction
- Perform backend detection
- Allocate device resources
- Read mutable global compiler registries without versioned APIs
- Generate the final numerical kernel body directly
- Pass unknown syntax through unchanged
- Encode semantic RNG identity as an incidental AST traversal offset

Macro behavior is tested with `macroexpand` from modules other than the defining module.

## Typed Intermediate Representation

IR nodes are immutable concrete data with source information. Representative categories include:

- Literals and symbolic references
- Scalar operations
- Property and parameter reads
- Conditional nodes
- Spatial queries
- Field samples
- Random draws
- Property results
- Lifecycle effects
- Diagnostics and explicit no-change

IR nodes contain meaning, not device storage. They do not hold arbitrary `Expr`, mutable dictionaries,
host closures, or backend arrays after normalization.

Every node supports ordinary functions for:

- Type and unit inference
- Validation
- Purity and effect classification
- Read/write dependency extraction
- RNG dependency extraction
- Capability collection
- Constant folding where safe
- Host reference evaluation
- Device lowering
- Stable reporting

One visitor/pass framework SHOULD implement cross-cutting traversal to keep analysis DRY. Individual
operations own local semantics through multiple dispatch.

## Registries and Extension Stability

Registries are host-side compiler services with explicit versioning and deterministic lookup.
Registration occurs during module loading, not inside generated functions or GPU compilation.

A registered operation supplies:

- Stable identifier and version
- IR node or lowering hook
- Validation and inference
- Reference implementation
- Capability declaration
- Device implementation
- Tests and documentation

Registration conflicts are errors. Compiler output fingerprints the resolved implementation version.
Mutable registry contents MUST NOT be observed by generated functions.

## Ordinary Functions First

Use ordinary Julia functions, multiple dispatch, function barriers, tuples, and static iteration
before considering code generation.

Preferred tools, in order, are:

1. Ordinary concrete dispatch
2. Small immutable callable structs
3. Tuple recursion or `ntuple`
4. Static arrays for genuinely small fixed data
5. Backend-resident descriptor arrays for larger data
6. Generated functions only with written justification

Performance claims require measurement on representative CPU, AMDGPU, and Metal paths where
supported.

## Generated-Function Policy

Every `@generated` method must have a nearby justification documenting:

- Why ordinary dispatch or static iteration is insufficient
- Which information is available only from argument types
- Expected specialization cardinality
- Compile-time and runtime benchmarks
- Code-size and register effects
- Reference or fallback implementation

A generated function MUST:

- Be pure
- Depend only on argument types and immutable constants
- Avoid I/O, locks, random numbers, mutable global state, and `eval`
- Avoid world-age-sensitive lookup
- Return deterministic code
- Preserve behavior under repeated or omitted generation
- Have equivalence tests against ordinary behavior

Optionally generated functions or ordinary fallbacks are preferred. CI SHOULD track their number and
prevent casual growth.

The current generated topology constructors should become host compiler constructors producing
validated descriptors. The current generated tuple rule evaluators should be replaced by ordinary
tuple recursion unless benchmarks demonstrate a necessary benefit.

## Type-Parameter and `Val` Policy

Type parameters are appropriate for small bounded structural facts that materially improve
inference, such as:

- Dimension
- Algorithm family
- Component category
- Precision policy
- Small fixed tuple length
- Static capability traits

Runtime scientific values, arbitrary radii, large stencil contents, parameter tables, seeds, and
model-specific numeric values SHOULD remain fields or descriptor data.

Constructing `Val(x)` is useful only when `x` is already inferable or deliberately crosses a
function barrier. Turning runtime values into unbounded types is forbidden.

Every compiler path has a specialization budget covering expected method instances, latency, native
code size, and cache behavior.

## Static and Descriptor Lowering

The compiler may choose between two equivalent paths:

- Static lowering for small, common, fixed descriptors
- Compact backend-resident descriptor lowering for larger or highly variable models

The cutoff is based on benchmarked compilation latency, register pressure, occupancy, code size, and
runtime. It may differ by algorithm and backend. It MUST NOT alter direction order, RNG identity,
floating operation policy, or scientific results beyond the declared numerical contract.

StaticArrays are used for small fixed mathematical objects, not as a blanket replacement for all
arrays. StructArrays are used where structure-of-arrays access matches kernels and lifecycle
requirements. Neither package defines public semantics.

## Closure Policy

Portable compiled models SHOULD contain typed IR and registered callable structs rather than
arbitrary closures.

An isbits closure is not automatically acceptable: it may still contain unsupported calls, unclear
effects, unstable identity, or backend-specific behavior. Closure environments must be inspected and
lowered before execution.

Host-only and expert-device closures use the explicit escape hatches defined by the rule semantics.
They provide source identity, effect sets, capabilities, and reference tests.

## RNG Lowering

Random draws are assigned semantic addresses during normalized IR construction. Device lowering
receives complete counter coordinates and distribution identifiers; it does not invent magic numeric
offsets.

Compiler transformations preserve draw identity. Common-subexpression elimination MUST NOT merge
independent random draws. Constant folding MUST NOT evaluate stochastic nodes. User labels and
compiler-generated identities are checked for collision.

## Effect and Dependency Analysis

Every rule or component produces explicit sets for:

- Property reads
- Property writes
- Lattice reads and writes
- Spatial relations
- Field reads and writes
- Tracker dependencies
- Lifecycle effects
- Random streams
- Synchronization requirements

The execution planner derives query precomputations, transaction phases, conflict footprints, field
synchronization, and backend capabilities from these sets. Kernel code is not reparsed to rediscover
dependencies.

Unknown effects reject portable compilation.

## Device Code Standard

Device operations use concrete dispatch with no unsupported dynamic invocation. Kernels are written
once through KernelAbstractions where its semantic and performance envelope is sufficient.
Backend-specific intrinsics live behind small, tested interfaces and implement a named generic
algorithm.

Device code MUST NOT perform:

- Host allocation or host array access
- Runtime reflection
- I/O
- Exception-driven ordinary control flow
- Method definition or `eval`
- Backend selection
- Unbounded recursion
- Implicit host fallback

Preflight compilation occurs before simulation work. Backend compiler failures are mapped through
source information to the originating model node where possible.

## Source Maps and Diagnostics

Source locations survive parsing, IR normalization, lowering, and kernel assembly. Generated internal
names never replace the user-facing model path in errors.

Diagnostics have stable categories and include:

- Authoring source
- Semantic node
- Compilation stage
- Backend when relevant
- Expected capability or type
- Suggested correction

Debug reports MAY show expanded syntax, normalized IR, dependency graphs, and lowered descriptors.
They MUST distinguish authoritative semantic data from compiler internals.

## Fingerprints and Caching

Compilation caches are keyed from normalized semantic meaning plus relevant implementation identity,
including:

- IR schema and operation versions
- Numerical policy
- Backend family and capability version
- Julia and package compatibility versions where code generation depends on them
- Extension implementation versions

Raw AST formatting, dictionary insertion order, object addresses, and unrelated host state do not
affect semantic fingerprints.

The exact stable cache/checkpoint contract remains a semantic decision under `SEM-DSL-005`.

## Testing Standard

### Syntax and IR

- Macro hygiene from external modules
- `macroexpand` snapshots for small public forms
- Parser tests independent of macros
- Source-location preservation
- Unknown-syntax rejection
- IR normalization and equality tests

### Semantics

- Host reference interpreter fixtures
- Snapshot and effect tests
- RNG address uniqueness and stability
- Dependency extraction tests
- Unit and type validation
- Model-report golden tests

### Lowering

- Reference interpreter versus CPU lowering
- CPU versus every supported GPU backend
- Static versus descriptor lowering
- Generic versus intrinsic algorithm equivalence
- Backend preflight failure diagnostics

### Compiler Quality

- Inference checks on kernel call graphs
- Invalid dynamic invocation checks
- Allocation checks
- Compile latency budgets
- Native code-size budgets
- GPU register and occupancy tracking
- Precompilation and world-age tests
- Cache hit and invalidation tests

Performance tests are separated from semantic conformance tests so an optimization regression cannot
be disguised as a semantic change.

## Review Checklist

A metaprogramming or compiler pull request answers:

1. Can this be an ordinary function?
2. Which semantic IR node owns the meaning?
3. Is the macro hygienic and minimal?
4. Are effects and RNG dependencies explicit?
5. Is specialization bounded?
6. Is there a non-generated reference behavior?
7. Does it compile on all claimed backends?
8. What are compile-time, code-size, register, and runtime costs?
9. Are source diagnostics preserved?
10. Does the semantic fingerprint change, and should it?

## Migration Priorities

1. Introduce source-located typed rule IR and a host reference evaluator.
2. Freeze the existing `@rule` path; implement Phase 10 entirely through ordinary Level 2 builders.
3. Reject unknown typed-rule operations instead of passing them through.
4. Assign semantic RNG identities and eliminate reused offsets.
5. Replace ambiguous query nodes with accepted spatial descriptors.
6. Add effect analysis and simultaneous property transactions.
7. Lower normalized IR to concrete CorePotts callable structs.
8. Replace unnecessary generated functions with ordinary implementations.
9. Add backend preflight and compiler-quality budgets.
10. After the replacement vertical slice reaches reference and CPU/Metal/ROCm parity, migrate
    library callers and tests and remove the closure-first/MLStyle prototype before broad Phase 10
    expansion. Phase 11 then implements a new thin macro front end over the accepted builders.

## Primary Guidance

- [Julia metaprogramming manual](https://docs.julialang.org/en/v1/manual/metaprogramming/)
- [Julia performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/)
- [KernelAbstractions kernel programming](https://juliagpu.github.io/KernelAbstractions.jl/stable/kernels/)
- [CUDA.jl kernel programming](https://cuda.juliagpu.org/stable/development/kernel/)
- [StaticArrays documentation](https://juliaarrays.github.io/StaticArrays.jl/stable/)
