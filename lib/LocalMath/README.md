# LocalMath.jl

> **Development disclosure:** Substantial portions of this pre-release codebase,
> tests, and documentation were developed with generative-AI assistance and
> remain subject to maintainer review.

New users can run the complete [ten-minute CPU
quickstart](docs/src/learn/localmath-quickstart.md) before reading the
compiler and execution details below.

`LocalMath` is the typed spatial and publication layer beneath bounded
local scientific computations. A program says:

- which finite `Space` owns each item;
- which typed `Field`s hold scientific values;
- which bounded `Relation`s connect spaces;
- which fields a `Stage` gathers;
- which conflict law publishes each result; and
- which finite sequence of stages forms the local calculation.

The package validates that meaning once, lowers it to one typed execution
plan, and launches only KernelAbstractions kernels on CPU and GPU. Domain
packages retain physics, clocks, semantic RNG, transactions, solvers,
checkpoints, and distributed policy.

## One typed waist

The central representation is `LocalLaw`, containing an ordered tuple of
typed `Stage`s. There is no parallel topology object, route-symbol program,
backend-specific program, or old/new execution selector.

```text
domain compiler or mathematical notation
                    ↓
                 LocalLaw
                    ↓
        plan → prepare → execute! → wait
                    ↓
          KernelAbstractions CPU/GPU
```

The ordinary mathematical form translates field notation directly into typed
`Stage` values. Domain compilers may construct `LocalLaw(stage)` explicitly;
there is no separate macro escape hatch or execution path:

```julia
law = @localmath (i ∈ cells;
        parameters = (dt::Float32,)) begin
    neighborhood = density[neighbors(i)]
    next_density[i] = update(neighborhood, dt)
end
```

`field[i]` is a required identity read, `field[relation(i)]` is a required
bounded gather, and `samples(field[relation(i)])` retains explicit presence,
boundary, and endpoint facts. Assignment lowers to `Unique`; `+=` lowers to a
canonical `Reduce`. `resolve_to`, `bounded_collect`, `@ordered`, and explicit
`publish(...; route, key, law)` cover resolution, finite collection, ordered
recurrence, and runtime routing. `bounded_collect(record; maximum, group,
groups)` keeps an explicit dense runtime group key separate from the stored
record. Authored resolution accepts `sense=:min` or `sense=:max`, an explicit bounded tie field, and an exact
empty result, for example
`resolve_to(; score=depth[i], tie=identity[i], payload=color[i],
onempty=UInt32(0))`; the lowest tie wins among equal scores. Several equations become named publication
ports, while nested `@stage` blocks become the existing finite stage tuple.

The macro is syntax translation only. Its parser records are discarded during
expansion, every descriptor is evaluated once, and no syntax object reaches
planning or a kernel.

## Spatial values

`Space(shape)` defines an ordinary finite index set. Domain compilers may use
`Space(Tag, shape)` when the domain kind itself carries durable scientific
meaning. `Field(space, T)` defines a logical value of type `T` at every point
in that space. These descriptors contain scientific structure, not arrays.

```julia
cells = Space((nx, ny))
padded = Space(PaddedTag, (nx + 2, ny + 2))

density = Field(cells, Float32)
padded_density = Field(padded, Float32)
```

Relations carry bounded connectivity and endpoint provenance:

```julia
self = IdentityRelation(cells)
neighbors = FixedRelation(cells => padded; degree = 5)
stream = AffineRelation(cells => padded; offsets = ((0, 0), (1, 0)))
path = compose(first_relation, second_relation)
```

For structured grids, compact Cartesian notation is a front-end spelling for
the same affine relations:

```julia
law = @localmath (i, j) ∈ interior(cells, 1) begin
    laplacian[i, j] = u[i - 1, j] + u[i + 1, j] +
                      u[i, j - 1] + u[i, j + 1] - 4u[i, j]
end
```

`interior(space, halo)` and `periodic(space)` are explicit authoring bounds.
Only static binder offsets are admitted; they lower to bounded affine
relations with exact directional footprints. No Cartesian storage or stencil
executor is introduced.

Available structural families include identity, affine, fixed, runtime,
masked, selected, inverse, product, composed, boundary, and packed relations.
Composition validates every adjacent space and preserves the product degree
bound. It does not precompute a hidden adjacency table.

Physical endpoint arrays are attached later during preparation. Planning validates
their schema and contents and mints package-owned `RelationProof`s. Execution
uses concrete device views and generation-qualified receipts; it never
reconstructs a host topology object on a warm path.

Direct fixed-topology arrays without a generation/status declaration are
immutable borrows on CPU and GPU: LocalMath validates them when binding and
callers must not mutate their contents for the lifetime of the bound law.
Relations whose contents change use
`LocalMath.MutableRelationStorage(storage; generation, status,
validated_generations, slot)` so the same validation contract remains
device-resident on CPU and GPU. Status and validated-generation arrays may be
omitted only when an explicit backend is available to allocate them cold.

## Local reads and publication laws

`Access(field, relation)` means a bounded gather from the current stage item.
Each evaluator receives only its declared gathered views, its typed parameters,
and the source item. An evaluator must be a concrete, structurally
device-admissible callable; capturing arrays or opaque runtime graphs is
rejected.

A publication law states the mathematics of competing writes. The common
waist supports:

- `Unique`: exact or partial assignment with proved destination ownership;
- `Reduce`: deterministic ordered folds or explicitly relaxed qualified folds;
- `Resolve`: argmin/argmax with payload, total rank bounds, tie-breaking, and
  explicit empty behavior;
- `Collect`: bounded canonical materialization with grouping and provenance;
- `OrderedFold`: exact canonical sequential recurrence over mutable state.

These are general operators, not Potts-, LBM-, LSM-, or FEM-specific features.
One evaluator may publish several ports under different laws. Ordered stage
composition remains finite and typed.

`Control` supplies bounded prefix, mask, subset, and device-gate selection.
False participation never calls the evaluator and never publishes a value.

## Collections

`Collection(T, capacity)` represents one bounded dynamic result. Its only
runtime authority is `CompactedStorage`, containing records, one device count,
optional group starts, source item/lane provenance, and an optional inverse
source-position projection.

Downstream stages consume collections without host settlement:

- `CollectionCount(collection)` reads the device-resident live prefix;
- `CollectionAccess(collection, BoundedGroup(K))` reads one bounded group;
- `SourcePositionAccess(collection, lane=1)` reads one selected producer-lane
  position; planning resolves and validates the producer's full emission width.

Ordinary notation spells these same reads as
`bounded(collection[i]; maximum=K)` and
`source_position(collection, i; lane=k)`. Bounds and lanes are static authoring
facts; no dynamically typed collection view reaches a kernel.

The planner requires the exact preceding producer and proves capacity,
occupancy, and projection compatibility. CPU and GPU use the same packed
storage and the same execution path.

## Ordered state

Ordered recurrence declares both its total order and exact initial state:

```julia
law = @localmath event ∈ events begin
    first = first_site[event]
    second = second_site[event]

    @ordered (
        by=(ordinal[event], identity[event]),
        state=(occupancy => occupancy_initial,
               accepted => accepted_initial),
    ) begin
        admitted = occupancy[first] == 0 && occupancy[second] == 0
        if admitted
            occupancy[(first, second)] = (label[event], label[event])
        end
        accepted[event] = Int32(admitted)
    end
end
```

Declared state reads observe the accumulated ordered prefix. Scalar and tuple
assignments lower to statically bounded writes, and conditional assignments
produce zero writes when false. `target => target` means explicit in-place
initialization, `by=:source` selects source order, and `halt_when(condition)`
terminates later steps. The macro generates a concrete isbits transition for
the existing `OrderedFold`; no transaction object or runtime AST is created.

## Preparation and execution

Ordinary authors prepare storage with one lexical assignment block. The left
side is the existing descriptor; the right side is caller-owned storage or an
explicit cold allocation:

```julia
prepared = @prepare (
    law;
    backend = KernelAbstractions.get_backend(source_array),
    lease_capacity = 3,
) begin
    source_field = source_array
    result_field = result_array
    neighbors = (endpoints = endpoint_array, counts = count_array)
end
receipt = execute!(prepared; parameters = parameter_values)
wait(receipt)
```

`@prepare` is syntax-only lowering to `prepare(law, descriptor_pairs...;
backend, ...)`. Every expression is evaluated once in ordinary Julia order;
no setup value survives macro expansion. The Pair form remains canonical for
dynamically generated compiler bindings.

Storage-free computed relations are derived from the law and need no binding.
The explicit `bind` and `plan` operations remain available to domain
compilers, inspection tooling, and code that intentionally controls those cold
boundaries; they accept the same flat descriptor-pair sequence.

Caller-owned arrays are used exactly as supplied. Cold, LocalMath-owned
storage is explicit and backend-qualified:

```julia
prepared = @prepare (law; backend) begin
    source_field = allocate(host_source)
    result_field = allocate(undef)
    neighbors = allocate((
        endpoints = host_endpoints,
        counts = host_counts,
    ))
    records = allocate()
end

result_array = LocalMath.storage(prepared, result_field)
```

A fixed relation may use its endpoint array directly when no per-source count
array is needed. Mutable topology keeps its receipt state explicit:

```julia
prepared = prepare(law,
    neighbors => LocalMath.MutableRelationStorage(
        LocalMath.Allocate((; endpoints = host_endpoints));
        generation = LocalMath.Allocate(UInt64[1]),
    ),
    field_pairs...;
    backend,
)
```

`Allocate(value)` fills only when `value` has the exact field element type;
an exact-shape, exact-element-type array is copied into independent storage.
`Allocate()` derives the precise bounded `CompactedStorage` of a produced
Collection. Allocation and copying finish during cold preparation; allocation
declarations never reach planning, preparation, or execution. An uninitialized
field is admitted only when stage order proves that a total unconditional
identity `Unique` publication initializes it before every use.

Record-valued Fields use ordinary concrete isbits structs. A direct
`StructArray` is borrowed with object identity intact; `allocate(struct_array)`
recursively copies its component arrays onto the explicit backend and returns
an independent `StructArray` with the same logical shape and element type.

The lifecycle has one authority:

1. `prepare(law, descriptor_pairs...; backend)` composes the existing cold
   binding, planning, and preparation operations without another object or
   execution path.
2. Binding either retains caller storage or explicitly materializes requested
   scientific storage; planning validates descriptors, relations, aliasing,
   laws, and lowering.
3. Preparation allocates or binds the exact bounded workspace and seals
   callable methods for the selected backend.
4. `execute!` appends the typed kernel sequence without an intermediate host wait.
5. `wait(receipt)` synchronizes and drains the cumulative submitted prefix.

Use `waitall(receipts...)` to settle several prepared plans sharing the same
backend/device/task scope with one provider synchronization. Use
`submission_capacity(prepared)` to preflight the bounded lease ledger.

## Inspection

`LocalMath.inspect` is public but intentionally unexported. It reports the
stage origins, laws, executor family, field dependencies, relation proofs,
workspace requirements, stage-local compiler spine, parameter ABI, backend
environment, callable admission, and receipt state.

```julia
facts = LocalMath.inspect(prepared)
facts.stages                         # semantic stages plus planning projections
facts.relations                      # validated topology and footprint facts
facts.planning.stage_phases          # current physical implementation
facts.realized.callback_methods      # concrete callable admission
```

Focused projections use the same canonical facts:

```julia
relations = LocalMath.inspect(prepared; level=:relations)
numerics = LocalMath.inspect(prepared; level=:numerics)
memory = LocalMath.inspect(prepared; level=:memory)
kernels = LocalMath.inspect(prepared; level=:kernels)
compiler = LocalMath.compilation_report(prepared)
```

`compilation_report` reports structural specialization and realized method
facts. It never predicts wall time or participates in planning.

Descriptors also have compact REPL displays. A `Field` shows its element type,
space extent, and abbreviated semantic identity; a `Relation` shows its family,
domain and codomain, degree, and whether physical storage is required.
Displaying a law, plan, or prepared plan summarizes descriptors, stages,
provenance, workspace, storage ownership, and physical segments without
planning, submitting, or synchronizing work.

If setup is incomplete, canonical binding reports all missing Fields, stored
Relations, and Collections in scientific encounter order. Fixed-topology
errors include the expected lane/domain layout and actual storage shape. The
manual's “LocalMath relations and storage” page contains the topology
selection table and complete binding examples.

Inspection is a cold, read-only projection, not a second semantic
representation. Production planning and execution never consume it. Semantic
fields describe the law; planning and realized fields describe the current
implementation. The `0.2` contract freezes their documented meaning, while
later compatible releases may add descriptive fields.

## Backend contract

All package-owned execution uses KernelAbstractions. Vendor packages supply
array types and a backend, but LocalMath contains no raw Metal, CUDA, AMDGPU,
or oneAPI launch/synchronization path. The same typed lowering is used on CPU
and GPU. The release suite executes on CPU and Metal; other conforming
KernelAbstractions providers remain architecturally admissible but are not
qualified or claimed by this release.

Warm execution owns only prepared typed views, bounded workspace, and receipt
state. Cold host descriptors and serialization values must be converted before
planning or preparation; conversion is forbidden during queued execution.

## Scientific ownership

LocalMath owns bounded gathering, local evaluation, routing, assignment,
folding, resolution, collection, ordered recurrence, composition, validation,
workspace, and execution lifetime. It does not absorb domain meaning.

For example, CorePotts retains Hamiltonian source order, before/after proposal
semantics, semantic RNG, Metropolis acceptance, MCS scheduling, lifecycle
transactions, checkpoint continuation, and CPM capability claims. LBM retains
collision and boundary-model meaning; LSM retains constitutive and fracture
meaning; FEM retains weak-form and solver meaning.

That boundary is intentional: many scientific languages can lower to one
small local-computation waist without turning LocalMath into a universal
simulation framework.
