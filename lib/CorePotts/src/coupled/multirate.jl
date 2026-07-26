"""Exact global clock used to compare multirate schedule positions."""
struct GlobalClock
    name::Symbol
    start::Rational{Int64}
    unit::Symbol
    version::VersionNumber
end
function GlobalClock(name::Symbol; start::Real = 0,
        unit::Symbol = :dimensionless,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    return GlobalClock(name, rationalize(Int64, start), unit, version)
end
component_identity(clock::GlobalClock) =
    ComponentIdentity(clock.name, clock.version, :global_clock)
component_semantic_data(clock::GlobalClock) =
    (start = clock.start, unit = clock.unit)

struct MCSDuration
    value::Rational{Int64}
    function MCSDuration(value::Real)
        value > 0 || throw(ArgumentError("MCS duration must be positive"))
        return new(rationalize(Int64, value))
    end
end

abstract type AbstractMCSPosition end
struct AtMCSStart <: AbstractMCSPosition end
struct AtMCSEnd <: AbstractMCSPosition end
struct AtMCSOffset <: AbstractMCSPosition
    offset::Rational{Int64}
    function AtMCSOffset(offset::Real)
        value = rationalize(Int64, offset)
        0 <= value <= 1 || throw(ArgumentError(
            "relative MCS offset must be in [0, 1]"))
        return new(value)
    end
end

abstract type AbstractScheduledEntry end
struct ScheduledSystem{P, S} <: AbstractScheduledEntry
    process::P
    schedule::S
    priority::Int32
end
ScheduledSystem(process, schedule::EveryGlobal; priority::Integer) =
    ScheduledSystem(process, schedule, Int32(priority))

struct ScheduledEvent{P} <: AbstractScheduledEntry
    event::P
    schedule::EveryGlobal
    priority::Int32
end
ScheduledEvent(event, schedule::EveryGlobal; priority::Integer) =
    ScheduledEvent(event, schedule, Int32(priority))

"""Schedule any registered phase process, including maps, delays, and exchanges."""
struct ScheduledProcess{P} <: AbstractScheduledEntry
    process::P
    schedule::EveryGlobal
    priority::Int32
end
ScheduledProcess(process, schedule::EveryGlobal; priority::Integer) =
    ScheduledProcess(process, schedule, Int32(priority))

struct ScheduledPotts{P <: PottsAttempts, A <: AbstractMCSPosition} <:
        AbstractScheduledEntry
    entry::P
    at::A
    priority::Int32
end
ScheduledPotts(entry::PottsAttempts, at::AbstractMCSPosition;
    priority::Integer) = ScheduledPotts(entry, at, Int32(priority))

struct TimedLifecyclePhase
    version::VersionNumber
end
TimedLifecyclePhase() =
    TimedLifecyclePhase(COUPLED_EXECUTION_CONTRACT_VERSION)

struct ScheduledLifecycle{P, S} <: AbstractScheduledEntry
    phase::P
    schedule::S
    priority::Int32
end
ScheduledLifecycle(phase, schedule; priority::Integer) =
    ScheduledLifecycle(phase, schedule, Int32(priority))

struct MultirateSchedule{G <: GlobalClock, E <: Tuple}
    global_clock::G
    mcs_duration::MCSDuration
    entries::E
    version::VersionNumber
end
function MultirateSchedule(; global_clock::GlobalClock,
        mcs_duration::MCSDuration, entries::Tuple,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    return MultirateSchedule(
        global_clock, mcs_duration, entries, version)
end
component_identity(::MultirateSchedule) = ComponentIdentity(
    :multirate_schedule, CONTINUOUS_SYSTEM_CONTRACT_VERSION,
    :multirate_schedule)
component_semantic_data(schedule::MultirateSchedule) = (
    global_clock = schedule.global_clock,
    mcs_duration = schedule.mcs_duration,
    entries = schedule.entries,
    version = schedule.version)

_scheduled_process(entry::ScheduledSystem) = entry.process
_scheduled_process(entry::ScheduledEvent) = entry.event
_scheduled_process(entry::ScheduledProcess) = entry.process
_scheduled_process(entry::ScheduledPotts) = entry.entry
_scheduled_process(entry::ScheduledLifecycle) = entry.phase

_scheduled_writes(entry::ScheduledSystem) =
    process_writes(entry.process)
_scheduled_writes(entry::ScheduledEvent) =
    process_writes(entry.event)
_scheduled_writes(entry::ScheduledProcess) =
    process_writes(entry.process)
_scheduled_writes(::ScheduledPotts) =
    ((:potts, :ownership), (:ownership, :lattice))
_scheduled_writes(::ScheduledLifecycle) =
    ((:potts, :ownership), (:ownership, :lattice),
        (:potts, :lifecycle))
_scheduled_reads(entry::ScheduledSystem) =
    process_reads(entry.process)
_scheduled_reads(entry::ScheduledEvent) =
    process_reads(entry.event)
_scheduled_reads(entry::ScheduledProcess) =
    process_reads(entry.process)
_scheduled_reads(::ScheduledPotts) =
    ((:potts, :ownership), (:ownership, :lattice))
_scheduled_reads(::ScheduledLifecycle) =
    ((:potts, :ownership), (:ownership, :lattice))

function _validate_multirate_timeline(timeline::MultirateSchedule)
    entries = timeline.entries
    isempty(entries) && throw(ArgumentError(
        "MultirateSchedule must not be empty"))
    all(entry -> entry isa AbstractScheduledEntry, entries) ||
        throw(ArgumentError(
            "multirate entries must use a registered scheduled-entry family"))
    count(entry -> entry isa ScheduledPotts, entries) == 1 ||
        throw(ArgumentError(
            "MultirateSchedule requires exactly one ScheduledPotts entry"))
    count(entry -> entry isa ScheduledLifecycle &&
        entry.phase isa LifecyclePhase, entries) == 1 ||
        throw(ArgumentError(
            "MultirateSchedule requires exactly one MCS-boundary LifecyclePhase"))
    identities = map(_scheduled_identity, entries)
    length(unique(identities)) == length(identities) || throw(ArgumentError(
        "multirate scheduled-entry identities must be unique"))
    for priority in unique(entry.priority for entry in entries)
        same_priority = filter(entry -> entry.priority == priority, entries)
        for left_index in eachindex(same_priority)
            left = same_priority[left_index]
            left_writes = Set(_scheduled_writes(left))
            left_reads = Set(_scheduled_reads(left))
            for right in same_priority[left_index + 1:end]
                right_writes = Set(_scheduled_writes(right))
                right_reads = Set(_scheduled_reads(right))
                isempty(intersect(left_writes, right_writes)) &&
                    isempty(intersect(left_writes, right_reads)) &&
                    isempty(intersect(right_writes, left_reads)) || throw(
                    ArgumentError(
                        "equal-priority multirate entries have a read/write conflict"))
            end
        end
    end
    for entry in entries
        entry isa ScheduledLifecycle || continue
        entry.phase isa LifecyclePhase &&
            !(entry.schedule isa AtMCSEnd) && throw(ArgumentError(
                "ordinary LifecyclePhase must be scheduled AtMCSEnd"))
        entry.phase isa TimedLifecyclePhase ||
            entry.phase isa LifecyclePhase || throw(ArgumentError(
                "ScheduledLifecycle requires LifecyclePhase or TimedLifecyclePhase"))
    end
    return timeline
end

_scheduled_identity(entry::ScheduledSystem) =
    (:system, component_identity(entry.process).key)
_scheduled_identity(entry::ScheduledEvent) =
    (:event, component_identity(entry.event).key)
_scheduled_identity(entry::ScheduledProcess) =
    (:process, component_identity(entry.process).key)
_scheduled_identity(::ScheduledPotts) = (:potts, :attempts)
_scheduled_identity(entry::ScheduledLifecycle) =
    (:lifecycle, Symbol(nameof(typeof(entry.phase))))

function _position_time(position::AtMCSStart, start, duration)
    return start
end
function _position_time(position::AtMCSEnd, start, duration)
    return start + duration
end
function _position_time(position::AtMCSOffset, start, duration)
    return start + position.offset * duration
end

function _ticks(entry::Union{ScheduledSystem, ScheduledEvent, ScheduledProcess},
        start, endpoint, duration)
    interval = entry.schedule.interval
    first_index = fld(start, interval) + 1
    first_tick = first_index * interval
    first_tick > endpoint && return Rational{Int64}[]
    return collect(first_tick:interval:endpoint)
end
_ticks(entry::ScheduledPotts, start, endpoint, duration) =
    [_position_time(entry.at, start, duration)]
function _ticks(entry::ScheduledLifecycle, start, endpoint, duration)
    schedule = entry.schedule
    if schedule isa AbstractMCSPosition
        return [_position_time(schedule, start, duration)]
    elseif schedule isa EveryGlobal
        first_index = fld(start, schedule.interval) + 1
        first_tick = first_index * schedule.interval
        first_tick > endpoint && return Rational{Int64}[]
        return collect(first_tick:schedule.interval:endpoint)
    end
    throw(ArgumentError("unsupported lifecycle schedule $(typeof(schedule))"))
end

function _due_entries(timeline, start, endpoint)
    due = Tuple{Rational{Int64}, Int32, Any}[]
    for entry in timeline.entries
        for tick in _ticks(entry, start, endpoint, timeline.mcs_duration.value)
            push!(due, (tick, entry.priority, entry))
        end
    end
    sort!(due; by = item -> (item[1], item[2], _scheduled_identity(item[3])))
    return due
end

function _execute_scheduled_process!(integrator, entry, target, stage, interval)
    snapshot = deepcopy(integrator.state)
    candidate = deepcopy(integrator.state)
    potts_snapshot = logical_state(integrator.potts)
    process = _scheduled_process(entry)
    if process isa CellDynamics
        potts_candidate = deepcopy(potts_snapshot)
        execute_cell_dynamics!(
            potts_candidate, potts_snapshot, process,
            target, Float64(interval))
        keys = Tuple(variable.property for variable in process.system.state)
        _publish_cell_properties!(
            integrator.potts, potts_candidate, keys)
    else
        execute_process!(candidate, snapshot, potts_snapshot, process,
            target, stage, Float64(interval))
    end
    publish_coupled_state!(integrator.state, candidate)
    return integrator
end

function _execute_scheduled_group!(integrator, group,
        target, stage, last_time)
    entries = Tuple(item[3] for item in group)
    if any(entry -> entry isa ScheduledPotts, entries)
        length(entries) == 1 || throw(ArgumentError(
            "ScheduledPotts cannot share an atomic priority group"))
        SciMLBase.step!(integrator.potts)
        return integrator
    elseif any(entry -> entry isa ScheduledLifecycle, entries)
        length(entries) == 1 || throw(ArgumentError(
            "ScheduledLifecycle cannot share an atomic priority group"))
        _execute_timed_lifecycle!(integrator, target)
        return integrator
    end

    snapshot = deepcopy(integrator.state)
    candidate = deepcopy(integrator.state)
    potts_snapshot = logical_state(integrator.potts)
    potts_candidate = deepcopy(potts_snapshot)
    written_cell_properties = Symbol[]
    for (_, _, entry) in group
        process = _scheduled_process(entry)
        identity = _scheduled_identity(entry)
        previous = get(last_time, identity,
            integrator.plan.timeline.global_clock.start +
            (target - 1) * integrator.plan.timeline.mcs_duration.value)
        interval = group[1][1] - previous
        if process isa CellDynamics
            execute_cell_dynamics!(
                potts_candidate, potts_snapshot, process,
                target, Float64(interval))
            append!(written_cell_properties,
                (variable.property for variable in process.system.state))
        else
            execute_process!(
                candidate, snapshot, potts_snapshot, process,
                target, stage, Float64(interval))
        end
    end
    publish_coupled_state!(integrator.state, candidate)
    _publish_cell_properties!(integrator.potts, potts_candidate,
        Tuple(unique(written_cell_properties)))
    for (_, _, entry) in group
        last_time[_scheduled_identity(entry)] = group[1][1]
    end
    return integrator
end

function _execute_timed_lifecycle!(integrator, target)
    before = logical_state(integrator.potts)
    run_compiled_lifecycle!(integrator.potts, integrator.lifecycle, target)
    after = logical_state(integrator.potts)
    apply_coupled_lifecycle!(integrator.state, before, after)
    return integrator
end

function _step_multirate!(integrator::CoupledIntegrator)
    integrator.checkpoint_stable = false
    target = integrator.mcs + UInt64(1)
    timeline = integrator.plan.timeline
    duration = timeline.mcs_duration.value
    start = timeline.global_clock.start + (target - 1) * duration
    endpoint = start + duration
    stage = integrator.protocol isa NoStagedProtocol ?
        nothing : stage_for(integrator.protocol, target)
    phase_name = :multirate
    last_time = Dict{Any, Rational{Int64}}()
    try
        due = _due_entries(timeline, start, endpoint)
        index = 1
        while index <= length(due)
            tick, priority, entry = due[index]
            last_index = index
            while last_index < length(due) &&
                    due[last_index + 1][1] == tick &&
                    due[last_index + 1][2] == priority
                last_index += 1
            end
            group = @view due[index:last_index]
            phase_name = Symbol(first(_scheduled_identity(entry)))
            _execute_scheduled_group!(
                integrator, group, target, stage, last_time)
            index = last_index + 1
        end
        observation = only(integrator.plan.entries)
        _execute_observations!(integrator, observation, target)
        integrator.mcs = target
        integrator.stage = stage === nothing ? nothing : stage.name
        integrator.stage_local_mcs = stage === nothing ? UInt64(0) :
            stage_local_mcs(stage, target)
        integrator.checkpoint_stable = true
        return integrator
    catch cause
        failure = CoupledPhaseFailure(target,
            stage === nothing ? nothing : stage.name,
            phase_name, nothing, cause)
        integrator.terminal_error = failure
        throw(failure)
    end
end

function global_time(integrator::CoupledIntegrator)
    timeline = integrator.plan.timeline
    timeline === nothing && return integrator.mcs
    return timeline.global_clock.start +
        integrator.mcs * timeline.mcs_duration.value
end
