const CellIdentity = CorePotts.CellIdentity

function _host_relationship_name(value)
    value isa Symbol && return value
    value isa RelationshipState && return Symbol(statement_id(value))
    name = _try_symbolic_name(value)
    name === nothing && throw(ArgumentError(
        "a host relationship mutation must name a compiled RelationshipState"
    ))
    return name
end

function _host_relationship_slot(plan::_PottsExecutionPlan, value)
    name = _host_relationship_name(value)
    reports = plan.reports.relationship_states
    exact = findall(entry -> entry.name === name, reports)
    matches = isempty(exact) ?
              findall(entry -> entry.local_name === name, reports) : exact
    isempty(matches) && throw(ArgumentError(
        "unknown compiled relationship $(repr(name))"
    ))
    length(matches) == 1 || throw(ArgumentError(
        "relationship name $(repr(name)) is ambiguous; use its qualified compiled name"
    ))
    report = reports[only(matches)]
    policies = filter(
        policy -> policy.identity == report.identity,
        plan.relationship_endpoint_policies,
    )
    length(policies) == 1 || error(
        "compiled relationship report and endpoint policy are misaligned"
    )
    return Int(only(policies).slot), report
end

function _host_cell_identity(snapshot, value)
    identity = if value isa CellIdentity
        value
    elseif value isa Integer
        slot = Int(value)
        1 <= slot <= length(snapshot.cell_kinds) || throw(ArgumentError(
            "cell slot $slot is outside the compiled cell table"
        ))
        kind = @inbounds snapshot.cell_kinds[slot]
        generation = @inbounds snapshot.cell_generations[slot]
        !iszero(kind) && !iszero(generation) || throw(ArgumentError(
            "cell slot $slot is inactive at this settled boundary"
        ))
        CellIdentity(slot, generation, kind)
    else
        throw(ArgumentError(
            "relationship endpoints must be active cell slots or CellIdentity values"
        ))
    end
    slot = Int(identity.slot)
    1 <= slot <= length(snapshot.cell_kinds) || throw(ArgumentError(
        "cell identity slot $slot is outside the compiled cell table"
    ))
    actual_kind = @inbounds snapshot.cell_kinds[slot]
    actual_generation = @inbounds snapshot.cell_generations[slot]
    actual_kind == identity.kind && actual_generation == identity.generation ||
        throw(ArgumentError(
            "cell identity for slot $slot is stale at this settled boundary"
        ))
    return identity
end

function _host_relationship_endpoints(snapshot, value)
    endpoints = if value isa SymmetricPair
        (value.first, value.second)
    elseif value isa Pair
        (first(value), last(value))
    elseif value isa Tuple && length(value) == 2
        value
    else
        throw(ArgumentError(
            "Remove and Retune require an endpoint pair such as `a ↔ b`"
        ))
    end
    return (
        _host_cell_identity(snapshot, endpoints[1]),
        _host_cell_identity(snapshot, endpoints[2]),
    )
end

function _host_relationship_priority(value)
    value isa Integer || throw(ArgumentError(
        "relationship mutation priority must be an integer"
    ))
    typemin(Int32) <= value <= typemax(Int32) || throw(ArgumentError(
        "relationship mutation priority must fit Int32"
    ))
    return Int32(value)
end

function _host_relationship_payload(report, payload, ::Type{T}) where {
        T <: AbstractFloat,
    }
    payload isa NamedTuple || throw(ArgumentError(
        "relationship mutation payloads must be named tuples"
    ))
    expected = keys(report.payload_units)
    supplied = keys(payload)
    length(expected) == length(supplied) &&
        all(name -> name in supplied, expected) || throw(ArgumentError(
            "relationship payload for `$(report.name)` must contain exactly " *
            join(string.(expected), ", ")
        ))
    return ntuple(length(expected)) do index
        name = expected[index]
        _convert_relationship_payload_value(
            report, name, getproperty(payload, name), T
        )
    end
end

function _host_relationship_policy(plan, slot::Integer)
    matches = filter(
        policy -> Int(policy.slot) == slot,
        plan.relationship_endpoint_policies,
    )
    length(matches) == 1 || error(
        "compiled relationship report and endpoint policy are misaligned"
    )
    return only(matches)
end

function _validate_host_relationship_kinds!(report, policy, a, b)
    policy.direction === :undirected || throw(ArgumentError(
        "host relationship mutation for `$(report.name)` requires qualified undirected semantics"
    ))
    _undirected_endpoint_kinds_match(
        a.kind, b.kind, policy.kind_a, policy.kind_b
    ) || throw(ArgumentError(
        "relationship `$(report.name)` endpoint kinds do not satisfy its Undirected contract"
    ))
    return nothing
end

function _host_relationship_edge(state, report, a, b)
    edge = CorePotts.BackendSPI.relationship_edge_index(
        state, a.slot, b.slot
    )
    edge === nothing && throw(ArgumentError(
        "relationship `$(report.name)` has no active edge for the supplied endpoints"
    ))
    return Int(edge)
end

function _host_relationship_request(
        integrator::PottsIntegrator,
        snapshot,
        effect::Create,
        identity::Integer,
    )
    slot, report = _host_relationship_slot(
        integrator.plan, effect.relationship
    )
    a = _host_cell_identity(snapshot, effect.endpoint_a)
    b = _host_cell_identity(snapshot, effect.endpoint_b)
    policy = _host_relationship_policy(integrator.plan, slot)
    _validate_host_relationship_kinds!(report, policy, a, b)
    payload = _host_relationship_payload(
        report, effect.payload, integrator.scalar_type
    )
    request = CorePotts.BackendSPI.CreateRelationshipRequest(
        a.slot,
        b.slot,
        payload;
        generation_a = a.generation,
        generation_b = b.generation,
        priority = _host_relationship_priority(effect.priority),
        identity,
    )
    return slot, request
end

function _host_relationship_request(
        integrator::PottsIntegrator,
        snapshot,
        effect::Remove,
        identity::Integer,
    )
    slot, report = _host_relationship_slot(
        integrator.plan, effect.relationship
    )
    a, b = _host_relationship_endpoints(snapshot, effect.edge)
    edge = _host_relationship_edge(snapshot.relationships[slot], report, a, b)
    request = CorePotts.BackendSPI.RemoveRelationshipRequest(
        edge;
        priority = _host_relationship_priority(effect.priority),
        identity,
    )
    return slot, request
end

function _host_relationship_request(
        integrator::PottsIntegrator,
        snapshot,
        effect::Retune,
        identity::Integer,
    )
    slot, report = _host_relationship_slot(
        integrator.plan, effect.relationship
    )
    a, b = _host_relationship_endpoints(snapshot, effect.edge)
    edge = _host_relationship_edge(snapshot.relationships[slot], report, a, b)
    payload = _host_relationship_payload(
        report, effect.payload, integrator.scalar_type
    )
    request = CorePotts.BackendSPI.RetuneRelationshipRequest(
        edge,
        payload;
        priority = _host_relationship_priority(effect.priority),
        identity,
    )
    return slot, request
end

function _host_relationship_request(
        ::PottsIntegrator, snapshot, effect, identity::Integer
    )
    throw(ArgumentError(
        "host relationship transactions admit only Create, Remove, and Retune effects; received $(typeof(effect))"
    ))
end

"""
    relationship_transaction!(integrator, effects...)

Atomically apply `Create`, `Remove`, and `Retune` relationship effects at one
settled MCS boundary. Integer endpoints are stamped with their current cell
generation. Pass `CellIdentity` endpoints to require an exact generation.
`Remove` and `Retune` identify an edge by an unordered endpoint pair, normally
written `a ↔ b`; raw reusable edge slots are intentionally not accepted.

All effects are normalized against one logical snapshot, validated together by
CorePotts, and published by replacing the complete runtime only after backend
adaptation succeeds. Failure leaves the pre-transaction runtime unchanged.
"""
function relationship_transaction!(
        integrator::PottsIntegrator, effects...
    )
    isempty(effects) && throw(ArgumentError(
        "relationship_transaction! requires at least one effect"
    ))
    integrator.terminated && throw(ArgumentError(
        "cannot mutate relationships on a terminated PottsIntegrator"
    ))
    integrator.retcode == SciMLBase.ReturnCode.Default || throw(ArgumentError(
        "cannot mutate relationships after a terminal solver result"
    ))
    _request_integrator_settlement!(
        integrator, CorePotts.BackendSPI.IndexMutationSettlement
    )
    CorePotts.program_failed(integrator.runtime) && throw(ArgumentError(
        "cannot mutate relationships on a failed Potts runtime"
    ))
    snapshot = CorePotts.program_snapshot(integrator.runtime)
    groups = Dict{
        Int, Vector{CorePotts.BackendSPI.ProgramRelationshipRequest},
    }()
    for (identity, effect) in enumerate(effects)
        slot, request = _host_relationship_request(
            integrator, snapshot, effect, identity
        )
        push!(get!(
            () -> CorePotts.BackendSPI.ProgramRelationshipRequest[],
            groups,
            slot,
        ), request)
    end
    transactions = Pair{Int, Any}[
        slot => groups[slot] for slot in sort!(collect(keys(groups)))
    ]
    host_candidate = CorePotts.BackendSPI.host_relationship_transaction(
        integrator.runtime, transactions
    )
    candidate = _adapt_runtime_backend(
        integrator.plan.core_program.backend, host_candidate
    )
    candidate isa typeof(integrator.runtime) || error(
        "relationship transaction changed the concrete runtime profile"
    )
    integrator.runtime = candidate
    integrator.t = candidate.mcs
    integrator.u = _current_saved_state(integrator)
    return integrator
end
