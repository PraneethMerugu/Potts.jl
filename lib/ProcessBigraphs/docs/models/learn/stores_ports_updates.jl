using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct TypedTransfer <: AbstractProcess
    increment::Int
end

ports(::TypedTransfer) = (
    InputPort(Int, :source; interval_behavior=:frozen),
    OutputPort(Int, :source_out; update_law=:add),
    OutputPort(Int, :published; update_law=:replace),
)
semantic_version(::TypedTransfer) = "1.0.0"
semantic_parameters(law::TypedTransfer) = (increment=law.increment,)
function invoke(law::TypedTransfer, inputs, context)
    next = inputs[:source] + law.increment
    InvocationResult((
        emit(context, :source_out, AdditiveUpdate(), law.increment),
        emit(context, :published, ReplaceUpdate(), next),
    ))
end

scale = TimeScale(1)
schema = BranchSchema(
    source=LeafSchema(Int; default=1, update_law=:add, units="molecule"),
    published=LeafSchema(Int; default=0, update_law=:replace, units="molecule"),
)
model = compose(:TypedStores, schema; scale) do system, stores
    transfer = mount!(system, :transfer, TypedTransfer(2))
    connect!(system, transfer.source, stores.source)
    connect!(system, transfer.source_out, stores.source)
    connect!(system, transfer.published, stores.published)
    schedule!(system, transfer, Every(Duration(1, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(3, scale))
snapshot = current_snapshot(runtime)

result = (
    leaves=first.(schema_leaves(schema)),
    source=snapshot[path("source")],
    published=snapshot[path("published")],
    commits=event_count(runtime),
)
@assert result.source == 7
@assert result.published == 7
