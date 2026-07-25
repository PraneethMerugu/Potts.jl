abstract type AbstractDelayInterpolation end
struct ExactSample <: AbstractDelayInterpolation end
struct PiecewiseConstantDelay <: AbstractDelayInterpolation end
struct LinearDelayInterpolation <: AbstractDelayInterpolation end
struct RepeatInitialDelay end

struct EveryGlobal
    interval::Rational{Int64}
    function EveryGlobal(interval::Real)
        interval > 0 || throw(ArgumentError(
            "global sampling interval must be positive"))
        value = rationalize(Int64, interval)
        return new(value)
    end
end

"""Bounded fixed-delay declaration over one registered source symbol."""
struct DelayState{S, T, I <: AbstractDelayInterpolation, A, D, X, R}
    name::Symbol
    source::S
    delay::T
    sampling::EveryGlobal
    interpolation::I
    initial::A
    division::D
    transition::X
    retirement::R
    version::VersionNumber
end
function DelayState(name::Symbol; source, delay::Real,
        sampling::EveryGlobal, interpolation::AbstractDelayInterpolation,
        initial = RepeatInitialDelay(), division = ResetChildHistory(),
        transition = PreserveHistory(), retirement = ResetHistory(),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    delay > 0 || throw(ArgumentError("delay must be positive"))
    if interpolation isa ExactSample
        ratio = rationalize(Int64, delay) / sampling.interval
        denominator(ratio) == 1 || throw(ArgumentError(
            "ExactSample delay must be an integer multiple of its sampling interval"))
    end
    return DelayState(name, source, delay, sampling, interpolation,
        initial, division, transition, retirement, version)
end
component_identity(delay::DelayState) =
    ComponentIdentity(delay.name, delay.version, :delay_state)
component_semantic_data(delay::DelayState) = (
    source = delay.source, delay = delay.delay,
    sampling = delay.sampling, interpolation = delay.interpolation,
    initial = delay.initial, division = delay.division,
    transition = delay.transition, retirement = delay.retirement)
process_reads(delay::DelayState) = ((:delay_source, delay.source),)
process_writes(delay::DelayState) = ((:delay, delay.name),)

mutable struct DelayStateStorage{D <: DelayState, T, V}
    declaration::D
    times::Vector{T}
    values::Vector{V}
    capacity::UInt32
    latest_time::T
end
function DelayStateStorage(delay::DelayState, initial_value;
        initial_time = zero(typeof(delay.delay)))
    count = ceil(Int, delay.delay / Float64(delay.sampling.interval)) + 2
    return DelayStateStorage(delay, [initial_time], [initial_value],
        UInt32(count), initial_time)
end

function sample_delay!(state::DelayStateStorage, time, value)
    time > state.latest_time || throw(ArgumentError(
        "delay samples must have strictly increasing semantic time"))
    push!(state.times, time)
    push!(state.values, convert(eltype(state.values), value))
    while length(state.times) > Int(state.capacity)
        popfirst!(state.times)
        popfirst!(state.values)
    end
    state.latest_time = time
    return state
end

function delay_value(state::DelayStateStorage, time)
    target = time - state.declaration.delay
    if target <= first(state.times)
        state.declaration.initial isa RepeatInitialDelay ||
            throw(ArgumentError("delay history is not initialized at requested time"))
        return first(state.values)
    end
    exact = findfirst(==(target), state.times)
    exact === nothing || return state.values[exact]
    interpolation = state.declaration.interpolation
    interpolation isa ExactSample && throw(ArgumentError(
        "ExactSample delay requested an unsampled time"))
    upper = findfirst(>(target), state.times)
    upper === nothing && throw(ArgumentError(
        "delay history has not reached the requested time"))
    lower = upper - 1
    interpolation isa PiecewiseConstantDelay && return state.values[lower]
    weight = (target - state.times[lower]) /
        (state.times[upper] - state.times[lower])
    return (one(weight) - weight) * state.values[lower] +
        weight * state.values[upper]
end

function _publish_state!(destination::DelayStateStorage,
        source::DelayStateStorage)
    empty!(destination.times)
    append!(destination.times, source.times)
    empty!(destination.values)
    append!(destination.values, source.values)
    destination.latest_time = source.latest_time
    return destination
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, delay::DelayState, target_mcs, stage, interval)
    storage = _state_by_name(candidate.delays, delay.name)
    source = delay.source
    value = if source isa Symbol
        system = only(state for state in snapshot.globals
            if state isa ContinuousSystemState &&
            hasproperty(state.values, source))
        getproperty(system.values, source)
    elseif applicable(source, snapshot, potts_snapshot, target_mcs)
        source(snapshot, potts_snapshot, target_mcs)
    else
        throw(ArgumentError("delay source cannot be materialized"))
    end
    sample_time = storage.latest_time +
        convert(typeof(storage.latest_time), interval)
    sample_delay!(storage, sample_time, value)
    return nothing
end

abstract type AbstractTriggerMemory end
struct WhileTrue <: AbstractTriggerMemory end
struct OnRising <: AbstractTriggerMemory end
struct OnceWhenTrue <: AbstractTriggerMemory end
struct PersistentTrigger <: AbstractTriggerMemory end

struct SampledTrigger{C, M <: AbstractTriggerMemory}
    condition::C
    memory::M
end
struct RootTrigger{F, T}
    root::F
    direction::Int8
    tolerance::T
    maximum_iterations::UInt32
end
function RootTrigger(root; direction::Integer = 0,
        tolerance::AbstractFloat = 1e-8,
        maximum_iterations::Integer = 64)
    T = typeof(tolerance)
    direction in (-1, 0, 1) || throw(ArgumentError(
        "root direction must be -1, 0, or 1"))
    tolerance > zero(T) || throw(ArgumentError(
        "root tolerance must be positive"))
    maximum_iterations > 0 || throw(ArgumentError(
        "root locator iteration bound must be positive"))
    return RootTrigger(root, Int8(direction), tolerance,
        UInt32(maximum_iterations))
end

struct EventAssignment{E}
    target::Symbol
    expression::E
end
struct FromTriggerSnapshot end
struct FromExecutionSnapshot end
struct NoImmediateCascade end
struct CascadeUntilStable
    maximum_iterations::UInt32
    function CascadeUntilStable(maximum_iterations::Integer)
        maximum_iterations > 0 || throw(ArgumentError(
            "cascade bound must be positive"))
        return new(UInt32(maximum_iterations))
    end
end

struct LifecycleRequest{E, P}
    event::Symbol
    target::CellEndpoint
    effect::E
    trigger_time::Float64
    payload::P
end
struct EventBatch{E <: Tuple}
    events::E
end
EventBatch(events...) = EventBatch(Tuple(events))

struct ContinuousEvent{D <: AbstractContinuousDomain, T, S, A <: Tuple, V, C}
    name::Symbol
    domain::D
    system::Symbol
    trigger::T
    schedule::S
    assignments::A
    delay::Float64
    priority::Int32
    values::V
    cascade::C
    queue_capacity::UInt32
    version::VersionNumber
end
function ContinuousEvent(name::Symbol; domain::AbstractContinuousDomain,
        system::Symbol, trigger, schedule,
        assignments::Tuple, delay::Real = 0,
        priority::Integer = 0, values = FromTriggerSnapshot(),
        cascade = NoImmediateCascade(),
        maximum_queue::Integer = 1024,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    delay >= 0 || throw(ArgumentError("event delay must be non-negative"))
    all(item -> item isa Union{EventAssignment, LifecycleRequest}, assignments) ||
        throw(ArgumentError(
            "event assignments must be EventAssignment or LifecycleRequest values"))
    maximum_queue > 0 || throw(ArgumentError(
        "continuous-event queue capacity must be positive"))
    return ContinuousEvent(name, domain, system, trigger, schedule,
        assignments, Float64(delay), Int32(priority), values, cascade,
        UInt32(maximum_queue), version)
end
component_identity(event::ContinuousEvent) =
    ComponentIdentity(event.name, event.version, :continuous_event)
component_semantic_data(event::ContinuousEvent) = (
    domain = event.domain, system = event.system, trigger = event.trigger,
    schedule = event.schedule, assignments = event.assignments,
    delay = event.delay, priority = event.priority,
    values = event.values, cascade = event.cascade,
    queue_capacity = event.queue_capacity)
process_reads(event::ContinuousEvent) =
    ((:continuous_system, event.system), (:event_memory, event.name))
process_writes(event::ContinuousEvent) =
    ((:continuous_system, event.system), (:event_memory, event.name))

struct QueuedEvent{V}
    execution_time::Float64
    priority::Int32
    trigger_time::Float64
    values::V
    requests::Tuple
end
mutable struct EventRuntimeState{D <: ContinuousEvent}
    declaration::D
    previous_condition::Bool
    latched::Bool
    queue::Vector{QueuedEvent}
    lifecycle_requests::Vector{Any}
end
EventRuntimeState(event::ContinuousEvent) =
    EventRuntimeState(event, false, false, QueuedEvent[], Any[])

function _trigger_fires(memory::WhileTrue, condition, previous, latched)
    return condition, condition, latched
end
function _trigger_fires(memory::OnRising, condition, previous, latched)
    return condition && !previous, condition, latched
end
function _trigger_fires(memory::OnceWhenTrue, condition, previous, latched)
    fires = condition && !latched
    return fires, condition, latched || fires
end
function _trigger_fires(memory::PersistentTrigger, condition, previous, latched)
    fires = condition && !latched
    return fires, condition, latched || condition
end

function _event_values(event::ContinuousEvent,
        state::ContinuousSystemState, time)
    snapshot = state.values
    pairs = Pair{Symbol, Any}[]
    requests = Any[]
    for assignment in event.assignments
        if assignment isa EventAssignment
            value = _evaluate_expression(assignment.expression, snapshot,
                state.declaration.parameters, state.declaration.inputs, time)
            push!(pairs, assignment.target => value)
        else
            push!(requests, assignment)
        end
    end
    names = Tuple(first(pair) for pair in pairs)
    values = Tuple(last(pair) for pair in pairs)
    return NamedTuple{names}(values), requests
end

function _commit_event_values!(state::ContinuousSystemState, values::NamedTuple)
    candidate = state.values
    for name in propertynames(values)
        candidate = _named_replace(candidate, name, getproperty(values, name))
    end
    state.values = candidate
    return state
end

function execute_event!(runtime::EventRuntimeState,
        state::ContinuousSystemState, time::Real)
    event = runtime.declaration
    trigger = event.trigger
    if trigger isa SampledTrigger
        condition = Bool(_evaluate_expression(trigger.condition, state.values,
            state.declaration.parameters, state.declaration.inputs, time))
        fires, previous, latched = _trigger_fires(
            trigger.memory, condition, runtime.previous_condition, runtime.latched)
        runtime.previous_condition = previous
        runtime.latched = latched
        if fires
            if iszero(event.delay)
                values, requests = _event_values(event, state, time)
                _commit_event_values!(state, values)
                append!(runtime.lifecycle_requests, requests)
            else
                length(runtime.queue) < Int(event.queue_capacity) || throw(
                    ArgumentError(
                        "continuous-event delayed queue capacity exceeded"))
                values, requests = event.values isa FromTriggerSnapshot ?
                    _event_values(event, state, time) :
                    (nothing, ())
                push!(runtime.queue, QueuedEvent(
                    Float64(time) + event.delay, event.priority,
                    Float64(time), values, Tuple(requests)))
                sort!(runtime.queue; by = item ->
                    (item.execution_time, -Int(item.priority)))
            end
        end
    else
        throw(ArgumentError(
            "RootTrigger execution requires locate_root and a solver-owned interval"))
    end
    while !isempty(runtime.queue) &&
            first(runtime.queue).execution_time <= time
        item = popfirst!(runtime.queue)
        values, requests = item.values === nothing ?
            _event_values(event, state, item.execution_time) :
            (item.values, item.requests)
        _commit_event_values!(state, values)
        append!(runtime.lifecycle_requests, requests)
    end
    return runtime
end

function locate_root(trigger::RootTrigger, function_value,
        left::T, right::T) where {T <: AbstractFloat}
    fleft = function_value(left)
    fright = function_value(right)
    crossing = trigger.direction == 1 ? fleft < 0 <= fright :
        trigger.direction == -1 ? fleft > 0 >= fright :
        signbit(fleft) != signbit(fright) || iszero(fleft) || iszero(fright)
    crossing || return nothing
    low, high = left, right
    for _ in 1:Int(trigger.maximum_iterations)
        midpoint = (low + high) / 2
        value = function_value(midpoint)
        if abs(value) <= trigger.tolerance ||
                abs(high - low) <= trigger.tolerance
            return midpoint
        end
        if signbit(value) == signbit(fleft)
            low = midpoint
            fleft = value
        else
            high = midpoint
        end
    end
    throw(ArgumentError("root locator exceeded its iteration bound"))
end

function _publish_state!(destination::EventRuntimeState,
        source::EventRuntimeState)
    destination.previous_condition = source.previous_condition
    destination.latched = source.latched
    empty!(destination.queue)
    append!(destination.queue, source.queue)
    empty!(destination.lifecycle_requests)
    append!(destination.lifecycle_requests, source.lifecycle_requests)
    return destination
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, event::ContinuousEvent, target_mcs, stage, interval)
    runtime = _state_by_name(candidate.delays, event.name)
    system = _state_by_name(candidate.globals, event.system)
    execute_event!(runtime, system, Float64(target_mcs))
    return nothing
end

struct SymbolIdentity
    namespace::Tuple{Vararg{Symbol}}
    domain::Symbol
    system::Symbol
    name::Symbol
    version::VersionNumber
end
struct SymbolRef
    identity::SymbolIdentity
end
struct InputRef
    system::Symbol
    name::Symbol
end

struct IdentityMap end
(::IdentityMap)(value) = value
struct SymbolMap{S, D, T, E, Q}
    name::Symbol
    source::S
    destination::D
    transform::T
    empty::E
    schedule::Q
    version::VersionNumber
end
function SymbolMap(name::Symbol; source, destination,
        transform = IdentityMap(), empty = :error, schedule = EveryMCS(),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    return SymbolMap(name, source, destination, transform, empty, schedule, version)
end
component_identity(mapping::SymbolMap) =
    ComponentIdentity(mapping.name, mapping.version, :symbol_mapping)
component_semantic_data(mapping::SymbolMap) = (
    source = mapping.source, destination = mapping.destination,
    transform = mapping.transform, empty = mapping.empty,
    schedule = mapping.schedule)
process_reads(mapping::SymbolMap) = ((:symbol, mapping.source),)
process_writes(mapping::SymbolMap) = ((:symbol, mapping.destination),)

function _symbol_value(state::CoupledState, reference::SymbolRef)
    identity = reference.identity
    system = _state_by_name(state.globals, identity.system)
    hasproperty(system.values, identity.name) || throw(ArgumentError(
        "mapped source symbol is absent"))
    return getproperty(system.values, identity.name)
end

function apply_symbol_map!(state::CoupledState, mapping::SymbolMap)
    value = mapping.transform(_symbol_value(state, mapping.source))
    destination = mapping.destination
    destination isa InputRef || throw(ArgumentError(
        "stable SymbolMap destination must be InputRef"))
    system = _state_by_name(state.globals, destination.system)
    hasproperty(system.values, destination.name) || throw(ArgumentError(
        "mapped destination symbol is absent"))
    system.values = _named_replace(
        system.values, destination.name, value)
    return state
end

function execute_process!(candidate::CoupledState, snapshot::CoupledState,
        potts_snapshot, mapping::SymbolMap, target_mcs, stage, interval)
    # Read from the phase snapshot and publish only the declared destination.
    value = mapping.transform(_symbol_value(snapshot, mapping.source))
    destination = mapping.destination
    system = _state_by_name(candidate.globals, destination.system)
    system.values = _named_replace(
        system.values, destination.name, value)
    return nothing
end

abstract type AbstractCompatibilityLevel end
struct ExactSemanticMapping <: AbstractCompatibilityLevel end
struct QualifiedNumericalMapping <: AbstractCompatibilityLevel end
struct ExplicitApproximation <: AbstractCompatibilityLevel end
struct PartialMapping <: AbstractCompatibilityLevel end
struct RejectedMapping <: AbstractCompatibilityLevel end

struct CompatibilityItem{L <: AbstractCompatibilityLevel}
    construct::Symbol
    level::L
    source::String
    target::String
    evidence::String
end
struct CompatibilityReport{I <: Tuple, L <: AbstractCompatibilityLevel}
    profile::Symbol
    source_checksum::String
    items::I
    overall::L
    executable::Bool
end

struct MorpheusSemanticProfile end
struct SBMLSemanticProfile end

_compatibility_rank(::ExactSemanticMapping) = 5
_compatibility_rank(::QualifiedNumericalMapping) = 4
_compatibility_rank(::ExplicitApproximation) = 3
_compatibility_rank(::PartialMapping) = 2
_compatibility_rank(::RejectedMapping) = 1
function _minimum_level(items)
    isempty(items) && return RejectedMapping()
    levels = Tuple(item.level for item in items)
    return reduce(levels) do left, right
        _compatibility_rank(left) <= _compatibility_rank(right) ?
            left : right
    end
end

struct ContinuousModelAdapter{P, L}
    name::Symbol
    profile::P
    lower::L
    version::VersionNumber
end
function ContinuousModelAdapter(name::Symbol; profile, lower,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    lower isa DirectLaw || throw(ArgumentError(
        "continuous adapter lowering requires DirectLaw semantic identity"))
    return ContinuousModelAdapter(name, profile, lower, version)
end
component_identity(adapter::ContinuousModelAdapter) =
    ComponentIdentity(adapter.name, adapter.version, :continuous_model_adapter)
component_semantic_data(adapter::ContinuousModelAdapter) = (
    profile = adapter.profile,
    lower = (name = adapter.lower.name, version = adapter.lower.version))

function adapt_continuous_model(adapter::ContinuousModelAdapter,
        source; checksum::AbstractString, allow_approximation::Bool = false)
    result = adapter.lower.function_value(source)
    haskey(result, :declarations) && haskey(result, :items) || throw(ArgumentError(
        "continuous adapter must return declarations and compatibility items"))
    items = Tuple(result.items)
    all(item -> item isa CompatibilityItem, items) || throw(ArgumentError(
        "adapter compatibility rows must be CompatibilityItem values"))
    overall = _minimum_level(items)
    executable = overall isa Union{
        ExactSemanticMapping, QualifiedNumericalMapping} ||
        (allow_approximation && overall isa ExplicitApproximation)
    report = CompatibilityReport(Symbol(nameof(typeof(adapter.profile))),
        String(checksum), items, overall, executable)
    executable || throw(ArgumentError(
        "adapter result is partial, rejected, or an unapproved approximation"))
    return (declarations = Tuple(result.declarations), report)
end
