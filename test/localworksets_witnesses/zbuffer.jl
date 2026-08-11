import KernelAbstractions
import LocalWorksets

struct _LWZBufferOperation end

function (::_LWZBufferOperation)(item::Int32, reads, values)
    return (color = LocalWorksets.candidate(
        @inbounds(reads.depth[item]),
        @inbounds(reads.color[item]),
        @inbounds(reads.covered[item]),
    ),)
end

function run_lw_zbuffer_witness(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
    )
    pixel = reshape(Int32[1, 1, 2, 2, 3], 1, 5)
    identities = reshape(UInt32[50, 10, 30, 20, 40], 1, 5)
    topology = (
        epoch = UInt64(4),
        item_count = 5,
        routes = (pixel = pixel,),
        destination_counts = (color = 4,),
        semantic_ids = (color = identities,),
    )
    work = LocalWorksets.localwork(
        _LWZBufferOperation(),
        1:5;
        read = (
            color = :fragment_colors,
            covered = :fragment_coverage,
            depth = :fragment_depths,
        ),
        outputs = (
            color = LocalWorksets.resolved(
                :pixel;
                value_type = UInt32,
                maximum = 1,
                empty = UInt32(0),
                rank = (
                    type = Int32,
                    order = :min,
                    lower = Int32(-100),
                    upper = Int32(100),
                ),
                tie_break = (type = UInt32, order = :min),
            ),
        ),
    )
    workplan = LocalWorksets.plan(work, topology; backend)
    duplicate_identities = copy(identities)
    duplicate_identities[1, 1] = duplicate_identities[1, 2]
    invalid_topology = merge(topology, (
        semantic_ids = (color = duplicate_identities,),
    ))
    invalid_rejected = try
        LocalWorksets.plan(work, invalid_topology; backend)
        false
    catch
        true
    end
    invalid_rejected || error("z-buffer duplicate identity was admitted")
    depths = Int32[-2, -2, -1, -1, 4]
    colors = UInt32[0x11, 0x22, 0x33, 0x44, 0x55]
    covered = Bool[true, true, true, false, true]
    expected = UInt32[0x22, 0x33, 0x55, 0x00]
    storage = (
        fragment_colors = array_type(colors),
        fragment_coverage = array_type(covered),
        fragment_depths = array_type(depths),
        color = array_type(fill(UInt32(0xff), 4)),
    )
    workspace = (
        records = (
            color = (
                ranks = array_type(fill(Int32(0), 5)),
                values = array_type(fill(UInt32(0), 5)),
                valid = array_type(fill(false, 5)),
            ),
        ),
        leases = Any[nothing, nothing],
    )
    prepared = LocalWorksets.prepare(workplan, storage; workspace)
    event = LocalWorksets.run!(prepared)
    wait(event)
    actual = Array(storage.color)
    actual == expected || error("generic z-buffer witness mismatch")
    planned = LocalWorksets.inspect(workplan)
    warm_allocations = @allocated begin
        warm_event = LocalWorksets.run!(prepared)
        wait(warm_event)
    end
    return (
        name = :zbuffer,
        result = actual,
        reference = expected,
        launches = planned.launches,
        waits = LocalWorksets.inspect(prepared).wait_count,
        transfer_bytes = planned.topology_transfer_bytes,
        workspace_bytes = planned.workspace.total_bytes,
        warm_allocations,
        determinism = planned.determinism,
        invalid_rejected,
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_lw_zbuffer_witness()
