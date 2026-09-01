# LocalMath across domains

LocalMath is a typed language for bounded local reads and conflict-aware
publication. A domain model owns its scientific equations; LocalMath describes
where each local calculation reads and how its results become spatial state.

```julia
law = @localmath (cell ∈ cells; parameters=(dt::Float32,)) begin
    local_population = population[neighbors(cell)]
    next_population[cell] = collide(local_population, dt)
end
```

The same authoring and execution path is exercised by dimension-parametric
stencils, D2Q9 collision and streaming, lattice-spring mechanics, matrix-free
finite-element application, CIC/TSC deposition, graph gather and scatter,
bounded recurrence, deterministic routed resolution, and a focused Potts
proposal calculation. These examples use independent numerical oracles; the
oracle is not a second LocalMath executor.

Ordinary spaces need no marker type. Structured notation keeps the boundary
contract in the equation while lowering to existing affine relations:

```julia
cells = Space((nx, ny))
laplacian = @localmath (i, j) ∈ interior(cells, 1) begin
    Δu[i, j] = u[i - 1, j] + u[i + 1, j] +
               u[i, j - 1] + u[i, j + 1] - 4u[i, j]
end
```

Use `periodic(cells)` for periodic indexing. Offset indices must be static;
LocalMath neither guesses boundary behavior nor creates adjacency storage.

Resolution makes conflict semantics visible in the equation:

```julia
law = @localmath fragment ∈ fragments begin
    color[pixel(fragment)] = resolve_to(;
        score=depth[fragment],
        tie=identity[fragment],
        payload=rgba[fragment],
        lower=-100,
        upper=100,
        onempty=UInt32(0),
        when=covered[fragment],
    )
end
```

Equal scores select the lowest explicit tie. An exact `onempty` value is
published when no fragment participates; `onempty=:preserve` retains the
destination. Reduction order is likewise explicit: `order=:canonical` gives a
deterministic fold and `order=:relaxed` selects the relaxed atomic law where
the operation supports it.

Scientific storage remains explicit. Descriptors carry mathematical identity
and topology; the setup block associates those lexical descriptors with
caller-owned arrays or explicit cold allocation. LocalMath never guesses
initialization or silently allocates an omitted output.

```julia
prepared = @prepare (law; backend) begin
    population = allocate(host_population)
    next_population = allocate(undef)
    neighbors = allocate(host_neighbors)
end

wait(execute!(prepared; parameters=(dt=0.1f0,)))
next_values = LocalMath.storage(prepared, next_population)
```

Computed identity and affine relations require no placeholder binding. Stored
relations remain explicit because their endpoint arrays are scientific input.
Direct fixed-topology arrays are immutable borrows on CPU and GPU; LocalMath
validates their bounds once during cold binding and does not attach mutable
generation receipts or repeat that validation during execution.
Domain compilers and inspection tooling can still use the same flat pairs with
the explicit `bind` and `plan` operations when they need to observe
the intermediate cold boundaries.

The reserved top-level forms are `allocate()`, `allocate(undef)`, and
`allocate(value_or_source)`. Other right-hand expressions pass through as
ordinary storage values. Direct arrays, including `StructArray` record
storage, are borrowed without adaptation. Allocating a `StructArray` copies
its component arrays onto the explicit backend while preserving its element
type, shape, and component structure.

Bounded dynamic records stay on the device. A producer may request a persistent
source-position projection, and a later stage consumes the same collection
without host settlement:

```julia
law = @localmath begin
    @stage produce(p ∈ particles) begin
        records[p] = bounded_collect(record(p);
            maximum=1, group=cell(p), groups=ncells,
            projection=:source_position)
    end

    @stage consume(c ∈ cells) begin
        local_record = bounded(records[c]; maximum=1)
        mass[c] = length(local_record) == 0 ? 0f0 : local_record[1].mass
    end

    @stage project_source(p ∈ particles) begin
        record_position[p] = source_position(records, p; lane=1)
    end
end
```

`count(records)` is the number of live records, not the extent of the grouping
key domain, so grouped consumers iterate the complete `cells` space (or an
explicit dense remapping of occupied keys). The projection is consumed by
producer identity in the final stage. Its maximum and projection lane are
static facts and lower to the existing typed collection access laws.

Cartesian binder symbols currently appear only inside Field indices. Use
Fields or explicit parameters for coordinate-dependent coefficients; this
keeps coordinate meaning explicit until that grammar is extended.

Ordered state uses the same equation vocabulary while making initialization
and total order explicit:

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

Reads from `occupancy` in this block observe the accumulated ordered state,
not the stage-entry snapshot. Tuple assignment is a statically bounded write;
the `if` produces zero occupancy writes when admission fails. Use
`target => target` for explicit in-place initialization, `by=:source` for
source order, and `halt_when(condition)` for an ordered terminal step. The
macro produces the existing typed `OrderedFold`; it does not create a task
graph, transaction object, or second runtime.

Bounded neighborhood mathematics can be packaged as an ordinary concrete
callable while retaining explicit invalid, empty, and order semantics:

```julia
positive_geometric_mean = LocalMath.bounded_fold(
    log, +, 0.0, (sum, count) -> exp(sum / count);
    domain=LocalMath.Where(>(0)),
    oninvalid=LocalMath.RejectInvalid(),
    onempty=LocalMath.RejectEmpty(),
    order=LocalMath.CanonicalLeftFold(),
)
```

The operator consumes only a bounded gathered view or bounded collection
group. Its implementation is a concrete evaluator-side fold; no dynamic
iterator, allocation, or symbolic expression reaches a device kernel.

Advanced authors and domain compilers may construct qualified `Stage`,
`Publication`, and publication-law values directly. Those constructors lower
to the same `LocalLaw`, planner, packed storage, and KernelAbstractions path;
they are not an alternate runtime. Collection and recurrence notation is kept
only where the cross-domain witnesses proved that it preserves explicit bounds,
ordering, initialization, and conflict semantics.
