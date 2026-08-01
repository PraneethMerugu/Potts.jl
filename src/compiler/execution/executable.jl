# Public executable and engine/backend selections.

abstract type AbstractPottsEngine end

"""
    SequentialEngine()

The V1 stochastic reference engine. Proposal attempts are committed one at a time
in their semantic RNG order.
"""
struct SequentialEngine <: AbstractPottsEngine end

"""
    CheckerboardEngine()

The V1 deterministic checkerboard engine. A compilation error is reported when
the completed model has effects whose touched set cannot be proven.
"""
struct CheckerboardEngine <: AbstractPottsEngine end

abstract type AbstractPottsBackend end

"""The qualified V1 host backend."""
struct CPUBackend <: AbstractPottsBackend end

struct ReferenceUnitDescriptor
    name::Symbol
    dimension::String
    scale::Float64
end

struct RuntimeParameter{D, U}
    name::Symbol
    default::D
    required::Bool
    unit::U
    index::Int
end

struct StructuralParameter{V}
    name::Symbol
    value::V
end

struct ParameterManifest{T <: Tuple, S <: Tuple, R <: Tuple}
    entries::T
    structural::S
    reference_units::R
end

Base.length(manifest::ParameterManifest) = length(manifest.entries)
Base.iterate(manifest::ParameterManifest, state...) =
    iterate(manifest.entries, state...)
Base.getindex(manifest::ParameterManifest, index::Integer) =
    manifest.entries[index]

"""
    PottsParameters

An immutable, normalized runtime-parameter buffer. Construct it through
`PottsProblem(...; p=...)` or `remake`; it cannot change structure or units.
"""
struct PottsParameters{T <: AbstractFloat, V <: Tuple, N <: NamedTuple}
    values::V
    named::N
end

PottsParameters(values::AbstractVector{T}, named::N) where {
        T <: AbstractFloat, N <: NamedTuple,
    } = PottsParameters{T, typeof(Tuple(values)), N}(Tuple(values), named)

Base.getindex(parameters::PottsParameters, name::Symbol) =
    getproperty(parameters.named, name)
Base.propertynames(parameters::PottsParameters) = propertynames(parameters.named)

function _parameter_buffer(values::Tuple, ::Type{T}) where {
        T <: AbstractFloat,
    }
    buffer = Vector{T}(undef, length(values))
    for index in eachindex(values)
        buffer[index] = values[index]
    end
    return buffer
end

_parameter_buffer(parameters::PottsParameters{T}) where {T <: AbstractFloat} =
    _parameter_buffer(parameters.values, T)

struct PottsExecutable{P, M, R, O}
    core_program::P
    parameter_manifest::M
    reports::R
    observations::O
    fingerprint::ExecutableFingerprint
end

function Base.show(io::IO, executable::PottsExecutable)
    report = executable.reports.execution
    print(
        io,
        "PottsExecutable(",
        report.engine,
        ", ",
        report.backend,
        ", ",
        report.scalar_type,
        "; ",
        join(report.shape, "×"),
        ")",
    )
end

executable_fingerprint(executable::PottsExecutable) = executable.fingerprint
