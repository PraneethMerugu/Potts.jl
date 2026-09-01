# Domain-neutral physical primitives shared by the sole Stage Collect executor.
# This file owns no LocalLaw lowering, topology, phase graph, or alternate output
# declaration.  Every kernel is launched only by `collect_stage.jl`.

const _COMPACTED_BLOCK = 256

@inline function _collect_atomic_min!(array, index, value)
    Atomix.@atomic min(array[index], value)
    return nothing
end

function _compacted_scan_sizes(item_count::Int)
    sizes = Int[]
    current = item_count
    while true
        push!(sizes, current)
        current <= _COMPACTED_BLOCK && break
        current = cld(current, _COMPACTED_BLOCK)
    end
    return Tuple(sizes)
end

@generated function _compacted_store_value!(storage, index::Int, value::T) where {T}
    if fieldcount(T) == 0
        return :(@inbounds storage[index] = value)
    end
    expressions = map(1:fieldcount(T)) do field_index
        name = fieldname(T, field_index)
        :(_compacted_store_value!(
            getproperty(storage, $(QuoteNode(name))), index,
            getfield(value, $field_index)))
    end
    return Expr(:block, expressions..., :(nothing))
end

@generated function _compacted_load_value(::Type{T}, storage, index::Int) where {T}
    fieldcount(T) == 0 && return :(@inbounds storage[index])
    values = map(1:fieldcount(T)) do field_index
        name = fieldname(T, field_index)
        :(_compacted_load_value(fieldtype(T, $field_index),
            getproperty(storage, $(QuoteNode(name))), index))
    end
    T <: Tuple && return Expr(:tuple, values...)
    T <: NamedTuple && return :($T(($(values...),)))
    return :($T($(values...)))
end

@inline _compacted_group(::_OneGroup, value) = Int32(1)
@inline _compacted_group(groups::_GroupBy, value) =
    _ordering_extract(groups.extractor, value)

@inline function _initialize_compacted_port!(port, index, terminal::Int32)
    index <= length(port.valid) && (@inbounds port.valid[index] = UInt8(0))
    index <= length(port.item_counts) &&
        (@inbounds port.item_counts[index] = Int32(0))
    if index == 1
        @inbounds begin
            port.count[1] = Int32(0)
            port.invalid_group[1] = terminal
            port.duplicate_position[1] = terminal
        end
    end
    return nothing
end

@kernel function _compacted_validate_order_kernel!(port, workspace, order)
    position = @index(Global, Linear)
    live = @inbounds workspace.count[1]
    if Int32(2) <= position <= live
        left = @inbounds order[position - 1]
        right = @inbounds order[position]
        same_group = workspace.groups === nothing ||
            @inbounds(workspace.groups[left]) == @inbounds(workspace.groups[right])
        key_type = typeof(port).parameters[5]
        identity_type = typeof(port).parameters[6]
        same_order = _canonical_order_equal(
            _compacted_load_value(key_type, workspace.keys, Int(left)),
            _compacted_load_value(identity_type, workspace.identities, Int(left)),
            _compacted_load_value(key_type, workspace.keys, Int(right)),
            _compacted_load_value(identity_type, workspace.identities, Int(right)))
        same_group && same_order &&
            _collect_atomic_min!(
                workspace.duplicate_position, 1, Int32(position - 1))
    end
end

@kernel function _compacted_scan_block_kernel!(input, output, block_sums, n::Int32)
    scratch = @localmem Int32 (_COMPACTED_BLOCK,)
    load_lane = @index(Local, Linear)
    load_group = @index(Group, Linear)
    load_index = (load_group - 1) * _COMPACTED_BLOCK + load_lane
    @inbounds scratch[load_lane] =
        load_index <= n ? input[load_index] : Int32(0)
    @synchronize()
    for stride_log in 0:7
        lane = @index(Local, Linear)
        scan_stride = Int32(1) << stride_log
        base = (lane - 1) * 2 * scan_stride
        right = base + 2 * scan_stride
        if right <= _COMPACTED_BLOCK
            @inbounds scratch[right] += scratch[base + scan_stride]
        end
        @synchronize()
    end
    root_lane = @index(Local, Linear)
    root_group = @index(Group, Linear)
    if root_lane == 1
        @inbounds begin
            block_sums[root_group] = scratch[_COMPACTED_BLOCK]
            scratch[_COMPACTED_BLOCK] = Int32(0)
        end
    end
    @synchronize()
    for stride_log in 7:-1:0
        lane = @index(Local, Linear)
        scan_stride = Int32(1) << stride_log
        base = (lane - 1) * 2 * scan_stride
        right = base + 2 * scan_stride
        if right <= _COMPACTED_BLOCK
            @inbounds begin
                temporary = scratch[base + scan_stride]
                scratch[base + scan_stride] = scratch[right]
                scratch[right] += temporary
            end
        end
        @synchronize()
    end
    output_lane = @index(Local, Linear)
    output_group = @index(Group, Linear)
    output_index = (output_group - 1) * _COMPACTED_BLOCK + output_lane
    output_index <= n &&
        (@inbounds output[output_index] = scratch[output_lane])
end

@kernel function _compacted_scan_add_kernel!(prefix, parent_prefix, n::Int32)
    index = @index(Global, Linear)
    if index <= n
        parent = cld(index, _COMPACTED_BLOCK)
        @inbounds prefix[index] += parent_prefix[parent]
    end
end

@kernel function _compacted_scatter_kernel!(
        valid, item_counts, item_prefix, order, positions, count,
        ::Val{K}, nitems::Int32
    ) where {K}
    item = @index(Global, Linear)
    if item <= nitems
        position = @inbounds item_prefix[item]
        for lane in 1:K
            candidate = lane + K * (item - 1)
            @inbounds positions[candidate] = Int32(0)
            if @inbounds valid[candidate] != UInt8(0)
                position += Int32(1)
                @inbounds begin
                    order[position] = Int32(candidate)
                    positions[candidate] = position
                end
            end
        end
        item == nitems &&
            (@inbounds count[1] = item_prefix[item] + item_counts[item])
    elseif nitems == 0 && item == 1
        @inbounds count[1] = Int32(0)
    end
end

@inline function _compacted_ordinal_less(port, workspace, left::Int32, right::Int32)
    left <= 0 && right <= 0 && return -left < -right
    left <= 0 && return false
    right <= 0 && return true
    if workspace.groups !== nothing
        left_group = @inbounds workspace.groups[left]
        right_group = @inbounds workspace.groups[right]
        left_group != right_group && return left_group < right_group
    end
    if workspace.keys !== nothing
        key_type = typeof(port).parameters[5]
        identity_type = typeof(port).parameters[6]
        comparison = _canonical_order_compare(
            _compacted_load_value(key_type, workspace.keys, Int(left)),
            _compacted_load_value(identity_type, workspace.identities, Int(left)),
            _compacted_load_value(key_type, workspace.keys, Int(right)),
            _compacted_load_value(identity_type, workspace.identities, Int(right)))
        comparison != 0 && return comparison < 0
    end
    return left < right
end

@kernel function _compacted_local_bitonic_kernel!(port, workspace, count, n::Int32)
    local_order = @localmem Int32 (_COMPACTED_BLOCK,)
    load_lane = @index(Local, Linear)
    load_group = @index(Group, Linear)
    item_index = (load_group - 1) * _COMPACTED_BLOCK + load_lane
    live = @inbounds count[1]
    @inbounds local_order[load_lane] = item_index <= n && item_index <= live ?
        workspace.order_a[item_index] : Int32(-1)
    @synchronize()
    for sort_size_log in 1:8
        for sort_stride_log in 1:sort_size_log
            lane = @index(Local, Linear)
            sort_size = Int32(1) << sort_size_log
            sort_stride = sort_size >>> sort_stride_log
            other = xor(lane - 1, sort_stride) + 1
            if other > lane
                ascending = ((lane - 1) & sort_size) == 0
                left = @inbounds local_order[lane]
                right = @inbounds local_order[other]
                swap = ascending ? _compacted_ordinal_less(port, workspace, right, left) :
                    _compacted_ordinal_less(port, workspace, left, right)
                if swap
                    @inbounds begin
                        local_order[lane] = right
                        local_order[other] = left
                    end
                end
            end
            @synchronize()
        end
    end
    output_lane = @index(Local, Linear)
    output_group = @index(Group, Linear)
    output_index = (output_group - 1) * _COMPACTED_BLOCK + output_lane
    if output_index <= n
        candidate = @inbounds local_order[output_lane]
        @inbounds workspace.order_a[output_index] = candidate
        candidate > 0 && (@inbounds workspace.positions[candidate] = Int32(output_index))
    end
end

@kernel function _compacted_merge_kernel!(
        port, workspace, source, destination, count, width::Int32, n::Int32)
    output_index = @index(Global, Linear)
    live = @inbounds count[1]
    if output_index <= n
        if output_index > live
            @inbounds destination[output_index] = -Int32(output_index)
        else
            run = div(output_index - 1, 2 * Int(width))
            first_index = run * 2 * Int(width) + 1
            middle = min(first_index + Int(width), Int(live) + 1)
            stop = min(first_index + 2 * Int(width), Int(live) + 1)
            rank = output_index - first_index
            low = max(0, rank - (stop - middle))
            high = min(rank, middle - first_index)
            while low < high
                left_count = (low + high) >>> 1
                right_count = rank - left_count
                left_index = first_index + left_count
                right_index = middle + right_count
                if left_count < middle - first_index && right_count > 0 &&
                        !_compacted_ordinal_less(port, workspace,
                            @inbounds(source[right_index - 1]),
                            @inbounds(source[left_index]))
                    low = left_count + 1
                else
                    high = left_count
                end
            end
            left_index = first_index + low
            right_index = middle + (rank - low)
            take_left = left_index < middle && (right_index >= stop ||
                !_compacted_ordinal_less(port, workspace,
                    @inbounds(source[right_index]), @inbounds(source[left_index])))
            candidate = take_left ? @inbounds(source[left_index]) :
                @inbounds(source[right_index])
            @inbounds destination[output_index] = candidate
            candidate > 0 &&
                (@inbounds workspace.positions[candidate] = Int32(output_index))
        end
    end
end

@kernel function _compacted_directory_kernel!(workspace, order, groups::Int32)
    group = @index(Global, Linear)
    if group <= groups + Int32(1)
        live = @inbounds workspace.count[1]
        if group == groups + Int32(1)
            @inbounds workspace.starts[group] = live + Int32(1)
        else
            low = Int32(1)
            high = live + Int32(1)
            while low < high
                middle = low + ((high - low) >>> 1)
                candidate = @inbounds order[middle]
                candidate_group = @inbounds workspace.groups[candidate]
                candidate_group < group ? (low = middle + Int32(1)) : (high = middle)
            end
            @inbounds workspace.starts[group] = low
        end
    end
end

const _COMPACTED_VALID = UInt8(0)
const _COMPACTED_CAPACITY = UInt8(1)
const _COMPACTED_GROUP = UInt8(2)
const _COMPACTED_DUPLICATE = UInt8(3)

struct _CompactedDiagnostic
    code::UInt8
    port::Int32
    primary::Int32
    secondary::Int32
    witness::UInt32
end

@inline _compacted_valid_diagnostic() =
    _CompactedDiagnostic(_COMPACTED_VALID, Int32(0), Int32(0), Int32(0), UInt32(0))
@inline _compacted_group_diagnostic(::Nothing, invalid, length, port) =
    _compacted_valid_diagnostic()
@inline function _compacted_group_diagnostic(groups, invalid, valid_length, port)
    invalid <= valid_length || return _compacted_valid_diagnostic()
    group = @inbounds groups[invalid]
    return _CompactedDiagnostic(_COMPACTED_GROUP, port, invalid, Int32(0),
        reinterpret(UInt32, group))
end

@inline function _compacted_validate_port(port, workspace, order, port_index)
    count = @inbounds workspace.count[1]
    count > port.capacity && return _CompactedDiagnostic(
        _COMPACTED_CAPACITY, port_index, count, Int32(port.capacity), UInt32(0))
    invalid = @inbounds workspace.invalid_group[1]
    group_diagnostic = _compacted_group_diagnostic(
        workspace.groups, invalid, length(workspace.valid), port_index)
    group_diagnostic.code == _COMPACTED_VALID || return group_diagnostic
    duplicate = @inbounds workspace.duplicate_position[1]
    if duplicate < count
        left = @inbounds order[duplicate]
        right = @inbounds order[duplicate + Int32(1)]
        return _CompactedDiagnostic(
            _COMPACTED_DUPLICATE, port_index, left, right, UInt32(0))
    end
    return _compacted_valid_diagnostic()
end

_compacted_record_components(records::StructArrays.StructArray) =
    StructArrays.components(records)
_compacted_record_components(records::AbstractArray) = records

@inline function _compacted_publish_port!(
        candidate, storage, workspace, ::Val{Grouped}) where {Grouped}
    count = @inbounds workspace.count[1]
    if candidate <= length(workspace.valid)
        position = @inbounds workspace.positions[candidate]
        storage.source_position === nothing ||
            (@inbounds storage.source_position[candidate] = position)
        if position > 0
            value = _compacted_load_value(
                eltype(storage.records), workspace.values, Int(candidate))
            _compacted_store_value!(
                _compacted_record_components(storage.records), Int(position), value)
            lanes = div(length(workspace.valid), length(workspace.item_counts))
            @inbounds begin
                storage.source_item[position] = Int32(cld(candidate, lanes))
                storage.source_lane[position] = Int32(mod(candidate - 1, lanes) + 1)
            end
        end
    end
    candidate == 1 && (@inbounds storage.count[1] = count)
    Grouped && candidate <= length(workspace.starts) &&
        (@inbounds storage.segment_starts[candidate] = workspace.starts[candidate])
    return nothing
end

@inline _compacted_publish_ports!(candidate, ::Tuple{}, ::Tuple{},
    ::Tuple{}, ::Tuple{}) = nothing
@inline function _compacted_publish_ports!(candidate, storages::Tuple,
        workspaces::Tuple, groupeds::Tuple, extents::Tuple)
    candidate <= first(extents) && _compacted_publish_port!(candidate,
        first(storages), first(workspaces), first(groupeds))
    _compacted_publish_ports!(candidate, Base.tail(storages),
        Base.tail(workspaces), Base.tail(groupeds), Base.tail(extents))
    return nothing
end

@kernel function _compacted_publish_ports_kernel!(
        storages, workspaces, gate, groupeds, extents)
    candidate = @index(Global, Linear)
    if @inbounds gate[1]
        _compacted_publish_ports!(candidate, storages, workspaces,
            groupeds, extents)
    end
end
