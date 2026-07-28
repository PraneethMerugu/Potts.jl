abstract type AbstractSchedule end

abstract type AbstractHorizonPolicy end
struct ExactHorizon <: AbstractHorizonPolicy end
struct StopPrior <: AbstractHorizonPolicy end

_horizon_symbol(::ExactHorizon) = :exact
_horizon_symbol(::StopPrior) = :stop_prior
function _horizon_symbol(policy::Symbol)
    policy in (:exact, :stop_prior) ||
        _fail(:unknown_horizon_policy,
            "horizon policy must be exact or stop_prior"; policy)
    policy
end

struct EventIdentity
    schema_version::String
    model_fingerprint::String
    plan_fingerprint::String
    logical_time::LogicalTime
    ordinal::UInt64
    fingerprint::String
end

function EventIdentity(
    model_fingerprint::AbstractString,
    plan_fingerprint::AbstractString,
    logical_time::LogicalTime,
    ordinal::UInt64,
)
    payload = (
        :process_bigraph_event_identity_v1,
        String(model_fingerprint),
        String(plan_fingerprint),
        logical_time,
        ordinal,
    )
    EventIdentity(
        "1.0.0",
        String(model_fingerprint),
        String(plan_fingerprint),
        logical_time,
        ordinal,
        canonical_fingerprint(payload),
    )
end

"""
An adaptive temporal schedule. The first invocation is fixed, and every complete
invocation must propose its next exact logical deadline transactionally.
"""
struct AdaptiveSchedule <: AbstractSchedule
    first_due::Duration
    supports_partial::Bool
    function AdaptiveSchedule(
        first_due::Duration;
        supports_partial::Bool=false,
    )
        first_due.tick > 0 ||
            _fail(:nonpositive_deadline, "first process deadline must be positive")
        new(first_due, supports_partial)
    end
end

"""
Internal lowered schedule for one authored `At` occurrence.

The clock becomes inactive after its exact deadline. Ordinary authors use
`At`; this type exists only so the runtime can represent completion without a
sentinel time or a fake numerical cadence.
"""
struct OneShotSchedule <: AbstractSchedule
    first_due::Duration
    supports_partial::Bool
    function OneShotSchedule(first_due::Duration)
        first_due.tick > 0 ||
            _fail(:nonpositive_deadline,
                "one-shot process deadline must be positive")
        new(first_due, false)
    end
end

"""
A model-owned explicit fixed-structure iterative region.

`:bounded` executes exactly `max_iterations`; `:convergent` stops when all
`watch_paths` have the same canonical values before and after an iteration and
fails if the bound is exhausted.
"""
struct IterationRegion
    id::String
    steps::Tuple{Vararg{String}}
    mode::Symbol
    max_iterations::Int
    watch_paths::Tuple{Vararg{Path}}
    function IterationRegion(
        id::AbstractString,
        steps;
        mode::Symbol=:convergent,
        max_iterations::Integer=32,
        watch_paths=(),
    )
        isempty(id) && _fail(:empty_iteration_identity,
            "iteration-region identity cannot be empty")
        normalized_steps = tuple(String.(steps)...)
        isempty(normalized_steps) && _fail(:empty_iteration_region,
            "iteration regions require at least one step"; id)
        length(normalized_steps) == length(unique(normalized_steps)) ||
            _fail(:duplicate_iteration_step,
                "an iteration region cannot contain a step more than once"; id)
        mode in (:bounded, :convergent) ||
            _fail(:invalid_iteration_mode,
                "iteration mode must be bounded or convergent"; id, mode)
        max_iterations > 0 ||
            _fail(:invalid_iteration_bound,
                "iteration bound must be positive"; id, max_iterations)
        max_iterations <= typemax(Int) ||
            _fail(:iteration_bound_overflow,
                "iteration bound exceeds the Int fast path"; id)
        normalized_watch = tuple(watch_paths...)
        mode === :convergent && isempty(normalized_watch) &&
            _fail(:missing_convergence_paths,
                "convergent regions require watched state paths"; id)
        new(String(id), normalized_steps, mode, Int(max_iterations), normalized_watch)
    end
end

abstract type AbstractIntervalInput end

struct FrozenInput{T} <: AbstractIntervalInput
    start_time::LogicalTime
    end_time::LogicalTime
    value::T
end

struct InterpolatedInput{T} <: AbstractIntervalInput
    start_time::LogicalTime
    end_time::LogicalTime
    start_value::T
    end_value::T
end

struct EventUpdatedInput <: AbstractIntervalInput
    start_time::LogicalTime
    end_time::LogicalTime
    samples::Tuple
end

struct ContinuouslyCallableInput <: AbstractIntervalInput
    start_time::LogicalTime
    end_time::LogicalTime
    samples::Tuple
end

function value_at(input::FrozenInput, time::LogicalTime)
    input.start_time <= time <= input.end_time ||
        _fail(:interval_query_out_of_bounds,
            "interval input queried outside its admitted interval")
    deepcopy(input.value)
end

function value_at(input::InterpolatedInput, time::LogicalTime)
    input.start_time <= time <= input.end_time ||
        _fail(:interval_query_out_of_bounds,
            "interpolated input queried outside its admitted interval")
    input.start_time == input.end_time && return deepcopy(input.end_value)
    fraction = (time.tick - input.start_time.tick) //
        (input.end_time.tick - input.start_time.tick)
    try
        deepcopy(input.start_value + (input.end_value - input.start_value) * fraction)
    catch
        _fail(:unsupported_interpolation,
            "interpolated input values do not admit exact linear interpolation";
            type=string(typeof(input.start_value)))
    end
end

function value_at(
    input::Union{EventUpdatedInput,ContinuouslyCallableInput},
    time::LogicalTime,
)
    input.start_time <= time <= input.end_time ||
        _fail(:interval_query_out_of_bounds,
            "timeline input queried outside its admitted interval")
    eligible = [sample for sample in input.samples if first(sample) <= time]
    isempty(eligible) &&
        _fail(:empty_input_timeline,
            "timeline contains no value at the requested time")
    deepcopy(last(last(eligible)))
end

struct ProcessInputCursor
    id::String
    since::LogicalTime
    start_values::Tuple
    samples::Tuple
end

function _canonical(io::IO, cursor::ProcessInputCursor)
    write(io, "IC")
    _canonical(io, cursor.id)
    _canonical(io, cursor.since)
    _canonical(io, cursor.start_values)
    _canonical(io, cursor.samples)
end

struct ActivationRecord
    owner::String
    kind::Symbol
    layer::Int
    iteration::Int
    input_fingerprint::String
    output_fingerprint::String
end

struct IterationOutcome
    region::String
    iterations::Int
    converged::Bool
    fingerprint::String
end

struct EventRecord
    schema_version::String
    event_id::String
    ordinal::UInt64
    time::LogicalTime
    due_processes::Tuple{Vararg{String}}
    activations::Tuple{Vararg{ActivationRecord}}
    iterations::Tuple{Vararg{IterationOutcome}}
    before_fingerprint::String
    after_fingerprint::String
    runtime_fingerprint::String
end

function _canonical(io::IO, schedule::AdaptiveSchedule)
    write(io, "AS")
    _canonical(io, "1.0.0")
    _canonical(io, schedule.first_due)
    _canonical(io, schedule.supports_partial)
end

function _canonical(io::IO, schedule::OneShotSchedule)
    write(io, "OS")
    _canonical(io, "1.0.0")
    _canonical(io, schedule.first_due)
end

function _canonical(io::IO, identity::EventIdentity)
    write(io, "EI")
    _canonical(io, identity.schema_version)
    _canonical(io, identity.model_fingerprint)
    _canonical(io, identity.plan_fingerprint)
    _canonical(io, identity.logical_time)
    _canonical(io, identity.ordinal)
    _canonical(io, identity.fingerprint)
end

function _canonical(io::IO, region::IterationRegion)
    write(io, "IR")
    _canonical(io, "1.0.0")
    _canonical(io, region.id)
    _canonical(io, region.steps)
    _canonical(io, region.mode)
    _canonical(io, region.max_iterations)
    _canonical(io, region.watch_paths)
end

function _canonical(io::IO, record::ActivationRecord)
    write(io, "AR")
    _canonical(io, record.owner)
    _canonical(io, record.kind)
    _canonical(io, record.layer)
    _canonical(io, record.iteration)
    _canonical(io, record.input_fingerprint)
    _canonical(io, record.output_fingerprint)
end

function _canonical(io::IO, outcome::IterationOutcome)
    write(io, "IO")
    _canonical(io, outcome.region)
    _canonical(io, outcome.iterations)
    _canonical(io, outcome.converged)
    _canonical(io, outcome.fingerprint)
end

function _canonical(io::IO, record::EventRecord)
    write(io, "ER")
    _canonical(io, record.schema_version)
    _canonical(io, record.event_id)
    _canonical(io, record.ordinal)
    _canonical(io, record.time)
    _canonical(io, record.due_processes)
    _canonical(io, record.activations)
    _canonical(io, record.iterations)
    _canonical(io, record.before_fingerprint)
    _canonical(io, record.after_fingerprint)
    _canonical(io, record.runtime_fingerprint)
end
