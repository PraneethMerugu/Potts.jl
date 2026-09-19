# Private late-lowered execution plan and public runtime selectors.

"""Supertype of qualified cellular Potts scheduling algorithms."""
abstract type AbstractPottsAlgorithm <: SciMLBase.AbstractSciMLAlgorithm end

"""
    SequentialCPM()

The stochastic reference engine. Proposal attempts are committed one at a time
in their semantic RNG order.
"""
struct SequentialCPM <: AbstractPottsAlgorithm end

"""
    CheckerboardSweepCPM()

The checkerboard sweep process. Every mutable site is scheduled once without
replacement and colors execute in an unbiased semantic-RNG permutation per MCS.
A compilation error is reported when the completed model has effects whose
touched set cannot be proven.
"""
struct CheckerboardSweepCPM <: AbstractPottsAlgorithm end

"""Supertype of explicitly selected Potts execution backends."""
abstract type AbstractPottsBackend end

"""The qualified host backend."""
struct CPUBackend <: AbstractPottsBackend end

"""Apple Metal accelerator selected through the optional Metal extension."""
struct MetalBackend <: AbstractPottsBackend end

_validate_backend_available(::CPUBackend) = nothing
function _validate_backend_available(backend::AbstractPottsBackend)
    throw(
        ArgumentError(
            "$(nameof(typeof(backend))) requires its optional backend package and " *
                "Potts extension"
        )
    )
end

_core_program_backend(::CPUBackend) = CorePotts.BackendSPI.CPUProgramBackend()
_core_program_backend(::MetalBackend) =
    CorePotts.BackendSPI.AdaptedProgramBackend{:MetalBackend}()

_adapt_runtime_backend(::CorePotts.BackendSPI.CPUProgramBackend, runtime) = runtime
function _adapt_runtime_backend(
        backend::CorePotts.BackendSPI.AdaptedProgramBackend, runtime
    )
    throw(
        ArgumentError(
            "$(CorePotts.BackendSPI.program_backend_name(backend)) runtime adaptation " *
                "requires its optional Potts backend extension"
        )
    )
end

# Runtime parameter names stay value-level: they support diagnostics and public
# indexing without parameterizing the normalized runtime-parameter buffer.
struct _RuntimeParameterSchema
    names::Tuple

    function _RuntimeParameterSchema(names)
        normalized = Tuple(Symbol(name) for name in names)
        length(unique(normalized)) == length(normalized) ||
            throw(ArgumentError("runtime parameter names must be unique"))
        return new(normalized)
    end
end

"""
    PottsParameters

An immutable, normalized runtime-parameter buffer. Construct it through
`PottsProblem(...; p=...)` or `remake`; it cannot change structure or units.
"""
struct PottsParameters{T, V <: Tuple}
    values::V
    schema::_RuntimeParameterSchema
end

PottsParameters(values::AbstractVector{T}, named::N) where {T, N <: NamedTuple} =
    PottsParameters{T, typeof(Tuple(values))}(
        Tuple(values), _RuntimeParameterSchema(keys(named)),
    )
PottsParameters(values::Tuple, named::N) where {N <: NamedTuple} =
    PottsParameters{Any, typeof(values)}(
        values, _RuntimeParameterSchema(keys(named)),
    )

function Base.getproperty(parameters::PottsParameters, name::Symbol)
    name === :named || return getfield(parameters, name)
    schema = getfield(parameters, :schema)
    return NamedTuple{schema.names}(getfield(parameters, :values))
end

Base.getindex(parameters::PottsParameters, name::Symbol) =
    let index = findfirst(==(name), parameters.schema.names)
        index === nothing && return getproperty(parameters.named, name)
        parameters.values[index]
    end
Base.propertynames(parameters::PottsParameters) = parameters.schema.names

function _parameter_buffer(values::Tuple, ::Type{T}) where {
        T <: AbstractFloat,
    }
    buffer = T[]
    for value in values
        if value isa StaticArrays.StaticVector
            append!(buffer, value)
        else
            push!(buffer, value)
        end
    end
    return buffer
end

_parameter_buffer(parameters::PottsParameters, ::Type{T}) where {
    T <: AbstractFloat,
} = _parameter_buffer(parameters.values, T)
_parameter_buffer(parameters::PottsParameters{T}) where {T <: AbstractFloat} =
    _parameter_buffer(parameters.values, T)
_parameter_buffer(parameters::PottsParameters) = collect(parameters.values)

struct CompiledRelationshipEndpointPolicy
    identity::CorePotts.CompilerSPI.QualifiedResourceIdentity
    slot::Int32
    direction::Symbol
    kind_a::Int16
    kind_b::Int16
    kind_a_name::Symbol
    kind_b_name::Symbol
end

struct CompiledDomainOwnerIdentity
    lattice::QualifiedStatementID
    local_id::Symbol
end

struct CompiledDomainOwner
    identity::CompiledDomainOwnerIdentity
    kind_identity::QualifiedStatementID
    metadata::CorePotts.CompilerSPI.DomainOwnerMetadata
end

struct _PottsExecutionPlan{P, M, S, R, K, O}
    core_program::P
    parameter_manifest::M
    relationship_endpoint_policies::Vector{CompiledRelationshipEndpointPolicy}
    state_manifest::S
    relationship_manifest::R
    kind_manifest::K
    domain_owner_manifest::Vector{CompiledDomainOwner}
    observations::O
    fingerprint::ExecutableFingerprint
end

function Base.show(io::IO, plan::_PottsExecutionPlan)
    report = CorePotts.program_execution_report(plan.core_program)
    return print(
        io,
        "PottsExecutionPlan(",
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

_execution_plan_fingerprint(plan::_PottsExecutionPlan) = plan.fingerprint

_execution_replay_contract() = (
    class = :exact_same_executable,
    cross_engine = false,
    addressed_rng = true,
)
