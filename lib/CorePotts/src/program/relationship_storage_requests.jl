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

function _copy_relationship_state_fields!(destination, source)
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

function Base.copyto!(
        destination::ProgramRelationshipState,
        source::ProgramRelationshipState,
    )
    return _copy_relationship_state_fields!(destination, source)
end

"""Read-only offset view into one packed relationship vector."""
struct PackedRelationshipVector{
        T,
        A <: AbstractVector{T},
    } <: AbstractVector{T}
    values::A
    offset::Int32
    count::Int32
end

Base.IndexStyle(::Type{<:PackedRelationshipVector}) = IndexLinear()
Base.size(values::PackedRelationshipVector) = (Int(values.count),)
Base.length(values::PackedRelationshipVector) = Int(values.count)
@inline function Base.getindex(values::PackedRelationshipVector, index::Int)
    @boundscheck checkbounds(values, index)
    return @inbounds values.values[Int(values.offset) + index - 1]
end

@inline function Base.setindex!(
        values::PackedRelationshipVector, value, index::Int
    )
    @boundscheck checkbounds(values, index)
    @inbounds values.values[Int(values.offset) + index - 1] = value
    return value
end

"""Read-only column-major view into one packed incident-edge matrix."""
struct PackedRelationshipMatrix{
        T,
        A <: AbstractVector{T},
    } <: AbstractMatrix{T}
    values::A
    offset::Int32
    rows::Int32
    columns::Int32
end

Base.IndexStyle(::Type{<:PackedRelationshipMatrix}) = IndexCartesian()
Base.size(values::PackedRelationshipMatrix) =
    (Int(values.rows), Int(values.columns))
@inline function Base.getindex(
        values::PackedRelationshipMatrix, row::Int, column::Int
    )
    @boundscheck checkbounds(values, row, column)
    index = Int(values.offset) + row - 1 + (column - 1) * Int(values.rows)
    return @inbounds values.values[index]
end

@inline function Base.setindex!(
        values::PackedRelationshipMatrix,
        value,
        row::Int,
        column::Int,
    )
    @boundscheck checkbounds(values, row, column)
    index = Int(values.offset) + row - 1 +
            (column - 1) * Int(values.rows)
    @inbounds values.values[index] = value
    return value
end

"""One isbits relationship-store view reconstructed from a packed bank."""
struct PackedRelationshipState{A, E, G, P, D, I}
    active::A
    endpoint_a::E
    endpoint_b::E
    generation_a::G
    generation_b::G
    payload::P
    degree::D
    incident_edges::I
end

function Base.copyto!(
        destination::ProgramRelationshipState,
        source::PackedRelationshipState,
    )
    return _copy_relationship_state_fields!(destination, source)
end

"""Occurrence-stable SoA bank used for read-only relationship kernels."""
struct PackedRelationshipBank{A, E, G, P, D, I, M}
    active::A
    endpoint_a::E
    endpoint_b::E
    generation_a::G
    generation_b::G
    payload::P
    degree::D
    incident_edges::I
    edge_offsets::M
    edge_counts::M
    endpoint_offsets::M
    endpoint_counts::M
    incident_offsets::M
    maximum_degrees::M
end

Adapt.@adapt_structure PackedRelationshipVector
Adapt.@adapt_structure PackedRelationshipMatrix
Adapt.@adapt_structure PackedRelationshipState
Adapt.@adapt_structure PackedRelationshipBank

Base.length(bank::PackedRelationshipBank) = length(bank.edge_offsets)

@inline function Base.getindex(bank::PackedRelationshipBank, slot::Int)
    @boundscheck checkbounds(bank.edge_offsets, slot)
    edge_offset = @inbounds bank.edge_offsets[slot]
    edge_count = @inbounds bank.edge_counts[slot]
    endpoint_offset = @inbounds bank.endpoint_offsets[slot]
    endpoint_count = @inbounds bank.endpoint_counts[slot]
    incident_offset = @inbounds bank.incident_offsets[slot]
    maximum_degree = @inbounds bank.maximum_degrees[slot]
    return PackedRelationshipState(
        PackedRelationshipVector(bank.active, edge_offset, edge_count),
        PackedRelationshipVector(bank.endpoint_a, edge_offset, edge_count),
        PackedRelationshipVector(bank.endpoint_b, edge_offset, edge_count),
        PackedRelationshipVector(bank.generation_a, edge_offset, edge_count),
        PackedRelationshipVector(bank.generation_b, edge_offset, edge_count),
        map(
            values -> PackedRelationshipVector(
                values, edge_offset, edge_count
            ),
            bank.payload,
        ),
        PackedRelationshipVector(
            bank.degree, endpoint_offset, endpoint_count
        ),
        PackedRelationshipMatrix(
            bank.incident_edges,
            incident_offset,
            maximum_degree,
            endpoint_count,
        ),
    )
end

function _flatten_relationship_arrays(states, accessor)
    prototype = accessor(first(states))
    total = sum(state -> length(accessor(state)), states; init = 0)
    total <= typemax(Int32) || throw(ArgumentError(
        "packed relationship storage exceeds the V1 Int32 offset bound"
    ))
    values = Vector{eltype(prototype)}(undef, total)
    offset = 1
    for state in states
        source = accessor(state)
        copyto!(values, offset, source, firstindex(source), length(source))
        offset += length(source)
    end
    return values
end

function _relationship_offsets(lengths)
    offsets = Vector{Int32}(undef, length(lengths))
    offset = 1
    for index in eachindex(lengths)
        length_value = Int(lengths[index])
        offset + length_value - 1 <= typemax(Int32) || throw(ArgumentError(
            "packed relationship storage exceeds the V1 Int32 offset bound"
        ))
        offsets[index] = Int32(offset)
        offset += length_value
    end
    return offsets, Int32.(lengths)
end

function _pack_relationship_bank(to, states::AbstractVector{S}) where {
        P,
        S <: ProgramRelationshipState{P},
    }
    isempty(states) && throw(ArgumentError(
        "a packed relationship representation bank cannot be empty"
    ))
    edge_lengths = map(state -> length(state.active), states)
    endpoint_lengths = map(state -> length(state.degree), states)
    incident_lengths = map(state -> length(state.incident_edges), states)
    maximum_degrees = map(state -> size(state.incident_edges, 1), states)
    edge_offsets, edge_counts = _relationship_offsets(edge_lengths)
    endpoint_offsets, endpoint_counts = _relationship_offsets(endpoint_lengths)
    incident_offsets, _ = _relationship_offsets(incident_lengths)
    payload = ntuple(Val(fieldcount(P))) do slot
        Adapt.adapt(to, _flatten_relationship_arrays(
            states, state -> state.payload[slot]
        ))
    end
    return PackedRelationshipBank(
        Adapt.adapt(to, _flatten_relationship_arrays(states, state -> state.active)),
        Adapt.adapt(to, _flatten_relationship_arrays(states, state -> state.endpoint_a)),
        Adapt.adapt(to, _flatten_relationship_arrays(states, state -> state.endpoint_b)),
        Adapt.adapt(to, _flatten_relationship_arrays(states, state -> state.generation_a)),
        Adapt.adapt(to, _flatten_relationship_arrays(states, state -> state.generation_b)),
        payload,
        Adapt.adapt(to, _flatten_relationship_arrays(states, state -> state.degree)),
        Adapt.adapt(to, _flatten_relationship_arrays(
            states, state -> vec(state.incident_edges)
        )),
        Adapt.adapt(to, edge_offsets),
        Adapt.adapt(to, edge_counts),
        Adapt.adapt(to, endpoint_offsets),
        Adapt.adapt(to, endpoint_counts),
        Adapt.adapt(to, incident_offsets),
        Adapt.adapt(to, Int32.(maximum_degrees)),
    )
end

_adapt_relationship_bank(to, values) = Adapt.adapt(to, values)
_adapt_relationship_bank(
    to, values::AbstractVector{<:ProgramRelationshipState}
) = _pack_relationship_bank(to, values)

function Adapt.adapt_structure(to, storage::RelationshipStorage)
    return RelationshipStorage(
        map(bank -> _adapt_relationship_bank(to, bank), storage.banks),
        Adapt.adapt(to, storage.slots),
    )
end

abstract type ProgramRelationshipRequest end

@enum RelationshipFailureDisposition::UInt8 begin
    RelationshipFailureError = 0x01
    RelationshipFailureFilter = 0x02
end

struct CreateRelationshipRequest{P <: Tuple} <:
       ProgramRelationshipRequest
    endpoint_a::Int32
    endpoint_b::Int32
    generation_a::UInt32
    generation_b::UInt32
    payload::P
    priority::Int32
    identity::UInt64
    on_failure::RelationshipFailureDisposition
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
        on_failure::RelationshipFailureDisposition = RelationshipFailureError,
    )
    return CreateRelationshipRequest(
        Int32(endpoint_a),
        Int32(endpoint_b),
        UInt32(generation_a),
        UInt32(generation_b),
        payload,
        Int32(priority),
        UInt64(identity),
        on_failure,
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

mutable struct RelationshipTransactionBuffer{
        S,
        Q,
        V <: AbstractVector{Q},
        I <: AbstractVector{Int32},
    }
    staged::S
    requests::V
    first_request_for_edge::I
    count::Int32
    filtered::Int32
    filtered_total::UInt64
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
        zeros(Int32, length(state.active)),
        Int32(0),
        Int32(0),
        UInt64(0),
    )
end

@inline function reset_relationship_transaction!(
        buffer::RelationshipTransactionBuffer,
        state::ProgramRelationshipState,
    )
    copyto!(buffer.staged, state)
    fill!(buffer.first_request_for_edge, Int32(0))
    buffer.count = 0
    buffer.filtered = 0
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

@generated function _call_relationship_bank(
        operation::F,
        banks::B,
        bank::Int32,
        slot::Int32,
        arguments::A,
    ) where {F, B <: Tuple, A <: Tuple}
    branches = Expr(:block)
    for index in 1:fieldcount(B)
        push!(branches.args, quote
            if bank == $(Int32(index))
                values = getfield(banks, $index)
                return operation(@inbounds(values[Int(slot)]), arguments...)
            end
        end)
    end
    push!(branches.args, :(throw(ArgumentError(
        "relationship slot is outside compiled storage"
    ))))
    return branches
end

@inline function _call_relationship_slot(
        operation,
        storage::RelationshipStorage,
        relationship_slot::Int32,
        arguments::Tuple,
    )
    location = _relationship_location(storage, Int(relationship_slot))
    return _call_relationship_bank(
        operation,
        storage.banks,
        location.bank,
        location.slot,
        arguments,
    )
end

@inline _emit_relationship_request_at(buffer, request) =
    emit_relationship_request!(buffer, request)

@inline function emit_relationship_request_at!(
        buffers::RelationshipStorage,
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

function _relationship_edge(state, a::Int32, b::Int32)
    a, b = _canonical_endpoints(a, b)
    a == b && return nothing
    (1 <= a <= length(state.degree) && 1 <= b <= length(state.degree)) ||
        return nothing
    degree_a = Int(@inbounds state.degree[Int(a)])
    degree_b = Int(@inbounds state.degree[Int(b)])
    endpoint = degree_a <= degree_b ? a : b
    degree = min(degree_a, degree_b)
    for position in 1:degree
        edge = Int(@inbounds state.incident_edges[position, Int(endpoint)])
        edge > 0 || continue
        if @inbounds state.active[edge] &&
                state.endpoint_a[edge] == a &&
                state.endpoint_b[edge] == b
            return edge
        end
    end
    return nothing
end

function _relationship_degree(state, endpoint::Int32)
    1 <= endpoint <= length(state.degree) || return Int32(0)
    return @inbounds state.degree[endpoint]
end

function _insert_incident_edge!(
        state,
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
        state,
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
    return (3, request.priority, a, b, 0, request.identity)
end
_request_sort_key(request::RetuneRelationshipRequest) =
    (2, request.priority, Int32(0), Int32(0), request.edge, request.identity)
_request_sort_key(request::RemoveRelationshipRequest) =
    (1, request.priority, Int32(0), Int32(0), request.edge, request.identity)

@inline function _canonical_create_signature(request::CreateRelationshipRequest)
    a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
    generations = request.endpoint_a == a ?
                  (request.generation_a, request.generation_b) :
                  (request.generation_b, request.generation_a)
    return (
        a,
        b,
        generations...,
        request.payload,
        request.priority,
        request.on_failure,
    )
end

@inline _relationship_request_equivalent(
    left::CreateRelationshipRequest,
    right::CreateRelationshipRequest,
) = _canonical_create_signature(left) == _canonical_create_signature(right)

@inline _relationship_request_equivalent(
    left::RemoveRelationshipRequest,
    right::RemoveRelationshipRequest,
) = left.edge == right.edge && left.priority == right.priority

@inline _relationship_request_equivalent(
    left::RetuneRelationshipRequest,
    right::RetuneRelationshipRequest,
) = left.edge == right.edge && left.payload == right.payload &&
    left.priority == right.priority

@inline _relationship_request_equivalent(
    ::ProgramRelationshipRequest, ::ProgramRelationshipRequest
) = false
