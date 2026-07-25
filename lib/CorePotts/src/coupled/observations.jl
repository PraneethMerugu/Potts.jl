abstract type AbstractObservationPhase end
struct CompletedMCS <: AbstractObservationPhase end
struct NamedPhaseSnapshot <: AbstractObservationPhase
    phase::Symbol
end

abstract type AbstractObservationFailurePolicy end
struct RequiredObservation <: AbstractObservationFailurePolicy end
struct BestEffortTelemetry <: AbstractObservationFailurePolicy end

abstract type AbstractObservationSchema end
struct RecordSchema <: AbstractObservationSchema
    name::Symbol
    version::VersionNumber
end

struct PhaseObservation{O, P <: AbstractObservationPhase, S,
        R <: AbstractObservationSchema, F <: AbstractObservationFailurePolicy}
    name::Symbol
    observable::O
    phase::P
    schedule::S
    schema::R
    failure::F
    version::VersionNumber
end
function PhaseObservation(name::Symbol, observable;
        phase::AbstractObservationPhase = CompletedMCS(),
        schedule = EveryMCS(),
        schema::AbstractObservationSchema = RecordSchema(name, v"1.0.0"),
        failure::AbstractObservationFailurePolicy = RequiredObservation(),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    return PhaseObservation(name, observable, phase, schedule,
        schema, failure, version)
end
component_identity(observation::PhaseObservation) =
    ComponentIdentity(observation.name, observation.version, :paper_observation)
component_semantic_data(observation::PhaseObservation) = (
    observable = _semantic_observable(observation.observable),
    phase = observation.phase, schedule = observation.schedule,
    schema = observation.schema, failure = observation.failure)

_semantic_observable(law::DirectLaw) =
    (name = law.name, version = law.version)
function _semantic_observable(observable)
    hasmethod(component_identity, Tuple{typeof(observable)}) ||
        throw(ArgumentError(
            "observation laws require DirectLaw or component identity"))
    identity = component_identity(observable)
    return (key = identity.key, version = identity.version,
        category = identity.category)
end

struct PaperObservationRecord{P <: AbstractObservationPhase,
        S <: AbstractObservationSchema, V}
    observation::Symbol
    mcs::UInt64
    phase::P
    schema::S
    value::V
end

struct ObservationFailureRecord
    observation::Symbol
    mcs::UInt64
    error_type::Symbol
    message::String
end

function _observation_due(schedule, target_mcs::UInt64)
    schedule isa AbstractMCSSchedule || throw(ArgumentError(
        "PhaseObservation schedule must implement AbstractMCSSchedule"))
    return is_due(schedule, target_mcs)
end

function _evaluate_observable(law::DirectLaw, coupled, potts, mcs)
    function_value = law.function_value
    applicable(function_value, coupled, potts, mcs) &&
        return function_value(coupled, potts, mcs)
    applicable(function_value, coupled, potts) &&
        return function_value(coupled, potts)
    applicable(function_value, potts, mcs) &&
        return function_value(potts, mcs)
    applicable(function_value, potts) && return function_value(potts)
    throw(ArgumentError(
        "observation law `$(law.name)` has no supported read-only call signature"))
end
function _evaluate_observable(observable, coupled, potts, mcs)
    applicable(observable, coupled, potts, mcs) &&
        return observable(coupled, potts, mcs)
    applicable(observable, coupled, potts) &&
        return observable(coupled, potts)
    applicable(observable, potts, mcs) &&
        return observable(potts, mcs)
    applicable(observable, potts) && return observable(potts)
    throw(ArgumentError(
        "observable $(typeof(observable)) has no supported read-only call signature"))
end

function execute_observation!(state::CoupledObservationState,
        observation::PhaseObservation, coupled, potts, target_mcs::UInt64)
    observation.phase isa CompletedMCS || throw(ArgumentError(
        "named intermediate observation snapshots require an explicit phase publisher"))
    _observation_due(observation.schedule, target_mcs) || return state
    last = get(state.last_published, observation.name, UInt64(0))
    last < target_mcs || return state
    try
        value = _evaluate_observable(
            observation.observable, deepcopy(coupled), potts, target_mcs)
        push!(state.records, PaperObservationRecord(
            observation.name, target_mcs, observation.phase,
            observation.schema, value))
        state.last_published[observation.name] = target_mcs
    catch error
        observation.failure isa RequiredObservation && rethrow()
        push!(state.records, ObservationFailureRecord(
            observation.name, target_mcs,
            Symbol(nameof(typeof(error))), sprint(showerror, error)))
    end
    return state
end

"""
Publish the bounded Act summary through one backend-native reduction and one explicit observation
synchronization. Only the two one-element result buffers cross the device boundary.
"""
function execute_activity_observation!(state::CoupledObservationState,
        observation::PhaseObservation{<:ActivitySummary}, coupled,
        plan::ExecutionPlan, target_mcs::UInt64)
    observation.phase isa CompletedMCS || throw(ArgumentError(
        "activity summary requires the completed-MCS snapshot"))
    _observation_due(observation.schedule, target_mcs) || return state
    last = get(state.last_published, observation.name, UInt64(0))
    last < target_mcs || return state
    summary = observation.observable
    site_state = _state_by_name(coupled.site_states, summary.property)
    backend = KernelAbstractions.get_backend(site_state.values)
    isequal(backend, plan.backend) ||
        throw(ArgumentError(
            "activity observation storage backend does not match the execution plan"))
    isequal(KernelAbstractions.get_backend(summary.active_count), backend) &&
        isequal(KernelAbstractions.get_backend(summary.total), backend) ||
        throw(ArgumentError(
            "activity observation workspace must share the activity-state backend"))
    kernel = _execution_kernel(plan, _activity_summary_kernel!, 1)
    launch!(plan, kernel, summary.active_count, summary.total,
        site_state.values; ndrange = 1)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    active_count = only(Array(summary.active_count))
    total = only(Array(summary.total))
    mean_activity = iszero(active_count) ?
        zero(eltype(site_state.values)) : total / active_count
    value = (
        active_site_count = Int(active_count),
        mean_activity,
        completed_mcs = target_mcs,
    )
    push!(state.records, PaperObservationRecord(
        observation.name, target_mcs, observation.phase,
        observation.schema, value))
    state.last_published[observation.name] = target_mcs
    return state
end

function execute_observation!(state::CoupledObservationState,
        observation, coupled, potts, target_mcs::UInt64)
    push!(state.records, observation(coupled, potts, target_mcs))
    return state
end

struct ObservationTransform{T, I <: AbstractObservationPhase}
    name::Symbol
    input::I
    transform::T
    maximum_work::UInt64
    version::VersionNumber
end
function ObservationTransform(name::Symbol; input::AbstractObservationPhase =
        CompletedMCS(), transform, maximum_work::Integer,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    maximum_work > 0 || throw(ArgumentError(
        "observation-transform work bound must be positive"))
    return ObservationTransform(name, input, transform,
        UInt64(maximum_work), version)
end
component_identity(transform::ObservationTransform) =
    ComponentIdentity(transform.name, transform.version, :observation_transform)
component_semantic_data(transform::ObservationTransform) = (
    input = transform.input,
    transform = _semantic_observable(transform.transform),
    maximum_work = transform.maximum_work)

function (transform::ObservationTransform)(coupled, potts, mcs)
    private_coupled = deepcopy(coupled)
    private_potts = deepcopy(potts)
    return _evaluate_observable(
        transform.transform, private_coupled, private_potts, mcs)
end
