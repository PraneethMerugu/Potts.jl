abstract type AbstractEngineAdapter end
abstract type AbstractEngineInstance end
abstract type AbstractEngineOperation end
abstract type AbstractCompletionHandle end

const ENGINE_OPERATION_FAMILIES =
    (:interval_advance, :boundary_solve, :discrete_batch, :typed_extension)
const ENGINE_INPUT_MODES =
    (:frozen, :interpolated, :event_updated, :continuously_callable)
const ENGINE_REPLAY_CLASSES = (:exact, :numerical, :statistical, :unsupported)
const ENGINE_CONTINUATION_ACTIONS =
    (:preserve, :transform, :reinitialize, :reconstruct, :reject)
const ENGINE_BACKENDS = (:cpu, :metal, :rocm, :cuda)
const ENGINE_RESIDENCIES = (:host, :device, :unified)
const ENGINE_PRECISIONS = (:float32, :float64, :mixed, :exact)

"""
    EngineCapabilities(...)

An immutable, envelope-specific declaration. A capability is evidence scope, not a
claim that every method dispatch or backend supported by a dependency is qualified.
"""
struct EngineCapabilities
    operation_families::Tuple{Vararg{Symbol}}
    problem_envelopes::Tuple{Vararg{String}}
    backends::Tuple{Vararg{Symbol}}
    precisions::Tuple{Vararg{Symbol}}
    residencies::Tuple{Vararg{Symbol}}
    input_modes::Tuple{Vararg{Symbol}}
    boundary_kinds::Tuple{Vararg{Symbol}}
    continuation_actions::Tuple{Vararg{Symbol}}
    replay_class::Symbol
    cancellation::Bool
    diagnostics::Bool
    resize::Bool
    bridges::Tuple{Vararg{String}}
end

function _unique_tuple(values, code::Symbol, label::AbstractString)
    normalized = tuple(values...)
    length(normalized) == length(unique(normalized)) ||
        _fail(code, "$(label) contains duplicates"; values=normalized)
    normalized
end

function EngineCapabilities(;
    operation_families=(:interval_advance,),
    problem_envelopes=("generic",),
    backends=(:cpu,),
    precisions=(:float64,),
    residencies=(:host,),
    input_modes=(:frozen,),
    boundary_kinds=(),
    continuation_actions=(:reconstruct,),
    replay_class::Symbol=:exact,
    cancellation::Bool=false,
    diagnostics::Bool=true,
    resize::Bool=false,
    bridges=(),
)
    operations = _unique_tuple(Symbol.(operation_families),
        :duplicate_engine_capability, "operation families")
    envelopes = _unique_tuple(String.(problem_envelopes),
        :duplicate_engine_capability, "problem envelopes")
    backend_values = _unique_tuple(Symbol.(backends),
        :duplicate_engine_capability, "backends")
    precision_values = _unique_tuple(Symbol.(precisions),
        :duplicate_engine_capability, "precisions")
    residency_values = _unique_tuple(Symbol.(residencies),
        :duplicate_engine_capability, "residencies")
    modes = _unique_tuple(Symbol.(input_modes),
        :duplicate_engine_capability, "input modes")
    boundaries = _unique_tuple(Symbol.(boundary_kinds),
        :duplicate_engine_capability, "boundary kinds")
    actions = _unique_tuple(Symbol.(continuation_actions),
        :duplicate_engine_capability, "continuation actions")
    bridge_values = _unique_tuple(String.(bridges),
        :duplicate_engine_capability, "bridges")

    isempty(operations) &&
        _fail(:empty_engine_operations, "an engine must declare an operation family")
    isempty(envelopes) &&
        _fail(:empty_problem_envelope, "an engine must declare a problem envelope")
    isempty(backend_values) &&
        _fail(:empty_engine_backend, "an engine must declare a backend")
    isempty(precision_values) &&
        _fail(:empty_engine_precision, "an engine must declare a precision")
    isempty(residency_values) &&
        _fail(:empty_engine_residency, "an engine must declare residency")
    Set(operations) <= Set(ENGINE_OPERATION_FAMILIES) ||
        _fail(:unknown_engine_operation, "unknown engine operation family";
            operation_families=operations)
    Set(backend_values) <= Set(ENGINE_BACKENDS) ||
        _fail(:unknown_engine_backend, "unknown engine backend"; backends=backend_values)
    Set(precision_values) <= Set(ENGINE_PRECISIONS) ||
        _fail(:unknown_engine_precision, "unknown engine precision";
            precisions=precision_values)
    Set(residency_values) <= Set(ENGINE_RESIDENCIES) ||
        _fail(:unknown_engine_residency, "unknown engine residency";
            residencies=residency_values)
    Set(modes) <= Set(ENGINE_INPUT_MODES) ||
        _fail(:unknown_engine_input_mode, "unknown engine input mode"; input_modes=modes)
    Set(actions) <= Set(ENGINE_CONTINUATION_ACTIONS) ||
        _fail(:unknown_continuation_action, "unknown continuation action";
            continuation_actions=actions)
    replay_class in ENGINE_REPLAY_CLASSES ||
        _fail(:unknown_replay_class, "unknown engine replay class"; replay_class)

    EngineCapabilities(
        operations,
        envelopes,
        backend_values,
        precision_values,
        residency_values,
        modes,
        boundaries,
        actions,
        replay_class,
        cancellation,
        diagnostics,
        resize,
        bridge_values,
    )
end

engine_semantic_version(::AbstractEngineAdapter) = "1.0.0"
engine_semantic_parameters(::AbstractEngineAdapter) = NamedTuple()

struct EngineDeclaration{A<:AbstractEngineAdapter}
    id::String
    adapter::A
    semantic_version::String
    capabilities::EngineCapabilities
    parameters::NamedTuple
    fingerprint::String
end

function EngineDeclaration(
    id::AbstractString,
    adapter::A;
    semantic_version::AbstractString=engine_semantic_version(adapter),
    capabilities::EngineCapabilities=EngineCapabilities(),
    parameters::NamedTuple=engine_semantic_parameters(adapter),
) where {A<:AbstractEngineAdapter}
    isempty(id) && _fail(:empty_engine_identity, "engine identity cannot be empty")
    isempty(semantic_version) &&
        _fail(:empty_engine_semantic_version, "engine semantic version cannot be empty")
    payload = (
        :process_bigraph_engine_declaration_v1,
        String(id),
        string(A),
        String(semantic_version),
        capabilities,
        parameters,
    )
    EngineDeclaration{A}(
        String(id),
        adapter,
        String(semantic_version),
        capabilities,
        deepcopy(parameters),
        canonical_fingerprint(payload),
    )
end

struct IntervalAdvance <: AbstractEngineOperation
    start_time::LogicalTime
    target_time::LogicalTime
    function IntervalAdvance(start_time::LogicalTime, target_time::LogicalTime)
        _same_scale(start_time, target_time)
        target_time > start_time ||
            _fail(:nonpositive_engine_interval,
                "an interval advance target must be after its start")
        new(start_time, target_time)
    end
end

struct BoundarySolve <: AbstractEngineOperation
    time::LogicalTime
    problem::Symbol
    function BoundarySolve(time::LogicalTime, problem::Symbol)
        isempty(String(problem)) &&
            _fail(:empty_boundary_problem, "boundary problem identity cannot be empty")
        new(time, problem)
    end
end

struct DiscreteBatch <: AbstractEngineOperation
    time::LogicalTime
    batch::Symbol
    count::Int
    function DiscreteBatch(time::LogicalTime, batch::Symbol, count::Integer=1)
        count > 0 || _fail(:empty_discrete_batch,
            "a discrete batch must contain at least one operation"; count)
        count <= typemax(Int) ||
            _fail(:discrete_batch_overflow, "discrete batch count exceeds Int"; count)
        new(time, batch, Int(count))
    end
end

operation_family(::IntervalAdvance) = :interval_advance
operation_family(::BoundarySolve) = :boundary_solve
operation_family(::DiscreteBatch) = :discrete_batch
operation_start(operation::IntervalAdvance) = operation.start_time
operation_target(operation::IntervalAdvance) = operation.target_time
operation_start(operation::Union{BoundarySolve,DiscreteBatch}) = operation.time
operation_target(operation::Union{BoundarySolve,DiscreteBatch}) = operation.time

struct EngineInputProjection
    name::Symbol
    version::UInt64
    time::LogicalTime
    mode::Symbol
    value_type::String
    encoded::Tuple{Vararg{UInt8}}
    fingerprint::String
end

function EngineInputProjection(
    name::Symbol,
    version::Integer,
    time::LogicalTime,
    value;
    mode::Symbol=:frozen,
)
    version >= 0 ||
        _fail(:negative_projection_version, "input projection version cannot be negative")
    version <= typemax(UInt64) ||
        _fail(:projection_version_overflow, "input projection version exceeds UInt64")
    mode in ENGINE_INPUT_MODES ||
        _fail(:unknown_engine_input_mode, "unknown projection input mode"; name, mode)
    owned = deepcopy(value)
    encoded = tuple(encode_logical_value(owned)...)
    EngineInputProjection(
        name,
        UInt64(version),
        time,
        mode,
        string(typeof(owned)),
        encoded,
        canonical_fingerprint((
            :engine_input_projection_v1,
            name,
            UInt64(version),
            time,
            mode,
            owned,
        )),
    )
end

projection_value(input::EngineInputProjection) =
    decode_logical_value(UInt8[input.encoded...])

struct EngineInvocation{O<:AbstractEngineOperation,R}
    id::String
    reason::Symbol
    declaration_fingerprint::String
    operation::O
    structural_epoch::String
    inputs::Tuple{Vararg{EngineInputProjection}}
    rng_context::R
    resource_authorization::NamedTuple
    expected_outputs::Tuple{Vararg{Symbol}}
    expected_diagnostics::Tuple{Vararg{Symbol}}
    fingerprint::String
end

function EngineInvocation(
    id::AbstractString,
    reason::Symbol,
    declaration::EngineDeclaration,
    operation::O;
    structural_epoch::AbstractString,
    inputs=(),
    rng_context=nothing,
    resource_authorization::NamedTuple=NamedTuple(),
    expected_outputs=(),
    expected_diagnostics=(),
) where {O<:AbstractEngineOperation}
    isempty(id) && _fail(:empty_engine_invocation, "engine invocation identity cannot be empty")
    isempty(String(reason)) &&
        _fail(:empty_engine_reason, "engine invocation reason cannot be empty")
    isempty(structural_epoch) &&
        _fail(:empty_structural_epoch, "engine invocation requires a structural epoch")
    family = operation_family(operation)
    family in declaration.capabilities.operation_families ||
        _fail(:unsupported_engine_operation,
            "engine declaration does not support the requested operation";
            engine=declaration.id, operation=family)
    projections = tuple(inputs...)
    all(input -> input isa EngineInputProjection, projections) ||
        _fail(:invalid_engine_projection,
            "engine inputs must be immutable versioned projections")
    names = Symbol[input.name for input in projections]
    length(names) == length(unique(names)) ||
        _fail(:duplicate_engine_projection, "engine input names must be unique")
    all(input -> input.mode in declaration.capabilities.input_modes, projections) ||
        _fail(:unsupported_engine_input_mode,
            "an input projection mode is unsupported by the engine")
    start_time = operation_start(operation)
    all(input -> (_same_scale(input.time, start_time);
            input.time <= start_time), projections) ||
        _fail(:future_engine_projection,
            "engine input projections cannot originate after invocation start")
    outputs = _unique_tuple(Symbol.(expected_outputs),
        :duplicate_engine_output, "expected outputs")
    diagnostics = _unique_tuple(Symbol.(expected_diagnostics),
        :duplicate_engine_diagnostic, "expected diagnostics")
    resources = deepcopy(resource_authorization)
    if haskey(resources, :backend)
        resources.backend in declaration.capabilities.backends ||
            _fail(:unsupported_engine_backend,
                "resource authorization selected an unsupported backend";
                backend=resources.backend)
    end
    if haskey(resources, :precision)
        resources.precision in declaration.capabilities.precisions ||
            _fail(:unsupported_engine_precision,
                "resource authorization selected an unsupported precision";
                precision=resources.precision)
    end
    if haskey(resources, :residency)
        resources.residency in declaration.capabilities.residencies ||
            _fail(:unsupported_engine_residency,
                "resource authorization selected unsupported residency";
                residency=resources.residency)
    end
    payload = (
        :process_bigraph_engine_invocation_v1,
        String(id),
        reason,
        declaration.fingerprint,
        operation,
        String(structural_epoch),
        projections,
        resources,
        outputs,
        diagnostics,
    )
    EngineInvocation(
        String(id),
        reason,
        declaration.fingerprint,
        operation,
        String(structural_epoch),
        projections,
        rng_context,
        resources,
        outputs,
        diagnostics,
        canonical_fingerprint(payload),
    )
end

struct EngineCandidate{P,C,D}
    actual_time::LogicalTime
    payload::P
    effects::Tuple
    continuation::C
    diagnostics::D
    fingerprint::String
end

function EngineCandidate(
    actual_time::LogicalTime,
    payload;
    effects=(),
    continuation=nothing,
    diagnostics=NamedTuple(),
    fingerprint=nothing,
)
    normalized_effects = tuple((Symbol(first(effect)) => last(effect)
        for effect in effects)...)
    names = Symbol[first(effect) for effect in normalized_effects]
    length(names) == length(unique(names)) ||
        _fail(:duplicate_engine_effect, "engine candidate effect names must be unique")
    candidate_fingerprint = isnothing(fingerprint) ?
        canonical_fingerprint((
            :engine_candidate_v1,
            actual_time,
            normalized_effects,
            continuation,
            diagnostics,
        )) : String(fingerprint)
    isempty(candidate_fingerprint) &&
        _fail(:empty_engine_candidate_fingerprint,
            "engine candidate fingerprint cannot be empty")
    EngineCandidate(
        actual_time,
        payload,
        normalized_effects,
        deepcopy(continuation),
        deepcopy(diagnostics),
        candidate_fingerprint,
    )
end

struct EngineEarlyReturn{D}
    actual_time::LogicalTime
    reason::Symbol
    diagnostics::D
end

EngineEarlyReturn(actual_time::LogicalTime, reason::Symbol; diagnostics=NamedTuple()) =
    EngineEarlyReturn(actual_time, reason, deepcopy(diagnostics))

struct EngineEventRequest{P}
    actual_time::LogicalTime
    event::Symbol
    payload::P
end

EngineEventRequest(actual_time::LogicalTime, event::Symbol) =
    EngineEventRequest(actual_time, event, NamedTuple())

struct EngineFailure{D}
    code::Symbol
    stage::Symbol
    retry_class::Symbol
    diagnostics::D
end

function EngineFailure(
    code::Symbol,
    stage::Symbol;
    retry_class::Symbol=:never,
    diagnostics=NamedTuple(),
)
    retry_class in (:never, :reconstruct, :retry_same, :retry_changed_resources) ||
        _fail(:unknown_engine_retry_class, "unknown engine retry class"; retry_class)
    EngineFailure(code, stage, retry_class, deepcopy(diagnostics))
end

struct EngineContinuation{T}
    owner::String
    identity::String
    schema_version::String
    codec_version::String
    replay_class::Symbol
    invalidated_by::Tuple{Vararg{Symbol}}
    value::T
    fingerprint::String
end

function EngineContinuation(
    owner::AbstractString,
    identity::AbstractString,
    value;
    schema_version::AbstractString="1.0.0",
    codec_version::AbstractString="1.0.0",
    replay_class::Symbol=:exact,
    invalidated_by=(:algorithm, :precision, :backend, :geometry, :topology),
)
    isempty(owner) && _fail(:empty_engine_continuation_owner,
        "engine continuation owner cannot be empty")
    isempty(identity) && _fail(:empty_engine_continuation_identity,
        "engine continuation identity cannot be empty")
    replay_class in ENGINE_REPLAY_CLASSES ||
        _fail(:unknown_replay_class, "unknown engine continuation replay class";
            replay_class)
    invalidations = _unique_tuple(Symbol.(invalidated_by),
        :duplicate_engine_invalidation, "engine continuation invalidations")
    encode_logical_value(value)
    fingerprint = canonical_fingerprint((
        :process_bigraph_engine_continuation_v1,
        String(owner),
        String(identity),
        String(schema_version),
        String(codec_version),
        replay_class,
        invalidations,
        value,
    ))
    EngineContinuation(
        String(owner),
        String(identity),
        String(schema_version),
        String(codec_version),
        replay_class,
        invalidations,
        deepcopy(value),
        fingerprint,
    )
end

function engine_continuation_action(
    continuation::EngineContinuation,
    changes;
    invalidated_action::Symbol=:reconstruct,
)
    invalidated_action in ENGINE_CONTINUATION_ACTIONS ||
        _fail(:unknown_continuation_action, "unknown continuation action";
            invalidated_action)
    changed = Set(Symbol.(changes))
    isempty(intersect(changed, Set(continuation.invalidated_by))) ?
        :preserve : invalidated_action
end

function encode_engine_continuation(continuation::EngineContinuation)
    encode_logical_value((
        schema=:process_bigraph_engine_continuation_v1,
        owner=continuation.owner,
        identity=continuation.identity,
        schema_version=continuation.schema_version,
        codec_version=continuation.codec_version,
        replay_class=continuation.replay_class,
        invalidated_by=continuation.invalidated_by,
        value=continuation.value,
        fingerprint=continuation.fingerprint,
    ))
end

function decode_engine_continuation(
    bytes;
    owner::AbstractString,
    identity::AbstractString,
    schema_version::AbstractString,
    codec_version::AbstractString,
)
    payload = decode_logical_value(bytes)
    payload isa NamedTuple && payload.schema === :process_bigraph_engine_continuation_v1 ||
        _fail(:invalid_engine_continuation,
            "payload is not a managed-engine continuation")
    payload.owner == owner && payload.identity == identity ||
        _fail(:engine_continuation_owner_mismatch,
            "engine continuation owner or identity changed";
            expected_owner=String(owner), actual_owner=payload.owner,
            expected_identity=String(identity), actual_identity=payload.identity)
    payload.schema_version == schema_version &&
        payload.codec_version == codec_version ||
        _fail(:engine_continuation_version_mismatch,
            "engine continuation schema or codec version changed")
    continuation = EngineContinuation(
        payload.owner,
        payload.identity,
        payload.value;
        schema_version=payload.schema_version,
        codec_version=payload.codec_version,
        replay_class=payload.replay_class,
        invalidated_by=payload.invalidated_by,
    )
    continuation.fingerprint == payload.fingerprint ||
        _fail(:engine_continuation_integrity_failure,
            "engine continuation fingerprint does not match its payload")
    continuation
end

function aggregate_replay_class(classes)
    rank = Dict(:exact => 1, :numerical => 2, :statistical => 3, :unsupported => 4)
    normalized = Symbol.(classes)
    isempty(normalized) &&
        _fail(:empty_replay_aggregate, "replay aggregation requires components")
    all(class -> haskey(rank, class), normalized) ||
        _fail(:unknown_replay_class, "replay aggregation contains an unknown class")
    last(sort(normalized; by=class -> rank[class]))
end

struct ImmediateCompletionHandle{T} <: AbstractCompletionHandle
    outcome::T
end

struct EngineTransactionResult{O,P}
    status::Symbol
    outcome::O
    publication::P
end

prepare_engine(adapter::AbstractEngineAdapter, declaration::EngineDeclaration) =
    _fail(:missing_prepare_engine,
        "engine adapter does not implement prepare_engine";
        adapter=string(typeof(adapter)), engine=declaration.id)
prepare_engine(declaration::EngineDeclaration) =
    prepare_engine(declaration.adapter, declaration)

stage_operation!(instance::AbstractEngineInstance, invocation::EngineInvocation) =
    _fail(:missing_stage_operation,
        "engine instance does not implement stage_operation!";
        instance=string(typeof(instance)), invocation=invocation.id)

complete_operation!(
    ::AbstractEngineInstance,
    handle::ImmediateCompletionHandle,
) = handle.outcome

complete_operation!(instance::AbstractEngineInstance, ::AbstractCompletionHandle) =
    _fail(:missing_complete_operation,
        "engine instance does not implement complete_operation!";
        instance=string(typeof(instance)))

function _validate_reached_time(invocation::EngineInvocation, actual::LogicalTime;
    terminal::Bool,
)
    start = operation_start(invocation.operation)
    target = operation_target(invocation.operation)
    _same_scale(start, actual)
    start <= actual <= target ||
        _fail(:engine_time_out_of_bounds,
            "engine result time is outside the authorized interval";
            invocation=invocation.id, actual=actual.tick,
            start=start.tick, target=target.tick)
    terminal && actual != target &&
        _fail(:engine_target_not_reached,
            "a successful engine candidate must reach the exact target";
            invocation=invocation.id, actual=actual.tick, target=target.tick)
    actual
end

function validate_candidate(
    ::AbstractEngineInstance,
    invocation::EngineInvocation,
    candidate::EngineCandidate,
)
    _validate_reached_time(invocation, candidate.actual_time; terminal=true)
    actual_outputs = Set(Symbol[first(effect) for effect in candidate.effects])
    actual_outputs == Set(invocation.expected_outputs) ||
        _fail(:engine_effect_schema_mismatch,
            "engine candidate effects do not match the expected schema";
            invocation=invocation.id,
            expected=sort!(collect(Set(invocation.expected_outputs))),
            actual=sort!(collect(actual_outputs)))
    candidate.diagnostics isa NamedTuple ||
        _fail(:invalid_engine_diagnostics,
            "normalized engine diagnostics must be a named tuple";
            invocation=invocation.id)
    Set(keys(candidate.diagnostics)) == Set(invocation.expected_diagnostics) ||
        _fail(:engine_diagnostic_schema_mismatch,
            "engine diagnostics do not match the expected schema";
            invocation=invocation.id,
            expected=sort!(collect(Set(invocation.expected_diagnostics))),
            actual=sort!(collect(Set(keys(candidate.diagnostics)))))
    true
end

publish_candidate!(
    instance::AbstractEngineInstance,
    invocation::EngineInvocation,
    candidate::EngineCandidate,
) = _fail(:missing_publish_candidate,
    "engine instance does not implement publish_candidate!";
    instance=string(typeof(instance)), invocation=invocation.id)

discard_candidate!(
    ::AbstractEngineInstance,
    ::EngineInvocation,
    candidate,
) = nothing

function _validate_nonterminal(
    invocation::EngineInvocation,
    outcome::Union{EngineEarlyReturn,EngineEventRequest},
)
    _validate_reached_time(invocation, outcome.actual_time; terminal=false)
    operation_family(invocation.operation) === :interval_advance &&
        outcome.actual_time == operation_target(invocation.operation) &&
        _fail(:terminal_time_as_early_return,
            "a result at the exact target must be a candidate, not an early return";
            invocation=invocation.id)
    true
end

"""
    execute_engine!(instance, invocation; authorize)

Runs the runtime-owned transaction boundary. The adapter stages and completes heavy
work, while this function validates and authorizes before the one-way publication
method is invoked. Any pre-publication failure calls `discard_candidate!`.
"""
function execute_engine!(
    instance::AbstractEngineInstance,
    invocation::EngineInvocation;
    authorize=(candidate, invocation) -> true,
)
    staged = nothing
    outcome = nothing
    try
        staged = stage_operation!(instance, invocation)
        staged isa AbstractCompletionHandle ||
            _fail(:invalid_completion_handle,
                "stage_operation! must return an AbstractCompletionHandle";
                actual=string(typeof(staged)))
        outcome = complete_operation!(instance, staged)
        if outcome isa EngineCandidate
            validate_candidate(instance, invocation, outcome)
            authorize(outcome, invocation) === true ||
                _fail(:engine_candidate_unauthorized,
                    "runtime authorization rejected the staged candidate";
                    invocation=invocation.id)
            publication = publish_candidate!(instance, invocation, outcome)
            return EngineTransactionResult(:published, outcome, publication)
        elseif outcome isa Union{EngineEarlyReturn,EngineEventRequest}
            _validate_nonterminal(invocation, outcome)
            discard_candidate!(instance, invocation, outcome)
            return EngineTransactionResult(:returned, outcome, nothing)
        elseif outcome isa EngineFailure
            discard_candidate!(instance, invocation, outcome)
            throw(ProcessBigraphError(
                outcome.code,
                "engine reported a structured failure";
                stage=outcome.stage,
                retry_class=outcome.retry_class,
                invocation=invocation.id,
            ))
        else
            _fail(:invalid_engine_outcome,
                "engine completion returned an unsupported result";
                actual=string(typeof(outcome)), invocation=invocation.id)
        end
    catch error
        if !(outcome isa EngineFailure)
            try
                discard_candidate!(instance, invocation,
                    isnothing(outcome) ? staged : outcome)
            catch
                # The original failure remains authoritative. A production executor
                # records ordered secondary cleanup failures in its diagnostic record.
            end
        end
        rethrow(error)
    end
end

function _canonical(io::IO, capabilities::EngineCapabilities)
    write(io, "EC")
    _canonical(io, "1.0.0")
    _canonical(io, capabilities.operation_families)
    _canonical(io, capabilities.problem_envelopes)
    _canonical(io, capabilities.backends)
    _canonical(io, capabilities.precisions)
    _canonical(io, capabilities.residencies)
    _canonical(io, capabilities.input_modes)
    _canonical(io, capabilities.boundary_kinds)
    _canonical(io, capabilities.continuation_actions)
    _canonical(io, capabilities.replay_class)
    _canonical(io, capabilities.cancellation)
    _canonical(io, capabilities.diagnostics)
    _canonical(io, capabilities.resize)
    _canonical(io, capabilities.bridges)
end

function _canonical(io::IO, operation::IntervalAdvance)
    write(io, "EA")
    _canonical(io, operation.start_time)
    _canonical(io, operation.target_time)
end

function _canonical(io::IO, operation::BoundarySolve)
    write(io, "EB")
    _canonical(io, operation.time)
    _canonical(io, operation.problem)
end

function _canonical(io::IO, operation::DiscreteBatch)
    write(io, "ED")
    _canonical(io, operation.time)
    _canonical(io, operation.batch)
    _canonical(io, operation.count)
end

function _canonical(io::IO, input::EngineInputProjection)
    write(io, "EP")
    _canonical(io, input.name)
    _canonical(io, input.version)
    _canonical(io, input.time)
    _canonical(io, input.mode)
    _canonical(io, input.value_type)
    _canonical(io, input.fingerprint)
end
