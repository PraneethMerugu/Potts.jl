using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct RecoverableGrowth <: AbstractProcess
    amount::Int
end

ports(::RecoverableGrowth) = (
    InputPort(Int, :mass),
    OutputPort(Int, :out; update_law=:add),
)
semantic_version(::RecoverableGrowth) = "1.0.0"
semantic_parameters(law::RecoverableGrowth) = (amount=law.amount,)
invoke(law::RecoverableGrowth, inputs, context) = InvocationResult((
    emit(context, :out, AdditiveUpdate(), law.amount),
))

scale = TimeScale(1)
cell = compose(:RecoverableCell; scale) do child
    mass = store!(
        child, :mass,
        LeafSchema(Int; default=1, update_law=:add),
    )
    growth = mount!(child, :growth, RecoverableGrowth(1))
    attach!(child, growth, (mass=mass, out=mass))
    schedule!(child, growth, Every(Duration(1, scale)))
    expose!(child, :mass, mass; role=:bidirectional)
end

host = compose(:RecoveryHost; scale, profile=:reproducible) do system
    mass = store!(
        system, :mass,
        LeafSchema(Int; default=1, update_law=:add),
    )
    mounted = mount!(system, :founder, cell)
    connect!(system, mounted.mass, mass)
    allow_instances!(system, :daughters, cell; capacity=4)
end
plan = compile(host)

runtime = initialize_runtime(plan)
run_until!(runtime, LogicalTime(2, scale))
safe_cut = checkpoint(runtime)
run_until!(runtime, LogicalTime(4, scale))

recovered = restore(plan, safe_cut)
run_until!(recovered, LogicalTime(4, scale))
result = (
    mass=current_snapshot(recovered)[path("mass")],
    exact=snapshot_fingerprint(current_snapshot(recovered)) ==
        snapshot_fingerprint(current_snapshot(runtime)),
    template=(name=:daughters, capacity=4),
)
@assert result.mass == 5
@assert result.exact
