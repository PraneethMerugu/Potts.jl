import KernelAbstractions
import LocalWorksets

struct _LWFEMElementApply end

function (::_LWFEMElementApply)(item::Int32, reads, values)
    base = 4 * (Int(item) - 1)
    return (residual = ntuple(Val(4)) do lane
        local_value = @inbounds reads.local_values[base + lane]
        LocalWorksets.emit(local_value * Float32(lane))
    end,)
end

function run_lw_matrix_free_fem_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    route = Int32[1 2 3; 2 3 5; 4 4 6; 5 6 7]
    work = LocalWorksets.localwork(
        _LWFEMElementApply(),
        1:3;
        read = (local_values = :local_values,),
        outputs = (
            residual = LocalWorksets.combined(
                :element_nodes;
                value_type = Float32,
                maximum = 4,
                combine = LocalWorksets.deterministic(+, Float32(0)),
            ),
        ),
    )
    topology = LocalWorksets.topology(
        work;
        epoch = UInt64(3),
        routes = (element_nodes = route,),
        destination_counts = (residual = 8,),
    )
    workplan = LocalWorksets.plan(work, topology; backend)
    local_values = Float32[
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 11, 12,
    ]
    expected = fill(Float32(0), 8)
    for item in 1:3, lane in 1:4
        expected[route[lane, item]] +=
            local_values[lane + 4 * (item - 1)] * Float32(lane)
    end
    storage = (
        local_values = array_type(local_values),
        residual = array_type(fill(Float32(-1), 8)),
    )
    prepared = LocalWorksets.prepare(
        workplan, storage; lease_capacity = 2
    )
    workspace = prepared.workspace
    invalid_workspace = (
        records = (
            residual = (
                values = array_type(fill(Float32(0), 11)),
                valid = array_type(fill(false, 12)),
            ),
        ),
        leases = Any[nothing],
    )
    invalid_rejected = try
        LocalWorksets.prepare(
            workplan, storage; workspace = invalid_workspace
        )
        false
    catch
        true
    end
    invalid_rejected || error("one-short FEM workspace was admitted")
    event = LocalWorksets.run!(prepared)
    wait(event)
    actual = Array(storage.residual)
    actual == expected || error("matrix-free FEM witness mismatch")
    actual[8] == 0f0 || error("FEM empty destination did not publish identity")
    planned = LocalWorksets.inspect(workplan)
    warm_allocations = @allocated begin
        warm_event = LocalWorksets.run!(prepared)
        wait(warm_event)
    end
    prepared_facts = LocalWorksets.inspect(prepared)
    return (
        name = :matrix_free_fem,
        result = actual,
        reference = expected,
        launches = planned.launches,
        waits = prepared_facts.wait_count,
        transfer_bytes = planned.topology_transfer_bytes,
        workspace_bytes = planned.workspace.total_bytes,
        workspace_ownership = prepared_facts.workspace_ownership,
        workspace_identities = Tuple(
            name => getproperty(prepared_facts.workspace_facts, name).identity
            for name in keys(prepared_facts.workspace_facts)
        ),
        lease_identity = prepared_facts.lease_identity,
        warm_allocations,
        determinism = planned.determinism,
        invalid_rejected,
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_lw_matrix_free_fem_witness()
