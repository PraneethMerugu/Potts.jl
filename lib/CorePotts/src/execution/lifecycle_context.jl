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
        for position in 1:Int(@inbounds workspace.planned_site_count[request])
            @inbounds(workspace.planned_sites[position, request]) == linear &&
                return @inbounds workspace.allocation[request]
        end
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
    count = Int32(0)
    for linear in eachindex(view.runtime.ownership)
        _lifecycle_planned_owner(view, Int(linear)) == cell &&
            (count += Int32(1))
    end
    return count
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
    start, count = _contact_domain_columns(resources, source_handle)
    result = Int32(0)
    indices = CartesianIndices(view.runtime.ownership)
    for linear in eachindex(view.runtime.ownership)
        _lifecycle_planned_owner(view, Int(linear)) == cell || continue
        site = indices[linear]
        for direction in 1:count
            neighbor = relation_neighbor_index(
                view.runtime.program.shape,
                view.runtime.program.periodic,
                site,
                resources.contact_offsets,
                start + direction - 1,
            )
            neighbor === nothing && continue
            neighbor == site && continue
            duplicate = false
            for prior in 1:(direction - 1)
                prior_neighbor = relation_neighbor_index(
                    view.runtime.program.shape,
                    view.runtime.program.periodic,
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
            neighbor_linear = LinearIndices(view.runtime.ownership)[neighbor]
            _lifecycle_planned_owner(view, neighbor_linear) != cell &&
                (result += Int32(1))
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
    count = Int32(0)
    first = ntuple(_ -> zero(T), N)
    second = ntuple(_ -> zero(T), N * N)
    indices = CartesianIndices(view.runtime.ownership)
    for linear in eachindex(view.runtime.ownership)
        _lifecycle_planned_owner(view, Int(linear)) == cell || continue
        site = indices[linear]
        coordinates = ntuple(
            dimension -> T(site[dimension]) - T(0.5), N
        )
        count += Int32(1)
        first = ntuple(N) do dimension
            first[dimension] + coordinates[dimension]
        end
        second = ntuple(N * N) do slot
            row = rem(slot - 1, N) + 1
            column = div(slot - 1, N) + 1
            second[slot] + coordinates[row] * coordinates[column]
        end
    end
    iszero(count) && return nothing
    inverse = inv(T(count))
    center = ntuple(dimension -> first[dimension] * inverse, N)
    covariance = ntuple(N * N) do slot
        row = rem(slot - 1, N) + 1
        column = div(slot - 1, N) + 1
        second[slot] * inverse - center[row] * center[column]
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
