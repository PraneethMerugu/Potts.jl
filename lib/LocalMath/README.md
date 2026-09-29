# LocalMath.jl

> **Development disclosure:** Substantial portions of this pre-release codebase,
> tests, and documentation were developed with generative-AI assistance and
> remain subject to maintainer review.

LocalMath is a typed language and execution layer for bounded local scientific
computation. It represents finite spaces, fields, topology, conflict laws, and
ordered publication independently of any one scientific domain. One validated
lowering targets KernelAbstractions on CPU and GPU.

Domain packages retain their physics, clocks, random-number semantics, solvers,
transactions, checkpoints, and distributed policy.

```text
mathematical notation or a domain compiler
                    ↓
                 LocalLaw
                    ↓
        bind → plan → prepare → execute!
                    ↓
          KernelAbstractions CPU/GPU
```

## Installation

LocalMath is currently a pre-release package. Develop it from its repository
until it is registered:

```julia
using Pkg
Pkg.develop(url="https://github.com/PraneethMerugu/LocalMath.jl")
```

## A complete local computation

```julia
using LocalMath
using KernelAbstractions

backend = KernelAbstractions.CPU()
cells = Space((6, 6))
u = Field(cells, Float32)
laplacian = Field(cells, Float32)

law = @localmath (i, j) ∈ interior(cells, 1) begin
    laplacian[i, j] =
        u[i - 1, j] + u[i + 1, j] +
        u[i, j - 1] + u[i, j + 1] - 4f0 * u[i, j]
end

host_u = reshape(Float32.(1:36), 6, 6)
prepared = @prepare (law; backend) begin
    u = host_u
    laplacian = allocate(0f0)
end

wait(execute!(prepared))
result = LocalMath.storage(prepared, laplacian)
```

The equation creates ordinary typed LocalMath values. `@prepare` is hygienic
syntax for descriptor-to-storage pairs; it does not introduce a builder or a
second execution path. Caller arrays are borrowed exactly as supplied, while
`allocate(...)` requests explicit cold LocalMath-owned storage on the selected
backend.

## Mathematical scope

LocalMath provides:

- required and presence-aware bounded gathers;
- unique assignment and deterministic or explicitly relaxed reduction;
- argmin/argmax resolution with payload and tie-breaking;
- bounded grouped collection with source provenance;
- finite ordered recurrence over explicit state;
- multiple publication ports and ordered stage composition;
- structured inspection of topology, storage, lowering, and physical launches.

Relations include identity, affine, fixed, boundary, indexed, selected,
inverse, product, composed, runtime, masked, and packed topology. Dynamic
topology remains packed and generation-qualified during execution.

## Execution guarantees

The current implementation has one packed KernelAbstractions execution path.
Preparation validates descriptors, storage, topology, callable admission,
aliasing, workspace, and backend requirements. Warm execution performs no
scientific storage allocation, relation packing, symbolic interpretation, or
host scalar round trip.

CPU and Metal are exercised by the current test suite. Other
KernelAbstractions providers are not claimed until independently qualified.

Inspection is a cold projection over the semantic law, validated plan, and
prepared runtime. Planning and execution never consume inspection reports.

## Learn more

- [Published documentation](https://praneethmerugu.github.io/LocalMath.jl/)
- [Ten-minute quick start](docs/src/learn/localmath-quickstart.md)
- [Relations and storage](docs/src/learn/localmath-relations.md)
- [Scientific recipes](docs/src/learn/localmath-recipes.md)
- [Troubleshooting](docs/src/learn/localmath-troubleshooting.md)
- [Domain compiler guide](docs/src/learn/localmath-domain-compiler.md)
- [API reference](docs/src/api/localmath.md)
- [Contributing](CONTRIBUTING.md)
- [Citation metadata](CITATION.cff)

LocalMath is MIT licensed.
