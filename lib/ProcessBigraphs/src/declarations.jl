struct PortSpec{T}
    name::Symbol
    direction::Symbol
    effect::Symbol
    interval_behavior::Symbol
    optional::Bool
    cardinality::Symbol
    residency::Symbol
    update_law::Union{Nothing,Symbol}
end

function PortSpec(
    ::Type{T},
    name::Symbol,
    direction::Symbol;
    effect::Symbol=direction === :input ? :read : :write,
    interval_behavior::Symbol=:event_updated,
    optional::Bool=false,
    cardinality::Symbol=:one,
    residency::Symbol=:inherit,
    update_law=nothing,
) where {T}
    direction in (:input, :output) ||
        _fail(:invalid_port_direction, "ports must be input or output"; name, direction)
    effect in (:read, :write) ||
        _fail(:invalid_port_effect, "ports must declare read or write effects"; name, effect)
    direction === :input && effect !== :read &&
        _fail(:input_write_effect, "input ports cannot write"; name)
    direction === :output && effect !== :write &&
        _fail(:output_read_effect, "output ports must publish effects"; name)
    interval_behavior in (:frozen, :interpolated, :event_updated, :continuously_callable) ||
        _fail(:invalid_interval_behavior, "unknown interval input behavior";
            name, interval_behavior)
    cardinality in (:one, :many) ||
        _fail(:invalid_cardinality, "unknown port cardinality"; name, cardinality)
    residency in (:inherit, :cpu, :metal, :rocm, :cuda) ||
        _fail(:invalid_port_residency, "unknown port residency"; name, residency)
    PortSpec{T}(name, direction, effect, interval_behavior, optional, cardinality,
        residency, isnothing(update_law) ? nothing : Symbol(update_law))
end

InputPort(type::Type, name::Symbol; kwargs...) =
    PortSpec(type, name, :input; kwargs...)
OutputPort(type::Type, name::Symbol; kwargs...) =
    PortSpec(type, name, :output; kwargs...)

struct PortBinding
    owner::String
    port::Symbol
    target::Path
    transfer::Union{Nothing,TransferDeclaration}
end

PortBinding(owner::AbstractString, port::Symbol, target::Path; transfer=nothing) =
    PortBinding(String(owner), port, target, transfer)

abstract type AbstractProcess end
abstract type AbstractStep end

ports(::Union{AbstractProcess,AbstractStep}) = ()
capabilities(::Union{AbstractProcess,AbstractStep}) = CapabilitySet()
semantic_version(::Union{AbstractProcess,AbstractStep}) = "1"
semantic_parameters(::Union{AbstractProcess,AbstractStep}) = NamedTuple()

function invoke(law::Union{AbstractProcess,AbstractStep}, inputs, context)
    _fail(:missing_invoke_method, "process or step does not implement invoke";
        law=string(typeof(law)))
end

struct FixedSchedule
    cadence::Duration
    first_due::Duration
    supports_partial::Bool
    function FixedSchedule(
        cadence::Duration;
        first_due::Duration=cadence,
        supports_partial::Bool=true,
    )
        cadence.tick > 0 ||
            _fail(:nonpositive_cadence, "temporal process cadence must be positive")
        cadence.scale == first_due.scale ||
            _fail(:time_scale_mismatch, "schedule durations must use one scale")
        first_due.tick > 0 ||
            _fail(:nonpositive_deadline, "first process deadline must be positive")
        new(cadence, first_due, supports_partial)
    end
end

struct ProcessDeclaration{P<:AbstractProcess,C}
    id::String
    law::P
    schedule::FixedSchedule
    domain::Symbol
    continuation::C
    continuation_version::String
end

function ProcessDeclaration(
    id::AbstractString,
    law::P,
    schedule::FixedSchedule;
    domain::Symbol=:cpu,
    continuation=nothing,
    continuation_version::AbstractString="1",
) where {P<:AbstractProcess}
    isempty(id) && _fail(:empty_process_identity, "process identity cannot be empty")
    domain in capabilities(law).domains ||
        _fail(:unsupported_execution_domain, "process does not support selected domain";
            id, domain, supported=capabilities(law).domains)
    ProcessDeclaration{P,typeof(continuation)}(
        String(id), law, schedule, domain, deepcopy(continuation),
        String(continuation_version))
end

struct StepDeclaration{S<:AbstractStep,C}
    id::String
    law::S
    dependencies::Tuple{Vararg{String}}
    domain::Symbol
    continuation::C
    continuation_version::String
end

function StepDeclaration(
    id::AbstractString,
    law::S;
    dependencies=(),
    domain::Symbol=:cpu,
    continuation=nothing,
    continuation_version::AbstractString="1",
) where {S<:AbstractStep}
    isempty(id) && _fail(:empty_step_identity, "step identity cannot be empty")
    domain in capabilities(law).domains ||
        _fail(:unsupported_execution_domain, "step does not support selected domain";
            id, domain, supported=capabilities(law).domains)
    StepDeclaration{S,typeof(continuation)}(
        String(id), law, tuple(String.(dependencies)...), domain,
        deepcopy(continuation), String(continuation_version))
end

struct InvocationContext
    owner::String
    event_id::String
    start_time::LogicalTime
    end_time::LogicalTime
    elapsed::Duration
    continuation::Any
    outputs::Tuple
end

struct InvocationResult
    deltas::Tuple{Vararg{Delta}}
    continuation::Any
    diagnostics::NamedTuple
end

InvocationResult(deltas=(); continuation=nothing, diagnostics=NamedTuple()) =
    InvocationResult(tuple(deltas...), continuation, diagnostics)

function emit(context::InvocationContext, port::Symbol, law::AbstractUpdateLaw, payload)
    position = findfirst(pair -> first(pair) == port, context.outputs)
    isnothing(position) &&
        _fail(:unknown_output_port, "invocation emitted through an undeclared output";
            owner=context.owner, port)
    target, schema = last(context.outputs[position])
    Delta(target, schema, law, payload;
        producer=context.owner, event_id=context.event_id)
end

struct PortView
    snapshot_version::UInt64
    snapshot_fingerprint::String
    values::Tuple{Vararg{Pair{Symbol,Any}}}
end

function Base.getindex(view::PortView, name::Symbol)
    position = findfirst(pair -> first(pair) == name, view.values)
    isnothing(position) && _fail(:unknown_port, "port is not present in invocation input"; name)
    deepcopy(last(view.values[position]))
end

Base.haskey(view::PortView, name::Symbol) =
    any(pair -> first(pair) == name, view.values)

function _canonical(io::IO, port::PortSpec{T}) where {T}
    write(io, "PO")
    _canonical(io, string(T))
    _canonical(io, port.name)
    _canonical(io, port.direction)
    _canonical(io, port.effect)
    _canonical(io, port.interval_behavior)
    _canonical(io, port.optional)
    _canonical(io, port.cardinality)
    _canonical(io, port.residency)
    _canonical(io, port.update_law)
end

function _canonical(io::IO, binding::PortBinding)
    write(io, "BI")
    _canonical(io, binding.owner)
    _canonical(io, binding.port)
    _canonical(io, binding.target)
    _canonical(io, binding.transfer)
end

function _declaration_identity(declaration::Union{ProcessDeclaration,StepDeclaration})
    (
        declaration.id,
        string(typeof(declaration.law)),
        semantic_version(declaration.law),
        semantic_parameters(declaration.law),
        declaration.domain,
        capabilities(declaration.law),
        ports(declaration.law),
        declaration.continuation_version,
    )
end
