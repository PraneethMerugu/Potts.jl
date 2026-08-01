# Bounded relationship storage and the sole canonical transaction path.

struct ProgramRelationshipState{P <: Tuple}
    active::BitVector
    endpoint_a::Vector{Int32}
    endpoint_b::Vector{Int32}
    generation_a::Vector{UInt32}
    generation_b::Vector{UInt32}
    payload::P
    degree::Vector{Int16}
    incident_edges::Matrix{Int32}
end

function ProgramRelationshipState(::Type{T}, capacity::Integer) where {
        T <: AbstractFloat,
    }
    return ProgramRelationshipState(T, capacity, capacity, capacity, 0)
end

function ProgramRelationshipState(
        ::Type{T},
        capacity::Integer,
        endpoint_capacity::Integer,
        maximum_degree::Integer,
        payload_count::Integer = 0,
    ) where {T <: AbstractFloat}
    capacity > 0 || throw(ArgumentError(
        "relationship capacity must be positive"
    ))
    capacity <= typemax(Int32) || throw(ArgumentError(
        "relationship capacity exceeds the V1 Int32 storage bound"
    ))
    endpoint_capacity >= 0 || throw(ArgumentError(
        "relationship endpoint capacity cannot be negative"
    ))
    endpoint_capacity <= typemax(Int32) || throw(ArgumentError(
        "relationship endpoint capacity exceeds the V1 Int32 identity bound"
    ))
    maximum_degree > 0 || throw(ArgumentError(
        "relationship maximum degree must be positive"
    ))
    maximum_degree <= typemax(Int16) || throw(ArgumentError(
        "relationship maximum degree exceeds the V1 Int16 storage bound"
    ))
    payload_count >= 0 || throw(ArgumentError(
        "relationship payload count cannot be negative"
    ))
    return ProgramRelationshipState(
        falses(capacity),
        zeros(Int32, capacity),
        zeros(Int32, capacity),
        zeros(UInt32, capacity),
        zeros(UInt32, capacity),
        ntuple(_ -> zeros(T, capacity), payload_count),
        zeros(Int16, endpoint_capacity),
        zeros(Int32, maximum_degree, endpoint_capacity),
    )
end

function Base.copy(state::ProgramRelationshipState)
    return ProgramRelationshipState(
        copy(state.active),
        copy(state.endpoint_a),
        copy(state.endpoint_b),
        copy(state.generation_a),
        copy(state.generation_b),
        map(copy, state.payload),
        copy(state.degree),
        copy(state.incident_edges),
    )
end

function Base.copyto!(
        destination::ProgramRelationshipState,
        source::ProgramRelationshipState,
    )
    length(destination.payload) == length(source.payload) || throw(
        ArgumentError("relationship states have incompatible payload schemas")
    )
    copyto!(destination.active, source.active)
    copyto!(destination.endpoint_a, source.endpoint_a)
    copyto!(destination.endpoint_b, source.endpoint_b)
    copyto!(destination.generation_a, source.generation_a)
    copyto!(destination.generation_b, source.generation_b)
    for slot in eachindex(destination.payload)
        copyto!(destination.payload[slot], source.payload[slot])
    end
    copyto!(destination.degree, source.degree)
    copyto!(destination.incident_edges, source.incident_edges)
    return destination
end

abstract type ProgramRelationshipRequest end

struct CreateRelationshipRequest{P <: Tuple} <:
       ProgramRelationshipRequest
    endpoint_a::Int32
    endpoint_b::Int32
    generation_a::UInt32
    generation_b::UInt32
    payload::P
    priority::Int32
    identity::UInt64
end

struct RemoveRelationshipRequest <: ProgramRelationshipRequest
    edge::Int32
    priority::Int32
    identity::UInt64
end

struct RetuneRelationshipRequest{P <: Tuple} <:
       ProgramRelationshipRequest
    edge::Int32
    payload::P
    priority::Int32
    identity::UInt64
end

function CreateRelationshipRequest(
        endpoint_a::Integer,
        endpoint_b::Integer,
        payload::Tuple = ();
        generation_a::Integer = 1,
        generation_b::Integer = 1,
        priority::Integer = 0,
        identity::Integer = 0,
    )
    return CreateRelationshipRequest(
        Int32(endpoint_a),
        Int32(endpoint_b),
        UInt32(generation_a),
        UInt32(generation_b),
        payload,
        Int32(priority),
        UInt64(identity),
    )
end

RemoveRelationshipRequest(edge::Integer; priority::Integer = 0,
        identity::Integer = 0) =
    RemoveRelationshipRequest(Int32(edge), Int32(priority), UInt64(identity))

function RetuneRelationshipRequest(
        edge::Integer,
        payload::Tuple;
        priority::Integer = 0,
        identity::Integer = 0,
    )
    return RetuneRelationshipRequest(
        Int32(edge), payload, Int32(priority), UInt64(identity)
    )
end

mutable struct RelationshipTransactionBuffer{S, Q, V <: AbstractVector{Q}}
    staged::S
    requests::V
    count::Int32
end

function RelationshipTransactionBuffer(
        state::ProgramRelationshipState,
        capacity::Integer,
    )
    capacity >= 0 || throw(ArgumentError(
        "relationship transaction capacity cannot be negative"
    ))
    payload = map(values -> zero(eltype(values)), state.payload)
    P = typeof(payload)
    Q = Union{
        CreateRelationshipRequest{P},
        RemoveRelationshipRequest,
        RetuneRelationshipRequest{P},
    }
    return RelationshipTransactionBuffer(
        copy(state),
        Vector{Q}(undef, capacity),
        Int32(0),
    )
end

@inline function reset_relationship_transaction!(
        buffer::RelationshipTransactionBuffer,
        state::ProgramRelationshipState,
    )
    copyto!(buffer.staged, state)
    buffer.count = 0
    return buffer
end

@inline function emit_relationship_request!(
        buffer::RelationshipTransactionBuffer,
        request::ProgramRelationshipRequest,
    )
    count = Int(buffer.count) + 1
    count <= length(buffer.requests) || throw(ArgumentError(
        "compiled relationship transaction request bound exceeded"
    ))
    @inbounds buffer.requests[count] = request
    buffer.count = Int32(count)
    return buffer
end

@generated function _call_relationship_slot(
        operation::F,
        values::V,
        slot::Int32,
        arguments::A,
    ) where {F, V <: Tuple, A <: Tuple}
    branches = Expr(:block)
    for index in 1:fieldcount(V)
        push!(branches.args, quote
            if slot == $(Int32(index))
                return operation(getfield(values, $index), arguments...)
            end
        end)
    end
    push!(branches.args, :(throw(ArgumentError(
        "relationship slot is outside compiled storage"
    ))))
    return branches
end

@inline _emit_relationship_request_at(buffer, request) =
    emit_relationship_request!(buffer, request)

@inline function emit_relationship_request_at!(
        buffers::Tuple,
        slot::Int32,
        request::ProgramRelationshipRequest,
    )
    return _call_relationship_slot(
        _emit_relationship_request_at, buffers, slot, (request,)
    )
end

@inline function _canonical_endpoints(a::Int32, b::Int32)
    return a < b ? (a, b) : (b, a)
end

function _relationship_edge(
        state::ProgramRelationshipState, a::Int32, b::Int32
    )
    a, b = _canonical_endpoints(a, b)
    return findfirst(eachindex(state.active)) do edge
        @inbounds state.active[edge] &&
            state.endpoint_a[edge] == a &&
            state.endpoint_b[edge] == b
    end
end

function _relationship_degree(state::ProgramRelationshipState, endpoint::Int32)
    1 <= endpoint <= length(state.degree) || return 0
    return @inbounds state.degree[endpoint]
end

function _insert_incident_edge!(
        state::ProgramRelationshipState,
        endpoint::Int32,
        edge::Int32,
    )
    1 <= endpoint <= length(state.degree) || throw(ArgumentError(
        "relationship endpoint $endpoint is outside incident storage"
    ))
    degree = Int(@inbounds state.degree[endpoint])
    degree < size(state.incident_edges, 1) || throw(ArgumentError(
        "relationship maximum degree exceeded for $endpoint"
    ))
    position = degree + 1
    while position > 1 &&
            @inbounds(state.incident_edges[position - 1, endpoint]) > edge
        @inbounds state.incident_edges[position, endpoint] =
            state.incident_edges[position - 1, endpoint]
        position -= 1
    end
    @inbounds state.incident_edges[position, endpoint] = edge
    @inbounds state.degree[endpoint] = Int16(degree + 1)
    return nothing
end

function _remove_incident_edge!(
        state::ProgramRelationshipState,
        endpoint::Int32,
        edge::Int32,
    )
    degree = Int(@inbounds state.degree[endpoint])
    position = 0
    for index in 1:degree
        if @inbounds(state.incident_edges[index, endpoint]) == edge
            position = index
            break
        end
    end
    position > 0 || error("active relationship is absent from its incident index")
    for index in position:(degree - 1)
        @inbounds state.incident_edges[index, endpoint] =
            state.incident_edges[index + 1, endpoint]
    end
    @inbounds state.incident_edges[degree, endpoint] = 0
    @inbounds state.degree[endpoint] = Int16(degree - 1)
    return nothing
end

function _validate_relationship_endpoint(
        endpoint::Int32,
        generation::UInt32,
        endpoint_status,
        endpoint_generations,
    )
    1 <= endpoint <= length(endpoint_status) ||
        throw(ArgumentError("relationship endpoint $endpoint is not an active cell"))
    @inbounds !iszero(endpoint_status[endpoint]) ||
        throw(ArgumentError("relationship endpoint $endpoint is not active"))
    @inbounds generation == endpoint_generations[endpoint] ||
        throw(ArgumentError("relationship endpoint generation is stale"))
    return nothing
end

function _validate_relationship_payload(
        state::ProgramRelationshipState,
        payload::Tuple,
    )
    length(payload) == length(state.payload) || throw(ArgumentError(
        "relationship request payload does not match its schema"
    ))
    all(isfinite, payload) || throw(DomainError(
        payload,
        "relationship request payload values must be finite",
    ))
    return nothing
end

function _request_sort_key(request::CreateRelationshipRequest)
    a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
    return (request.priority, 1, a, b, 0, request.identity)
end
_request_sort_key(request::RetuneRelationshipRequest) =
    (request.priority, 2, Int32(0), Int32(0), request.edge, request.identity)
_request_sort_key(request::RemoveRelationshipRequest) =
    (request.priority, 3, Int32(0), Int32(0), request.edge, request.identity)

function validate_relationship_request(
        state::ProgramRelationshipState,
        endpoint_status,
        endpoint_generations,
        schema::RelationshipStoreSchema,
        request::CreateRelationshipRequest,
    )
    request.endpoint_a != request.endpoint_b ||
        throw(ArgumentError("a relationship cannot be a self-edge"))
    a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
    generation_a, generation_b = request.endpoint_a == a ?
        (request.generation_a, request.generation_b) :
        (request.generation_b, request.generation_a)
    _validate_relationship_endpoint(
        a, generation_a, endpoint_status, endpoint_generations
    )
    _validate_relationship_endpoint(
        b, generation_b, endpoint_status, endpoint_generations
    )
    _relationship_edge(state, a, b) === nothing || return false
    _relationship_degree(state, a) < schema.maximum_degree ||
        throw(ArgumentError("relationship maximum degree exceeded for $a"))
    _relationship_degree(state, b) < schema.maximum_degree ||
        throw(ArgumentError("relationship maximum degree exceeded for $b"))
    findfirst(!, state.active) === nothing &&
        throw(ArgumentError("relationship capacity exceeded"))
    _validate_relationship_payload(state, request.payload)
    return true
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
        state::ProgramRelationshipState,
        request::CreateRelationshipRequest,
    )
    a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
    generation_a, generation_b = request.endpoint_a == a ?
        (request.generation_a, request.generation_b) :
        (request.generation_b, request.generation_a)
    slot = something(findfirst(!, state.active))
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
        state::ProgramRelationshipState,
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
        state::ProgramRelationshipState,
        request::RetuneRelationshipRequest,
    )
    for payload_slot in eachindex(state.payload)
        @inbounds state.payload[payload_slot][request.edge] =
            request.payload[payload_slot]
    end
    return state
end

@inline function _sort_relationship_requests!(
        buffer::RelationshipTransactionBuffer,
    )
    count = Int(buffer.count)
    for index in 2:count
        request = @inbounds buffer.requests[index]
        key = _request_sort_key(request)
        position = index
        while position > 1 &&
                _request_sort_key(@inbounds(buffer.requests[position - 1])) > key
            @inbounds buffer.requests[position] =
                buffer.requests[position - 1]
            position -= 1
        end
        @inbounds buffer.requests[position] = request
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
    for index in 1:Int(buffer.count)
        request = @inbounds buffer.requests[index]
        edge = _request_edge(request)
        if edge > 0
            for prior_index in 1:(index - 1)
                prior = @inbounds buffer.requests[prior_index]
                _request_edge(prior) == edge && throw(ArgumentError(
                    "conflicting relationship requests for edge $edge"
                ))
            end
        end
        if request isa CreateRelationshipRequest
            validate_relationship_request(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
            ) || continue
        else
            validate_relationship_request(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
            )
        end
        apply_validated_relationship_request!(staged, request)
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

@inline _reset_relationship_transactions!(::Tuple{}, ::Tuple{}) = nothing
@inline function _reset_relationship_transactions!(
        buffers::Tuple,
        states::Tuple,
    )
    reset_relationship_transaction!(first(buffers), first(states))
    return _reset_relationship_transactions!(
        Base.tail(buffers), Base.tail(states)
    )
end

@inline _prepare_relationship_transactions!(
    ::Tuple{}, endpoint_status, endpoint_generations, ::Tuple{}
) = nothing
@inline function _prepare_relationship_transactions!(
        buffers::Tuple,
        endpoint_status,
        endpoint_generations,
        schemas::Tuple,
    )
    prepare_relationship_transaction!(
        first(buffers),
        endpoint_status,
        endpoint_generations,
        first(schemas),
    )
    return _prepare_relationship_transactions!(
        Base.tail(buffers),
        endpoint_status,
        endpoint_generations,
        Base.tail(schemas),
    )
end

@inline _publish_relationship_transactions!(::Tuple{}, ::Tuple{}) = nothing
@inline function _publish_relationship_transactions!(
        states::Tuple,
        buffers::Tuple,
    )
    publish_relationship_transaction!(first(states), first(buffers))
    return _publish_relationship_transactions!(
        Base.tail(states), Base.tail(buffers)
    )
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

function initialize_program_relationships(
        schema::RelationshipStoreSchema,
        endpoint_status,
        endpoint_generations,
        parameters::AbstractVector{T},
        entries,
    ) where {T}
    state = ProgramRelationshipState(
        T,
        schema.capacity,
        length(endpoint_status),
        schema.maximum_degree,
        length(schema.payload_defaults),
    )
    entries === nothing && return state
    defaults = map(
        value -> compiled_scalar_value(value, parameters),
        schema.payload_defaults,
    )
    requests = ProgramRelationshipRequest[]
    for (identity, entry) in enumerate(entries)
        entry isa Tuple && length(entry) in (2, 3, 5) || throw(ArgumentError(
            "relationship entries are `(a, b)`, `(a, b, payload)`, or " *
            "`(a, b, payload, generation_a, generation_b)`"
        ))
        a, b = entry[1], entry[2]
        a isa Integer && 1 <= a <= length(endpoint_generations) ||
            throw(ArgumentError("relationship endpoint $a is not an active cell"))
        b isa Integer && 1 <= b <= length(endpoint_generations) ||
            throw(ArgumentError("relationship endpoint $b is not an active cell"))
        supplied = length(entry) >= 3 ? entry[3] : ntuple(_ -> nothing, length(defaults))
        supplied isa Tuple && length(supplied) == length(defaults) ||
            throw(ArgumentError(
                "initial relationship payload does not match its schema"
            ))
        payload = ntuple(length(defaults)) do slot
            value = supplied[slot]
            value === nothing ? defaults[slot] : T(value)
        end
        generation_a = length(entry) == 5 && entry[4] !== nothing ?
                       UInt32(entry[4]) : endpoint_generations[Int(a)]
        generation_b = length(entry) == 5 && entry[5] !== nothing ?
                       UInt32(entry[5]) : endpoint_generations[Int(b)]
        push!(requests, CreateRelationshipRequest(
            a,
            b,
            payload;
            generation_a,
            generation_b,
            identity,
        ))
    end
    apply_relationship_requests!(
        state, endpoint_status, endpoint_generations, schema, requests
    )
    return state
end

@inline function relationship_payload(
        state::ProgramRelationshipState,
        edge::Integer,
        slot::Integer,
    )
    1 <= slot <= length(state.payload) || throw(ArgumentError(
        "relationship payload slot is outside the compiled schema"
    ))
    1 <= edge <= length(state.active) || throw(ArgumentError(
        "relationship edge is outside the compiled store"
    ))
    return @inbounds state.payload[slot][edge]
end
