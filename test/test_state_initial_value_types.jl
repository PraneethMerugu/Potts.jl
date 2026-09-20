using StaticArrays

@testset "declared logical state types and initial shapes" begin
    @variables tensor[1:2, 1:2] direction[1:2] counter::Int32 enabled::Bool
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium)

    function state_problem(variable, declaration; supplied = nothing)
        system = PottsSystem(
            name = :typed_state,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    declaration, ProposalConstraint(:fixed_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (variable,),
        )
        values = supplied === nothing ? () : (variable => supplied,)
        return PottsProblem(system, PottsInitialState(; ownership, values), (0, 1); seed = 17)
    end

    @testset "declared integer and Boolean meaning survives precision selection" begin
        for (variable, initial) in ((counter, Int32(3)), (enabled, true))
            problem = state_problem(variable, ModelState(variable; initial))
            for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
                integrator = init(problem, algorithm; scalar_type = Float32)
                getter = SymbolicIndexingInterface.getsym(problem.system, variable)
                @test getter(integrator) === initial
                solution = solve!(integrator)
                @test solution.retcode == SciMLBase.ReturnCode.Success
                @test getter(integrator) === initial
            end
        end
        fractional = state_problem(counter, ModelState(counter; initial = Int32(3)); supplied = 1.5)
        @test_throws InexactError init(fractional)
        nonboolean = state_problem(enabled, ModelState(enabled; initial = true); supplied = 2)
        @test_throws InexactError init(nonboolean)
    end

    @testset "scalar symbolic components reject nested initial arrays" begin
        nested = SVector(SVector(1.0, 2.0), SVector(3.0, 4.0))
        for constructor in (ModelState, SiteState)
            problem = state_problem(direction, constructor(direction; initial = nested))
            @test_throws r"requires scalar components" init(problem; scalar_type = Float32)
        end
    end

    @testset "tensor axes remain inside each logical value" begin
        initial = SMatrix{2, 2}(1.0, 2.0, 3.0, 4.0)
        supplied = SMatrix{2, 2}(5.0, 6.0, 7.0, 8.0)
        for declaration in (ModelState(tensor; initial), SiteState(tensor; initial))
            is_model = declaration isa ModelState
            values = is_model ? supplied : fill(supplied, 2, 2)
            problem = state_problem(tensor, declaration; supplied = values)
            for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
                integrator = init(problem, algorithm; scalar_type = Float32)
                expected = is_model ? Float32.(supplied) : fill(Float32.(supplied), 2, 2)
                @test integrator.u[:tensor] == expected
                logical_type = is_model ? typeof(integrator.u[:tensor]) : eltype(integrator.u[:tensor])
                @test logical_type === SMatrix{2, 2, Float32, 4}
                restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
                @test restored.u[:tensor] == expected
            end
        end
        default_problem = state_problem(tensor, ModelState(tensor))
        @test init(default_problem; scalar_type = Float32).u[:tensor] == zero(SMatrix{2, 2, Float32, 4})
        wrong_declaration = state_problem(tensor, ModelState(tensor; initial = SVector(1.0, 2.0)))
        @test_throws r"fixed-size initial value with shape" init(wrong_declaration)
        wrong_value = state_problem(tensor, ModelState(tensor; initial); supplied = SVector(1.0, 2.0))
        @test_throws r"wrong logical shape" init(wrong_value)
        nonfinite = state_problem(tensor, ModelState(tensor; initial); supplied = SMatrix{2, 2}(1.0, Inf, 3.0, 4.0))
        @test_throws r"must be finite" init(nonfinite)
    end
end
