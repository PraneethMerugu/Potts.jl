# Immutable lifecycle evaluator contexts and their resource protocol.

struct _LifecycleTriggerContext{R, I} <:
       AbstractLifecycleTriggerEvaluationContext
    runtime::R
    source_identity::UInt64
    action_identity::UInt64
    workspace_maximum::Int32
    workspace_offset::Int32
    workspace_slot::Int32
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
end

struct _LifecyclePlacementContext{R, I} <:
       AbstractLifecyclePlacementEvaluationContext
    runtime::R
    source_identity::UInt64
    action_identity::UInt64
    workspace_maximum::Int32
    workspace_offset::Int32
    workspace_slot::Int32
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
end

struct _LifecyclePartitionContext{R, I} <:
       AbstractLifecyclePartitionEvaluationContext
    runtime::R
    source_identity::UInt64
    action_identity::UInt64
    workspace_maximum::Int32
    workspace_offset::Int32
    workspace_slot::Int32
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
end

struct _LifecycleStateContext{R, P, I, H} <:
       AbstractLifecycleStateTransformEvaluationContext
    runtime::R
    planned::P
    source_identity::UInt64
    action_identity::UInt64
    workspace_maximum::Int32
    workspace_offset::Int32
    workspace_slot::Int32
    anchor::Int32
    generation::UInt32
    source::Int32
    source_generation::UInt32
    destination::Int32
    destination_generation::UInt32
    role::LifecycleStateRoleCode
    state_identity::UInt64
    state_handle::H
    site::I
    occurrence::Int32
    operation::UInt16
end

"""Read-only request-local planned view over one common lifecycle snapshot."""
struct _LifecycleRequestView{R, W, D}
    runtime::R
    workspace::W
    descriptor::D
    request::Int32
end

const _LifecycleContext = Union{
    _LifecycleTriggerContext,
    _LifecyclePlacementContext,
    _LifecyclePartitionContext,
    _LifecycleStateContext,
}

@inline lifecycle_anchor(context::_LifecycleContext) = context.anchor
@inline lifecycle_site(context::_LifecycleContext) = context.site
@inline lifecycle_occurrence(context::_LifecycleContext) = context.occurrence
@inline lifecycle_source_identity(context::_LifecycleContext) =
    context.source_identity
@inline lifecycle_action_identity(context::_LifecycleContext) =
    context.action_identity
@inline lifecycle_workspace_capacity(context::_LifecycleContext) =
    context.workspace_maximum

@inline function _lifecycle_workspace_column(context::_LifecycleContext)
    return Int(context.workspace_slot)
end

@inline function lifecycle_workspace_value(
        context::_LifecycleContext, index::Integer
    )
    @boundscheck 1 <= index <= context.workspace_maximum || throw(BoundsError(
        context.runtime.lifecycle_workspace.policy_workspace,
        (index, _lifecycle_workspace_column(context)),
    ))
    return @inbounds context.runtime.lifecycle_workspace.policy_workspace[
        Int(context.workspace_offset) + index, _lifecycle_workspace_column(context)
    ]
end

@inline function set_lifecycle_workspace_value!(
        context::_LifecycleContext, value, index::Integer
    )
    @boundscheck 1 <= index <= context.workspace_maximum || throw(BoundsError(
        context.runtime.lifecycle_workspace.policy_workspace,
        (index, _lifecycle_workspace_column(context)),
    ))
    @inbounds context.runtime.lifecycle_workspace.policy_workspace[
        Int(context.workspace_offset) + index, _lifecycle_workspace_column(context)
    ] = value
    return value
end

struct LifecycleWorkspaceOperation{F} <: AbstractContextualOperation
    operation::F
    offset::Int32
    maximum::Int32
end

function LifecycleWorkspaceOperation(
        operation, offset::Integer, maximum::Integer
    )
    0 <= offset <= typemax(Int32) || throw(ArgumentError(
        "lifecycle workspace offset is outside Int32"
    ))
    0 <= maximum <= typemax(Int32) || throw(ArgumentError(
        "lifecycle workspace maximum is outside Int32"
    ))
    return LifecycleWorkspaceOperation(
        operation, Int32(offset), Int32(maximum)
    )
end

operation_context_supported(
    operation::LifecycleWorkspaceOperation,
    context::Type{<:AbstractEvaluatorExecutionContext},
) = operation_context_supported(operation.operation, context)

function _lifecycle_workspace_slice(
        context::_LifecycleTriggerContext, offset::Int32, maximum::Int32
    )
    return _LifecycleTriggerContext(
        context.runtime,
        context.source_identity,
        context.action_identity,
        maximum,
        context.workspace_offset + offset,
        context.workspace_slot,
        context.anchor,
        context.generation,
        context.site,
        context.occurrence,
        context.operation,
    )
end

function _lifecycle_workspace_slice(
        context::_LifecyclePlacementContext, offset::Int32, maximum::Int32
    )
    return _LifecyclePlacementContext(
        context.runtime,
        context.source_identity,
        context.action_identity,
        maximum,
        context.workspace_offset + offset,
        context.workspace_slot,
        context.anchor,
        context.generation,
        context.site,
        context.occurrence,
        context.operation,
    )
end


function _lifecycle_workspace_slice(
        context::_LifecyclePartitionContext, offset::Int32, maximum::Int32
    )
    return _LifecyclePartitionContext(
        context.runtime,
        context.source_identity,
        context.action_identity,
        maximum,
        context.workspace_offset + offset,
        context.workspace_slot,
        context.anchor,
        context.generation,
        context.site,
        context.occurrence,
        context.operation,
    )
end

function _lifecycle_workspace_slice(
        context::_LifecycleStateContext, offset::Int32, maximum::Int32
    )
    return _LifecycleStateContext(
        context.runtime,
        context.planned,
        context.source_identity,
        context.action_identity,
        maximum,
        context.workspace_offset + offset,
        context.workspace_slot,
        context.anchor,
        context.generation,
        context.source,
        context.source_generation,
        context.destination,
        context.destination_generation,
        context.role,
        context.state_identity,
        context.state_handle,
        context.site,
        context.occurrence,
        context.operation,
    )
end

@inline function (operation::LifecycleWorkspaceOperation)(
        arguments::Tuple,
        context::AbstractEvaluatorExecutionContext,
    )
    sliced = _lifecycle_workspace_slice(
        context, operation.offset, operation.maximum
    )
    return operation.operation(arguments, sliced)
end

@inline lifecycle_source_cell(context::_LifecycleStateContext) = context.source
@inline lifecycle_source_generation(context::_LifecycleStateContext) =
    context.source_generation
@inline lifecycle_destination_cell(context::_LifecycleStateContext) =
    context.destination
@inline lifecycle_destination_generation(context::_LifecycleStateContext) =
    context.destination_generation
@inline lifecycle_state_role(context::_LifecycleStateContext) = context.role
@inline lifecycle_state_identity(context::_LifecycleStateContext) =
    context.state_identity

@inline function lifecycle_before_state_value(context::_LifecycleStateContext)
    index = context.source > 0 ? context.source : context.destination
    index > 0 || return zero(eltype(state_block(
        context.runtime.descriptor_state, context.state_handle
    ).values))
    return @inbounds state_block(
        context.runtime.descriptor_state, context.state_handle
    ).values[index]
end

@inline function lifecycle_planned_state_value(context::_LifecycleStateContext)
    index = context.role in (
        DestinationLifecycleStateRole, DaughterLifecycleStateRole,
    ) ? context.destination : context.source
    values = state_block(
        context.runtime.descriptor_state, context.state_handle
    ).values
    index > 0 || return zero(eltype(values))
    return @inbounds state_block(
        context.runtime.descriptor_state,
        context.state_handle,
    ).values[index]
end
@inline _lifecycle_value_runtime(context::_LifecycleContext) = context.runtime
@inline _lifecycle_value_runtime(context::_LifecycleStateContext) = context.planned
@inline evaluator_parameters(context::_LifecycleContext) = context.runtime.parameters
@inline _compiled_evaluator_parameters(context::_LifecycleContext) =
    context.runtime.parameters

@inline context_value(
    ::ContextOperation{:energy_anchor_cell}, context::_LifecycleContext
) = context.anchor

@inline function _compiled_context_value(
        operation::ContextOperation{Identity}, context::_LifecycleContext
    ) where {Identity}
    return context_value(operation, context)
end

@inline function state_value(
        context::_LifecycleContext, handle::StateHandle, index
    )
    return @inbounds state_block(
        context.runtime.descriptor_state, handle
    ).values[index]
end

@inline function apply_resource_operation(
    ::ResourceOperation{:cell_volume}, arguments, context::_LifecycleContext
)
    cell = Int32(only(arguments))
    cell <= 0 && return Int32(0)
    return program_tracker_value(
        _lifecycle_value_runtime(context), Val(:cell_volume), cell
    )
end

@inline function _lifecycle_planned_owner(view::_LifecycleRequestView, linear::Int)
    runtime = view.runtime
    workspace = view.workspace
    descriptor = view.descriptor
    request = Int(view.request)
    owner = @inbounds runtime.ownership[linear]
    if descriptor.effect === CreateCellLifecycleEffect
        @inbounds(workspace.planned_site_request[linear]) == request &&
            return @inbounds workspace.allocation[request]
    elseif descriptor.effect === RemoveCellLifecycleEffect
        anchor = @inbounds workspace.anchor[request]
        owner == anchor && return -Int32(descriptor.replacement_medium)
    elseif descriptor.effect === DivideCellLifecycleEffect
        anchor = @inbounds workspace.anchor[request]
        if owner == anchor &&
                @inbounds(workspace.partition_owner[anchor]) == request
            position = Int(@inbounds workspace.site_position[linear])
            position > 0 && @inbounds(workspace.partition_labels[position]) == 2 &&
                return @inbounds workspace.allocation[request]
        end
    end
    return owner
end

@inline function _lifecycle_request_owns_cell(
        view::_LifecycleRequestView, cell::Int32
    )
    workspace = view.workspace
    request = Int(view.request)
    descriptor = view.descriptor
    anchor = @inbounds workspace.anchor[request]
    allocation = @inbounds workspace.allocation[request]
    descriptor.effect === CreateCellLifecycleEffect &&
        return cell == allocation
    descriptor.effect === DivideCellLifecycleEffect &&
        return cell == anchor || cell == allocation
    return cell == anchor
end

@inline function _lifecycle_request_change_count(view::_LifecycleRequestView)
    workspace = view.workspace
    request = Int(view.request)
    effect = view.descriptor.effect
    effect === CreateCellLifecycleEffect &&
        return Int(@inbounds workspace.planned_site_count[request])
    if effect in (RemoveCellLifecycleEffect, DivideCellLifecycleEffect)
        anchor = @inbounds workspace.anchor[request]
        return Int(@inbounds workspace.cell_site_counts[anchor])
    end
    return 0
end

@inline function _lifecycle_request_change(
        view::_LifecycleRequestView, position::Int
    )
    runtime = view.runtime
    workspace = view.workspace
    request = Int(view.request)
    descriptor = view.descriptor
    if descriptor.effect === CreateCellLifecycleEffect
        linear = Int(@inbounds workspace.planned_sites[position, request])
        old_owner = @inbounds runtime.ownership[linear]
        new_owner = @inbounds workspace.allocation[request]
        return linear, old_owner, new_owner, old_owner != new_owner
    end
    anchor = @inbounds workspace.anchor[request]
    offset = Int(@inbounds workspace.cell_site_starts[anchor]) + position - 1
    linear = Int(@inbounds workspace.cell_sites[offset])
    old_owner = @inbounds runtime.ownership[linear]
    if descriptor.effect === RemoveCellLifecycleEffect
        new_owner = -Int32(descriptor.replacement_medium)
        return linear, old_owner, new_owner, old_owner != new_owner
    end
    changed = descriptor.effect === DivideCellLifecycleEffect &&
              @inbounds(workspace.partition_owner[anchor]) == request &&
              @inbounds(workspace.partition_labels[offset]) == 2
    new_owner = changed ? @inbounds(workspace.allocation[request]) : old_owner
    return linear, old_owner, new_owner, changed
end

@inline function _lifecycle_site_changed(
        view::_LifecycleRequestView, linear::Int
    )
    return @inbounds(view.runtime.ownership[linear]) !=
           _lifecycle_planned_owner(view, linear)
end

@inline function _lifecycle_planned_kind(
        view::_LifecycleRequestView, cell::Int32
    )
    cell > 0 || return view.runtime.program.medium_kind
    descriptor = view.descriptor
    workspace = view.workspace
    request = Int(view.request)
    anchor = @inbounds workspace.anchor[request]
    allocation = @inbounds workspace.allocation[request]
    if descriptor.effect === CreateCellLifecycleEffect && cell == allocation
        return descriptor.destination_kind
    elseif descriptor.effect in (
            RetireCellLifecycleEffect, RemoveCellLifecycleEffect,
        ) && cell == anchor
        return Int16(0)
    elseif descriptor.effect === TransitionCellLifecycleEffect && cell == anchor
        return descriptor.destination_kind
    elseif descriptor.effect === DivideCellLifecycleEffect
        cell == anchor && return descriptor.parent_kind == 0 ?
            @inbounds(view.runtime.cell_kinds[anchor]) : descriptor.parent_kind
        cell == allocation && return descriptor.daughter_kind == 0 ?
            @inbounds(view.runtime.cell_kinds[anchor]) : descriptor.daughter_kind
    end
    return @inbounds view.runtime.cell_kinds[cell]
end

@inline _owner_kind(view::_LifecycleRequestView, owner::Int32) =
    owner > 0 ? _lifecycle_planned_kind(view, owner) :
    owner == 0 ? view.runtime.program.medium_kind : Int16(-owner)

function _lifecycle_planned_volume(view::_LifecycleRequestView, cell::Int32)
    cell > 0 || return Int32(0)
    trackers = _lifecycle_request_owns_cell(view, cell) ?
        view.workspace.staged_trackers : view.runtime.trackers
    return tracker_value(
        view.runtime.program.tracker_plan,
        trackers,
        Val(:cell_volume),
        cell,
    )
end

@inline program_tracker_value(
    view::_LifecycleRequestView, ::Val{:cell_volume}, cell::Integer
) = _lifecycle_planned_volume(view, Int32(cell))

function _lifecycle_planned_surface(
        view::_LifecycleRequestView,
        source_handle::Int32,
        cell::Int32,
    )
    cell > 0 || return Int32(0)
    resources = view.runtime.program.descriptor_plan.domain_resources
    shape = view.runtime.program.shape
    periodic = view.runtime.program.periodic
    for dimension in eachindex(shape)
        if shape[dimension] <= 0
            _set_lifecycle_status!(
                view.workspace,
                LifecycleStatusInvariant;
                source = source_handle,
                anchor = cell,
                detail = LifecycleDetailTrackerStorageInvalid,
                required = Int32(dimension),
                available = Int32(shape[dimension]),
            )
            return Int32(0)
        end
    end
    if !(1 <= source_handle <= length(resources.contact_starts)) ||
            @inbounds(resources.contact_starts[source_handle]) <= 0 ||
            @inbounds(resources.contact_counts[source_handle]) <= 0
        _set_lifecycle_status!(
            view.workspace,
            LifecycleStatusInvariant;
            source = source_handle,
            anchor = cell,
            detail = LifecycleDetailTrackerStorageInvalid,
        )
        return Int32(0)
    end
    start, count = _contact_domain_columns(resources, source_handle)
    result = qualified_tracker_value(
        view.runtime.program.tracker_plan,
        view.runtime.trackers,
        Val(:cell_surface),
        source_handle,
        cell,
    )
    indices = CartesianIndices(view.runtime.ownership)
    linear_indices = LinearIndices(view.runtime.ownership)
    for position in 1:_lifecycle_request_change_count(view)
        linear, old_owner, new_owner, changed =
            _lifecycle_request_change(view, position)
        changed || continue
        site = indices[linear]
        for direction in 1:count
            neighbor = relation_neighbor_index(
                shape,
                periodic,
                site,
                resources.contact_offsets,
                start + direction - 1,
            )
            neighbor === nothing && continue
            neighbor == site && continue
            duplicate = false
            for prior in 1:(direction - 1)
                prior_neighbor = relation_neighbor_index(
                    shape,
                    periodic,
                    site,
                    resources.contact_offsets,
                    start + prior - 1,
                )
                if prior_neighbor == neighbor
                    duplicate = true
                    break
                end
            end
            duplicate && continue
            neighbor_linear = linear_indices[neighbor]
            old_neighbor = @inbounds view.runtime.ownership[neighbor_linear]
            new_neighbor = _lifecycle_planned_owner(view, neighbor_linear)
            before = old_owner == cell && old_neighbor != cell
            after = new_owner == cell && new_neighbor != cell
            result += Int32(after) - Int32(before)

            _lifecycle_site_changed(view, neighbor_linear) && continue
            for reverse_direction in 1:count
                reverse_neighbor = relation_neighbor_index(
                    shape,
                    periodic,
                    neighbor,
                    resources.contact_offsets,
                    start + reverse_direction - 1,
                )
                reverse_neighbor == site || continue
                reverse_duplicate = false
                for prior in 1:(reverse_direction - 1)
                    prior_neighbor = relation_neighbor_index(
                        shape,
                        periodic,
                        neighbor,
                        resources.contact_offsets,
                        start + prior - 1,
                    )
                    if prior_neighbor == reverse_neighbor
                        reverse_duplicate = true
                        break
                    end
                end
                reverse_duplicate && continue
                reverse_before = old_neighbor == cell && old_owner != cell
                reverse_after = old_neighbor == cell && new_owner != cell
                result += Int32(reverse_after) - Int32(reverse_before)
            end
        end
    end
    return result
end

@inline function apply_resource_operation(
        ::ResourceOperation{:cell_surface}, arguments, context::_LifecycleContext
    )
    throw(ArgumentError(
        "cell_surface requires a compiler-bound tracker resource"
    ))
end

@inline function qualified_tracker_operation_call(
        ::ResourceOperation{:cell_surface},
        arguments::Tuple,
        context::_LifecycleContext,
        quantity::Val,
        source_handle::Int32,
    )
    cell = Int32(only(arguments))
    cell <= 0 && return Int32(0)
    runtime = _lifecycle_value_runtime(context)
    runtime isa _LifecycleRequestView && return _lifecycle_planned_surface(
        runtime, source_handle, cell
    )
    return qualified_tracker_value(
        runtime.program.tracker_plan,
        runtime.trackers,
        quantity,
        source_handle,
        cell,
    )
end

function _lifecycle_planned_shape_statistics(
        view::_LifecycleRequestView, cell::Int32
    )
    T = eltype(view.runtime.parameters)
    N = length(view.runtime.program.shape)
    trackers = _lifecycle_request_owns_cell(view, cell) ?
        view.workspace.staged_trackers : view.runtime.trackers
    plan = view.runtime.program.tracker_plan
    count = Int32(tracker_value(plan, trackers, Val(:cell_volume), cell))
    iszero(count) && return nothing
    moments = tracker_values(plan, trackers, Val(:cell_moments))
    inverse = inv(T(count))
    center = ntuple(N) do dimension
        @inbounds(moments.first[dimension, Int(cell)]) * inverse
    end
    covariance = ntuple(N * N) do slot
        row = rem(slot - 1, N) + 1
        column = div(slot - 1, N) + 1
        @inbounds(moments.second[slot, Int(cell)]) * inverse -
            center[row] * center[column]
    end
    return count, center, covariance
end

@inline function _cell_center(view::_LifecycleRequestView, cell::Int32)
    statistics = _lifecycle_planned_shape_statistics(view, cell)
    return statistics === nothing ? nothing : statistics[2]
end

@inline function _cell_length(view::_LifecycleRequestView, cell::Int32)
    T = eltype(view.runtime.parameters)
    statistics = _lifecycle_planned_shape_statistics(view, cell)
    statistics === nothing && return zero(T)
    covariance = statistics[3]
    maximum_variance = _maximum_covariance_eigenvalue(
        Val(length(view.runtime.program.shape)), covariance
    )
    return T(4) * sqrt(max(zero(T), maximum_variance))
end

@inline function _compiled_qualified_tracker_operation(
        operation::QualifiedTrackerOperation,
        arguments::Tuple,
        context::_LifecycleContext,
    )
    return qualified_tracker_operation_call(
        operation.operation,
        arguments,
        context,
        operation.quantity,
        operation.source_handle,
    )
end

@inline apply_resource_operation(
    ::ResourceOperation{:cell_center}, arguments, context::_LifecycleContext
) = _cell_center(_lifecycle_value_runtime(context), Int32(only(arguments)))

@inline apply_resource_operation(
    ::ResourceOperation{:unwrapped_center}, arguments, context::_LifecycleContext
) = _cell_center(_lifecycle_value_runtime(context), Int32(only(arguments)))

@inline apply_resource_operation(
    ::ResourceOperation{:cell_elongation}, arguments, context::_LifecycleContext
) = _cell_length(_lifecycle_value_runtime(context), Int32(only(arguments)))

@inline function apply_resource_operation(
        ::ResourceOperation{:field_value}, arguments, context::_LifecycleContext
    )
    return state_value(context, first(arguments), last(arguments))
end

@inline function apply_resource_operation(
        ::ResourceOperation{:history_value}, arguments, context::_LifecycleContext
    )
    handle = first(arguments)
    indices = Base.tail(arguments)
    return @inbounds state_block(
        context.runtime.descriptor_state, handle
    ).values[indices...]
end

@inline function apply_resource_operation(
        ::ResourceOperation{:occupancy}, arguments, context::_LifecycleContext
    )
    kind = Int16(first(arguments))
    runtime = _lifecycle_value_runtime(context)
    owner = runtime isa _LifecycleRequestView ?
        _lifecycle_planned_owner(
            runtime, LinearIndices(runtime.runtime.ownership)[last(arguments)]
        ) : @inbounds(runtime.ownership[last(arguments)])
    return _owner_kind(runtime, owner) == kind
end

@inline function apply_resource_operation(
        ::ResourceOperation{:degree}, arguments, context::_LifecycleContext
    )
    relationship_handle = Int32(first(arguments))
    endpoint = Int32(last(arguments))
    endpoint <= 0 && return Int32(0)
    runtime = _lifecycle_value_runtime(context)
    base_runtime = runtime isa _LifecycleRequestView ? runtime.runtime : runtime
    slot = _relationship_domain_slot(
        base_runtime.program.descriptor_plan.domain_resources,
        relationship_handle,
    )
    runtime isa _LifecycleRequestView && return
        _lifecycle_planned_relationship_degree(runtime, slot, endpoint)
    return _call_relationship_slot(
        _relationship_degree, runtime.relationships, slot, (endpoint,)
    )
end

@inline function _lifecycle_relationship_edge_survives(
        view::_LifecycleRequestView, slot::Int32, edge::Int, state
    )
    workspace = view.workspace
    descriptor = view.descriptor
    request = Int(view.request)
    anchor = @inbounds workspace.anchor[request]
    a = @inbounds state.endpoint_a[edge]
    b = @inbounds state.endpoint_b[edge]
    (a == anchor || b == anchor) || return true
    other = a == anchor ? b : a
    plan = view.runtime.program.lifecycle_plan
    for offset in 0:(Int(descriptor.relationship_rule_count) - 1)
        rule = @inbounds plan.relationship_rules[
            Int(descriptor.relationship_rule_offset) + offset
        ]
        rule.relationship_slot == slot || continue
        rule.action === RemoveIncidentLifecycleRelationship && return false
        if rule.action === RemoveIncompatibleLifecycleRelationship
            other_kind = _lifecycle_planned_kind(view, other)
            _relationship_kinds_match(
                descriptor.destination_kind, other_kind, rule
            ) || return false
        end
    end
    return true
end

function _lifecycle_planned_relationship_degree(
        view::_LifecycleRequestView, slot::Int32, endpoint::Int32
    )
    request = Int(view.request)
    allocation = @inbounds view.workspace.allocation[request]
    descriptor = view.descriptor
    if endpoint == allocation && descriptor.effect in (
            CreateCellLifecycleEffect, DivideCellLifecycleEffect,
        )
        return Int32(0)
    end
    state = view.runtime.relationships[Int(slot)]
    result = Int32(0)
    for edge in eachindex(state.active)
        @inbounds state.active[edge] || continue
        a = @inbounds state.endpoint_a[edge]
        b = @inbounds state.endpoint_b[edge]
        (a == endpoint || b == endpoint) || continue
        _lifecycle_relationship_edge_survives(view, slot, edge, state) &&
            (result += Int32(1))
    end
    return result
end

@inline function apply_resource_operation(
        ::ResourceOperation{:draw}, arguments, context::_LifecycleContext
    )
    T = eltype(context.runtime.parameters)
    family = Int(arguments[1])
    first_parameter = T(arguments[2])
    second_parameter = T(arguments[3])
    operation = UInt16(arguments[4])
    stream = context isa _LifecycleTriggerContext ? LifecycleTriggerStream :
        context isa _LifecyclePlacementContext ? LifecyclePlacementStream :
        context isa _LifecyclePartitionContext ? LifecyclePartitionStream :
        LifecycleStateStream
    destination_address = context isa _LifecycleStateContext &&
        context.role in (
            DestinationLifecycleStateRole, DaughterLifecycleStateRole,
        )
    address_anchor = destination_address ? context.destination : context.anchor
    address_generation = destination_address ?
        context.destination_generation : context.generation
    first_uniform = _lifecycle_uniform(
        T,
        context.runtime,
        stream,
        operation,
        address_anchor,
        address_generation,
        context.occurrence;
        destination = destination_address,
        draw = 0,
    )
    family == 1 && return first_uniform < first_parameter
    family == 2 && return muladd(
        first_uniform, second_parameter - first_parameter, first_parameter
    )
    if family == 3
        iszero(second_parameter) && return first_parameter
        second_uniform = _lifecycle_uniform(
            T,
            context.runtime,
            stream,
            operation,
            address_anchor,
            address_generation,
            context.occurrence;
            destination = destination_address,
            draw = 1,
        )
        normal = sqrt(-T(2) * log(first_uniform)) *
                 cos(T(2pi) * second_uniform)
        return muladd(second_parameter, normal, first_parameter)
    end
    return T(NaN)
end

@inline function _compiled_resource_operation(
        operation::ResourceOperation{Identity},
        arguments::Tuple,
        context::_LifecycleContext,
    ) where {Identity}
    return apply_resource_operation(operation, arguments, context)
end
