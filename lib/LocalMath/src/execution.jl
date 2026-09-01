@inline function _validate_stage_parameter_value(slot::_StageParameterSlot,
        value)
    _stage_parameter_in_bounds(value, slot.bounds) || throw(
        LocalMathValidationError(
            "submission value $(slot.name) is outside its declared bounds";
            stage = :execute, contract = :submission_value_bounds,
            binding = slot.name,
            expected = slot.bounds isa _ClosedParameterBounds ?
                (slot.bounds.lower, slot.bounds.upper) : :unbounded,
            actual = value,
        ))
    return value
end

@inline _submission_slot_names(layout::_StageParameterLayout) =
    map(slot -> slot.name, layout.slots)

@generated function _canonical_submission(
        layout::_StageParameterLayout{S}, submission::Q
    ) where {S<:Tuple,Q<:NamedTuple}
    slot_types = S.parameters
    submission_names = Q.parameters[1]
    length(slot_types) == length(submission_names) || return :(
        throw(LocalMathValidationError(
            "submission names do not exactly match the prepared parameter layout";
            stage = :execute, contract = :submission_slot_names,
            expected = _submission_slot_names(layout),
            actual = $(QuoteNode(submission_names)),
        )))
    values = Expr[]
    for (slot_index, slot_type) in pairs(slot_types)
        T = slot_type.parameters[1]
        slot = :(getfield(layout.slots, $slot_index))
        selection = :(throw(LocalMathValidationError(
            "submission names do not exactly match the prepared parameter layout";
            stage = :execute, contract = :submission_slot_names,
            binding = $slot.name, expected = $slot.name,
            actual = $(QuoteNode(submission_names)),
        )))
        for submission_index in reverse(eachindex(submission_names))
            name = submission_names[submission_index]
            candidate = :(getfield(submission, $submission_index))
            selection = :($slot.name === $(QuoteNode(name)) ? begin
                typeof($candidate) === $T || throw(LocalMathValidationError(
                    "submission value has the wrong exact type";
                    stage = :execute, contract = :submission_value_type,
                    binding = $slot.name, expected = $T,
                    actual = typeof($candidate),
                ))
                $candidate::$T
            end : $selection)
        end
        push!(values, :(_validate_stage_parameter_value($slot, $selection)))
    end
    return :(($(values...),))
end

struct _SuccessfulWorkGate{G,S} <: AbstractVector{Bool}
    parent::G
    statuses::S
    lease_index::Int32
end

Base.size(::_SuccessfulWorkGate) = (1,)
Base.length(::_SuccessfulWorkGate) = 1
Base.strides(::_SuccessfulWorkGate) = (1,)
Base.IndexStyle(::Type{<:_SuccessfulWorkGate}) = IndexLinear()

function Adapt.adapt_structure(to, gate::_SuccessfulWorkGate)
    return _SuccessfulWorkGate(
        Adapt.adapt(to, gate.parent),
        Adapt.adapt(to, gate.statuses),
        gate.lease_index,
    )
end

@inline _validation_prefix_succeeded(::Tuple{}, _lease_index::Int32) = true
@inline function _validation_prefix_succeeded(
        statuses::Tuple, lease_index::Int32
    )
    succeeded = @inbounds first(statuses)[
        _VALIDATION_FAILURE_CLASS, lease_index
    ] == UInt32(0)
    return succeeded && _validation_prefix_succeeded(
        Base.tail(statuses), lease_index
    )
end

@inline function Base.getindex(gate::_SuccessfulWorkGate, index::Integer)
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return @inbounds(gate.parent[1]) && _validation_prefix_succeeded(
        gate.statuses, gate.lease_index
    )
end

function KernelAbstractions.get_backend(gate::_SuccessfulWorkGate)
    backend = KernelAbstractions.get_backend(gate.parent)
    all(status -> KernelAbstractions.get_backend(status) == backend,
        gate.statuses) || throw(LocalMathValidationError(
            "success-gate parents belong to different backends";
            stage = :prepare,
            contract = :provider_backend,
            expected = backend,
            actual = map(KernelAbstractions.get_backend, gate.statuses),
        ))
    return backend
end

function _success_gate(prepared::PreparedPlan, lease_index::Int32, parent)
    current_task() === prepared.owner || throw(LocalMathValidationError(
        "a success gate belongs to the task that prepared its source work";
        stage = :execute,
        contract = :receipt_owner,
        expected = prepared.owner,
        actual = current_task(),
    ))
    statuses = map(
        status -> status.device, _prepared_validation_statuses(prepared)
    )
    isempty(statuses) && throw(LocalMathValidationError(
        "success_gate requires a source work with device validation status";
        stage = :prepare,
        contract = :validation_status,
        expected = :device_validation_status,
        actual = :none,
    ))
    return _SuccessfulWorkGate(
        parent, statuses, lease_index
    )
end

"""
    success_gate(source::PreparedPlan, parent)
    success_gate(receipt::ExecutionReceipt, parent)

Construct a device-resident Boolean gate for downstream `LocalLaw`. The gate
opens only when `parent[1]` is true and every validation status produced by the
selected source submission is successful. The `PreparedPlan` form describes
the next submission and can be used to construct a gate before submission; the
`ExecutionReceipt` form addresses the exact submitted lease. Neither form waits or
copies status to the host.
"""
function success_gate(source::PreparedPlan, parent)
    lease_index = _available_lease(source)
    lease_index != 0 || throw(
        LocalMathValidationError(
            "success-gate source has no available submission lease";
            stage = :prepare,
            contract = :workspace_lease_capacity,
            expected = :available,
            actual = submission_capacity(source),
        )
    )
    return _success_gate(source, Int32(lease_index), parent)
end

function success_gate(receipt::ExecutionReceipt, parent)
    prepared = receipt.prepared
    !_receipt_settled(receipt) &&
        prepared.leases[Int(receipt.lease_index)] === receipt || throw(
        LocalMathValidationError(
            "success_gate requires an outstanding source receipt";
            stage = :execute,
            contract = :receipt_serial,
            expected = :outstanding,
            actual = receipt.serial,
        )
    )
    return _success_gate(prepared, receipt.lease_index, parent)
end

"""
    submission_capacity(prepared::PreparedPlan)

Return the allocation-free mechanical queue-capacity facts for a preparation.
Domain packages remain responsible for translating these facts into complete
scientific-step preflight requirements.
"""
function submission_capacity(prepared::PreparedPlan)
    capacity = length(prepared.leases)
    outstanding = prepared.outstanding
    return (
        capacity,
        outstanding,
        available = capacity - outstanding,
        submitted = prepared.submitted,
        drained = prepared.drained,
    )
end

@inline _receipt_settled(receipt::ExecutionReceipt) =
    receipt.state != _EXECUTION_RECEIPT_PENDING
@inline _receipt_succeeded(receipt::ExecutionReceipt) =
    receipt.state == _EXECUTION_RECEIPT_SUCCESS

function _available_lease(prepared::PreparedPlan)
    capacity = length(prepared.leases)
    prepared.outstanding < capacity || return 0
    for offset in 0:(capacity - 1)
        index = mod1(prepared.next_lease + offset, capacity)
        prepared.leases[index] === nothing && return index
    end
    return 0
end

function _release_receipt_lease!(receipt::ExecutionReceipt)
    prepared = receipt.prepared
    index = Int(receipt.lease_index)
    prepared.lease_generations[index] == receipt.lease_generation || return nothing
    prepared.leases[index] === receipt || return nothing
    prepared.leases[index] = nothing
    prepared.outstanding -= 1
    prepared.drained += UInt64(1)
    return nothing
end

Base.@nospecializeinfer Base.@noinline function _validate_dependencies(
        prepared::PreparedPlan, dependencies::Tuple)
    Base.@nospecialize dependencies
    length(dependencies) == prepared.dependency_arity || throw(
        LocalMathValidationError(
            "submission dependency arity differs from preparation";
            stage = :execute, contract = :dependency_arity,
            expected = prepared.dependency_arity,
            actual = length(dependencies)))
    unresolved = Int32(0)
    local_status = prepared.runtime.execution_gate
    for dependency in dependencies
        dependency isa ExecutionReceipt || throw(LocalMathValidationError(
            "dependencies must be ExecutionReceipt receipts";
            stage = :execute, contract = :execution_dependency,
            expected = ExecutionReceipt, actual = typeof(dependency)))
        if _receipt_settled(dependency)
            _receipt_succeeded(dependency) || throw(LocalMathValidationError(
                "a settled failed dependency cannot be submitted";
                stage = :execute, contract = :execution_dependency,
                expected = :success,
                actual = (ordinal = dependency.scope_ordinal,
                    failure = dependency.failure)))
        else
            _lane_same_wait_scope(prepared.lane,
                dependency.prepared.lane) || throw(LocalMathValidationError(
                    "an unresolved dependency belongs to another provider scope";
                    stage = :execute, contract = :execution_dependency_scope,
                    expected = :same_scope_or_settled_success,
                    actual = :unresolved_cross_scope,
                    hint = "wait for the dependency before submitting"))
            dependency.scope_ordinal <= _lane_scope_ordinal(prepared.lane) ||
                throw(LocalMathValidationError(
                    "an unresolved dependency is not earlier in provider order";
                    stage = :execute, contract = :execution_dependency_order,
                    expected = :earlier_ordinal,
                    actual = dependency.scope_ordinal))
            source = dependency.prepared.runtime.execution_gate
            typeof(source) === typeof(local_status) || throw(
                LocalMathValidationError(
                    "same-scope dependency status has an incompatible device ABI";
                    stage = :execute, contract = :execution_dependency_abi,
                    expected = typeof(local_status), actual = typeof(source)))
            unresolved += Int32(1)
        end
    end
    return unresolved
end

"""
    execute!(prepared::PreparedPlan; parameters=(;), dependencies=()) -> ExecutionReceipt

Validate and append one execution to the prepared provider scope. The receipt
owns one logical ordinal, one workspace lease generation, exact dependencies,
and its independently cached settlement result.
"""
function execute!(prepared::PreparedPlan;
        parameters::NamedTuple = (;), dependencies::Tuple = ())
    current_task() === prepared.owner || throw(LocalMathValidationError(
        "PreparedPlan submission is bound to its preparing host task"
    ))
    prepared.poisoned && throw(LocalMathValidationError(
        "PreparedPlan is poisoned; inspect and drain before re-preparing";
        stage = :execute, contract = :provider_poison_state,
        expected = :healthy, actual = prepared.poison_reason,
        hint = "create a fresh preparation after the provider scope is discarded",
    ))
    _validate_lane_current!(prepared.lane)
    canonical = _canonical_submission(prepared.submission_schema, parameters)
    dependency_join_count = _validate_dependencies(prepared, dependencies)
    lease_index = _available_lease(prepared)
    lease_index != 0 ||
        throw(LocalMathValidationError(
            "PreparedPlan submission lease capacity is exhausted";
            stage = :execute, contract = :workspace_lease_capacity,
            workspace_leaf = :leases,
            expected = length(prepared.leases), actual = prepared.outstanding,
            hint = "wait for an outstanding ExecutionReceipt before submitting again",
        ))

    # PreparedPlan is already restricted to the preparing Task. A Julia Task
    # cannot execute two submissions concurrently, so an additional host lock
    # adds no exclusion fact on this admitted path.
    current_task() === prepared.owner || throw(LocalMathValidationError(
        "PreparedPlan host ownership changed during submission"
    ))
    serial = prepared.submitted + UInt64(1)
    prepared.lease_generations[lease_index] += UInt64(1)
    generation = prepared.lease_generations[lease_index]
    ordinal = _next_lane_ordinal!(prepared.lane)
    receipt = ExecutionReceipt(_CONSTRUCTION_TOKEN, prepared, serial, ordinal,
        Int32(lease_index), generation, dependencies, dependency_join_count)
    prepared.leases[lease_index] = receipt
    prepared.next_lease = mod1(lease_index + 1, length(prepared.leases))
    prepared.outstanding += 1
    prepared.submitted = serial
    try
        _execute_lowering!(
            prepared.runtime,
            canonical,
            lease_index,
            dependencies,
        )
    catch error
        # All schema, topology, binding, alias, method-ownership, and
        # lowering-dispatch checks finish before this boundary. A throw after
        # entering an admitted lowering may follow an appended launch, so
        # conservatively poison the complete shared provider scope and retain
        # the lease until that scope is discarded.
        reason = _mandatory_failed_submission_drain!(
            prepared, serial, error
        )
        annotated = _provider_execution_error(reason, :execute)
        if annotated === reason
            reason === error ? rethrow() : throw(reason)
        end
        throw(annotated)
    end
    return receipt
end

function _mandatory_failed_submission_drain!(prepared, serial, error)
    drain_error = try
        _drain_lane_tail!(prepared.lane)
        nothing
    catch failure
        failure
    end
    # A successful mandatory drain establishes that the provider has stopped
    # touching retained storage; it does not turn an admitted provider failure
    # into an ordinary successful settlement. Keep the complete affected lease
    # prefix owned by the poisoned preparation so that failure-before- and
    # failure-after-publication have one conservative lifetime law.
    reason = drain_error === nothing ? error :
        CompositeException(Any[error, drain_error])
    _poison_lane!(prepared.lane, reason)
    prepared.poisoned = true
    prepared.poison_reason = reason
    return reason
end

"""`ispending(receipt)` reports whether a logical execution receipt is unsettled."""
@inline ispending(receipt::ExecutionReceipt) = !_receipt_settled(receipt)

function _receipt_dependency_error(receipt::ExecutionReceipt)
    for dependency in receipt.dependencies
        failure = _observe_receipt_failure(dependency)
        failure === nothing || return LocalMathValidationError(
            "execution dependency failed";
            stage = :wait, contract = :execution_dependency,
            expected = :success,
            actual = (producer_ordinal = dependency.scope_ordinal,
                producer_serial = dependency.serial,
                failure = failure),
            hint = "inspect or wait the producer receipt for its complete failure",
            origin = failure isa LocalMathValidationError ? failure.origin : nothing)
    end
    return nothing
end

function _provider_execution_error(error, lifecycle::Symbol)
    error isa LocalMathValidationError && return error
    return LocalMathValidationError(
        "the KernelAbstractions provider failed while processing submitted work";
        stage = lifecycle,
        contract = :provider_execution,
        expected = :successful_provider_completion,
        actual = error,
        hint = "discard the poisoned provider scope and prepare a fresh plan",
    )
end

function _observe_receipt_failure(receipt::ExecutionReceipt)
    _receipt_settled(receipt) && return receipt.failure
    _lane_poisoned(receipt.prepared.lane) &&
        return _lane_poison_reason(receipt.prepared.lane)
    dependency_error = _receipt_dependency_error(receipt)
    dependency_error === nothing || return dependency_error
    error = _prepared_validation_error_at(
        receipt.prepared, receipt.lease_index)
    error === nothing && return nothing
    return _with_work_source_origin(error,
        _plan_law(receipt.prepared.plan), :wait, error.contract)
end

function _cache_receipt_result!(receipt::ExecutionReceipt)
    _receipt_settled(receipt) && return receipt.failure
    failure = _observe_receipt_failure(receipt)
    receipt.failure = failure
    receipt.state = failure === nothing ? _EXECUTION_RECEIPT_SUCCESS :
        failure isa LocalMathValidationError &&
            failure.contract === :execution_dependency ?
            _EXECUTION_RECEIPT_DEPENDENCY_FAILURE : _EXECUTION_RECEIPT_SEMANTIC_FAILURE
    _release_receipt_lease!(receipt)
    return failure
end

function _synchronize_receipt_scope!(receipt::ExecutionReceipt)
    lane = receipt.prepared.lane
    receipt.scope_ordinal <= _lane_settled_ordinal(lane) && return nothing
    target = _lane_scope_ordinal(lane)
    try
        _wait_lane!(lane)
        _mark_lane_settled!(lane, target)
    catch error
        annotated = _provider_execution_error(error, :wait)
        receipt.state = _EXECUTION_RECEIPT_PROVIDER_FAILURE
        receipt.failure = annotated
        throw(annotated)
    end
    return nothing
end

function _transfer_receipt_statuses!(receipt::ExecutionReceipt, seen::Base.IdSet{Any})
    prepared = receipt.prepared
    if !(prepared in seen)
        _transfer_settled_validation_statuses!(prepared.lane,
            _prepared_validation_statuses(prepared))
        push!(seen, prepared)
    end
    for dependency in receipt.dependencies
        _receipt_settled(dependency) ||
            _transfer_receipt_statuses!(dependency, seen)
    end
    return nothing
end

function Base.wait(receipt::ExecutionReceipt)
    current_task() === receipt.prepared.owner || throw(LocalMathValidationError(
        "this ExecutionReceipt belongs to another owner task";
        stage = :wait, contract = :receipt_owner))
    if !_receipt_settled(receipt)
        _synchronize_receipt_scope!(receipt)
        _transfer_receipt_statuses!(receipt, Base.IdSet{Any}())
        _cache_receipt_result!(receipt)
    end
    receipt.failure === nothing || throw(receipt.failure)
    return receipt
end

"""
    waitall(receipts::ExecutionReceipt...)

Settle several logical receipts, synchronizing each represented provider scope
at most once. Cached failures are reported deterministically in argument order.
Inspection is not required before waiting and waiting remains idempotent.
"""
function waitall(receipts::Tuple{Vararg{ExecutionReceipt}})
    isempty(receipts) && throw(LocalMathValidationError(
        "waitall requires at least one ExecutionReceipt";
        stage = :wait, contract = :receipt_group_arity,
        expected = :nonempty, actual = 0))
    lanes = Any[]
    targets = UInt64[]
    for receipt in receipts
        current_task() === receipt.prepared.owner || throw(
            LocalMathValidationError(
                "grouped ExecutionReceipts belong to another owner task";
                stage = :wait, contract = :receipt_owner))
        lane = receipt.prepared.lane
        index = findfirst(candidate ->
            _lane_same_wait_scope(candidate, lane), lanes)
        if index === nothing
            push!(lanes, lane)
            push!(targets, _lane_scope_ordinal(lane))
        else
            targets[index] = max(targets[index], _lane_scope_ordinal(lane))
        end
    end
    provider_failures = IdDict{Any,Any}()
    for (lane, target) in zip(lanes, targets)
        target <= _lane_settled_ordinal(lane) && continue
        try
            _wait_lane!(lane)
            _mark_lane_settled!(lane, target)
        catch error
            provider_failures[lane.scope] =
                _provider_execution_error(error, :wait)
        end
    end
    seen = Base.IdSet{Any}()
    for receipt in receipts
        haskey(provider_failures, receipt.prepared.lane.scope) && continue
        _receipt_settled(receipt) || _transfer_receipt_statuses!(receipt, seen)
    end
    first_failure = nothing
    for receipt in receipts
        if !_receipt_settled(receipt)
            provider_failure = get(provider_failures,
                receipt.prepared.lane.scope, nothing)
            if provider_failure === nothing
                _cache_receipt_result!(receipt)
            else
                receipt.state = _EXECUTION_RECEIPT_PROVIDER_FAILURE
                receipt.failure = provider_failure
            end
        end
        first_failure === nothing && receipt.failure !== nothing &&
            (first_failure = receipt.failure)
    end
    first_failure === nothing || throw(first_failure)
    return receipts
end

waitall(receipt::ExecutionReceipt, receipts::ExecutionReceipt...) =
    waitall((receipt, receipts...))
