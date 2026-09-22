using StaticArrays

@testset "default product arrays preserve declared logical structure" begin
    @variables memory::NamedTuple{(:samples,), Tuple{SVector{2, NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}}}}
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :default_product_samples,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(memory), ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (memory,),
    )
    ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium)
    problem = PottsProblem(source, PottsInitialState(; ownership), (0, 1); seed = 17)
    expected = (samples = SVector((amount = 0.0f0, enabled = false), (amount = 0.0f0, enabled = false)),)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        @test integrator.u[:memory] === expected
        restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        @test restored.u[:memory] === expected
        @test solve!(integrator).u[end][:memory] === expected
    end
end
