function _inspect_output(value)
    return value
end

function _inspect_combination(law::_CombinationLaw{M}) where {M}
    return (
        mode = M,
        operation = law.operation,
        identity = law.identity,
        semantic_order = M === :deterministic ?
                         :canonical_item_local_slot : :backend_qualified,
    )
end

function _inspect_output(
        output::_IndependentOutput{T, K, R, C}
    ) where {T, K, R, C}
    return (
        family = :independent,
        route = output.route,
        value_type = T,
        maximum_emissions = K,
        coverage = C,
        false_lane = :no_emission,
    )
end

function _inspect_output(
        output::_CombinedOutput{T, K}
    ) where {T, K}
    return (
        family = :combined,
        route = output.route,
        value_type = T,
        maximum_emissions = K,
        combine = invoke(
            _inspect_combination,
            Tuple{_CombinationLaw},
            output.combine,
        ),
        empty_destination = output.combine.identity,
        false_lane = :no_emission,
    )
end


function _inspect_output(
        output::_GenericResolvedOutput{T, K}
    ) where {T, K}
    return (
        family = :resolved,
        route = output.route,
        value_type = T,
        maximum_emissions = K,
        empty = output.empty,
        rank = output.rank,
        tie_break = output.tie_break,
        false_lane = :no_candidate,
    )
end

"""
    inspect(value)

Return non-synchronizing facts for a `LocalWork`, `WorkPlan`, `PreparedWork`,
or `WorkEvent`, including topology, lowering, storage, workspace, provider,
determinism, lease, and failure information available at that lifecycle stage.
"""
function inspect(work::LocalWork)
    if work.operation isa _SequenceOperation
        return (
            lifecycle = :LocalWork,
            family = :ordered_sequence,
            stages = map(
                stage -> invoke(inspect, Tuple{LocalWork}, stage),
                work.operation.works,
            ),
        )
    end
    inspected_outputs = map(values(work.outputs)) do output
        signature = Tuple{typeof(output)}
        method = which(_inspect_output, signature)
        method.module === (@__MODULE__) || throw(LocalWorkValidationError(
            "the output inspection implementation is not package-owned"
        ))
        invoke(_inspect_output, signature, output)
    end
    return (
        lifecycle = :LocalWork,
        family = hasproperty(work.operation, :family) ?
                 work.operation.family : :unrecognized,
        items = work.items,
        reads = work.reads,
        outputs = NamedTuple{keys(work.outputs)}(inspected_outputs),
        active = work.active,
        operation = work.operation,
    )
end

inspect(workplan::WorkPlan) = (
    lifecycle = :WorkPlan,
    topology = (
        identity = workplan.evidence.topology_identity,
        epoch = workplan.evidence.topology_epoch,
        fingerprint = workplan.evidence.topology_fingerprint,
    ),
    backend = workplan.evidence.backend_type,
    family = workplan.evidence.family,
    lowering = workplan.evidence.lowering_identity,
    launches = workplan.evidence.launch_count,
    phases = workplan.evidence.phases,
    workspace = workplan.evidence.workspace,
    topology_transfer_bytes = workplan.evidence.topology_transfer_bytes,
    capability = workplan.evidence.capability,
    determinism = workplan.evidence.determinism,
    ports = hasproperty(workplan.evidence, :ports) ?
            workplan.evidence.ports : nothing,
    stages = hasproperty(workplan.evidence, :stages) ?
             workplan.evidence.stages : nothing,
)

_static_binding_facts(storage) = NamedTuple{keys(storage)}(map(
    values(storage)
) do value
    (
        identity = objectid(value),
        element_type = eltype(value),
        dimensions = ndims(value),
        size = size(value),
        strides = strides(value),
        backend = typeof(KernelAbstractions.get_backend(value)),
        device = invoke(_array_device_identity, Tuple{Any}, value),
    )
end)

function _submission_slot_fact(slot::_ValueSlot{T}) where {T}
    return (kind = :value, type = T, bounds = slot.bounds)
end

function _submission_slot_fact(slot::_StorageSlot{T, N}) where {T, N}
    return (
        kind = :storage,
        element_type = T,
        dimensions = N,
        size = slot.size,
        strides = slot.strides,
        access = slot.access,
        array_type = slot.array_type,
        backend = slot.backend_type,
        device = slot.device_identity,
    )
end

_submission_slot_facts(schema) = NamedTuple{keys(schema)}(
    map(values(schema)) do slot
        signature = slot isa _ValueSlot ? Tuple{_ValueSlot} :
                    Tuple{_StorageSlot}
        invoke(_submission_slot_fact, signature, slot)
    end
)

function _inspect_provider_lane(lane::_AbstractProviderLane)
    fact(callback, purpose) = invoke(
        _centrally_admitted_provider_call,
        Tuple{Function, Tuple, Symbol},
        callback,
        (lane,),
        purpose,
    )
    return (
        provider = fact(_lane_provider, :inspection),
        device = fact(_lane_device, :inspection),
        lane = fact(_lane_identity, :inspection),
        event_scope = fact(_lane_wait_scope, :inspection),
        event_transfer = fact(_lane_transfer_law, :inspection),
        event_cumulative = fact(_lane_cumulative, :inspection),
        event_selective = fact(_lane_selective, :inspection),
        wait_count = fact(_lane_wait_count, :inspection),
        poisoned = fact(_lane_poisoned, :inspection),
        poison_reason = fact(_lane_poison_reason, :inspection),
        asynchronous_error_observation =
            fact(_lane_error_observation, :inspection),
    )
end

function inspect(prepared::PreparedWork)
    planned = invoke(inspect, Tuple{WorkPlan}, prepared.workplan)
    provider_signature = Tuple{_AbstractProviderLane}
    provider_method = which(_inspect_provider_lane, provider_signature)
    provider_method.module === (@__MODULE__) ||
        throw(LocalWorkValidationError(
            "the provider inspection implementation is not package-owned"
        ))
    provider = invoke(
        _inspect_provider_lane,
        provider_signature,
        prepared.lane,
    )
    lowering_signature = Tuple{Function, Tuple, Symbol}
    lowering_method = which(
        _centrally_admitted_lowering_call, lowering_signature
    )
    lowering_method.module === (@__MODULE__) ||
        throw(LocalWorkValidationError(
            "the lowering inspection boundary is not package-owned"
        ))
    return merge(planned, (
        lifecycle = :PreparedWork,
        bindings = prepared.binding_names,
        binding_access = prepared.binding_access,
        static_bindings = keys(prepared.storage),
        static_binding_facts = invoke(
            _static_binding_facts, Tuple{Any}, prepared.storage
        ),
        submission_slots = keys(prepared.submission_schema),
        submission_slot_facts = invoke(
            _submission_slot_facts,
            Tuple{Any},
            prepared.submission_schema
        ),
        alias_rule = :distinct_write_alias_rejected,
        provider = provider.provider,
        device = provider.device,
        lane = provider.lane,
        lowering_detail = invoke(
            _centrally_admitted_lowering_call,
            lowering_signature,
            _lowering_inspection,
            (
                prepared.runtime,
                prepared.workplan.lowering,
                prepared.workplan.work,
                prepared.workspace,
            ),
            :inspection,
        ),
        record_capacity = length(prepared.leases),
        lease_identity = objectid(prepared.leases),
        submitted = prepared.submitted,
        drained = prepared.drained,
        reentrancy = :ordered_reentrant_one_lane,
        event_scope = provider.event_scope,
        event_transfer = provider.event_transfer,
        event_cumulative = provider.event_cumulative,
        event_selective = provider.event_selective,
        wait_count = provider.wait_count,
        asynchronous_error_observation =
            provider.asynchronous_error_observation,
        allocation_class = :prebound_algorithmic_workspace,
        poisoned = prepared.poisoned || provider.poisoned,
        poison_reason = prepared.poison_reason === nothing ?
                        provider.poison_reason : prepared.poison_reason,
    ))
end

inspect(event::WorkEvent) = merge(invoke(
    inspect, Tuple{PreparedWork}, event.prepared
), (
    lifecycle = :WorkEvent,
    event_serial = event.serial,
    receipt_scope = :lane_tail,
))

function Base.show(io::IO, value::LocalWork)
    facts = invoke(inspect, Tuple{LocalWork}, value)
    print(io, "LocalWork(family=", facts.family, ")")
end

function Base.show(io::IO, value::WorkPlan)
    facts = invoke(inspect, Tuple{WorkPlan}, value)
    print(io, "WorkPlan(lowering=", facts.lowering,
          ", launches=", facts.launches, ")")
end

function Base.show(io::IO, value::PreparedWork)
    facts = invoke(inspect, Tuple{PreparedWork}, value)
    print(io, "PreparedWork(provider=", facts.provider,
          ", submitted=", facts.submitted,
          ", drained=", facts.drained,
          ", poisoned=", facts.poisoned, ")")
end

function Base.show(io::IO, value::WorkEvent)
    facts = invoke(inspect, Tuple{WorkEvent}, value)
    print(io, "WorkEvent(serial=", facts.event_serial,
          ", scope=", facts.receipt_scope, ")")
end
