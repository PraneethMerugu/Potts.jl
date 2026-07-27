# Final SciML-facing interface over the qualified scientific engine. The historical simulator is
# retained only in `sciml/simulator.jl` under explicit `Legacy*` names for the frozen Toolkit bridge.

const _SII = SciMLBase.SymbolicIndexingInterface

abstract type AbstractPottsModel end

"""A host-side parameterization which leaves an already concrete component set unchanged."""
struct ConstantPottsParameterization{C}
    components::C
end

function (parameterization::ConstantPottsParameterization)(parameters)
    fieldcount(typeof(parameters)) == 0 || throw(ArgumentError(
        "this PottsModel has no runtime parameter declarations; remake the model or supply a typed parameterization"))
    return parameterization.components
end

"""
    PottsModel(proposal_relation, boundary_tracker; components, parameters, ...)

Reusable scientific meaning for the Phase 9 interface. A custom `parameterization` is an ordinary
typed callable which maps the problem's concrete parameter container to a `ScientificComponentSet`
on the host before device adaptation.
"""
struct PottsModel{R, B, M, L, V, P, F, O} <: AbstractPottsModel
    proposal_relation::R
    boundary_tracker::B
    moment_tracker::M
    lifecycle_events::L
    lifecycle_resolver::V
    parameterization::P
    default_p::F
    observable_symbols::O
end

function PottsModel(proposal_relation::StaticCartesianRelation{<:ProposalRole},
        boundary_tracker::BoundaryMeasureTracker;
        components::ScientificComponentSet = ScientificComponentSet(),
        parameters = NamedTuple(), parameterization = nothing,
        moment_tracker = nothing, lifecycle_events::Tuple = (),
        lifecycle_resolver::AbstractLifecycleConflictResolver = RejectLifecycleConflicts(),
        observables::Tuple = ())
    all(symbol -> symbol isa Symbol, observables) || throw(ArgumentError(
        "PottsModel observable declarations must be symbols"))
    length(unique(observables)) == length(observables) || throw(ArgumentError(
        "PottsModel observable declarations must be unique"))
    resolved = parameterization === nothing ?
               ConstantPottsParameterization(components) : parameterization
    realized = resolved(parameters)
    realized isa ScientificComponentSet || throw(ArgumentError(
        "PottsModel parameterization must return ScientificComponentSet"))
    return PottsModel(proposal_relation, boundary_tracker, moment_tracker,
        lifecycle_events, lifecycle_resolver, resolved, parameters, observables)
end

default_parameters(model::PottsModel) = model.default_p
realize_components(model::PottsModel, parameters) = model.parameterization(parameters)
proposal_relation(model::PottsModel) = model.proposal_relation
boundary_tracker(model::PottsModel) = model.boundary_tracker
moment_tracker(model::PottsModel) = model.moment_tracker
lifecycle_events(model::PottsModel) = model.lifecycle_events
lifecycle_resolver(model::PottsModel) = model.lifecycle_resolver
observable_symbols(model::PottsModel) = model.observable_symbols

abstract type AbstractInitialStateOwnership end
struct CopyInitialState <: AbstractInitialStateOwnership end
struct AliasInitialState <: AbstractInitialStateOwnership end

mutable struct InitialStateLease
    lock::ReentrantLock
    active::Bool
end
InitialStateLease() = InitialStateLease(ReentrantLock(), false)

"""Explicit ownership for expert backend-resident initial state."""
struct DeviceInitialState{S, O <: AbstractInitialStateOwnership}
    state::S
    ownership::O
    lease::InitialStateLease
end

DeviceInitialState(state, ownership::AbstractInitialStateOwnership = CopyInitialState()) =
    DeviceInitialState(state, ownership, InitialStateLease())

abstract type AbstractReproducibilityProfile end
struct StrictReproducibility <: AbstractReproducibilityProfile end
struct StatisticalReproducibility <: AbstractReproducibilityProfile end

abstract type AbstractPottsExecutionPolicy end
struct DefaultPottsExecution <: AbstractPottsExecutionPolicy
    block_size::Int
    function DefaultPottsExecution(block_size::Integer = DEFAULT_BLOCK_SIZE)
        block_size > 0 || throw(ArgumentError("block size must be positive"))
        new(Int(block_size))
    end
end

abstract type AbstractSnapshotPolicy end
struct BackendSnapshotPolicy <: AbstractSnapshotPolicy end
struct HostSnapshotPolicy <: AbstractSnapshotPolicy end
struct ObservableSnapshotPolicy{F} <: AbstractSnapshotPolicy
    observe::F
end

abstract type AbstractPottsDeviceCallback end
abstract type AbstractPottsDeviceCallbackEffect end
struct DeviceObservationEffect <: AbstractPottsDeviceCallbackEffect end

"""Typed observable handles read by a device callback's bounded kernel operation."""
device_callback_requirements(callback::AbstractPottsDeviceCallback) =
    throw(MethodError(device_callback_requirements, (callback,)))

"""Declared effects of a device callback; Phase 9 qualifies pure resident observation only."""
device_callback_effects(callback::AbstractPottsDeviceCallback) =
    throw(MethodError(device_callback_effects, (callback,)))

"""Stable ordering priority for resident observations; lower values execute first."""
device_callback_priority(callback::AbstractPottsDeviceCallback) =
    throw(MethodError(device_callback_priority, (callback,)))

"""Whether a typed device callback is due at this completed MCS."""
device_callback_due(callback::AbstractPottsDeviceCallback, mcs::Integer) =
    throw(MethodError(device_callback_due, (callback, mcs)))

"""Launch a bounded resident callback operation without materializing scientific state."""
execute_device_callback!(callback::AbstractPottsDeviceCallback, integrator) =
    throw(MethodError(execute_device_callback!, (callback, integrator)))

function validate_device_callback(callback::AbstractPottsDeviceCallback)
    requirements = device_callback_requirements(callback)
    requirements isa Tuple && all(item -> item isa PottsObservableHandle, requirements) ||
        throw(ArgumentError(
            "device callback requirements must be a tuple of PottsObservableHandle values"))
    effects = device_callback_effects(callback)
    effects isa Tuple && all(item -> item isa AbstractPottsDeviceCallbackEffect, effects) ||
        throw(ArgumentError(
            "device callback effects must be typed AbstractPottsDeviceCallbackEffect values"))
    all(effect -> effect isa DeviceObservationEffect, effects) || throw(
        UnsupportedSolverOptionError(:callback,
            "Phase 9 qualifies GPU-resident pure observation effects; control effects use a standard host DiscreteCallback"))
    priority = device_callback_priority(callback)
    priority isa Integer || throw(ArgumentError(
        "device callback priority must be an integer"))
    return callback
end

struct PottsParameterHandle{Name} end
PottsParameterHandle(name::Symbol) = PottsParameterHandle{name}()
parameter_name(::PottsParameterHandle{Name}) where {Name} = Name

# Keep symbolic parameter indexing scoped to Potts-owned values. Extending
# `Base.getindex` for an unconstrained first argument creates ambiguities with
# every array, dictionary, and SciML indexing method loaded in the process.
struct PottsParameterValues{P}
    values::P
end
Base.propertynames(view::PottsParameterValues, private::Bool = false) =
    propertynames(getfield(view, :values), private)
function Base.getproperty(view::PottsParameterValues, name::Symbol)
    name === :values && return getfield(view, :values)
    return getproperty(getfield(view, :values), name)
end
Base.getindex(view::PottsParameterValues,
    ::PottsParameterHandle{Name}) where {Name} =
    getproperty(getfield(view, :values), Name)

struct PottsObservableHandle{Name} end
PottsObservableHandle(name::Symbol) = PottsObservableHandle{name}()
observable_name(::PottsObservableHandle{Name}) where {Name} = Name

struct InvalidPottsProblemError <: Exception
    messages::Vector{String}
end
Base.showerror(io::IO, error::InvalidPottsProblemError) =
    print(io, "invalid PottsProblem:\n  - ", join(error.messages, "\n  - "))

struct UnsupportedSolverOptionError <: Exception
    option::Symbol
    reason::String
end
Base.showerror(io::IO, error::UnsupportedSolverOptionError) =
    print(io, "unsupported Potts solver option `", error.option, "`: ", error.reason)

struct IntegratorTerminatedError <: Exception
    t::Int
    retcode::SciMLBase.ReturnCode.T
end
Base.showerror(io::IO, error::IntegratorTerminatedError) =
    print(io, "cannot step terminal PottsIntegrator at MCS ", error.t,
        " (retcode ", error.retcode, ")")

struct UnsavedTimeError <: Exception
    t::Int
    available::Vector{Int}
end
Base.showerror(io::IO, error::UnsavedTimeError) =
    print(io, "MCS ", error.t, " was not saved; available MCS values are ", error.available)

struct UnsavedObservableError <: Exception
    name::Symbol
    t::Union{Nothing, Int}
end
function Base.showerror(io::IO, error::UnsavedObservableError)
    print(io, "observable `", error.name, "` was not retained")
    error.t === nothing || print(io, " at MCS ", error.t)
    print(io, "; observable indexing never recomputes or transfers unsaved values")
end

struct PottsCallbackConflictError <: Exception
    message::String
end
Base.showerror(io::IO, error::PottsCallbackConflictError) = print(io, error.message)

struct UnsafePottsSerializationError <: Exception
    value_type::DataType
    alternative::String
end
function Base.showerror(io::IO, error::UnsafePottsSerializationError)
    print(io, "raw Julia serialization is unsupported for ", error.value_type,
        "; ", error.alternative)
end

struct PottsCompilationArtifact
    structural_key::UInt64
    model_type::DataType
    state_type::DataType
    geometry_type::DataType
    parameter_type::DataType
end

struct PottsCompatibilityReport{F, G <: AlgorithmGuaranteeProfile}
    backend::DataType
    backend_family::F
    algorithm::DataType
    dimensions::Int
    qualified::Bool
    messages::Tuple
    guarantee::G
end

struct PottsCompilationReport
    state::DataType
    components::DataType
    workspace::DataType
    launches_before_first_mcs::Int
    host_synchronizations_before_first_mcs::Int
    device_to_host_transfers_before_first_mcs::Int
end

"""Explicit thread-safe cache for trajectory-free compilation metadata."""
mutable struct PottsCompilationCache
    lock::ReentrantLock
    artifacts::Dict{UInt64, PottsCompilationArtifact}
    hits::Int
    misses::Int
end
PottsCompilationCache() = PottsCompilationCache(
    ReentrantLock(), Dict{UInt64, PottsCompilationArtifact}(), 0, 0)

Base.length(cache::PottsCompilationCache) = length(cache.artifacts)
function Base.empty!(cache::PottsCompilationCache)
    lock(cache.lock) do
        empty!(cache.artifacts)
        cache.hits = 0
        cache.misses = 0
    end
    return cache
end
Base.summarysize(cache::PottsCompilationCache) = Base.summarysize(cache.artifacts)
function Base.show(io::IO, cache::PottsCompilationCache)
    print(io, "PottsCompilationCache(", length(cache), " artifacts, ", cache.hits,
        " hits, ", cache.misses, " misses, ", Base.summarysize(cache), " bytes)")
end

function Base.show(io::IO, report::PottsCompatibilityReport)
    print(io, "PottsCompatibilityReport(backend=", nameof(report.backend),
        ", alg=", nameof(report.algorithm), ", ", report.dimensions,
        "D, qualified=", report.qualified,
        ", guarantee=", report.guarantee.guarantee_label,
        ", api=", report.guarantee.api_status, ")")
end

function Base.show(io::IO, report::PottsCompilationReport)
    print(io, "PottsCompilationReport(state=", nameof(report.state),
        ", components=", nameof(report.components), ", workspace=",
        nameof(report.workspace), ")")
end

function _cache_artifact!(cache::PottsCompilationCache, key::UInt64, model, state,
        geometry, parameters)
    lock(cache.lock) do
        if haskey(cache.artifacts, key)
            cache.hits += 1
        else
            cache.misses += 1
            cache.artifacts[key] = PottsCompilationArtifact(key, typeof(model),
                typeof(state), typeof(geometry), typeof(parameters))
        end
        return cache.artifacts[key]
    end
end

"""Immutable portable experiment definition."""
struct PottsProblem{M, U, G, T, P} <: AbstractPottsProblem
    model::M
    u0::U
    geometry::G
    tspan::Tuple{T, T}
    p::P
    capacity::CellCapacity
    seed::UInt64
end

function _integer_mcs(value, label)
    value isa Integer || throw(ArgumentError("$label must be an integer MCS"))
    0 <= value <= typemax(Int) || throw(ArgumentError(
        "$label must be non-negative and fit Int"))
    return Int(value)
end

_initial_capacity(state::LogicalPottsState) = capacity(state)
_initial_capacity(state::InitializedLogicalState) = capacity(logical_state(state))
_initial_capacity(state::CompiledScientificState) = state.potts.descriptor.capacity
_initial_capacity(state::DeviceInitialState) = _initial_capacity(state.state)
_initial_capacity(state) = nothing

function _problem_owned_initial_state(state::LogicalPottsState)
    return deepcopy(assert_valid_state(state))
end
function _problem_owned_initial_state(state::InitializedLogicalState)
    return deepcopy(logical_state(state))
end
_problem_owned_initial_state(state::DeviceInitialState) = state
_problem_owned_initial_state(state) = state

function PottsProblem(model::AbstractPottsModel, u0, geometry::CartesianDomain, tspan;
        p = default_parameters(model), capacity = nothing, seed::Integer = 0, kwargs...)
    isempty(kwargs) || throw(UnsupportedSolverOptionError(first(keys(kwargs)),
        "problem construction accepts only p, capacity, and seed"))
    errors = String[]
    length(tspan) == 2 || push!(errors, "tspan must contain exactly two integer MCS values")
    t0 = length(tspan) >= 1 ? try
        _integer_mcs(tspan[1], "tspan start")
    catch error
        push!(errors, sprint(showerror, error)); 0
    end : 0
    t1 = length(tspan) >= 2 ? try
        _integer_mcs(tspan[2], "tspan end")
    catch error
        push!(errors, sprint(showerror, error)); t0
    end : t0
    t1 >= t0 || push!(errors, "tspan end must not precede its start")
    0 <= seed <= typemax(UInt64) || push!(errors, "seed must fit UInt64")
    p isa AbstractDict && push!(errors, "problem parameters must be a concrete typed container, not a dictionary")
    Base.ismutabletype(typeof(p)) && push!(errors,
        "problem parameters must be an immutable concrete container")
    realized = try
        realize_components(model, p)
    catch error
        push!(errors, sprint(showerror, error)); nothing
    end
    realized isa ScientificComponentSet || push!(errors,
        "model parameterization must realize ScientificComponentSet")
    inferred = _initial_capacity(u0)
    resolved_capacity = if capacity === nothing
        inferred === nothing ? (push!(errors,
            "capacity is required when the initial-state source does not declare one"); CellCapacity(1)) : inferred
    else
        try
            capacity isa CellCapacity ? capacity : CellCapacity(capacity)
        catch error
            push!(errors, sprint(showerror, error)); CellCapacity(1)
        end
    end
    inferred !== nothing && resolved_capacity != inferred && push!(errors,
        "problem capacity must match the fixed capacity carried by u0")
    if u0 isa LogicalPottsState
        lattice_size(u0) == geometry.dims || push!(errors,
            "logical initial-state dimensions must match geometry")
    elseif u0 isa CompiledScientificState
        u0.potts.descriptor.lattice_dims == geometry.dims || push!(errors,
            "compiled initial-state dimensions must match geometry")
    elseif u0 isa DeviceInitialState && u0.state isa CompiledScientificState
        u0.state.potts.descriptor.lattice_dims == geometry.dims || push!(errors,
            "device initial-state dimensions must match geometry")
    end
    isempty(errors) || throw(InvalidPottsProblemError(errors))
    return PottsProblem(model, _problem_owned_initial_state(u0), geometry,
        (t0, t1), p, resolved_capacity, UInt64(seed))
end

function SciMLBase.remake(prob::PottsProblem; model = prob.model, u0 = prob.u0,
        geometry = prob.geometry, tspan = prob.tspan, p = prob.p,
        capacity = prob.capacity, seed = prob.seed, kwargs...)
    isempty(kwargs) || throw(UnsupportedSolverOptionError(first(keys(kwargs)),
        "unknown remake field"))
    return PottsProblem(model, u0, geometry, tspan; p, capacity, seed)
end

Base.getindex(prob::PottsProblem, ::PottsParameterHandle{Name}) where {Name} =
    getproperty(prob.p, Name)

problem_geometry(prob::PottsProblem) = prob.geometry

_parameter_symbols(parameters) = fieldnames(typeof(parameters))
_SII.is_parameter(prob::PottsProblem, symbol::Symbol) =
    symbol in _parameter_symbols(prob.p)
_SII.parameter_index(prob::PottsProblem, symbol::Symbol) =
    _SII.is_parameter(prob, symbol) ? PottsParameterHandle(symbol) : nothing
_SII.parameter_symbols(prob::PottsProblem) = collect(_parameter_symbols(prob.p))
_SII.is_variable(::PottsProblem, symbol) = false
_SII.variable_index(::PottsProblem, symbol) = nothing
_SII.variable_symbols(::PottsProblem) = Symbol[]
_SII.is_independent_variable(::PottsProblem, symbol) = symbol === :t
_SII.independent_variable_symbols(::PottsProblem) = [:t]
_SII.is_time_dependent(::PottsProblem) = true
_SII.constant_structure(::PottsProblem) = true
_SII.is_observed(prob::PottsProblem, symbol) = symbol in observable_symbols(prob.model)
_SII.parameter_values(prob::PottsProblem) = PottsParameterValues(prob.p)

function Base.show(io::IO, prob::PottsProblem)
    print(io, "PottsProblem(", prob.geometry.dims, ", tspan=", prob.tspan,
        ", capacity=", nslots(prob.capacity), ", seed=0x",
        string(prob.seed, base = 16, pad = 16), ", model=", nameof(typeof(prob.model)), ")")
end

function compatibility_report(prob::PottsProblem, alg::AbstractPottsAlgorithm,
        backend::KernelAbstractions.Backend = KernelAbstractions.CPU())
    capabilities = backend_capabilities(backend)
    dimensions = length(prob.geometry.dims)
    guarantee = algorithm_guarantees(alg)
    messages = String[]
    supports(capabilities, QualifiedBackendCapability()) ||
        push!(messages, "backend is not qualified")
    dimensions in guarantee.dimensions ||
        push!(messages, "algorithm does not declare this dimension")
    components = try
        realize_components(prob.model, prob.p)
    catch error
        push!(messages, "model parameterization failed: $(sprint(showerror, error))")
        nothing
    end
    if components isa ScientificComponentSet
        for component in _all_scientific_components(components)
            component_supports_dimension(component, dimensions) || push!(messages,
                "component $(typeof(component)) does not declare $(dimensions)D support")
            component_supports_backend(component, capabilities) || push!(messages,
                "component $(typeof(component)) is not qualified for backend $(typeof(backend))")
        end
        append!(messages, algorithm_component_compatibility(
            alg, components, moment_tracker(prob.model)))
    else
        components === nothing || push!(messages,
            "model parameterization did not return ScientificComponentSet")
    end
    return PottsCompatibilityReport(typeof(backend), capabilities.family, typeof(alg),
        dimensions, isempty(messages), Tuple(unique(messages)), guarantee)
end

struct SavedPottsState{S}
    t::Int
    state::S
    residency::Symbol
end

"""Return the exact completed-MCS coordinate carried by a saved solution entry."""
snapshot_mcs(saved::SavedPottsState) = saved.t

"""Return the declared storage residency of a saved solution entry."""
snapshot_residency(saved::SavedPottsState) = saved.residency

"""
    snapshot_state(saved::SavedPottsState)

Return the complete logical host state retained by `HostSnapshotPolicy`.

This accessor never transfers, synchronizes, or reconstructs data. Device, backend-native, and
observable-only entries fail with an actionable error.
"""
function snapshot_state(saved::SavedPottsState)
    saved.residency === :host && saved.state isa LogicalPottsState ||
        throw(ArgumentError(
            "saved entry at MCS $(saved.t) does not contain a complete logical host state; " *
            "solve with snapshot_policy=HostSnapshotPolicy() or request explicit observables"))
    return saved.state
end

function Base.getindex(saved::SavedPottsState,
        ::PottsObservableHandle{Name}) where {Name}
    saved.residency === :observable && hasproperty(saved.state, Name) ||
        throw(UnsavedObservableError(Name, saved.t))
    return getproperty(saved.state, Name)
end

struct PottsStats
    completed_mcs::Int
    launches::Int
    host_synchronizations::Int
    host_to_device_transfers::Int
    device_to_host_transfers::Int
    host_allocations::Int
    device_allocations::Int
    saved_states::Int
    host_callback_boundaries::Int
    device_callback_invocations::Int
end

function Base.merge(left::PottsStats, right::PottsStats)
    values = ntuple(index -> getfield(left, index) + getfield(right, index),
        fieldcount(PottsStats))
    return PottsStats(values...)
end

@enum PottsIntegratorStatus::UInt8 begin
    PottsRunning = 1
    PottsSucceeded = 2
    PottsTerminated = 3
    PottsMaxIters = 4
    PottsFailed = 5
end

mutable struct PottsIntegrator{I, P, A, O, C}
    inner::I
    prob::P
    alg::A
    t::Int
    status::PottsIntegratorStatus
    retcode::SciMLBase.ReturnCode.T
    options::O
    callbacks::C
    sol_u::Vector{Any}
    sol_t::Vector{Int}
    checkpoints::Vector{Any}
    steps::Int
    host_callback_boundaries::Int
    device_callback_invocations::Int
    solution::Any
    alias_lease::Union{Nothing, InitialStateLease}
end

function Serialization.serialize(serializer::Serialization.AbstractSerializer,
        integrator::PottsIntegrator)
    throw(UnsafePottsSerializationError(typeof(integrator),
        "capture a CanonicalCheckpoint or retain explicit host observations"))
end

function Serialization.serialize(serializer::Serialization.AbstractSerializer,
        integrator::ScientificPottsIntegrator)
    throw(UnsafePottsSerializationError(typeof(integrator),
        "capture a CanonicalCheckpoint instead of serializing live workspaces"))
end

function Serialization.serialize(serializer::Serialization.AbstractSerializer,
        initial::DeviceInitialState)
    throw(UnsafePottsSerializationError(typeof(initial),
        "use a host LogicalPottsState or a CanonicalCheckpoint for distribution"))
end

function Base.getproperty(integrator::PottsIntegrator, name::Symbol)
    if name === :u
        return getfield(integrator, :inner).state
    elseif name === :p
        return PottsParameterValues(getfield(integrator, :prob).p)
    elseif name === :sol
        return getfield(integrator, :solution)
    else
        return getfield(integrator, name)
    end
end

function Base.show(io::IO, integrator::PottsIntegrator)
    print(io, "PottsIntegrator(t=", integrator.t, ", backend=",
        nameof(typeof(integrator.inner.plan.backend)), ", alg=",
        nameof(typeof(integrator.alg)), ", status=", integrator.status, ")")
end

struct PottsSolution{U, P, A, S} <: SciMLBase.AbstractTimeseriesSolution{Any, 1, Any}
    u::U
    t::Vector{Int}
    prob::P
    alg::A
    retcode::SciMLBase.ReturnCode.T
    stats::S
    checkpoints::Vector{Any}
    provenance::NamedTuple
end

Base.length(sol::PottsSolution) = length(sol.t)
Base.firstindex(sol::PottsSolution) = firstindex(sol.t)
Base.lastindex(sol::PottsSolution) = lastindex(sol.t)
Base.getindex(sol::PottsSolution, index::Int) = sol.u[index]
solution_problem(sol::PottsSolution) = sol.prob
function Base.getindex(sol::PottsSolution, handle::PottsObservableHandle)
    name = observable_name(handle)
    _SII.is_observed(sol.prob, name) || throw(UnsavedObservableError(name, nothing))
    return [saved[handle] for saved in sol.u]
end
function (sol::PottsSolution)(t::Integer)
    index = findfirst(==(Int(t)), sol.t)
    index === nothing && throw(UnsavedTimeError(Int(t), copy(sol.t)))
    return sol.u[index]
end
function Base.getproperty(sol::PottsSolution, name::Symbol)
    if name === :dense
        return false
    elseif name === :interp
        return nothing
    elseif name === :destats
        return getfield(sol, :stats)
    else
        return getfield(sol, name)
    end
end
function Base.show(io::IO, sol::PottsSolution)
    print(io, "PottsSolution(retcode=", sol.retcode, ", saved=", length(sol),
        ", interval=", isempty(sol.t) ? "empty" : "$(first(sol.t)):$(last(sol.t))",
        ", backend=", sol.provenance.backend, ", alg=", nameof(typeof(sol.alg)), ")")
end

execution_adaptor(::KernelAbstractions.CPU) = Array
function execution_adaptor(backend::KernelAbstractions.Backend)
    throw(UnsupportedBackendType(typeof(backend)))
end

function _structural_key(prob::PottsProblem, alg, backend, options)
    return UInt64(hash((typeof(prob.model), typeof(prob.u0), typeof(prob.geometry),
        prob.geometry.dims, nslots(prob.capacity), typeof(prob.p), typeof(alg),
        typeof(backend), typeof(options.snapshot_policy))))
end

function _acquire_initial_state(prob::PottsProblem, backend, adaptor)
    source = prob.u0
    if source isa LogicalPottsState
        compiled = compile_scientific_state(deepcopy(source), prob.geometry,
            boundary_tracker(prob.model); moment_tracker = moment_tracker(prob.model))
        return Adapt.adapt(adaptor, compiled), nothing
    elseif source isa CompiledScientificState
        return Adapt.adapt(adaptor, deepcopy(source)), nothing
    elseif source isa DeviceInitialState
        state = source.state
        actual_backend = KernelAbstractions.get_backend(state.potts.storage.active)
        isequal(actual_backend, backend) || throw(ArgumentError(
            "device initial state backend does not match solve backend"))
        if source.ownership isa CopyInitialState
            return deepcopy(state), nothing
        end
        lock(source.lease.lock) do
            source.lease.active && throw(ArgumentError(
                "aliased device initial state already has an active integrator"))
            source.lease.active = true
        end
        return state, source.lease
    end
    throw(ArgumentError("unsupported initial-state source $(typeof(source))"))
end

function _release_alias!(integrator::PottsIntegrator)
    lease = integrator.alias_lease
    lease === nothing && return integrator
    lock(lease.lock) do
        lease.active = false
    end
    integrator.alias_lease = nothing
    return integrator
end

function _normalize_saveat(saveat, tspan)
    t0, t1 = tspan
    values = if saveat === nothing || saveat === ()
        Int[]
    elseif saveat isa Integer
        saveat > 0 || throw(ArgumentError("scalar saveat must be a positive MCS interval"))
        collect((t0 + Int(saveat)):Int(saveat):t1)
    else
        [_integer_mcs(value, "saveat value") for value in saveat]
    end
    all(value -> t0 <= value <= t1, values) || throw(ArgumentError(
        "saveat values must lie within tspan"))
    return sort!(unique!(values))
end

function _partition_callbacks(callback)
    callback === nothing && return ((), ())
    callback isa SciMLBase.AbstractContinuousCallback && throw(
        UnsupportedSolverOptionError(:callback,
            "continuous callbacks and root finding are undefined for integer-MCS dynamics"))
    if hasproperty(callback, :continuous_callbacks) &&
       !isempty(callback.continuous_callbacks)
        throw(UnsupportedSolverOptionError(:callback,
            "continuous callbacks and root finding are undefined for integer-MCS dynamics"))
    end
    callbacks = hasproperty(callback, :discrete_callbacks) ?
                Tuple(callback.discrete_callbacks) : callback isa Tuple ? callback : (callback,)
    any(item -> item isa SciMLBase.AbstractContinuousCallback, callbacks) && throw(
        UnsupportedSolverOptionError(:callback,
            "continuous callbacks and root finding are undefined for integer-MCS dynamics"))
    device = Tuple(item for item in callbacks if item isa AbstractPottsDeviceCallback)
    host = Tuple(item for item in callbacks if !(item isa AbstractPottsDeviceCallback))
    foreach(validate_device_callback, device)
    device = Tuple(sort!(collect(device); by = device_callback_priority,
        alg = Base.Sort.MergeSort))
    return host, device
end

function _validate_solver_kwargs(kwargs)
    forbidden = (:adaptive, :abstol, :reltol, :dt, :sensealg)
    for key in keys(kwargs)
        key in forbidden && throw(UnsupportedSolverOptionError(key,
            "Cellular Potts time is fixed to one integer MCS and generic trajectory AD is undefined"))
        throw(UnsupportedSolverOptionError(key, "unknown Potts solver keyword"))
    end
end

function _snapshot_state(integrator::PottsIntegrator, policy::BackendSnapshotPolicy)
    residency = integrator.inner.plan.backend isa KernelAbstractions.CPU ? :host : :device
    snapshot = deepcopy(integrator.inner.state)
    record_allocation!(integrator.inner.plan, residency,
        scientific_state_bytes(snapshot))
    return SavedPottsState(integrator.t, snapshot, residency)
end
function _snapshot_state(integrator::PottsIntegrator, ::HostSnapshotPolicy)
    return SavedPottsState(integrator.t, logical_state(integrator.inner), :host)
end
function _snapshot_state(integrator::PottsIntegrator, policy::ObservableSnapshotPolicy)
    observed = policy.observe(integrator)
    declarations = observable_symbols(integrator.prob.model)
    observed isa NamedTuple || throw(ArgumentError(
        "ObservableSnapshotPolicy must return a NamedTuple"))
    missing = Tuple(symbol for symbol in declarations if !hasproperty(observed, symbol))
    isempty(missing) || throw(ArgumentError(
        "observable snapshot omitted declared values $(missing)"))
    return SavedPottsState(integrator.t, observed, :observable)
end

function _save_due!(integrator::PottsIntegrator; force::Bool = false)
    options = integrator.options
    due = force || options.save_everystep || integrator.t in options.saveat
    due || return integrator
    if !isempty(integrator.sol_t) && last(integrator.sol_t) == integrator.t
        return integrator
    end
    push!(integrator.sol_u, _snapshot_state(integrator, options.snapshot_policy))
    push!(integrator.sol_t, integrator.t)
    return integrator
end

SciMLBase.savevalues!(integrator::PottsIntegrator) =
    _save_due!(integrator; force = true)

function _run_callbacks!(integrator::PottsIntegrator)
    host_callbacks, device_callbacks = integrator.callbacks
    for callback in device_callbacks
        device_callback_due(callback, integrator.t) || continue
        execute_device_callback!(callback, integrator)
        integrator.device_callback_invocations += 1
    end
    isempty(host_callbacks) && return integrator
    snapshot = logical_state(integrator.inner)
    integrator.host_callback_boundaries += 1
    for callback in host_callbacks
        hasproperty(callback, :condition) && hasproperty(callback, :affect!) ||
            throw(ArgumentError("host callbacks must provide condition and affect!"))
        callback.condition(snapshot, integrator.t, integrator) && callback.affect!(integrator)
    end
    return integrator
end

function _stats(integrator::PottsIntegrator)
    metrics = integrator.inner.plan.metrics
    return PottsStats(integrator.steps, metrics.launches, metrics.host_synchronizations,
        metrics.host_to_device_transfers, metrics.device_to_host_transfers,
        metrics.host_allocations, metrics.device_allocations, length(integrator.sol_t),
        integrator.host_callback_boundaries, integrator.device_callback_invocations)
end

function _finalize_solution!(integrator::PottsIntegrator)
    integrator.solution !== nothing && return integrator.solution
    if integrator.options.save_end
        _save_due!(integrator; force = true)
    end
    provenance = (
        seed = integrator.prob.seed,
        rng_version = rng_contract_version(integrator.inner.rng),
        backend = nameof(typeof(integrator.inner.plan.backend)),
        backend_family = integrator.inner.plan.capabilities.family,
        algorithm_guarantee = algorithm_guarantees(integrator.alg),
        model_fingerprint = scientific_model_fingerprint(integrator.inner),
        storage = nameof(typeof(integrator.options.snapshot_policy)),
    )
    solution = PottsSolution(copy(integrator.sol_u), copy(integrator.sol_t),
        integrator.prob, integrator.alg, integrator.retcode, _stats(integrator),
        copy(integrator.checkpoints), provenance)
    integrator.solution = solution
    _release_alias!(integrator)
    return solution
end

function SciMLBase.__init(prob::PottsProblem, alg::AbstractPottsAlgorithm, args...;
        backend::KernelAbstractions.Backend = KernelAbstractions.CPU(), adaptor = nothing,
        cache::Union{Nothing, PottsCompilationCache} = nothing,
        reproducibility::AbstractReproducibilityProfile = StrictReproducibility(),
        execution::AbstractPottsExecutionPolicy = DefaultPottsExecution(),
        saveat = (), save_everystep::Bool = false, save_start::Bool = true,
        save_end::Bool = true, snapshot_policy::AbstractSnapshotPolicy = BackendSnapshotPolicy(),
        callback = nothing, maxiters = nothing, progress::Bool = false,
        progress_steps::Integer = 1, verbose::Bool = true,
        checkpoint::Union{Nothing, CanonicalCheckpoint} = nothing, kwargs...)
    isempty(args) || throw(ArgumentError("Potts init accepts no positional solver arguments"))
    _validate_solver_kwargs(kwargs)
    progress_steps > 0 || throw(ArgumentError("progress_steps must be a positive integer MCS interval"))
    reproducibility isa StrictReproducibility || @warn(
        "statistical reproducibility was requested; the selected algorithm profile remains authoritative")
    execution isa DefaultPottsExecution || throw(ArgumentError(
        "unsupported execution policy $(typeof(execution))"))
    resolved_adaptor = adaptor === nothing ? execution_adaptor(backend) : adaptor
    options = (
        saveat = _normalize_saveat(saveat, prob.tspan),
        save_everystep,
        save_start,
        save_end,
        snapshot_policy,
        maxiters = maxiters === nothing ? prob.tspan[2] - prob.tspan[1] :
                   _integer_mcs(maxiters, "maxiters"),
        progress,
        progress_steps = Int(progress_steps),
        verbose,
        reproducibility,
        execution,
    )
    callbacks = _partition_callbacks(callback)
    state, lease = _acquire_initial_state(prob, backend, resolved_adaptor)
    successful = false
    try
    components = realize_components(prob.model, prob.p)
    components isa ScientificComponentSet || throw(ArgumentError(
        "model parameterization must return ScientificComponentSet"))
    adapted_components = Adapt.adapt(resolved_adaptor, components)
    metrics = ExecutionMetrics()
    plan = ExecutionPlan(backend; block_size = execution.block_size, metrics)
    events = lifecycle_events(prob.model)
    lifecycle = isempty(events) ? NoCompiledLifecycle() :
                compile_lifecycle(events, state, plan;
                    resolver = lifecycle_resolver(prob.model))
    inner = init_scientific(state, proposal_relation(prob.model), adapted_components, alg;
        seed = prob.seed, plan, moment_tracker = moment_tracker(prob.model), lifecycle)
    inner.mcs = UInt64(prob.tspan[1])
    if checkpoint !== nothing
        restored = CorePotts.restore_checkpoint(checkpoint, inner; adaptor = resolved_adaptor)
        prob.tspan[1] <= restored.mcs <= prob.tspan[2] || throw(
            CheckpointCompatibilityError(:mcs, string(prob.tspan), string(restored.mcs)))
        inner = restored
    end
    cache === nothing || _cache_artifact!(cache,
        _structural_key(prob, alg, backend, options), prob.model, state, prob.geometry, prob.p)
    t = Int(inner.mcs)
    status = t == prob.tspan[2] ? PottsSucceeded : PottsRunning
    retcode = status === PottsSucceeded ? SciMLBase.ReturnCode.Success : SciMLBase.ReturnCode.Default
    integrator = PottsIntegrator(inner, prob, alg, t, status, retcode, options,
        callbacks, Any[], Int[], Any[], 0, 0, 0, nothing, lease)
    if integrator.status === PottsRunning && options.maxiters == 0
        integrator.status = PottsMaxIters
        integrator.retcode = SciMLBase.ReturnCode.MaxIters
    end
    if save_start
        _save_due!(integrator; force = true)
    end
    if verbose && !(backend isa KernelAbstractions.CPU) && alg isa SequentialCPM
        @info "SequentialCPM is intentionally selected on a GPU; CheckerboardSweepCPM and LotteryCPM are distinct explicit parallel dynamics"
    end
    successful = true
    return integrator
    finally
        if !successful && lease !== nothing
            lock(lease.lock) do
                lease.active = false
            end
        end
    end
end

function SciMLBase.__init(prob::PottsProblem, args...; kwargs...)
    return SciMLBase.__init(prob, SequentialCPM(), args...; kwargs...)
end

function SciMLBase.init(prob::PottsProblem, alg::AbstractPottsAlgorithm, args...; kwargs...)
    return SciMLBase.__init(prob, alg, args...; kwargs...)
end
SciMLBase.init(prob::PottsProblem, args...; kwargs...) =
    SciMLBase.__init(prob, SequentialCPM(), args...; kwargs...)

function _perform_potts_step!(integrator::PottsIntegrator)
    SciMLBase.step!(integrator.inner)
    integrator.t = Int(integrator.inner.mcs)
    integrator.steps += 1
    _save_due!(integrator)
    _run_callbacks!(integrator)
    if integrator.status === PottsRunning && integrator.t >= integrator.prob.tspan[2]
        integrator.status = PottsSucceeded
        integrator.retcode = SciMLBase.ReturnCode.Success
    elseif integrator.status === PottsRunning && integrator.steps >= integrator.options.maxiters
        integrator.status = PottsMaxIters
        integrator.retcode = SciMLBase.ReturnCode.MaxIters
    end
    if integrator.options.progress && integrator.t % integrator.options.progress_steps == 0
        @info "Potts solve progress" mcs = integrator.t final_mcs = integrator.prob.tspan[2]
    end
    return integrator
end

function SciMLBase.step!(integrator::PottsIntegrator)
    integrator.status === PottsRunning || throw(
        IntegratorTerminatedError(integrator.t, integrator.retcode))
    try
        return _perform_potts_step!(integrator)
    catch
        integrator.status = PottsFailed
        integrator.retcode = SciMLBase.ReturnCode.Failure
        _release_alias!(integrator)
        rethrow()
    end
end

function SciMLBase.step!(integrator::PottsIntegrator, steps::Integer)
    steps >= 0 || throw(ArgumentError("Potts step count must be non-negative"))
    for _ in 1:steps
        SciMLBase.step!(integrator)
    end
    return integrator
end

function SciMLBase.terminate!(integrator::PottsIntegrator,
        retcode = SciMLBase.ReturnCode.Terminated)
    integrator.status === PottsRunning || return integrator
    integrator.status = PottsTerminated
    integrator.retcode = retcode
    return integrator
end

function SciMLBase.solve!(integrator::PottsIntegrator)
    integrator.solution !== nothing && return integrator.solution
    while integrator.status === PottsRunning
        SciMLBase.step!(integrator)
    end
    return _finalize_solution!(integrator)
end

function SciMLBase.__solve(prob::PottsProblem, alg::AbstractPottsAlgorithm, args...; kwargs...)
    return SciMLBase.solve!(SciMLBase.__init(prob, alg, args...; kwargs...))
end
SciMLBase.__solve(prob::PottsProblem, args...; kwargs...) =
    SciMLBase.__solve(prob, SequentialCPM(), args...; kwargs...)

function SciMLBase.solve(prob::PottsProblem, alg::AbstractPottsAlgorithm, args...; kwargs...)
    return SciMLBase.__solve(prob, alg, args...; kwargs...)
end
SciMLBase.solve(prob::PottsProblem, args...; kwargs...) =
    SciMLBase.__solve(prob, SequentialCPM(), args...; kwargs...)

function restore_checkpoint(checkpoint::CanonicalCheckpoint, prob::PottsProblem,
        alg::AbstractPottsAlgorithm; kwargs...)
    return SciMLBase.init(prob, alg; checkpoint, kwargs...)
end

logical_state(integrator::PottsIntegrator) = logical_state(integrator.inner)
current_mcs_report(integrator::PottsIntegrator) = current_mcs_report(integrator.inner)
algorithm_guarantees(integrator::PottsIntegrator) = algorithm_guarantees(integrator.alg)
function compilation_report(integrator::PottsIntegrator)
    metrics = integrator.inner.plan.metrics
    return PottsCompilationReport(typeof(integrator.inner.state),
        typeof(integrator.inner.components), typeof(integrator.inner.algorithm_workspace),
        metrics.launches, metrics.host_synchronizations,
        metrics.device_to_host_transfers)
end

function set_parameter!(integrator::PottsIntegrator,
        ::PottsParameterHandle{Name}, value) where {Name}
    integrator.status === PottsRunning || throw(
        IntegratorTerminatedError(integrator.t, integrator.retcode))
    hasproperty(integrator.prob.p, Name) || throw(ArgumentError(
        "problem has no parameter `$(Name)`"))
    previous = getproperty(integrator.prob.p, Name)
    typeof(value) === typeof(previous) || throw(ArgumentError(
        "runtime parameter changes must preserve concrete type $(typeof(previous))"))
    replacement = NamedTuple{(Name,)}((value,))
    parameters = ConstructionBase.setproperties(integrator.prob.p, replacement)
    components = realize_components(integrator.prob.model, parameters)
    components isa ScientificComponentSet || throw(ArgumentError(
        "model parameterization must return ScientificComponentSet"))
    adaptor = execution_adaptor(integrator.inner.plan.backend)
    adapted = Adapt.adapt(adaptor, components)
    typeof(adapted) === typeof(integrator.inner.components) || throw(ArgumentError(
        "runtime parameter change altered component structure; use remake and init"))
    remade = SciMLBase.remake(integrator.prob; p = parameters)
    typeof(remade) === typeof(integrator.prob) || throw(ArgumentError(
        "runtime parameter change altered problem structure; use remake and init"))
    integrator.inner.components = adapted
    integrator.prob = remade
    return integrator
end
analysis_snapshot(integrator::PottsIntegrator; kwargs...) =
    analysis_snapshot(integrator.inner; kwargs...)
function capture_checkpoint(integrator::PottsIntegrator; retain::Bool = false, kwargs...)
    checkpoint = capture_checkpoint(integrator.inner; kwargs...)
    retain && push!(integrator.checkpoints, checkpoint)
    return checkpoint
end

function _problem_schema(prob::PottsProblem)
    source = prob.u0 isa DeviceInitialState ? prob.u0.state : prob.u0
    if source isa LogicalPottsState
        return source.properties.schema
    elseif source isa CompiledScientificState
        return source.potts.descriptor.property_schema
    end
    throw(ArgumentError("initial-state source does not expose a checkpoint schema"))
end

function import_checkpoint(checkpoint::CanonicalCheckpoint, prob::PottsProblem)
    logical = checkpoint_logical_state(checkpoint, _problem_schema(prob))
    endpoint = max(Int(checkpoint.mcs), prob.tspan[2])
    imported = SciMLBase.remake(prob; u0 = logical,
        tspan = (Int(checkpoint.mcs), endpoint), seed = checkpoint.seed)
    report = LogicalImportReport(checkpoint.checksum, checkpoint.profile.backend,
        CPUFamily, :statistical_or_weaker,
        ("logical import creates a new portable problem",))
    return imported, report
end

abstract type AbstractEnsembleSeedPolicy end
struct EnsembleSeedDerivationV1 <: AbstractEnsembleSeedPolicy end
struct UserManagedEnsembleSeeds <: AbstractEnsembleSeedPolicy end

function ensemble_seed(::EnsembleSeedDerivationV1, master_seed::UInt64,
        trajectory::Integer, rerun::Integer = 1)
    1 <= trajectory <= typemax(UInt32) || throw(ArgumentError(
        "ensemble trajectory identity must lie in 1:typemax(UInt32)"))
    1 <= rerun <= typemax(UInt8) + 1 || throw(ArgumentError(
        "ensemble rerun identity exceeds the v1 address domain"))
    address = RNGAddress(stream = EnsembleStream, mcs = 0, subround = 0,
        operation = 1, entity_kind = EnsembleEntity, entity = trajectory,
        invocation = rerun - 1, draw = 0)
    words = rng_words(Philox4x32x10V1(), master_seed, address)
    return UInt64(words[1]) | (UInt64(words[2]) << 32)
end
function ensemble_seed(policy::EnsembleSeedDerivationV1, master_seed::Integer,
        trajectory::Integer, rerun::Integer = 1)
    0 <= master_seed <= typemax(UInt64) || throw(ArgumentError(
        "ensemble master seed must fit UInt64"))
    return ensemble_seed(policy, UInt64(master_seed), trajectory, rerun)
end

struct PottsEnsembleProbFunc{F, P <: AbstractEnsembleSeedPolicy}
    user::F
    master_seed::UInt64
    policy::P
end

function (wrapped::PottsEnsembleProbFunc)(prob, context)
    candidate = wrapped.user(prob, context)
    candidate isa PottsProblem || throw(ArgumentError(
        "Potts ensemble prob_func must return PottsProblem, got $(typeof(candidate))"))
    wrapped.policy isa UserManagedEnsembleSeeds && return candidate
    seed = ensemble_seed(wrapped.policy, wrapped.master_seed,
        context.sim_id, context.repeat)
    return SciMLBase.remake(candidate; seed)
end

struct PottsEnsembleOutputFunc{F}
    user::F
    max_reruns::Int
end
function (wrapped::PottsEnsembleOutputFunc)(solution, context)
    result = wrapped.user(solution, context)
    normalized = result isa Tuple ? result : (result, false)
    length(normalized) == 2 || throw(ArgumentError(
        "ensemble output_func must return output or (output, rerun)"))
    rerun = Bool(normalized[2])
    rerun && context.repeat > wrapped.max_reruns && throw(ArgumentError(
        "ensemble trajectory $(context.sim_id) exceeded max_reruns=$(wrapped.max_reruns)"))
    return normalized[1], rerun
end

function SciMLBase.EnsembleProblem(prob::PottsProblem;
        prob_func = SciMLBase.DEFAULT_PROB_FUNC,
        output_func = SciMLBase.DEFAULT_OUTPUT_FUNC,
        reduction = SciMLBase.DEFAULT_REDUCTION, u_init = nothing,
        safetycopy::Bool = false, seed::Integer = prob.seed, rng = nothing,
        seed_policy::AbstractEnsembleSeedPolicy = EnsembleSeedDerivationV1(),
        max_reruns::Integer = 0)
    0 <= seed <= typemax(UInt64) || throw(ArgumentError(
        "ensemble seed must fit UInt64"))
    max_reruns >= 0 || throw(ArgumentError("max_reruns must be non-negative"))
    master_seed = rng === nothing ? UInt64(seed) : rand(rng, UInt64)
    wrapped_prob = PottsEnsembleProbFunc(prob_func, master_seed, seed_policy)
    wrapped_output = PottsEnsembleOutputFunc(output_func, Int(max_reruns))
    return SciMLBase.EnsembleProblem(prob, wrapped_prob, wrapped_output,
        reduction, u_init, safetycopy)
end

function SciMLBase.__solve(prob::SciMLBase.EnsembleProblem{<:PottsProblem},
        alg::AbstractPottsAlgorithm, ensemblealg::SciMLBase.EnsembleThreads;
        backend::KernelAbstractions.Backend = KernelAbstractions.CPU(), kwargs...)
    backend isa KernelAbstractions.CPU || throw(ArgumentError(
        "same-device threaded GPU ensembles are not qualified; use EnsembleSerial or explicit multi-device execution"))
    return invoke(SciMLBase.__solve,
        Tuple{SciMLBase.AbstractEnsembleProblem, Any, SciMLBase.BasicEnsembleAlgorithm},
        prob, alg, ensemblealg; backend, kwargs...)
end
