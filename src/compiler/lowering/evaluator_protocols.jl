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

function _static_literal(value, manifest::ParameterManifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    if value isa Bool || value isa Integer || value isa Symbol
        return CorePotts.LiteralExpression(value)
    elseif value isa Number
        return CorePotts.LiteralExpression(T(_numeric_value(
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
    return CorePotts.ParameterExpression(
        scalar.value, scalar.parameter_index
    )
end

function _static_operation_callable(
        identity::Symbol,
        version::VersionNumber,
        source::QualifiedStatementID,
        provenance,
    )
    operation = try
        CorePotts.operation_callable(
            Val(identity), version
        )
    catch error
        if error isa MethodError && error.f === CorePotts.operation_callable
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :missing_concrete_operation_callable,
                    source,
                    String(identity),
                    source.path,
                    "a concrete public CorePotts operation callable",
                    "$identity $version",
                    (),
                    provenance,
                ),),
            ))
        end
        rethrow(error)
    end
    isbits(operation) || throw(PottsValidationError(
        :descriptor_lowering,
        (PottsDiagnostic(
            :device_illegal_operation_callable,
            source,
            String(identity),
            source.path,
            "an isbits concrete operation callable",
            string(typeof(operation)),
            (),
            provenance,
        ),),
    ))
    return operation
end

_static_operation_callable(node::NormalizedTermNode) =
    _static_operation_callable(
        node.operation,
        node.schema_version,
        node.source,
        UnknownSource(),
    )

function _compiler_operation_expression(
        operation,
        arguments::Tuple,
        record::QualifiedStatement,
    )
    transfer = try
        operation_transfer(operation, length(arguments))
    catch error
        if error isa MethodError && error.f === operation_transfer
            throw(PottsValidationError(
                :descriptor_lowering,
                (PottsDiagnostic(
                    :missing_operation_transfer,
                    record.identity,
                    repr(operation),
                    record.identity.path,
                    "a versioned operation transfer rule",
                    repr(operation),
                    (),
                    record.source,
                ),),
            ))
        end
        rethrow(error)
    end
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
    callable = _static_operation_callable(
        transfer.identity,
        transfer.schema_version,
        record.identity,
        record.source,
    )
    return _bounded_static_operation(callable, arguments)
end

function _validate_static_expression_context(
        expression::CorePotts.AbstractStaticExpression,
        context::Type{<:CorePotts.AbstractEvaluatorExecutionContext},
        record::QualifiedStatement,
    )
    operation = if expression isa CorePotts.ContextExpression
        expression.operation
    elseif expression isa CorePotts.OperationExpression
        expression.operation
    else
        nothing
    end
    if operation !== nothing && !CorePotts.operation_context_supported(
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
    if expression isa CorePotts.OperationExpression
        for argument in expression.arguments
            _validate_static_expression_context(argument, context, record)
        end
    end
    return nothing
end

function _static_evaluator(
        expression::CorePotts.AbstractStaticExpression,
        context::Type{<:CorePotts.AbstractEvaluatorExecutionContext},
        record::QualifiedStatement,
    )
    _validate_static_expression_context(expression, context, record)
    return CorePotts.StaticEvaluator(expression)
end

function _bounded_static_operation(operation, arguments::Tuple)
    length(arguments) <= 8 &&
        return CorePotts.OperationExpression(operation, arguments...)
    (
        operation isa CorePotts.OrderedFold &&
        operation.operation in (+, *)
    ) || return CorePotts.OperationExpression(operation, arguments...)
    result = CorePotts.OperationExpression(operation, arguments[1:8]...)
    index = 9
    while index <= length(arguments)
        final = min(index + 6, length(arguments))
        result = CorePotts.OperationExpression(
            operation, result, arguments[index:final]...
        )
        index = final + 1
    end
    return result
end
