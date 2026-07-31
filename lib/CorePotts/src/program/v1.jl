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

# Concrete, unit-free expression nodes produced by the PottsToolkit compiler.
# These values deliberately contain neither Symbolics objects nor executable
# host closures. Operation identity is a type parameter so warmed proposal
# evaluation remains fully dispatch-resolved.
abstract type AbstractProgramExpression end

struct ProgramLiteral{T} <: AbstractProgramExpression
    value::T
end

struct ProgramScalar{T <: AbstractFloat} <: AbstractProgramExpression
    value::CompiledScalar{T}
end

struct ProgramCall{F, A <: Tuple} <: AbstractProgramExpression
    arguments::A
end

ProgramCall(::Val{F}, arguments...) where {F} =
    ProgramCall{F, typeof(arguments)}(arguments)

struct ProgramDraw{F, A, B} <: AbstractProgramExpression
    first_parameter::A
    second_parameter::B
    operation::UInt16
end

function ProgramDraw(
        ::Val{F}, first_parameter, second_parameter, operation::Integer
    ) where {F}
    1 <= operation <= _RNG_MAX_OPERATION ||
        throw(ArgumentError("explicit draw operation is outside the RNG address domain"))
    F in (:bernoulli, :uniform, :normal) ||
        throw(ArgumentError("unsupported scalar proposal draw family `$F`"))
    return ProgramDraw{F, typeof(first_parameter), typeof(second_parameter)}(
        first_parameter, second_parameter, UInt16(operation)
    )
end

struct CompiledProposalTerm{E <: AbstractProgramExpression}
    expression::E
end

struct CompiledActivityPlan{T <: AbstractFloat}
    kind::Int16
    maximum::CompiledScalar{T}
    strength::CompiledScalar{T}
    neighborhood_offsets::Matrix{Int8}
    activate_extensions::Bool
    decay_per_mcs::T
end

struct CompiledFieldPlan{T <: AbstractFloat}
    enabled::Bool
    diffusion::CompiledScalar{T}
    decay::CompiledScalar{T}
    secretion::CompiledScalar{T}
    source_kind::Int16
    chemotaxis_kind::Int16
    chemotaxis_strength::CompiledScalar{T}
    stencil_offsets::Matrix{Int8}
    substeps::Int32
    duration_per_mcs::T
end

struct CompiledHistoryPlan
    depth::Int32
    source::Symbol
    function CompiledHistoryPlan(depth::Integer, source::Symbol)
        depth > 0 || throw(ArgumentError("history depth must be positive"))
        source === :activity || throw(ArgumentError(
            "V1 histories currently admit only the activity source"
        ))
        new(Int32(depth), source)
    end
end

struct CompiledElongationPlan{T <: AbstractFloat}
    kind::Int16
    target::CompiledScalar{T}
    strength::CompiledScalar{T}
end

struct CompiledRelationshipPlan{T <: AbstractFloat}
    capacity::Int32
    maximum_degree::Int16
    kind_a::Int16
    kind_b::Int16
    strength::CompiledScalar{T}
    target::CompiledScalar{T}
    maximum::CompiledScalar{T}
    create_on_accepted_copy::Bool
    break_after_mcs::Bool
    remove_with_endpoint::Bool
end

function CompiledRelationshipPlan(
        capacity::Integer,
        maximum_degree::Integer,
        kind_a::Integer,
        kind_b::Integer,
        strength::CompiledScalar{T},
        target::CompiledScalar{T},
        maximum::CompiledScalar{T};
        create_on_accepted_copy::Bool = false,
        break_after_mcs::Bool = false,
        remove_with_endpoint::Bool = false,
    ) where {T <: AbstractFloat}
    capacity > 0 || throw(ArgumentError("relationship capacity must be positive"))
    maximum_degree > 0 ||
        throw(ArgumentError("relationship maximum degree must be positive"))
    1 <= kind_a <= typemax(Int16) ||
        throw(ArgumentError("relationship endpoint kind is out of range"))
    1 <= kind_b <= typemax(Int16) ||
        throw(ArgumentError("relationship endpoint kind is out of range"))
    return CompiledRelationshipPlan(
        Int32(capacity),
        Int16(maximum_degree),
        Int16(kind_a),
        Int16(kind_b),
        strength,
        target,
        maximum,
        create_on_accepted_copy,
        break_after_mcs,
        remove_with_endpoint,
    )
end

abstract type AbstractProgramObservation end
struct OccupiedSitesObservation <: AbstractProgramObservation
    kind::Int16
end
struct FieldStateObservation <: AbstractProgramObservation end
struct RelationshipDegreeObservation <: AbstractProgramObservation
    endpoint::Int32
end

struct CompiledPottsProgram{
        T <: AbstractFloat,
        N,
        E <: AbstractProgramEngine,
        B,
        A,
        F,
        H,
        G,
        R,
        O,
        PE,
        PD,
        PC,
        PM,
        CS,
    }
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::Matrix{Int8}
    contact_offsets::Matrix{Int8}
    kind_count::Int16
    medium_kind::Int16
    medium_kinds::BitVector
    volume_targets::Vector{CompiledScalar{T}}
    volume_strengths::Vector{CompiledScalar{T}}
    contact_energies::Matrix{CompiledScalar{T}}
    connectivity_kinds::BitVector
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    parameter_defaults::Vector{T}
    activity::A
    field::F
    history::H
    elongation::G
    relationships::R
    observations::O
    proposal_energies::PE
    proposal_drives::PD
    proposal_constraints::PC
    proposal_modifiers::PM
    cell_state_fields::CS
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
        volume_targets::Vector{CompiledScalar{T}},
        volume_strengths::Vector{CompiledScalar{T}},
        contact_energies::Matrix{CompiledScalar{T}},
        connectivity_kinds::BitVector,
        temperature::CompiledScalar{T},
        attempts_per_site::Integer,
        parameter_defaults::Vector{T},
        activity,
        field,
        history,
        elongation,
        relationships,
        observations,
        engine::E,
        backend::B,
        fingerprint::AbstractString;
        medium_kinds = nothing,
        proposal_energies = (),
        proposal_drives = (),
        proposal_constraints = (),
        proposal_modifiers = (),
        cell_state_fields = (),
    ) where {T <: AbstractFloat, N, E <: AbstractProgramEngine, B}
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
    length(volume_targets) == kind_count ||
        throw(ArgumentError("volume target table has the wrong size"))
    length(volume_strengths) == kind_count ||
        throw(ArgumentError("volume strength table has the wrong size"))
    size(contact_energies) == (kind_count, kind_count) ||
        throw(ArgumentError("contact table has the wrong size"))
    length(connectivity_kinds) == kind_count ||
        throw(ArgumentError("connectivity table has the wrong size"))
    attempts_per_site > 0 ||
        throw(ArgumentError("attempts per site must be positive"))
    return CompiledPottsProgram{
        T, N, E, B, typeof(activity), typeof(field), typeof(history),
        typeof(elongation),
        typeof(relationships), typeof(observations),
        typeof(proposal_energies), typeof(proposal_drives),
        typeof(proposal_constraints), typeof(proposal_modifiers),
        typeof(cell_state_fields),
    }(
        shape,
        periodic,
        copy(proposal_offsets),
        copy(contact_offsets),
        Int16(kind_count),
        Int16(medium_kind),
        medium_mask,
        copy(volume_targets),
        copy(volume_strengths),
        copy(contact_energies),
        copy(connectivity_kinds),
        temperature,
        Int32(attempts_per_site),
        copy(parameter_defaults),
        activity,
        field,
        history,
        elongation,
        relationships,
        observations,
        proposal_energies,
        proposal_drives,
        proposal_constraints,
        proposal_modifiers,
        Tuple(Symbol.(cell_state_fields)),
        engine,
        backend,
        String(fingerprint),
    )
end

function program_observations(runtime)
    return map(runtime.program.observations) do observation
        if observation isa OccupiedSitesObservation
            total = 0
    for owner in runtime.ownership
                _owner_kind(runtime, owner) == observation.kind &&
                    (total += 1)
            end
            total
        elseif observation isa FieldStateObservation
            runtime.field === nothing ? nothing : copy(runtime.field)
        elseif observation isa RelationshipDegreeObservation
            runtime.relationships === nothing && return 0
            _relationship_degree(runtime.relationships, observation.endpoint)
        else
            error("unreachable program observation")
        end
    end
end

struct ProgramInitialState{T <: AbstractFloat, N, A, F, H, S, R}
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    activity::A
    field::F
    history::H
    stored_states::S
    relationships::R
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
        activity = nothing,
        field = nothing,
        history = nothing,
        stored_states::NamedTuple = NamedTuple(),
        relationships = nothing,
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
    activity_values = activity === nothing ? nothing : Array{T, N}(activity)
    field_values = field === nothing ? nothing : Array{T, N}(field)
    history_values = history === nothing ? nothing :
                     [Array{T, N}(entry) for entry in history]
    stored_values = _copy_program_value(stored_states)
    relationship_values = relationships === nothing ? nothing : deepcopy(relationships)
    return ProgramInitialState{
        T, N, typeof(activity_values), typeof(field_values),
        typeof(history_values), typeof(stored_values),
        typeof(relationship_values),
    }(
        owned,
        kinds,
        generations,
        activity_values,
        field_values,
        history_values,
        stored_values,
        relationship_values,
    )
end

struct ProgramRelationshipState{T <: AbstractFloat}
    active::BitVector
    endpoint_a::Vector{Int32}
    endpoint_b::Vector{Int32}
    generation_a::Vector{UInt32}
    generation_b::Vector{UInt32}
    strength::Vector{T}
    target::Vector{T}
    maximum::Vector{T}
end

function ProgramRelationshipState(::Type{T}, capacity::Integer) where {
        T <: AbstractFloat,
    }
    return ProgramRelationshipState(
        falses(capacity),
        zeros(Int32, capacity),
        zeros(Int32, capacity),
        zeros(UInt32, capacity),
        zeros(UInt32, capacity),
        zeros(T, capacity),
        zeros(T, capacity),
        zeros(T, capacity),
    )
end

function Base.copy(state::ProgramRelationshipState)
    return ProgramRelationshipState(
        copy(state.active),
        copy(state.endpoint_a),
        copy(state.endpoint_b),
        copy(state.generation_a),
        copy(state.generation_b),
        copy(state.strength),
        copy(state.target),
        copy(state.maximum),
    )
end

abstract type ProgramRelationshipRequest end

struct CreateRelationshipRequest{T <: AbstractFloat} <:
       ProgramRelationshipRequest
    endpoint_a::Int32
    endpoint_b::Int32
    generation_a::UInt32
    generation_b::UInt32
    strength::T
    target::T
    maximum::T
    priority::Int32
    identity::UInt64
end

struct RemoveRelationshipRequest <: ProgramRelationshipRequest
    edge::Int32
    priority::Int32
    identity::UInt64
end

struct RetuneRelationshipRequest{T <: AbstractFloat} <:
       ProgramRelationshipRequest
    edge::Int32
    strength::T
    target::T
    maximum::T
    priority::Int32
    identity::UInt64
end

function CreateRelationshipRequest(
        endpoint_a::Integer,
        endpoint_b::Integer,
        strength::T,
        target::T,
        maximum::T;
        generation_a::Integer = 1,
        generation_b::Integer = 1,
        priority::Integer = 0,
        identity::Integer = 0,
    ) where {T <: AbstractFloat}
    return CreateRelationshipRequest(
        Int32(endpoint_a),
        Int32(endpoint_b),
        UInt32(generation_a),
        UInt32(generation_b),
        strength,
        target,
        maximum,
        Int32(priority),
        UInt64(identity),
    )
end

RemoveRelationshipRequest(edge::Integer; priority::Integer = 0,
        identity::Integer = 0) =
    RemoveRelationshipRequest(Int32(edge), Int32(priority), UInt64(identity))

function RetuneRelationshipRequest(
        edge::Integer,
        strength::T,
        target::T,
        maximum::T;
        priority::Integer = 0,
        identity::Integer = 0,
    ) where {T <: AbstractFloat}
    return RetuneRelationshipRequest(
        Int32(edge), strength, target, maximum, Int32(priority), UInt64(identity)
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
    degree = 0
    for edge in eachindex(state.active)
        @inbounds state.active[edge] || continue
        degree += @inbounds(
            state.endpoint_a[edge] == endpoint ||
            state.endpoint_b[edge] == endpoint
        )
    end
    return degree
end

function _validate_relationship_endpoint(
        endpoint::Int32,
        generation::UInt32,
        expected_kind::Int16,
        cell_kinds,
        cell_generations,
    )
    1 <= endpoint <= length(cell_kinds) ||
        throw(ArgumentError("relationship endpoint $endpoint is not an active cell"))
    @inbounds generation == cell_generations[endpoint] ||
        throw(ArgumentError("relationship endpoint generation is stale"))
    @inbounds cell_kinds[endpoint] == expected_kind ||
        throw(ArgumentError("relationship endpoint kind does not match"))
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

function apply_relationship_requests!(
        state::ProgramRelationshipState{T},
        cell_kinds,
        cell_generations,
        plan::CompiledRelationshipPlan{T},
        requests,
    ) where {T}
    staged = copy(state)
    ordered = sort!(collect(requests); by = _request_sort_key)
    touched_edges = Set{Int32}()
    for request in ordered
        if request isa CreateRelationshipRequest
            request.endpoint_a != request.endpoint_b ||
                throw(ArgumentError("a relationship cannot be a self-edge"))
            a, b = _canonical_endpoints(request.endpoint_a, request.endpoint_b)
            generation_a, generation_b =
                request.endpoint_a == a ?
                (request.generation_a, request.generation_b) :
                (request.generation_b, request.generation_a)
            1 <= a <= length(cell_kinds) ||
                throw(ArgumentError("relationship endpoint $a is not an active cell"))
            1 <= b <= length(cell_kinds) ||
                throw(ArgumentError("relationship endpoint $b is not an active cell"))
            kind_a = @inbounds cell_kinds[a]
            kind_b = @inbounds cell_kinds[b]
            legal = (kind_a == plan.kind_a && kind_b == plan.kind_b) ||
                    (kind_a == plan.kind_b && kind_b == plan.kind_a)
            legal || throw(ArgumentError("relationship endpoint kinds do not match"))
            _validate_relationship_endpoint(
                a, generation_a, kind_a, cell_kinds, cell_generations
            )
            _validate_relationship_endpoint(
                b, generation_b, kind_b, cell_kinds, cell_generations
            )
            existing = _relationship_edge(staged, a, b)
            existing === nothing || continue # declared duplicate policy: ignore exact create
            _relationship_degree(staged, a) < plan.maximum_degree ||
                throw(ArgumentError("relationship maximum degree exceeded for $a"))
            _relationship_degree(staged, b) < plan.maximum_degree ||
                throw(ArgumentError("relationship maximum degree exceeded for $b"))
            slot = findfirst(!, staged.active)
            slot === nothing &&
                throw(ArgumentError("relationship capacity exceeded"))
            request.maximum > zero(T) ||
                throw(ArgumentError("relationship breaking length must be positive"))
            request.target >= zero(T) ||
                throw(ArgumentError("relationship target length must be nonnegative"))
            request.strength >= zero(T) ||
                throw(ArgumentError("relationship strength must be nonnegative"))
            staged.active[slot] = true
            staged.endpoint_a[slot] = a
            staged.endpoint_b[slot] = b
            staged.generation_a[slot] = generation_a
            staged.generation_b[slot] = generation_b
            staged.strength[slot] = request.strength
            staged.target[slot] = request.target
            staged.maximum[slot] = request.maximum
        elseif request isa RemoveRelationshipRequest
            edge = request.edge
            1 <= edge <= length(staged.active) && staged.active[edge] ||
                throw(ArgumentError("remove request references an inactive edge"))
            edge in touched_edges &&
                throw(ArgumentError("conflicting relationship requests for edge $edge"))
            push!(touched_edges, edge)
            staged.active[edge] = false
            staged.endpoint_a[edge] = 0
            staged.endpoint_b[edge] = 0
            staged.generation_a[edge] = 0
            staged.generation_b[edge] = 0
            staged.strength[edge] = zero(T)
            staged.target[edge] = zero(T)
            staged.maximum[edge] = zero(T)
        elseif request isa RetuneRelationshipRequest
            edge = request.edge
            1 <= edge <= length(staged.active) && staged.active[edge] ||
                throw(ArgumentError("retune request references an inactive edge"))
            edge in touched_edges &&
                throw(ArgumentError("conflicting relationship requests for edge $edge"))
            push!(touched_edges, edge)
            request.maximum > zero(T) ||
                throw(ArgumentError("relationship breaking length must be positive"))
            staged.strength[edge] = request.strength
            staged.target[edge] = request.target
            staged.maximum[edge] = request.maximum
        else
            throw(ArgumentError("unknown relationship request type"))
        end
    end
    copyto!(state.active, staged.active)
    copyto!(state.endpoint_a, staged.endpoint_a)
    copyto!(state.endpoint_b, staged.endpoint_b)
    copyto!(state.generation_a, staged.generation_a)
    copyto!(state.generation_b, staged.generation_b)
    copyto!(state.strength, staged.strength)
    copyto!(state.target, staged.target)
    copyto!(state.maximum, staged.maximum)
    return state
end

function initialize_program_relationships(
        plan::CompiledRelationshipPlan{T},
        cell_kinds,
        cell_generations,
        parameters,
        entries,
    ) where {T}
    state = ProgramRelationshipState(T, plan.capacity)
    entries === nothing && return state
    default_strength = compiled_scalar_value(plan.strength, parameters)
    default_target = compiled_scalar_value(plan.target, parameters)
    default_maximum = compiled_scalar_value(plan.maximum, parameters)
    requests = ProgramRelationshipRequest[]
    for (identity, entry) in enumerate(entries)
        length(entry) in (2, 3) ||
            throw(ArgumentError("relationship entries are `(a, b)` or `(a, b, payload)`"))
        a, b = entry[1], entry[2]
        a isa Integer && 1 <= a <= length(cell_generations) ||
            throw(ArgumentError("relationship endpoint $a is not an active cell"))
        b isa Integer && 1 <= b <= length(cell_generations) ||
            throw(ArgumentError("relationship endpoint $b is not an active cell"))
        payload = length(entry) == 3 ? entry[3] : NamedTuple()
        strength = haskey(payload, :strength) ? T(payload.strength) : default_strength
        target = haskey(payload, :target) ? T(payload.target) : default_target
        maximum = haskey(payload, :maximum) ? T(payload.maximum) : default_maximum
        generation_a = haskey(payload, :generation_a) ?
                       UInt32(payload.generation_a) :
                       cell_generations[Int(a)]
        generation_b = haskey(payload, :generation_b) ?
                       UInt32(payload.generation_b) :
                       cell_generations[Int(b)]
        push!(requests, CreateRelationshipRequest(
            a,
            b,
            strength,
            target,
            maximum;
            generation_a,
            generation_b,
            identity,
        ))
    end
    apply_relationship_requests!(
        state, cell_kinds, cell_generations, plan, requests
    )
    return state
end

struct ProgramSnapshot{T <: AbstractFloat, N, A, F, H, S, R}
    mcs::Int
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    volumes::Vector{Int}
    activity::A
    field::F
    history::H
    stored_states::S
    relationships::R
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
        snapshot.activity === nothing ? "nothing" :
        join(vec(snapshot.activity), ','), '\n',
        snapshot.field === nothing ? "nothing" :
        join(vec(snapshot.field), ','), '\n',
        snapshot.history === nothing ? "nothing" :
        join((join(vec(entry), ',') for entry in snapshot.history), ';'), '\n',
        repr(snapshot.stored_states), '\n',
        snapshot.relationships === nothing ? "nothing" :
        string(
            join(snapshot.relationships.active, ','),
            ';', join(snapshot.relationships.endpoint_a, ','),
            ';', join(snapshot.relationships.endpoint_b, ','),
            ';', join(snapshot.relationships.generation_a, ','),
            ';', join(snapshot.relationships.generation_b, ','),
            ';', join(snapshot.relationships.strength, ','),
            ';', join(snapshot.relationships.target, ','),
            ';', join(snapshot.relationships.maximum, ','),
        ), '\n',
        join(parameters, ','), '\n',
        seed, '\n',
        replica, '\n',
        repeat, '\n',
        accepted, '\n',
        rejected, '\n',
        null_attempts,
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
    )
    expected == checkpoint.checksum ||
        throw(ArgumentError("checkpoint integrity checksum mismatch"))
    initial = ProgramInitialState(
        checkpoint.snapshot.ownership,
        checkpoint.snapshot.cell_kinds;
        scalar_type = eltype(program.parameter_defaults),
        cell_generations = checkpoint.snapshot.cell_generations,
        activity = checkpoint.snapshot.activity,
        field = checkpoint.snapshot.field,
        history = checkpoint.snapshot.history,
        stored_states = checkpoint.snapshot.stored_states,
        relationships = nothing,
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
    return runtime
end

mutable struct ProgramRuntime{T <: AbstractFloat, N, P, A, F, H, S, R}
    program::P
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    volumes::Vector{Int}
    activity::A
    field::F
    history::H
    stored_states::S
    relationships::R
    parameters::Vector{T}
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
    accepted::Int
    rejected::Int
    null_attempts::Int
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
    activity = if program.activity === nothing
        nothing
    elseif initial.activity === nothing
        zeros(T, program.shape)
    else
        size(initial.activity) == program.shape ||
            throw(ArgumentError("activity state shape does not match the program"))
        copy(initial.activity)
    end
    field = if program.field === nothing || !program.field.enabled
        nothing
    elseif initial.field === nothing
        zeros(T, program.shape)
    else
        size(initial.field) == program.shape ||
            throw(ArgumentError("field state shape does not match the program"))
        copy(initial.field)
    end
    history = if program.history === nothing
        nothing
    elseif initial.history === nothing
        source = program.history.source === :activity ? activity : nothing
        source === nothing && throw(ArgumentError(
            "compiled history source is not allocated"
        ))
        [copy(source) for _ in 1:Int(program.history.depth)]
    else
        length(initial.history) == Int(program.history.depth) ||
            throw(ArgumentError("initial history has the wrong depth"))
        all(entry -> size(entry) == program.shape, initial.history) ||
            throw(ArgumentError("initial history state shape does not match the program"))
        [copy(entry) for entry in initial.history]
    end
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
    stored_states = _copy_program_value(initial.stored_states)
    return ProgramRuntime{
        T, N, typeof(program), typeof(activity), typeof(field), typeof(history),
        typeof(stored_states), typeof(relationships),
    }(
        program,
        copy(initial.ownership),
        copy(initial.cell_kinds),
        copy(initial.cell_generations),
        volumes,
        activity,
        field,
        history,
        stored_states,
        relationships,
        T.(parameters),
        seed,
        replica,
        repeat,
        Int(initial_mcs),
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
    activity = runtime.activity === nothing ? nothing : copy(runtime.activity)
    field = runtime.field === nothing ? nothing : copy(runtime.field)
    history = runtime.history === nothing ? nothing :
              [copy(entry) for entry in runtime.history]
    stored_states = _copy_program_value(runtime.stored_states)
    relationships = runtime.relationships === nothing ?
                    nothing : copy(runtime.relationships)
    return ProgramSnapshot{
        T, N, typeof(activity), typeof(field), typeof(history),
        typeof(stored_states), typeof(relationships),
    }(
        runtime.mcs,
        copy(runtime.ownership),
        copy(runtime.cell_kinds),
        copy(runtime.cell_generations),
        copy(runtime.volumes),
        activity,
        field,
        history,
        stored_states,
        relationships,
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
        draw,
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

@inline function _volume_delta(runtime::ProgramRuntime{T}, old_owner, new_owner) where {T}
    old_owner == new_owner && return zero(T)
    program = runtime.program
    parameters = runtime.parameters
    delta = zero(T)
    if old_owner > 0
        kind = @inbounds runtime.cell_kinds[old_owner]
        strength = compiled_scalar_value(program.volume_strengths[kind], parameters)
        target = compiled_scalar_value(program.volume_targets[kind], parameters)
        volume = @inbounds runtime.volumes[old_owner]
        delta += strength * ((T(volume - 1) - target)^2 - (T(volume) - target)^2)
    end
    if new_owner > 0
        kind = @inbounds runtime.cell_kinds[new_owner]
        strength = compiled_scalar_value(program.volume_strengths[kind], parameters)
        target = compiled_scalar_value(program.volume_targets[kind], parameters)
        volume = @inbounds runtime.volumes[new_owner]
        delta += strength * ((T(volume + 1) - target)^2 - (T(volume) - target)^2)
    end
    return delta
end

function _contact_delta(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    old_kind = _owner_kind(runtime, old_owner)
    new_kind = _owner_kind(runtime, new_owner)
    delta = zero(T)
    table = runtime.program.contact_energies
    for direction in axes(runtime.program.contact_offsets, 2)
        neighbor = _neighbor_index(
            runtime.program, target, runtime.program.contact_offsets, direction
        )
        neighbor === nothing && continue
        neighbor_owner = @inbounds runtime.ownership[neighbor]
        neighbor_kind = _owner_kind(runtime, neighbor_owner)
        old_owner == neighbor_owner || (
            delta -= compiled_scalar_value(
                @inbounds(table[old_kind, neighbor_kind]), runtime.parameters
            )
        )
        new_owner == neighbor_owner || (
            delta += compiled_scalar_value(
                @inbounds(table[new_kind, neighbor_kind]), runtime.parameters
            )
        )
    end
    return delta
end

function _connected_after_removal(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        owner::Int32,
    ) where {T, N}
    owner <= 0 && return true
    kind = @inbounds runtime.cell_kinds[owner]
    runtime.program.connectivity_kinds[kind] || return true
    neighbors = CartesianIndex{N}[]
    for direction in axes(runtime.program.proposal_offsets, 2)
        candidate = _neighbor_index(
            runtime.program, target, runtime.program.proposal_offsets, direction
        )
        candidate === nothing && continue
        @inbounds runtime.ownership[candidate] == owner || continue
        candidate == target || push!(neighbors, candidate)
    end
    length(neighbors) <= 1 && return true
    visited = Set{CartesianIndex{N}}((first(neighbors),))
    frontier = CartesianIndex{N}[first(neighbors)]
    neighbor_set = Set(neighbors)
    while !isempty(frontier)
        current = pop!(frontier)
        for direction in axes(runtime.program.proposal_offsets, 2)
            candidate = _neighbor_index(
                runtime.program,
                current,
                runtime.program.proposal_offsets,
                direction,
            )
            candidate === nothing && continue
            candidate == target && continue
            candidate in neighbor_set || continue
            candidate in visited && continue
            push!(visited, candidate)
            push!(frontier, candidate)
        end
    end
    return length(visited) == length(neighbor_set)
end

function _local_activity_geomean(
        runtime::ProgramRuntime{T, N},
        site::CartesianIndex{N},
        owner::Int32,
    ) where {T, N}
    owner <= 0 && return zero(T)
    plan = runtime.program.activity
    plan === nothing && return zero(T)
    total = zero(T)
    count = 0
    if @inbounds runtime.ownership[site] == owner
        total += log1p(max(zero(T), @inbounds(runtime.activity[site])))
        count += 1
    end
    for direction in axes(plan.neighborhood_offsets, 2)
        neighbor = _neighbor_index(
            runtime.program, site, plan.neighborhood_offsets, direction
        )
        neighbor === nothing && continue
        @inbounds runtime.ownership[neighbor] == owner || continue
        total += log1p(max(zero(T), @inbounds(runtime.activity[neighbor])))
        count += 1
    end
    return count == 0 ? zero(T) : exp(total / T(count)) - one(T)
end

function _activity_delta(
        runtime::ProgramRuntime{T, N},
        source::CartesianIndex{N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    plan = runtime.program.activity
    plan === nothing && return zero(T)
    new_owner <= 0 && return zero(T)
    @inbounds runtime.cell_kinds[new_owner] == plan.kind || return zero(T)
    maximum = compiled_scalar_value(plan.maximum, runtime.parameters)
    maximum > zero(T) || return zero(T)
    strength = compiled_scalar_value(plan.strength, runtime.parameters)
    source_activity = _local_activity_geomean(runtime, source, new_owner)
    target_activity = _local_activity_geomean(runtime, target, old_owner)
    return -(strength / maximum) * (source_activity - target_activity)
end

function _chemotaxis_delta(
        runtime::ProgramRuntime{T, N},
        source::CartesianIndex{N},
        target::CartesianIndex{N},
        new_owner::Int32,
    ) where {T, N}
    plan = runtime.program.field
    plan === nothing && return zero(T)
    plan.enabled || return zero(T)
    new_owner <= 0 && return zero(T)
    @inbounds runtime.cell_kinds[new_owner] == plan.chemotaxis_kind || return zero(T)
    strength = compiled_scalar_value(plan.chemotaxis_strength, runtime.parameters)
    return -strength * (@inbounds(runtime.field[target]) - @inbounds(runtime.field[source]))
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
                quadratic[row, column] += coordinates[row] * coordinates[column]
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
    maximum_variance = maximum(eigen(Symmetric(covariance)).values)
    return T(4) * sqrt(max(zero(T), maximum_variance))
end

function _elongation_delta(
        runtime::ProgramRuntime{T, N},
        target_site::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    plan = runtime.program.elongation
    plan === nothing && return zero(T)
    target_length = compiled_scalar_value(plan.target, runtime.parameters)
    strength = compiled_scalar_value(plan.strength, runtime.parameters)
    delta = zero(T)
    for cell in (old_owner, new_owner)
        cell == 0 && continue
        @inbounds runtime.cell_kinds[cell] == plan.kind || continue
        before_length = _cell_length(runtime, cell)
        after_length = _cell_length(
            runtime,
            cell;
            replaced_site = target_site,
            replacement_owner = new_owner,
        )
        delta += strength * (
            (after_length - target_length)^2 -
            (before_length - target_length)^2
        )
    end
    return delta
end

@inline function _center_distance(first, second)
    return sqrt(sum((first[i] - second[i])^2 for i in eachindex(first)))
end

function _relationship_energy(
        state::ProgramRelationshipState{T},
        edge::Int,
        runtime::ProgramRuntime{T, N};
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    a = @inbounds state.endpoint_a[edge]
    b = @inbounds state.endpoint_b[edge]
    center_a = _cell_center(
        runtime, a; replaced_site, replacement_owner
    )
    center_b = _cell_center(
        runtime, b; replaced_site, replacement_owner
    )
    (center_a === nothing || center_b === nothing) && return zero(T)
    distance = _center_distance(center_a, center_b)
    target = @inbounds state.target[edge]
    strength = @inbounds state.strength[edge]
    return strength * (distance - target)^2
end

function _relationship_delta(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    state = runtime.relationships
    state === nothing && return zero(T)
    delta = zero(T)
    for edge in eachindex(state.active)
        @inbounds state.active[edge] || continue
        a = @inbounds state.endpoint_a[edge]
        b = @inbounds state.endpoint_b[edge]
        (a in (old_owner, new_owner) || b in (old_owner, new_owner)) || continue
        before = _relationship_energy(state, edge, runtime)
        after = _relationship_energy(
            state,
            edge,
            runtime;
            replaced_site = target,
            replacement_owner = new_owner,
        )
        delta += after - before
    end
    return delta
end

function _accepted_copy_relationship_state(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        new_owner::Int32,
        attempt_identity::Int,
    ) where {T, N}
    plan = runtime.program.relationships
    state = runtime.relationships
    (plan === nothing || state === nothing ||
     !plan.create_on_accepted_copy || new_owner <= 0) && return state
    staged = copy(state)
    requests = ProgramRelationshipRequest[]
    strength = compiled_scalar_value(plan.strength, runtime.parameters)
    target_length = compiled_scalar_value(plan.target, runtime.parameters)
    maximum = compiled_scalar_value(plan.maximum, runtime.parameters)
    request_index = 0
    for direction in axes(runtime.program.contact_offsets, 2)
        neighbor = _neighbor_index(
            runtime.program, target, runtime.program.contact_offsets, direction
        )
        neighbor === nothing && continue
        other = @inbounds runtime.ownership[neighbor]
        (other <= 0 || other == new_owner) && continue
        _relationship_edge(staged, new_owner, other) === nothing || continue
        request_index += 1
        identity = UInt64(attempt_identity) << 32 | UInt64(request_index)
        push!(requests, CreateRelationshipRequest(
            new_owner,
            other,
            strength,
            target_length,
            maximum;
            generation_a = @inbounds(runtime.cell_generations[new_owner]),
            generation_b = @inbounds(runtime.cell_generations[other]),
            identity,
        ))
    end
    isempty(requests) ||
        apply_relationship_requests!(
            staged,
            runtime.cell_kinds,
            runtime.cell_generations,
            plan,
            requests,
        )
    return staged
end

@inline function _relationship_allows_extinction(
        runtime::ProgramRuntime, old_owner::Int32
    )
    old_owner <= 0 && return true
    @inbounds runtime.volumes[old_owner] == 1 || return true
    plan = runtime.program.relationships
    state = runtime.relationships
    (plan === nothing || state === nothing || plan.remove_with_endpoint) &&
        return true
    return _relationship_degree(state, old_owner) == 0
end

function _commit_copy!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
        attempt_identity::Int,
    ) where {T, N}
    staged_relationships = _accepted_copy_relationship_state(
        runtime, target, new_owner, attempt_identity
    )
    @inbounds runtime.ownership[target] = new_owner
    old_owner > 0 && (@inbounds runtime.volumes[old_owner] -= 1)
    new_owner > 0 && (@inbounds runtime.volumes[new_owner] += 1)
    plan = runtime.program.activity
    if plan !== nothing && runtime.activity !== nothing
        old_owner == new_owner || (@inbounds runtime.activity[target] = zero(T))
        if plan.activate_extensions && old_owner <= 0 && new_owner > 0 &&
                @inbounds(runtime.cell_kinds[new_owner]) == plan.kind
            @inbounds runtime.activity[target] =
                compiled_scalar_value(plan.maximum, runtime.parameters)
        end
    end
    runtime.relationships = staged_relationships
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

@inline _evaluate_program_expression(
    expression::ProgramLiteral, context::_ProposalEvaluationContext
) = expression.value

@inline _evaluate_program_expression(
    expression::ProgramScalar, context::_ProposalEvaluationContext
) = compiled_scalar_value(expression.value, context.runtime.parameters)

@inline function _evaluate_program_expression(
        expression::ProgramCall, context::_ProposalEvaluationContext
    )
    return _evaluate_program_call(expression, context)
end

@inline _evaluate_program_call(
    expression::ProgramCall{:source_site}, context::_ProposalEvaluationContext
) = context.source
@inline _evaluate_program_call(
    expression::ProgramCall{:target_site}, context::_ProposalEvaluationContext
) = context.target
@inline _evaluate_program_call(
    expression::ProgramCall{:source_cell}, context::_ProposalEvaluationContext
) = context.new_owner
@inline _evaluate_program_call(
    expression::ProgramCall{:target_cell}, context::_ProposalEvaluationContext
) = context.old_owner
@inline _evaluate_program_call(
    expression::ProgramCall{:source_kind}, context::_ProposalEvaluationContext
) = _owner_kind(context.runtime, context.new_owner)
@inline _evaluate_program_call(
    expression::ProgramCall{:target_kind}, context::_ProposalEvaluationContext
) = _owner_kind(context.runtime, context.old_owner)
@inline _evaluate_program_call(
    expression::ProgramCall{:is_extension}, context::_ProposalEvaluationContext
) = context.old_owner <= 0 && context.new_owner > 0
@inline _evaluate_program_call(
    expression::ProgramCall{:is_retraction}, context::_ProposalEvaluationContext
) = context.old_owner > 0 && context.new_owner <= 0

@inline function _evaluate_program_call(
        expression::ProgramCall{:cell_volume}, context::_ProposalEvaluationContext
    )
    owner = Int(_evaluate_program_expression(only(expression.arguments), context))
    owner <= 0 && return 0
    1 <= owner <= length(context.runtime.volumes) ||
        throw(ArgumentError("proposal expression addressed an invalid cell `$owner`"))
    return @inbounds context.runtime.volumes[owner]
end

@inline function _evaluate_program_call(
        expression::ProgramCall{:field_value}, context::_ProposalEvaluationContext
    )
    context.runtime.field === nothing &&
        throw(ArgumentError("proposal expression reads an unavailable field"))
    site_expression = last(expression.arguments)
    site = _evaluate_program_expression(site_expression, context)
    return @inbounds context.runtime.field[site]
end

for (name, operator) in (
        (:add, :+),
        (:subtract, :-),
        (:multiply, :*),
        (:divide, :/),
        (:power, :^),
        (:maximum, :max),
        (:minimum, :min),
        (:less, :<),
        (:less_equal, :<=),
        (:greater, :>),
        (:greater_equal, :>=),
        (:equal, :(==)),
        (:not_equal, :(!=)),
        (:and, :(&)),
        (:or, :(|)),
    )
    @eval @inline function _evaluate_program_call(
            expression::ProgramCall{$(QuoteNode(name))},
            context::_ProposalEvaluationContext,
        )
        arguments = expression.arguments
        return $(operator)(
            _evaluate_program_expression(first(arguments), context),
            _evaluate_program_expression(last(arguments), context),
        )
    end
end

for (name, operator) in (
        (:negate, :-),
        (:not, :!),
        (:absolute, :abs),
        (:exponential, :exp),
        (:logarithm, :log),
        (:square_root, :sqrt),
    )
    @eval @inline function _evaluate_program_call(
            expression::ProgramCall{$(QuoteNode(name))},
            context::_ProposalEvaluationContext,
        )
        return $(operator)(
            _evaluate_program_expression(only(expression.arguments), context)
        )
    end
end

@inline function _evaluate_program_call(
        expression::ProgramCall{:ifelse}, context::_ProposalEvaluationContext
    )
    condition, when_true, when_false = expression.arguments
    return ifelse(
        _evaluate_program_expression(condition, context),
        _evaluate_program_expression(when_true, context),
        _evaluate_program_expression(when_false, context),
    )
end

@inline function _explicit_draw_uniform(
        ::Type{T}, expression::ProgramDraw, context::_ProposalEvaluationContext;
        draw::Integer = 0,
    ) where {T}
    return _program_uniform(
        T,
        context.runtime,
        ExplicitProposalDrawStream,
        expression.operation,
        context.attempt;
        subround = context.subround,
        draw,
    )
end

@inline function _evaluate_program_expression(
        expression::ProgramDraw{:bernoulli},
        context::_ProposalEvaluationContext,
    )
    T = eltype(context.runtime.parameters)
    probability = T(_evaluate_program_expression(
        expression.first_parameter, context
    ))
    zero(T) <= probability <= one(T) ||
        throw(ArgumentError("Bernoulli probability must remain in [0, 1]"))
    return _explicit_draw_uniform(T, expression, context) < probability
end

@inline function _evaluate_program_expression(
        expression::ProgramDraw{:uniform},
        context::_ProposalEvaluationContext,
    )
    T = eltype(context.runtime.parameters)
    minimum = T(_evaluate_program_expression(
        expression.first_parameter, context
    ))
    maximum = T(_evaluate_program_expression(
        expression.second_parameter, context
    ))
    minimum < maximum ||
        throw(ArgumentError("Uniform draw bounds must remain strictly ordered"))
    draw = _explicit_draw_uniform(T, expression, context)
    return muladd(draw, maximum - minimum, minimum)
end

@inline function _evaluate_program_expression(
        expression::ProgramDraw{:normal},
        context::_ProposalEvaluationContext,
    )
    T = eltype(context.runtime.parameters)
    mean = T(_evaluate_program_expression(
        expression.first_parameter, context
    ))
    standard_deviation = T(_evaluate_program_expression(
        expression.second_parameter, context
    ))
    standard_deviation >= zero(T) ||
        throw(ArgumentError("Normal standard deviation must remain nonnegative"))
    iszero(standard_deviation) && return mean
    first_uniform = _explicit_draw_uniform(T, expression, context; draw = 0)
    second_uniform = _explicit_draw_uniform(T, expression, context; draw = 1)
    normal = sqrt(-T(2) * log(first_uniform)) *
             cos(T(2pi) * second_uniform)
    return muladd(standard_deviation, normal, mean)
end

@inline _proposal_term_value(term::CompiledProposalTerm, context) =
    _evaluate_program_expression(term.expression, context)

@inline _proposal_sum(::Tuple{}, context, initial) = initial
@inline function _proposal_sum(terms::Tuple, context, initial)
    return _proposal_sum(
        Base.tail(terms),
        context,
        initial + _proposal_term_value(first(terms), context),
    )
end

@inline _proposal_all(::Tuple{}, context) = true
@inline function _proposal_all(terms::Tuple, context)
    Bool(_proposal_term_value(first(terms), context)) || return false
    return _proposal_all(Base.tail(terms), context)
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
    old_owner = @inbounds runtime.ownership[target]
    new_owner = @inbounds runtime.ownership[source]
    old_owner == new_owner && (runtime.null_attempts += 1; return false)
    _connected_after_removal(runtime, target, old_owner) ||
        (runtime.rejected += 1; return false)
    _relationship_allows_extinction(runtime, old_owner) ||
        (runtime.rejected += 1; return false)

    expression_context = _ProposalEvaluationContext(
        runtime,
        source,
        target,
        old_owner,
        new_owner,
        attempt_identity,
        subround,
    )
    _proposal_all(program.proposal_constraints, expression_context) ||
        (runtime.rejected += 1; return false)
    delta = _volume_delta(runtime, old_owner, new_owner)
    delta += _contact_delta(runtime, target, old_owner, new_owner)
    delta += _activity_delta(runtime, source, target, old_owner, new_owner)
    delta += _chemotaxis_delta(runtime, source, target, new_owner)
    delta += _relationship_delta(runtime, target, old_owner, new_owner)
    delta += _elongation_delta(runtime, target, old_owner, new_owner)
    delta = _proposal_sum(
        program.proposal_energies, expression_context, delta
    )
    temperature = compiled_scalar_value(program.temperature, runtime.parameters)
    temperature >= zero(T) ||
        throw(ArgumentError("temperature must remain nonnegative"))
    has_bias = !isempty(program.proposal_drives) ||
               !isempty(program.proposal_modifiers)
    has_bias && iszero(temperature) && throw(ArgumentError(
        "ProposalDrive and ProposalModifier require positive temperature; " *
        "no zero-temperature rule was declared"
    ))
    log_ratio = if iszero(temperature)
        delta <= zero(T) ? zero(T) : -T(Inf)
    else
        -delta / temperature
    end
    log_ratio = _proposal_sum(
        program.proposal_drives, expression_context, log_ratio
    )
    log_ratio = _proposal_sum(
        program.proposal_modifiers, expression_context, log_ratio
    )
    accepted = log_ratio >= zero(T)
    if !accepted && isfinite(log_ratio)
        draw = _program_uniform(
            T,
            runtime,
            AcceptanceStream,
            3,
            attempt_identity;
            subround,
        )
        accepted = log(draw) < log_ratio
    end
    if accepted
        _commit_copy!(runtime, target, old_owner, new_owner, attempt_identity)
        runtime.accepted += 1
        return true
    end
    runtime.rejected += 1
    return false
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

@inline _clear_retired_cell_state!(states, ::Tuple{}, cell) = nothing
@inline function _clear_retired_cell_state!(states, names::Tuple, cell)
    values = getproperty(states, first(names))
    @inbounds values[cell] = zero(eltype(values))
    return _clear_retired_cell_state!(states, Base.tail(names), cell)
end

function _retire_extinct_cells!(runtime::ProgramRuntime)
    for cell in eachindex(runtime.cell_kinds)
        @inbounds runtime.cell_kinds[cell] == 0 && continue
        @inbounds runtime.volumes[cell] == 0 || continue
        @inbounds runtime.cell_kinds[cell] = 0
        _clear_retired_cell_state!(
            runtime.stored_states, runtime.program.cell_state_fields, cell
        )
    end
    return nothing
end

function _after_mcs!(runtime::ProgramRuntime{T, N}) where {T, N}
    _retire_extinct_cells!(runtime)
    plan = runtime.program.activity
    if plan !== nothing && runtime.activity !== nothing
        decay = plan.decay_per_mcs
        for index in eachindex(runtime.activity)
            @inbounds runtime.activity[index] =
                max(zero(T), runtime.activity[index] - decay)
        end
    end
    history_plan = runtime.program.history
    if history_plan !== nothing && runtime.history !== nothing
        source = history_plan.source === :activity ? runtime.activity : nothing
        source === nothing && error("unreachable compiled history source")
        for index in 1:(length(runtime.history) - 1)
            copyto!(runtime.history[index], runtime.history[index + 1])
        end
        copyto!(last(runtime.history), source)
    end
    field_plan = runtime.program.field
    if field_plan !== nothing && field_plan.enabled && runtime.field !== nothing
        substeps = Int(field_plan.substeps)
        dt = field_plan.duration_per_mcs / T(substeps)
        diffusion = compiled_scalar_value(field_plan.diffusion, runtime.parameters)
        decay = compiled_scalar_value(field_plan.decay, runtime.parameters)
        secretion = compiled_scalar_value(field_plan.secretion, runtime.parameters)
        scratch = similar(runtime.field)
        for _ in 1:substeps
            for site in CartesianIndices(runtime.field)
                center = @inbounds runtime.field[site]
                laplace = zero(T)
                for direction in axes(field_plan.stencil_offsets, 2)
                    neighbor = _neighbor_index(
                        runtime.program,
                        site,
                        field_plan.stencil_offsets,
                        direction,
                    )
                    neighbor === nothing && continue
                    laplace += @inbounds(runtime.field[neighbor]) - center
                end
                owner = @inbounds runtime.ownership[site]
                source = owner > 0 && field_plan.source_kind != 0 &&
                         @inbounds(runtime.cell_kinds[owner]) ==
                         field_plan.source_kind ? secretion : zero(T)
                @inbounds scratch[site] = max(
                    zero(T),
                    center + dt * (diffusion * laplace - decay * center + source),
                )
            end
            runtime.field, scratch = scratch, runtime.field
        end
    end
    relationship_plan = runtime.program.relationships
    if relationship_plan !== nothing && runtime.relationships !== nothing &&
            (
                relationship_plan.break_after_mcs ||
                relationship_plan.remove_with_endpoint
            )
        requests = ProgramRelationshipRequest[]
        for edge in eachindex(runtime.relationships.active)
            @inbounds runtime.relationships.active[edge] || continue
            a = @inbounds runtime.relationships.endpoint_a[edge]
            b = @inbounds runtime.relationships.endpoint_b[edge]
            center_a = _cell_center(runtime, a)
            center_b = _cell_center(runtime, b)
            missing_endpoint = center_a === nothing || center_b === nothing
            too_long = relationship_plan.break_after_mcs &&
                       !missing_endpoint &&
                       _center_distance(center_a, center_b) >
                    @inbounds(runtime.relationships.maximum[edge])
            if (
                    relationship_plan.remove_with_endpoint && missing_endpoint
                ) || too_long
                push!(requests, RemoveRelationshipRequest(
                    edge; identity = edge
                ))
            end
        end
        isempty(requests) || apply_relationship_requests!(
            runtime.relationships,
            runtime.cell_kinds,
            runtime.cell_generations,
            relationship_plan,
            requests,
        )
    end
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
    activity = program.activity !== nothing,
    field = program.field !== nothing && program.field.enabled,
    history = program.history !== nothing,
    elongation = program.elongation !== nothing,
    relationships = program.relationships !== nothing,
    observations = length(program.observations),
)
