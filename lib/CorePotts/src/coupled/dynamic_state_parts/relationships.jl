struct CellEndpoint
    cell::CellID
    generation::CellGeneration
end
Base.isless(left::CellEndpoint, right::CellEndpoint) =
    (value(left.cell), value(left.generation)) <
    (value(right.cell), value(right.generation))

struct RelationshipCapacity
    value::UInt32
    function RelationshipCapacity(value::Integer)
        0 < value <= typemax(UInt32) || throw(ArgumentError(
            "relationship capacity must be positive and fit UInt32"))
        return new(UInt32(value))
    end
end

abstract type AbstractEndpointLifecyclePolicy end
struct RemoveIncidentEdges <: AbstractEndpointLifecyclePolicy end
struct RejectEndpointRetirement <: AbstractEndpointLifecyclePolicy end

"""Generation-aware bounded relationship declaration."""
struct RelationshipSet{T, E, L <: AbstractEndpointLifecyclePolicy}
    name::Symbol
    endpoint_scope::E
    edge_type::Type{T}
    directed::Bool
    maximum_degree::UInt32
    capacity::RelationshipCapacity
    endpoint_lifecycle::L
    version::VersionNumber
end

function RelationshipSet(name::Symbol, endpoint_scope = nothing;
        edge::Type{T}, directed::Bool = false,
        maximum_degree::Integer, capacity::RelationshipCapacity,
        endpoint_lifecycle::AbstractEndpointLifecyclePolicy = RemoveIncidentEdges(),
        version::VersionNumber = DYNAMIC_STATE_CONTRACT_VERSION) where {T}
    isbitstype(T) || throw(ArgumentError(
        "relationship payload type must be isbits"))
    0 < maximum_degree <= typemax(UInt32) || throw(ArgumentError(
        "maximum relationship degree must be positive and fit UInt32"))
    return RelationshipSet{T, typeof(endpoint_scope), typeof(endpoint_lifecycle)}(
        name, endpoint_scope, T, directed, UInt32(maximum_degree), capacity,
        endpoint_lifecycle, version)
end
component_identity(set::RelationshipSet) =
    ComponentIdentity(set.name, set.version, :relationship_set)
component_semantic_data(set::RelationshipSet) = (
    endpoint_scope = set.endpoint_scope, edge_type = set.edge_type, directed = set.directed,
    maximum_degree = set.maximum_degree, capacity = set.capacity,
    endpoint_lifecycle = set.endpoint_lifecycle)
component_effects(::RelationshipSet) = (:relationship_state,)

struct RelationshipEdge{T}
    left::CellEndpoint
    right::CellEndpoint
    payload::T
end

"""Generic elastic-link payload stored as three relationship-owned SoA columns."""
struct ElasticLinkParameters{T <: AbstractFloat}
    strength::T
    target_length::T
    maximum_length::T
    ElasticLinkParameters{T}(
        strength::T, target_length::T, maximum_length::T) where {T} =
        new{T}(strength, target_length, maximum_length)
    function ElasticLinkParameters(
            strength::T, target_length::T, maximum_length::T) where {
            T <: AbstractFloat}
        isfinite(strength) && strength >= zero(T) || throw(ArgumentError(
            "elastic-link strength must be finite and non-negative"))
        isfinite(target_length) && target_length >= zero(T) ||
            throw(ArgumentError(
                "elastic-link target length must be finite and non-negative"))
        isfinite(maximum_length) && maximum_length >= target_length ||
            throw(ArgumentError(
                "elastic-link maximum length must be finite and at least the target length"))
        return new{T}(strength, target_length, maximum_length)
    end
end
Base.zero(::Type{ElasticLinkParameters{T}}) where {T} =
    ElasticLinkParameters(zero(T), zero(T), zero(T))

struct ElasticLinkColumns{T <: AbstractFloat,
        A <: AbstractVector{T}} <: AbstractVector{ElasticLinkParameters{T}}
    strength::A
    target_length::A
    maximum_length::A
end
Base.IndexStyle(::Type{<:ElasticLinkColumns}) = IndexLinear()
Base.size(columns::ElasticLinkColumns) = size(columns.strength)
Base.length(columns::ElasticLinkColumns) = length(columns.strength)
@inline function Base.getindex(columns::ElasticLinkColumns, index::Int)
    @boundscheck checkbounds(columns.strength, index)
    @inbounds return ElasticLinkParameters{eltype(columns.strength)}(
        columns.strength[index],
        columns.target_length[index],
        columns.maximum_length[index])
end
@inline function Base.setindex!(
        columns::ElasticLinkColumns{T}, value::ElasticLinkParameters{T},
        index::Int) where {T}
    @boundscheck checkbounds(columns.strength, index)
    @inbounds begin
        columns.strength[index] = value.strength
        columns.target_length[index] = value.target_length
        columns.maximum_length[index] = value.maximum_length
    end
    return value
end
function Base.similar(columns::ElasticLinkColumns{T}) where {T}
    return ElasticLinkColumns(
        similar(columns.strength),
        similar(columns.target_length),
        similar(columns.maximum_length))
end
function Base.similar(columns::ElasticLinkColumns{T},
        ::Type{ElasticLinkParameters{T}}, dims::Dims) where {T}
    return ElasticLinkColumns(
        similar(columns.strength, T, dims),
        similar(columns.target_length, T, dims),
        similar(columns.maximum_length, T, dims))
end
Base.similar(columns::ElasticLinkColumns{T},
    ::Type{ElasticLinkParameters{T}}, length::Int) where {T} =
    similar(columns, ElasticLinkParameters{T}, (length,))
function Adapt.adapt_structure(to, columns::ElasticLinkColumns)
    return ElasticLinkColumns(
        Adapt.adapt(to, columns.strength),
        Adapt.adapt(to, columns.target_length),
        Adapt.adapt(to, columns.maximum_length))
end
KernelAbstractions.get_backend(columns::ElasticLinkColumns) =
    KernelAbstractions.get_backend(columns.strength)

_relationship_payload_storage(::Type{T}, capacity::Int) where {T} =
    Vector{T}(undef, capacity)
function _relationship_payload_storage(
        ::Type{ElasticLinkParameters{T}}, capacity::Int) where {T}
    return ElasticLinkColumns(
        zeros(T, capacity), zeros(T, capacity), zeros(T, capacity))
end

mutable struct RelationshipState{D <: RelationshipSet, T,
        E <: AbstractVector{UInt32}, G <: AbstractVector{UInt64},
        P <: AbstractVector{T}, A <: AbstractVector{UInt8},
        C <: AbstractVector{UInt32}, U <: AbstractVector{UInt64}}
    declaration::D
    endpoint_a::E
    generation_a::G
    endpoint_b::E
    generation_b::G
    payload::P
    active::A
    count::C
    publication_epoch::U
end
function RelationshipState(set::RelationshipSet{T}) where {T}
    capacity = Int(set.capacity.value)
    endpoint_a = zeros(UInt32, capacity)
    generation_a = zeros(UInt64, capacity)
    endpoint_b = zeros(UInt32, capacity)
    generation_b = zeros(UInt64, capacity)
    payload = _relationship_payload_storage(T, capacity)
    zero_payload = hasmethod(zero, Tuple{Type{T}}) ?
        zero(T) : reinterpret(T, zeros(UInt8, sizeof(T)))[1]
    fill!(payload, zero_payload)
    active = zeros(UInt8, capacity)
    return RelationshipState(
        set, endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, zeros(UInt32, 1), zeros(UInt64, 1))
end

function Adapt.adapt_structure(to, state::RelationshipState)
    return RelationshipState(
        state.declaration,
        Adapt.adapt(to, state.endpoint_a),
        Adapt.adapt(to, state.generation_a),
        Adapt.adapt(to, state.endpoint_b),
        Adapt.adapt(to, state.generation_b),
        Adapt.adapt(to, state.payload),
        Adapt.adapt(to, state.active),
        Adapt.adapt(to, state.count),
        Adapt.adapt(to, state.publication_epoch))
end

"""
Descriptor-free fixed-capacity relationship view admitted to portable kernels.

The relationship identity, directionality, and maximum degree are encoded in the type. All
runtime storage is a backend-adaptable isbits array.
"""
struct RelationshipExecutionState{Name, Directed, MaximumDegree,
        E, G, P, A, C, U}
    endpoint_a::E
    generation_a::G
    endpoint_b::E
    generation_b::G
    payload::P
    active::A
    count::C
    publication_epoch::U
end

RelationshipExecutionState(state::RelationshipState) =
    RelationshipExecutionState{
        state.declaration.name, state.declaration.directed,
        Int(state.declaration.maximum_degree),
        typeof(state.endpoint_a), typeof(state.generation_a),
        typeof(state.payload), typeof(state.active),
        typeof(state.count), typeof(state.publication_epoch)}(
        state.endpoint_a, state.generation_a,
        state.endpoint_b, state.generation_b,
        state.payload, state.active, state.count,
        state.publication_epoch)

function Adapt.adapt_structure(to,
        state::RelationshipExecutionState{Name, Directed, MaximumDegree}) where {
        Name, Directed, MaximumDegree}
    endpoint_a = Adapt.adapt(to, state.endpoint_a)
    generation_a = Adapt.adapt(to, state.generation_a)
    endpoint_b = Adapt.adapt(to, state.endpoint_b)
    generation_b = Adapt.adapt(to, state.generation_b)
    payload = Adapt.adapt(to, state.payload)
    active = Adapt.adapt(to, state.active)
    count = Adapt.adapt(to, state.count)
    publication_epoch = Adapt.adapt(to, state.publication_epoch)
    return RelationshipExecutionState{Name, Directed, MaximumDegree,
        typeof(endpoint_a), typeof(generation_a), typeof(payload),
        typeof(active), typeof(count), typeof(publication_epoch)}(
        endpoint_a, generation_a, endpoint_b, generation_b,
        payload, active, count, publication_epoch)
end

@inline _relationship_count(state::RelationshipState) =
    Int(@inbounds state.count[1])

@inline function _relationship_edge(state::RelationshipState, index::Int)
    @boundscheck 1 <= index <= _relationship_count(state) ||
        throw(BoundsError(state, index))
    @inbounds return RelationshipEdge(
        CellEndpoint(
            CellID(state.endpoint_a[index]),
            CellGeneration(state.generation_a[index])),
        CellEndpoint(
            CellID(state.endpoint_b[index]),
            CellGeneration(state.generation_b[index])),
        state.payload[index])
end

function _relationship_edges(state::RelationshipState)
    return [_relationship_edge(state, index)
        for index in 1:_relationship_count(state)]
end

# Compatibility inspection for the registry-v1 provisional surface. Mutations use the bounded
# state operations below; the returned vector is deliberately not authoritative storage.
function Base.getproperty(state::RelationshipState, name::Symbol)
    name === :edges && return _relationship_edges(state)
    return getfield(state, name)
end

function clear_relationships!(state::RelationshipState)
    fill!(state.endpoint_a, UInt32(0))
    fill!(state.generation_a, UInt64(0))
    fill!(state.endpoint_b, UInt32(0))
    fill!(state.generation_b, UInt64(0))
    fill!(state.active, UInt8(0))
    fill!(state.count, UInt32(0))
    return state
end

struct RelationshipCapacityError <: Exception
    relationship::Symbol
    requested::Int
    capacity::UInt32
end
Base.showerror(io::IO, error::RelationshipCapacityError) = print(io,
    "relationship `", error.relationship, "` capacity ", error.capacity,
    " cannot admit ", error.requested, " edges")

function _canonical_endpoints(set::RelationshipSet,
        left::CellEndpoint, right::CellEndpoint)
    left == right && throw(ArgumentError("relationship self-edges are not admitted"))
    return set.directed || isless(left, right) ? (left, right) : (right, left)
end

function _edge_index(state::RelationshipState,
        left::CellEndpoint, right::CellEndpoint)
    canonical = _canonical_endpoints(state.declaration, left, right)
    left_value = value(canonical[1].cell)
    left_generation = value(canonical[1].generation)
    right_value = value(canonical[2].cell)
    right_generation = value(canonical[2].generation)
    for index in 1:_relationship_count(state)
        @inbounds if state.active[index] != UInt8(0) &&
                state.endpoint_a[index] == left_value &&
                state.generation_a[index] == left_generation &&
                state.endpoint_b[index] == right_value &&
                state.generation_b[index] == right_generation
            return index
        end
    end
    return nothing
end

function _relationship_degree(state::RelationshipState, endpoint)
    endpoint_value = value(endpoint.cell)
    endpoint_generation = value(endpoint.generation)
    degree = 0
    for index in 1:_relationship_count(state)
        @inbounds state.active[index] == UInt8(0) && continue
        @inbounds degree += (
            (state.endpoint_a[index] == endpoint_value &&
             state.generation_a[index] == endpoint_generation) ||
            (state.endpoint_b[index] == endpoint_value &&
             state.generation_b[index] == endpoint_generation))
    end
    return degree
end

@inline function _relationship_key(
        left::CellEndpoint, right::CellEndpoint)
    return (
        value(left.cell), value(left.generation),
        value(right.cell), value(right.generation))
end

function _relationship_insert_index(
        state::RelationshipState, left::CellEndpoint, right::CellEndpoint)
    key = _relationship_key(left, right)
    for index in 1:_relationship_count(state)
        edge = _relationship_edge(state, index)
        key < _relationship_key(edge.left, edge.right) && return index
    end
    return _relationship_count(state) + 1
end

@inline function _copy_relationship_slot!(
        state::RelationshipState, destination::Int, source::Int)
    @inbounds begin
        state.endpoint_a[destination] = state.endpoint_a[source]
        state.generation_a[destination] = state.generation_a[source]
        state.endpoint_b[destination] = state.endpoint_b[source]
        state.generation_b[destination] = state.generation_b[source]
        state.payload[destination] = state.payload[source]
        state.active[destination] = state.active[source]
    end
    return state
end

function create_relationship!(state::RelationshipState{D, T},
        left::CellEndpoint, right::CellEndpoint, payload::T) where {D, T}
    canonical = _canonical_endpoints(state.declaration, left, right)
    _edge_index(state, canonical...) === nothing || throw(ArgumentError(
        "duplicate relationship edge"))
    count = _relationship_count(state)
    count < Int(state.declaration.capacity.value) || throw(
        RelationshipCapacityError(state.declaration.name,
            count + 1, state.declaration.capacity.value))
    for endpoint in canonical
        _relationship_degree(state, endpoint) <
            Int(state.declaration.maximum_degree) || throw(ArgumentError(
                "relationship maximum degree exceeded"))
    end
    insertion = _relationship_insert_index(state, canonical...)
    for index in (count + 1):-1:(insertion + 1)
        _copy_relationship_slot!(state, index, index - 1)
    end
    @inbounds begin
        state.endpoint_a[insertion] = value(canonical[1].cell)
        state.generation_a[insertion] = value(canonical[1].generation)
        state.endpoint_b[insertion] = value(canonical[2].cell)
        state.generation_b[insertion] = value(canonical[2].generation)
        state.payload[insertion] = payload
        state.active[insertion] = UInt8(1)
        state.count[1] = UInt32(count + 1)
    end
    return state
end

function remove_relationship!(state::RelationshipState,
        left::CellEndpoint, right::CellEndpoint)
    index = _edge_index(state, left, right)
    index === nothing && return false
    count = _relationship_count(state)
    for source in (index + 1):count
        _copy_relationship_slot!(state, source - 1, source)
    end
    @inbounds begin
        state.endpoint_a[count] = UInt32(0)
        state.generation_a[count] = UInt64(0)
        state.endpoint_b[count] = UInt32(0)
        state.generation_b[count] = UInt64(0)
        state.active[count] = UInt8(0)
        state.count[1] = UInt32(count - 1)
    end
    return true
end

function retune_relationship!(state::RelationshipState{D, T},
        left::CellEndpoint, right::CellEndpoint, payload::T) where {D, T}
    index = _edge_index(state, left, right)
    index === nothing && throw(ArgumentError("cannot retune an absent relationship"))
    @inbounds state.payload[index] = payload
    return state
end

function relationship_edges(state::RelationshipState, endpoint::CellEndpoint)
    result = RelationshipEdge{eltype(state.payload)}[]
    for index in 1:_relationship_count(state)
        edge = _relationship_edge(state, index)
        (edge.left == endpoint || edge.right == endpoint) &&
            push!(result, edge)
    end
    return Tuple(result)
end

function relationship_payload(state::RelationshipState,
        left::CellEndpoint, right::CellEndpoint)
    index = _edge_index(state, left, right)
    index === nothing && throw(ArgumentError("relationship edge is absent"))
    return @inbounds state.payload[index]
end

function retire_relationship_endpoint!(state::RelationshipState,
        endpoint::CellEndpoint)
    found = false
    index = 1
    while index <= _relationship_count(state)
        edge = _relationship_edge(state, index)
        if edge.left == endpoint || edge.right == endpoint
            found = true
            state.declaration.endpoint_lifecycle isa RemoveIncidentEdges || throw(
                ArgumentError("relationship endpoint retirement rejected by policy"))
            remove_relationship!(state, edge.left, edge.right)
        else
            index += 1
        end
    end
    found || return state
    return state
end
