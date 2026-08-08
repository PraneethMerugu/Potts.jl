#!/usr/bin/env julia

# Deterministic, bounded G5H-1 evidence for CorePotts memory and relationship
# integrity scaling. This is an evidence harness, not a performance benchmark or
# a GPU qualification lane.

using CorePotts
using Serialization
using SHA

const C = CorePotts.CompilerSPI
const B = CorePotts.BackendSPI
const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))

struct EvidenceBulkPolicy <: B.AbstractBulkComponentStatePolicy end

function B.validate_component_state(
        ::EvidenceBulkPolicy,
        state::AbstractArray{Float64},
        capacity::Integer,
    )
    size(state, ndims(state)) == capacity || throw(ArgumentError(
        "evidence component state does not match its fixed capacity"
    ))
    all(isfinite, state) || throw(ArgumentError(
        "evidence component state must remain finite"
    ))
    return nothing
end

function B.transition_component_state!(
        ::EvidenceBulkPolicy,
        state::AbstractArray{Float64},
        event::CorePotts.TransitionLifecycleEvent,
    )
    slot = Int(event.before.slot)
    increment = Float64(event.after.kind - event.before.kind)
    for index in axes(state, 1)
        state[index, slot] += increment
    end
    return state
end

function evidence_state_schema(name::Symbol, domain::Symbol, shape::Tuple)
    return C.StateBlockSchema(
        C.QualifiedResourceIdentity((), name),
        v"1.0.0",
        domain,
        Float64,
        shape,
        prod(shape),
        :structure_of_arrays,
        :provided_or_zero,
        :shape_and_finite,
        :logical,
        :preserve,
        :declared,
        :bounded_write,
        :adapt_storage,
        :copy,
        :logical_copy,
        :qualified,
        true,
    )
end

function evidence_descriptor_plan(side::Integer, cell_capacity::Integer)
    layout = C.StateLayout(C.StateBlockSchema[
        evidence_state_schema(
            :evidence_lattice_state, :lattice, (Int(side), Int(side))
        ),
        evidence_state_schema(
            :evidence_cell_state, :cell, (Int(cell_capacity),)
        ),
    ])
    return C.DescriptorExecutionPlan(
        (),
        layout,
        C.WorkspaceLayout(C.WorkspaceSchema[]),
        (),
        Any[],
        Int32(0),
        "g5h1-evidence-empty-descriptor-plan",
        C.HamiltonianDomainResources(0, 0),
    )
end

function evidence_lifecycle_descriptor()
    return C.LifecycleDescriptor{2, Float64}(
        Int32(1),
        UInt64(1),
        UInt64(1),
        C.CellKindLifecycleDomain,
        Int16(2),
        Int32(0),
        C.EveryMCSLifecycleCadence,
        Int32(1),
        C.TransitionCellLifecycleEffect,
        Int32(0),
        C.ErrorLifecycleInadmissible,
        Int16(3),
        Int16(1),
        C.NoLifecyclePlacement,
        Int32(0),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(0),
        C.NoLifecyclePartition,
        Int32(0),
        false,
        (0.0, 0.0),
        (0.0, 0.0),
        C.CanonicalLifecycleSide,
        UInt16(0),
        UInt16(0),
        Int16(0),
        Int16(0),
        Int32(1),
        Int32(0),
        Int32(1),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        Int32(0),
        false,
    )
end

function evidence_lifecycle_plan(cell_capacity::Integer)
    descriptors = C.LifecycleDescriptor{2, Float64}[
        evidence_lifecycle_descriptor(),
    ]
    return C.LifecycleExecutionPlan(
        descriptors,
        C.LifecycleEvaluatorStorage(Any[], Symbol[]),
        C.LifecycleStateRuleStorage(Any[]),
        C.LifecycleRelationshipRule[],
        (),
        NTuple{2, Int16}[],
        C.LifecycleRelationStorage(Any[], Val(2)),
        C.StablePriorityLifecycleConflicts,
        cell_capacity,
        cell_capacity,
        1,
        0,
        falses(3),
    )
end

function evidence_program(
        side::Integer,
        cell_capacity::Integer;
        relationship_capacity::Integer = cell_capacity,
        maximum_degree::Integer = 4,
    )
    T = Float64
    offsets = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    relationships = (
        C.RelationshipStoreSchema(
            relationship_capacity, maximum_degree, ()
        ),
    )
    trackers = C.TrackerExecutionPlan(
        (C.OwnershipCountTracker(),),
        "g5h1-evidence-ownership-tracker",
    )
    return C.CompiledPottsProgram(
        (Int(side), Int(side)),
        (true, true),
        offsets,
        3,
        1,
        C.CompiledScalar(T(3)),
        1,
        T[],
        relationships,
        trackers,
        evidence_descriptor_plan(side, cell_capacity),
        C.StageExecutionPlan(),
        B.SequentialProgramEngine(),
        B.CPUProgramBackend(),
        "g5h1-evidence-side-$(side)-cells-$(cell_capacity)-edges-$(relationship_capacity)";
        lifecycle_plan = evidence_lifecycle_plan(cell_capacity),
    )
end

function evidence_initial(side::Integer, cell_capacity::Integer)
    active_cells = min(64, Int(cell_capacity), Int(side)^2)
    ownership = zeros(Int32, Int(side), Int(side))
    for cell in 1:active_cells
        ownership[cell] = Int32(cell)
    end
    return CorePotts.ProgramInitialState(
        ownership,
        fill(Int16(2), active_cells);
        scalar_type = Float64,
        relationships = (nothing,),
    )
end

function evidence_runtime(side::Integer, cell_capacity::Integer)
    program = evidence_program(side, cell_capacity)
    initial = evidence_initial(side, cell_capacity)
    runtime = CorePotts.initialize_program(
        program,
        initial,
        Float64[],
        UInt64(0x5a17),
        UInt32(1),
    )
    return program, runtime
end

function serialized_size(value)
    io = IOBuffer()
    Serialization.serialize(io, value)
    return position(io)
end

function scientific_bank(runtime)
    return (
        runtime.ownership,
        runtime.cell_kinds,
        runtime.cell_generations,
        runtime.trackers,
        runtime.relationships,
        runtime.descriptor_state,
    )
end

function candidate_bank(runtime)
    workspace = runtime.engine_workspace
    return (
        workspace.ownership,
        workspace.cell_kinds,
        workspace.cell_generations,
        workspace.trackers,
        workspace.relationships,
        workspace.descriptor_state,
    )
end

function assert_two_bank_aliasing(runtime)
    candidate = runtime.engine_workspace
    lifecycle = runtime.lifecycle_workspace
    @assert runtime.ownership !== candidate.ownership
    @assert runtime.cell_kinds !== candidate.cell_kinds
    @assert runtime.cell_generations !== candidate.cell_generations
    @assert runtime.trackers !== candidate.trackers
    @assert runtime.relationships !== candidate.relationships
    @assert runtime.descriptor_state !== candidate.descriptor_state
    @assert lifecycle.staged_ownership === candidate.ownership
    @assert lifecycle.staged_cell_kinds === candidate.cell_kinds
    @assert lifecycle.staged_cell_generations === candidate.cell_generations
    @assert lifecycle.staged_trackers === candidate.trackers
    @assert lifecycle.staged_relationships === candidate.relationships
    @assert lifecycle.staged_descriptor_state === candidate.descriptor_state
    return nothing
end

function runtime_memory_row(side::Integer, cell_capacity::Integer)
    program, runtime = evidence_runtime(side, cell_capacity)
    assert_two_bank_aliasing(runtime)
    snapshot = CorePotts.program_snapshot(runtime)
    checkpoint = CorePotts.program_checkpoint(runtime)
    active = scientific_bank(runtime)
    candidate = candidate_bank(runtime)
    engine = runtime.engine_workspace
    lifecycle = runtime.lifecycle_workspace
    engine_tuple_bytes = Base.summarysize((engine,))
    combined_tuple_bytes = Base.summarysize((engine, lifecycle))
    lifecycle_incremental_bytes = combined_tuple_bytes - engine_tuple_bytes
    @assert lifecycle_incremental_bytes > 0
    @assert Base.summarysize((active, candidate, lifecycle)) <
            Base.summarysize(active) + Base.summarysize(candidate) +
            Base.summarysize(lifecycle)
    layout = C.lifecycle_workspace_layout(
        program.lifecycle_plan, length(runtime.ownership)
    )
    return (
        side = Int(side),
        sites = length(runtime.ownership),
        cells = Int(cell_capacity),
        relationship_capacity = Int(only(program.relationships).capacity),
        runtime_bytes = Base.summarysize(runtime),
        active_bank_bytes = Base.summarysize(active),
        candidate_bank_bytes = Base.summarysize(candidate),
        lifecycle_incremental_bytes,
        snapshot_bytes = Base.summarysize(snapshot),
        checkpoint_bytes = Base.summarysize(checkpoint),
        checkpoint_serialized_bytes = serialized_size(checkpoint),
        request_slots = layout.request_slots,
        planned_site_slots = layout.planned_site_slots,
        cell_index_slots = layout.cell_index_slots,
        site_index_slots = layout.site_index_slots,
    )
end

function transition_receipt(count::Integer)
    events = CorePotts.LifecycleEvent[]
    for slot in 1:Int(count)
        request = CorePotts.QualifiedLifecycleRequestIdentity(
            slot, 1, slot, 1
        )
        before = CorePotts.CellIdentity(slot, 1, 2)
        after = CorePotts.CellIdentity(slot, 1, 3)
        push!(events, CorePotts.TransitionLifecycleEvent(
            request, before, after
        ))
    end
    return CorePotts.LifecycleReceipt(1, 1, events)
end

function bulk_memory_row(capacity::Integer, state_width::Integer = 1)
    capacity = Int(capacity)
    state_width = Int(state_width)
    state_width > 0 || throw(ArgumentError("component state width must be positive"))
    live = min(64, capacity)
    active = falses(capacity)
    active[1:live] .= true
    generations = zeros(UInt32, capacity)
    generations[1:live] .= UInt32(1)
    kinds = zeros(Int16, capacity)
    kinds[1:live] .= Int16(2)
    pool = B.BulkComponentStatePool(
        active,
        generations,
        kinds,
        zeros(Float64, state_width, capacity),
        EvidenceBulkPolicy(),
    )
    @assert pool.banks[1].state !== pool.banks[2].state
    receipt = transition_receipt(live)

    warmup = B.stage_lifecycle_receipt!(pool, receipt)
    B.abort_component_state_transaction!(warmup)
    stage_allocated = @allocated begin
        transaction = B.stage_lifecycle_receipt!(pool, receipt)
        B.abort_component_state_transaction!(transaction)
    end
    transaction = B.stage_lifecycle_receipt!(pool, receipt)
    transaction_incremental_bytes =
        Base.summarysize((pool, receipt, transaction)) -
        Base.summarysize((pool, receipt))
    B.abort_component_state_transaction!(transaction)
    return (
        capacity,
        live,
        state_width,
        pool_bytes = Base.summarysize(pool),
        active_bank_bytes = Base.summarysize(pool.banks[1]),
        inactive_bank_bytes = Base.summarysize(pool.banks[2]),
        receipt_bytes = Base.summarysize(receipt),
        transaction_incremental_bytes,
        stage_allocated_bytes = stage_allocated,
    )
end

function component_pool_projections(capacity_rows, width_rows)
    capacity_left, capacity_right = capacity_rows[end - 1], capacity_rows[end]
    width_left, width_right = width_rows[end - 1], width_rows[end]
    @assert capacity_left.state_width == capacity_right.state_width == 1
    @assert width_left.capacity == width_right.capacity
    per_state_cell_bytes =
        (width_right.pool_bytes - width_left.pool_bytes) /
        ((width_right.state_width - width_left.state_width) * width_right.capacity)
    one_width_per_cell_bytes =
        (capacity_right.pool_bytes - capacity_left.pool_bytes) /
        (capacity_right.capacity - capacity_left.capacity)
    metadata_per_cell_bytes = one_width_per_cell_bytes - per_state_cell_bytes
    fixed_bytes = capacity_right.pool_bytes - capacity_right.capacity *
                  (metadata_per_cell_bytes + per_state_cell_bytes)
    @assert per_state_cell_bytes == 2 * sizeof(Float64)
    @assert metadata_per_cell_bytes > 0
    target_cells = 10_000
    return map((1_000, 10_000)) do state_width
        projected = fixed_bytes + target_cells *
                    (metadata_per_cell_bytes +
                     per_state_cell_bytes * state_width)
        return (
            target_cells,
            state_width,
            per_state_cell_bytes,
            metadata_per_cell_bytes,
            projected_pool_bytes = round(Int, projected),
        )
    end
end

function ring_relationship_fixture(vertex_count::Integer)
    vertices = Int(vertex_count)
    vertices >= 3 || throw(ArgumentError("ring requires at least three vertices"))
    edges = vertices
    maximum_degree = 2
    schema = C.RelationshipStoreSchema(edges, maximum_degree, ())
    state = B.ProgramRelationshipState(
        Float64, edges, vertices, maximum_degree, 0
    )
    status = fill(Int16(2), vertices)
    generations = fill(UInt32(1), vertices)
    incident = [Int32[] for _ in 1:vertices]
    for edge in 1:edges
        raw_a = edge
        raw_b = edge == edges ? 1 : edge + 1
        a, b = minmax(raw_a, raw_b)
        state.active[edge] = true
        state.endpoint_a[edge] = Int32(a)
        state.endpoint_b[edge] = Int32(b)
        state.generation_a[edge] = UInt32(1)
        state.generation_b[edge] = UInt32(1)
        push!(incident[a], Int32(edge))
        push!(incident[b], Int32(edge))
    end
    for endpoint in 1:vertices
        sort!(incident[endpoint])
        @assert length(incident[endpoint]) == maximum_degree
        state.degree[endpoint] = Int16(maximum_degree)
        state.incident_edges[:, endpoint] .= incident[endpoint]
    end
    CorePotts.validate_relationship_integrity(
        state, schema, status, generations
    )
    return state, schema, status, generations
end

function relationship_validation_work_bound(state, schema)
    # Source-anchored bound for validate_relationship_integrity at fixed D:
    # two complete edge passes, one V*D incident pass, two E*D membership
    # scans, and at most one E*D duplicate scan. Scalar checks are omitted.
    E = length(state.active)
    V = length(state.degree)
    D = Int(schema.maximum_degree)
    return 2E + V * D + 3E * D
end

function assert_relationship_validation_structure()
    source_path = joinpath(
        REPOSITORY_ROOT,
        "lib",
        "CorePotts",
        "src",
        "program",
        "relationship_state.jl",
    )
    source = read(source_path, String)
    start_marker = "function validate_relationship_integrity("
    stop_marker = "@inline function relationship_payload("
    start_index = findfirst(start_marker, source)
    stop_index = findfirst(stop_marker, source)
    @assert start_index !== nothing && stop_index !== nothing
    body = source[first(start_index):(first(stop_index) - 1)]
    @assert length(findall("for edge in eachindex(state.active)", body)) == 2
    @assert occursin(
        "for position in 1:size(state.incident_edges, 1)", body
    )
    @assert occursin(
        "count(==(Int32(edge)), @view state.incident_edges[:, a])", body
    )
    @assert occursin(
        "for position in 1:Int(@inbounds state.degree[a])", body
    )
    return bytes2hex(SHA.sha256(codeunits(body)))
end

@noinline function validation_batch!(sink, fixture, repetitions::Integer)
    state, schema, status, generations = fixture
    started = time_ns()
    for _ in 1:Int(repetitions)
        sink[] = CorePotts.validate_relationship_integrity(
            state, schema, status, generations
        )
    end
    return time_ns() - started
end

function median_validation_ns(
        fixture; repetitions::Integer = 12, samples::Integer = 9
    )
    sink = Ref{Any}(nothing)
    validation_batch!(sink, fixture, 1)
    values = Int[]
    GC.gc()
    for _ in 1:Int(samples)
        push!(values, validation_batch!(sink, fixture, repetitions))
    end
    sort!(values)
    return values[(length(values) + 1) ÷ 2] ÷ Int(repetitions)
end

function relationship_scaling_rows()
    structure_hash = assert_relationship_validation_structure()
    sizes = (1024, 2048, 4096)
    fixtures = map(ring_relationship_fixture, sizes)
    rows = map(zip(sizes, fixtures)) do (vertices, fixture)
        state, schema, status, generations = fixture
        CorePotts.validate_relationship_integrity(
            state, schema, status, generations
        )
        allocated = @allocated CorePotts.validate_relationship_integrity(
            state, schema, status, generations
        )
        return (
            vertices,
            edges = length(state.active),
            maximum_degree = Int(schema.maximum_degree),
            state_bytes = Base.summarysize(state),
            work_bound = relationship_validation_work_bound(state, schema),
            median_ns = median_validation_ns(fixture),
            allocated_bytes = allocated,
        )
    end
    small = first(rows)
    large = last(rows)
    @assert large.edges == 4 * small.edges
    @assert large.maximum_degree == small.maximum_degree
    @assert large.work_bound == 4 * small.work_bound
    timing_ratio = large.median_ns / small.median_ns
    # Loose by design: a fixed-degree linear traversal should be near 4x for a
    # 4x fixture. A ratio below 10 is not a speed claim, but catches a clear
    # accidental E^2 validator (approximately 16x) after warmup and batching.
    @assert timing_ratio < 10.0
    return rows, structure_hash, timing_ratio
end

function emit_ring_creates!(buffer, vertex_count::Integer)
    vertices = Int(vertex_count)
    # Reverse emission is intentional: it prevents an already-canonical input
    # from hiding a quadratic request sorter.
    for edge in vertices:-1:1
        endpoint_a = edge
        endpoint_b = edge == vertices ? 1 : edge + 1
        B.emit_relationship_request!(
            buffer,
            B.CreateRelationshipRequest(
                endpoint_a,
                endpoint_b;
                generation_a = 1,
                generation_b = 1,
                identity = edge,
            ),
        )
    end
    return buffer
end

function relationship_transaction_fixture(vertex_count::Integer)
    vertices = Int(vertex_count)
    vertices >= 3 || throw(ArgumentError("ring requires at least three vertices"))
    schema = C.RelationshipStoreSchema(vertices, 2, ())
    state = B.ProgramRelationshipState(Float64, vertices, vertices, 2, 0)
    status = fill(Int16(2), vertices)
    generations = fill(UInt32(1), vertices)
    buffer = B.RelationshipTransactionBuffer(state, vertices)
    return state, schema, status, generations, buffer
end


@noinline function transaction_batch!(fixture, repetitions::Integer)
    state, schema, status, generations, buffer = fixture
    started = time_ns()
    for _ in 1:Int(repetitions)
        B.reset_relationship_transaction!(buffer, state)
        emit_ring_creates!(buffer, length(status))
        B.prepare_relationship_transaction!(
            buffer, status, generations, schema
        )
    end
    return time_ns() - started
end

function median_transaction_ns(
        fixture; repetitions::Integer = 4, samples::Integer = 7
    )
    transaction_batch!(fixture, 1)
    values = Int[]
    GC.gc()
    for _ in 1:Int(samples)
        push!(values, transaction_batch!(fixture, repetitions))
    end
    sort!(values)
    return values[(length(values) + 1) ÷ 2] ÷ Int(repetitions)
end

function relationship_transaction_scaling_rows()
    sizes = (1024, 2048, 4096)
    fixtures = map(relationship_transaction_fixture, sizes)
    rows = map(zip(sizes, fixtures)) do (vertices, fixture)
        state, schema, status, generations, buffer = fixture
        B.reset_relationship_transaction!(buffer, state)
        emit_ring_creates!(buffer, vertices)
        B.prepare_relationship_transaction!(
            buffer, status, generations, schema
        )
        CorePotts.validate_relationship_integrity(
            buffer.staged, schema, status, generations
        )
        B.reset_relationship_transaction!(buffer, state)
        emit_ring_creates!(buffer, vertices)
        allocated = @allocated B.prepare_relationship_transaction!(
            buffer, status, generations, schema
        )
        request_count = Int(buffer.count)
        D = Int(schema.maximum_degree)
        # Copy/reset O(E + V*D), heap sort O(Q*log Q), then bounded-degree
        # admission/index work O(Q*D). Constants are deliberately omitted.
        work_bound = length(state.active) + length(state.degree) * D +
                     request_count * max(1, ceil(Int, log2(request_count))) +
                     request_count * D
        return (
            vertices,
            edges = length(state.active),
            maximum_degree = D,
            requests = request_count,
            transaction_bytes = Base.summarysize(buffer),
            work_bound,
            median_ns = median_transaction_ns(fixture),
            allocated_bytes = allocated,
        )
    end
    small = first(rows)
    large = last(rows)
    @assert large.requests == 4 * small.requests
    @assert large.maximum_degree == small.maximum_degree
    @assert large.work_bound < 6 * small.work_bound
    @assert all(iszero(row.allocated_bytes) for row in rows)
    timing_ratio = large.median_ns / small.median_ns
    @assert timing_ratio < 10.0
    return rows, timing_ratio
end

function slope(left, right, axis::Symbol, metric::Symbol)
    dx = getproperty(right, axis) - getproperty(left, axis)
    dx > 0 || throw(ArgumentError("projection axis must increase"))
    return (getproperty(right, metric) - getproperty(left, metric)) / dx
end

function projected_row(site_rows, capacity_rows)
    site_left, site_right = site_rows[end - 1], site_rows[end]
    capacity_left, capacity_right = capacity_rows[end - 1], capacity_rows[end]
    reference = capacity_right
    target_sites = 512^2
    target_cells = 10_000
    metrics = (
        :runtime_bytes,
        :active_bank_bytes,
        :candidate_bank_bytes,
        :lifecycle_incremental_bytes,
        :snapshot_bytes,
        :checkpoint_bytes,
        :checkpoint_serialized_bytes,
    )
    values = map(metrics) do metric
        per_site = slope(site_left, site_right, :sites, metric)
        per_cell = slope(capacity_left, capacity_right, :cells, metric)
        projected = getproperty(reference, metric) +
                    per_site * (target_sites - reference.sites) +
                    per_cell * (target_cells - reference.cells)
        return (
            metric,
            per_site_bytes = per_site,
            per_cell_bound_bytes = per_cell,
            projected_bytes = round(Int, projected),
        )
    end
    return (
        target_sites,
        target_cells,
        reference_sites = reference.sites,
        reference_cells = reference.cells,
        values,
    )
end

function git_head()
    try
        return readchomp(`git -C $REPOSITORY_ROOT rev-parse HEAD`)
    catch
        return "unavailable"
    end
end

function git_dirty()
    try
        return !isempty(readchomp(
            `git -C $REPOSITORY_ROOT status --porcelain`
        ))
    catch
        return true
    end
end

function print_environment()
    println("[environment]")
    println("julia_version=", VERSION)
    println("machine=", Sys.MACHINE)
    println("kernel=", Sys.KERNEL)
    println("cpu=", Sys.CPU_NAME)
    println("threads=", Threads.nthreads())
    println("word_size=", Sys.WORD_SIZE)
    println("total_memory_bytes=", Sys.total_memory())
    println("git_head=", git_head())
    println("git_dirty=", git_dirty())
end

function print_named_row(section, row)
    println('[', section, ']')
    for key in keys(row)
        println(key, '=', getproperty(row, key))
    end
end

function main()
    print_environment()

    site_rows = map(side -> runtime_memory_row(side, 256), (64, 96, 128))
    capacity_rows = map(cells -> runtime_memory_row(128, cells), (256, 1024, 4096))
    for row in site_rows
        print_named_row("runtime_site_axis", row)
    end
    for row in capacity_rows
        print_named_row("runtime_capacity_axis", row)
    end

    for count in (0, 64, 256, 1024)
        receipt = transition_receipt(count)
        print_named_row("receipt_memory", (
            events = count,
            heap_bytes = Base.summarysize(receipt),
            serialized_bytes = serialized_size(receipt),
        ))
    end

    bulk_capacity_rows = map(
        capacity -> bulk_memory_row(capacity, 1), (256, 1024, 4096)
    )
    bulk_width_rows = map(
        width -> bulk_memory_row(1024, width), (1, 16, 64, 256)
    )
    for row in bulk_capacity_rows
        print_named_row("bulk_component_capacity_axis", row)
    end
    for row in bulk_width_rows
        print_named_row("bulk_component_width_axis", row)
    end
    for row in component_pool_projections(
            bulk_capacity_rows, bulk_width_rows
        )
        print_named_row("component_pool_projection", row)
    end

    relationship_rows, structure_hash, timing_ratio =
        relationship_scaling_rows()
    for row in relationship_rows
        print_named_row("relationship_validation", row)
    end
    print_named_row("relationship_guard", (
        validator_body_sha256 = structure_hash,
        large_to_small_timing_ratio = timing_ratio,
        timing_ratio_limit = 10.0,
        assertion_basis = "fourfold E/V at fixed maximum_degree",
    ))

    transaction_rows, transaction_timing_ratio =
        relationship_transaction_scaling_rows()
    for row in transaction_rows
        print_named_row("relationship_transaction", row)
    end
    print_named_row("relationship_transaction_guard", (
        large_to_small_timing_ratio = transaction_timing_ratio,
        timing_ratio_limit = 10.0,
        allocation_limit_bytes = 0,
        assertion_basis =
            "fourfold reverse-ordered Q/E/V at fixed maximum_degree",
    ))

    projection = projected_row(site_rows, capacity_rows)
    for value in projection.values
        print_named_row("projection", merge((
            target_sites = projection.target_sites,
            target_cells = projection.target_cells,
            reference_sites = projection.reference_sites,
            reference_cells = projection.reference_cells,
        ), value))
    end
    println("[result]")
    println("status=pass")
    println("claim=bounded_cpu_evidence_only")
end

main()
