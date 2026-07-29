using ProcessBigraphs
using Test

import ProcessBigraphs: AbstractProcess, ports, invoke

struct DocumentedIncrement <: AbstractProcess
    amount::Int
end

ports(::DocumentedIncrement) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)

function invoke(law::DocumentedIncrement, inputs, context)
    InvocationResult((
        emit(context, :increment, AdditiveUpdate(), law.amount),
    ))
end

scale = TimeScale(1)
model = compose(:DocumentedCounter; scale) do builder
    state = store!(
        builder,
        :state,
        LeafSchema(Int; default=0, update_law=:add),
    )
    increment = mount!(builder, :increment, DocumentedIncrement(2))
    schedule!(builder, increment, Every(Duration(1, scale)))
    connect!(builder, state, increment.state, increment.increment)
    observable!(builder, :state_value, state)
end

report = validate(model)
lowered = lower(model)
plan = compile(lowered)
problem = SimulationProblem(
    model;
    tspan=(LogicalTime(0, scale), LogicalTime(3, scale)),
    initial=(model.state.state => 5,),
    observations=(model.observables.state_value,),
    seed=0x1234,
)
runtime = initialize_runtime(problem)
run_until!(runtime, LogicalTime(3, scale))

@test isempty(report.diagnostics)
@test lowered isa LoweredModel
@test plan_fingerprint(plan) == execution_plan_fingerprint(plan)
@test problem.observations == (:state_value => true,)
@test current_snapshot(runtime)[path("state")] == 11
