using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct JunctionSource <: AbstractProcess
    amount::Int
end

ports(::JunctionSource) = (
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::JunctionSource) = "1.0.0"
semantic_parameters(source::JunctionSource) = (amount=source.amount,)
invoke(source::JunctionSource, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), source.amount),
))

scale = TimeScale(1)
model = compose(:NWayJunction; scale) do system
    junction = store!(
        system, :junction,
        LeafSchema(Int; default=0, update_law=:add),
    )
    for (name, amount) in ((:left, 1), (:center, 2), (:right, 3))
        source = mount!(system, name, JunctionSource(amount))
        connect!(system, source.out, junction)
        schedule!(system, source, Every(Duration(1, scale)))
    end
    expose!(system, :sum, junction; role=:export)
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(2, scale))
result = (
    value=current_snapshot(runtime)[path("junction")],
    commits=event_count(runtime),
    diagram=diagram(model),
)
@assert result.value == 12
@assert result.commits == 2
