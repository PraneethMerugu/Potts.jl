# Compiled program types and immutable construction contracts.

"""Supertype for compiled program scheduling engines."""
abstract type AbstractProgramEngine end
"""Independent host reference engine with sequential proposal order."""
struct SequentialProgramEngine <: AbstractProgramEngine end
"""Conflict-free colored engine using the shared KernelAbstractions path."""
struct CheckerboardProgramEngine <: AbstractProgramEngine end
"""Host CPU storage and execution backend."""
struct CPUProgramBackend end
"""Backend identity whose runtime storage is supplied by adapter `Name`."""
struct AdaptedProgramBackend{Name} end

"""Scalar compiler value represented by a default or submission-parameter slot."""
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

"""Capacity, degree, endpoint, generation, and payload schema for one relationship store."""
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
        "relationship capacity exceeds the Int32 storage bound"
    ))
    maximum_degree > 0 ||
        throw(ArgumentError("relationship maximum degree must be positive"))
    maximum_degree <= typemax(Int16) || throw(ArgumentError(
        "relationship maximum degree exceeds the Int16 storage bound"
    ))
    return RelationshipStoreSchema(
        Int32(capacity),
        Int16(maximum_degree),
        payload_defaults,
    )
end

struct RelationshipSlot
    bank::Int32
    slot::Int32
end

"""Representation-banked relationship values with value-level flat slots."""
struct RelationshipStorage{
        B <: Tuple,
        S <: AbstractVector{RelationshipSlot},
    }
    banks::B
    slots::S
end

function RelationshipStorage(values)
    entries = collect(values)
    representations = unique!(DataType[typeof(value) for value in entries])
    sort!(representations; by = string)
    bank_for = Dict(
        representation => index
        for (index, representation) in enumerate(representations)
    )
    banks = Any[
        Vector{representation}() for representation in representations
    ]
    slots = Vector{RelationshipSlot}(undef, length(entries))
    for (index, value) in enumerate(entries)
        bank = bank_for[typeof(value)]
        push!(banks[bank], value)
        slots[index] = RelationshipSlot(bank, length(banks[bank]))
    end
    return RelationshipStorage(Tuple(banks), slots)
end

Base.length(storage::RelationshipStorage) = length(storage.slots)
Base.isempty(storage::RelationshipStorage) = isempty(storage.slots)
Base.firstindex(::RelationshipStorage) = 1
Base.lastindex(storage::RelationshipStorage) = length(storage)
Base.eachindex(storage::RelationshipStorage) = Base.OneTo(length(storage))

@inline function _relationship_location(
        storage::RelationshipStorage, index::Integer
    )
    return @inbounds storage.slots[index]
end

function Base.copy(storage::RelationshipStorage)
    return RelationshipStorage(
        map(copy, storage.banks),
        copy(storage.slots),
    )
end

function Base.copyto!(
        destination::RelationshipStorage, source::RelationshipStorage
    )
    Adapt.adapt(Array, destination.slots) == Adapt.adapt(Array, source.slots) ||
        throw(ArgumentError(
        "relationship storages have incompatible canonical slots"
    ))
    length(destination.banks) == length(source.banks) || throw(ArgumentError(
        "relationship storages have incompatible bank counts"
    ))
    for index in eachindex(destination.banks, source.banks)
        target = destination.banks[index]
        values = source.banks[index]
        target isa PackedRelationshipBank && values isa PackedRelationshipBank ||
            throw(ArgumentError(
                "runtime RelationshipStorage copy requires packed banks"))
        copyto!(target, values)
    end
    return destination
end

function _cold_relationship_bank_get(banks::Tuple, bank::Int, slot::Int)
    isempty(banks) && throw(BoundsError(banks, bank))
    bank == 1 && return @inbounds first(banks)[slot]
    return _cold_relationship_bank_get(Base.tail(banks), bank - 1, slot)
end

function Base.getindex(storage::RelationshipStorage, index::Integer)
    location = _relationship_location(storage, index)
    return _cold_relationship_bank_get(
        storage.banks, Int(location.bank), Int(location.slot)
    )
end

function Base.iterate(storage::RelationshipStorage, state::Int = 1)
    state > length(storage) && return nothing
    return storage[state], state + 1
end

Adapt.@adapt_structure RelationshipSlot

"""Validated immutable scientific program and its qualified execution plans."""
struct CompiledPottsProgram{
        T <: AbstractFloat,
        N,
        E <: AbstractProgramEngine,
        B,
        R,
        TP,
        D,
        SP,
        H <: Tuple,
        LP <: AbstractLifecycleExecutionPlan,
        CP <: AbstractCheckerboardPlan,
        Q,
    }
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::Matrix{Int8}
    kind_count::Int16
    medium_kind::Int16
    medium_kinds::BitVector
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    parameter_defaults::Vector{T}
    relationships::R
    tracker_plan::TP
    descriptor_plan::D
    stage_plan::SP
    ownership_change_handles::H
    lifecycle_plan::LP
    checkerboard_plan::CP
    engine::E
    backend::B
    mechanism_authority::Q
    fingerprint::String
    integrity_fingerprint::String
end

"""Own one compiler-supplied value before it enters a durable program."""
_own_compiled_program_value(value) = deepcopy(value)

function _compiled_program_integrity_fingerprint(
        shape,
        periodic,
        proposal_offsets,
        kind_count,
        medium_kind,
        medium_kinds,
        temperature,
        attempts_per_site,
        parameter_defaults,
        relationships,
        tracker_plan,
        descriptor_plan,
        stage_plan,
        ownership_change_handles,
        lifecycle_plan,
        checkerboard_plan,
        engine,
        backend,
        mechanism_authority,
        compiler_fingerprint,
    )
    payload = (
        schema = v"1.0.0",
        shape,
        periodic,
        proposal_offsets,
        kind_count,
        medium_kind,
        medium_kinds,
        temperature,
        attempts_per_site,
        parameter_defaults,
        relationships,
        tracker_plan,
        descriptor_plan,
        stage_plan,
        ownership_change_handles,
        lifecycle_plan,
        checkerboard_plan,
        engine,
        backend,
        mechanism_authority,
        compiler_fingerprint,
    )
    return bytes2hex(SHA.sha256(codeunits(repr(payload))))
end

function _compiled_program_integrity_fingerprint(program::CompiledPottsProgram)
    return _compiled_program_integrity_fingerprint(
        program.shape,
        program.periodic,
        program.proposal_offsets,
        program.kind_count,
        program.medium_kind,
        program.medium_kinds,
        program.temperature,
        program.attempts_per_site,
        program.parameter_defaults,
        program.relationships,
        program.tracker_plan,
        program.descriptor_plan,
        program.stage_plan,
        program.ownership_change_handles,
        program.lifecycle_plan,
        program.checkerboard_plan,
        program.engine,
        program.backend,
        program.mechanism_authority,
        program.fingerprint,
    )
end

function _validate_compiled_program_integrity(program::CompiledPottsProgram)
    actual = _compiled_program_integrity_fingerprint(program)
    actual == program.integrity_fingerprint || throw(ArgumentError(
        "compiled program storage was mutated after construction; rebuild " *
        "the program through the compiler boundary"
    ))
    return program
end

function CompiledPottsProgram(
        shape::NTuple{N, Int},
        periodic::NTuple{N, Bool},
        proposal_offsets::Matrix{Int8},
        kind_count::Integer,
        medium_kind::Integer,
        temperature::CompiledScalar{T},
        attempts_per_site::Integer,
        parameter_defaults::Vector{T},
        relationships,
        tracker_plan::TP,
        descriptor_plan::D,
        stage_plan::SP,
        engine::E,
        backend::B,
        fingerprint::AbstractString;
        medium_kinds = nothing,
        lifecycle_plan::AbstractLifecycleExecutionPlan = NoLifecycleExecutionPlan(),
        checkerboard_plan = nothing,
        ownership_change_handles::Tuple = (),
        mechanism_authority = nothing,
    ) where {T <: AbstractFloat, N, TP, D, SP, E <: AbstractProgramEngine, B}
    all(>(0), shape) || throw(ArgumentError("program dimensions must be positive"))
    size(proposal_offsets, 1) == N ||
        throw(ArgumentError("proposal offsets have the wrong dimensionality"))
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
    attempts_per_site > 0 || throw(ArgumentError(
        "attempts per site must be positive"
    ))
    relationship_storage = relationships isa RelationshipStorage ?
                           relationships : RelationshipStorage(relationships)
    checkerboard_plan === nothing && engine isa CheckerboardProgramEngine &&
        throw(ArgumentError(
            "checkerboard programs require a compiler-derived checkerboard plan"
        ))
    resolved_checkerboard_plan = checkerboard_plan === nothing ?
                                 NoCheckerboardPlan() : checkerboard_plan
    resolved_checkerboard_plan isa AbstractCheckerboardPlan || throw(
        ArgumentError("checkerboard_plan has the wrong type")
    )
    if engine isa CheckerboardProgramEngine
        resolved_checkerboard_plan isa CheckerboardPlan || throw(
            ArgumentError("checkerboard programs require a realized-domain plan")
        )
        resolved_checkerboard_plan.shape == shape || throw(ArgumentError(
            "checkerboard plan shape does not match the compiled program"
        ))
        resolved_checkerboard_plan.periodic == periodic || throw(ArgumentError(
            "checkerboard plan periodicity does not match the compiled program"
        ))
        resolved_checkerboard_plan = CheckerboardPlan(
            resolved_checkerboard_plan.shape,
            resolved_checkerboard_plan.periodic,
            resolved_checkerboard_plan.sites,
            resolved_checkerboard_plan.color_offsets,
            resolved_checkerboard_plan.conflict_displacements,
            resolved_checkerboard_plan.color_count,
            resolved_checkerboard_plan.maximum_color_size,
        )
    end
    engine isa SequentialProgramEngine &&
        !(resolved_checkerboard_plan isa NoCheckerboardPlan) && throw(
            ArgumentError("sequential programs cannot carry a checkerboard plan")
        )
    owned_proposal_offsets = copy(proposal_offsets)
    owned_medium_mask = copy(medium_mask)
    owned_parameter_defaults = copy(parameter_defaults)
    owned_relationship_storage = _own_compiled_program_value(
        relationship_storage
    )
    owned_tracker_plan = _own_compiled_program_value(tracker_plan)
    owned_descriptor_plan = _own_compiled_program_value(descriptor_plan)
    owned_stage_plan = _own_compiled_program_value(stage_plan)
    owned_ownership_change_handles = _own_compiled_program_value(
        ownership_change_handles
    )
    owned_lifecycle_plan = _own_compiled_program_value(
        lifecycle_plan
    )
    owned_checkerboard_plan = _own_compiled_program_value(
        resolved_checkerboard_plan
    )
    owned_engine = _own_compiled_program_value(engine)
    owned_backend = _own_compiled_program_value(backend)
    owned_mechanism_authority = _own_compiled_program_value(
        mechanism_authority
    )
    compiler_fingerprint = String(fingerprint)
    integrity_fingerprint = _compiled_program_integrity_fingerprint(
        shape,
        periodic,
        owned_proposal_offsets,
        Int16(kind_count),
        Int16(medium_kind),
        owned_medium_mask,
        temperature,
        Int32(attempts_per_site),
        owned_parameter_defaults,
        owned_relationship_storage,
        owned_tracker_plan,
        owned_descriptor_plan,
        owned_stage_plan,
        owned_ownership_change_handles,
        owned_lifecycle_plan,
        owned_checkerboard_plan,
        owned_engine,
        owned_backend,
        owned_mechanism_authority,
        compiler_fingerprint,
    )
    return CompiledPottsProgram{
        T, N, typeof(owned_engine), typeof(owned_backend),
        typeof(owned_relationship_storage), typeof(owned_tracker_plan),
        typeof(owned_descriptor_plan), typeof(owned_stage_plan),
        typeof(owned_ownership_change_handles),
        typeof(owned_lifecycle_plan),
        typeof(owned_checkerboard_plan),
        typeof(owned_mechanism_authority),
    }(
        shape,
        periodic,
        owned_proposal_offsets,
        Int16(kind_count),
        Int16(medium_kind),
        owned_medium_mask,
        temperature,
        Int32(attempts_per_site),
        owned_parameter_defaults,
        owned_relationship_storage,
        owned_tracker_plan,
        owned_descriptor_plan,
        owned_stage_plan,
        owned_ownership_change_handles,
        owned_lifecycle_plan,
        owned_checkerboard_plan,
        owned_engine,
        owned_backend,
        owned_mechanism_authority,
        compiler_fingerprint,
        integrity_fingerprint,
    )
end

"""Owned, validated inputs used to initialize one compiled Potts trajectory."""
struct ProgramInitialState{T <: AbstractFloat, N, R, D}
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    relationships::R
    descriptor_state::D
end

_program_initial_field(initial::ProgramInitialState, name::Symbol) =
    getfield(initial, name)

function Base.getproperty(initial::ProgramInitialState, name::Symbol)
    value = _program_initial_field(initial, name)
    name === :descriptor_state && value isa AuxiliaryState &&
        return copy_auxiliary_state(value)
    name === :relationships && return value isa RelationshipStorage ?
        copy(value) : deepcopy(value)
    value isa AbstractArray && return copy(value)
    return value
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
        relationships = (),
        descriptor_state = nothing,
    ) where {N, T <: AbstractFloat}
    owned = Array{Int32, N}(ownership)
    kinds = Int16.(cell_kinds)
    generations = cell_generations === nothing ?
                  ones(UInt32, length(kinds)) :
                  UInt32.(cell_generations)
    length(generations) == length(kinds) ||
        throw(ArgumentError("cell generation table has the wrong length"))
    all(eachindex(kinds)) do index
        @inbounds kinds[index] == 0 || !iszero(generations[index])
    end || throw(ArgumentError("active cell generations must be positive"))
    relationship_values = relationships isa RelationshipStorage ?
        copy(relationships) : Any[deepcopy(value) for value in relationships]
    owned_descriptor_state = descriptor_state === nothing ? nothing :
                             descriptor_state isa AuxiliaryState ?
                             copy_auxiliary_state(descriptor_state) :
                             deepcopy(descriptor_state)
    return ProgramInitialState{
        T, N, typeof(relationship_values), typeof(owned_descriptor_state),
    }(
        owned,
        kinds,
        generations,
        relationship_values,
        owned_descriptor_state,
    )
end

"""
Return an independently owned copy of the initial auxiliary descriptor state.

This is a backend-integration boundary: callers may prepare coupled-component
inputs without inspecting `ProgramInitialState` fields or aliasing the state
that will later be used to construct a Core runtime.
"""
function program_initial_descriptor_state(initial::ProgramInitialState)
    state = _program_initial_field(initial, :descriptor_state)
    state === nothing && return nothing
    state isa AuxiliaryState || throw(ArgumentError(
        "the program initial descriptor state is not a CorePotts AuxiliaryState"
    ))
    return copy_auxiliary_state(state)
end

"""
Rebuild a program initial state with an independently owned descriptor state.

The candidate must preserve the already-validated physical bank layout. Full
schema validation still occurs when the compiled program materializes the
runtime; this boundary additionally rejects nonfinite floating-point payloads
before rebuilding the immutable initial-state value.
"""
function with_program_initial_descriptor_state(
        initial::ProgramInitialState{T}, candidate::AuxiliaryState
    ) where {T <: AbstractFloat}
    expected = _program_initial_field(initial, :descriptor_state)
    expected isa AuxiliaryState || throw(ArgumentError(
        "the program initial state has no CorePotts descriptor-state layout"
    ))
    typeof(candidate.banks) === typeof(expected.banks) || throw(ArgumentError(
        "the replacement descriptor state has an incompatible physical layout or element type"
    ))
    for (candidate_bank, expected_bank) in zip(
            candidate.banks, expected.banks
        )
        axes(candidate_bank.values) == axes(expected_bank.values) || throw(
            ArgumentError(
                "the replacement descriptor state has an incompatible bank shape"
            )
        )
        if eltype(candidate_bank.values) <: AbstractFloat
            all(isfinite, candidate_bank.values) || throw(ArgumentError(
                "the replacement descriptor state contains a nonfinite value"
            ))
        end
    end
    return ProgramInitialState(
        _program_initial_field(initial, :ownership),
        _program_initial_field(initial, :cell_kinds);
        scalar_type = T,
        cell_generations = _program_initial_field(initial, :cell_generations),
        relationships = _program_initial_field(initial, :relationships),
        descriptor_state = candidate,
    )
end

function with_program_initial_descriptor_state(
        initial::ProgramInitialState, candidate
    )
    throw(ArgumentError(
        "the replacement descriptor state must be a CorePotts AuxiliaryState"
    ))
end
