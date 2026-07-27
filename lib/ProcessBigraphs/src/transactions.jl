const FAILURE_SCHEMA_VERSION = "process-bigraph-failure-v1"
const FAILURE_STAGES = (
    :process_invocation,
    :invocation_result_validation,
    :reconciliation,
    :reactive_step_execution,
    :continuation_validation,
    :required_observation,
    :checkpoint_capture,
    :record_publication,
)

struct RuntimeDiagnostic
    schema_version::String
    semantic_code::Symbol
    stage::Symbol
    owner::String
    logical_time::LogicalTime
    event_identity::String
    last_stable_fingerprint::String
    cause_classification::Symbol
    retry_classification::Symbol
end

struct FailureInjection
    stage::Union{Nothing,Symbol}
    owner::Union{Nothing,String}
    function FailureInjection(
        stage::Union{Nothing,Symbol}=nothing;
        owner=nothing,
    )
        isnothing(stage) || stage in FAILURE_STAGES ||
            _fail(:invalid_failure_injection_stage,
                "failure injection stage is not registered"; stage)
        new(stage, isnothing(owner) ? nothing : String(owner))
    end
end

function _inject_failure(
    injection::FailureInjection,
    stage::Symbol,
    owner::AbstractString,
)
    injection.stage === stage || return
    isnothing(injection.owner) || injection.owner == owner || return
    _fail(:injected_failure, "deterministic failure injection requested";
        stage, owner=String(owner))
end

function _canonical(io::IO, diagnostic::RuntimeDiagnostic)
    write(io, "RD")
    _canonical(io, diagnostic.schema_version)
    _canonical(io, diagnostic.semantic_code)
    _canonical(io, diagnostic.stage)
    _canonical(io, diagnostic.owner)
    _canonical(io, diagnostic.logical_time)
    _canonical(io, diagnostic.event_identity)
    _canonical(io, diagnostic.last_stable_fingerprint)
    _canonical(io, diagnostic.cause_classification)
    _canonical(io, diagnostic.retry_classification)
end
