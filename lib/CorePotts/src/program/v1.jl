abstract type AbstractProgramEngine end
struct SequentialProgramEngine <: AbstractProgramEngine end
struct CheckerboardProgramEngine <: AbstractProgramEngine end
struct CPUProgramBackend end

struct CompiledScalar{T <: AbstractFloat}
    value::T
    parameter_index::Int32
    function CompiledScalar(value::T, parameter_index::Integer = 0) where {
            T <: AbstractFloat,
        }
        0 <= parameter_index <= typemax(Int32) ||
            throw(ArgumentError("compiled scalar parameter index is out of range"))
        new{T}(value, Int32(parameter_index))
    end
end

@inline function compiled_scalar_value(
        scalar::CompiledScalar{T}, parameters::AbstractVector{T}
    ) where {T}
    index = scalar.parameter_index
    return index == 0 ? scalar.value : @inbounds parameters[index]
end

struct RelationshipStoreSchema{D <: Tuple}
    capacity::Int32
    maximum_degree::Int16
    payload_defaults::D
end

function RelationshipStoreSchema(
        capacity::Integer,
        maximum_degree::Integer,
        payload_defaults::Tuple = (),
    )
    capacity > 0 || throw(ArgumentError("relationship capacity must be positive"))
    capacity <= typemax(Int32) || throw(ArgumentError(
        "relationship capacity exceeds the V1 Int32 storage bound"
    ))
    maximum_degree > 0 ||
        throw(ArgumentError("relationship maximum degree must be positive"))
    maximum_degree <= typemax(Int16) || throw(ArgumentError(
        "relationship maximum degree exceeds the V1 Int16 storage bound"
    ))
    return RelationshipStoreSchema(
        Int32(capacity),
        Int16(maximum_degree),
        payload_defaults,
    )
end

struct CompiledPottsProgram{
        T <: AbstractFloat,
        N,
        E <: AbstractProgramEngine,
        B,
        R,
        D,
        SP,
    }
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::Matrix{Int8}
    contact_offsets::Matrix{Int8}
    kind_count::Int16
    medium_kind::Int16
    medium_kinds::BitVector
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    parameter_defaults::Vector{T}
    relationships::R
    descriptor_plan::D
    stage_plan::SP
    engine::E
    backend::B
    fingerprint::String
end

function CompiledPottsProgram(
        shape::NTuple{N, Int},
        periodic::NTuple{N, Bool},
        proposal_offsets::Matrix{Int8},
        contact_offsets::Matrix{Int8},
        kind_count::Integer,
        medium_kind::Integer,
        temperature::CompiledScalar{T},
        attempts_per_site::Integer,
        parameter_defaults::Vector{T},
        relationships,
        descriptor_plan::D,
        stage_plan::SP,
        engine::E,
        backend::B,
        fingerprint::AbstractString;
        medium_kinds = nothing,
    ) where {T <: AbstractFloat, N, D, SP, E <: AbstractProgramEngine, B}
    all(>(0), shape) || throw(ArgumentError("program dimensions must be positive"))
    size(proposal_offsets, 1) == N ||
        throw(ArgumentError("proposal offsets have the wrong dimensionality"))
    size(contact_offsets, 1) == N ||
        throw(ArgumentError("contact offsets have the wrong dimensionality"))
    kind_count > 0 || throw(ArgumentError("a program requires at least one kind"))
    1 <= medium_kind <= kind_count ||
        throw(ArgumentError("the medium kind must be declared"))
    medium_mask = medium_kinds === nothing ? begin
        value = falses(kind_count)
        value[medium_kind] = true
        value
    end : BitVector(medium_kinds)
    length(medium_mask) == kind_count ||
        throw(ArgumentError("the medium-kind table has the wrong size"))
    medium_mask[medium_kind] ||
        throw(ArgumentError("the default medium must be a declared medium kind"))
    attempts_per_site > 0 ||
        throw(ArgumentError("attempts per site must be positive"))
    return CompiledPottsProgram{
        T, N, E, B, typeof(relationships), D, SP,
    }(
        shape,
        periodic,
        copy(proposal_offsets),
        copy(contact_offsets),
        Int16(kind_count),
        Int16(medium_kind),
        medium_mask,
        temperature,
        Int32(attempts_per_site),
        copy(parameter_defaults),
        relationships,
        descriptor_plan,
        stage_plan,
        engine,
        backend,
        String(fingerprint),
    )
end

struct ProgramInitialState{T <: AbstractFloat, N, R, D}
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    relationships::R
    descriptor_state::D
end

_copy_program_value(value::AbstractArray) = copy(value)
_copy_program_value(value::Tuple) = map(_copy_program_value, value)
function _copy_program_value(value::NamedTuple)
    mapped = map(_copy_program_value, values(value))
    return NamedTuple{keys(value)}(mapped)
end
_copy_program_value(value) = value

function ProgramInitialState(
        ownership::AbstractArray{<:Integer, N},
        cell_kinds::AbstractVector{<:Integer};
        scalar_type::Type{T} = Float64,
        cell_generations = nothing,
        relationships = nothing,
        descriptor_state = nothing,
    ) where {N, T <: AbstractFloat}
    owned = Array{Int32, N}(ownership)
    kinds = Int16.(cell_kinds)
    generations = cell_generations === nothing ?
                  ones(UInt32, length(kinds)) :
                  UInt32.(cell_generations)
    length(generations) == length(kinds) ||
        throw(ArgumentError("cell generation table has the wrong length"))
    all(!iszero, generations) ||
        throw(ArgumentError("active cell generations must be positive"))
    relationship_values = relationships === nothing ? nothing : deepcopy(relationships)
    return ProgramInitialState{
        T, N, typeof(relationship_values), typeof(descriptor_state),
    }(
        owned,
        kinds,
        generations,
        relationship_values,
        descriptor_state,
    )
end

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
    length(request.payload) == length(state.payload) ||
        throw(ArgumentError(
            "relationship request payload does not match its schema"
        ))
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
    request isa RetuneRelationshipRequest &&
        length(request.payload) != length(state.payload) &&
        throw(ArgumentError(
            "relationship request payload does not match its schema"
        ))
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

function apply_relationship_requests!(
        state::ProgramRelationshipState,
        endpoint_status,
        endpoint_generations,
        schema::RelationshipStoreSchema,
        requests,
    )
    length(endpoint_status) == length(endpoint_generations) ||
        throw(ArgumentError("relationship endpoint tables have different lengths"))
    length(state.payload) == length(schema.payload_defaults) ||
        throw(ArgumentError("relationship state payload does not match its schema"))
    staged = copy(state)
    ordered = sort!(collect(requests); by = _request_sort_key)
    touched_edges = Set{Int32}()
    for request in ordered
        if request isa CreateRelationshipRequest
            validate_relationship_request(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
            ) || continue # declared duplicate policy: ignore exact create
            apply_validated_relationship_request!(staged, request)
        elseif request isa RemoveRelationshipRequest
            edge = request.edge
            1 <= edge <= length(staged.active) && staged.active[edge] ||
                throw(ArgumentError("remove request references an inactive edge"))
            edge in touched_edges &&
                throw(ArgumentError("conflicting relationship requests for edge $edge"))
            push!(touched_edges, edge)
            validate_relationship_request(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
            )
            apply_validated_relationship_request!(staged, request)
        elseif request isa RetuneRelationshipRequest
            edge = request.edge
            1 <= edge <= length(staged.active) && staged.active[edge] ||
                throw(ArgumentError("retune request references an inactive edge"))
            edge in touched_edges &&
                throw(ArgumentError("conflicting relationship requests for edge $edge"))
            push!(touched_edges, edge)
            validate_relationship_request(
                staged,
                endpoint_status,
                endpoint_generations,
                schema,
                request,
            )
            apply_validated_relationship_request!(staged, request)
        else
            throw(ArgumentError("unknown relationship request type"))
        end
    end
    copyto!(state.active, staged.active)
    copyto!(state.endpoint_a, staged.endpoint_a)
    copyto!(state.endpoint_b, staged.endpoint_b)
    copyto!(state.generation_a, staged.generation_a)
    copyto!(state.generation_b, staged.generation_b)
    for payload_slot in eachindex(state.payload)
        copyto!(state.payload[payload_slot], staged.payload[payload_slot])
    end
    copyto!(state.degree, staged.degree)
    copyto!(state.incident_edges, staged.incident_edges)
    return state
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

struct ProgramSnapshot{T <: AbstractFloat, N, R, D}
    mcs::Int
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    volumes::Vector{Int}
    relationships::R
    descriptor_state::D
end

struct ProgramCheckpoint{S, P}
    schema::VersionNumber
    program_fingerprint::String
    snapshot::S
    parameters::P
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    accepted::Int
    rejected::Int
    null_attempts::Int
    constraint_rejections::Int
    energy_rejections::Int
    retired_cells::Int
    checksum::String
end

function _program_checkpoint_checksum(
        schema,
        fingerprint,
        snapshot,
        parameters,
        seed,
        replica,
        repeat,
        accepted,
        rejected,
        null_attempts,
        constraint_rejections,
        energy_rejections,
        retired_cells,
    )
    payload = string(
        schema, '\n',
        fingerprint, '\n',
        snapshot.mcs, '\n',
        size(snapshot.ownership), '\n',
        join(vec(snapshot.ownership), ','), '\n',
        join(snapshot.cell_kinds, ','), '\n',
        join(snapshot.cell_generations, ','), '\n',
        join(snapshot.volumes, ','), '\n',
        repr(snapshot.descriptor_state), '\n',
        snapshot.relationships === nothing ? "nothing" :
        string(
            join(snapshot.relationships.active, ','),
            ';', join(snapshot.relationships.endpoint_a, ','),
            ';', join(snapshot.relationships.endpoint_b, ','),
            ';', join(snapshot.relationships.generation_a, ','),
            ';', join(snapshot.relationships.generation_b, ','),
            ';', join(
                (join(values, ',') for values in snapshot.relationships.payload),
                '|',
            ),
            ';', join(snapshot.relationships.degree, ','),
            ';', join(vec(snapshot.relationships.incident_edges), ','),
        ), '\n',
        join(parameters, ','), '\n',
        seed, '\n',
        replica, '\n',
        repeat, '\n',
        accepted, '\n',
        rejected, '\n',
        null_attempts, '\n',
        constraint_rejections, '\n',
        energy_rejections, '\n',
        retired_cells,
    )
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function program_checkpoint(runtime)
    runtime.settled || throw(ArgumentError(
        "a checkpoint requires a settled complete-MCS boundary"
    ))
    schema = v"1.0.0"
    snapshot = program_snapshot(runtime)
    parameters = copy(runtime.parameters)
    checksum = _program_checkpoint_checksum(
        schema,
        runtime.program.fingerprint,
        snapshot,
        parameters,
        runtime.seed,
        runtime.replica,
        runtime.repeat,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
    )
    return ProgramCheckpoint(
        schema,
        runtime.program.fingerprint,
        snapshot,
        parameters,
        runtime.seed,
        runtime.replica,
        runtime.repeat,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
        checksum,
    )
end

function restore_program_checkpoint(
        program::CompiledPottsProgram, checkpoint::ProgramCheckpoint
    )
    checkpoint.schema == v"1.0.0" ||
        throw(ArgumentError("unsupported CorePotts checkpoint schema"))
    checkpoint.program_fingerprint == program.fingerprint ||
        throw(ArgumentError("checkpoint executable identity does not match"))
    expected = _program_checkpoint_checksum(
        checkpoint.schema,
        checkpoint.program_fingerprint,
        checkpoint.snapshot,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica,
        checkpoint.repeat,
        checkpoint.accepted,
        checkpoint.rejected,
        checkpoint.null_attempts,
        checkpoint.constraint_rejections,
        checkpoint.energy_rejections,
        checkpoint.retired_cells,
    )
    expected == checkpoint.checksum ||
        throw(ArgumentError("checkpoint integrity checksum mismatch"))
    initial = ProgramInitialState(
        checkpoint.snapshot.ownership,
        checkpoint.snapshot.cell_kinds;
        scalar_type = eltype(program.parameter_defaults),
        cell_generations = checkpoint.snapshot.cell_generations,
        relationships = nothing,
        descriptor_state = checkpoint.snapshot.descriptor_state,
    )
    runtime = initialize_program(
        program,
        initial,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica;
        repeat = checkpoint.repeat,
        initial_mcs = checkpoint.snapshot.mcs,
    )
    runtime.volumes == checkpoint.snapshot.volumes ||
        throw(ArgumentError("checkpoint logical volume invariant failed"))
    if checkpoint.snapshot.relationships !== nothing
        runtime.relationships = copy(checkpoint.snapshot.relationships)
    end
    runtime.accepted = checkpoint.accepted
    runtime.rejected = checkpoint.rejected
    runtime.null_attempts = checkpoint.null_attempts
    runtime.constraint_rejections = checkpoint.constraint_rejections
    runtime.energy_rejections = checkpoint.energy_rejections
    runtime.retired_cells = checkpoint.retired_cells
    return runtime
end

mutable struct ProgramRuntime{T <: AbstractFloat, N, P, R, D, SB}
    program::P
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    volumes::Vector{Int}
    relationships::R
    descriptor_state::D
    proposal_contributions::Vector{ProposalEvaluation{T}}
    stage_buffers::SB
    parameters::Vector{T}
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
    accepted::Int
    rejected::Int
    null_attempts::Int
    constraint_rejections::Int
    energy_rejections::Int
    retired_cells::Int
    settled::Bool
end

function initialize_program(
        program::CompiledPottsProgram{T, N},
        initial::ProgramInitialState,
        parameters::AbstractVector{<:Real},
        seed::UInt64,
        replica::UInt32;
        repeat::UInt32 = UInt32(1),
        initial_mcs::Integer = 0,
    ) where {T, N}
    size(initial.ownership) == program.shape ||
        throw(ArgumentError("initial ownership shape does not match the program"))
    length(parameters) == length(program.parameter_defaults) ||
        throw(ArgumentError("runtime parameter buffer has the wrong length"))
    maximum(initial.ownership; init = Int32(0)) <= length(initial.cell_kinds) ||
        throw(ArgumentError("initial ownership references an unknown cell label"))
    minimum(initial.ownership; init = Int32(0)) >= -program.kind_count ||
        throw(ArgumentError("initial ownership references an unknown medium kind"))
    all(initial.ownership) do owner
        owner >= 0 || @inbounds(program.medium_kinds[-owner])
    end || throw(ArgumentError(
        "initial ownership uses a non-medium kind as a medium domain"
    ))
    all(kind -> kind == 0 || 1 <= kind <= program.kind_count, initial.cell_kinds) ||
        throw(ArgumentError("initial cell kind is outside the compiled kind table"))
    all(kind -> kind == 0 || !program.medium_kinds[kind], initial.cell_kinds) ||
        throw(ArgumentError("a finite cell cannot use a medium kind"))
    length(initial.cell_generations) == length(initial.cell_kinds) ||
        throw(ArgumentError("initial cell generation table has the wrong length"))
    all(!iszero, initial.cell_generations) ||
        throw(ArgumentError("active cell generations must be positive"))
    initial_mcs >= 0 || throw(ArgumentError("initial MCS must be nonnegative"))
    repeat > 0 || throw(ArgumentError("ensemble repeat identity must be positive"))

    volumes = zeros(Int, length(initial.cell_kinds))
    for owner in initial.ownership
        owner > 0 && (volumes[owner] += 1)
    end
    all(eachindex(volumes)) do cell
        active = initial.cell_kinds[cell] != 0
        occupied = volumes[cell] != 0
        active == occupied
    end || throw(ArgumentError(
        "every active finite cell must own at least one site and inactive slots " *
        "must not appear in ownership"
    ))
    relationships = if program.relationships === nothing
        nothing
    else
        initialize_program_relationships(
            program.relationships,
            initial.cell_kinds,
            initial.cell_generations,
            T.(parameters),
            initial.relationships,
        )
    end
    descriptor_state = if initial.descriptor_state === nothing
        allocate_auxiliary_state(program.descriptor_plan.state_layout)
    elseif initial.descriptor_state isa AuxiliaryState
        copy_auxiliary_state(
            program.descriptor_plan.state_layout,
            initial.descriptor_state,
        )
    else
        throw(ArgumentError(
            "descriptor state must be a CorePotts AuxiliaryState"
        ))
    end
    stage_buffers = allocate_stage_runtime_buffers(
        program.stage_plan,
        T,
        program.shape,
        program.relationships === nothing ? 0 : program.relationships.capacity,
    )
    return ProgramRuntime{
        T, N, typeof(program), typeof(relationships),
        typeof(descriptor_state),
        typeof(stage_buffers),
    }(
        program,
        copy(initial.ownership),
        copy(initial.cell_kinds),
        copy(initial.cell_generations),
        volumes,
        relationships,
        descriptor_state,
        fill(
            _neutral_proposal_evaluation(T),
            length(program.descriptor_plan.source_table),
        ),
        stage_buffers,
        T.(parameters),
        seed,
        replica,
        repeat,
        Int(initial_mcs),
        0,
        0,
        0,
        0,
        0,
        0,
        true,
    )
end

function program_snapshot(runtime::ProgramRuntime{T, N}) where {T, N}
    runtime.settled || throw(ArgumentError(
        "a program snapshot requires a settled complete-MCS boundary"
    ))
    relationships = runtime.relationships === nothing ?
                    nothing : copy(runtime.relationships)
    descriptor_state = copy_auxiliary_state(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
    )
    return ProgramSnapshot{
        T, N, typeof(relationships), typeof(descriptor_state),
    }(
        runtime.mcs,
        copy(runtime.ownership),
        copy(runtime.cell_kinds),
        copy(runtime.cell_generations),
        copy(runtime.volumes),
        relationships,
        descriptor_state,
    )
end

@inline function _trajectory_seed(
        seed::UInt64, replica::UInt32, repeat::UInt32
    )
    return _rng_mix64(
        xor(
            seed,
            UInt64(0x706f7474732d7631),
            UInt64(replica) * UInt64(0x9e3779b97f4a7c15),
            UInt64(repeat) * UInt64(0xbf58476d1ce4e5b9),
        )
    )
end

function initialization_bounded(
        seed::UInt64,
        replica::UInt32,
        operation::Integer,
        invocation::Integer,
        bound::Integer,
    )
    1 <= operation <= Int(_RNG_MAX_OPERATION) ||
        throw(ArgumentError("initialization operation is outside the RNG address domain"))
    invocation >= 0 ||
        throw(ArgumentError("initialization invocation must be nonnegative"))
    bound > 0 && bound <= typemax(UInt32) ||
        throw(ArgumentError("initialization draw bound is outside UInt32"))
    operation_offset, draw = divrem(invocation, Int(_RNG_MAX_DRAW) + 1)
    addressed_operation = operation + operation_offset
    addressed_operation <= Int(_RNG_MAX_OPERATION) ||
        throw(ArgumentError("initialization request exceeds the RNG address domain"))
    address = RNGAddress(
        stream = InitializationStream,
        mcs = 0,
        operation = addressed_operation,
        entity_kind = GlobalEntity,
        invocation = 0,
        draw = draw,
    )
    return Int(bounded_uint(
        Philox4x32x10V1(),
        _trajectory_seed(seed, replica, UInt32(1)),
        address,
        UInt32(bound),
    )) + 1
end

@inline function _program_address(
        stream::RNGStream, mcs::Int, operation::Integer, entity::Integer;
        subround::Integer = 0, draw::Integer = 0,
    )
    return RNGAddress(
        stream = stream,
        mcs = mcs,
        subround = subround,
        operation = operation,
        entity_kind = SiteEntity,
        entity = entity,
        draw = draw,
    )
end

@inline function _program_bounded(
        runtime::ProgramRuntime, stream::RNGStream, operation, entity, bound;
        subround = 0, draw = 0,
    )
    address = _program_address(
        stream, runtime.mcs + 1, operation, entity; subround, draw
    )
    return Int(bounded_uint(
        Philox4x32x10V1(),
        _trajectory_seed(runtime.seed, runtime.replica, runtime.repeat),
        address,
        UInt32(bound),
    )) + 1
end

@inline function _program_uniform(
        ::Type{T}, runtime::ProgramRuntime, stream::RNGStream, operation, entity;
        subround = 0, draw = 0,
    ) where {T}
    address = _program_address(
        stream, runtime.mcs + 1, operation, entity; subround, draw
    )
    return uniform_open01(
        T,
        Philox4x32x10V1(),
        _trajectory_seed(runtime.seed, runtime.replica, runtime.repeat),
        address,
    )
end

@inline function _neighbor_index(
        program::CompiledPottsProgram{T, N},
        index::CartesianIndex{N},
        offsets::Matrix{Int8},
        direction::Int,
    ) where {T, N}
    coords = Tuple(index)
    candidate = ntuple(N) do dimension
        value = coords[dimension] + Int(offsets[dimension, direction])
        if program.periodic[dimension]
            mod1(value, program.shape[dimension])
        elseif 1 <= value <= program.shape[dimension]
            value
        else
            0
        end
    end
    any(iszero, candidate) && return nothing
    return CartesianIndex(candidate)
end

@inline _owner_kind(runtime::ProgramRuntime, owner::Int32) =
    owner > 0 ? @inbounds(runtime.cell_kinds[owner]) :
    owner == 0 ? runtime.program.medium_kind : Int16(-owner)

@inline ownership_state(runtime::ProgramRuntime) = runtime.ownership
@inline owner_kind(runtime::ProgramRuntime, owner::Integer) =
    _owner_kind(runtime, Int32(owner))
@inline function relationship_degree(
        runtime::ProgramRuntime,
        relationship_slot::Integer,
        endpoint::Integer,
    )
    relationship_slot == 1 || throw(ArgumentError(
        "runtime relationship slot is outside the compiled store"
    ))
    runtime.relationships === nothing && return 0
    return _relationship_degree(runtime.relationships, Int32(endpoint))
end

function _cell_center(
        runtime::ProgramRuntime{T, N},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    totals = zeros(T, N)
    count = 0
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        coordinates = Tuple(site)
        for dimension in 1:N
            totals[dimension] += T(coordinates[dimension]) - T(0.5)
        end
        count += 1
    end
    count > 0 || return nothing
    return ntuple(dimension -> totals[dimension] / T(count), N)
end

function _cell_center(
        runtime::ProgramRuntime{T, 2},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T}
    first_total = zero(T)
    second_total = zero(T)
    count = 0
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        first_total += T(site[1]) - T(0.5)
        second_total += T(site[2]) - T(0.5)
        count += 1
    end
    count > 0 || return nothing
    inverse = inv(T(count))
    return first_total * inverse, second_total * inverse
end

function _cell_shape_statistics(
        runtime::ProgramRuntime{T, N},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    count = 0
    totals = zeros(T, N)
    quadratic = zeros(T, N, N)
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        coordinates = ntuple(
            dimension -> T(Tuple(site)[dimension]) - T(0.5), N
        )
        for row in 1:N
            totals[row] += coordinates[row]
            for column in 1:N
                quadratic[row, column] +=
                    coordinates[row] * coordinates[column]
            end
        end
        count += 1
    end
    count == 0 && return nothing
    inverse = inv(T(count))
    covariance = Matrix{T}(undef, N, N)
    for row in 1:N, column in 1:N
        covariance[row, column] =
            quadratic[row, column] * inverse -
            (totals[row] * inverse) * (totals[column] * inverse)
    end
    return count, totals .* inverse, covariance
end

function _cell_shape_statistics(
        runtime::ProgramRuntime{T, 2},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T}
    first_total = zero(T)
    second_total = zero(T)
    first_squared = zero(T)
    cross_product = zero(T)
    second_squared = zero(T)
    count = 0
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        first_coordinate = T(site[1]) - T(0.5)
        second_coordinate = T(site[2]) - T(0.5)
        first_total += first_coordinate
        second_total += second_coordinate
        first_squared += first_coordinate^2
        cross_product += first_coordinate * second_coordinate
        second_squared += second_coordinate^2
        count += 1
    end
    count == 0 && return nothing
    inverse = inv(T(count))
    first_center = first_total * inverse
    second_center = second_total * inverse
    covariance = (
        first_squared * inverse - first_center^2,
        cross_product * inverse - first_center * second_center,
        cross_product * inverse - first_center * second_center,
        second_squared * inverse - second_center^2,
    )
    return count, (first_center, second_center), covariance
end

@inline function _maximum_covariance_eigenvalue(
        ::Val{2}, covariance::NTuple{4, T}
    ) where {T}
    first_diagonal = covariance[1]
    off_diagonal = covariance[2]
    second_diagonal = covariance[4]
    discriminant = max(
        zero(T),
        (first_diagonal - second_diagonal)^2 +
        T(4) * off_diagonal^2,
    )
    return (
        first_diagonal + second_diagonal + sqrt(discriminant)
    ) / T(2)
end

_maximum_covariance_eigenvalue(::Val, covariance::AbstractMatrix) =
    maximum(eigen(Symmetric(covariance)).values)

function _cell_length(
        runtime::ProgramRuntime{T, N},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    statistics = _cell_shape_statistics(
        runtime, cell; replaced_site, replacement_owner
    )
    statistics === nothing && return zero(T)
    covariance = statistics[3]
    maximum_variance = _maximum_covariance_eigenvalue(Val(N), covariance)
    return T(4) * sqrt(max(zero(T), maximum_variance))
end

@inline function _center_distance(
        first::NTuple{2, T}, second::NTuple{2, T}
    ) where {T}
    return sqrt(
        (first[1] - second[1])^2 + (first[2] - second[2])^2
    )
end

@inline function _center_distance(first, second)
    return sqrt(sum((first[i] - second[i])^2 for i in eachindex(first)))
end

@inline _center_distance(::Nothing, second) = Inf
@inline _center_distance(first, ::Nothing) = Inf
@inline _center_distance(::Nothing, ::Nothing) = Inf

function _commit_copy!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
        context,
    ) where {T, N}
    @inbounds runtime.ownership[target] = new_owner
    old_owner > 0 && (@inbounds runtime.volumes[old_owner] -= 1)
    new_owner > 0 && (@inbounds runtime.volumes[new_owner] += 1)
    old_owner == new_owner || _clear_ownership_changed_state!(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
        target,
    )
    _apply_accepted_copy_stage!(runtime, context)
    return nothing
end

struct _ProposalEvaluationContext{R, I}
    runtime::R
    source::I
    target::I
    old_owner::Int32
    new_owner::Int32
    attempt::Int
    subround::Int
end

@inline evaluator_parameters(context::_ProposalEvaluationContext) =
    context.runtime.parameters
@inline _compiled_evaluator_parameters(context::_ProposalEvaluationContext) =
    context.runtime.parameters
@inline proposal_source_site(context::_ProposalEvaluationContext) =
    context.source
@inline proposal_target_site(context::_ProposalEvaluationContext) =
    context.target
@inline proposal_source_owner(context::_ProposalEvaluationContext) =
    context.new_owner
@inline proposal_target_owner(context::_ProposalEvaluationContext) =
    context.old_owner
@inline proposal_source_kind(context::_ProposalEvaluationContext) =
    _owner_kind(context.runtime, context.new_owner)
@inline proposal_target_kind(context::_ProposalEvaluationContext) =
    _owner_kind(context.runtime, context.old_owner)
@inline owner_kind(
    context::_ProposalEvaluationContext, owner::Integer
) = _owner_kind(context.runtime, Int32(owner))
@inline proposal_site_owner(
    context::_ProposalEvaluationContext,
    site,
) = @inbounds context.runtime.ownership[site]

@inline function proposal_relation_count(
        context::_ProposalEvaluationContext,
        relation_handle::Integer,
    )
    _, count = _contact_domain_columns(
        context.runtime.program.descriptor_plan.domain_resources,
        Int32(relation_handle),
    )
    return Int(count)
end

@inline function proposal_relation_neighbor_site(
        context::_ProposalEvaluationContext,
        relation_handle::Integer,
        center,
        direction::Integer,
    )
    resources = context.runtime.program.descriptor_plan.domain_resources
    start, count = _contact_domain_columns(
        resources, Int32(relation_handle)
    )
    1 <= direction <= count || return nothing
    column = start + Int32(direction - 1)
    return _neighbor_index(
        context.runtime.program,
        center,
        resources.contact_offsets,
        Int(column),
    )
end

@inline function proposal_relation_neighbor_owner(
        context::_ProposalEvaluationContext{R, CartesianIndex{N}},
        relation_handle::Integer,
        offset::NTuple{N, <:Integer},
    ) where {R, N}
    resources = context.runtime.program.descriptor_plan.domain_resources
    start, count = _contact_domain_columns(resources, Int32(relation_handle))
    column = Int32(0)
    for candidate in start:(start + count - 1)
        matches = true
        for dimension in 1:N
            matches &= @inbounds(resources.contact_offsets[dimension, candidate]) ==
                       offset[dimension]
        end
        if matches
            column = candidate
            break
        end
    end
    iszero(column) && return typemin(Int32)
    neighbor = _neighbor_index(
        context.runtime.program,
        context.target,
        resources.contact_offsets,
        Int(column),
    )
    neighbor === nothing && return Int32(0)
    return @inbounds context.runtime.ownership[neighbor]
end

@inline function _compiled_context_value(
        operation::ContextOperation{Identity},
        context::_ProposalEvaluationContext,
    ) where {Identity}
    return invoke(
        context_value,
        Tuple{ContextOperation{Identity}, _ProposalEvaluationContext},
        operation,
        context,
    )
end

@inline function _compiled_resource_operation(
        operation::ResourceOperation{Identity},
        arguments::Tuple,
        context::_ProposalEvaluationContext,
    ) where {Identity}
    return invoke(
        apply_resource_operation,
        Tuple{ResourceOperation{Identity}, Tuple, _ProposalEvaluationContext},
        operation,
        arguments,
        context,
    )
end

@inline context_value(
    ::ContextOperation{:source_site},
    context::_ProposalEvaluationContext,
) = context.source
@inline context_value(
    ::ContextOperation{:target_site},
    context::_ProposalEvaluationContext,
) = context.target
@inline context_value(
    ::ContextOperation{:source_cell},
    context::_ProposalEvaluationContext,
) = context.new_owner
@inline context_value(
    ::ContextOperation{:target_cell},
    context::_ProposalEvaluationContext,
) = context.old_owner
@inline context_value(
    ::ContextOperation{:source_kind},
    context::_ProposalEvaluationContext,
) = _owner_kind(context.runtime, context.new_owner)
@inline context_value(
    ::ContextOperation{:target_kind},
    context::_ProposalEvaluationContext,
) = _owner_kind(context.runtime, context.old_owner)
@inline context_value(
    ::ContextOperation{:is_extension},
    context::_ProposalEvaluationContext,
) = context.old_owner <= 0 && context.new_owner > 0
@inline context_value(
    ::ContextOperation{:is_retraction},
    context::_ProposalEvaluationContext,
) = context.old_owner > 0 && context.new_owner <= 0

@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume},
        arguments,
        context::_ProposalEvaluationContext,
    )
    owner = Int(only(arguments))
    owner <= 0 && return 0
    return @inbounds context.runtime.volumes[owner]
end

@inline function apply_resource_operation(
        ::ResourceOperation{:field_value},
        arguments,
        context::_ProposalEvaluationContext,
    )
    handle = first(arguments)
    site = last(arguments)
    return state_value(context, handle, site)
end

@inline function apply_resource_operation(
        ::ResourceOperation{:degree},
        arguments,
        context::_ProposalEvaluationContext,
    )
    relationship_handle = Int32(first(arguments))
    owner = Int32(last(arguments))
    owner <= 0 && return 0
    slot = _relationship_domain_slot(
        context.runtime.program.descriptor_plan.domain_resources,
        relationship_handle,
    )
    slot == 1 || throw(ArgumentError(
        "V1 runtime contains one relationship storage slot"
    ))
    state = context.runtime.relationships
    state === nothing && return 0
    return _relationship_degree(state, owner)
end

@inline function apply_resource_operation(
        ::ResourceOperation{:linked},
        arguments,
        context::_ProposalEvaluationContext,
    )
    relationship_handle = Int32(arguments[1])
    endpoint_a = Int32(arguments[2])
    endpoint_b = Int32(arguments[3])
    (endpoint_a <= 0 || endpoint_b <= 0) && return false
    slot = _relationship_domain_slot(
        context.runtime.program.descriptor_plan.domain_resources,
        relationship_handle,
    )
    slot == 1 || throw(ArgumentError(
        "V1 runtime contains one relationship storage slot"
    ))
    state = context.runtime.relationships
    state === nothing && return false
    return _relationship_edge(state, endpoint_a, endpoint_b) !== nothing
end

@inline function _proposal_endpoint_pair(arguments, context)
    endpoint_a = Int32(first(arguments))
    endpoint_b = Int32(last(arguments))
    declared = _canonical_endpoints(endpoint_a, endpoint_b)
    transition = _canonical_endpoints(context.new_owner, context.old_owner)
    return endpoint_a > 0 && endpoint_b > 0 &&
           endpoint_a != endpoint_b && declared == transition
end

@inline apply_resource_operation(
    ::ResourceOperation{:new_contact}, arguments,
    context::_ProposalEvaluationContext,
) = _proposal_endpoint_pair(arguments, context)

@inline apply_resource_operation(
    ::ResourceOperation{:lost_contact}, arguments,
    context::_ProposalEvaluationContext,
) = _proposal_endpoint_pair(arguments, context)

@inline function apply_resource_operation(
        ::ResourceOperation{:draw},
        arguments,
        context::_ProposalEvaluationContext,
    )
    T = eltype(context.runtime.parameters)
    family = Int(arguments[1])
    first_parameter = T(arguments[2])
    second_parameter = T(arguments[3])
    operation = UInt16(arguments[4])
    first_uniform = _program_uniform(
        T,
        context.runtime,
        ExplicitProposalDrawStream,
        operation,
        context.attempt;
        subround = context.subround,
        draw = 0,
    )
    if family == 1
        return first_uniform < first_parameter
    elseif family == 2
        return muladd(
            first_uniform,
            second_parameter - first_parameter,
            first_parameter,
        )
    elseif family == 3
        iszero(second_parameter) && return first_parameter
        second_uniform = _program_uniform(
            T,
            context.runtime,
            ExplicitProposalDrawStream,
            operation,
            context.attempt;
            subround = context.subround,
            draw = 1,
        )
        normal = sqrt(-T(2) * log(first_uniform)) *
                 cos(T(2pi) * second_uniform)
        return muladd(second_parameter, normal, first_parameter)
    end
    return T(NaN)
end

@inline function state_value(
        context::_ProposalEvaluationContext,
        handle::StateHandle,
        site,
    )
    return @inbounds state_block(
        context.runtime.descriptor_state, handle
    ).values[site]
end

@inline stage_site(
    ::ProposalTargetStageSite,
    context::_ProposalEvaluationContext,
) = context.target

struct _SiteStageEvaluationContext{R, I}
    runtime::R
    site::I
end

struct _RelationshipStageEvaluationContext{R}
    runtime::R
    relationship_slot::Int32
    edge::Int32
end

@inline _compiled_evaluator_parameters(
    context::_RelationshipStageEvaluationContext
) = context.runtime.parameters
@inline evaluator_parameters(
    context::_RelationshipStageEvaluationContext
) = context.runtime.parameters
@inline context_value(
    ::ContextOperation{:energy_anchor_relationship},
    context::_RelationshipStageEvaluationContext,
) = context.edge
@inline function _compiled_context_value(
        operation::ContextOperation{Identity},
        context::_RelationshipStageEvaluationContext,
    ) where {Identity}
    return invoke(
        context_value,
        Tuple{
            ContextOperation{Identity},
            _RelationshipStageEvaluationContext,
        },
        operation,
        context,
    )
end
@inline function _relationship_stage_state(
        context::_RelationshipStageEvaluationContext,
    )
    context.relationship_slot == 1 || throw(ArgumentError(
        "V1 runtime contains one relationship storage slot"
    ))
    state = context.runtime.relationships
    state === nothing && throw(ArgumentError(
        "relationship stage references absent runtime storage"
    ))
    return state
end
@inline function apply_resource_operation(
        ::ResourceOperation{:endpoint_a},
        arguments,
        context::_RelationshipStageEvaluationContext,
    )
    state = _relationship_stage_state(context)
    return @inbounds state.endpoint_a[Int(only(arguments))]
end
@inline function apply_resource_operation(
        ::ResourceOperation{:endpoint_b},
        arguments,
        context::_RelationshipStageEvaluationContext,
    )
    state = _relationship_stage_state(context)
    return @inbounds state.endpoint_b[Int(only(arguments))]
end
@inline function apply_resource_operation(
        ::ResourceOperation{:edge_payload},
        arguments,
        context::_RelationshipStageEvaluationContext,
    )
    return relationship_payload(
        _relationship_stage_state(context),
        Int(first(arguments)),
        Int(last(arguments)),
    )
end
@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume},
        arguments,
        context::_RelationshipStageEvaluationContext,
    )
    owner = Int(only(arguments))
    owner <= 0 && return 0
    return @inbounds context.runtime.volumes[owner]
end
@inline apply_resource_operation(
    ::ResourceOperation{:unwrapped_center},
    arguments,
    context::_RelationshipStageEvaluationContext,
) = _cell_center(context.runtime, Int32(only(arguments)))
@inline apply_resource_operation(
    ::ResourceOperation{:cell_center},
    arguments,
    context::_RelationshipStageEvaluationContext,
) = _cell_center(context.runtime, Int32(only(arguments)))
@inline apply_resource_operation(
    ::ResourceOperation{:distance},
    arguments,
    ::_RelationshipStageEvaluationContext,
) = _center_distance(first(arguments), last(arguments))
@inline function _compiled_resource_operation(
        operation::ResourceOperation{Identity},
        arguments::Tuple,
        context::_RelationshipStageEvaluationContext,
    ) where {Identity}
    return invoke(
        apply_resource_operation,
        Tuple{
            ResourceOperation{Identity},
            Any,
            _RelationshipStageEvaluationContext,
        },
        operation,
        arguments,
        context,
    )
end
@inline function state_value(
        context::_RelationshipStageEvaluationContext,
        handle::StateHandle,
        site,
    )
    return @inbounds state_block(
        context.runtime.descriptor_state, handle
    ).values[site]
end

@inline _compiled_evaluator_parameters(
    context::_SiteStageEvaluationContext
) = context.runtime.parameters
@inline evaluator_parameters(context::_SiteStageEvaluationContext) =
    context.runtime.parameters
@inline stage_site(
    ::IterationStageSite,
    context::_SiteStageEvaluationContext,
) = context.site
@inline function state_value(
        context::_SiteStageEvaluationContext,
        handle::StateHandle,
        site,
    )
    return @inbounds state_block(
        context.runtime.descriptor_state, handle
    ).values[site]
end
@inline site_owner(
    context::_SiteStageEvaluationContext, site
) = @inbounds context.runtime.ownership[site]
@inline owner_kind(
    context::_SiteStageEvaluationContext, owner::Integer
) = _owner_kind(context.runtime, Int32(owner))
@inline function relation_count(
        context::_SiteStageEvaluationContext,
        relation_handle::Integer,
    )
    _, count = _contact_domain_columns(
        context.runtime.program.descriptor_plan.domain_resources,
        Int32(relation_handle),
    )
    return Int(count)
end
@inline function relation_neighbor_site(
        context::_SiteStageEvaluationContext,
        relation_handle::Integer,
        center,
        direction::Integer,
    )
    resources = context.runtime.program.descriptor_plan.domain_resources
    start, count = _contact_domain_columns(
        resources, Int32(relation_handle)
    )
    1 <= direction <= count || return nothing
    return _neighbor_index(
        context.runtime.program,
        center,
        resources.contact_offsets,
        Int(start + Int32(direction - 1)),
    )
end

@inline function descriptor_emit_requests!(
        requests::AbstractVector{StageEvaluation{T}},
        descriptor::CompiledStageDescriptor{
            C, V, E, AcceptedCopyStage,
        },
        context::_ProposalEvaluationContext,
    ) where {T <: AbstractFloat, C, V, E}
    condition = _compiled_evaluate_static(descriptor.condition, context)
    condition isa Bool || throw(ArgumentError(
        "accepted-copy stage condition must return Bool"
    ))
    value = condition ? T(_compiled_evaluate_static(
        descriptor.value, context
    )) : zero(T)
    isfinite(value) || throw(DomainError(
        value, "accepted-copy stage value must be finite"
    ))
    @inbounds requests[Int(descriptor.buffer_slot)] =
        StageEvaluation(condition, value)
    return requests
end

@inline function _relationship_create_request(
        effect::RelationshipCreateEffect,
        context::_ProposalEvaluationContext,
    )
    endpoint_a = Int32(_compiled_evaluate_static(
        effect.endpoint_a, context
    ))
    endpoint_b = Int32(_compiled_evaluate_static(
        effect.endpoint_b, context
    ))
    payload = map(
        evaluator -> _compiled_evaluate_static(evaluator, context),
        effect.payload,
    )
    generation_a = 1 <= endpoint_a <= length(context.runtime.cell_generations) ?
                   @inbounds(context.runtime.cell_generations[endpoint_a]) :
                   UInt32(0)
    generation_b = 1 <= endpoint_b <= length(context.runtime.cell_generations) ?
                   @inbounds(context.runtime.cell_generations[endpoint_b]) :
                   UInt32(0)
    return CreateRelationshipRequest(
        endpoint_a,
        endpoint_b,
        payload;
        generation_a,
        generation_b,
        priority = effect.priority,
        identity = context.attempt,
    )
end

@inline function descriptor_emit_requests!(
        requests::AbstractVector{StageEvaluation{T}},
        descriptor::CompiledStageDescriptor{
            C, V, E, AcceptedCopyStage,
        },
        context::_ProposalEvaluationContext,
    ) where {
        T <: AbstractFloat,
        C,
        V,
        E <: RelationshipCreateEffect,
    }
    condition = _compiled_evaluate_static(descriptor.condition, context)
    condition isa Bool || throw(ArgumentError(
        "accepted-copy relationship condition must return Bool"
    ))
    enabled = false
    if condition
        effect = descriptor.effect
        effect.relationship_slot == 1 || throw(ArgumentError(
            "V1 runtime contains one relationship storage slot"
        ))
        state = context.runtime.relationships
        schema = context.runtime.program.relationships
        state === nothing || schema === nothing ? throw(ArgumentError(
            "relationship effect references absent runtime storage"
        )) : nothing
        request = _relationship_create_request(effect, context)
        enabled = validate_relationship_request(
            state,
            context.runtime.cell_kinds,
            context.runtime.cell_generations,
            schema,
            request,
        )
    end
    @inbounds requests[Int(descriptor.buffer_slot)] =
        StageEvaluation(enabled, zero(T))
    return requests
end

@inline function descriptor_emit_requests!(
        scratch::AbstractArray{T},
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
        context::_SiteStageEvaluationContext,
    ) where {T <: AbstractFloat, C, V, E}
    condition = _compiled_evaluate_static(descriptor.condition, context)
    condition isa Bool || throw(ArgumentError(
        "after-MCS stage condition must return Bool"
    ))
    value = condition ? T(_compiled_evaluate_static(
        descriptor.value, context
    )) : T(state_value(
        context, descriptor.effect.target, context.site
    ))
    isfinite(value) || throw(DomainError(
        value, "after-MCS stage value must be finite"
    ))
    @inbounds scratch[context.site] = value
    return scratch
end

@inline function descriptor_apply_stage!(
        descriptor::CompiledStageDescriptor,
        request::StageEvaluation,
        state::AuxiliaryState,
        site,
    )
    request.enabled || return state
    effect = descriptor.effect
    effect isa SiteAssignmentEffect || throw(ArgumentError(
        "unsupported compiled accepted-copy effect"
    ))
    @inbounds state_block(state, effect.target).values[site] = request.value
    return state
end

@inline function descriptor_apply_stage!(
        descriptor::CompiledStageDescriptor{
            C, V, E, AcceptedCopyStage,
        },
        request::StageEvaluation,
        runtime::ProgramRuntime,
        context::_ProposalEvaluationContext,
    ) where {C, V, E <: SiteAssignmentEffect}
    return descriptor_apply_stage!(
        descriptor,
        request,
        runtime.descriptor_state,
        context.target,
    )
end

@inline function descriptor_apply_stage!(
        descriptor::CompiledStageDescriptor{
            C, V, E, AcceptedCopyStage,
        },
        evaluation::StageEvaluation,
        runtime::ProgramRuntime,
        context::_ProposalEvaluationContext,
    ) where {C, V, E <: RelationshipCreateEffect}
    evaluation.enabled || return runtime
    request = _relationship_create_request(descriptor.effect, context)
    apply_validated_relationship_request!(runtime.relationships, request)
    return runtime
end

@inline function descriptor_apply_stage!(
        descriptor::CompiledStageDescriptor,
        scratch::AbstractArray,
        state::AuxiliaryState,
    )
    effect = descriptor.effect
    effect isa Union{SiteAssignmentEffect, IteratedSiteAssignmentEffect} ||
        throw(ArgumentError(
        "unsupported compiled after-MCS effect"
    ))
    copyto!(state_block(state, effect.target).values, scratch)
    return state
end

@inline _emit_accepted_copy_groups!(
    requests, ::Tuple{}, context
) = requests
@inline function _emit_accepted_copy_groups!(
        requests,
        groups::Tuple,
        context,
    )
    for descriptor in first(groups).instances
        descriptor_emit_requests!(requests, descriptor, context)
    end
    return _emit_accepted_copy_groups!(
        requests, Base.tail(groups), context
    )
end

@inline _apply_accepted_copy_groups!(
    runtime, ::Tuple{}, requests, context
) = runtime
@inline function _apply_accepted_copy_groups!(
        runtime,
        groups::Tuple,
        requests,
        context,
    )
    for descriptor in first(groups).instances
        request = @inbounds requests[Int(descriptor.buffer_slot)]
        descriptor_apply_stage!(
            descriptor, request, runtime, context
        )
    end
    return _apply_accepted_copy_groups!(
        runtime, Base.tail(groups), requests, context
    )
end

@inline function _emit_accepted_copy_stage!(
        runtime::ProgramRuntime,
        context::_ProposalEvaluationContext,
    )
    return _emit_accepted_copy_groups!(
        runtime.stage_buffers.accepted_copy,
        runtime.program.stage_plan.accepted_copy,
        context,
    )
end

@inline function _apply_accepted_copy_stage!(
        runtime::ProgramRuntime,
        context::_ProposalEvaluationContext,
    )
    _apply_accepted_copy_groups!(
        runtime,
        runtime.program.stage_plan.accepted_copy,
        runtime.stage_buffers.accepted_copy,
        context,
    )
    return nothing
end

function _clear_ownership_changed_state!(
        layout::StateLayout,
        state::AuxiliaryState,
        site,
    )
    for entry in layout.entries
        lifecycle = entry.schema.lifecycle
        declared = lifecycle isa NamedTuple && haskey(lifecycle, :declared) ?
                   lifecycle.declared : nothing
        declared === :ClearOnOwnershipChange || continue
        values = state_block(state, entry.handle).values
        @inbounds values[site] = zero(eltype(values))
    end
    return state
end

function _emit_after_mcs_descriptor!(
        runtime,
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: SiteAssignmentEffect}
    scratch = @inbounds runtime.stage_buffers.after_mcs[
        Int(descriptor.buffer_slot)
    ]
    for site in CartesianIndices(runtime.ownership)
        descriptor_emit_requests!(
            scratch,
            descriptor,
            _SiteStageEvaluationContext(runtime, site),
        )
    end
    return runtime
end

@inline function _emit_after_mcs_descriptor!(
        runtime,
        ::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: ShiftAppendEffect}
    return runtime
end

@inline function _emit_after_mcs_descriptor!(
        runtime,
        ::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: IteratedSiteAssignmentEffect}
    return runtime
end

function _emit_after_mcs_descriptor!(
        runtime,
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: RelationshipRemoveEffect}
    effect = descriptor.effect
    effect.relationship_slot == 1 || throw(ArgumentError(
        "V1 runtime contains one relationship storage slot"
    ))
    state = runtime.relationships
    state === nothing && throw(ArgumentError(
        "relationship stage references absent runtime storage"
    ))
    scratch = @inbounds runtime.stage_buffers.relationship_after_mcs[
        Int(descriptor.buffer_slot)
    ]
    fill!(scratch, false)
    for edge in eachindex(state.active)
        @inbounds state.active[edge] || continue
        condition = _compiled_evaluate_static(
            descriptor.condition,
            _RelationshipStageEvaluationContext(
                runtime, effect.relationship_slot, Int32(edge)
            ),
        )
        condition isa Bool || throw(ArgumentError(
            "relationship lifecycle condition must return Bool"
        ))
        @inbounds scratch[edge] = condition
    end
    return runtime
end

function _emit_after_mcs_groups!(runtime, ::Tuple{})
    return runtime
end
function _emit_after_mcs_groups!(runtime, groups::Tuple)
    for descriptor in first(groups).instances
        _emit_after_mcs_descriptor!(runtime, descriptor)
    end
    return _emit_after_mcs_groups!(runtime, Base.tail(groups))
end

function _apply_after_mcs_descriptor!(
        runtime,
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: SiteAssignmentEffect}
    scratch = @inbounds runtime.stage_buffers.after_mcs[
        Int(descriptor.buffer_slot)
    ]
    descriptor_apply_stage!(descriptor, scratch, runtime.descriptor_state)
    return runtime
end

function _apply_after_mcs_descriptor!(
        runtime,
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: RelationshipRemoveEffect}
    state = runtime.relationships
    schema = runtime.program.relationships
    state === nothing || schema === nothing ? throw(ArgumentError(
        "relationship stage references absent runtime storage"
    )) : nothing
    scratch = @inbounds runtime.stage_buffers.relationship_after_mcs[
        Int(descriptor.buffer_slot)
    ]
    for edge in eachindex(scratch)
        @inbounds scratch[edge] || continue
        @inbounds state.active[edge] || continue
        request = RemoveRelationshipRequest(
            edge;
            identity = UInt64(runtime.mcs + 1) << 32 | UInt64(edge),
        )
        validate_relationship_request(
            state,
            runtime.cell_kinds,
            runtime.cell_generations,
            schema,
            request,
        )
        apply_validated_relationship_request!(state, request)
    end
    return runtime
end

function _apply_after_mcs_descriptor!(
        runtime,
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: IteratedSiteAssignmentEffect}
    scratch = @inbounds runtime.stage_buffers.after_mcs[
        Int(descriptor.buffer_slot)
    ]
    for _ in 1:Int(descriptor.effect.iterations)
        for site in CartesianIndices(runtime.ownership)
            descriptor_emit_requests!(
                scratch,
                descriptor,
                _SiteStageEvaluationContext(runtime, site),
            )
        end
        descriptor_apply_stage!(
            descriptor, scratch, runtime.descriptor_state
        )
    end
    return runtime
end

function _apply_after_mcs_descriptor!(
        runtime,
        descriptor::CompiledStageDescriptor{
            C, V, E, AfterMCSStage,
        },
    ) where {C, V, E <: ShiftAppendEffect}
    effect = descriptor.effect
    target = state_block(runtime.descriptor_state, effect.target).values
    source = state_block(runtime.descriptor_state, effect.source).values
    axis = Int(effect.axis)
    1 <= axis <= ndims(target) || error(
        "compiled shift-append axis is outside its target block"
    )
    size(target)[1:(axis - 1)] == size(source) || error(
        "compiled shift-append source shape is incompatible"
    )
    size(target)[(axis + 1):end] == () || error(
        "compiled shift-append target has trailing dimensions"
    )
    depth = size(target, axis)
    for index in 1:(depth - 1)
        copyto!(
            selectdim(target, axis, index),
            selectdim(target, axis, index + 1),
        )
    end
    copyto!(selectdim(target, axis, depth), source)
    return runtime
end

function _apply_after_mcs_groups!(runtime, ::Tuple{})
    return runtime
end
function _apply_after_mcs_groups!(runtime, groups::Tuple)
    for descriptor in first(groups).instances
        _apply_after_mcs_descriptor!(runtime, descriptor)
    end
    return _apply_after_mcs_groups!(runtime, Base.tail(groups))
end

function _execute_after_mcs_stage!(runtime::ProgramRuntime)
    _emit_after_mcs_groups!(runtime, runtime.program.stage_plan.after_mcs)
    _apply_after_mcs_groups!(runtime, runtime.program.stage_plan.after_mcs)
    return nothing
end

"""Log acceptance ratio for the conventional descriptor-driven V1 law."""
@inline function proposal_log_acceptance_ratio(
        evaluation::ProposalEvaluation{T},
        temperature::Real,
    ) where {T <: AbstractFloat}
    converted_temperature = T(temperature)
    isfinite(converted_temperature) && converted_temperature >= zero(T) ||
        throw(ArgumentError(
            "acceptance temperature must be finite and nonnegative"
        ))
    all(isfinite, (
        evaluation.delta_h,
        evaluation.drive_energy,
        evaluation.drive_log_bias,
        evaluation.kinetic_modifier,
    )) || throw(ArgumentError(
        "proposal acceptance inputs must be finite"
    ))
    evaluation.constraints_allowed || return -T(Inf)
    if iszero(converted_temperature)
        iszero(evaluation.drive_log_bias) &&
            iszero(evaluation.kinetic_modifier) || throw(ArgumentError(
                "nonconservative drives and proposal modifiers require positive temperature"
            ))
        effective_energy = evaluation.delta_h + evaluation.drive_energy
        return effective_energy <= zero(T) ? zero(T) : -T(Inf)
    end
    return -(evaluation.delta_h + evaluation.drive_energy) /
           converted_temperature +
           evaluation.drive_log_bias + evaluation.kinetic_modifier
end

"""Exact conventional acceptance probability for a structured proposal evaluation."""
@inline function proposal_acceptance_probability(
        evaluation::ProposalEvaluation{T}, temperature::Real
    ) where {T <: AbstractFloat}
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    return log_ratio >= zero(T) ? one(T) :
           isfinite(log_ratio) ? exp(log_ratio) : zero(T)
end

"""Apply the V1 strict-threshold decision to one pre-addressed uniform draw."""
@inline function proposal_acceptance_decision(
        evaluation::ProposalEvaluation{T},
        temperature::Real,
        draw::Real,
    ) where {T <: AbstractFloat}
    converted_draw = T(draw)
    zero(T) < converted_draw < one(T) || throw(ArgumentError(
        "acceptance draws must lie strictly inside (0, 1)"
    ))
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    return log_ratio >= zero(T) ||
           (isfinite(log_ratio) && log(converted_draw) < log_ratio)
end

@inline function _proposal_acceptance_draw(
        runtime::ProgramRuntime{T},
        attempt_identity::Int,
        subround::Int,
        ::Val{:addressed},
        scripted::T,
    ) where {T}
    return _program_uniform(
        T,
        runtime,
        AcceptanceStream,
        3,
        attempt_identity;
        subround,
    )
end

@inline _proposal_acceptance_draw(
    runtime::ProgramRuntime{T},
    attempt_identity::Int,
    subround::Int,
    ::Val{:scripted},
    scripted::T,
) where {T} = scripted

function _attempt_selected!(
        runtime::ProgramRuntime{T, N},
        source::CartesianIndex{N},
        target::CartesianIndex{N},
        attempt_identity::Int,
        subround::Int,
        draw_mode::Val,
        scripted_draw::T,
    ) where {T, N}
    program = runtime.program
    old_owner = @inbounds runtime.ownership[target]
    new_owner = @inbounds runtime.ownership[source]
    old_owner == new_owner && (runtime.null_attempts += 1; return false)

    context = _ProposalEvaluationContext(
        runtime,
        source,
        target,
        old_owner,
        new_owner,
        attempt_identity,
        subround,
    )
    evaluate_proposal_contributions!(
        runtime.proposal_contributions,
        program.descriptor_plan,
        context,
    )
    evaluation = fold_proposal_contributions(
        program.descriptor_plan, runtime.proposal_contributions
    )
    if !evaluation.constraints_allowed
        runtime.constraint_rejections += 1
        runtime.rejected += 1
        return false
    end
    temperature = compiled_scalar_value(program.temperature, runtime.parameters)
    log_ratio = proposal_log_acceptance_ratio(evaluation, temperature)
    accepted = log_ratio >= zero(T)
    if !accepted && isfinite(log_ratio)
        draw = _proposal_acceptance_draw(
            runtime,
            attempt_identity,
            subround,
            draw_mode,
            scripted_draw,
        )
        accepted = proposal_acceptance_decision(
            evaluation, temperature, draw
        )
    end
    if accepted
        _emit_accepted_copy_stage!(runtime, context)
        _commit_copy!(
            runtime,
            target,
            old_owner,
            new_owner,
            context,
        )
        runtime.accepted += 1
        return true
    end
    runtime.energy_rejections += 1
    runtime.rejected += 1
    return false
end

function _attempt!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        attempt_identity::Int,
        subround::Int,
    ) where {T, N}
    program = runtime.program
    direction = _program_bounded(
        runtime,
        ProposalDirectionStream,
        2,
        attempt_identity,
        size(program.proposal_offsets, 2);
        subround,
    )
    source = _neighbor_index(program, target, program.proposal_offsets, direction)
    source === nothing && (runtime.null_attempts += 1; return false)
    return _attempt_selected!(
        runtime,
        source,
        target,
        attempt_identity,
        subround,
        Val(:addressed),
        zero(T),
    )
end

function _advance_sequential!(runtime::ProgramRuntime)
    site_count = length(runtime.ownership)
    attempts = site_count * Int(runtime.program.attempts_per_site)
    indices = CartesianIndices(runtime.ownership)
    for attempt in 1:attempts
        target_linear = _program_bounded(
            runtime, ProposalRecipientStream, 1, attempt, site_count
        )
        _attempt!(runtime, indices[target_linear], attempt, 0)
    end
    return nothing
end

function _advance_checkerboard!(runtime::ProgramRuntime{T, N}) where {T, N}
    colors = 1 << N
    attempt_identity = 0
    for color in 0:(colors - 1)
        for target in CartesianIndices(runtime.ownership)
            encoded = 0
            coordinates = Tuple(target)
            for dimension in 1:N
                encoded |= ((coordinates[dimension] - 1) & 1) << (dimension - 1)
            end
            encoded == color || continue
            for _ in 1:Int(runtime.program.attempts_per_site)
                attempt_identity += 1
                _attempt!(runtime, target, attempt_identity, color)
            end
        end
    end
    return nothing
end

function _clear_retired_cell_state!(
        layout::StateLayout,
        state::AuxiliaryState,
        cell::Integer,
    )
    for entry in layout.entries
        entry.schema.domain === :cell || continue
        values = state_block(state, entry.handle).values
        1 <= cell <= length(values) || error(
            "compiled cell-state block is incompatible with the cell table"
        )
        @inbounds values[cell] = zero(eltype(values))
    end
    return state
end

function _retire_extinct_cells!(runtime::ProgramRuntime)
    for cell in eachindex(runtime.cell_kinds)
        @inbounds runtime.cell_kinds[cell] == 0 && continue
        @inbounds runtime.volumes[cell] == 0 || continue
        @inbounds runtime.cell_kinds[cell] = 0
        runtime.retired_cells += 1
        _clear_retired_cell_state!(
            runtime.program.descriptor_plan.state_layout,
            runtime.descriptor_state,
            cell,
        )
    end
    return nothing
end

function _after_mcs!(runtime::ProgramRuntime{T, N}) where {T, N}
    _retire_extinct_cells!(runtime)
    _execute_after_mcs_stage!(runtime)
    return nothing
end

function advance_mcs!(runtime::ProgramRuntime)
    runtime.settled ||
        throw(ArgumentError("cannot advance an unsettled program runtime"))
    runtime.settled = false
    if runtime.program.engine isa SequentialProgramEngine
        _advance_sequential!(runtime)
    elseif runtime.program.engine isa CheckerboardProgramEngine
        _advance_checkerboard!(runtime)
    else
        error("unreachable program engine")
    end
    _after_mcs!(runtime)
    runtime.mcs += 1
    runtime.settled = true
    return runtime
end

function update_program_parameters!(
        runtime::ProgramRuntime{T}, parameters::AbstractVector{<:Real}
    ) where {T}
    runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    length(parameters) == length(runtime.parameters) ||
        throw(ArgumentError("runtime parameter buffer has the wrong length"))
    replacement = T.(parameters)
    all(isfinite, replacement) ||
        throw(ArgumentError("runtime parameters must be finite"))
    copyto!(runtime.parameters, replacement)
    return runtime
end

program_execution_report(program::CompiledPottsProgram) = (
    engine = nameof(typeof(program.engine)),
    backend = nameof(typeof(program.backend)),
    scalar_type = eltype(program.parameter_defaults),
    shape = program.shape,
    attempts_per_site = program.attempts_per_site,
    rng = :Philox4x32x10V1,
    numerical_policy = (
        math = :accurate,
        reductions = :deterministic,
        bounds = :checked,
    ),
)

program_capability_report(program::CompiledPottsProgram) = (
    sequential = program.engine isa SequentialProgramEngine,
    checkerboard = program.engine isa CheckerboardProgramEngine,
    cpu = program.backend isa CPUProgramBackend,
    state_domains = Tuple(unique(
        entry.schema.domain
        for entry in program.descriptor_plan.state_layout.entries
    )),
    stage_effects = Tuple(unique(
        nameof(typeof(descriptor.effect))
        for groups in (
            program.stage_plan.accepted_copy,
            program.stage_plan.after_mcs,
        )
        for group in groups
        for descriptor in group.instances
    )),
    relationships = program.relationships !== nothing,
)
