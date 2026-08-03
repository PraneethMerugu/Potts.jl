# Immutable lifecycle evaluator contexts and their resource protocol.

struct _LifecycleTriggerContext{R, I} <:
       AbstractLifecycleTriggerEvaluationContext
    runtime::R
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
end

struct _LifecyclePlacementContext{R, I} <:
       AbstractLifecyclePlacementEvaluationContext
    runtime::R
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
end

struct _LifecyclePartitionContext{R, I} <:
       AbstractLifecyclePartitionEvaluationContext
    runtime::R
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
end

struct _LifecycleStateContext{R, I} <:
       AbstractLifecycleStateTransformEvaluationContext
    runtime::R
    anchor::Int32
    generation::UInt32
    site::I
    occurrence::Int32
    operation::UInt16
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
    cell <= 0 && return 0
    return program_tracker_value(context.runtime, Val(:cell_volume), cell)
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
    cell <= 0 && return 0
    return qualified_tracker_value(
        context.runtime.program.tracker_plan,
        context.runtime.trackers,
        quantity,
        source_handle,
        cell,
    )
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
) = _cell_center(context.runtime, Int32(only(arguments)))

@inline apply_resource_operation(
    ::ResourceOperation{:unwrapped_center}, arguments, context::_LifecycleContext
) = _cell_center(context.runtime, Int32(only(arguments)))

@inline apply_resource_operation(
    ::ResourceOperation{:cell_elongation}, arguments, context::_LifecycleContext
) = _cell_length(context.runtime, Int32(only(arguments)))

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
    owner = @inbounds context.runtime.ownership[last(arguments)]
    return _owner_kind(context.runtime, owner) == kind
end

@inline function apply_resource_operation(
        ::ResourceOperation{:degree}, arguments, context::_LifecycleContext
    )
    relationship_handle = Int32(first(arguments))
    endpoint = Int32(last(arguments))
    endpoint <= 0 && return 0
    slot = _relationship_domain_slot(
        context.runtime.program.descriptor_plan.domain_resources,
        relationship_handle,
    )
    return _call_relationship_slot(
        _relationship_degree, context.runtime.relationships, slot, (endpoint,)
    )
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
    first_uniform = _lifecycle_uniform(
        T,
        context.runtime,
        stream,
        operation,
        context.anchor,
        context.generation,
        context.occurrence;
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
            context.anchor,
            context.generation,
            context.occurrence;
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
