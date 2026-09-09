using Symbolics, ModelingToolkitBase, SymbolicIndexingInterface

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

function _symbolic_mutation_refresh_failure_contract(algorithms, backend)
    return @testset "host observation refresh failure restores published state" begin
        @variables amount
        @parameters rate = 1.0
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
                    Protocol(Sweep(; temperature = rate); name = :main),
                )
            ),
            parameters = (rate,),
        )
        labels = ones(Int, 2, 2)
        initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell], medium))
        problem = PottsProblem(source, initial, (0, 1); seed = 29)
        for algorithm in algorithms
            integrator = init(problem, algorithm; backend, scalar_type = Float32, observables = (:snapshot,))
            original_u = integrator.u
            original_checkpoint = checkpoint(integrator)
            setp(integrator, rate; run_hook = false)(integrator, 4.0)
            original_pending = copy(integrator.pending_parameters)
            original_history = copy(integrator.parameter_history)
            original_observation = only(integrator.plan.observations)
            fail = Ref(true)
            observation = merge(
                original_observation, (
                    evaluator = FailingMutationObservation(original_observation.evaluator, fail),
                )
            )
            integrator = _with_mutation_observation(integrator, observation)
            try
                for (setter, values) in (
                        (setu(integrator, amount), 9.0),
                        (setp(integrator, rate), 3.0),
                        (setu(integrator, (amount, rate)), (9.0, 3.0)),
                    )
                    @test_throws r"injected host observation failure" setter(integrator, values)
                    @test integrator.u === original_u
                    @test integrator.t == 0
                    @test integrator.u[:amount] === 2.0f0
                    @test integrator.u.ownership == labels
                    @test getp(integrator, rate)(integrator) === 1.0f0
                    @test integrator.pending_parameters == original_pending
                    @test integrator.parameter_history == original_history
                    @test failure_report(integrator) === nothing
                end
            finally
                fail[] = false
            end
            @test_throws r"finalize the staged parameter transaction" checkpoint(integrator)
            @test integrator.pending_parameters == original_pending
            # A successful complete publication explicitly supersedes staging.
            setp(integrator, rate)(integrator, 1.0)
            restored_before = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = original_checkpoint, observables = (:snapshot,))
            restored_after = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator), observables = (:snapshot,))
            @test restored_after.u[:amount] === restored_before.u[:amount] === 2.0f0
            @test restored_after.t == restored_before.t == 0
            @test restored_after.u.ownership == restored_before.u.ownership
            @test getp(restored_after, rate)(restored_after) === getp(restored_before, rate)(restored_before) === 1.0f0
            @test only(restored_after.u[:snapshot]) === 2.0f0
            setp(integrator, rate; run_hook = false)(integrator, 4.0)
            setu(integrator, amount)(integrator, 3.0)
            @test only(integrator.u[:snapshot]) === 3.0f0
            @test original_u[:amount] === 2.0f0
            @test integrator.pending_parameters == original_pending
        end
    end
end
