const MANAGED_FIELD_PROCESS_VERSION =
    "process-bigraph-managed-field-process-v1"

function field_engine_reconstruct end
function field_engine_array_type end
function field_engine_expected_diagnostics end

field_engine_array_type(
    declaration::EngineDeclaration,
) = field_engine_array_type(declaration.adapter)

struct ManagedFieldAdvanceProcess{
        D<:EngineDeclaration,A,R<:NamedTuple} <: AbstractProcess
    declaration::D
    resource_authorization::R
    subcycles_per_mcs::Int
end

function _validate_managed_field_authorization(
        declaration::EngineDeclaration,
        resource_authorization::NamedTuple)
    isempty(resource_authorization) &&
        _fail(:missing_field_resource_authorization,
            "managed field execution requires explicit resource authorization")
    required = (:backend, :precision, :residency)
    missing = Tuple(filter(
        key -> !haskey(resource_authorization, key), required))
    isempty(missing) ||
        _fail(:incomplete_field_resource_authorization,
            "managed field authorization must select a backend, precision, and residency";
            missing)
    resource_authorization.backend in declaration.capabilities.backends ||
        _fail(:unsupported_engine_backend,
            "resource authorization selected an unsupported backend";
            backend=resource_authorization.backend)
    resource_authorization.precision in declaration.capabilities.precisions ||
        _fail(:unsupported_engine_precision,
            "resource authorization selected an unsupported precision";
            precision=resource_authorization.precision)
    resource_authorization.residency in declaration.capabilities.residencies ||
        _fail(:unsupported_engine_residency,
            "resource authorization selected unsupported residency";
            residency=resource_authorization.residency)
    return resource_authorization
end

function ManagedFieldAdvanceProcess(
    declaration::EngineDeclaration;
    resource_authorization::NamedTuple,
    subcycles_per_mcs::Integer=1,
)
    subcycles_per_mcs > 0 ||
        _fail(:invalid_field_subcycle_count,
            "managed field process requires a positive MCS subcycle count")
    subcycles_per_mcs <= typemax(Int) ||
        _fail(:field_subcycle_overflow,
            "managed field process subcycle count exceeds Int")
    _validate_managed_field_authorization(
        declaration, resource_authorization)
    A = field_engine_array_type(declaration)
    A <: AbstractArray ||
        _fail(:invalid_field_array_type,
            "field adapter must declare an AbstractArray state type")
    ManagedFieldAdvanceProcess{
        typeof(declaration),A,typeof(resource_authorization)}(
        declaration,
        deepcopy(resource_authorization),
        Int(subcycles_per_mcs),
    )
end

"""
    managed_field_process(
        declaration;
        resource_authorization,
        subcycles_per_mcs=1,
    )

Construct a scheduled process that advances a declared field engine and
publishes its committed field state. `resource_authorization` must explicitly
select a backend, precision, and residency admitted by `declaration`.

The concrete process type is intentionally private. Compose, inspect, and
schedule the returned value through the ordinary [`AbstractProcess`](@ref)
protocol.
"""
function managed_field_process(
    declaration::EngineDeclaration;
    resource_authorization::NamedTuple,
    subcycles_per_mcs::Integer=1,
)
    return ManagedFieldAdvanceProcess(
        declaration;
        resource_authorization,
        subcycles_per_mcs,
    )
end

function ports(::ManagedFieldAdvanceProcess{D,A}) where {D,A}
    (
        PortSpec(A, :field, :input; interval_behavior=:frozen),
        PortSpec(A, :forcing, :input; interval_behavior=:frozen),
        PortSpec(A, :decay_weights, :input; interval_behavior=:frozen),
        PortSpec(A, :field_out, :output; update_law=:replace),
        PortSpec(A, :mcs_field, :output; update_law=:replace),
    )
end

semantic_version(::ManagedFieldAdvanceProcess) = "1.0.0"
semantic_parameters(process::ManagedFieldAdvanceProcess) = (
    contract_version=MANAGED_FIELD_PROCESS_VERSION,
    declaration_id=process.declaration.id,
    declaration_fingerprint=process.declaration.fingerprint,
    resource_authorization=process.resource_authorization,
    subcycles_per_mcs=process.subcycles_per_mcs,
    mcs_publication_policy=:exact_tick_multiple_after_field_publication,
)

function invoke(
    process::ManagedFieldAdvanceProcess,
    inputs::PortView,
    context::InvocationContext,
)
    context.end_time > context.start_time ||
        _fail(:nonpositive_managed_field_interval,
            "managed field process must advance logical time")
    instance = field_engine_reconstruct(
        process.declaration,
        inputs[:field],
        context.start_time.tick,
    )
    projections = (
        EngineInputProjection(
            :forcing,
            inputs.snapshot_version,
            context.start_time,
            inputs[:forcing],
            mode=:frozen,
        ),
        EngineInputProjection(
            :decay_weights,
            inputs.snapshot_version,
            context.start_time,
            inputs[:decay_weights],
            mode=:frozen,
        ),
    )
    invocation = EngineInvocation(
        string(context.event_id, "/engine"),
        :scheduled_field_advance,
        process.declaration,
        IntervalAdvance(context.start_time, context.end_time);
        structural_epoch=process.declaration.fingerprint,
        inputs=projections,
        rng_context=context.rng,
        resource_authorization=process.resource_authorization,
        expected_outputs=(:field_state,),
        expected_diagnostics=
            field_engine_expected_diagnostics(process.declaration.adapter),
    )
    transaction = execute_engine!(instance, invocation)
    transaction.status === :published ||
        _fail(:managed_field_not_published,
            "field engine did not publish at its authorized target")
    values = field_engine_snapshot(instance)
    effects = Delta[
        emit(context, :field_out, ReplaceUpdate(), values),
    ]
    if mod(context.end_time.tick, process.subcycles_per_mcs) == 0
        push!(effects,
            emit(context, :mcs_field, ReplaceUpdate(), values))
    end
    InvocationResult(tuple(effects...);
        diagnostics=(
            engine=process.declaration.id,
            publication=:committed,
        ))
end
