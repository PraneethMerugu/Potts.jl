using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct ScheduledPulse <: AbstractProcess
    amount::Int
end

ports(::ScheduledPulse) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::ScheduledPulse) = "1.0.0"
semantic_parameters(pulse::ScheduledPulse) = (amount=pulse.amount,)
invoke(pulse::ScheduledPulse, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), pulse.amount),
))

scale = TimeScale(1, 1, :minute)
model = compose(:FirstMultirate; scale, profile=:reproducible) do system
    total = store!(
        system, :total,
        LeafSchema(Int; default=0, update_law=:add),
    )

    fast = mount!(system, :fast, ScheduledPulse(1))
    attach!(system, fast, (state=total, out=total))
    schedule!(system, fast, Every(Duration(1, scale)))

    slow = mount!(system, :slow, ScheduledPulse(10))
    attach!(system, slow, (state=total, out=total))
    schedule!(system, slow, Every(Duration(2, scale)))

    observable!(system, :total, total)
end

problem = SimulationProblem(
    model;
    tspan=(LogicalTime(0, scale), LogicalTime(4, scale)),
    observations=(model.observables.total,),
    seed=2021,
)
runtime = initialize_runtime(problem)
run_until!(runtime, last(problem.tspan))

result = (
    total=current_snapshot(runtime)[path("total")],
    events=event_count(runtime),
    settled=settled(runtime),
    fingerprint=problem_fingerprint(problem),
)
@assert result == (
    total=24,
    events=4,
    settled=true,
    fingerprint=problem_fingerprint(problem),
)
