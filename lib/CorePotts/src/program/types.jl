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
    relationships isa Tuple || throw(ArgumentError(
        "compiled relationship schemas must be a tuple"
    ))
    return CompiledPottsProgram{
        T, N, E, B, typeof(relationships), D, SP,
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
    relationships isa Tuple || throw(ArgumentError(
        "program relationship initial values must be a tuple aligned to schemas"
    ))
    relationship_values = deepcopy(relationships)
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
