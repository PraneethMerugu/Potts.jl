# Generic, mechanism-free evaluator, storage, and descriptor runtime boundary.

"""Closed, recursively typed expression accepted by `StaticEvaluator`."""
abstract type AbstractStaticExpression end
"""Operation whose meaning is supplied by a qualified evaluation context."""
abstract type AbstractContextualOperation end

"""Structural execution contexts used to qualify concrete evaluator callables."""
abstract type AbstractEvaluatorExecutionContext end
"""Cold context used to validate evaluator construction without scientific execution."""
abstract type AbstractProbeEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting before/after Hamiltonian evaluation."""
abstract type AbstractHamiltonianEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting proposal-scoped scientific evaluation."""
abstract type AbstractProposalEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting one site-stage evaluation."""
abstract type AbstractSiteStageEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting one relationship-stage evaluation."""
abstract type AbstractRelationshipStageEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting lifecycle-trigger evaluation."""
abstract type AbstractLifecycleTriggerEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting lifecycle-placement evaluation."""
abstract type AbstractLifecyclePlacementEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting lifecycle-partition evaluation."""
abstract type AbstractLifecyclePartitionEvaluationContext <:
              AbstractEvaluatorExecutionContext end
"""Context supporting lifecycle state-transform evaluation."""
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

function _validated_handle_indices(bank::Integer, slot::Integer, owner)
    bank > 0 || throw(ArgumentError("a $owner bank ordinal must be positive"))
    slot > 0 || throw(ArgumentError("a $owner handle slot must be positive"))
    return Int32(bank), Int32(slot)
end

"""Typed bank, slot, and block location for compiler-declared state."""
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
        checked_bank, checked_slot = _validated_handle_indices(
            bank, slot, "state"
        )
        return new{Representation, L}(checked_bank, checked_slot, location)
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

"""Typed bank, slot, and block location for compiler-declared workspace."""
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
        checked_bank, checked_slot = _validated_handle_indices(
            bank, slot, "workspace"
        )
        return new{Representation, L}(checked_bank, checked_slot, location)
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

"""Return the one-based bank ordinal encoded by a state or workspace handle."""
handle_bank(handle::Union{StateHandle, WorkspaceHandle}) = handle.bank
"""Return the one-based slot encoded by a state or workspace handle."""
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

"""Literal isbits value in a compiled expression."""
struct LiteralExpression{T} <: AbstractStaticExpression
    value::T
end

"""Floating-point submission parameter with a compile-time default and positional index."""
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

"""Leaf expression evaluated by a contextual operation."""
struct ContextExpression{T <: AbstractContextualOperation} <: AbstractStaticExpression
    operation::T
end

"""Leaf expression reading a compiler-declared state handle."""
struct StateExpression{H <: StateHandle} <: AbstractStaticExpression
    handle::H
end

"""Typed callable application over a tuple of compiled subexpressions."""
struct OperationExpression{
        T,
        A <: Tuple,
    } <: AbstractStaticExpression
    operation::T
    arguments::A
end

OperationExpression(operation, arguments...) =
    OperationExpression(operation, arguments)

"""Concrete evaluator wrapper around one recursively typed expression."""
struct StaticEvaluator{E <: AbstractStaticExpression}
    expression::E
end

"""Callable marker requesting canonical left-to-right argument folding."""
struct OrderedFold{F}
    operation::F
end

"""Comparison preserving the compiled floating-point profile for mixed integer/float inputs."""
struct NumericComparison{F}
    operation::F
end

@inline function (comparison::NumericComparison)(left, right)
    if left isa Integer && right isa AbstractFloat
        return comparison.operation(typeof(right)(left), right)
    elseif left isa AbstractFloat && right isa Integer
        return comparison.operation(left, typeof(left)(right))
    end
    return comparison.operation(left, right)
end

"""Contextual operation identified by a compile-time `Symbol`."""
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
"""Resolve a durable operation identity and version to a concrete callable."""
function operation_callable end
"""Evaluate a qualified tracker operation against the current execution context."""
function qualified_tracker_operation_call end
"""Report whether an operation is admitted by an evaluator context type."""
function operation_context_supported end
"""Read one compiler-declared state handle at an execution-local index."""
function state_value end
function workspace_value end
function evaluator_parameters end
"""Return the source lattice site of the current proposal."""
function proposal_source_site end
"""Return the target lattice site of the current proposal."""
function proposal_target_site end
"""Return the source owner before the current proposal."""
function proposal_source_owner end
"""Return the target owner before the current proposal."""
function proposal_target_owner end
"""Return the source owner's cell kind."""
function proposal_source_kind end
"""Return the target owner's cell kind."""
function proposal_target_kind end
"""Return the owner at a proposal-relative lattice site."""
function proposal_site_owner end
"""Return the bounded degree of a proposal-relative relation."""
function proposal_relation_count end
"""Return a relation endpoint site for the current proposal."""
function proposal_relation_neighbor_site end
"""Return the owner at a relation endpoint for the current proposal."""
function proposal_relation_neighbor_owner end
"""Return the owner at a stage-relative lattice site."""
function site_owner end
"""Return the cell kind for a finite owner identity."""
function owner_kind end
"""Return the bounded degree of a stage-relative relation."""
function relation_count end
"""Return a stage-relative relation endpoint site."""
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
        :less => NumericComparison(<),
        :less_equal => NumericComparison(<=),
        :greater => NumericComparison(>),
        :greater_equal => NumericComparison(>=),
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
        :contact_edge_count,
        :contact_measure,
        :boundary_site_count,
        :neighbor_cell_count,
        :neighbor_property_sum,
        :neighbor_property_mean,
        :global_interface_measure,
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
        :bounded_fold,
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
