abstract type AbstractObserver end

observe(::AbstractObserver, projection, context) =
    _fail(:missing_observe_method, "observer does not implement observe")
observer_semantic_version(::AbstractObserver) = "1"
observer_semantic_parameters(::AbstractObserver) = NamedTuple()
observer_continuation_schema(::AbstractObserver) =
    stateless_continuation_schema()

abstract type AbstractObservationSchedule end

struct EventObservationSchedule <: AbstractObservationSchedule end

struct PeriodicObservationSchedule <: AbstractObservationSchedule
    cadence::Duration
    first_due::Duration
    function PeriodicObservationSchedule(
        cadence::Duration;
        first_due::Duration=cadence,
    )
        cadence.tick > 0 ||
            _fail(:nonpositive_observer_cadence,
                "observer cadence must be positive")
        cadence.scale == first_due.scale ||
            _fail(:time_scale_mismatch,
                "observer schedule durations must use one scale")
        first_due.tick >= 0 ||
            _fail(:negative_observer_deadline,
                "observer first deadline cannot be negative")
        new(cadence, first_due)
    end
end

const ObservationSchedule = PeriodicObservationSchedule

struct AtTimesObservationSchedule <: AbstractObservationSchedule
    times::Tuple{Vararg{LogicalTime}}
    function AtTimesObservationSchedule(times)
        normalized = tuple(sort!(collect(times);
            by=time -> (time.scale.unit, time.scale.numerator,
                time.scale.denominator, time.tick))...)
        length(normalized) == length(unique(normalized)) ||
            _fail(:duplicate_observation_time,
                "at-times observer schedule contains duplicate times")
        isempty(normalized) ||
            all(time -> time.scale == first(normalized).scale, normalized) ||
            _fail(:time_scale_mismatch,
                "at-times observer schedule must use one scale")
        new(normalized)
    end
end

struct RecordSchema{T}
    identity::String
    version::String
end

function RecordSchema(
    ::Type{T};
    identity::AbstractString="record-$(string(T))",
    version::AbstractString="1.0.0",
) where {T}
    isempty(identity) && _fail(:empty_record_schema,
        "observation record schema identity cannot be empty")
    RecordSchema{T}(String(identity), String(version))
end

function validate_record(::RecordSchema{T}, value) where {T}
    value isa T || _fail(:observation_record_type_mismatch,
        "observer record does not match its output schema";
        expected=string(T), actual=string(typeof(value)))
    encode_logical_value(value)
    true
end

struct ObserverSpec{
    O<:AbstractObserver,
    S<:AbstractObservationSchedule,
    R<:RecordSchema,
    C<:BoundContinuationSpec,
}
    id::String
    observer::O
    paths::Tuple{Vararg{Path}}
    metadata::NamedTuple
    schedule::S
    required::Bool
    optional_failure_policy::Symbol
    continuation::Any
    continuation_spec::C
    record_schema::R
end

function ObserverSpec(
    id::AbstractString,
    observer::O,
    paths,
    schedule::S;
    metadata::NamedTuple=NamedTuple(),
    required::Bool=true,
    optional_failure_policy::Symbol=:publish_failure_record,
    continuation=nothing,
    continuation_schema=nothing,
    record_schema::RecordSchema=RecordSchema(Any;
        identity="canonical-record-v1"),
) where {O<:AbstractObserver,S<:AbstractObservationSchedule}
    identity = String(id)
    isempty(identity) && _fail(:empty_observer_identity,
        "observer identity cannot be empty")
    optional_failure_policy in (:publish_failure_record, :omit_and_advance) ||
        _fail(:invalid_optional_observer_policy,
            "optional observer failure policy is unknown";
            observer=identity)
    schema = isnothing(continuation_schema) ?
        observer_continuation_schema(observer) : continuation_schema
    bound = bind_continuation(
        identity,
        observer_semantic_version(observer),
        canonical_fingerprint((:observer_schedule_v1, schedule)),
        schema,
    )
    validate_continuation(bound, identity, continuation)
    canonical_bytes(metadata)
    ObserverSpec{
        O,S,typeof(record_schema),typeof(bound),
    }(
        identity,
        observer,
        tuple(paths...),
        metadata,
        schedule,
        required,
        optional_failure_policy,
        deepcopy(continuation),
        bound,
        record_schema,
    )
end

struct ObservationPlan
    observers::Tuple{Vararg{ObserverSpec}}
    fingerprint::String
end

function ObservationPlan(observers=())
    values = tuple(observers...)
    ids = String[observer.id for observer in values]
    length(ids) == length(unique(ids)) ||
        _fail(:duplicate_observer_identity,
            "observation plan contains duplicate observer identities")
    ordered = tuple(sort!(collect(values);
        by=observer -> observer.id)...)
    identity = canonical_fingerprint((
        :observation_plan_v1,
        tuple(((
            observer.id,
            string(typeof(observer.observer)),
            observer_semantic_version(observer.observer),
            observer_semantic_parameters(observer.observer),
            observer.paths,
            observer.metadata,
            observer.schedule,
            observer.required,
            observer.optional_failure_policy,
            observer.continuation_spec,
            continuation_fingerprint(observer.continuation_spec,
                observer.continuation),
            observer.record_schema,
        ) for observer in ordered)...),
    ))
    ObservationPlan(ordered, identity)
end

struct ObserverContext
    owner::String
    event_id::String
    time::LogicalTime
    continuation::Any
    rng::ObserverRNGContext
end

struct ObservationResult{T,C}
    record::T
    continuation::C
end

ObservationResult(record; continuation=nothing) =
    ObservationResult(record, continuation)

struct ObservationRecord{T}
    observer::String
    event_id::String
    time::LogicalTime
    status::Symbol
    payload::T
    payload_fingerprint::String
end

struct ObserverClock
    id::String
    next_due::Union{Nothing,LogicalTime}
    continuation::Any
    position::UInt64
end

observation_fingerprint(plan::ObservationPlan) = plan.fingerprint

function _initial_observer_deadline(
    schedule::PeriodicObservationSchedule,
    origin::LogicalTime,
)
    origin + schedule.first_due
end
_initial_observer_deadline(
    ::EventObservationSchedule,
    ::LogicalTime,
) = nothing
_initial_observer_deadline(
    schedule::AtTimesObservationSchedule,
    ::LogicalTime,
) = isempty(schedule.times) ? nothing : first(schedule.times)

function _next_observer_deadline(
    schedule::PeriodicObservationSchedule,
    clock::ObserverClock,
)
    clock.next_due + schedule.cadence
end
_next_observer_deadline(
    ::EventObservationSchedule,
    ::ObserverClock,
) = nothing
function _next_observer_deadline(
    schedule::AtTimesObservationSchedule,
    clock::ObserverClock,
)
    next_position = Int(clock.position) + 2
    next_position > length(schedule.times) ?
        nothing : schedule.times[next_position]
end

function _canonical(io::IO, ::EventObservationSchedule)
    write(io, "OE")
    _canonical(io, "1.0.0")
end

function _canonical(io::IO, schedule::PeriodicObservationSchedule)
    write(io, "OP")
    _canonical(io, "1.0.0")
    _canonical(io, schedule.cadence)
    _canonical(io, schedule.first_due)
end

function _canonical(io::IO, schedule::AtTimesObservationSchedule)
    write(io, "OT")
    _canonical(io, "1.0.0")
    _canonical(io, schedule.times)
end

function _canonical(io::IO, schema::RecordSchema{T}) where {T}
    write(io, "RS")
    _canonical(io, string(T))
    _canonical(io, schema.identity)
    _canonical(io, schema.version)
end

function _canonical(io::IO, record::ObservationRecord)
    write(io, "OR")
    _canonical(io, record.observer)
    _canonical(io, record.event_id)
    _canonical(io, record.time)
    _canonical(io, record.status)
    _canonical(io, record.payload)
    _canonical(io, record.payload_fingerprint)
end

function _canonical(io::IO, clock::ObserverClock)
    write(io, "OC")
    _canonical(io, clock.id)
    _canonical(io, clock.next_due)
    _canonical(io, clock.continuation)
    _canonical(io, clock.position)
end
