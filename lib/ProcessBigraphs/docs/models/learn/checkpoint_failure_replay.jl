using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct ReplayIncrement <: AbstractProcess
    amount::Int
end

ports(::ReplayIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::ReplayIncrement) = "1.0.0"
semantic_parameters(law::ReplayIncrement) = (amount=law.amount,)
invoke(law::ReplayIncrement, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
))

scale = TimeScale(1)
model = compose(:Replayable; scale, profile=:reproducible) do system
    state = store!(
        system, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    actor = mount!(system, :increment, ReplayIncrement(2))
    attach!(system, actor, (state=state, out=state))
    schedule!(system, actor, Every(Duration(1, scale)))
end
plan = compile(model)

uninterrupted = initialize_runtime(plan)
run_until!(uninterrupted, LogicalTime(5, scale))

interrupted = initialize_runtime(plan)
run_until!(interrupted, LogicalTime(2, scale))
saved = checkpoint(interrupted)
restored = restore(plan, saved)
run_until!(restored, LogicalTime(5, scale))

result = (
    value=current_snapshot(restored)[path("state")],
    exact=snapshot_fingerprint(current_snapshot(restored)) ==
        snapshot_fingerprint(current_snapshot(uninterrupted)),
    events=event_count(restored),
    checkpoint=checkpoint_fingerprint(saved),
)
@assert result.value == 10
@assert result.exact
@assert result.events == event_count(uninterrupted)
