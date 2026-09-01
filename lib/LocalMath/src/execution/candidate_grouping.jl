# Device-resident destination segmentation for Unique, Reduce, and Resolve.
# Destination is the sole directory key. A closed package-owned physical
# policy determines order within each segment: canonical ordinal by default,
# or Resolve's rank/tie key for adjacent-key validation. This helper does not
# represent the scientific order laws required by Collect or OrderedFold.

const _DESTINATION_GROUP_BLOCK = 256
struct _OrdinalCandidateOrder end

struct _DestinationGrouping{D,V,A,B,S,X,O}
    destinations::D
    valid::V
    order_a::A
    order_b::B
    starts::S
    invalid_ordinal::X
    candidate_count::Int32
    destination_count::Int32
    sort_capacity::Int32
    merge_passes::Int32
    ordering::O
end

Adapt.adapt_structure(to, grouping::_DestinationGrouping) =
    _DestinationGrouping(
        Adapt.adapt(to, grouping.destinations),
        Adapt.adapt(to, grouping.valid),
        Adapt.adapt(to, grouping.order_a),
        Adapt.adapt(to, grouping.order_b),
        Adapt.adapt(to, grouping.starts),
        Adapt.adapt(to, grouping.invalid_ordinal),
        grouping.candidate_count,
        grouping.destination_count,
        grouping.sort_capacity,
        grouping.merge_passes,
        Adapt.adapt(to, grouping.ordering),
    )

struct _DestinationGroupingShape
    candidate_count::Int32
    destination_count::Int32
    sort_capacity::Int32
    merge_passes::Int32
end

function _destination_grouping_capacity(candidate_count::Integer)
    candidate_count >= 0 || throw(LocalMathValidationError(
        "destination grouping requires a nonnegative candidate count";
        stage = :prepare, contract = :destination_grouping_capacity,
        actual = candidate_count,
    ))
    candidate_count <= typemax(Int32) || throw(LocalMathValidationError(
        "destination grouping exceeds its canonical Int32 ordinal space";
        stage = :prepare, contract = :destination_grouping_capacity,
        expected = 0:typemax(Int32), actual = candidate_count,
    ))
    capacity = nextpow(2, max(Int(candidate_count), 1))
    capacity <= typemax(Int32) || throw(LocalMathValidationError(
        "destination grouping sort capacity exceeds Int32 device indexing";
        stage = :prepare, contract = :destination_grouping_sort_capacity,
        expected = 1:typemax(Int32), actual = capacity,
    ))
    return capacity
end

function _require_destination_grouping_capabilities(backend)
    values = all(((Int32, :load), (Int32, :store),
                  (UInt8, :load), (UInt8, :store))) do requirement
        T, operation = requirement
        _centrally_qualified_value_capability(
            backend, T, operation, :global)
    end
    atomic = _centrally_qualified_atomic_capability(
        backend, Int32, :min, :global)
    values && atomic || throw(LocalMathValidationError(
        "the backend lacks the reviewed destination-grouping capabilities";
        stage = :prepare, contract = :destination_grouping_backend_capability,
        expected = (values = ((Int32, :load, :store),
            (UInt8, :load, :store)), atomic = (Int32, :min)),
        actual = typeof(backend),
    ))
    return nothing
end

function _destination_grouping_workspace_spec(
        candidate_count::Integer, destination_count::Integer;
        path::Tuple, name_prefix::Symbol,
    )
    0 <= destination_count < typemax(Int32) || throw(
        LocalMathValidationError(
            "destination grouping requires room for its terminal directory entry";
            stage = :prepare, contract = :destination_grouping_destinations,
            expected = 0:(typemax(Int32) - 1), actual = destination_count,
        ))
    capacity = _destination_grouping_capacity(candidate_count)
    merge_passes = capacity <= _DESTINATION_GROUP_BLOCK ? 0 :
        ceil(Int, log2(cld(capacity, _DESTINATION_GROUP_BLOCK)))
    names = (
        destinations = Symbol(name_prefix, :_destinations),
        valid = Symbol(name_prefix, :_valid),
        order_a = Symbol(name_prefix, :_order_a),
        order_b = Symbol(name_prefix, :_order_b),
        starts = Symbol(name_prefix, :_starts),
        invalid_ordinal = Symbol(name_prefix, :_invalid_ordinal),
    )
    sizes = (
        destinations = (Int(candidate_count),),
        valid = (Int(candidate_count),),
        order_a = (capacity,),
        order_b = (capacity,),
        starts = (Int(destination_count) + 1,),
        invalid_ordinal = (1,),
    )
    leaves = (
        _workspace_leaf(names.destinations, (path..., :destinations), Int32,
            sizes.destinations; role = :candidate_destination),
        _workspace_leaf(names.valid, (path..., :valid), UInt8,
            sizes.valid; role = :candidate_participation),
        _workspace_leaf(names.order_a, (path..., :order_a), Int32,
            sizes.order_a; role = :candidate_order),
        _workspace_leaf(names.order_b, (path..., :order_b), Int32,
            sizes.order_b; role = :candidate_order),
        _workspace_leaf(names.starts, (path..., :starts), Int32,
            sizes.starts; role = :destination_directory),
        _workspace_leaf(names.invalid_ordinal, (path..., :invalid_ordinal), Int32,
            sizes.invalid_ordinal; role = :candidate_invalid_destination),
    )
    template = (
        destinations = _WorkspaceLeafSlot(names.destinations),
        valid = _WorkspaceLeafSlot(names.valid),
        order_a = _WorkspaceLeafSlot(names.order_a),
        order_b = _WorkspaceLeafSlot(names.order_b),
        starts = _WorkspaceLeafSlot(names.starts),
        invalid_ordinal = _WorkspaceLeafSlot(names.invalid_ordinal),
    )
    shape = _DestinationGroupingShape(
        Int32(candidate_count), Int32(destination_count), Int32(capacity),
        Int32(merge_passes),
    )
    return (leaves = leaves, template = template, shape = shape)
end

function _destination_grouping_from_workspace(workspace,
        shape::_DestinationGroupingShape,
        ordering = _OrdinalCandidateOrder())
    return _DestinationGrouping(
        workspace.destinations, workspace.valid, workspace.order_a,
        workspace.order_b, workspace.starts, workspace.invalid_ordinal,
        shape.candidate_count, shape.destination_count, shape.sort_capacity,
        shape.merge_passes, ordering,
    )
end

@inline function _destination_group_atomic_min!(array, index, value)
    Atomix.@atomic min(array[index], value)
    return nothing
end

@inline function _reset_destination_grouping_index!(grouping, index)
    extent = max(grouping.sort_capacity,
        grouping.destination_count + Int32(1), grouping.candidate_count)
    if index <= extent
        if index <= grouping.sort_capacity
            @inbounds begin
                grouping.order_a[index] = Int32(0)
                grouping.order_b[index] = Int32(0)
            end
        end
        if index <= grouping.candidate_count
            @inbounds begin
                grouping.valid[index] = UInt8(0)
                grouping.destinations[index] = Int32(0)
            end
        end
        index <= grouping.destination_count + Int32(1) &&
            (@inbounds grouping.starts[index] = Int32(1))
        index == 1 &&
            (@inbounds grouping.invalid_ordinal[1] = typemax(Int32))
    end
    return nothing
end

@inline _intra_destination_precedes(
    ::_OrdinalCandidateOrder, left::Int32, right::Int32) = left < right

@inline function _destination_candidate_precedes(
        grouping, left::Int32, right::Int32)
    left == 0 && return false
    right == 0 && return true
    left_valid = @inbounds grouping.valid[left] != UInt8(0)
    right_valid = @inbounds grouping.valid[right] != UInt8(0)
    left_valid != right_valid && return left_valid
    left_valid || return left < right
    if left_valid
        left_destination = @inbounds grouping.destinations[left]
        right_destination = @inbounds grouping.destinations[right]
        left_destination != right_destination &&
            return left_destination < right_destination
    end
    return _intra_destination_precedes(grouping.ordering, left, right)
end

@kernel function _destination_grouping_local_sort_kernel!(grouping)
    lane = @index(Local, Linear)
    group = @index(Group, Linear)
    candidate_index = (group - 1) * _DESTINATION_GROUP_BLOCK + lane
    if candidate_index <= grouping.candidate_count &&
            @inbounds(grouping.valid[candidate_index] != UInt8(0))
        destination = @inbounds grouping.destinations[candidate_index]
        if destination < 1 || destination > grouping.destination_count
            _destination_group_atomic_min!(
                grouping.invalid_ordinal, 1, Int32(candidate_index))
            @inbounds begin
                grouping.valid[candidate_index] = UInt8(0)
                grouping.destinations[candidate_index] = Int32(0)
            end
        end
    end
    local_order = @localmem Int32 (_DESTINATION_GROUP_BLOCK,)
    @inbounds local_order[lane] = candidate_index <= grouping.candidate_count ?
        Int32(candidate_index) : Int32(0)
    @synchronize
    for width_log in 1:8
        for stride_log in 1:width_log
            width = Int32(1) << width_log
            stride = width >>> stride_log
            partner = xor(lane - 1, stride) + 1
            if partner > lane
                ascending = ((lane - 1) & width) == 0
                left = @inbounds local_order[lane]
                right = @inbounds local_order[partner]
                swap = ascending ? _destination_candidate_precedes(
                    grouping, right, left) : _destination_candidate_precedes(
                    grouping, left, right)
                if swap
                    @inbounds begin
                        local_order[lane] = right
                        local_order[partner] = left
                    end
                end
            end
            @synchronize
        end
    end
    ((group - 1) * _DESTINATION_GROUP_BLOCK + lane) <=
        grouping.sort_capacity &&
        (@inbounds grouping.order_a[
            (group - 1) * _DESTINATION_GROUP_BLOCK + lane] = local_order[lane])
end

@kernel function _destination_grouping_merge_kernel!(
        grouping, source, destination, width::Int32)
    output_index = @index(Global, Linear)
    if output_index <= grouping.sort_capacity
        run = div(output_index - 1, 2 * Int(width))
        first = run * 2 * Int(width) + 1
        middle = min(first + Int(width), Int(grouping.sort_capacity) + 1)
        stop = min(first + 2 * Int(width), Int(grouping.sort_capacity) + 1)
        rank = output_index - first
        low = max(0, rank - (stop - middle))
        high = min(rank, middle - first)
        while low < high
            left_count = (low + high) >>> 1
            right_count = rank - left_count
            left_index = first + left_count
            right_index = middle + right_count
            if left_count < middle - first && right_count > 0 &&
                    !_destination_candidate_precedes(
                        grouping, @inbounds(source[right_index - 1]),
                        @inbounds(source[left_index]))
                low = left_count + 1
            else
                high = left_count
            end
        end
        left_index = first + low
        right_index = middle + (rank - low)
        take_left = left_index < middle && (right_index >= stop ||
            !_destination_candidate_precedes(
                grouping, @inbounds(source[right_index]),
                @inbounds(source[left_index])))
        @inbounds destination[output_index] = take_left ?
            source[left_index] : source[right_index]
    end
end

@inline function _destination_at(grouping, order, position::Int32)
    ordinal = @inbounds order[position]
    ordinal == 0 && return typemax(Int32)
    @inbounds grouping.valid[ordinal] == UInt8(0) && return typemax(Int32)
    return @inbounds grouping.destinations[ordinal]
end

@kernel function _destination_grouping_directory_kernel!(grouping, order)
    destination = @index(Global, Linear)
    terminal = Int(grouping.destination_count) + 1
    if destination <= terminal
        low = Int32(1)
        high = grouping.sort_capacity + Int32(1)
        while low < high
            middle = low + ((high - low) >>> 1)
            value = middle <= grouping.sort_capacity ?
                _destination_at(grouping, order, middle) : typemax(Int32)
            if value < destination
                low = middle + Int32(1)
            else
                high = middle
            end
        end
        @inbounds grouping.starts[destination] = min(
            low, grouping.candidate_count + Int32(1))
    end
end

@inline _destination_grouping_success(grouping) =
    @inbounds(grouping.invalid_ordinal[1]) == typemax(Int32)

function _group_destinations!(backend, grouping::_DestinationGrouping)
    local_extent = max(cld(Int(grouping.sort_capacity),
        _DESTINATION_GROUP_BLOCK), 1) * _DESTINATION_GROUP_BLOCK
    _destination_grouping_local_sort_kernel!(
        backend, _DESTINATION_GROUP_BLOCK, local_extent)(grouping;
        ndrange = local_extent)
    source, destination = grouping.order_a, grouping.order_b
    width = _DESTINATION_GROUP_BLOCK
    while width < grouping.sort_capacity
        _destination_grouping_merge_kernel!(backend)(
            grouping, source, destination, Int32(width);
            ndrange = Int(grouping.sort_capacity))
        source, destination = destination, source
        width <<= 1
    end
    directory_extent = Int(grouping.destination_count) + 1
    _destination_grouping_directory_kernel!(backend)(
        grouping, source; ndrange = max(directory_extent, 1))
    return grouping
end

@inline function _destination_segment(grouping, destination::Integer)
    first = @inbounds grouping.starts[destination]
    stop = @inbounds grouping.starts[destination + 1]
    return first:(stop - Int32(1))
end

@inline function _destination_grouping_order(grouping)
    return isodd(grouping.merge_passes) ? grouping.order_b : grouping.order_a
end
