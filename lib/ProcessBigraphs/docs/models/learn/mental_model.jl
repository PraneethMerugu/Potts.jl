using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct MentalPulse <: AbstractProcess
    amount::Int
end

ports(::MentalPulse) = (
    InputPort(Int, :current),
    OutputPort(Int, :increment; update_law=:add),
)
semantic_version(::MentalPulse) = "1.0.0"
semantic_parameters(pulse::MentalPulse) = (amount=pulse.amount,)
invoke(pulse::MentalPulse, inputs, context) = InvocationResult((
    emit(context, :increment, AdditiveUpdate(), pulse.amount),
))

scale = TimeScale(1)
model = compose(:MentalModel; scale) do system
    count = store!(
        system, :count,
        LeafSchema(Int; default=0, update_law=:add),
    )
    pulse = mount!(system, :pulse, MentalPulse(2))
    connect!(system, pulse.current, count)
    connect!(system, pulse.increment, count)
    schedule!(system, pulse, Every(Duration(1, scale)))
    observable!(system, :count, count)
end

report = validate(model)
plan = compile(model)
result = (
    valid=isempty(report.diagnostics),
    model=semantic_fingerprint(model),
    structure=structural_fingerprint(plan),
    execution=plan_fingerprint(plan),
)
