# A centrally selected fast path for the common one-port resolved profile.
# This is a specialization of the buffered family, not a third execution
# family: preparation has already validated the same records, segments,
# ranking, identity, and empty-result contract as the heterogeneous lowering.

struct _PreparedSingleResolved{K1, K2, K3, S, I, N, M, O, T, B, E, P}
    apply_kernel::K1
    static_apply_kernel::K2
    publish_kernel::K3
    segment::S
    semantic_ids::I
    name::N
    maximum::M
    order::O
    identity_type::T
    bounds::B
    empty::E
    specialized::P
end

@inline _single_resolved_port(result, ::Val{Name}) where {Name} =
    getproperty(result, Name)

@kernel function _single_min_one_resolved_apply_kernel!(
        operation,
        reads,
        values,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        active_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= active_count
        emission = first(operation(Int32(item), reads, values))
        enabled = _candidate_enabled(emission)
        rank = _candidate_rank(emission)
        !enabled || lower <= rank <= upper || error(
            "resolved rank is outside its declared total domain"
        )
        @inbounds begin
            record_valid[item] = enabled
            record_ranks[item] = rank
            record_values[item] = _candidate_value(emission)
        end
    end
end

@kernel function _single_min_one_resolved_static_apply_kernel!(
        operation,
        output_name,
        reads,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        active_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= active_count
        emission = _single_resolved_port(
            operation(Int32(item), reads, (;)), output_name
        )
        enabled = _candidate_enabled(emission)
        rank = _candidate_rank(emission)
        !enabled || lower <= rank <= upper || error(
            "resolved rank is outside its declared total domain"
        )
        @inbounds begin
            record_valid[item] = enabled
            record_ranks[item] = rank
            record_values[item] = _candidate_value(emission)
        end
    end
end

macro _define_single_resolved_flat_apply(read_count_literal)
    read_count = Int(read_count_literal)
    read_arguments = [Symbol(:read_, index) for index in 1:read_count]
    read_tuple = Expr(:tuple, read_arguments...)
    reads_name = Symbol(:_single_resolved_named_reads_, read_count)
    kernel_name = Symbol(
        :_single_min_one_resolved_flat_, read_count, :_apply_kernel!
    )
    return esc(quote
        @inline function $reads_name(
                ::Val{Names}, $(read_arguments...)
            ) where {Names}
            return NamedTuple{Names}($read_tuple)
        end

        @kernel function $kernel_name(
                operation,
                output_name,
                read_names,
                $(read_arguments...),
                record_ranks,
                record_values,
                record_valid,
                lower,
                upper,
                active_count::Int32,
            )
            item = @index(Global, Linear)
            if item <= active_count
                reads = $reads_name(
                    read_names, $(read_arguments...)
                )
                emission = _single_resolved_port(
                    operation(Int32(item), reads, (;)), output_name
                )
                enabled = _candidate_enabled(emission)
                rank = _candidate_rank(emission)
                !enabled || lower <= rank <= upper || error(
                    "resolved rank is outside its declared total domain"
                )
                @inbounds begin
                    record_valid[item] = enabled
                    record_ranks[item] = rank
                    record_values[item] = _candidate_value(emission)
                end
            end
        end
    end)
end

@_define_single_resolved_flat_apply 1
@_define_single_resolved_flat_apply 2
@_define_single_resolved_flat_apply 3
@_define_single_resolved_flat_apply 4

const _SINGLE_RESOLVED_FLAT_APPLY_SOURCES = (
    _single_min_one_resolved_static_apply_kernel!,
    _single_min_one_resolved_flat_1_apply_kernel!,
    _single_min_one_resolved_flat_2_apply_kernel!,
    _single_min_one_resolved_flat_3_apply_kernel!,
    _single_min_one_resolved_flat_4_apply_kernel!,
)

@kernel function _single_min_one_resolved_publish_kernel!(
        output,
        offsets,
        records,
        semantic_ids,
        record_ranks,
        record_values,
        record_valid,
        upper,
        empty,
        destination_count::Int32,
    )
    destination = @index(Global, Linear)
    if destination <= destination_count
        found = false
        winner_rank = upper
        # This specialization is admitted only for the centrally qualified
        # UInt32 semantic-identity profile. Keep the sentinel scalar in the
        # kernel ABI instead of deriving it from device storage at runtime.
        winner_identity = typemax(UInt32)
        winner_value = empty
        first_index = Int(@inbounds offsets[destination])
        last_index = Int(@inbounds offsets[destination + 1]) - 1
        for segment_index in first_index:last_index
            record = Int(@inbounds records[segment_index])
            if @inbounds record_valid[record]
                rank = @inbounds record_ranks[record]
                identity = @inbounds semantic_ids[record]
                if !found || rank < winner_rank ||
                        (rank == winner_rank && identity < winner_identity)
                    found = true
                    winner_rank = rank
                    winner_identity = identity
                    winner_value = @inbounds record_values[record]
                end
            end
        end
        @inbounds output[destination] = winner_value
    end
end

@kernel function _single_resolved_apply_kernel!(
        operation,
        reads,
        values,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        active_count::Int32,
        name,
        maximum,
    )
    item = @index(Global, Linear)
    if item <= active_count
        emissions = _single_resolved_port(
            operation(Int32(item), reads, values), name
        )
        _single_resolved_apply_item!(
            emissions,
            record_ranks,
            record_values,
            record_valid,
            lower,
            upper,
            Int32(item),
            maximum,
        )
    end
end

@inline @generated function _single_resolved_apply_item!(
        emissions,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        item::Int32,
        ::Val{Maximum},
    ) where {Maximum}
    expressions = Expr[]
    for lane in 1:Maximum
        push!(expressions, quote
            local emission = _emission_lane(
                emissions, Val($Maximum), Val($lane)
            )
            local enabled = _candidate_enabled(emission)
            local record_index = $lane + $Maximum * (Int(item) - 1)
            @inbounds record_valid[record_index] = enabled
            if enabled
                local rank = _candidate_rank(emission)
                lower <= rank <= upper || error(
                    "resolved rank is outside its declared total domain"
                )
                @inbounds begin
                    record_ranks[record_index] = rank
                    record_values[record_index] = _candidate_value(emission)
                end
            end
        end)
    end
    return Expr(:block, expressions..., :(nothing))
end

@kernel function _single_resolved_publish_kernel!(
        output,
        offsets,
        records,
        semantic_ids,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        empty,
        destination_count::Int32,
        active_count::Int32,
        maximum,
        order,
        identity_type,
        full_active,
    )
    destination = @index(Global, Linear)
    if destination <= destination_count
        _single_resolved_publish_destination!(
            output,
            offsets,
            records,
            semantic_ids,
            record_ranks,
            record_values,
            record_valid,
            lower,
            upper,
            empty,
            Int32(destination),
            active_count,
            maximum,
            order,
            identity_type,
            full_active,
        )
    end
end

@inline function _single_resolved_publish_destination!(
        output,
        offsets,
        records,
        semantic_ids,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        empty,
        destination::Int32,
        active_count::Int32,
        ::Val{Maximum},
        ::Val{Order},
        ::Val{Identity},
        ::Val{FullActive},
    ) where {Maximum, Order, Identity, FullActive}
    found = false
    winner_rank = Order === :min ? upper : lower
    winner_identity = typemax(Identity)
    winner_value = empty
    first_index = Int(@inbounds offsets[destination])
    last_index = Int(@inbounds offsets[destination + 1]) - 1
    for segment_index in first_index:last_index
        record_index = Int(@inbounds records[segment_index])
        record_active = FullActive ||
            (record_index - 1) ÷ Maximum + 1 <= active_count
        if record_active && @inbounds(record_valid[record_index])
            rank = @inbounds record_ranks[record_index]
            identity = @inbounds semantic_ids[record_index]
            better_rank = Order === :min ?
                rank < winner_rank : rank > winner_rank
            wins = !found || better_rank ||
                (rank == winner_rank && identity < winner_identity)
            if wins
                found = true
                winner_rank = rank
                winner_identity = identity
                winner_value = @inbounds record_values[record_index]
            end
        end
    end
    @inbounds output[destination] = winner_value
    return nothing
end

function _prepare_single_resolved_runtime(
        lowering::_BufferedCombinedLowering,
        work,
        backend,
        segments,
        semantic_ids,
    )
    name = first(keys(lowering.outputs))
    declaration = getproperty(lowering.outputs, name)
    one_min_full = typeof(declaration).parameters[2] == 1 &&
        typeof(declaration).parameters[5] === :min && work.active === nothing
    flat_static_reads = one_min_full && 1 <= length(work.reads) <= 4
    apply_source = one_min_full ?
        _single_min_one_resolved_apply_kernel! :
        _single_resolved_apply_kernel!
    publish_source = one_min_full ?
        _single_min_one_resolved_publish_kernel! :
        _single_resolved_publish_kernel!
    return _PreparedSingleResolved(
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            apply_source,
            backend,
        ),
        one_min_full ? invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            flat_static_reads ?
                _SINGLE_RESOLVED_FLAT_APPLY_SOURCES[length(work.reads) + 1] :
                _single_min_one_resolved_static_apply_kernel!,
            backend,
        ) : nothing,
        invoke(
            _owned_kernel_factory,
            Tuple{Function, Any},
            publish_source,
            backend,
        ),
        getproperty(segments, name),
        getproperty(semantic_ids, name),
        Val(name),
        Val(typeof(declaration).parameters[2]),
        Val(typeof(declaration).parameters[5]),
        Val(typeof(declaration).parameters[6]),
        (declaration.rank.lower, declaration.rank.upper),
        declaration.empty,
        Val((one_min_full, flat_static_reads)),
    )
end

function _execute_lowering!(
        runtime::_PreparedSingleResolved,
        lowering::_BufferedCombinedLowering,
        work,
        bindings,
        workspace,
        submission,
    )
    name = first(keys(work.outputs))
    reads = NamedTuple{keys(work.reads)}(map(
        read_name -> getproperty(bindings, read_name), values(work.reads)
    ))
    output = getproperty(bindings, name)
    records = getproperty(
        invoke(_deterministic_workspace, Tuple{Any}, workspace), name
    )
    active_count = work.active === nothing ? lowering.item_count :
        Int(getproperty(submission, work.active))
    0 <= active_count <= lowering.item_count || throw(
        LocalWorkValidationError(
            "active selection exceeds the planned item capacity"
        )
    )
    destination_count = getproperty(lowering.destination_counts, name)
    lower, upper = runtime.bounds
    if runtime.specialized isa Val{(true, true)}
        if isempty(submission)
            runtime.static_apply_kernel(
                work.operation,
                runtime.name,
                Val(keys(reads)),
                values(reads)...,
                records.ranks,
                records.values,
                records.valid,
                lower,
                upper,
                Int32(active_count);
                ndrange = max(active_count, 1),
            )
        else
            runtime.apply_kernel(
                work.operation,
                reads,
                submission,
                records.ranks,
                records.values,
                records.valid,
                lower,
                upper,
                Int32(active_count);
                ndrange = max(active_count, 1),
            )
        end
        runtime.publish_kernel(
            output,
            runtime.segment.offsets,
            runtime.segment.records,
            runtime.semantic_ids,
            records.ranks,
            records.values,
            records.valid,
            upper,
            runtime.empty,
            Int32(destination_count);
            ndrange = max(destination_count, 1),
        )
    elseif runtime.specialized isa Val{(true, false)}
        if isempty(submission)
            runtime.static_apply_kernel(
                work.operation,
                runtime.name,
                reads,
                records.ranks,
                records.values,
                records.valid,
                lower,
                upper,
                Int32(active_count);
                ndrange = max(active_count, 1),
            )
        else
            runtime.apply_kernel(
                work.operation,
                reads,
                submission,
                records.ranks,
                records.values,
                records.valid,
                lower,
                upper,
                Int32(active_count);
                ndrange = max(active_count, 1),
            )
        end
        runtime.publish_kernel(
            output,
            runtime.segment.offsets,
            runtime.segment.records,
            runtime.semantic_ids,
            records.ranks,
            records.values,
            records.valid,
            upper,
            runtime.empty,
            Int32(destination_count);
            ndrange = max(destination_count, 1),
        )
    else
        runtime.apply_kernel(
            work.operation,
            reads,
            submission,
            records.ranks,
            records.values,
            records.valid,
            lower,
            upper,
            Int32(active_count),
            runtime.name,
            runtime.maximum;
            ndrange = max(active_count, 1),
        )
        runtime.publish_kernel(
            output,
            runtime.segment.offsets,
            runtime.segment.records,
            runtime.semantic_ids,
            records.ranks,
            records.values,
            records.valid,
            lower,
            upper,
            runtime.empty,
            Int32(destination_count),
            Int32(active_count),
            runtime.maximum,
            runtime.order,
            runtime.identity_type,
            Val(work.active === nothing);
            ndrange = max(destination_count, 1),
        )
    end
    return 2
end

function _lowering_inspection(
        runtime::_PreparedSingleResolved,
        lowering::_BufferedCombinedLowering,
        work,
        workspace,
    )
    return (
        family = :buffered,
        phases = (:apply, :publish_canonical),
        launches = 2,
        operation_invocations = :once_per_active_item,
        device_routes = (),
        deterministic_segments = (first(keys(lowering.outputs)),),
    )
end
