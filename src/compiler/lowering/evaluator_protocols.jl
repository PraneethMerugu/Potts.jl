# Symbolic evaluator, descriptor, and layout lowering.

"""
    DescriptorSource

Stable host-side source information supplied to downstream descriptor and
workspace construction hooks. Private compiler IR is deliberately absent.
"""
struct DescriptorSource
    identity::QualifiedStatementID
    kind::Symbol
    schema_version::VersionNumber
    lowering_identity::Symbol
    provenance::Any
end

"""
    DescriptorConstructionContext

Complete, resolved input to a downstream descriptor constructor. Every handle
is compact and every evaluator/tag is concrete before this value is created.
"""
struct DescriptorConstructionContext{A, S, H <: Tuple, W <: Tuple, R}
    access::A
    support::S
    state_handles::H
    workspace_handles::W
    role::R
    source_handle::Int32
    source::DescriptorSource
end

"""
    registered_descriptor_payload(::Val{lowering_identity}, context)

Construct inert isbits metadata for a registered statement family. CorePotts
always owns the proposal descriptor and evaluator execution path; downstream
metadata cannot replace either. The payload value's concrete type must exactly
match the fixed `descriptor_payload_type` in the registered statement contract.
"""
function registered_descriptor_payload end

"""
    registered_workspace_schemas(::Val{lowering_identity}, source, scalar_type, lattice_shape)

Declare reusable workspaces required by a registered descriptor family.
Declarations are host metadata; the compiler resolves them to compact handles.
"""
registered_workspace_schemas(
    ::Val, ::DescriptorSource, ::Type, ::Tuple
) = ()

"""
    registered_tracker_requirements(::Val{lowering_identity}, source, scalar_type, lattice_shape)

Declare typed derived-state trackers required by a registered descriptor
family. Repeated requirements for the same scientific quantity are
canonicalized by the compiler; the runtime executor remains mechanism-free.
"""
registered_tracker_requirements(
    ::Val, ::DescriptorSource, ::Type, ::Tuple
) = ()

"""Public, resolved resource binding supplied to operation tracker hooks."""
struct ResolvedOperationSourceBinding{M}
    requirement_index::Int16
    kind::Symbol
    identity::QualifiedStatementID
    handle::Int32
    metadata::M
end

"""Closed host context for constructing trackers required by one operation."""
struct OperationTrackerContext{S <: DescriptorSource, B <: Tuple}
    operation::Symbol
    schema_version::VersionNumber
    source::S
    bindings::B
end

"""
    registered_operation_tracker_requirements(::Val{requirement}, context,
                                               scalar_type, lattice_shape)

Construct typed tracker descriptors for one operation-level requirement. The
compiler supplies only analyzed qualified bindings and value-level handles;
private compiler IR is never exposed to extensions.
"""
function registered_operation_tracker_requirements end

const _GatherReductionNumber = Union{
    Bool,
    Int8, Int16, Int32, Int64,
    UInt8, UInt16, UInt32, UInt64,
    Float16, Float32, Float64,
}

struct _GatherReductionConvert{T} end
(::_GatherReductionConvert{T})(value) where {T} = convert(T, value)

struct _GatherReductionResult end
(::_GatherReductionResult)(accumulator, ::Int32) = accumulator

struct _GatherMeanResult{T} end
(::_GatherMeanResult{T})(accumulator, count::Int32) where {T} =
    accumulator / T(count)

struct _GatherGeometricMap end
(::_GatherGeometricMap)(value) = log(value)

struct _GatherGeometricResult{T} end
(::_GatherGeometricResult{T})(accumulator, count::Int32) where {T} =
    exp(accumulator / T(count))

struct _GatherPositive end
(::_GatherPositive)(value) = value > zero(value)

_gather_sum_type(::Type{Bool}) = Int
_gather_sum_type(::Type{T}) where {T <: Signed} = promote_type(Int, T)
_gather_sum_type(::Type{T}) where {T <: Unsigned} = promote_type(UInt, T)
_gather_sum_type(::Type{T}) where {T <: AbstractFloat} = T
_gather_mean_type(::Type{T}) where {T <: Integer} = Float64
_gather_mean_type(::Type{T}) where {T <: AbstractFloat} = T

function _unsupported_gather_reduction(kind::Symbol, ::Type{T}) where {T}
    throw(ArgumentError(
        "$(kind) does not support gathered values with element type $(T)"
    ))
end

function _materialize_gather_reduction(::Val{:sum}, ::Type{T}) where {T}
    T <: _GatherReductionNumber ||
        return _unsupported_gather_reduction(:sum, T)
    R = _gather_sum_type(T)
    return LocalMath.BoundedFold(
        T, _GatherReductionConvert{R}(), +, zero(R), _GatherReductionResult();
        onempty = LocalMath.FillEmpty(zero(R)),
    )
end


function _materialize_gather_reduction(::Val{:minimum}, ::Type{T}) where {T}
    T <: _GatherReductionNumber ||
        return _unsupported_gather_reduction(:minimum, T)
    return LocalMath.BoundedFold(
        T, identity, min, typemax(T), _GatherReductionResult())
end

function _materialize_gather_reduction(::Val{:maximum}, ::Type{T}) where {T}
    T <: _GatherReductionNumber ||
        return _unsupported_gather_reduction(:maximum, T)
    return LocalMath.BoundedFold(
        T, identity, max, typemin(T), _GatherReductionResult())
end

function _materialize_gather_reduction(::Val{:mean}, ::Type{T}) where {T}
    T <: _GatherReductionNumber ||
        return _unsupported_gather_reduction(:mean, T)
    R = _gather_mean_type(T)
    return LocalMath.BoundedFold(
        T, _GatherReductionConvert{R}(), +, zero(R), _GatherMeanResult{R}();
        onempty = LocalMath.FillEmpty(R(NaN)),
    )
end

function _materialize_gather_reduction(
        ::Val{:geometric_mean}, ::Type{T},
    ) where {T}
    T <: Union{Float16,Float32,Float64} ||
        return _unsupported_gather_reduction(:geometric_mean, T)
    return LocalMath.BoundedFold(
        T, _GatherGeometricMap(), +, zero(T),
        _GatherGeometricResult{T}();
        domain = LocalMath.Where(_GatherPositive()),
    )
end

function _gather_reduction_kind(reduction::_GatherReduction)
    kind = reduction.kind
    kind === _GatherSum && return :sum
    kind === _GatherMinimum && return :minimum
    kind === _GatherMaximum && return :maximum
    kind === _GatherMean && return :mean
    kind === _GatherGeometricMean && return :geometric_mean
    error("unknown gathered reduction kind")
end

_dense_gather_scalar_type(
    ::CorePotts.CompilerSPI.DenseOwnerScalarStorage{T},
) where {T} = T

function _resolved_gather_scalar_type(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        ::Type{T},
    ) where {T <: AbstractFloat}
    tracker_source = _tracker_projection_operand(node, graph)
    tracker_source === nothing && return T
    descriptors = _operation_tracker_descriptors(ir, tracker_source, T)
    if isempty(descriptors) && tracker_source.transfer.identity === :cell_volume
        storage = CorePotts.CompilerSPI.tracker_contract(
            CorePotts.CompilerSPI.OwnershipCountTracker()).storage
        return _dense_gather_scalar_type(storage)
    end
    isempty(descriptors) && throw(ArgumentError(
        "gathered tracker operation has no resolved tracker descriptor"
    ))
    storages = map(descriptors) do descriptor
        storage = CorePotts.CompilerSPI.tracker_contract(descriptor).storage
        storage isa CorePotts.CompilerSPI.DenseOwnerScalarStorage ||
            throw(ArgumentError(
                "gathered folds require direct dense scalar tracker storage"
            ))
        storage
    end
    types = map(_dense_gather_scalar_type, storages)
    all(==(first(types)), types) || throw(ArgumentError(
        "gathered tracker descriptors must have one scalar element type"
    ))
    return first(types)
end

function _checked_gather_fold(
        fold::LocalMath.BoundedFold, ::Type{T},
    ) where {T}
    return LocalMath.BoundedFold(
        T,
        fold.map,
        fold.combine,
        fold.seed,
        fold.finish;
        domain = fold.domain,
        oninvalid = fold.oninvalid,
        onempty = fold.onempty,
        order = fold.order,
    )
end

_materialize_gather_fold(fold::LocalMath.BoundedFold, ::Type{T}) where {T} =
    _checked_gather_fold(fold, T)
_materialize_gather_fold(reduction::_GatherReduction, ::Type{T}) where {T} =
    _materialize_gather_reduction(
        Val(_gather_reduction_kind(reduction)), T)

_gather_fold_name(::LocalMath.BoundedFold) = "bounded fold"
_gather_fold_name(reduction::_GatherReduction) =
    String(_gather_reduction_kind(reduction))

function _materialize_checked_gather_fold(
        ir::AnalyzedTermIR,
        node::NormalizedTermNode,
        graph::NormalizedTermGraph,
        fold,
        ::Type{T},
    ) where {T <: AbstractFloat}
    try
        input_type = _resolved_gather_scalar_type(ir, node, graph, T)
        return _materialize_gather_fold(fold, input_type)
    catch error
        error isa ArgumentError ||
            error isa LocalMath.LocalMathValidationError || rethrow(error)
        record = ir.source.records[Int(node.record)]
        throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :invalid_gather_fold,
                node.source,
                _gather_fold_name(fold),
                node.source.path,
                "a fold closed over the resolved gathered scalar type",
                sprint(showerror, error),
                (),
                record.source,
            ),),
        ))
    end
end

function _static_literal(value, manifest::ParameterManifest, ::Type{T}; state = nothing) where {
        T <: AbstractFloat,
    }
    if state !== nothing
        isbitstype(typeof(value)) || throw(
            ArgumentError(
                "state-policy literals require immutable fixed-shape numerical values"
            )
        )
        converted = _convert_state_initial_value(value, state.unit, typeof(state.initial), T)
        return CorePotts.CompilerSPI.LiteralExpression(converted)
    end
    value isa LocalMath.BoundedFold &&
        return CorePotts.CompilerSPI.LiteralExpression(value)
    if value isa Bool || value isa Integer || value isa Symbol
        return CorePotts.CompilerSPI.LiteralExpression(value)
    elseif value isa Number
        return CorePotts.CompilerSPI.LiteralExpression(T(_numeric_value(
            value, _reference_for(manifest.reference_units, value)
        )))
    end
    throw(ArgumentError(
        "static evaluator literal is not device-compatible: $(repr(value))"
    ))
end

function _static_parameter(value, manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    scalar = _compiled_scalar(value, manifest, T)
    return CorePotts.CompilerSPI.ParameterExpression(
        scalar.value, scalar.parameter_index
    )
end

function _static_operation_callable(node::NormalizedTermNode)
    operation = node.callable
    operation === nothing && throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :missing_concrete_operation_callable,
            node.source,
            String(node.operation),
            node.source.path,
            "the concrete callable frozen during completion",
            "nothing",
            (),
            UnknownSource(),
        ),),
    ))
    isbits(operation) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_operation_callable,
            node.source,
            String(node.operation),
            node.source.path,
            "an isbits callable frozen during completion",
            string(typeof(operation)),
            (),
            UnknownSource(),
        ),),
    ))
    return operation
end

function _compiler_synthesized_operation_expression(
        graph::NormalizedTermGraph,
        operation,
        arguments::Tuple,
        record::QualifiedStatement,
        ;
        semantic_role::Symbol = _record_operation_role(record),
        semantic_phase::Symbol = _record_operation_phase(record),
    )
    schema_index = findfirst(
        schema -> schema.surface_operation === operation &&
            schema.arity == length(arguments),
        graph.operation_snapshot,
    )
    schema_index === nothing && throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :missing_frozen_operation_schema,
            record.identity,
            repr(operation),
            record.identity.path,
            "an operation schema frozen during completion",
            "no matching frozen schema",
            (),
            record.source,
        ),),
    ))
    schema = graph.operation_snapshot[schema_index]
    transfer = schema.transfer
    reason = _operation_transfer_error(transfer, length(arguments))
    reason === nothing || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :invalid_operation_transfer,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "a valid frozen operation transfer",
            reason,
            (),
            record.source,
        ),),
    ))
    role = semantic_role
    phase = semantic_phase
    role in transfer.allowed_roles && phase in transfer.allowed_phases &&
        _operation_context_admitted(transfer.required_context, role, phase) ||
        throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :illegal_operation_use,
                record.identity,
                String(transfer.identity),
                record.identity.path,
                "the frozen role, phase, and context contract",
                "role=$(repr(role)), phase=$(repr(phase)), " *
                "required_context=$(repr(transfer.required_context))",
                (),
                record.source,
            ),),
        ))
    callable = schema.callable
    isbits(callable) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_operation_callable,
            record.identity,
            String(transfer.identity),
            record.identity.path,
            "an isbits callable frozen during completion",
            string(typeof(callable)),
            (),
            record.source,
        ),),
    ))
    return _bounded_static_operation(callable, arguments)
end

function _validate_static_expression_context(
        expression::CorePotts.CompilerSPI.AbstractStaticExpression,
        context::Type{<:CorePotts.CompilerSPI.AbstractEvaluatorExecutionContext},
        record::QualifiedStatement,
    )
    operation = if expression isa CorePotts.CompilerSPI.ContextExpression
        expression.operation
    elseif expression isa CorePotts.CompilerSPI.OperationExpression
        expression.operation
    else
        nothing
    end
    if operation !== nothing && !CorePotts.CompilerSPI.operation_context_supported(
            operation, context
        )
        throw(PottsValidationError(
            :descriptor_lowering,
            (PottsDiagnostic(
                :unsupported_operation_context,
                record.identity,
                string(typeof(operation)),
                record.identity.path,
                "a concrete callable implemented for $(nameof(context))",
                "no callable implementation for $(nameof(context))",
                (),
                record.source,
            ),),
        ))
    end
    if expression isa CorePotts.CompilerSPI.OperationExpression
        for argument in expression.arguments
            _validate_static_expression_context(argument, context, record)
        end
    end
    return nothing
end

function _static_evaluator(
        expression::CorePotts.CompilerSPI.AbstractStaticExpression,
        context::Type{<:CorePotts.CompilerSPI.AbstractEvaluatorExecutionContext},
        record::QualifiedStatement,
    )
    _validate_static_expression_context(expression, context, record)
    return CorePotts.CompilerSPI.StaticEvaluator(expression)
end

function _bounded_static_operation(operation, arguments::Tuple)
    length(arguments) <= 8 &&
        return CorePotts.CompilerSPI.OperationExpression(operation, arguments...)
    (
        operation isa CorePotts.CompilerSPI.OrderedFold &&
        operation.operation in (+, *)
    ) || return CorePotts.CompilerSPI.OperationExpression(operation, arguments...)
    result = CorePotts.CompilerSPI.OperationExpression(operation, arguments[1:8]...)
    index = 9
    while index <= length(arguments)
        final = min(index + 6, length(arguments))
        result = CorePotts.CompilerSPI.OperationExpression(
            operation, result, arguments[index:final]...
        )
        index = final + 1
    end
    return result
end
