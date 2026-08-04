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

"""Apple Metal accelerator selected through the optional Metal extension."""
struct MetalBackend <: AbstractPottsBackend end

"""NVIDIA accelerator selector reserved for the backend-neutral release matrix."""
struct CUDABackend <: AbstractPottsBackend end

"""AMD accelerator selector reserved for the backend-neutral release matrix."""
struct ROCmBackend <: AbstractPottsBackend end

_validate_backend_available(::CPUBackend) = nothing
function _validate_backend_available(backend::AbstractPottsBackend)
    throw(ArgumentError(
        "$(nameof(typeof(backend))) requires its optional backend package and " *
        "PottsToolkit extension"
    ))
end

_core_program_backend(::CPUBackend) = CorePotts.CPUProgramBackend()
_core_program_backend(::MetalBackend) =
    CorePotts.AdaptedProgramBackend{:MetalBackend}()
_core_program_backend(::CUDABackend) =
    CorePotts.AdaptedProgramBackend{:CUDABackend}()
_core_program_backend(::ROCmBackend) =
    CorePotts.AdaptedProgramBackend{:ROCmBackend}()

_adapt_runtime_backend(::CorePotts.CPUProgramBackend, runtime) = runtime
function _adapt_runtime_backend(
        backend::CorePotts.AdaptedProgramBackend, runtime
    )
    throw(ArgumentError(
        "$(CorePotts.program_backend_name(backend)) runtime adaptation " *
        "requires its optional PottsToolkit backend extension"
    ))
end

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

struct CompiledRelationshipEndpointPolicy
    identity::CorePotts.QualifiedResourceIdentity
    slot::Int32
    direction::Symbol
    kind_a::Int16
    kind_b::Int16
    kind_a_name::Symbol
    kind_b_name::Symbol
end

struct PottsExecutable{P, M, R, O}
    core_program::P
    parameter_manifest::M
    relationship_endpoint_policies::Vector{CompiledRelationshipEndpointPolicy}
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
