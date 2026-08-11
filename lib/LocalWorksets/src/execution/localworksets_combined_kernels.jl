# Backend-neutral kernels for the heterogeneous buffered lowering. The
# generated per-item and per-destination helpers live with its compiler logic.

@kernel function _combined_clear_kernel!(declarations, outputs, count::Int32)
    destination = @index(Global, Linear)
    destination <= count && _clear_fast_destination!(
        declarations, outputs, Int32(destination)
    )
end

@kernel function _combined_apply_kernel!(
        operation,
        reads,
        values,
        declarations,
        outputs,
        routes,
        record_values,
        record_ranks,
        record_valid,
        active_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= active_count
        result = operation(Int32(item), reads, values)
        _apply_combined_item!(
            declarations,
            outputs,
            routes,
            record_values,
            record_ranks,
            record_valid,
            result,
            Int32(item),
        )
    end
end

@kernel function _combined_publish_kernel!(
        declarations,
        outputs,
        segments,
        semantic_ids,
        record_values,
        record_ranks,
        record_valid,
        destination_count::Int32,
        active_count::Int32,
        full_active,
        full_destinations,
    )
    destination = @index(Global, Linear)
    if destination <= destination_count
        _publish_deterministic_destination!(
            declarations,
            outputs,
            segments,
            semantic_ids,
            record_values,
            record_ranks,
            record_valid,
            Int32(destination),
            active_count,
            full_active,
            full_destinations,
        )
    end
end
