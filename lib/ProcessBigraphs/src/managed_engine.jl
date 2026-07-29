const MANAGED_ENGINE_RUNTIME_VERSION = "process-bigraph-managed-engine-v1"
const DOMAIN_STRUCTURAL_REQUEST_VERSION =
    "process-bigraph-domain-structural-request-v1"
const DOMAIN_STRUCTURAL_OPERATIONS =
    (:add, :remove, :divide, :move, :rewire)

struct DomainStructuralIdentity
    domain::String
    kind::Symbol
    id::String
    generation::UInt64
    function DomainStructuralIdentity(
        domain::AbstractString,
        kind::Symbol,
        id::AbstractString,
        generation::Integer=0,
    )
        isempty(domain) &&
            _fail(:empty_domain_identity_namespace,
                "domain structural identity requires a namespace")
        isempty(String(kind)) &&
            _fail(:empty_domain_identity_kind,
                "domain structural identity requires a kind")
        isempty(id) &&
            _fail(:empty_domain_identity,
                "domain structural identity cannot be empty")
        generation >= 0 && generation <= typemax(UInt64) ||
            _fail(:invalid_domain_generation,
                "domain structural generation must fit UInt64";
                generation)
        new(String(domain), kind, String(id), UInt64(generation))
    end
end

Base.:(==)(left::DomainStructuralIdentity, right::DomainStructuralIdentity) =
    left.domain == right.domain &&
    left.kind === right.kind &&
    left.id == right.id &&
    left.generation == right.generation
Base.isequal(left::DomainStructuralIdentity, right::DomainStructuralIdentity) =
    left == right
Base.hash(identity::DomainStructuralIdentity, seed::UInt) =
    hash((identity.domain, identity.kind, identity.id, identity.generation), seed)

_domain_identity_payload(identity::DomainStructuralIdentity) = (
    domain=identity.domain,
    kind=identity.kind,
    id=identity.id,
    generation=identity.generation,
)

struct DomainStructuralRequest{P<:NamedTuple}
    request_id::String
    owner::String
    source_epoch::UInt64
    operation::Symbol
    targets::Tuple{Vararg{DomainStructuralIdentity}}
    payload::P
    dependencies::Tuple{Vararg{String}}
    priority::Int
    fingerprint::String
end

function DomainStructuralRequest(
    request_id::AbstractString,
    owner::AbstractString,
    source_epoch::Integer,
    operation::Symbol,
    targets;
    payload::NamedTuple=NamedTuple(),
    dependencies=(),
    priority::Integer=0,
)
    isempty(request_id) &&
        _fail(:empty_domain_request_identity,
            "domain structural request identity cannot be empty")
    isempty(owner) &&
        _fail(:empty_domain_request_owner,
            "domain structural request owner cannot be empty")
    source_epoch >= 0 && source_epoch <= typemax(UInt64) ||
        _fail(:invalid_domain_source_epoch,
            "domain structural source epoch must fit UInt64";
            source_epoch)
    operation in DOMAIN_STRUCTURAL_OPERATIONS ||
        _fail(:unsupported_domain_structural_operation,
            "domain structural request uses an unsupported operation";
            operation)
    normalized_targets = tuple(targets...)
    all(value -> value isa DomainStructuralIdentity, normalized_targets) ||
        _fail(:untyped_domain_structural_target,
            "domain structural targets must use DomainStructuralIdentity")
    if operation === :add
        length(normalized_targets) <= 1 ||
            _fail(:invalid_domain_request_arity,
                "domain add accepts at most one container target")
    elseif operation in (:remove, :divide)
        length(normalized_targets) == 1 ||
            _fail(:invalid_domain_request_arity,
                "domain remove/divide requires exactly one target")
    else
        length(normalized_targets) == 2 ||
            _fail(:invalid_domain_request_arity,
                "domain move/rewire requires exactly two targets")
    end
    encode_logical_value(payload)
    deps = tuple(sort!(unique!(String[String(value)
        for value in dependencies]))...)
    any(isempty, deps) &&
        _fail(:empty_domain_request_dependency,
            "domain structural dependency identity cannot be empty")
    priority >= typemin(Int) && priority <= typemax(Int) ||
        _fail(:domain_request_priority_overflow,
            "domain structural request priority exceeds Int")
    request_payload = (
        contract_version=DOMAIN_STRUCTURAL_REQUEST_VERSION,
        request_id=String(request_id),
        owner=String(owner),
        source_epoch=UInt64(source_epoch),
        operation,
        targets=tuple((_domain_identity_payload(value)
            for value in normalized_targets)...),
        payload,
        dependencies=deps,
        priority=Int(priority),
    )
    DomainStructuralRequest(
        String(request_id),
        String(owner),
        UInt64(source_epoch),
        operation,
        normalized_targets,
        deepcopy(payload),
        deps,
        Int(priority),
        canonical_fingerprint(request_payload),
    )
end

struct DomainStructuralDisposition
    request_id::String
    status::Symbol
    conflicting_with::Union{Nothing,String}
end

struct DomainStructuralSelection
    source_epoch::UInt64
    selected::Tuple{Vararg{DomainStructuralRequest}}
    dispositions::Tuple{Vararg{DomainStructuralDisposition}}
    fingerprint::String
end

function _exclusive_domain_targets(request::DomainStructuralRequest)
    request.operation === :add && return ()
    (first(request.targets),)
end

function select_domain_structural_requests(
    requests;
    maximum_selected::Integer=typemax(Int),
)
    supplied = DomainStructuralRequest[requests...]
    isempty(supplied) &&
        _fail(:empty_domain_request_batch,
            "domain structural selection requires at least one request")
    maximum_selected >= 0 && maximum_selected <= typemax(Int) ||
        _fail(:invalid_domain_request_capacity,
            "domain structural selection capacity must fit nonnegative Int")
    ids = String[request.request_id for request in supplied]
    length(ids) == length(unique(ids)) ||
        _fail(:duplicate_domain_request,
            "domain structural request identities must be unique")
    epochs = unique(UInt64[request.source_epoch for request in supplied])
    length(epochs) == 1 ||
        _fail(:mixed_domain_source_epochs,
            "one domain structural transaction cannot mix source epochs")
    known = Set(ids)
    all(request -> all(in(known), request.dependencies), supplied) ||
        _fail(:unknown_domain_request_dependency,
            "domain structural dependency is not present in the batch")
    selected = DomainStructuralRequest[]
    claimed = Dict{DomainStructuralIdentity,String}()
    dispositions = DomainStructuralDisposition[]
    status = Dict{String,Symbol}()
    pending = Dict(request.request_id => request for request in supplied)
    while !isempty(pending)
        ready = DomainStructuralRequest[
            request for request in values(pending)
            if all(dependency -> haskey(status, dependency),
                request.dependencies)
        ]
        isempty(ready) &&
            _fail(:cyclic_domain_request_dependencies,
                "domain structural request dependencies contain a cycle")
        sort!(ready; by=request ->
            (-request.priority, request.request_id))
        for request in ready
            rejected_dependency = findfirst(dependency ->
                status[dependency] !== :selected, request.dependencies)
            disposition = if !isnothing(rejected_dependency)
                DomainStructuralDisposition(
                    request.request_id,
                    :dependency_rejected,
                    request.dependencies[rejected_dependency],
                )
            else
                exclusive = _exclusive_domain_targets(request)
                conflict = findfirst(target -> haskey(claimed, target),
                    exclusive)
                if !isnothing(conflict)
                    DomainStructuralDisposition(
                        request.request_id,
                        :conflict_rejected,
                        claimed[exclusive[conflict]],
                    )
                elseif length(selected) >= maximum_selected
                    DomainStructuralDisposition(
                        request.request_id, :capacity_rejected, nothing)
                else
                    push!(selected, request)
                    for target in exclusive
                        claimed[target] = request.request_id
                    end
                    DomainStructuralDisposition(
                        request.request_id, :selected, nothing)
                end
            end
            push!(dispositions, disposition)
            status[request.request_id] = disposition.status
            delete!(pending, request.request_id)
        end
    end
    sort!(dispositions; by=value -> value.request_id)
    normalized_selected = tuple(sort!(selected;
        by=request -> request.request_id)...)
    normalized_dispositions = tuple(dispositions...)
    fingerprint = canonical_fingerprint((
        DOMAIN_STRUCTURAL_REQUEST_VERSION,
        only(epochs),
        tuple((request.fingerprint for request
            in normalized_selected)...),
        tuple(((value.request_id, value.status, value.conflicting_with)
            for value in normalized_dispositions)...),
    ))
    DomainStructuralSelection(
        only(epochs),
        normalized_selected,
        normalized_dispositions,
        fingerprint,
    )
end

mutable struct ManagedEngineRuntime{D<:EngineDeclaration,I<:AbstractEngineInstance}
    declaration::D
    instance::I
    logical_time::LogicalTime
    structural_epoch::String
    invocation_ordinal::UInt64
    publication_version::UInt64
    is_settled::Bool
    last_result::Any
    last_failure::Union{Nothing,ProcessBigraphError}
end

function managed_engine_runtime(
    declaration::EngineDeclaration,
    initial_time::LogicalTime;
    structural_epoch::AbstractString,
)
    isempty(structural_epoch) &&
        _fail(:empty_structural_epoch,
            "managed engine runtime requires a structural epoch")
    instance = prepare_engine(declaration)
    ManagedEngineRuntime(
        declaration,
        instance,
        initial_time,
        String(structural_epoch),
        UInt64(0),
        UInt64(0),
        true,
        nothing,
        nothing,
    )
end

managed_engine_time(runtime::ManagedEngineRuntime) = runtime.logical_time
managed_engine_settled(runtime::ManagedEngineRuntime) = runtime.is_settled
managed_engine_instance(runtime::ManagedEngineRuntime) = runtime.instance

function _managed_projection(
    runtime::ManagedEngineRuntime,
    pair::Pair;
    mode::Symbol=:frozen,
)
    EngineInputProjection(
        Symbol(first(pair)),
        runtime.publication_version,
        runtime.logical_time,
        last(pair);
        mode,
    )
end

function advance_managed_engine!(
    runtime::ManagedEngineRuntime,
    target::LogicalTime;
    reason::Symbol=:scheduled_interval,
    inputs=(),
    input_mode::Symbol=:frozen,
    resource_authorization::NamedTuple=NamedTuple(),
    expected_outputs=(),
    expected_diagnostics=(),
    rng_context=nothing,
    authorize=(candidate, invocation) -> true,
)
    runtime.is_settled ||
        _fail(:managed_engine_unsettled,
            "managed engine runtime already has an in-flight transaction")
    runtime.last_failure === nothing ||
        _fail(:managed_engine_fail_stop,
            "managed engine runtime requires explicit reconstruction after failure";
            code=runtime.last_failure.code)
    _same_scale(runtime.logical_time, target)
    target > runtime.logical_time ||
        _fail(:nonpositive_engine_interval,
            "managed engine target must advance exact logical time";
            start=runtime.logical_time.tick, target=target.tick)
    ordinal = Base.Checked.checked_add(
        runtime.invocation_ordinal, UInt64(1))
    invocation_id = string(
        runtime.declaration.id, ":invocation:", ordinal)
    projections = tuple((
        value isa EngineInputProjection ? value :
        _managed_projection(runtime, value; mode=input_mode)
        for value in inputs
    )...)
    invocation = EngineInvocation(
        invocation_id,
        reason,
        runtime.declaration,
        IntervalAdvance(runtime.logical_time, target);
        structural_epoch=runtime.structural_epoch,
        inputs=projections,
        rng_context,
        resource_authorization,
        expected_outputs,
        expected_diagnostics,
    )
    runtime.is_settled = false
    try
        result = execute_engine!(
            runtime.instance, invocation; authorize)
        result.status === :published ||
            _fail(:managed_engine_nonterminal,
                "managed interval returned before its exact target";
                invocation=invocation.id, status=result.status)
        runtime.logical_time = result.outcome.actual_time
        runtime.invocation_ordinal = ordinal
        runtime.publication_version = Base.Checked.checked_add(
            runtime.publication_version, UInt64(1))
        runtime.last_result = result
        runtime.is_settled = true
        result
    catch error
        runtime.is_settled = true
        if error isa ProcessBigraphError
            runtime.last_failure = error
            rethrow()
        else
            failure = ProcessBigraphError(
                :managed_engine_failure,
                "managed engine transaction failed";
                cause=sprint(showerror, error),
                invocation=invocation.id,
            )
            runtime.last_failure = failure
            throw(failure)
        end
    end
end

function reconstruct_managed_engine!(
    runtime::ManagedEngineRuntime,
    instance::AbstractEngineInstance,
)
    runtime.is_settled ||
        _fail(:managed_engine_unsettled,
            "cannot reconstruct an in-flight engine")
    runtime.instance = instance
    runtime.last_failure = nothing
    runtime.last_result = nothing
    runtime
end

function _managed_engine_payload(runtime::ManagedEngineRuntime)
    (
        contract_version=MANAGED_ENGINE_RUNTIME_VERSION,
        declaration_id=runtime.declaration.id,
        declaration_fingerprint=runtime.declaration.fingerprint,
        logical_time=runtime.logical_time,
        structural_epoch=runtime.structural_epoch,
        invocation_ordinal=runtime.invocation_ordinal,
        publication_version=runtime.publication_version,
    )
end
