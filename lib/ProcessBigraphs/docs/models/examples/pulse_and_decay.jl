using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct PulseAndDecay <: AbstractProcess
    pulse::Float64
    retention::Float64
end

ports(::PulseAndDecay) = (
    OutputPort(Float64, :accumulated; update_law=:add),
    OutputPort(Float64, :remaining; update_law=:multiply),
)
semantic_version(::PulseAndDecay) = "1.0.0"
semantic_parameters(law::PulseAndDecay) = (
    pulse=law.pulse,
    retention=law.retention,
)
invoke(law::PulseAndDecay, inputs, context) = InvocationResult((
    emit(context, :accumulated, AdditiveUpdate(), law.pulse),
    emit(context, :remaining, MultiplicativeUpdate(), law.retention),
))

scale = TimeScale(1)
model = compose(:PulseAndDecay; scale) do system
    accumulated = store!(
        system, :accumulated,
        LeafSchema(Float64; default=0.0, update_law=:add),
    )
    remaining = store!(
        system, :remaining,
        LeafSchema(Float64; default=100.0, update_law=:multiply),
    )
    dynamics = mount!(system, :dynamics, PulseAndDecay(2.0, 0.5))
    attach!(system, dynamics, (
        accumulated=accumulated,
        remaining=remaining,
    ))
    schedule!(system, dynamics, Every(Duration(1, scale)))
end

runtime = initialize_runtime(compile(model))
run_until!(runtime, LogicalTime(3, scale))
result = (
    accumulated=current_snapshot(runtime)[path("accumulated")],
    remaining=current_snapshot(runtime)[path("remaining")],
)
@assert result == (accumulated=6.0, remaining=12.5)
