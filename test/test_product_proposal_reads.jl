@testset "model product Boolean fields constrain proposals" begin
    @variables memory::NamedTuple{(:nested,), Tuple{NamedTuple{(:enabled,), Tuple{Bool}}}}
    memory_state = ModelState(memory; initial = (nested = (enabled = true,),))
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :model_product_constraint,
        statements = StatementSet(
            (
                Lattice((6, 6); boundary = Closed()), cell, medium, memory_state,
                ProposalConstraint(:held_ownership, !memory_state.nested.enabled),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (memory,),
    )
    labels = zeros(Int, 6, 6)
    labels[3:4, 3:4] .= 1
    ownership = LabelledCells(labels; cells = [cell], medium)
    initial = PottsInitialState(; ownership)
    problem = PottsProblem(source, initial, (0, 2); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        before = deepcopy(integrator.u[:memory])
        step!(integrator)
        @test integrator.u[:memory] == before
        restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        step!(integrator)
        step!(restored)
        @test restored.u[:memory] == integrator.u[:memory] == before
        @test restored.t == integrator.t == 2
        solution = solve!(integrator)
        @test last(solution).ownership == labels
        @test solution.stats.constraint_rejections > 0
        @test solution.stats.accepted == 0
    end
end
