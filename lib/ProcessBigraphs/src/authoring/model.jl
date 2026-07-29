const AUTHORING_CONTRACT_VERSION = "process-bigraph-authoring-v2"

abstract type AbstractAuthoringHandle end

"""
Builder-local identity. It is used only to reject handles from another
transaction and never contributes to diagnostics, serialization, or model
identity.
"""
mutable struct AuthoringScope end

struct StoreHandle{S<:AbstractSchema,O} <: AbstractAuthoringHandle
    owner::O
    name::Symbol
    target::Path
    schema::S
end

struct ComponentHandle{L,O} <: AbstractAuthoringHandle
    owner::O
    name::Symbol
    law::L
end

struct PortHandle{P<:PortSpec,O} <: AbstractAuthoringHandle
    owner::O
    component::Symbol
    name::Symbol
    contract::P
end

struct ParameterHandle{T,O} <: AbstractAuthoringHandle
    owner::O
    name::Symbol
    default::T
end

struct ObservableHandle{O,T} <: AbstractAuthoringHandle
    owner::O
    name::Symbol
    declaration::T
end

struct MountedCompositeHandle{O} <: AbstractAuthoringHandle
    owner::O
    name::Symbol
    endpoints::Tuple{Vararg{Symbol}}
end

struct MountedEndpointHandle{O} <: AbstractAuthoringHandle
    owner::O
    mount::Symbol
    name::Symbol
end

struct TemplateHandle{O} <: AbstractAuthoringHandle
    owner::O
    name::Symbol
    definition_id::String
    capacity::Int
end

"""
Declare the problem-level parameters consumed by a component law.

Domain packages extend this together with `with_parameters`. The default is
parameter-free and keeps ProcessBigraphs independent of concrete solvers.
"""
parameter_names(::Union{AbstractProcess,AbstractStep}) = ()

function with_parameters(
    law::Union{AbstractProcess,AbstractStep},
    values::NamedTuple,
)
    isempty(values) ||
        _fail(:missing_parameter_binding_method,
            "component declares run parameters but does not implement with_parameters";
            law=string(typeof(law)), parameters=tuple(keys(values)...))
    law
end

function _component_port(handle::ComponentHandle, name::Symbol)
    contract = findfirst(port -> port.name === name, ports(getfield(handle, :law)))
    isnothing(contract) &&
        _fail(:unknown_component_port,
            "component does not declare the requested port";
            component=getfield(handle, :name), port=name)
    spec = ports(getfield(handle, :law))[contract]
    PortHandle(getfield(handle, :owner), getfield(handle, :name), name, spec)
end

function Base.getproperty(handle::ComponentHandle, name::Symbol)
    name in fieldnames(typeof(handle)) && return getfield(handle, name)
    _component_port(handle, name)
end

Base.propertynames(handle::ComponentHandle; private::Bool=false) =
    tuple(fieldnames(typeof(handle))...,
        (port.name for port in ports(getfield(handle, :law)))...)

function Base.getproperty(handle::MountedCompositeHandle, name::Symbol)
    name in fieldnames(typeof(handle)) && return getfield(handle, name)
    name in getfield(handle, :endpoints) ||
        _fail(:unknown_mounted_endpoint,
            "mounted composite does not expose the requested endpoint";
            mount=getfield(handle, :name), endpoint=name)
    MountedEndpointHandle(
        getfield(handle, :owner), getfield(handle, :name), name)
end

Base.propertynames(handle::MountedCompositeHandle; private::Bool=false) =
    tuple(fieldnames(typeof(handle))..., getfield(handle, :endpoints)...)

function Base.show(io::IO, handle::AbstractAuthoringHandle)
    print(io, nameof(typeof(handle)), "(:", getfield(handle, :name), ")")
end

struct HandleNamespace{H}
    handles::Tuple{Vararg{H}}
end

function Base.getproperty(namespace::HandleNamespace, name::Symbol)
    name === :handles && return getfield(namespace, :handles)
    position = findfirst(handle -> getfield(handle, :name) === name,
        getfield(namespace, :handles))
    isnothing(position) &&
        _fail(:unknown_authoring_name,
            "semantic namespace does not contain the requested name"; name)
    getfield(namespace, :handles)[position]
end

Base.propertynames(namespace::HandleNamespace; private::Bool=false) =
    tuple((getfield(handle, :name)
        for handle in getfield(namespace, :handles))...)

struct Every
    cadence::Duration
    first_due::Duration
    supports_partial::Bool
end

Every(cadence::Duration;
    first_due::Duration=cadence,
    supports_partial::Bool=true,
) = Every(cadence, first_due, supports_partial)

function _canonical(io::IO, schedule::Every)
    write(io, "EV")
    _canonical(io, schedule.cadence)
    _canonical(io, schedule.first_due)
    _canonical(io, schedule.supports_partial)
end

struct At
    times::Tuple{Vararg{LogicalTime}}
    function At(times::Tuple{Vararg{LogicalTime}})
        isempty(times) &&
            _fail(:empty_at_schedule,
                "At requires at least one logical time")
        ordered = tuple(sort!(collect(times);
            by=time -> (time.scale.unit, time.scale.numerator,
                time.scale.denominator, time.tick))...)
        length(ordered) == length(unique(ordered)) ||
            _fail(:duplicate_schedule_time,
                "At contains duplicate logical times")
        new(ordered)
    end
end

At(time::LogicalTime, rest::LogicalTime...) = At((time, rest...))
At(times::AbstractVector{<:LogicalTime}) = At(tuple(times...))

function _canonical(io::IO, schedule::At)
    write(io, "AT")
    _canonical(io, schedule.times)
end

struct On{T}
    trigger::T
end

struct After
    components::Tuple{Vararg{Symbol}}
end

After(handles::ComponentHandle...) =
    After(tuple((getfield(handle, :name) for handle in handles)...))
After(names::Union{Symbol,AbstractString}...) =
    After(tuple(Symbol.(names)...))

function _canonical(io::IO, schedule::After)
    write(io, "AF")
    _canonical(io, schedule.components)
end

struct SemanticStore
    name::Symbol
    target::Path
    schema::AbstractSchema
    has_initial::Bool
    initial::Any
end

struct SemanticActor
    name::Symbol
    law::Union{AbstractProcess,AbstractStep}
    kind::Symbol
    schedule::Any
    dependencies::Tuple{Vararg{Symbol}}
    domain::Symbol
    continuation::Any
    continuation_version::String
end

struct SemanticBinding
    component::Symbol
    port::Symbol
    target::Path
    transfer::Union{Nothing,TransferDeclaration}
end

struct SemanticEndpoint
    name::Symbol
    target::Path
    role::Symbol
    transfer::Union{Nothing,TransferDeclaration}
end

struct SemanticParameter
    name::Symbol
    default::Any
    units::Union{Nothing,String}
    description::String
end

struct SemanticObservable
    name::Symbol
    target::Path
    schema::AbstractSchema
    description::String
end

function _canonical(io::IO, observable::SemanticObservable)
    write(io, "AO")
    _canonical(io, observable.name)
    _canonical(io, observable.target)
    _canonical(io, observable.schema)
    _canonical(io, observable.description)
end

struct SemanticTemplate
    name::Symbol
    definition_id::String
    model::Any
    capacity::Int
end

struct SemanticMount
    name::Symbol
    model::Any
end

struct SemanticMountedBinding
    mount::Symbol
    endpoint::Symbol
    target::Path
end

function _canonical(io::IO, binding::SemanticBinding)
    write(io, "AB")
    _canonical(io, binding.component)
    _canonical(io, binding.port)
    _canonical(io, binding.target)
    _canonical(io, binding.transfer)
end

function _canonical(io::IO, endpoint::SemanticEndpoint)
    write(io, "AE")
    _canonical(io, endpoint.name)
    _canonical(io, endpoint.target)
    _canonical(io, endpoint.role)
    _canonical(io, endpoint.transfer)
end

function _canonical(io::IO, parameter::SemanticParameter)
    write(io, "AP")
    _canonical(io, parameter.name)
    _canonical(io, parameter.default)
    _canonical(io, parameter.units)
    _canonical(io, parameter.description)
end

function _canonical(io::IO, binding::SemanticMountedBinding)
    write(io, "AM")
    _canonical(io, binding.mount)
    _canonical(io, binding.endpoint)
    _canonical(io, binding.target)
end

struct ValidationDiagnostic
    code::Symbol
    severity::Symbol
    message::String
    subject::Union{Nothing,Symbol}
    location::Tuple
    related::Tuple
    expected::Any
    actual::Any
    suggestion::String
    context::NamedTuple
end

struct ValidationReport
    profile::Symbol
    diagnostics::Tuple{Vararg{ValidationDiagnostic}}
    fingerprint::String
end

Base.isempty(report::ValidationReport) =
    !any(diagnostic -> diagnostic.severity === :error, report.diagnostics)

struct ModelValidationError <: Exception
    report::ValidationReport
end

function Base.showerror(io::IO, error::ModelValidationError)
    failures = filter(diagnostic -> diagnostic.severity === :error,
        error.report.diagnostics)
    print(io, "ModelValidationError: ", length(failures),
        " authoring error", length(failures) == 1 ? "" : "s")
    for diagnostic in failures
        print(io, "\n  [", diagnostic.code, "] ", diagnostic.message)
        isnothing(diagnostic.subject) ||
            print(io, " (", diagnostic.subject, ")")
    end
end

"""
Immutable author-facing scientific and compositional meaning.

The value contains no live builder and is distinct from canonical ACSet IR and
from the execution plan.
"""
struct CompositeModel
    contract_version::String
    name::Symbol
    scale::TimeScale
    stores::Tuple{Vararg{SemanticStore}}
    actors::Tuple{Vararg{SemanticActor}}
    bindings::Tuple{Vararg{SemanticBinding}}
    iterations::Tuple{Vararg{IterationRegion}}
    endpoints::Tuple{Vararg{SemanticEndpoint}}
    parameters::Tuple{Vararg{SemanticParameter}}
    observables::Tuple{Vararg{SemanticObservable}}
    templates::Tuple{Vararg{SemanticTemplate}}
    mounts::Tuple{Vararg{SemanticMount}}
    mounted_bindings::Tuple{Vararg{SemanticMountedBinding}}
    profile::Symbol
    fingerprint::String
end

struct AuthorOrigin
    kind::Symbol
    name::Symbol
    location::Tuple
    canonical_identity::String
    path::Union{Nothing,Path}
end

struct LoweredModel
    contract_version::String
    semantic_fingerprint::String
    canonical::CanonicalModel
    origins::Tuple{Vararg{AuthorOrigin}}
    fingerprint::String
end

function Base.show(io::IO, model::LoweredModel)
    print(io, "LoweredModel(semantic=\"",
        first(model.semantic_fingerprint, 12),
        "…\", ir=\"", first(model.fingerprint, 12),
        "…\", origins=", length(model.origins), ")")
end

struct AttachmentReport
    component::Symbol
    connected::Tuple{Vararg{Symbol}}
    missing_required::Tuple{Vararg{Symbol}}
    extra::Tuple{Vararg{Symbol}}
end

function Base.show(io::IO, report::AttachmentReport)
    print(io, "AttachmentReport(:", report.component,
        "; connected=", report.connected,
        ", missing=", report.missing_required,
        ", extra=", report.extra, ")")
end
