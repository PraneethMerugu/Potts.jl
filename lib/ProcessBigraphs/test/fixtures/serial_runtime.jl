import ProcessBigraphs: ports, invoke, semantic_parameters,
    continuation_schema, observe, observer_semantic_parameters

struct C15Add <: AbstractProcess
    amount::Int
end

ports(::C15Add) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:add),
)
semantic_parameters(law::C15Add) = (amount=law.amount,)
invoke(law::C15Add, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
))

struct C15Adaptive <: AbstractProcess
    amount::Int
    offset::Int
end

ports(::C15Adaptive) =
    (OutputPort(Int, :out; update_law=:add),)
semantic_parameters(law::C15Adaptive) =
    (amount=law.amount, offset=law.offset)
invoke(law::C15Adaptive, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
); next_deadline=LogicalTime(
    context.end_time.tick + law.offset,
    context.end_time.scale,
))

struct C15Counter <: AbstractProcess end
ports(::C15Counter) =
    (OutputPort(Int, :out; update_law=:add),)
continuation_schema(::C15Counter) = ContinuationSchema(
    "c15-counter-state",
    CanonicalContinuationCodec{typeof((count=0,))}(),
)
function invoke(::C15Counter, inputs, context)
    next = (count=context.continuation.count + 1,)
    InvocationResult((
        emit(context, :out, AdditiveUpdate(), next.count),
    ); continuation=next)
end

struct C15BadContinuation <: AbstractProcess end
ports(::C15BadContinuation) =
    (OutputPort(Int, :out; update_law=:add),)
continuation_schema(::C15BadContinuation) = ContinuationSchema(
    "c15-bad-counter-state",
    CanonicalContinuationCodec{typeof((count=0,))}(),
)
invoke(::C15BadContinuation, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), 1),
); continuation="wrong-type")

struct C15Random <: AbstractProcess end
ports(::C15Random) =
    (OutputPort(UInt64, :out; update_law=:replace),)
invoke(::C15Random, inputs, context) = InvocationResult((
    emit(context, :out, ReplaceUpdate(),
        semantic_bits(context, :branch, 0)),
))

struct C15Producer <: AbstractProcess end
ports(::C15Producer) =
    (OutputPort(Int, :out; update_law=:add),)
invoke(::C15Producer, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), 1),
))

struct C15IntervalProbe <: AbstractProcess
    behavior::Symbol
end
ports(law::C15IntervalProbe) = (
    InputPort(Int, :input; interval_behavior=law.behavior),
    OutputPort(Int, :observed; update_law=:replace),
)
semantic_parameters(law::C15IntervalProbe) = (behavior=law.behavior,)
function invoke(law::C15IntervalProbe, inputs, context)
    interval = interval_input(inputs, :input)
    value = if interval isa FrozenInput
        value_at(interval, context.start_time)
    elseif interval isa InterpolatedInput
        Int(value_at(interval, context.end_time))
    else
        length(interval.samples)
    end
    InvocationResult((
        emit(context, :observed, ReplaceUpdate(), value),
    ))
end

struct C15ReactiveCopy <: AbstractStep end
ports(::C15ReactiveCopy) = (
    InputPort(Int, :input),
    OutputPort(Int, :out; update_law=:replace),
)
invoke(::C15ReactiveCopy, inputs, context) = InvocationResult((
    emit(context, :out, ReplaceUpdate(), inputs[:input]),
))

struct C15Converge <: AbstractStep end
ports(::C15Converge) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:replace),
)
invoke(::C15Converge, inputs, context) = InvocationResult((
    emit(context, :out, ReplaceUpdate(), min(inputs[:state] + 1, 2)),
))

struct C15Bounded <: AbstractStep end
ports(::C15Bounded) =
    (OutputPort(Int, :out; update_law=:add),)
invoke(::C15Bounded, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), 1),
))

struct C15Observer <: AbstractObserver end
observer_semantic_parameters(::C15Observer) = (kind=:state_projection,)
function observe(::C15Observer, projection, context)
    ObservationResult((
        value=projection[path("state")],
        time=context.time.tick,
    ))
end

struct C15FailObserver <: AbstractObserver end
observe(::C15FailObserver, projection, context) =
    throw(ProcessBigraphError(:observer_fixture_failure, "requested observer failure"))

struct C15RandomObserver <: AbstractObserver end
observer_semantic_parameters(::C15RandomObserver) = (kind=:semantic_rng_probe,)
observe(::C15RandomObserver, projection, context) = ObservationResult((
    draw=semantic_bits(context.rng, :observer_probe, 0),
    state=projection[path("state")],
))

struct C15CountingObserver <: AbstractObserver end
ProcessBigraphs.observer_continuation_schema(::C15CountingObserver) =
    ContinuationSchema(
        "c15-observer-counter",
        CanonicalContinuationCodec{typeof((count=0,))}(),
    )
function observe(::C15CountingObserver, projection, context)
    next = (count=context.continuation.count + 1,)
    ObservationResult(
        (count=next.count, value=projection[path("state")]);
        continuation=next,
    )
end

struct C15LeakyObserver <: AbstractObserver end
observe(::C15LeakyObserver, projection, context) =
    ObservationResult((secret=projection[path("secret")],))

function c15_add_composite(;
    processes=("fast" => (1, 1), "slow" => (10, 2)),
)
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    model = compose(:C15AddFixture, schema; scale) do builder, stores
        for (id, (amount, cadence)) in processes
            actor = mount!(builder, Symbol(id), C15Add(amount))
            schedule!(
                builder, actor, Every(Duration(cadence, scale)))
            attach!(builder, actor, (
                state=stores.state,
                out=stores.state,
            ))
        end
    end
    compile(model)
end

function c15_observation_plan(scale; required=true, schedule=EventObservationSchedule())
    spec = ObserverSpec(
        "state-observer",
        C15Observer(),
        (path("state"),),
        schedule;
        required,
        record_schema=RecordSchema(typeof((value=0, time=0,));
            identity="state-time-record"),
    )
    ObservationPlan((spec,))
end
