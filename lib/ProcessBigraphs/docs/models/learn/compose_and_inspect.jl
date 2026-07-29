using ProcessBigraphs
import ProcessBigraphs: AbstractProcess, ports, semantic_version,
    semantic_parameters, invoke

struct InspectableIncrement <: AbstractProcess
    amount::Int
end

ports(::InspectableIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)
semantic_version(::InspectableIncrement) = "1.0.0"
semantic_parameters(law::InspectableIncrement) = (amount=law.amount,)
invoke(law::InspectableIncrement, inputs, context) = InvocationResult((
    emit(context, :increment, AdditiveUpdate(), law.amount),
))

scale = TimeScale(1)
model = compose(:Inspectable; scale, profile=:reproducible) do system
    state = store!(
        system, :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    gain = parameter!(
        system, :gain, 3;
        units="dimensionless",
        description="Documented experiment parameter",
    )
    actor = mount!(system, :increment, InspectableIncrement(gain.default))
    attach!(system, actor, (state=state, increment=state))
    schedule!(system, actor, Every(Duration(1, scale)))
    observable!(system, :state, state)
end

validation = validate(model)
lowered = lower(model)
plan = compile(lowered)

result = (
    summary=describe(model),
    expanded=diagram(model),
    valid=isempty(validation.diagnostics),
    semantic=semantic_fingerprint(model),
    canonical=ir_fingerprint(lowered),
    execution=plan_fingerprint(plan),
)
@assert result.valid
