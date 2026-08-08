const _RELATIONSHIP_CREATE_APPLY = UInt8(0x01)
const _RELATIONSHIP_CREATE_IDEMPOTENT = UInt8(0x02)
const _RELATIONSHIP_CREATE_SELF_EDGE = UInt8(0x03)
const _RELATIONSHIP_CREATE_INACTIVE_ENDPOINT = UInt8(0x04)
const _RELATIONSHIP_CREATE_STALE_GENERATION = UInt8(0x05)
const _RELATIONSHIP_CREATE_CONTRADICTORY = UInt8(0x06)
const _RELATIONSHIP_CREATE_MAXIMUM_DEGREE = UInt8(0x07)
const _RELATIONSHIP_CREATE_CAPACITY = UInt8(0x08)

@inline function _relationship_endpoint_admission(
        endpoint::Int32,
        generation::UInt32,
        endpoint_status,
        endpoint_generations,
    )
    1 <= endpoint <= length(endpoint_status) ||
        return _RELATIONSHIP_CREATE_INACTIVE_ENDPOINT
    @inbounds !iszero(endpoint_status[endpoint]) ||
        return _RELATIONSHIP_CREATE_INACTIVE_ENDPOINT
    @inbounds generation == endpoint_generations[endpoint] ||
        return _RELATIONSHIP_CREATE_STALE_GENERATION
    return _RELATIONSHIP_CREATE_APPLY
end

function _relationship_create_admission(
        state::ProgramRelationshipState,
        endpoint_status,
        endpoint_generations,
        schema::RelationshipStoreSchema,
        request::CreateRelationshipRequest,
        available_edge::Int32 = Int32(0),
    )
    _validate_relationship_payload(state, request.payload)
    request.endpoint_a != request.endpoint_b ||
        return _RELATIONSHIP_CREATE_SELF_EDGE
    a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
    generation_a, generation_b = request.endpoint_a == a ?
        (request.generation_a, request.generation_b) :
        (request.generation_b, request.generation_a)
    admission = _relationship_endpoint_admission(
        a, generation_a, endpoint_status, endpoint_generations
    )
    admission == _RELATIONSHIP_CREATE_APPLY || return admission
    admission = _relationship_endpoint_admission(
        b, generation_b, endpoint_status, endpoint_generations
    )
    admission == _RELATIONSHIP_CREATE_APPLY || return admission
    existing = _relationship_edge(state, a, b)
    if existing !== nothing
        edge = Int(existing)
        existing_generation_a = @inbounds state.generation_a[edge]
        existing_generation_b = @inbounds state.generation_b[edge]
        return existing_generation_a == generation_a &&
               existing_generation_b == generation_b ?
               _RELATIONSHIP_CREATE_IDEMPOTENT :
               _RELATIONSHIP_CREATE_CONTRADICTORY
    end
    _relationship_degree(state, a) < schema.maximum_degree ||
        return _RELATIONSHIP_CREATE_MAXIMUM_DEGREE
    _relationship_degree(state, b) < schema.maximum_degree ||
        return _RELATIONSHIP_CREATE_MAXIMUM_DEGREE
    has_capacity = available_edge > 0 ||
                   (available_edge == 0 && findfirst(!, state.active) !== nothing)
    !has_capacity &&
        return _RELATIONSHIP_CREATE_CAPACITY
    return _RELATIONSHIP_CREATE_APPLY
end

function _throw_relationship_create_admission(
        admission::UInt8, request::CreateRelationshipRequest
    )
    admission == _RELATIONSHIP_CREATE_SELF_EDGE &&
        throw(ArgumentError("a relationship cannot be a self-edge"))
    admission == _RELATIONSHIP_CREATE_INACTIVE_ENDPOINT && throw(
        ArgumentError("relationship request references an inactive endpoint")
    )
    admission == _RELATIONSHIP_CREATE_STALE_GENERATION &&
        throw(ArgumentError("relationship endpoint generation is stale"))
    admission == _RELATIONSHIP_CREATE_CONTRADICTORY && throw(ArgumentError(
        "contradictory relationship creations target the same endpoints"
    ))
    admission == _RELATIONSHIP_CREATE_MAXIMUM_DEGREE &&
        throw(ArgumentError("relationship maximum degree exceeded"))
    admission == _RELATIONSHIP_CREATE_CAPACITY &&
        throw(ArgumentError("relationship capacity exceeded"))
    error("unknown relationship-create admission code $admission")
end

function validate_relationship_request(
        state::ProgramRelationshipState,
        endpoint_status,
        endpoint_generations,
        schema::RelationshipStoreSchema,
        request::CreateRelationshipRequest,
    )
    admission = _relationship_create_admission(
        state,
        endpoint_status,
        endpoint_generations,
        schema,
        request,
    )
    admission == _RELATIONSHIP_CREATE_APPLY && return true
    admission == _RELATIONSHIP_CREATE_IDEMPOTENT && return false
    _throw_relationship_create_admission(admission, request)
end

function validate_relationship_request(
        state::ProgramRelationshipState,
        endpoint_status,
        endpoint_generations,
        ::RelationshipStoreSchema,
        request::Union{RemoveRelationshipRequest, RetuneRelationshipRequest},
    )
    edge = request.edge
    1 <= edge <= length(state.active) && @inbounds(state.active[edge]) ||
        throw(ArgumentError(
            "relationship request references an inactive edge"
        ))
    if request isa RetuneRelationshipRequest
        _validate_relationship_payload(state, request.payload)
    end
    return true
end

function apply_validated_relationship_request!(
        state,
        request::CreateRelationshipRequest,
        slot::Integer = something(findfirst(!, state.active)),
    )
    a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
    generation_a, generation_b = request.endpoint_a == a ?
        (request.generation_a, request.generation_b) :
        (request.generation_b, request.generation_a)
    1 <= slot <= length(state.active) && !(@inbounds state.active[slot]) ||
        throw(ArgumentError("relationship create slot is not available"))
    @inbounds begin
        state.active[slot] = true
        state.endpoint_a[slot] = a
        state.endpoint_b[slot] = b
        state.generation_a[slot] = generation_a
        state.generation_b[slot] = generation_b
    end
    for payload_slot in eachindex(state.payload)
        @inbounds state.payload[payload_slot][slot] =
            request.payload[payload_slot]
    end
    _insert_incident_edge!(state, a, Int32(slot))
    _insert_incident_edge!(state, b, Int32(slot))
    return state
end

function apply_validated_relationship_request!(
        state,
        request::RemoveRelationshipRequest,
    )
    edge = request.edge
    a = @inbounds state.endpoint_a[edge]
    b = @inbounds state.endpoint_b[edge]
    _remove_incident_edge!(state, a, edge)
    _remove_incident_edge!(state, b, edge)
    @inbounds begin
        state.active[edge] = false
        state.endpoint_a[edge] = 0
        state.endpoint_b[edge] = 0
        state.generation_a[edge] = 0
        state.generation_b[edge] = 0
    end
    for values in state.payload
        @inbounds values[edge] = zero(eltype(values))
    end
    return state
end

function apply_validated_relationship_request!(
        state,
        request::RetuneRelationshipRequest,
    )
    for payload_slot in eachindex(state.payload)
        @inbounds state.payload[payload_slot][request.edge] =
            request.payload[payload_slot]
    end
    return state
end

@inline function _relationship_request_greater(left, right)
    return _request_sort_key(left) > _request_sort_key(right)
end

@inline function _relationship_sift_down!(requests, root::Int, count::Int)
    while true
        child = 2root
        child > count && return requests
        if child < count && _relationship_request_greater(
                @inbounds(requests[child + 1]), @inbounds(requests[child])
            )
            child += 1
        end
        _relationship_request_greater(
            @inbounds(requests[child]), @inbounds(requests[root])
        ) || return requests
        @inbounds requests[root], requests[child] = requests[child], requests[root]
        root = child
    end
end

"""Allocation-free `O(Q log Q)` canonical ordering of the initialized prefix."""
@inline function _sort_relationship_requests!(
        buffer::RelationshipTransactionBuffer,
    )
    count = Int(buffer.count)
    for root in fld(count, 2):-1:1
        _relationship_sift_down!(buffer.requests, root, count)
    end
    for last_index in count:-1:2
        @inbounds buffer.requests[1], buffer.requests[last_index] =
            buffer.requests[last_index], buffer.requests[1]
        _relationship_sift_down!(buffer.requests, 1, last_index - 1)
    end
    return buffer
end

@inline _request_edge(::CreateRelationshipRequest) = Int32(0)
@inline _request_edge(request::Union{
    RemoveRelationshipRequest, RetuneRelationshipRequest,
}) = request.edge

function prepare_relationship_transaction!(
        buffer::RelationshipTransactionBuffer,
        endpoint_status,
        endpoint_generations,
        schema::RelationshipStoreSchema,
    )
    length(endpoint_status) == length(endpoint_generations) || throw(
        ArgumentError("relationship endpoint tables have different lengths")
    )
    staged = buffer.staged
    length(staged.payload) == length(schema.payload_defaults) || throw(
        ArgumentError("relationship state payload does not match its schema")
    )
    _sort_relationship_requests!(buffer)
    next_available_edge = Int32(0)
    for index in 1:Int(buffer.count)
        request = @inbounds buffer.requests[index]
        edge = _request_edge(request)
        if edge > 0
            1 <= edge <= length(staged.active) || begin
                validate_relationship_request(
                    staged,
                    endpoint_status,
                    endpoint_generations,
                    schema,
                    request,
                )
                error("unreachable invalid relationship edge")
            end
            prior_index = @inbounds buffer.first_request_for_edge[edge]
            if prior_index > 0
                prior = @inbounds buffer.requests[prior_index]
                _relationship_request_equivalent(prior, request) && continue
                throw(ArgumentError(
                    "conflicting relationship requests for edge $edge"
                ))
            end
            @inbounds buffer.first_request_for_edge[edge] = Int32(index)
        end
        if request isa CreateRelationshipRequest
            if next_available_edge == 0
                available = findfirst(!, staged.active)
                next_available_edge = available === nothing ? Int32(-1) :
                                      Int32(available)
            end
            admission = _relationship_create_admission(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
                next_available_edge,
            )
            admission == _RELATIONSHIP_CREATE_IDEMPOTENT && continue
            if admission != _RELATIONSHIP_CREATE_APPLY
                if request.on_failure == RelationshipFailureFilter
                    buffer.filtered += Int32(1)
                    buffer.filtered_total += UInt64(1)
                    continue
                end
                _throw_relationship_create_admission(admission, request)
            end
            apply_validated_relationship_request!(
                staged, request, next_available_edge
            )
            available = findnext(!, staged.active, Int(next_available_edge) + 1)
            next_available_edge = available === nothing ? Int32(-1) :
                                  Int32(available)
        else
            validate_relationship_request(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
            )
            apply_validated_relationship_request!(staged, request)
        end
    end
    return buffer
end

@inline function publish_relationship_transaction!(
        state::ProgramRelationshipState,
        buffer::RelationshipTransactionBuffer,
    )
    copyto!(state, buffer.staged)
    return state
end

@inline _reset_relationship_state!(state, buffer) =
    (reset_relationship_transaction!(buffer, state); nothing)

@inline function _reset_relationship_buffer!(
        buffer, states, relationship_slot
    )
    _call_relationship_slot(
        _reset_relationship_state!,
        states,
        relationship_slot,
        (buffer,),
    )
    return nothing
end

@inline function _reset_relationship_transactions!(
        buffers::RelationshipStorage,
        states::RelationshipStorage,
    )
    length(buffers) == length(states) || throw(ArgumentError(
        "relationship transaction and state storage are misaligned"
    ))
    for relationship_slot in eachindex(buffers)
        _call_relationship_slot(
            _reset_relationship_buffer!,
            buffers,
            Int32(relationship_slot),
            (states, Int32(relationship_slot)),
        )
    end
    return nothing
end

@inline function _prepare_relationship_schema!(
        schema,
        buffer,
        endpoint_status,
        endpoint_generations,
    )
    prepare_relationship_transaction!(
        buffer,
        endpoint_status,
        endpoint_generations,
        schema,
    )
    return nothing
end

@inline function _prepare_relationship_buffer!(
        buffer,
        endpoint_status,
        endpoint_generations,
        schemas,
        relationship_slot,
    )
    _call_relationship_slot(
        _prepare_relationship_schema!,
        schemas,
        relationship_slot,
        (buffer, endpoint_status, endpoint_generations),
    )
    return nothing
end

@inline function _prepare_relationship_transactions!(
        buffers::RelationshipStorage,
        endpoint_status,
        endpoint_generations,
        schemas::RelationshipStorage,
    )
    length(buffers) == length(schemas) || throw(ArgumentError(
        "relationship transaction and schema storage are misaligned"
    ))
    for relationship_slot in eachindex(buffers)
        _call_relationship_slot(
            _prepare_relationship_buffer!,
            buffers,
            Int32(relationship_slot),
            (
                endpoint_status,
                endpoint_generations,
                schemas,
                Int32(relationship_slot),
            ),
        )
    end
    return nothing
end

@inline _publish_relationship_buffer!(buffer, state) =
    (publish_relationship_transaction!(state, buffer); nothing)

@inline function _publish_relationship_state!(
        state, buffers, relationship_slot
    )
    _call_relationship_slot(
        _publish_relationship_buffer!,
        buffers,
        relationship_slot,
        (state,),
    )
    return nothing
end

@inline function _publish_relationship_transactions!(
        states::RelationshipStorage,
        buffers::RelationshipStorage,
    )
    length(states) == length(buffers) || throw(ArgumentError(
        "relationship state and transaction storage are misaligned"
    ))
    for relationship_slot in eachindex(states)
        _call_relationship_slot(
            _publish_relationship_state!,
            states,
            Int32(relationship_slot),
            (buffers, Int32(relationship_slot)),
        )
    end
    return nothing
end

function apply_relationship_requests!(
        state::ProgramRelationshipState,
        endpoint_status,
        endpoint_generations,
        schema::RelationshipStoreSchema,
        requests,
    )
    request_values = collect(requests)
    buffer = RelationshipTransactionBuffer(state, length(request_values))
    reset_relationship_transaction!(buffer, state)
    for request in request_values
        emit_relationship_request!(buffer, request)
    end
    prepare_relationship_transaction!(
        buffer,
        endpoint_status,
        endpoint_generations,
        schema,
    )
    return publish_relationship_transaction!(state, buffer)
end

"""
Return the active edge slot for an unordered endpoint pair, or `nothing`.

This is a read-only backend boundary used to turn a generation-checked host
endpoint pair into the compact edge slot consumed by the transactional request
protocol. Callers must still validate endpoint identities against the same
settled snapshot before constructing a remove or retune request.
"""
function relationship_edge_index(
        state::ProgramRelationshipState,
        endpoint_a::Integer,
        endpoint_b::Integer,
    )
    typemin(Int32) <= endpoint_a <= typemax(Int32) || return nothing
    typemin(Int32) <= endpoint_b <= typemax(Int32) || return nothing
    return _relationship_edge(
        state, Int32(endpoint_a), Int32(endpoint_b)
    )
end
