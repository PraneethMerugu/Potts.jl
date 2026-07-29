using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct NestedIncrement <: AbstractProcess
    amount::Int
end

ports(::NestedIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::NestedIncrement) = "1.0.0"
semantic_parameters(law::NestedIncrement) = (amount=law.amount,)
invoke(law::NestedIncrement, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
))

scale = TimeScale(1)
counter = compose(:ReusableCounter; scale) do child
    state = store!(
        child, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    actor = mount!(child, :increment, NestedIncrement(1))
    attach!(child, actor, (state=state, out=state))
    schedule!(child, actor, Every(Duration(1, scale)))
    expose!(child, :state, state; role=:bidirectional)
end

system = compose(:NestedSystem; scale) do parent
    shared = store!(
        parent, :shared,
        LeafSchema(Int; default=0, update_law=:add),
    )
    left = mount!(parent, :left, counter)
    right = mount!(parent, :right, counter)
    connect!(parent, left.state, shared)
    connect!(parent, right.state, shared)
    expose!(parent, :total, shared; role=:bidirectional)
end

runtime = initialize_runtime(compile(system))
run_until!(runtime, LogicalTime(3, scale))
result = (
    total=current_snapshot(runtime)[path("shared")],
    structure=ir_fingerprint(lower(system)),
    execution=plan_fingerprint(compile(system)),
)
@assert result.total == 6
