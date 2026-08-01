# Compiled program types and immutable construction contracts.

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
        map(bank -> map(copy, bank), storage.banks),
        copy(storage.slots),
    )
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
Adapt.@adapt_structure RelationshipStorage

struct CompiledPottsProgram{
        T <: AbstractFloat,
        N,
        E <: AbstractProgramEngine,
        B,
        R,
        D,
        SP,
        CP <: AbstractCheckerboardPlan,
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
    descriptor_plan::D
    stage_plan::SP
    checkerboard_plan::CP
    engine::E
    backend::B
    fingerprint::String
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
        descriptor_plan::D,
        stage_plan::SP,
        engine::E,
        backend::B,
        fingerprint::AbstractString;
        medium_kinds = nothing,
        checkerboard_plan = nothing,
    ) where {T <: AbstractFloat, N, D, SP, E <: AbstractProgramEngine, B}
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
    attempts_per_site > 0 ||
        throw(ArgumentError("attempts per site must be positive"))
    relationship_storage = relationships isa RelationshipStorage ?
                           relationships : RelationshipStorage(relationships)
    resolved_checkerboard_plan = if checkerboard_plan === nothing
        engine isa CheckerboardProgramEngine ? CheckerboardPlan(
            shape, periodic, proposal_offsets
        ) : NoCheckerboardPlan()
    else
        checkerboard_plan
    end
    resolved_checkerboard_plan isa AbstractCheckerboardPlan || throw(
        ArgumentError("checkerboard_plan has the wrong type")
    )
    return CompiledPottsProgram{
        T, N, E, B, typeof(relationship_storage), D, SP,
        typeof(resolved_checkerboard_plan),
    }(
        shape,
        periodic,
        copy(proposal_offsets),
        Int16(kind_count),
        Int16(medium_kind),
        medium_mask,
        temperature,
        Int32(attempts_per_site),
        copy(parameter_defaults),
        relationship_storage,
        descriptor_plan,
        stage_plan,
        resolved_checkerboard_plan,
        engine,
        backend,
        String(fingerprint),
    )
end

struct ProgramInitialState{T <: AbstractFloat, N, D}
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    relationships::Vector{Any}
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
    all(!iszero, generations) ||
        throw(ArgumentError("active cell generations must be positive"))
    relationship_values = Any[deepcopy(value) for value in relationships]
    return ProgramInitialState{
        T, N, typeof(descriptor_state),
    }(
        owned,
        kinds,
        generations,
        relationship_values,
        descriptor_state,
    )
end
