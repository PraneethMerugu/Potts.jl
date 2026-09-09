@testset "lexically declared dimensional parameters retain overrides and execution" begin
    calls = Ref(0)
    default_increment() = (calls[] += 1; 2.0u"m")
    source = @statements PottsSystem(; name = :lexical_length) begin
        @parameters increment = default_increment() unused_length = 5.0u"m"
        @variables position
        Lattice((2, 2); boundary = Closed())
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        ModelState(position; initial = 0.0u"m")
        Synchronous(:advance, Assign(position, position + increment))
        ProposalConstraint(:held_ownership, false)
        Protocol(Sweep(; temperature = 0.0); name = :main)
    end
    @test calls[] == 1
    @test length(parameters(source)) == 2
    scheduled = mtkcompile(complete(source; reference_units = ReferenceUnits(length = 2.0u"m")))
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
    )
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 17)
    changed = remake(problem; p = (increment => 4.0u"m", unused_length => 9.0u"m"))
    @test_throws ArgumentError remake(problem; p = (unused_length => 9.0u"s",))
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        for (current_problem, stride, unused) in ((problem, 1.0f0, 2.5f0), (changed, 2.0f0, 4.5f0))
            integrator = init(current_problem, algorithm; scalar_type = Float32)
            @test SymbolicIndexingInterface.getp(integrator, unused_length)(integrator) == unused
            for boundary in 1:2
                step!(integrator)
                @test integrator.u[:position] == boundary * stride
                @test failure_report(integrator) === nothing
            end
        end
    end
    @test calls[] == 1
end
