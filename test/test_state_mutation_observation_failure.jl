# Fault injection stays inside the owning package. It tests the refresh boundary,
# not a public extension point for arbitrary observation evaluators.
struct FailingMutationObservation{E} <: Potts.AbstractCompiledObservationEvaluator
    original::E
    fail::Base.RefValue{Bool}
end
function Potts._evaluate_observation(evaluator::FailingMutationObservation, runtime)
    evaluator.fail[] && error("injected host observation failure")
    return Potts._evaluate_observation(evaluator.original, runtime)
end

function _with_mutation_observation(integrator, observation)
    plan = integrator.plan
    replacement_plan = Potts._PottsExecutionPlan(
        (
            name === :observations ? (observation,) : getfield(plan, name)
                for name in fieldnames(typeof(plan))
        )...,
    )
    return Potts.PottsIntegrator(
        (
            name === :plan ? replacement_plan : getfield(integrator, name)
                for name in fieldnames(typeof(integrator))
        )...,
    )
end

@testset "host observation refresh failure restores published state" begin
    @variables amount
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :mutation_refresh,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(amount; initial = 2.0),
                Observation(:snapshot, amount),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
    )
    labels = ones(Int, 2, 2)
    initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
    problem = PottsProblem(source, initial, (0, 1); seed = 29)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32, observables = (:snapshot,))
        original_u = integrator.u
        original_checkpoint = checkpoint(integrator)
        original_observation = only(integrator.plan.observations)
        fail = Ref(true)
        observation = merge(
            original_observation, (
                evaluator = FailingMutationObservation(original_observation.evaluator, fail),
            )
        )
        integrator = _with_mutation_observation(integrator, observation)
        try
            @test_throws r"injected host observation failure" setu(integrator, amount)(integrator, 9.0)
            @test integrator.u === original_u
            @test integrator.t == 0
            @test integrator.u[:amount] === 2.0f0
            @test integrator.u.ownership == labels
            @test failure_report(integrator) === nothing
        finally
            fail[] = false
        end
        restored_before = init(problem, algorithm; scalar_type = Float32, checkpoint = original_checkpoint, observables = (:snapshot,))
        restored_after = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator), observables = (:snapshot,))
        @test restored_after.u[:amount] === restored_before.u[:amount] === 2.0f0
        @test restored_after.t == restored_before.t == 0
        @test restored_after.u.ownership == restored_before.u.ownership
        @test only(restored_after.u[:snapshot]) === 2.0f0
        setu(integrator, amount)(integrator, 3.0)
        @test only(integrator.u[:snapshot]) === 3.0f0
        @test original_u[:amount] === 2.0f0
    end
end
