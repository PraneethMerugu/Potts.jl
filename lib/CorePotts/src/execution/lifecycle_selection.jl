# Typed lifecycle selection and finite-resource assignment over one completed
# planning snapshot. CorePotts owns cross-request conflict and finite-resource
# settlement meaning; LocalMath owns typed selected-request publication.
# Both execute through KernelAbstractions on the same backend queue.

const _LifecycleRequestOrderKey = Tuple{
    UInt32, UInt32, UInt32, UInt32, Int32, UInt32,
}
struct _LifecycleConflictWitness
    left::Int32
    right::Int32
end

struct _LifecycleOverflowWitness
    request::Int32
    cell::Int32
end

struct _LifecycleDemand
    group::Int32
    request::Int32
    key::_LifecycleRequestOrderKey
    order_identity::Int32
end

struct _LifecycleFreeCell
    group::Int32
    cell::Int32
    generation::UInt32
    key::Tuple{UInt32, Int32}
    identity::Int32
end

struct _LifecycleSelectedRequest
    request::Int32
    allocation::Int32
    key::_LifecycleRequestOrderKey
    order_identity::Int32
end

struct _LifecycleSelectionStorage{FC,D,SR,B,CW,OW,S,I,A,H}
    free_cells::FC
    demands::D
    selected_requests::SR
    selected::B
    selected_initial::B
    canonical::B
    open::B
    ready::B
    conflict_witness::CW
    overflow_witness::OW
    conflict_status::S
    capacity_status::S
    overflow_status::S
    conflict_left::I
    conflict_left_initial::I
    conflict_right::I
    conflict_right_initial::I
    allocation::A
    high_water::H
end

function Adapt.adapt_structure(to, selection::_LifecycleSelectionStorage)
    return _LifecycleSelectionStorage(
        Adapt.adapt(to, selection.free_cells),
        Adapt.adapt(to, selection.demands),
        Adapt.adapt(to, selection.selected_requests),
        Adapt.adapt(to, selection.selected),
        Adapt.adapt(to, selection.selected_initial),
        Adapt.adapt(to, selection.canonical),
        Adapt.adapt(to, selection.open),
        Adapt.adapt(to, selection.ready),
        Adapt.adapt(to, selection.conflict_witness),
        Adapt.adapt(to, selection.overflow_witness),
        Adapt.adapt(to, selection.conflict_status),
        Adapt.adapt(to, selection.capacity_status),
        Adapt.adapt(to, selection.overflow_status),
        Adapt.adapt(to, selection.conflict_left),
        Adapt.adapt(to, selection.conflict_left_initial),
        Adapt.adapt(to, selection.conflict_right),
        Adapt.adapt(to, selection.conflict_right_initial),
        Adapt.adapt(to, selection.allocation),
        Adapt.adapt(to, selection.high_water),
    )
end

function _lifecycle_compacted_storage_conforms(
        storage::LocalMath.CompactedStorage,
        capacity::Integer;
        grouped::Bool,
        projected::Bool,
    )
    return length(storage.records) == capacity &&
        length(storage.count) == 1 &&
        (grouped ? length(storage.segment_starts) == 2 :
            storage.segment_starts === nothing) &&
        length(storage.source_item) == capacity &&
        length(storage.source_lane) == capacity &&
        (projected ? length(storage.source_position) == capacity :
            storage.source_position === nothing)
end

function _lifecycle_selection_storage_conforms(
        selection::_LifecycleSelectionStorage,
        plan::LifecycleExecutionPlan,
    )
    requests = Int(plan.maximum_requests)
    cells = Int(plan.cell_capacity)
    return _lifecycle_compacted_storage_conforms(
            selection.free_cells, cells; grouped = true, projected = false
        ) &&
        _lifecycle_compacted_storage_conforms(
            selection.demands, requests; grouped = true, projected = false
        ) &&
        _lifecycle_compacted_storage_conforms(
            selection.selected_requests, requests;
            grouped = false,
            projected = true,
        ) &&
        all(array -> length(array) == requests, (
            selection.selected,
            selection.selected_initial,
            selection.canonical,
            selection.allocation,
        )) &&
        all(array -> length(array) == 1, (
            selection.open,
            selection.ready,
            selection.conflict_witness,
            selection.overflow_witness,
            selection.conflict_status,
            selection.capacity_status,
            selection.overflow_status,
            selection.conflict_left,
            selection.conflict_left_initial,
            selection.conflict_right,
            selection.conflict_right_initial,
            selection.high_water,
        ))
end

@inline function _lifecycle_direct_request_key(reads, request::Int32)
    return (
        @inbounds(reads.source_high[request]),
        @inbounds(reads.source_low[request]),
        @inbounds(reads.action_high[request]),
        @inbounds(reads.action_low[request]),
        @inbounds(reads.anchor[request]),
        @inbounds(reads.generation[request]),
    )
end

@inline function _lifecycle_direct_request_is_canonical(
        reads, request::Int32
    )
    @inbounds reads.active[request] || return false
    key = _lifecycle_direct_request_key(reads, request)
    count = Int(@inbounds reads.canonical_count[1])
    for position in 1:count
        prior = @inbounds reads.canonical_slots[position]
        @inbounds reads.active[prior] || continue
        _lifecycle_direct_request_key(reads, prior) == key || continue
        return prior == request
    end
    return false
end

@inline function _lifecycle_descending_priority(priority::Int32)
    return ~xor(reinterpret(UInt32, priority), UInt32(0x80000000))
end

@inline _lifecycle_direct_request_order_key(reads, request::Int32) =
    _lifecycle_direct_request_key(reads, request)

@inline function _lifecycle_first_publication_request(
        ::Val{Stable}, reads; anchor::Int32 = Int32(0)
    ) where {Stable}
    best_request = Int32(0)
    best_key = (
        typemax(UInt32), typemax(UInt32), typemax(UInt32), typemax(UInt32),
        typemax(Int32), typemax(UInt32),
    )
    count = Int(@inbounds reads.canonical_count[1])
    for position in 1:count
        request = @inbounds reads.canonical_slots[position]
        included = Stable ? @inbounds(reads.selected[request]) :
            @inbounds(reads.canonical[request])
        included || continue
        iszero(anchor) || @inbounds(reads.anchor[request]) == anchor || continue
        key = _lifecycle_direct_request_order_key(reads, request)
        if key < best_key
            best_request = request
            best_key = key
        end
    end
    return best_request
end

@inline function _lifecycle_first_action_for_source(descriptors, source::Int32)
    for descriptor in descriptors
        descriptor.source_handle == source && return descriptor.action_identity
    end
    return UInt64(0)
end

@inline @generated function _lifecycle_packed_incident_conflict(
        ::Val{B}, reads::R, bank::Int32, slot::Int32,
        left_anchor::Int32, right_anchor::Int32,
    ) where {B, R}
    branches = :(false)
    for index in reverse(1:B)
        degree = QuoteNode(Symbol(:relationship_, index, :_degree))
        incident = QuoteNode(Symbol(:relationship_, index, :_incident_edges))
        endpoint_offsets = QuoteNode(
            Symbol(:relationship_, index, :_endpoint_offsets)
        )
        incident_offsets = QuoteNode(
            Symbol(:relationship_, index, :_incident_offsets)
        )
        maximum_degrees = QuoteNode(
            Symbol(:relationship_, index, :_maximum_degrees)
        )
        branches = quote
            if bank == $(Int32(index))
                local degrees = getproperty(reads, $degree)
                local incidents = getproperty(reads, $incident)
                local endpoint_offset = @inbounds getproperty(
                    reads, $endpoint_offsets
                )[slot]
                local incident_offset = @inbounds getproperty(
                    reads, $incident_offsets
                )[slot]
                local maximum_degree = @inbounds getproperty(
                    reads, $maximum_degrees
                )[slot]
                local left_degree = Int32(@inbounds degrees[
                    endpoint_offset + left_anchor - Int32(1)
                ])
                local right_degree = Int32(@inbounds degrees[
                    endpoint_offset + right_anchor - Int32(1)
                ])
                for left_position in Int32(1):left_degree
                    local left_edge = @inbounds incidents[
                        incident_offset +
                        (left_anchor - Int32(1)) * maximum_degree +
                        left_position - Int32(1)
                    ]
                    for right_position in Int32(1):right_degree
                        left_edge == @inbounds(incidents[
                            incident_offset +
                            (right_anchor - Int32(1)) * maximum_degree +
                            right_position - Int32(1)
                        ]) && return true
                    end
                end
                return false
            end
            $branches
        end
    end
    return branches
end

@inline function _lifecycle_direct_relationship_conflict(
        bank_count::Val{B}, reads, left::Int32, right::Int32
    ) where {B}
    left_descriptor = @inbounds reads.descriptors[
        Int(reads.descriptor[left])
    ]
    right_descriptor = @inbounds reads.descriptors[
        Int(reads.descriptor[right])
    ]
    left_descriptor.relationship_rule_count > 0 || return false
    right_descriptor.relationship_rule_count > 0 || return false
    left_anchor = @inbounds reads.anchor[left]
    right_anchor = @inbounds reads.anchor[right]
    left_anchor > 0 && right_anchor > 0 || return false
    for left_offset in Int32(0):(left_descriptor.relationship_rule_count - 1)
        left_rule = @inbounds reads.relationship_rules[
            left_descriptor.relationship_rule_offset + left_offset
        ]
        for right_offset in Int32(0):(right_descriptor.relationship_rule_count - 1)
            right_rule = @inbounds reads.relationship_rules[
                right_descriptor.relationship_rule_offset + right_offset
            ]
            left_rule.relationship_slot == right_rule.relationship_slot || continue
            location = @inbounds reads.relationship_locations[
                left_rule.relationship_slot
            ]
            _lifecycle_packed_incident_conflict(
                bank_count,
                reads,
                location.bank,
                location.slot,
                left_anchor,
                right_anchor,
            ) && return true
        end
    end
    return false
end

@inline function _lifecycle_direct_requests_conflict(
        bank_count::Val, reads, left::Int32, right::Int32
    )
    left_anchor = @inbounds reads.anchor[left]
    right_anchor = @inbounds reads.anchor[right]
    left_anchor > 0 && left_anchor == right_anchor && return true
    left_count = Int32(@inbounds reads.planned_site_count[left])
    right_count = Int32(@inbounds reads.planned_site_count[right])
    for left_position in Int32(1):left_count
        left_site = @inbounds reads.planned_sites[left_position, left]
        for right_position in Int32(1):right_count
            left_site == @inbounds(
                reads.planned_sites[right_position, right]
            ) && return true
        end
    end
    return _lifecycle_direct_relationship_conflict(
        bank_count, reads, left, right
    )
end

@inline function _lifecycle_normalized_conflict(
        reads, left::Int32, right::Int32
    )
    left_key = _lifecycle_direct_request_order_key(reads, left)
    right_key = _lifecycle_direct_request_order_key(reads, right)
    return left_key <= right_key ?
        (left, right, (left_key..., right_key...)) :
        (right, left, (right_key..., left_key...))
end

struct _LifecycleSelectionSpace end
struct _LifecycleSelectedOrder end
@inline (::_LifecycleSelectedOrder)(value::_LifecycleSelectedRequest) = value.key
struct _LifecycleSelectedIdentity end
@inline (::_LifecycleSelectedIdentity)(value::_LifecycleSelectedRequest) =
    value.order_identity

function _allocate_lifecycle_selection_storage(
        plan::LifecycleExecutionPlan, ownership, relationships::RelationshipStorage
    )
    requests = Int(plan.maximum_requests)
    cells = Int(plan.cell_capacity)
    backend = KernelAbstractions.get_backend(ownership)
    free_cells = LocalMath.CompactedStorage(
        backend, _LifecycleFreeCell, cells; group_count = 1)
    demands = LocalMath.CompactedStorage(
        backend, _LifecycleDemand, requests; group_count = 1)
    selected_requests = LocalMath.CompactedStorage(
        backend, _LifecycleSelectedRequest, requests; source_position = true)
    success = ProgramStatus()
    return _LifecycleSelectionStorage(
        free_cells,
        demands,
        selected_requests,
        fill(false, requests),
        fill(false, requests),
        fill(false, requests),
        fill(false, 1),
        fill(false, 1),
        StructArrays.StructArray([
            _LifecycleConflictWitness(Int32(0), Int32(0))
        ]),
        StructArrays.StructArray([
            _LifecycleOverflowWitness(Int32(0), Int32(0))
        ]),
        StructArrays.StructArray(ProgramStatus[success]),
        StructArrays.StructArray(ProgramStatus[success]),
        StructArrays.StructArray(ProgramStatus[success]),
        zeros(Int32, 1),
        zeros(Int32, 1),
        zeros(Int32, 1),
        zeros(Int32, 1),
        zeros(Int32, requests),
        zeros(Int32, 1),
    )
end

function _lifecycle_relationship_read_storage(
        relationships::RelationshipStorage
    )
    names = Symbol[]
    arrays = Any[]
    for (index, bank) in enumerate(relationships.banks)
        bank isa PackedRelationshipBank || throw(ArgumentError(
            "runtime relationship storage must be packed"
        ))
        append!(names, (
            Symbol(:relationship_, index, :_degree),
            Symbol(:relationship_, index, :_incident_edges),
            Symbol(:relationship_, index, :_endpoint_offsets),
            Symbol(:relationship_, index, :_incident_offsets),
            Symbol(:relationship_, index, :_maximum_degrees),
        ))
        append!(arrays, (
            bank.degree,
            bank.incident_edges,
            bank.endpoint_offsets,
            bank.incident_offsets,
            bank.maximum_degrees,
        ))
    end
    return NamedTuple{Tuple(names)}(Tuple(arrays))
end

@inline function _lifecycle_selected_count(workspace::LifecycleWorkspace)
    @inbounds workspace.selection.ready[1] || return 0
    return Int(@inbounds workspace.selection.selected_requests.count[1])
end

@inline function _lifecycle_selected_record(
        workspace::LifecycleWorkspace, position::Integer
    )
    return @inbounds workspace.selection.selected_requests.records[position]
end

@inline function _lifecycle_selected_request(
        workspace::LifecycleWorkspace, position::Integer
    )
    return @inbounds workspace.selection.selected_requests.records.request[
        position
    ]
end

@inline function _lifecycle_selected_position(
        workspace::LifecycleWorkspace, request::Integer
    )
    @inbounds workspace.selection.ready[1] || return Int32(0)
    return @inbounds workspace.selection.selected_requests.source_position[
        Int(request)]
end

@inline function _lifecycle_request_selected(
        workspace::LifecycleWorkspace, request::Integer
    )
    return !iszero(_lifecycle_selected_position(workspace, request))
end

@inline function _lifecycle_request_allocation(
        workspace::LifecycleWorkspace, request::Integer
    )
    position = _lifecycle_selected_position(workspace, request)
    return iszero(position) ? Int32(0) :
        @inbounds(workspace.selection.selected_requests.records.allocation[
            position
        ])
end

struct _LifecycleSelectedCollectEvaluator end
@inline function (::_LifecycleSelectedCollectEvaluator)(
        request::Int32, reads, parameters)
    selected = something(@inbounds reads[1][1].value)
    allocation = something(@inbounds reads[2][1].value)
    key = (
        something(@inbounds(reads[3][1].value)),
        something(@inbounds(reads[4][1].value)),
        something(@inbounds(reads[5][1].value)),
        something(@inbounds(reads[6][1].value)),
        something(@inbounds(reads[7][1].value)),
        something(@inbounds(reads[8][1].value)),
    )
    return (selected_requests = LocalMath.CollectedValue(
        _LifecycleSelectedRequest(request, allocation, key, request),
        selected),)
end

@inline function _lifecycle_selection_transaction_device!(
        reads, current_mcs::Int64, ::Val{Stable}, ::Val{B},
    ) where {Stable,B}
    selection = reads.selection
    @inbounds begin
        selection.open[1] = reads.planning_open[1]
        selection.ready[1] = false
    end
    @inbounds(reads.planning_open[1]) || return
    requests = length(reads.active)
    canonical_count = Int(@inbounds reads.canonical_count[1])
    for request in 1:requests
        @inbounds begin
            selection.canonical[request] = false
            selection.selected[request] = false
            selection.selected_initial[request] = false
            selection.allocation[request] = Int32(0)
        end
    end
    @inbounds begin
        selection.conflict_left[1] = Int32(0)
        selection.conflict_right[1] = Int32(0)
        selection.conflict_witness[1] = _LifecycleConflictWitness(0, 0)
        selection.overflow_witness[1] = _LifecycleOverflowWitness(0, 0)
        selection.conflict_status[1] = ProgramStatus()
        selection.capacity_status[1] = ProgramStatus()
        selection.overflow_status[1] = ProgramStatus()
    end
    for position in 1:canonical_count
        request = @inbounds reads.canonical_slots[position]
        @inbounds selection.canonical[request] =
            _lifecycle_direct_request_is_canonical(reads, request)
    end

    conflict_left = Int32(0)
    conflict_right = Int32(0)
    if Stable
        for _ in 1:canonical_count
            next_request = Int32(0)
            next_rank = (
                typemax(UInt32), typemax(UInt32), typemax(UInt32),
                typemax(UInt32), typemax(UInt32), typemax(Int32),
                typemax(UInt32))
            for position in 1:canonical_count
                request = @inbounds reads.canonical_slots[position]
                @inbounds(selection.canonical[request]) || continue
                @inbounds(selection.selected_initial[request]) && continue
                key = (_lifecycle_descending_priority(
                    @inbounds(reads.priority[request])),
                    _lifecycle_direct_request_key(reads, request)...)
                if key < next_rank
                    next_rank = key
                    next_request = request
                end
            end
            iszero(next_request) && break
            @inbounds selection.selected_initial[next_request] = true
            blocked = false
            for other in 1:requests
                @inbounds(selection.selected[other]) || continue
                _lifecycle_direct_requests_conflict(
                    Val(B), reads, Int32(other), next_request) || continue
                other_priority = @inbounds reads.priority[other]
                next_priority = @inbounds reads.priority[next_request]
                if other_priority == next_priority
                    conflict_left = Int32(other)
                    conflict_right = next_request
                end
                blocked = true
                break
            end
            !blocked && @inbounds(selection.selected[next_request] = true)
            !iszero(conflict_left) && break
        end
        @inbounds begin
            selection.conflict_left[1] = conflict_left
            selection.conflict_right[1] = conflict_right
        end
    else
        best_rank = (
            typemax(UInt32), typemax(UInt32), typemax(UInt32),
            typemax(UInt32), typemax(Int32), typemax(UInt32),
            typemax(UInt32), typemax(UInt32), typemax(UInt32),
            typemax(UInt32), typemax(Int32), typemax(UInt32))
        for left in 1:requests
            @inbounds(selection.canonical[left]) || continue
            for right in (left + 1):requests
                @inbounds(selection.canonical[right]) || continue
                _lifecycle_direct_requests_conflict(
                    Val(B), reads, Int32(left), Int32(right)) || continue
                normalized_left, normalized_right, rank =
                    _lifecycle_normalized_conflict(
                        reads, Int32(left), Int32(right))
                if rank < best_rank
                    best_rank = rank
                    conflict_left = normalized_left
                    conflict_right = normalized_right
                end
            end
        end
        if iszero(conflict_left)
            for request in 1:requests
                @inbounds selection.selected[request] =
                    selection.canonical[request]
            end
        else
            @inbounds selection.conflict_witness[1] =
                _LifecycleConflictWitness(conflict_left, conflict_right)
        end
    end

    if !iszero(conflict_left)
        left_descriptor = @inbounds reads.descriptors[
            Int(reads.descriptor[conflict_left])]
        right_descriptor = @inbounds reads.descriptors[
            Int(reads.descriptor[conflict_right])]
        status = _lifecycle_backend_status(ProgramStatusConflict;
            mcs = Int32(current_mcs + 1), stage = ProgramStageSelection,
            source = left_descriptor.source_handle,
            action_identity = _lifecycle_first_action_for_source(
                reads.descriptors, left_descriptor.source_handle),
            secondary_source = right_descriptor.source_handle,
            anchor = @inbounds(reads.anchor[conflict_right]))
        @inbounds begin
            selection.conflict_status[1] = status
            reads.status[1] = status
        end
        for request in 1:requests
            @inbounds selection.selected_initial[request] = false
        end
        return
    end

    high_water = Int32(0)
    for cell in eachindex(reads.cell_generations)
        generation = @inbounds reads.cell_generations[cell]
        !iszero(generation) && (high_water = max(high_water, Int32(cell)))
    end
    @inbounds selection.high_water[1] = high_water
    free_count = Int32(0)
    for class in UInt32(0):UInt32(1)
        for cell in eachindex(reads.cell_kinds)
            kind = @inbounds reads.cell_kinds[cell]
            generation = @inbounds reads.cell_generations[cell]
            recycled = iszero(kind) && !iszero(generation)
            virgin = iszero(kind) && iszero(generation) && cell > high_water
            ((class == 0 && recycled) || (class == 1 && virgin)) || continue
            free_count += Int32(1)
            @inbounds begin
                selection.free_cells.records[free_count] = _LifecycleFreeCell(
                    Int32(1), Int32(cell), generation,
                    (class, Int32(cell)), Int32(cell))
                selection.free_cells.source_item[free_count] = Int32(cell)
                selection.free_cells.source_lane[free_count] = Int32(1)
            end
        end
    end
    @inbounds begin
        selection.free_cells.count[1] = free_count
        selection.free_cells.segment_starts[1] = Int32(1)
        selection.free_cells.segment_starts[2] = free_count + Int32(1)
    end
    demand_count = Int32(0)
    for _ in 1:canonical_count
        request = Int32(0)
        best_key = (
            typemax(UInt32), typemax(UInt32), typemax(UInt32),
            typemax(UInt32), typemax(Int32), typemax(UInt32))
        for position in 1:canonical_count
            candidate = @inbounds reads.canonical_slots[position]
            @inbounds(selection.selected[candidate]) || continue
            descriptor = @inbounds reads.descriptors[
                Int(reads.descriptor[candidate])]
            descriptor.effect in (
                CreateCellLifecycleEffect, DivideCellLifecycleEffect) || continue
            already_added = false
            for prior in Int32(1):demand_count
                already_added |= @inbounds(
                    selection.demands.records.request[prior]) == candidate
            end
            already_added && continue
            key = _lifecycle_direct_request_order_key(reads, candidate)
            if key < best_key
                best_key = key
                request = candidate
            end
        end
        iszero(request) && break
        demand_count += Int32(1)
        @inbounds begin
            selection.demands.records[demand_count] = _LifecycleDemand(
                Int32(1), request,
                _lifecycle_direct_request_order_key(reads, request), request)
            selection.demands.source_item[demand_count] = request
            selection.demands.source_lane[demand_count] = Int32(1)
        end
    end
    @inbounds begin
        selection.demands.count[1] = demand_count
        selection.demands.segment_starts[1] = Int32(1)
        selection.demands.segment_starts[2] = demand_count + Int32(1)
    end
    if demand_count > free_count
        request = _lifecycle_first_publication_request(Val(Stable), reads)
        descriptor = @inbounds reads.descriptors[Int(reads.descriptor[request])]
        status = _lifecycle_backend_status(ProgramStatusCellCapacity;
            mcs = Int32(current_mcs + 1), stage = ProgramStageSelection,
            source = descriptor.source_handle,
            action_identity = descriptor.action_identity,
            required = demand_count, available = free_count,
            maximum = Int32(length(reads.cell_kinds)))
        @inbounds begin
            selection.capacity_status[1] = status
            reads.status[1] = status
        end
        for request in 1:requests
            @inbounds selection.selected_initial[request] = false
        end
        return
    end
    for position in Int32(1):demand_count
        generation = @inbounds selection.free_cells.records.generation[position]
        if generation == typemax(UInt32)
            request = @inbounds selection.demands.records.request[position]
            cell = @inbounds selection.free_cells.records.cell[position]
            source = Int32(0)
            action_identity = UInt64(0)
            publication_request = _lifecycle_first_publication_request(
                Val(Stable), reads; anchor = cell)
            if publication_request > 0
                descriptor = @inbounds reads.descriptors[
                    Int(reads.descriptor[publication_request])]
                source = descriptor.source_handle
                action_identity = descriptor.action_identity
            end
            status = _lifecycle_backend_status(ProgramStatusGenerationOverflow;
                mcs = Int32(current_mcs + 1), stage = ProgramStageSelection,
                source, action_identity, anchor = cell)
            @inbounds begin
                selection.overflow_witness[1] =
                    _LifecycleOverflowWitness(request, cell)
                selection.overflow_status[1] = status
                reads.status[1] = status
            end
            for slot in 1:requests
                @inbounds selection.selected_initial[slot] = false
            end
            return
        end
        request = @inbounds selection.demands.records.request[position]
        @inbounds selection.allocation[request] =
            selection.free_cells.records.cell[position]
    end
    @inbounds begin
        reads.status[1] = ProgramStatus()
        selection.ready[1] = true
    end
    for request in 1:requests
        @inbounds selection.selected_initial[request] =
            selection.selected[request]
    end
end

@kernel function _lifecycle_selection_transaction_kernel!(
        reads, current_mcs::Int64, stable::Val, banks::Val)
    index = @index(Global, Linear)
    if index == 1
        _lifecycle_selection_transaction_device!(
            reads, current_mcs, stable, banks)
    end
end

struct _PreparedLifecycleSelection{Stable,Banks,B,R,P,W}
    backend::B
    reads::R
    publication::P
    plan::W
end
LocalMath.execution_contract(prepared::_PreparedLifecycleSelection) =
    LocalMath.execution_contract(prepared.publication)
LocalMath.inspect(prepared::_PreparedLifecycleSelection) =
    LocalMath.inspect(prepared.publication)
LocalMath.success_gate(prepared::_PreparedLifecycleSelection, parent) =
    LocalMath.success_gate(prepared.publication, parent)
LocalMath.submission_capacity(prepared::_PreparedLifecycleSelection) =
    LocalMath.submission_capacity(prepared.publication)
function LocalMath.execute!(
        prepared::_PreparedLifecycleSelection{Stable,Banks};
        parameters::NamedTuple = (;), dependencies::Tuple = (),
    ) where {Stable,Banks}
    current_mcs = Int64(parameters.current_mcs)
    _lifecycle_selection_transaction_kernel!(prepared.backend)(
        prepared.reads, current_mcs, Val(Stable), Val(Banks); ndrange = 1)
    return LocalMath.execute!(prepared.publication; dependencies)
end

function _lifecycle_selected_publication(plan, selection, reads, backend;
        lease_capacity)
    requests = Int(plan.maximum_requests)
    source = LocalMath.Space(_LifecycleSelectionSpace, requests)
    identity = LocalMath.IdentityRelation(source)
    selected = LocalMath.Field(source, Bool)
    allocation = LocalMath.Field(source, Int32)
    source_high = LocalMath.Field(source, UInt32)
    source_low = LocalMath.Field(source, UInt32)
    action_high = LocalMath.Field(source, UInt32)
    action_low = LocalMath.Field(source, UInt32)
    anchor = LocalMath.Field(source, Int32)
    generation = LocalMath.Field(source, UInt32)
    collection = LocalMath.Collection(_LifecycleSelectedRequest, requests)
    accesses = (
        selected = LocalMath.Access(selected, identity),
        allocation = LocalMath.Access(allocation, identity),
        source_high = LocalMath.Access(source_high, identity),
        source_low = LocalMath.Access(source_low, identity),
        action_high = LocalMath.Access(action_high, identity),
        action_low = LocalMath.Access(action_low, identity),
        anchor = LocalMath.Access(anchor, identity),
        generation = LocalMath.Access(generation, identity),
    )
    publication = LocalMath.Publication((
        LocalMath.CollectionPublication(collection,
            LocalMath.PublicationValue(:selected_requests)),),
        LocalMath.Collect(_LifecycleSelectedRequest;
            order = LocalMath.canonical_by(
                _LifecycleSelectedOrder(), _LifecycleSelectedIdentity()),
            projection = LocalMath.persistent_source_position()))
    stage = LocalMath.Stage(source, accesses, (publication,),
        LocalMath.Evaluator(_LifecycleSelectedCollectEvaluator()),
        LocalMath.Control(),
        LocalMath.SourceOrigin(@__FILE__, @__LINE__;
            label = :lifecycle_selected_publication))
    work = LocalMath.LocalLaw(stage)
    return LocalMath.prepare(work,
        selected => selection.selected_initial,
        allocation => selection.allocation,
        source_high => reads.source_high,
        source_low => reads.source_low,
        action_high => reads.action_high,
        action_low => reads.action_low,
        anchor => reads.anchor,
        generation => reads.generation,
        collection => selection.selected_requests;
        backend, lease_capacity = Int(lease_capacity))
end

function _prepare_lifecycle_selection(
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
        science,
        gate;
        lease_capacity::Integer = 1,
    )
    backend = KernelAbstractions.get_backend(science.ownership)
    runtime = science
    relationships = runtime.relationships
    selection = workspace.selection
    reads = merge((
        bank_count = Int32(length(relationships.banks)),
        selection,
        active = workspace.active,
        planning_open = gate,
        priority = workspace.request_priority,
        source_high = workspace.request_source_high,
        source_low = workspace.request_source_low,
        action_high = workspace.request_action_high,
        action_low = workspace.request_action_low,
        anchor = workspace.anchor,
        generation = workspace.generation,
        canonical = selection.canonical,
        canonical_slots = workspace.request_index.records.slot,
        canonical_count = workspace.request_index.count,
        descriptor = workspace.descriptor,
        descriptors = runtime.program.lifecycle_plan.descriptors,
        planned_site_count = workspace.planned_site_count,
        planned_sites = workspace.planned_sites,
        relationship_rules = runtime.program.lifecycle_plan.relationship_rules,
        relationship_locations = relationships.slots,
        selected = selection.selected,
        selected_initial = selection.selected_initial,
        conflict_left = selection.conflict_left,
        conflict_left_initial = selection.conflict_left_initial,
        conflict_right = selection.conflict_right,
        conflict_right_initial = selection.conflict_right_initial,
        conflict_status = selection.conflict_status,
        conflict_witness = selection.conflict_witness,
        overflow_witness = selection.overflow_witness,
        capacity_status = selection.capacity_status,
        overflow_status = selection.overflow_status,
        selection_ready = selection.ready,
        demands = selection.demands,
        cell_kinds = runtime.cell_kinds,
        cell_generations = runtime.cell_generations,
        high_water = selection.high_water,
        free_cells = selection.free_cells,
        allocation = selection.allocation,
        selected_requests = selection.selected_requests,
        status = workspace.status,
    ),
        _lifecycle_relationship_read_storage(relationships),
    )
    publication = _lifecycle_selected_publication(
        plan, selection, reads, backend; lease_capacity)
    stable = plan.conflict_policy === StablePriorityLifecycleConflicts
    return _PreparedLifecycleSelection{
        stable,length(relationships.banks),typeof(backend),typeof(reads),
        typeof(publication),typeof(publication.plan)
    }(backend, reads, publication, publication.plan)
end
