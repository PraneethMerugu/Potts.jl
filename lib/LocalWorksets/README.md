# LocalWorksets.jl

`LocalWorksets` runs bounded local operations over validated connectivity. It
sits one layer above
[`KernelAbstractions.jl`](https://github.com/JuliaGPU/KernelAbstractions.jl):
KernelAbstractions owns portable kernel launch and implicit ordering;
LocalWorksets owns topology validation, output-conflict semantics, bounded
workspace, submission lifetime, and inspection. A domain package still owns
its physics, clocks, RNG, transactions, and checkpoints.

The public lifecycle is deliberately small:

```julia
workplan = plan(work, topology; backend)
prepared = prepare(workplan, storage; workspace)
event = run!(prepared, submission)
wait(event)
```

`plan` validates a reusable declaration and immutable topology. `prepare`
attaches actual arrays, submission slots, and either package-allocated or
caller-provided bounded workspace. `run!` appends work without a host wait.
`wait(event)` performs the one portable `KernelAbstractions.synchronize`
needed to make the cumulative submitted prefix visible.

## A complete single-output example

```julia
using KernelAbstractions
using LocalWorksets
import LocalWorksets: inspect

struct Scale
    factor::Int32
end

function (operation::Scale)(item::Int32, reads, values)
    emit(@inbounds(reads.source[item]) * operation.factor)
end

work = localwork(
    Scale(Int32(3)),
    1:3,
    :scaled => independent(:route; value_type = Int32);
    read = (source = :source,),
)

topo = topology(
    work;
    epoch = UInt64(1),
    routes = (route = reshape(Int32[2, 3, 1], 1, 3),),
    destination_counts = (scaled = 3,),
)

storage = (
    source = Int32[4, 5, 6],
    scaled = fill(Int32(-1), 3),
)
backend = KernelAbstractions.CPU()
workplan = plan(work, topo; backend)
prepared = prepare(workplan, storage)
event = run!(prepared)
wait(event)

@assert storage.scaled == Int32[18, 12, 15]
```

This concise form is only syntax: it lowers to the same named-port model as
the package-author form below.

## Named outputs and explicit numerical semantics

A local operation returns a named tuple whose names exactly match its output
ports. Every port states how its emissions reach destinations:

- `independent`: destinations have no competing writers. `coverage=:all`
  requires exact coverage; `coverage=:partial` preserves a destination when
  its fixed lane does not emit.
- `combined`: contributions are folded with an explicit
  `deterministic(operation, identity)` or `fast(operation, identity)` law.
  A bare floating-point `+` is rejected.
- `resolved`: one candidate wins by a bounded total rank followed by a
  canonical semantic identity. A destination with no candidate receives the
  declared `empty` value.

`emit(value, false)` and `candidate(rank, value, false)` mean no emission.
They do not contribute an identity, empty value, or masked write.

The complete lattice-spring example exercises all three port kinds in one
operation: edge state is independent, two endpoint forces are explicitly
combined, and fracture proposals are resolved. Its topology names every route
and supplies semantic identities for resolution:

- [lattice-spring authoring example](../../test/localworksets_witnesses/lattice_spring.jl)

The same directory contains complete, directly runnable CPU examples for:

- [D2Q9 stream/collide](../../test/localworksets_witnesses/lbm_d2q9.jl)
- [matrix-free FEM element application](../../test/localworksets_witnesses/matrix_free_fem.jl)
- [keyed z-buffer resolution](../../test/localworksets_witnesses/zbuffer.jl)
- [all cross-domain examples together](../../test/localworksets_witnesses/runtests.jl)

The CorePotts conjunctive proposal example is intentionally a domain adapter,
not a public LocalWorksets convenience. CorePotts retains proposal evaluation,
acceptance, RNG, settlement, checkpoint, and canonical Hamiltonian-folding
semantics:

- [CorePotts checkerboard adapter](../CorePotts/src/execution/checkerboard_program.jl)
- [CorePotts parity and continuation tests](../CorePotts/test/test_program_v1_localworksets_vertical.jl)

## Construction and binding

`topology(work; ...)` derives only `item_count`. The caller explicitly owns the
topology epoch, route matrices, destination counts, and resolved semantic IDs.
This prevents an empty destination or a stale topology from being inferred
away.

Static storage is an ordinary named tuple. Submission-time values and arrays
are declared during `prepare` with `value_slot` and `storage_slot`, then passed
to `run!`. A storage slot freezes element type, dimensionality, shape, strides,
access, backend, and device/context. Writable aliases are rejected.

For example, a reusable preparation with one bounded scalar and one dynamic
read array is written explicitly as:

```julia
template = zeros(Int32, 3)
prepared = prepare(
    workplan,
    (scaled = zeros(Int32, 3),);
    submission = (
        active_count = value_slot(
            Int32; bounds = Int32(0):Int32(3)
        ),
        source = storage_slot(template; access = :read),
    ),
    lease_capacity = 2,
)

event = run!(prepared, (
    active_count = Int32(3),
    source = Int32[4, 5, 6],
))
wait(event)
```

The submission names and types must match exactly. A differently shaped or
aliased dynamic array rejects before a lease is occupied.

Omitting `workspace` asks `prepare` to allocate the exact validated scratch
once with `KernelAbstractions.allocate`. Pass `lease_capacity=n` when more than
one unwaited submission must remain live. Advanced callers may instead pass an
explicit workspace; `run!` never allocates or grows it.

An explicit caller-owned workspace has the same structure reported by
`LocalWorksets.inspect(workplan).workspace` and always includes bounded host
receipt slots:

```julia
workspace = (
    records = (
        total = (
            values = Vector{Int32}(undef, record_capacity),
            valid = Vector{Bool}(undef, record_capacity),
        ),
    ),
    leases = Any[nothing, nothing],
)
prepared = prepare(workplan, storage; workspace)
```

The exact record fields are output-family specific; automatic preparation is
the normal choice when callers do not need to own these arrays. The expert
workspace keyword is stable, but lowering-specific record-leaf names and
nesting are not a second public authoring API: construct them from the exact
plan inspection for the package version being qualified. LocalWorksets does
not promise source compatibility for an internal record layout merely because
it is inspectable.

Ordered stages use `sequence(stage1, stage2)` or `sequence((stage1, stage2))`.
The spellings are identical. Ordering and intermediate visibility come from
sequential launches on one KernelAbstractions backend lane; LocalWorksets adds
no intermediate host wait, barrier node, queue, stream, or scheduler.

## Inspection

`LocalWorksets.inspect` is public but intentionally unexported so it does not
collide with the inspection functions of domain packages. It is
non-synchronizing at every lifecycle stage:

```julia
LocalWorksets.inspect(work)       # declarations and authoring level
LocalWorksets.inspect(workplan)   # lowering, launches and guarantees
LocalWorksets.inspect(prepared)   # bindings, workspace, lane and poison state
LocalWorksets.inspect(event)      # cumulative lane-tail receipt and serial
```

`show` is intentionally short; `inspect` is the complete machine-readable
report. Plan, preparation, and event reports retain the complete flat evidence
fields and also derive an author-oriented organization from those same facts:

```julia
facts = LocalWorksets.inspect(prepared)
facts.summary        # lifecycle, family, backend, poison state
facts.outputs        # exact per-port semantics and empty behavior
facts.execution      # lowering, phases, launches, determinism, lane/event scope
facts.memory         # planned/actual workspace, transfers, ownership, identities
facts.qualification # environment and selected-device compilation status
```

These groups are views of the authoritative validation/lowering evidence, not
a separately maintained evidence graph.

## Extension boundary

External packages extend LocalWorksets by supplying concrete isbits callable
operations with a device-compatible
`(item::Int32, reads, values)` method. They may use the public declarations above without
editing LocalWorksets. Combination and resolution declarations are semantic
claims only: an external type or method cannot authorize a backend, atomics,
host fallback, synchronization, allocation, or a new lowering. The central
planner must recognize and qualify the exact backend × element type × operation
× address-space profile.

The provider and lowering execution source is vendor-neutral; reviewed
qualification metadata is intentionally provider-specific. Current runtime qualification
is intentionally narrower: CPU and Apple M1 Metal are tested; CUDA and ROCm are
not claimed merely because the kernels use JuliaGPU-compatible source.

All statically knowable declaration, schema, capability, binding and workspace
faults reject during `plan` or `prepare`. KernelAbstractions does not expose a
portable compile-only operation for GPU backends: a selected-device compiler
fault can therefore first be reported by `run!`. Such a failure poisons the
cumulative provider scope and output visibility follows the inspected
lowering-specific partial-visibility contract. This is not host fallback.
Provider-specific compile preflight would require a separately reviewed,
fail-closed provider protocol; LocalWorksets does not use vendor hooks to
simulate one.

`LocalWorkValidationError` is the stable public exception for validation and
admission failures. Its stable fields are `stage`, `contract`, `port`,
`binding`, `workspace_leaf`, `expected`, `actual`, and `hint`; fields that do
not apply are `nothing`. `showerror` remains concise for interactive use.
Declaration-constructor misuse still follows Julia convention and throws
`ArgumentError`; validated lifecycle failures use the structured exception.
Once a launch may have entered the provider, callers must inspect
poison/failure state and create a fresh preparation rather than trying to
recover or transfer the cumulative lane receipt.

## Legacy resolved compatibility

New authoring uses one resolved-output language:

```julia
resolved(...)
candidate(rank, value, condition)
```

`masked`, the named-family resolved descriptor, its flat topology record,
caller workspace layout, and four-launch lowering remain together only as a
bounded compatibility path. They are closed to new consumers. They may be
deprecated only after generic `resolved`/`candidate` work proves every mask,
active-prefix, empty-result, stale-topology, lifetime, inspection, CPU/Metal,
launch/allocation, and direct-performance obligation; all internal consumers
must then migrate through one warned release before removal. CorePotts'
conjunctive two-owner claim remains a private domain adapter and is not a
second scientific-user resolved language.
