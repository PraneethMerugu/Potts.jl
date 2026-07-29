using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, AbstractStep, AbstractObserver,
    ports, semantic_version, semantic_parameters, invoke,
    observer_semantic_version, observer_semantic_parameters, observe

struct ProducedSignal <: AbstractProcess end
ports(::ProducedSignal) = (
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::ProducedSignal) = "1.0.0"
invoke(::ProducedSignal, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), 1),
))

struct CopySignal <: AbstractStep end
ports(::CopySignal) = (
    InputPort(Int, :input),
    OutputPort(Int, :out; update_law=:replace),
)
semantic_version(::CopySignal) = "1.0.0"
invoke(::CopySignal, inputs, context) = InvocationResult((
    emit(context, :out, ReplaceUpdate(), inputs[:input]),
))

struct SignalObserver <: AbstractObserver end
observer_semantic_version(::SignalObserver) = "1.0.0"
observer_semantic_parameters(::SignalObserver) = (record=:signal_and_tick,)
observe(::SignalObserver, projection, context) = ObservationResult((
    signal=projection[path("signal")],
    tick=Int(context.time.tick),
))

scale = TimeScale(1)
model = compose(:WrittenComponents; scale) do system
    signal = store!(
        system, :signal,
        LeafSchema(Int; default=0, update_law=:add),
    )
    copied = store!(
        system, :copied,
        LeafSchema(Int; default=0, update_law=:replace),
    )
    producer = mount!(system, :producer, ProducedSignal())
    connect!(system, producer.out, signal)
    schedule!(system, producer, Every(Duration(1, scale)))
    copier = mount!(system, :copier, CopySignal())
    attach!(system, copier, (input=signal, out=copied))
end

observer = ObserverSpec(
    "signal-observer",
    SignalObserver(),
    (path("signal"),),
    EventObservationSchedule();
    record_schema=RecordSchema(
        NamedTuple; identity="signal-record-v1",
    ),
)
executor = SerialExecutor(
    root_seed=7,
    observation_plan=ObservationPlan((observer,)),
)
runtime = initialize_runtime(compile(model), executor)
run_until!(runtime, LogicalTime(3, scale))

result = (
    signal=current_snapshot(runtime)[path("signal")],
    copied=current_snapshot(runtime)[path("copied")],
    observations=Tuple(record.payload for record in observation_records(runtime)),
)
@assert result.signal == result.copied == 3
@assert last(result.observations).signal == 3
