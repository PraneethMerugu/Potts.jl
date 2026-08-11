import KernelAbstractions
import LocalWorksets

struct _LWSpringOperation end

function (::_LWSpringOperation)(item::Int32, reads, values)
    extension = @inbounds reads.extensions[item]
    edge_id = UInt32(item)
    return (
        edge_state = LocalWorksets.emit(
            extension > Int32(4) ? UInt32(2) : UInt32(1)
        ),
        force = (
            LocalWorksets.emit(Float32(extension)),
            LocalWorksets.emit(-Float32(extension)),
        ),
        fracture = LocalWorksets.candidate(
            extension, edge_id, extension > Int32(3)
        ),
    )
end

function run_lw_lattice_spring_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
        force_mode::Symbol = :deterministic,
    )
    extensions = Int32[2, 7, 5, 1]
    edge_route = reshape(Int32[4, 1, 3, 2], 1, 4)
    force_route = Int32[1 2 3 1; 2 3 4 4]
    fracture_route = reshape(Int32[1, 1, 2, 2], 1, 4)
    topology = (
        epoch = UInt64(2),
        item_count = 4,
        routes = (
            edge_route = edge_route,
            force_route = force_route,
            fracture_route = fracture_route,
        ),
        destination_counts = (
            edge_state = 4,
            force = 5,
            fracture = 3,
        ),
        semantic_ids = (
            fracture = reshape(UInt32[40, 10, 30, 20], 1, 4),
        ),
    )
    force_law = force_mode === :deterministic ?
        LocalWorksets.deterministic(+, Float32(0)) :
        force_mode === :fast ? LocalWorksets.fast(+, Float32(0)) :
        throw(ArgumentError("force_mode must be :deterministic or :fast"))
    work = LocalWorksets.localwork(
        _LWSpringOperation(),
        1:4;
        read = (extensions = :extensions,),
        outputs = (
            edge_state = LocalWorksets.independent(
                :edge_route; value_type = UInt32
            ),
            force = LocalWorksets.combined(
                :force_route;
                value_type = Float32,
                maximum = 2,
                combine = force_law,
            ),
            fracture = LocalWorksets.resolved(
                :fracture_route;
                value_type = UInt32,
                maximum = 1,
                empty = UInt32(0),
                rank = (
                    type = Int32,
                    order = :max,
                    lower = Int32(0),
                    upper = Int32(10),
                ),
                tie_break = (type = UInt32, order = :min),
            ),
        ),
    )
    workplan = LocalWorksets.plan(work, topology; backend)
    duplicate_identities = copy(topology.semantic_ids.fracture)
    duplicate_identities[1, 1] = duplicate_identities[1, 2]
    invalid_topology = merge(topology, (
        semantic_ids = (fracture = duplicate_identities,),
    ))
    invalid_rejected = try
        LocalWorksets.plan(work, invalid_topology; backend)
        false
    catch
        true
    end
    invalid_rejected || error("spring duplicate semantic identity was admitted")
    expected_edge = fill(UInt32(0), 4)
    expected_force = fill(Float32(0), 5)
    expected_fracture = fill(UInt32(0), 3)
    winner_rank = fill(typemin(Int32), 3)
    winner_identity = fill(typemax(UInt32), 3)
    for item in 1:4
        extension = extensions[item]
        expected_edge[edge_route[1, item]] =
            extension > 4 ? UInt32(2) : UInt32(1)
        expected_force[force_route[1, item]] += Float32(extension)
        expected_force[force_route[2, item]] -= Float32(extension)
        extension > 3 || continue
        destination = fracture_route[1, item]
        identity = topology.semantic_ids.fracture[1, item]
        if extension > winner_rank[destination] ||
                extension == winner_rank[destination] &&
                identity < winner_identity[destination]
            winner_rank[destination] = extension
            winner_identity[destination] = identity
            expected_fracture[destination] = UInt32(item)
        end
    end
    storage = (
        extensions = array_type(extensions),
        edge_state = array_type(fill(UInt32(0), 4)),
        force = array_type(fill(Float32(0), 5)),
        fracture = array_type(fill(UInt32(0), 3)),
    )
    force_records = (
        values = array_type(fill(Float32(0), 8)),
        valid = array_type(fill(false, 8)),
    )
    fracture_records = (
        ranks = array_type(fill(Int32(0), 4)),
        values = array_type(fill(UInt32(0), 4)),
        valid = array_type(fill(false, 4)),
    )
    records = force_mode === :deterministic ?
        (force = force_records, fracture = fracture_records) :
        (fracture = fracture_records,)
    workspace = (records, leases = Any[nothing, nothing, nothing])
    prepared = LocalWorksets.prepare(workplan, storage; workspace)
    event = LocalWorksets.run!(prepared)
    wait(event)
    actual_edge = Array(storage.edge_state)
    actual_force = Array(storage.force)
    actual_fracture = Array(storage.fracture)
    actual_edge == expected_edge || error("spring edge-state mismatch")
    if force_mode === :deterministic
        actual_force == expected_force || error("spring force mismatch")
    else
        all(isapprox.(actual_force, expected_force; rtol = 8eps(Float32))) ||
            error("fast spring force mismatch")
    end
    actual_fracture == expected_fracture || error("spring fracture mismatch")
    planned = LocalWorksets.inspect(workplan)
    warm_allocations = @allocated begin
        warm_event = LocalWorksets.run!(prepared)
        wait(warm_event)
    end
    return (
        name = :lattice_spring,
        force_mode,
        edge_state = actual_edge,
        force = actual_force,
        fracture = actual_fracture,
        launches = planned.launches,
        waits = LocalWorksets.inspect(prepared).wait_count,
        transfer_bytes = planned.topology_transfer_bytes,
        workspace_bytes = planned.workspace.total_bytes,
        warm_allocations,
        determinism = planned.determinism,
        invalid_rejected,
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_lw_lattice_spring_witness()
