import KernelAbstractions
import LocalWorksets

struct _LWD2Q9Collision
    equilibrium::NTuple{9, Float32}
    omega::Float32
end

function (operation::_LWD2Q9Collision)(item::Int32, reads, values)
    base = 9 * (Int(item) - 1)
    return (populations = ntuple(Val(9)) do lane
        value = @inbounds reads.populations[base + lane]
        LocalWorksets.emit(
            value - operation.omega *
                (value - operation.equilibrium[lane])
        )
    end,)
end

function _lw_d2q9_topology(nx::Int, ny::Int)
    velocities = (
        (0, 0), (1, 0), (0, 1), (-1, 0), (0, -1),
        (1, 1), (-1, 1), (-1, -1), (1, -1),
    )
    cells = nx * ny
    routes = Matrix{Int32}(undef, 9, cells)
    for y in 1:ny, x in 1:nx
        cell = x + nx * (y - 1)
        for lane in 1:9
            dx, dy = velocities[lane]
            target_x = mod1(x + dx, nx)
            target_y = mod1(y + dy, ny)
            target_cell = target_x + nx * (target_y - 1)
            routes[lane, cell] = Int32(lane + 9 * (target_cell - 1))
        end
    end
    return (
        epoch = UInt64(1),
        item_count = cells,
        routes = (stream = routes,),
        destination_counts = (populations = 9 * cells,),
    )
end

function run_lw_d2q9_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    nx, ny = 4, 3
    topology = _lw_d2q9_topology(nx, ny)
    equilibrium = ntuple(lane -> Float32(lane) / 20f0, 9)
    operation = _LWD2Q9Collision(equilibrium, 0.75f0)
    work = LocalWorksets.localwork(
        operation,
        1:topology.item_count;
        read = (populations = :source_populations,),
        outputs = (
            populations = LocalWorksets.independent(
                :stream;
                value_type = Float32,
                maximum = 9,
            ),
        ),
    )
    workplan = LocalWorksets.plan(work, topology; backend)
    invalid_routes = copy(topology.routes.stream)
    invalid_routes[1, 1] = invalid_routes[1, 2]
    invalid_topology = merge(
        topology, (routes = (stream = invalid_routes,),)
    )
    invalid_rejected = try
        LocalWorksets.plan(work, invalid_topology; backend)
        false
    catch
        true
    end
    invalid_rejected || error("D2Q9 duplicate destination was admitted")
    source = Float32[
        Float32(index % 17) / 7f0 for index in 1:(9 * nx * ny)
    ]
    expected = fill(Float32(NaN), length(source))
    for item in 1:topology.item_count, lane in 1:9
        source_index = lane + 9 * (item - 1)
        value = source[source_index]
        destination = topology.routes.stream[lane, item]
        expected[destination] = value - operation.omega *
            (value - operation.equilibrium[lane])
    end
    source_storage = array_type(source)
    storage = (
        populations = array_type(fill(Float32(-1), length(source))),
    )
    submission = (
        source_populations = LocalWorksets.storage_slot(
            source_storage; access = :read
        ),
    )
    prepared = LocalWorksets.prepare(
        workplan,
        storage;
        workspace = (leases = Any[nothing, nothing, nothing],),
        submission,
    )
    event = LocalWorksets.run!(prepared, (; source_populations = source_storage))
    wait(event)
    actual = Array(storage.populations)
    actual == expected || error("D2Q9 LocalWorksets witness mismatch")
    planned = LocalWorksets.inspect(workplan)
    planned.launches == 1 || error("D2Q9 witness launch mismatch")
    planned.workspace.algorithmic_bytes == 0 ||
        error("D2Q9 witness unexpectedly requires workspace")
    warm_source = array_type(source)
    warm_allocations = @allocated begin
        warm_event = LocalWorksets.run!(
            prepared, (; source_populations = warm_source)
        )
        wait(warm_event)
    end
    return (
        name = :lbm_d2q9,
        result = actual,
        reference = expected,
        launches = planned.launches,
        waits = LocalWorksets.inspect(prepared).wait_count,
        transfer_bytes = planned.topology_transfer_bytes,
        workspace_bytes = planned.workspace.algorithmic_bytes,
        warm_allocations,
        invalid_rejected,
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_lw_d2q9_witness()
