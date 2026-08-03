# Generic, mechanism-free evaluator, storage, and descriptor runtime boundary.

abstract type AbstractStaticExpression end
abstract type AbstractContextualOperation end

"""Structural execution contexts used to qualify concrete evaluator callables."""
abstract type AbstractEvaluatorExecutionContext end
abstract type AbstractProbeEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractHamiltonianEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractProposalEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractSiteStageEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractRelationshipStageEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractLifecycleTriggerEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractLifecyclePlacementEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractLifecyclePartitionEvaluationContext <:
              AbstractEvaluatorExecutionContext end
abstract type AbstractLifecycleStateTransformEvaluationContext <:
              AbstractEvaluatorExecutionContext end

abstract type AbstractStorageRepresentation end

struct StateStorageRepresentation{
        ElementType,
        Dimensions,
        Layout,
        Adaptation,
    } <: AbstractStorageRepresentation end

struct WorkspaceStorageRepresentation{
        ContainerType,
        ElementType,
        Dimensions,
        Adaptation,
    } <: AbstractStorageRepresentation end

struct DefaultStateStorageRepresentation <: AbstractStorageRepresentation end
struct DefaultWorkspaceStorageRepresentation <: AbstractStorageRepresentation end

struct BlockLocation{N}
    offset::Int32
    shape::NTuple{N, Int32}
    function BlockLocation(
            offset::Integer, shape::NTuple{N, <:Integer}
        ) where {N}
        offset > 0 || throw(ArgumentError(
            "a block location offset must be positive"
        ))
        all(>(0), shape) || throw(ArgumentError(
            "block location dimensions must be positive"
        ))
        return new{N}(Int32(offset), Int32.(shape))
    end
end

struct StateHandle{
        Representation <: AbstractStorageRepresentation,
        L <: BlockLocation,
    }
    bank::Int32
    slot::Int32
    location::L
    function StateHandle{Representation}(
            bank::Integer,
            slot::Integer,
            location::L,
        ) where {
            Representation <: AbstractStorageRepresentation,
            L <: BlockLocation,
        }
        bank > 0 ||
            throw(ArgumentError("a state bank ordinal must be positive"))
        slot > 0 || throw(ArgumentError("a state handle slot must be positive"))
        new{Representation, L}(Int32(bank), Int32(slot), location)
    end
end

StateHandle{Representation}(slot::Integer) where {
    Representation <: AbstractStorageRepresentation,
} = StateHandle{Representation}(1, slot, BlockLocation(slot, (1,)))
StateHandle{Representation}(
    bank::Integer, slot::Integer
) where {Representation <: AbstractStorageRepresentation} =
    StateHandle{Representation}(bank, slot, BlockLocation(slot, (1,)))
StateHandle(
    ::Type{Representation}, bank::Integer, slot::Integer
) where {Representation <: AbstractStorageRepresentation} =
    StateHandle{Representation}(bank, slot)
StateHandle(
    ::Type{Representation},
    bank::Integer,
    slot::Integer,
    offset::Integer,
    shape::Tuple,
) where {Representation <: AbstractStorageRepresentation} =
    StateHandle{Representation}(
        bank, slot, BlockLocation(offset, shape)
    )
StateHandle(slot::Integer) =
    StateHandle{DefaultStateStorageRepresentation}(1, slot)
StateHandle(bank::Integer, slot::Integer) =
    StateHandle{DefaultStateStorageRepresentation}(bank, slot)

struct WorkspaceHandle{
        Representation <: AbstractStorageRepresentation,
        L <: BlockLocation,
    }
    bank::Int32
    slot::Int32
    location::L
    function WorkspaceHandle{Representation}(
            bank::Integer,
            slot::Integer,
            location::L,
        ) where {
            Representation <: AbstractStorageRepresentation,
            L <: BlockLocation,
        }
        bank > 0 ||
            throw(ArgumentError("a workspace bank ordinal must be positive"))
        slot > 0 ||
            throw(ArgumentError("a workspace handle slot must be positive"))
        new{Representation, L}(Int32(bank), Int32(slot), location)
    end
end

WorkspaceHandle{Representation}(slot::Integer) where {
    Representation <: AbstractStorageRepresentation,
} = WorkspaceHandle{Representation}(1, slot, BlockLocation(slot, (1,)))
WorkspaceHandle{Representation}(
    bank::Integer, slot::Integer
) where {Representation <: AbstractStorageRepresentation} =
    WorkspaceHandle{Representation}(bank, slot, BlockLocation(slot, (1,)))
WorkspaceHandle(
    ::Type{Representation}, bank::Integer, slot::Integer
) where {Representation <: AbstractStorageRepresentation} =
    WorkspaceHandle{Representation}(bank, slot)
WorkspaceHandle(
    ::Type{Representation},
    bank::Integer,
    slot::Integer,
    offset::Integer,
    shape::Tuple,
) where {Representation <: AbstractStorageRepresentation} =
    WorkspaceHandle{Representation}(
        bank, slot, BlockLocation(offset, shape)
    )
WorkspaceHandle(slot::Integer) =
    WorkspaceHandle{DefaultWorkspaceStorageRepresentation}(1, slot)
WorkspaceHandle(bank::Integer, slot::Integer) =
    WorkspaceHandle{DefaultWorkspaceStorageRepresentation}(bank, slot)

handle_bank(handle::Union{StateHandle, WorkspaceHandle}) = handle.bank
handle_slot(handle::Union{StateHandle, WorkspaceHandle}) = handle.slot
handle_offset(handle::Union{StateHandle, WorkspaceHandle}) =
    handle.location.offset
handle_shape(handle::Union{StateHandle, WorkspaceHandle}) =
    handle.location.shape
handle_representation(
    ::StateHandle{Representation}
) where {Representation} = Representation
handle_representation(
    ::WorkspaceHandle{Representation}
) where {Representation} = Representation

function Base.getproperty(
        handle::Union{StateHandle, WorkspaceHandle}, name::Symbol
    )
    name === :index && return getfield(handle, :slot)
    return getfield(handle, name)
end

struct LiteralExpression{T} <: AbstractStaticExpression
    value::T
end

struct ParameterExpression{T <: AbstractFloat} <: AbstractStaticExpression
    default::T
    index::Int32
    function ParameterExpression(default::T, index::Integer = 0) where {
            T <: AbstractFloat,
        }
        0 <= index <= typemax(Int32) ||
            throw(ArgumentError("parameter expression index is out of range"))
        new{T}(default, Int32(index))
    end
end

struct ContextExpression{T <: AbstractContextualOperation} <: AbstractStaticExpression
    operation::T
end

struct StateExpression{H <: StateHandle} <: AbstractStaticExpression
    handle::H
end

struct OperationExpression{
        T,
        A <: Tuple,
    } <: AbstractStaticExpression
    operation::T
    arguments::A
end

OperationExpression(operation, arguments...) =
    OperationExpression(operation, arguments)

struct StaticEvaluator{E <: AbstractStaticExpression}
    expression::E
end

struct OrderedFold{F}
    operation::F
end

struct ContextOperation{Identity} <: AbstractContextualOperation end
struct ResourceOperation{Identity} <: AbstractContextualOperation end

"""Concrete callable plus one qualified value-level tracker binding."""
struct QualifiedTrackerOperation{O, Q <: Val} <: AbstractContextualOperation
    operation::O
    quantity::Q
    source_handle::Int32
end

function context_value end
function apply_resource_operation end
function operation_callable end
function qualified_tracker_operation_call end
function operation_context_supported end
function state_value end
function workspace_value end
function evaluator_parameters end
function proposal_source_site end
function proposal_target_site end
function proposal_source_owner end
function proposal_target_owner end
function proposal_source_kind end
function proposal_target_kind end
function proposal_site_owner end
function proposal_relation_count end
function proposal_relation_neighbor_site end
function proposal_relation_neighbor_owner end
function site_owner end
function owner_kind end
function relation_count end
function relation_neighbor_site end
function _compiled_evaluator_parameters end
function _compiled_context_value end
function _compiled_resource_operation end
function _compiled_qualified_tracker_operation end

# Ordinary Julia callables carry no evaluator-context dependency. Contextual
# callables must prove support explicitly; ResourceOperation and ContextOperation
# derive that proof from their actual context method at each runtime boundary.
operation_context_supported(
    operation, ::Type{<:AbstractEvaluatorExecutionContext}
) = !(operation isa AbstractContextualOperation)
operation_context_supported(
    ::AbstractContextualOperation,
    ::Type{<:AbstractEvaluatorExecutionContext},
) = false

# Completion freezes semantic lifecycle callable admission without introducing
# the lifecycle transaction runtime. Concrete execution contexts still implement
# the corresponding resource operation before execution can qualify.
for (identity, contexts) in (
        :cell_volume => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :cell_surface => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :cell_elongation => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :cell_center => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePlacementEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :unwrapped_center => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePlacementEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :field_value => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePlacementEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :history_value => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :degree => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :edge_payload => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
        :occupancy => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePlacementEvaluationContext,
        ),
        :draw => (
            AbstractLifecycleTriggerEvaluationContext,
            AbstractLifecyclePlacementEvaluationContext,
            AbstractLifecyclePartitionEvaluationContext,
            AbstractLifecycleStateTransformEvaluationContext,
        ),
    )
    for context in contexts
        @eval operation_context_supported(
            ::ResourceOperation{$(QuoteNode(identity))},
            ::Type{$context},
        ) = true
    end
end

for (identity, operation) in (
        :add => OrderedFold(+),
        :subtract => OrderedFold(-),
        :multiply => OrderedFold(*),
        :divide => OrderedFold(/),
        :power => (^),
        :maximum => OrderedFold(max),
        :minimum => OrderedFold(min),
        :less => (<),
        :less_equal => (<=),
        :greater => (>),
        :greater_equal => (>=),
        :equal => (==),
        :not_equal => (!=),
        :and => (&),
        :or => (|),
        :not => (!),
        :ifelse => ifelse,
        :absolute => abs,
        :exponential => exp,
        :logarithm => log,
        :square_root => sqrt,
    )
    @eval operation_callable(
        ::Val{$(QuoteNode(identity))}, version::VersionNumber
    ) = version == v"1.0.0" ?
        $operation :
        throw(ArgumentError("unsupported operation schema version $version"))
end

for identity in (
        :source_site,
        :target_site,
        :source_cell,
        :target_cell,
        :source_kind,
        :target_kind,
        :is_extension,
        :is_retraction,
        :energy_anchor_site,
        :energy_anchor_cell,
        :energy_anchor_contact,
        :energy_anchor_relationship,
    )
    @eval operation_callable(
        ::Val{$(QuoteNode(identity))}, version::VersionNumber
    ) = version == v"1.0.0" ?
        ContextOperation{$(QuoteNode(identity))}() :
        throw(ArgumentError("unsupported operation schema version $version"))
end

for identity in (
        :cell_volume,
        :cell_surface,
        :cell_elongation,
        :contact_owner_a,
        :contact_owner_b,
        :contact_kind_a,
        :contact_kind_b,
        :cell_center,
        :unwrapped_center,
        :distance,
        :contact_measure,
        :boundary_measure,
        :neighbor_count,
        :neighbor_sum,
        :neighbor_mean,
        :neighbor_geomean,
        :field_value,
        :field_gradient,
        :laplacian,
        :occupancy,
        :history_value,
        :linked,
        :endpoint_a,
        :endpoint_b,
        :degree,
        :edge_payload,
        :lag,
        :new_contact,
        :lost_contact,
        :draw,
    )
    @eval operation_callable(
        ::Val{$(QuoteNode(identity))}, version::VersionNumber
    ) = version == v"1.0.0" ?
        ResourceOperation{$(QuoteNode(identity))}() :
        throw(ArgumentError("unsupported operation schema version $version"))
end

@inline evaluate_expression(
    expression::LiteralExpression, context
) = expression.value

@inline function evaluate_expression(
        expression::ParameterExpression,
        context,
    )
    index = expression.index
    return index == 0 ? expression.default :
           @inbounds evaluator_parameters(context)[index]
end

@inline evaluate_expression(
    expression::ContextExpression, context
) = context_value(expression.operation, context)

@inline evaluate_expression(
    expression::StateExpression, context
) = expression.handle

@inline function evaluate_expression(
        expression::OperationExpression,
        context,
    )
    arguments = map(
        argument -> evaluate_expression(argument, context),
        expression.arguments,
    )
    return execute_operation(expression.operation, arguments, context)
end

@inline evaluate_static(evaluator::StaticEvaluator, context) =
    evaluate_expression(evaluator.expression, context)

# Production execution deliberately does not redispatch through the public
# evaluator/operation protocol. Registered concrete callables remain the one
# semantic extension point after lowering.
@inline _compiled_evaluate_expression(
    expression::LiteralExpression, context
) = expression.value

@inline function _compiled_evaluate_expression(
        expression::ParameterExpression,
        context,
    )
    index = expression.index
    return index == 0 ? expression.default :
           @inbounds _compiled_evaluator_parameters(context)[index]
end

@inline _compiled_evaluate_expression(
    expression::ContextExpression, context
) = _compiled_context_value(expression.operation, context)

@inline _compiled_evaluate_expression(
    expression::StateExpression, context
) = expression.handle

@inline function _compiled_evaluate_expression(
        expression::OperationExpression,
        context,
    )
    arguments = map(
        argument -> _compiled_evaluate_expression(argument, context),
        expression.arguments,
    )
    return _compiled_execute_operation(
        expression.operation, arguments, context
    )
end

@inline _compiled_evaluate_static(
    evaluator::StaticEvaluator, context
) = _compiled_evaluate_expression(evaluator.expression, context)

@inline function _ordered_fold(operation, arguments::Tuple)
    length(arguments) == 1 && return operation(only(arguments))
    return foldl(operation, Base.tail(arguments); init = first(arguments))
end

@inline (fold::OrderedFold)(arguments::Tuple) =
    _ordered_fold(fold.operation, arguments)

@inline execute_operation(
    operation::AbstractContextualOperation, arguments::Tuple, context
) = operation(arguments, context)
@inline execute_operation(
    operation::OrderedFold, arguments::Tuple, context
) = operation(arguments)
@inline execute_operation(
    operation, arguments::Tuple, context
) = operation(arguments...)

@inline _compiled_execute_operation(
    operation::ContextOperation, arguments::Tuple, context
) = _compiled_context_value(operation, context)
@inline _compiled_execute_operation(
    operation::ResourceOperation, arguments::Tuple, context
) = _compiled_resource_operation(operation, arguments, context)
@inline _compiled_execute_operation(
    operation::QualifiedTrackerOperation, arguments::Tuple, context
) = _compiled_qualified_tracker_operation(operation, arguments, context)
@inline _compiled_execute_operation(
    operation::AbstractContextualOperation, arguments::Tuple, context
) = operation(arguments, context)
@inline _compiled_execute_operation(
    operation::OrderedFold, arguments::Tuple, context
) = _ordered_fold(operation.operation, arguments)
@inline _compiled_execute_operation(
    operation, arguments::Tuple, context
) = operation(arguments...)

@inline (
    operation::ContextOperation
)(arguments::Tuple, context) =
    context_value(operation, context)
@inline (
    operation::ResourceOperation
)(arguments::Tuple, context) =
    apply_resource_operation(operation, arguments, context)
@inline (
    operation::QualifiedTrackerOperation
)(arguments::Tuple, context) =
    qualified_tracker_operation_call(
        operation.operation,
        arguments,
        context,
        operation.quantity,
        operation.source_handle,
    )

operation_context_supported(
    operation::QualifiedTrackerOperation,
    context::Type{<:AbstractEvaluatorExecutionContext},
) = operation_context_supported(operation.operation, context)

struct EvaluatorProbeContext{P, V, S, W} <:
       AbstractProbeEvaluationContext
    parameters::P
    values::V
    states::S
    workspaces::W
end

EvaluatorProbeContext(parameters, values) =
    EvaluatorProbeContext(parameters, values, (), ())
EvaluatorProbeContext(parameters, values, states) =
    EvaluatorProbeContext(parameters, values, states, ())

@inline evaluator_parameters(context::EvaluatorProbeContext) =
    context.parameters
@inline _compiled_evaluator_parameters(context::EvaluatorProbeContext) =
    context.parameters

for identity in (
        :source_site,
        :target_site,
        :source_cell,
        :target_cell,
        :source_kind,
        :target_kind,
        :is_extension,
        :is_retraction,
        :energy_anchor_site,
        :energy_anchor_cell,
        :energy_anchor_contact,
        :energy_anchor_relationship,
    )
    @eval @inline context_value(
        ::ContextOperation{$(QuoteNode(identity))},
        context::EvaluatorProbeContext,
    ) = getproperty(context.values, $(QuoteNode(identity)))
end

@inline function _compiled_context_value(
        operation::ContextOperation{Identity},
        context::EvaluatorProbeContext,
    ) where {Identity}
    return invoke(
        context_value,
        Tuple{ContextOperation{Identity}, EvaluatorProbeContext},
        operation,
        context,
    )
end

@inline apply_resource_operation(
    ::ResourceOperation{:cell_volume},
    arguments,
    context::EvaluatorProbeContext,
) = @inbounds context.values.cell_volumes[only(arguments)]

@inline function apply_resource_operation(
        ::ResourceOperation{:occupancy},
        arguments,
        context::EvaluatorProbeContext,
    )
    kind = Int16(first(arguments))
    owner = @inbounds context.values.ownership[Int(last(arguments))]
    owner <= 0 && return false
    return @inbounds context.values.cell_kinds[owner] == kind
end

@inline function _compiled_resource_operation(
        operation::ResourceOperation{Identity},
        arguments::Tuple,
        context::EvaluatorProbeContext,
    ) where {Identity}
    return invoke(
        apply_resource_operation,
        Tuple{ResourceOperation{Identity}, Any, EvaluatorProbeContext},
        operation,
        arguments,
        context,
    )
end

operation_context_supported(
    operation::ContextOperation,
    ::Type{AbstractProbeEvaluationContext},
) = hasmethod(
    context_value,
    Tuple{typeof(operation), EvaluatorProbeContext},
)

operation_context_supported(
    operation::ResourceOperation,
    ::Type{AbstractProbeEvaluationContext},
) = hasmethod(
    apply_resource_operation,
    Tuple{typeof(operation), Tuple, EvaluatorProbeContext},
)

@inline state_value(
    context::EvaluatorProbeContext,
    handle::StateHandle,
    site,
) = @inbounds context.states[Int(handle.index)][site]

@inline workspace_value(
    context::EvaluatorProbeContext,
    handle::WorkspaceHandle,
) = workspace_block(context.workspaces, handle).values

@kernel function evaluator_probe_kernel!(
        output,
        evaluator,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(output)
        @inbounds output[index] = _compiled_evaluate_static(evaluator, context)
    end
end

@kernel function descriptor_probe_kernel!(
        output,
        descriptor,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(output)
        descriptor isa ProposalDescriptor || error(
            "descriptor probes require compiler-owned ProposalDescriptor values"
        )
        @inbounds output[index] = _compiled_evaluate_static(
            getfield(descriptor, :evaluator), context
        )
    end
end
