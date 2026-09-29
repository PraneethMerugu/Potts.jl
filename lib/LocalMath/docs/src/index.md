# LocalMath.jl

LocalMath is a typed, bounded, conflict-aware language for local scientific
computation. It separates mathematical meaning from physical execution, then
runs the validated computation on CPU or GPU through one
KernelAbstractions execution path.

Use LocalMath when a model needs explicit finite domains, bounded topology,
storage ownership, publication conflicts, or ordered state evolution. Domain
packages still own their physics, clocks, random-number semantics, solvers,
transactions, checkpoints, and distributed policy.

## Install

LocalMath is currently a pre-release package. Develop it directly from its
repository:

```julia
using Pkg
Pkg.develop(url="https://github.com/PraneethMerugu/LocalMath.jl")
```

## A complete computation

This periodic finite-difference law is ordinary typed Julia code. Descriptors
state the mathematical problem; preparation associates them with concrete
storage and an explicit backend.

```@example home
using LocalMath, KernelAbstractions

cells = Space(6)
u = Field(cells, Float32)
laplacian = Field(cells, Float32)

law = @localmath i ∈ periodic(cells) begin
    laplacian[i] = u[i - 1] - 2f0 * u[i] + u[i + 1]
end

prepared = @prepare (law; backend=KernelAbstractions.CPU()) begin
    u = Float32[1, 2, 4, 7, 11, 16]
    laplacian = allocate(0f0)
end

wait(execute!(prepared))
result = LocalMath.storage(prepared, laplacian)
@assert result == Float32[16, 1, 1, 1, 1, -20]
nothing
```

Caller arrays are borrowed exactly as supplied. `allocate(...)` requests
explicit LocalMath-owned backend storage; omitted scientific storage is never
guessed or allocated during warm execution.

## Core vocabulary

| Concept | Responsibility |
|:--|:--|
| `Space` and `Field` | Finite domains and typed mathematical values |
| `Relation` | Bounded reads and publications between spaces |
| `LocalLaw` | Stages, gathers, equations, and publication semantics |
| `bind` and `plan` | Storage validation and backend-independent lowering |
| `prepare` / `@prepare` | Backend realization, workspace, and device storage |
| `execute!` | Asynchronous KernelAbstractions submission returning an `ExecutionReceipt` |

## One architecture, from equation to device

LocalMath keeps mathematical meaning and physical execution separate without
creating parallel representations:

```text
@localmath
    → LocalLaw
    → bind (validated descriptors and scientific storage)
    → Plan (backend-independent meaning plus a concrete lowering)
    → PreparedPlan (workspace, provider, and device realization)
    → KernelAbstractions launches
    → ExecutionReceipt
```

`inspect` and `compilation_report` project facts from those existing values;
execution never consumes a report. CPU and qualified GPU backends use the same
laws, validation, packed storage, and KernelAbstractions execution path.

LocalMath supports identity and structured relations, interior and periodic
stencils, fixed and dynamic topology, deterministic or explicitly relaxed
reductions, argmin/argmax resolution, bounded grouped collection, and finite
ordered recurrence. Preparation validates topology, callable admission,
aliasing, workspace, and backend support before submission. CPU and Metal are
exercised by the package test suite; other providers are not claimed until
independently qualified.

## Continue from here

| Goal | Guide |
|:--|:--|
| Run the first model and understand initialization | [Quick start](@ref localmath-quickstart) |
| Choose topology and bind scientific storage | [Relations and storage](@ref localmath-relations) |
| See stencils, scatter, resolve, collect, and recurrence | [Scientific recipes](@ref localmath-recipes) |
| Diagnose validation or execution failures | [Troubleshooting](@ref localmath-troubleshooting) |
| Lower another scientific package into LocalMath | [Writing a domain compiler](@ref localmath-domain-compiler) |
| Find the complete public and qualified interface | [API reference](@ref localmath-api) |
