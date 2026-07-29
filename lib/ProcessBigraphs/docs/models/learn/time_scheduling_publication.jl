using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct TimedPulse <: AbstractProcess
    amount::Int
end

ports(::TimedPulse) = (
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::TimedPulse) = "1.0.0"
semantic_parameters(pulse::TimedPulse) = (amount=pulse.amount,)
invoke(pulse::TimedPulse, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), pulse.amount),
))

scale = TimeScale(1, 100, :second)
model = compose(:TimedPublication; scale) do system
    total = store!(
        system, :total,
        LeafSchema(Int; default=0, update_law=:add),
    )
    periodic = mount!(system, :periodic, TimedPulse(1))
    connect!(system, periodic.out, total)
    schedule!(system, periodic, Every(Duration(2, scale)))
    one_shot = mount!(system, :one_shot, TimedPulse(10))
    connect!(system, one_shot.out, total)
    schedule!(system, one_shot, At(LogicalTime(3, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(6, scale))

result = (
    value=current_snapshot(runtime)[path("total")],
    commits=event_count(runtime),
    times=Tuple(record.time.tick for record in event_trace(runtime)),
)
@assert result.value == 13
@assert result.times == (2, 3, 4, 6)
