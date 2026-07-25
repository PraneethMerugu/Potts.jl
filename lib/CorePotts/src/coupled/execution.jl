abstract type AbstractMCSPlanEntry end
abstract type AbstractProcessInvocation end

struct CoupledPhase{I <: Tuple} <: AbstractMCSPlanEntry
    name::Symbol
    invocations::I
    version::VersionNumber

    function CoupledPhase(name::Symbol, invocations::I;
            version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION) where {I <: Tuple}
        isempty(String(name)) && throw(ArgumentError("phase identity must not be empty"))
        isempty(invocations) && throw(ArgumentError(
            "a coupled Phase must contain at least one process invocation"))
        all(invocation -> invocation isa AbstractProcessInvocation, invocations) ||
            throw(ArgumentError(
                "coupled Phase entries must be typed process invocations"))
        return new{I}(name, invocations, version)
    end
end

CoupledPhase(name::Symbol, invocations::AbstractProcessInvocation...; kwargs...) =
    CoupledPhase(name, Tuple(invocations); kwargs...)

struct PottsAttempts{E <: Tuple} <: AbstractMCSPlanEntry
    on_accept::E
    version::VersionNumber
end
function PottsAttempts(; on_accept::Tuple = (),
        version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION)
    all(effect -> effect isa AcceptedCopyUpdate, on_accept) || throw(ArgumentError(
        "PottsAttempts on_accept entries must be AcceptedCopyUpdate values"))
    return PottsAttempts(on_accept, version)
end

struct LifecyclePhase <: AbstractMCSPlanEntry
    version::VersionNumber
end
LifecyclePhase() = LifecyclePhase(COUPLED_EXECUTION_CONTRACT_VERSION)

struct ObservationPhase{O <: Tuple} <: AbstractMCSPlanEntry
    observations::O
    version::VersionNumber
end
ObservationPhase(observations...;
    version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION) =
    ObservationPhase(Tuple(observations), version)

"""One immutable, explicitly ordered coupled MCS plan."""
struct MCSPlan{E <: Tuple, T}
    entries::E
    timeline::T
    version::VersionNumber

    function MCSPlan(entries::E; timeline = nothing,
            version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION) where {E <: Tuple}
        isempty(entries) && throw(ArgumentError("MCSPlan must not be empty"))
        all(entry -> entry isa AbstractMCSPlanEntry, entries) || throw(ArgumentError(
            "MCSPlan entries must use registered plan-entry families"))
        if timeline !== nothing
            length(entries) == 1 && only(entries) isa ObservationPhase ||
                throw(ArgumentError(
                    "a multirate MCSPlan stores exactly one final ObservationPhase"))
            _validate_multirate_timeline(timeline)
            return new{E, typeof(timeline)}(entries, timeline, version)
        end
        potts = findall(entry -> entry isa PottsAttempts, entries)
        lifecycle = findall(entry -> entry isa LifecyclePhase, entries)
        observation = findall(entry -> entry isa ObservationPhase, entries)
        length(potts) == 1 || throw(ArgumentError(
            "MCSPlan requires exactly one PottsAttempts stage"))
        length(lifecycle) == 1 || throw(ArgumentError(
            "MCSPlan requires exactly one LifecyclePhase"))
        length(observation) == 1 || throw(ArgumentError(
            "MCSPlan requires exactly one ObservationPhase"))
        only(potts) < only(lifecycle) < only(observation) || throw(ArgumentError(
            "MCSPlan requires PottsAttempts before LifecyclePhase before ObservationPhase"))
        only(observation) == length(entries) || throw(ArgumentError(
            "ObservationPhase must be the final ordinary MCSPlan entry"))
        names = Tuple(entry.name for entry in entries if entry isa CoupledPhase)
        length(unique(names)) == length(names) || throw(ArgumentError(
            "coupled phase identities must be unique within one MCSPlan"))
        _validate_plan_write_conflicts(entries)
        return new{E, Nothing}(entries, nothing, version)
    end
end
MCSPlan(entries::AbstractMCSPlanEntry...; kwargs...) =
    MCSPlan(Tuple(entries); kwargs...)
MCSPlan(; timeline, observation::ObservationPhase = ObservationPhase(),
    version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION) =
    MCSPlan((observation,); timeline, version)

_validate_multirate_timeline(timeline) = throw(ArgumentError(
    "unsupported multirate timeline type $(typeof(timeline))"))

component_identity(::MCSPlan) =
    ComponentIdentity(:coupled_mcs_plan, COUPLED_EXECUTION_CONTRACT_VERSION, :execution_plan)
component_semantic_data(plan::MCSPlan) = plan.timeline === nothing ?
    (entries = plan.entries, version = plan.version) :
    (timeline = plan.timeline, observation = only(plan.entries),
        version = plan.version)

struct Advance{P, I, A} <: AbstractProcessInvocation
    process::P
    interval::I
    active::A
    label::Symbol
end
Advance(process; interval, active = nothing, label::Symbol = :advance) =
    Advance(process, interval, active, label)

struct Exchange{P, A, M} <: AbstractProcessInvocation
    process::P
    active::A
    mode::M
    label::Symbol
end
Exchange(process; active = nothing, mode = nothing,
        label::Symbol = :exchange) =
    Exchange(process, active, mode, label)

struct Sample{P, A} <: AbstractProcessInvocation
    process::P
    active::A
    label::Symbol
end
Sample(process; active = nothing, label::Symbol = :sample) =
    Sample(process, active, label)
Sample(history::HistorySample; kwargs...) = Sample{typeof(history), Nothing}(
    history, nothing, get(kwargs, :label, :sample))

struct Update{P, A} <: AbstractProcessInvocation
    process::P
    active::A
    label::Symbol
end
Update(process; active = nothing, label::Symbol = :update) =
    Update(process, active, label)

invocation_process(invocation::AbstractProcessInvocation) = invocation.process
invocation_reads(invocation::AbstractProcessInvocation) =
    process_reads(invocation_process(invocation))
invocation_writes(invocation::AbstractProcessInvocation) =
    process_writes(invocation_process(invocation))
process_reads(process) = throw(ArgumentError(
    "$(typeof(process)) must implement the public process_reads protocol"))
process_writes(process) = throw(ArgumentError(
    "$(typeof(process)) must implement the public process_writes protocol"))
process_reads(process::SiteDynamics) = ((:site, process.property),)
process_writes(process::SiteDynamics) = ((:site, process.property),)
process_reads(sample::HistorySample) = ((:history_source, sample.history),)
process_writes(sample::HistorySample) = ((:history, sample.history),)

function _validate_plan_write_conflicts(entries)
    for phase in entries
        phase isa CoupledPhase || continue
        all(invocation -> invocation.active === nothing ||
                invocation.active isa Union{During, AbstractMCSSchedule},
            phase.invocations) || throw(ArgumentError(
            "process activation must be During(...), an MCS schedule, or nothing"))
        writes = Tuple(target for invocation in phase.invocations
            for target in invocation_writes(invocation))
        length(unique(writes)) == length(writes) || throw(ArgumentError(
            "phase `$(phase.name)` has conflicting writes without a resolver"))
    end
    return entries
end

struct MCSRange
    first::UInt64
    last::UInt64
    function MCSRange(first::Integer, last::Integer)
        0 < first <= last <= typemax(UInt64) || throw(ArgumentError(
            "MCSRange endpoints must be positive, ordered, and fit UInt64"))
        return new(UInt64(first), UInt64(last))
    end
end
Base.in(mcs::Integer, range::MCSRange) =
    range.first <= mcs <= range.last

struct During
    stages::Tuple{Vararg{Symbol}}
    function During(stages::Symbol...)
        isempty(stages) && throw(ArgumentError("During requires at least one stage"))
        length(unique(stages)) == length(stages) || throw(ArgumentError(
            "During stage identities must be unique"))
        return new(Tuple(stages))
    end
end

struct ProtocolStage
    name::Symbol
    mcs::MCSRange
end
ProtocolStage(name::Symbol; mcs::MCSRange) = ProtocolStage(name, mcs)

struct StagedProtocol{S <: Tuple}
    stages::S
    version::VersionNumber
end
component_identity(::StagedProtocol) =
    ComponentIdentity(:staged_protocol, COUPLED_EXECUTION_CONTRACT_VERSION, :protocol)
component_semantic_data(protocol::StagedProtocol) = (
    stages = protocol.stages, version = protocol.version)
component_effects(::StagedProtocol) = (:protocol_selection,)
function StagedProtocol(stages::ProtocolStage...;
        version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION)
    isempty(stages) && throw(ArgumentError(
        "StagedProtocol requires at least one ProtocolStage"))
    ordered = Tuple(sort!(collect(stages); by = stage -> stage.mcs.first))
    length(unique(stage.name for stage in ordered)) == length(ordered) ||
        throw(ArgumentError("protocol stage identities must be unique"))
    for index in 2:length(ordered)
        ordered[index - 1].mcs.last < ordered[index].mcs.first ||
            throw(ArgumentError("protocol stage ranges must not overlap"))
    end
    return StagedProtocol(ordered, version)
end

function stage_for(protocol::StagedProtocol, target_mcs::Integer)
    index = findfirst(stage -> target_mcs in stage.mcs, protocol.stages)
    index === nothing && throw(ArgumentError(
        "StagedProtocol does not cover target MCS $target_mcs"))
    return protocol.stages[index]
end
stage_local_mcs(stage::ProtocolStage, target_mcs::Integer) =
    UInt64(target_mcs) - stage.mcs.first + UInt64(1)

struct ScheduledParameter{P, V}
    name::Symbol
    protocol::P
    values::V
    version::VersionNumber
end
component_identity(parameter::ScheduledParameter) =
    ComponentIdentity(parameter.name, parameter.version, :scheduled_parameter)
component_semantic_data(parameter::ScheduledParameter) = (
    protocol = component_semantic_data(parameter.protocol),
    values = parameter.values)
function ScheduledParameter(name::Symbol, protocol::StagedProtocol;
        version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION, kwargs...)
    values = (; kwargs...)
    expected = Set(stage.name for stage in protocol.stages)
    Set(propertynames(values)) == expected || throw(ArgumentError(
        "ScheduledParameter must provide exactly one value for every protocol stage"))
    types = Tuple(typeof(value) for value in values)
    all(type -> type === first(types), types) || throw(ArgumentError(
        "ScheduledParameter stage values must share one concrete type"))
    return ScheduledParameter(name, protocol, values, version)
end
scheduled_value(parameter::ScheduledParameter, stage::ProtocolStage) =
    getproperty(parameter.values, stage.name)

struct ContinuousClock{T <: AbstractFloat}
    name::Symbol
    per_mcs::T
    unit::Symbol
    origin::T
    version::VersionNumber
end
component_identity(clock::ContinuousClock) =
    ComponentIdentity(clock.name, clock.version, :continuous_clock)
component_semantic_data(clock::ContinuousClock) = (
    per_mcs = clock.per_mcs, unit = clock.unit, origin = clock.origin)
function ContinuousClock(name::Symbol; per_mcs::T, unit::Symbol,
        origin = nothing,
        version::VersionNumber = COUPLED_EXECUTION_CONTRACT_VERSION) where {
        T <: AbstractFloat}
    isfinite(per_mcs) && per_mcs > zero(T) || throw(ArgumentError(
        "continuous-clock per_mcs must be finite and positive"))
    resolved_origin = origin === nothing ? zero(T) : convert(T, origin)
    isfinite(resolved_origin) || throw(ArgumentError(
        "continuous-clock origin must be finite"))
    return ContinuousClock(name, per_mcs, unit, resolved_origin, version)
end

struct ContinuousInterval{T <: AbstractFloat}
    value::T
    unit::Symbol
    function ContinuousInterval(value::T, unit::Symbol) where {T <: AbstractFloat}
        isfinite(value) && value > zero(T) || throw(ArgumentError(
            "continuous interval must be finite and positive"))
        return new{T}(value, unit)
    end
end
struct OneMCS end
struct HalfMCS end

interval_value(clock::ContinuousClock, ::OneMCS) = clock.per_mcs
interval_value(clock::ContinuousClock, ::HalfMCS) = clock.per_mcs / 2
function interval_value(clock::ContinuousClock, interval::ContinuousInterval)
    interval.unit === clock.unit || throw(ArgumentError(
        "continuous interval unit does not match its process clock"))
    return convert(typeof(clock.per_mcs), interval.value)
end

struct NoStagedProtocol end

mutable struct CoupledState{S <: Tuple, H <: Tuple, R <: Tuple, F <: Tuple,
        G <: Tuple, M <: Tuple, D <: Tuple}
    site_states::S
    histories::H
    relationships::R
    fields::F
    globals::G
    membranes::M
    delays::D
end
CoupledState(; site_states::Tuple = (), histories::Tuple = (),
    relationships::Tuple = (), fields::Tuple = (), globals::Tuple = (),
    membranes::Tuple = (), delays::Tuple = ()) =
    CoupledState(site_states, histories, relationships, fields,
        globals, membranes, delays)

function _state_by_name(states::Tuple, name::Symbol)
    index = findfirst(states) do state
        if hasproperty(state, :declaration)
            return getproperty(state, :declaration).name === name
        end
        return hasproperty(state, :name) &&
            getproperty(state, :name) === name
    end
    index === nothing && throw(ArgumentError("coupled state `$name` is not realized"))
    return states[index]
end

function _publish_state!(destination::SitePropertyState,
        source::SitePropertyState)
    copyto!(destination.values, source.values)
    destination.semantic_time = source.semantic_time
    return destination
end
function _publish_state!(destination::CellHistoryState,
        source::CellHistoryState)
    copyto!(destination.values, source.values)
    copyto!(destination.heads, source.heads)
    copyto!(destination.fills, source.fills)
    copyto!(destination.generations, source.generations)
    destination.latest_sample_mcs = source.latest_sample_mcs
    return destination
end
function _publish_state!(destination::RelationshipState,
        source::RelationshipState)
    empty!(destination.edges)
    append!(destination.edges, source.edges)
    return destination
end
_publish_state!(destination, source) = copyto!(destination, source)

function _publish_tuple!(destination::Tuple, source::Tuple)
    length(destination) == length(source) || throw(ArgumentError(
        "coupled state families differ during phase publication"))
    foreach(_publish_state!, destination, source)
    return destination
end

function _accepted_copy_effects_match(declared::Tuple, compiled::Tuple)
    length(declared) == length(compiled) || return false
    return all(zip(declared, compiled)) do pair
        source, execution = pair
        source.name === _effect_name(execution) &&
            source.property === _effect_property(execution) &&
            source.when == execution.when &&
            source.gained == execution.gained &&
            source.lost == execution.lost
    end
end
function publish_coupled_state!(destination::CoupledState, source::CoupledState)
    _publish_tuple!(destination.site_states, source.site_states)
    _publish_tuple!(destination.histories, source.histories)
    _publish_tuple!(destination.relationships, source.relationships)
    _publish_tuple!(destination.fields, source.fields)
    _publish_tuple!(destination.globals, source.globals)
    _publish_tuple!(destination.membranes, source.membranes)
    _publish_tuple!(destination.delays, source.delays)
    return destination
end

mutable struct CoupledObservationState
    completed_mcs::UInt64
    records::Vector{Any}
    last_published::Dict{Symbol, UInt64}
end
CoupledObservationState() = CoupledObservationState(
    UInt64(0), Any[], Dict{Symbol, UInt64}())
CoupledObservationState(completed_mcs::UInt64, records::Vector{Any}) =
    CoupledObservationState(
        completed_mcs, records, Dict{Symbol, UInt64}())

struct CoupledPhaseFailure <: Exception
    target_mcs::UInt64
    stage::Union{Nothing, Symbol}
    phase::Symbol
    process::Union{Nothing, Symbol}
    cause::Any
end
function Base.showerror(io::IO, error::CoupledPhaseFailure)
    print(io, "coupled MCS ", error.target_mcs, " failed in phase `",
        error.phase, '`')
    error.stage === nothing || print(io, " during protocol stage `", error.stage, '`')
    error.process === nothing || print(io, " at process `", error.process, '`')
    print(io, ": ")
    showerror(io, error.cause)
end

function _coupled_initial_state_fingerprint end
function preflight_coupled end

function _runtime_process_ids(potts, plan::MCSPlan)
    ids = Symbol[]
    potts_entry = plan.timeline === nothing ?
        only(entry for entry in plan.entries if entry isa PottsAttempts) :
        only(entry.entry for entry in plan.timeline.entries
            if entry isa ScheduledPotts)
    append!(ids, (effect.name for effect in potts_entry.on_accept))
    for entry in plan.entries
        entry isa CoupledPhase || continue
        for invocation in entry.invocations
            process = invocation_process(invocation)
            identity = component_identity(process)
            push!(ids, identity.key)
        end
    end
    for component in _all_scientific_components(potts.components)
        push!(ids, component_identity(component).key)
    end
    return Set(ids)
end

function _runtime_process_laws(potts, plan::MCSPlan)
    laws = Dict{Symbol, Any}()
    potts_entry = plan.timeline === nothing ?
        only(entry for entry in plan.entries if entry isa PottsAttempts) :
        only(entry.entry for entry in plan.timeline.entries
            if entry isa ScheduledPotts)
    for effect in potts_entry.on_accept
        laws[effect.name] = canonical_process_law(effect)
    end
    for entry in plan.entries
        entry isa CoupledPhase || continue
        for invocation in entry.invocations
            process = invocation_process(invocation)
            laws[component_identity(process).key] =
                canonical_process_law(process)
        end
    end
    for component in _all_scientific_components(potts.components)
        laws[component_identity(component).key] =
            canonical_process_law(component)
    end
    return laws
end

function _validate_semantic_realization(model::SemanticModel,
        potts::ScientificPottsIntegrator, plan::MCSPlan, state::CoupledState)
    runtime_state_ids = Set(block.name for block in _coupled_blocks(state))
    model_state_ids = Set(spec.id for spec in model.states)
    runtime_state_ids == model_state_ids || throw(ArgumentError(
        "canonical semantic states do not match the realized coupled state"))
    for block in _coupled_blocks(state)
        realized = _find_state(state, block)
        hasproperty(realized, :declaration) || continue
        derived = canonical_state_spec(realized.declaration)
        derived === nothing && continue
        expected = only(spec for spec in model.states if spec.id === block.name)
        derived == expected || throw(ArgumentError(
            "canonical state `$(block.name)` does not match its realization"))
    end

    _semantic_record(model.algorithm) == _semantic_record(potts.algorithm) ||
        throw(ArgumentError(
            "canonical Potts algorithm does not match the realized integrator"))

    runtime_process_ids = _runtime_process_ids(potts, plan)
    all(spec -> spec.id in runtime_process_ids, model.processes) ||
        throw(ArgumentError(
            "canonical semantic processes do not match the realized execution"))
    runtime_laws = _runtime_process_laws(potts, plan)
    for spec in model.processes
        _semantic_record(spec.law) ==
            _semantic_record(runtime_laws[spec.id]) || throw(ArgumentError(
            "canonical process `$(spec.id)` law does not match its realization"))
    end

    runtime_kinds = Symbol[]
    for entry in plan.entries
        push!(runtime_kinds,
            entry isa PottsAttempts ? :potts :
            entry isa CoupledPhase ? :process :
            entry isa LifecyclePhase ? :lifecycle : :observation)
    end
    push!(runtime_kinds, :stable_boundary)
    Tuple(runtime_kinds) ==
        Tuple(entry.kind for entry in model.plan.entries) ||
        throw(ArgumentError(
            "canonical plan order does not match the realized MCS plan"))

    observation_entry = only(
        entry for entry in plan.entries if entry isa ObservationPhase)
    runtime_observations = Set(observation.name
        for observation in observation_entry.observations)
    all(spec -> spec.id in runtime_observations, model.observations) ||
        throw(ArgumentError(
            "canonical observations do not match the realized observation phase"))
    for spec in model.observations
        observation = only(item for item in observation_entry.observations
            if item.name === spec.id)
        cadence = observation.schedule isa EveryMCS ? UInt64(1) :
            UInt64(observation.schedule.period)
        transform = canonical_observation_transform(observation.observable)
        schema = (name = observation.schema.name,
            version = observation.schema.version)
        failure = observation.failure isa RequiredObservation ?
            :required : :best_effort
        _semantic_record(spec.transform) == _semantic_record(transform) &&
            spec.cadence == cadence &&
            spec.snapshot === :completed_mcs &&
            spec.schema == schema &&
            spec.failure === failure || throw(ArgumentError(
            "canonical observation `$(spec.id)` does not match its realization"))
    end

    runtime_relations = Any[potts.proposal_relation]
    for component in _all_scientific_components(potts.components)
        append!(runtime_relations, required_relations(component))
    end
    all(relation -> relation in runtime_relations,
        required_relations(model.spatial_roles)) ||
        throw(ArgumentError(
            "canonical spatial roles do not match realized component relations"))
    return model
end

mutable struct CoupledIntegrator{P, S, L, O, R, M}
    potts::P
    plan::MCSPlan
    state::S
    lifecycle::L
    observations::O
    protocol::R
    semantic_model::M
    mcs::UInt64
    stage::Union{Nothing, Symbol}
    stage_local_mcs::UInt64
    terminal_error::Union{Nothing, CoupledPhaseFailure}
    initial_state_fingerprint::NTuple{32, UInt8}
end

function init_coupled(potts::ScientificPottsIntegrator, plan::MCSPlan,
        state::CoupledState; lifecycle = NoCompiledLifecycle(),
        observations = CoupledObservationState(),
        protocol = NoStagedProtocol(), semantic_model = nothing)
    potts.mcs == 0 || throw(ArgumentError(
        "coupled initialization requires an unstepped scientific integrator"))
    potts_entry = if plan.timeline === nothing
        only(entry for entry in plan.entries if entry isa PottsAttempts)
    else
        only(entry.entry for entry in plan.timeline.entries
            if entry isa ScheduledPotts)
    end
    declared_effects = potts_entry.on_accept
    workspace_effects = potts.algorithm_workspace isa CoupledAttemptWorkspace ?
        potts.algorithm_workspace.effects : ()
    _accepted_copy_effects_match(declared_effects, workspace_effects) ||
        throw(ArgumentError(
        "PottsAttempts accepted-copy effects must match the scientific algorithm workspace"))
    semantic_model === nothing ||
        semantic_model isa SemanticModel || throw(ArgumentError(
            "semantic_model must be the canonical SemanticModel"))
    semantic_model === nothing ||
        _validate_semantic_realization(semantic_model, potts, plan, state)
    preflight_coupled(plan, state, potts.plan.capabilities)
    observation_entry = only(
        entry for entry in plan.entries if entry isa ObservationPhase)
    domain = potts.plan.backend isa KernelAbstractions.CPU ? :host : :device
    for observation in observation_entry.observations
        observable = observation.observable
        observable isa ActivitySummary || continue
        record_allocation!(
            potts.plan, domain, _array_bytes(observable.active_count))
        record_allocation!(
            potts.plan, domain, _array_bytes(observable.total))
    end
    if !(potts.plan.backend isa KernelAbstractions.CPU)
        synchronize_observation!(potts.plan)
        for site_state in state.site_states
            record_transfer!(potts.plan, :device_to_host)
        end
    end
    initial_fingerprint = _coupled_initial_state_fingerprint(state)
    return CoupledIntegrator(potts, plan, state, lifecycle, observations,
        protocol, semantic_model, UInt64(0), nothing, UInt64(0), nothing,
        initial_fingerprint)
end

function _invocation_active(invocation, stage, target_mcs)
    invocation.active === nothing && return true
    invocation.active isa AbstractMCSSchedule &&
        return is_due(invocation.active, target_mcs)
    invocation.active isa During || throw(ArgumentError(
        "process activation must be During(...), an MCS schedule, or nothing"))
    return stage !== nothing && stage.name in invocation.active.stages
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, process::SiteDynamics, target_mcs, stage, interval)
    source = _state_by_name(snapshot.site_states, process.property)
    target = _state_by_name(candidate.site_states, process.property)
    copyto!(target.values, source.values)
    apply_site_dynamics!(target, process, target_mcs)
    return nothing
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, sample::HistorySample, target_mcs, stage, interval)
    history = _state_by_name(candidate.histories, sample.history)
    declaration = history.declaration
    source = declaration.source
    capacity = length(history.generations)
    values = Vector{eltype(history.values)}(undef, capacity)
    active = falses(capacity)
    generations = copy(history.generations)
    for slot in 1:capacity
        cell = CellID(slot)
        if is_active(potts_snapshot, cell)
            active[slot] = true
            generations[slot] = generation(potts_snapshot, cell)
            values[slot] = applicable(source, potts_snapshot, cell) ?
                source(potts_snapshot, cell) :
                property_value(potts_snapshot, source, cell)
        else
            values[slot] = @inbounds history.values[slot, 1]
        end
    end
    sample_history!(history, values, active, generations, target_mcs)
    return nothing
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, process, target_mcs, stage, interval)
    throw(ArgumentError(
        "$(typeof(process)) must implement the public execute_process! protocol"))
end

_invocation_interval(invocation::Advance) = invocation.interval
_invocation_interval(invocation::Exchange) = invocation.mode
_invocation_interval(invocation::AbstractProcessInvocation) = nothing

function _execute_phase!(integrator::CoupledIntegrator,
        phase::CoupledPhase, target_mcs::UInt64, stage)
    if !(integrator.potts.plan.backend isa KernelAbstractions.CPU)
        for invocation in phase.invocations
            _invocation_active(invocation, stage, target_mcs) || continue
            process = invocation_process(invocation)
            process isa SiteDynamics || throw(ArgumentError(
                "the GPU-native coupled phase currently admits only qualified site dynamics"))
            target = _state_by_name(
                integrator.state.site_states, process.property)
            apply_site_dynamics!(
                integrator.potts.plan, target, process, target_mcs)
        end
        return integrator
    end
    snapshot = deepcopy(integrator.state)
    candidate = deepcopy(integrator.state)
    potts_snapshot = logical_state(integrator.potts)
    potts_candidate = deepcopy(potts_snapshot)
    written_cell_properties = Symbol[]
    for invocation in phase.invocations
        _invocation_active(invocation, stage, target_mcs) || continue
        process = invocation_process(invocation)
        if process isa FieldExchange &&
                _invocation_interval(invocation) !== nothing
            output = execute_field_exchange!(
                candidate, snapshot, potts_candidate, potts_snapshot,
                process, _invocation_interval(invocation), target_mcs)
            output === nothing || push!(written_cell_properties, output)
        elseif process isa CellDynamics
            execute_cell_dynamics!(
                potts_candidate, potts_snapshot, process,
                target_mcs, _invocation_interval(invocation))
            append!(written_cell_properties,
                (variable.property for variable in process.system.state))
        else
            execute_process!(candidate, snapshot, potts_snapshot, process,
                target_mcs, stage, _invocation_interval(invocation))
        end
    end
    publish_coupled_state!(integrator.state, candidate)
    _publish_cell_properties!(
        integrator.potts, potts_candidate,
        Tuple(unique(written_cell_properties)))
    return integrator
end

function _publish_cell_properties!(integrator::ScientificPottsIntegrator,
        candidate::LogicalPottsState, keys::Tuple)
    storage = integrator.state.potts.storage.properties
    for key in keys
        destination = getproperty(storage, key)
        destination isa Array || throw(ArgumentError(
            "CellDynamics is currently qualified only for CPU-resident property arrays"))
        copyto!(destination, property_values(candidate, key))
    end
    return integrator
end

@inline function _observation_due_now(state, observation, target_mcs)
    return _observation_due(observation.schedule, target_mcs) &&
           get(state.last_published, observation.name, UInt64(0)) < target_mcs
end
@inline _any_observation_due(::Tuple{}, state, target_mcs) = false
@inline function _any_observation_due(observations::Tuple, state, target_mcs)
    _observation_due_now(state, first(observations), target_mcs) && return true
    return _any_observation_due(Base.tail(observations), state, target_mcs)
end
@inline _any_potts_observation_due(::Tuple{}, state, target_mcs) = false
@inline function _any_potts_observation_due(observations::Tuple, state, target_mcs)
    observation = first(observations)
    _observation_due_now(state, observation, target_mcs) &&
        !(observation.observable isa ActivitySummary) && return true
    return _any_potts_observation_due(
        Base.tail(observations), state, target_mcs)
end

function _execute_observations!(integrator::CoupledIntegrator,
        phase::ObservationPhase, target_mcs::UInt64)
    _any_observation_due(
        phase.observations, integrator.observations, target_mcs) || begin
        integrator.observations.completed_mcs = target_mcs
        return integrator
    end
    needs_potts_snapshot = _any_potts_observation_due(
        phase.observations, integrator.observations, target_mcs)
    snapshot = needs_potts_snapshot ? logical_state(integrator.potts) : nothing
    for observation in phase.observations
        if observation.observable isa ActivitySummary
            execute_activity_observation!(
                integrator.observations, observation,
                integrator.state, integrator.potts.plan, target_mcs)
        else
            execute_observation!(
                integrator.observations, observation,
                integrator.state, snapshot, target_mcs)
        end
    end
    integrator.observations.completed_mcs = target_mcs
    return integrator
end

function SciMLBase.step!(integrator::CoupledIntegrator)
    integrator.terminal_error === nothing || throw(IntegratorTerminatedError(
        Int(integrator.mcs), SciMLBase.ReturnCode.Terminated))
    integrator.plan.timeline === nothing ||
        return _step_multirate!(integrator)
    target = integrator.mcs + UInt64(1)
    stage = integrator.protocol isa NoStagedProtocol ?
        nothing : stage_for(integrator.protocol, target)
    phase_name = :protocol_selection
    try
        for entry in integrator.plan.entries
            if entry isa CoupledPhase
                phase_name = entry.name
                _execute_phase!(integrator, entry, target, stage)
            elseif entry isa PottsAttempts
                phase_name = :potts_attempts
                SciMLBase.step!(integrator.potts)
            elseif entry isa LifecyclePhase
                phase_name = :lifecycle
                if integrator.lifecycle isa NoCompiledLifecycle
                    run_compiled_lifecycle!(
                        integrator.potts, integrator.lifecycle, target)
                else
                    before_lifecycle = logical_state(integrator.potts)
                    run_compiled_lifecycle!(
                        integrator.potts, integrator.lifecycle, target)
                    after_lifecycle = logical_state(integrator.potts)
                    apply_coupled_lifecycle!(
                        integrator.state, before_lifecycle, after_lifecycle)
                end
            else
                phase_name = :observation
                _execute_observations!(integrator, entry, target)
            end
        end
        integrator.mcs = target
        integrator.stage = stage === nothing ? nothing : stage.name
        integrator.stage_local_mcs =
            stage === nothing ? UInt64(0) : stage_local_mcs(stage, target)
        return integrator
    catch cause
        failure = CoupledPhaseFailure(target,
            stage === nothing ? nothing : stage.name,
            phase_name, nothing, cause)
        integrator.terminal_error = failure
        throw(failure)
    end
end

function SciMLBase.step!(integrator::CoupledIntegrator, steps::Integer)
    steps >= 0 || throw(ArgumentError("coupled step count must be non-negative"))
    for _ in 1:steps
        SciMLBase.step!(integrator)
    end
    return integrator
end
