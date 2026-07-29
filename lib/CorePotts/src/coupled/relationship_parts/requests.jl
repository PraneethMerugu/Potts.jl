struct StableRelationshipPriority end

abstract type AbstractRelationshipRequest end
struct CreateRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
CreateRelationship(left, right, payload; priority::Integer = 0) =
    CreateRelationship(left, right, payload, Int32(priority))
struct RemoveRelationship <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    priority::Int32
end
RemoveRelationship(left, right; priority::Integer = 0) =
    RemoveRelationship(left, right, Int32(priority))
struct RetuneRelationship{T} <: AbstractRelationshipRequest
    left::CellEndpoint
    right::CellEndpoint
    payload::T
    priority::Int32
end
RetuneRelationship(left, right, payload; priority::Integer = 0) =
    RetuneRelationship(left, right, payload, Int32(priority))

const RELATIONSHIP_REMOVE_REQUEST = UInt8(1)
const RELATIONSHIP_RETUNE_REQUEST = UInt8(2)
const RELATIONSHIP_CREATE_REQUEST = UInt8(3)

struct RelationshipTransactionWorkspace{
        E <: AbstractVector{UInt32}, G <: AbstractVector{UInt64},
        P <: AbstractVector, A <: AbstractVector{UInt8},
        C <: AbstractVector{UInt32}, K <: AbstractVector{UInt8},
        R <: AbstractVector{Int32}}
    candidate_endpoint_a::E
    candidate_generation_a::G
    candidate_endpoint_b::E
    candidate_generation_b::G
    candidate_payload::P
    candidate_active::A
    candidate_count::C
    request_kind::K
    request_endpoint_a::E
    request_generation_a::G
    request_endpoint_b::E
    request_generation_b::G
    request_payload::P
    request_priority::R
    request_count::C
    status::C
    failing_request::C
end

function RelationshipTransactionWorkspace(
        state::RelationshipState; request_capacity::Integer =
            Int(state.declaration.capacity.value))
    request_capacity > 0 || throw(ArgumentError(
        "relationship request capacity must be positive"))
    candidate_endpoint_a = similar(state.endpoint_a)
    candidate_generation_a = similar(state.generation_a)
    candidate_endpoint_b = similar(state.endpoint_b)
    candidate_generation_b = similar(state.generation_b)
    candidate_payload = similar(state.payload)
    candidate_active = similar(state.active)
    request_endpoint_a = similar(state.endpoint_a, UInt32, request_capacity)
    request_generation_a = similar(
        state.generation_a, UInt64, request_capacity)
    request_endpoint_b = similar(state.endpoint_b, UInt32, request_capacity)
    request_generation_b = similar(
        state.generation_b, UInt64, request_capacity)
    request_payload = similar(state.payload, eltype(state.payload), request_capacity)
    request_kind = similar(state.active, UInt8, request_capacity)
    request_priority = similar(state.endpoint_a, Int32, request_capacity)
    candidate_count = similar(state.count)
    request_count = similar(state.count)
    status = similar(state.count)
    failing_request = similar(state.count)
    for array in (
            candidate_endpoint_a, candidate_generation_a,
            candidate_endpoint_b, candidate_generation_b,
            candidate_active, request_endpoint_a, request_generation_a,
            request_endpoint_b, request_generation_b, request_kind,
            request_priority, candidate_count, request_count,
            status, failing_request)
        fill!(array, zero(eltype(array)))
    end
    return RelationshipTransactionWorkspace(
        candidate_endpoint_a, candidate_generation_a,
        candidate_endpoint_b, candidate_generation_b,
        candidate_payload, candidate_active, candidate_count,
        request_kind, request_endpoint_a, request_generation_a,
        request_endpoint_b, request_generation_b, request_payload,
        request_priority, request_count, status, failing_request)
end

function Adapt.adapt_structure(to,
        workspace::RelationshipTransactionWorkspace)
    return RelationshipTransactionWorkspace(
        Adapt.adapt(to, workspace.candidate_endpoint_a),
        Adapt.adapt(to, workspace.candidate_generation_a),
        Adapt.adapt(to, workspace.candidate_endpoint_b),
        Adapt.adapt(to, workspace.candidate_generation_b),
        Adapt.adapt(to, workspace.candidate_payload),
        Adapt.adapt(to, workspace.candidate_active),
        Adapt.adapt(to, workspace.candidate_count),
        Adapt.adapt(to, workspace.request_kind),
        Adapt.adapt(to, workspace.request_endpoint_a),
        Adapt.adapt(to, workspace.request_generation_a),
        Adapt.adapt(to, workspace.request_endpoint_b),
        Adapt.adapt(to, workspace.request_generation_b),
        Adapt.adapt(to, workspace.request_payload),
        Adapt.adapt(to, workspace.request_priority),
        Adapt.adapt(to, workspace.request_count),
        Adapt.adapt(to, workspace.status),
        Adapt.adapt(to, workspace.failing_request))
end

@inline _relationship_request_kind(::RemoveRelationship) =
    RELATIONSHIP_REMOVE_REQUEST
@inline _relationship_request_kind(::RetuneRelationship) =
    RELATIONSHIP_RETUNE_REQUEST
@inline _relationship_request_kind(::CreateRelationship) =
    RELATIONSHIP_CREATE_REQUEST

function stage_relationship_requests!(
        workspace::RelationshipTransactionWorkspace,
        declaration::RelationshipSet, requests)
    ordered = collect(requests)
    all(request -> request isa AbstractRelationshipRequest, ordered) ||
        throw(ArgumentError(
            "relationship transaction contains an untyped request"))
    sort!(ordered; by = _request_key)
    length(ordered) <= length(workspace.request_kind) || throw(
        RelationshipCapacityError(
            declaration.name, length(ordered),
            UInt32(length(workspace.request_kind))))
    previous = nothing
    for (index, request) in enumerate(ordered)
        left, right = _canonical_endpoints(
            declaration, request.left, request.right)
        key = (left, right)
        key == previous && throw(ArgumentError(
            "relationship transaction contains conflicting requests for one edge"))
        previous = key
        payload = request isa RemoveRelationship ?
            workspace.request_payload[index] :
            convert(eltype(workspace.request_payload), request.payload)
        @inbounds begin
            workspace.request_kind[index] =
                _relationship_request_kind(request)
            workspace.request_endpoint_a[index] = value(left.cell)
            workspace.request_generation_a[index] =
                value(left.generation)
            workspace.request_endpoint_b[index] = value(right.cell)
            workspace.request_generation_b[index] =
                value(right.generation)
            request isa RemoveRelationship ||
                (workspace.request_payload[index] = payload)
            workspace.request_priority[index] = request.priority
        end
    end
    workspace.request_count[1] = UInt32(length(ordered))
    return workspace
end

function clear_relationship_requests!(
        workspace::RelationshipTransactionWorkspace)
    workspace.request_count[1] = UInt32(0)
    return workspace
end

@inline function _relationship_endpoint_is_current(
        active, generations, endpoint::UInt32, generation::UInt64)
    return UInt32(1) <= endpoint <= UInt32(length(active)) &&
        @inbounds(active[Int(endpoint)] != zero(eltype(active)) &&
            generations[Int(endpoint)] == generation)
end

@inline function _relationship_raw_edge_index(
        endpoint_a, generation_a, endpoint_b, generation_b,
        active, count, left, left_generation, right, right_generation)
    for index in 1:count
        @inbounds if active[index] != UInt8(0) &&
                endpoint_a[index] == left &&
                generation_a[index] == left_generation &&
                endpoint_b[index] == right &&
                generation_b[index] == right_generation
            return index
        end
    end
    return 0
end

@inline function _relationship_raw_degree(
        endpoint_a, generation_a, endpoint_b, generation_b,
        active, count, endpoint, generation)
    degree = 0
    for index in 1:count
        @inbounds active[index] == UInt8(0) && continue
        @inbounds degree += (
            (endpoint_a[index] == endpoint &&
             generation_a[index] == generation) ||
            (endpoint_b[index] == endpoint &&
             generation_b[index] == generation))
    end
    return degree
end

@inline function _relationship_raw_copy!(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, destination, source)
    @inbounds begin
        endpoint_a[destination] = endpoint_a[source]
        generation_a[destination] = generation_a[source]
        endpoint_b[destination] = endpoint_b[source]
        generation_b[destination] = generation_b[source]
        payload[destination] = payload[source]
        active[destination] = active[source]
    end
    return nothing
end

@inline function _relationship_raw_less(
        left_a, left_ga, left_b, left_gb,
        right_a, right_ga, right_b, right_gb)
    left_a != right_a && return left_a < right_a
    left_ga != right_ga && return left_ga < right_ga
    left_b != right_b && return left_b < right_b
    return left_gb < right_gb
end

"""Admit every pair of distinct active finite cells for contact-triggered relationship formation."""
