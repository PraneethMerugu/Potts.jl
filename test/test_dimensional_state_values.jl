using StaticArrays

@testset "fixed array state uses one compatible reference dimension" begin
    @variables position[1:2] tensor[1:2, 1:2]
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium)
    for state_constructor in (ModelState, SiteState)
        source = PottsSystem(
            name = :dimensional_position,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    state_constructor(position; initial = SVector(2.0u"m", 4.0u"m")),
                    ProposalConstraint(:fixed_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (position,),
        )
        system = mtkcompile(complete(source; reference_units = ReferenceUnits(length = 2.0u"m")))
        is_model = state_constructor === ModelState
        for supplied in (nothing, SVector(600.0u"cm", 800.0u"cm"))
            values = supplied === nothing ? () :
                (position => (is_model ? supplied : fill(supplied, 2, 2)),)
            problem = PottsProblem(system, PottsInitialState(; ownership, values), (0, 1); seed = 17)
            expected = supplied === nothing ? SVector(1.0f0, 2.0f0) : SVector(3.0f0, 4.0f0)
            expected_state = is_model ? expected : fill(expected, 2, 2)
            for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
                integrator = init(problem, algorithm; scalar_type = Float32)
                @test integrator.u[:position] == expected_state
                restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
                @test restored.u[:position] == expected_state
                @test solve!(integrator).u[end][:position] == expected_state
            end
        end
        for incompatible in (SVector(1.0, 2.0), SVector(1.0u"s", 2.0u"s"))
            values = (position => (is_model ? incompatible : fill(incompatible, 2, 2)),)
            problem = PottsProblem(system, PottsInitialState(; ownership, values), (0, 1); seed = 17)
            @test_throws ArgumentError init(problem)
        end
    end
    tensor_source = PottsSystem(
        name = :dimensional_tensor,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(tensor; initial = SMatrix{2, 2}(2.0u"m", 4.0u"m", 6.0u"m", 8.0u"m")),
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (tensor,),
    )
    tensor_system = mtkcompile(complete(tensor_source; reference_units = ReferenceUnits(length = 2.0u"m")))
    tensor_problem = PottsProblem(tensor_system, PottsInitialState(; ownership), (0, 1); seed = 17)
    tensor_value = init(tensor_problem; scalar_type = Float32).u[:tensor]
    @test tensor_value == SMatrix{2, 2}(1.0f0, 2.0f0, 3.0f0, 4.0f0)
    @test typeof(tensor_value) === SMatrix{2, 2, Float32, 4}
end
