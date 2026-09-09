using StaticArrays, DynamicQuantities, ModelingToolkitBase, SymbolicIndexingInterface, Symbolics
import CorePotts

function _vector_parameter_problem(; defaults = [2.0, 3.0])
    @parameters weights[1:2] = defaults
    @parameters temperature = 1.0
    @variables direction[1:2] amount
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :vector_coefficients,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(direction; initial = SVector(0.0, 0.0)),
                ModelState(amount; initial = 0.0),
                Synchronous(:coefficients, Assign(direction, weights)),
                Synchronous(:weighted_increment, Assign(amount, amount + weights[1] + 2weights[2])),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature); name = :main),
            )
        ),
        unknowns = (direction, amount), parameters = (weights, temperature),
    )
    initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
    return PottsProblem(source, initial, (0, 4); seed = 71), weights, temperature, direction, amount
end


include(joinpath(@__DIR__, "..", "..", "examples", "vector_coefficients.jl"))

function _fixed_vector_parameters_contract(algorithms, backend)
    return @testset "fixed-vector parameters use logical identities and component slots" begin
        problem, weights, temperature, direction, amount = _vector_parameter_problem()
        @test_throws ArgumentError Potts._assert_concrete_core_boundary(CorePotts.CompilerSPI.LiteralExpression(weights))
        @test getp(problem, weights)(problem) == SVector(2.0, 3.0)
        @test getp(problem, weights[2])(problem) == 3.0
        @test getp(problem, weights)(remake(problem; p = Dict(weights[2] => 5.0))) == SVector(2.0, 5.0)
        @test_throws ArgumentError remake(problem; p = Dict(weights => [1.0, 2.0, 3.0]))
        @test_throws ArgumentError remake(problem; p = [weights => [1.0, 2.0], weights[2] => 4.0])
        @test_throws ArgumentError setp(problem, (weights, weights[1]))
        @test_throws ArgumentError setp(problem, (weights[1], weights[1]))
        @test_throws ArgumentError remake(problem; p = Dict(weights => Float64[]))
        @test_throws r"default of matching size" _vector_parameter_problem(; defaults = Float64[])
        @test_throws r"default of matching size" _vector_parameter_problem(; defaults = [1.0, 2.0, 3.0])
        component = SymbolicIndexingInterface.parameter_index(problem.system, weights[2])
        remade = SymbolicIndexingInterface.remake_buffer(problem.system, problem.p, (component,), (6.0,))
        @test remade[:weights] == SVector(2.0, 6.0)
        @test_throws ArgumentError SymbolicIndexingInterface.remake_buffer(problem.system, problem.p, (weights, component), ([4.0, 5.0], 6.0))
        for algorithm in algorithms
            @testset "$(typeof(algorithm))" begin
                integrator = init(problem, algorithm; backend, scalar_type = Float32)
                read_vector = getp(problem.system, weights)
                read_second = getp(problem, weights[2])
                old_parameters = SymbolicIndexingInterface.parameter_values(integrator)
                @test old_parameters isa Tuple
                @test read_vector(integrator) === SVector(2.0f0, 3.0f0)
                step!(integrator)
                @test integrator.u[:direction] == SVector(2.0f0, 3.0f0)
                @test integrator.u[:amount] == 8.0f0
                setp(problem.system, weights)(integrator, [4.0, 5.0])
                @test read_second(integrator) == 5.0f0
                @test old_parameters[SymbolicIndexingInterface.parameter_index(problem.system, weights)] == SVector(2.0f0, 3.0f0)
                before = SymbolicIndexingInterface.parameter_values(integrator)
                before_u = integrator.u
                @test_throws ArgumentError setp(integrator, temperature)(integrator, -1.0)
                @test_throws ArgumentError setp(integrator, (temperature, weights))(integrator, (2.0, [1.0, Inf]))
                @test_throws ArgumentError setp(integrator, (weights[1], weights[2]))(integrator, (8.0, Inf))
                @test SymbolicIndexingInterface.parameter_values(integrator) == before
                @test integrator.u === before_u
                setp(integrator, (weights[1], weights[2]))(integrator, (6.0, 7.0))
                @test read_vector(integrator) == SVector(6.0f0, 7.0f0)
                setp(integrator, weights[2]; run_hook = false)(integrator, 9.0)
                @test read_second(integrator) == 7.0f0
                SymbolicIndexingInterface.finalize_parameters_hook!(integrator, (weights[2],))
                @test read_second(integrator) == 9.0f0
                saved = checkpoint(integrator)
                restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = saved)
                step!(integrator)
                step!(restored)
                @test integrator.u[:direction] == SVector(6.0f0, 9.0f0)
                @test integrator.u[:amount] == 32.0f0
                @test restored.u[:direction] == integrator.u[:direction]
                @test restored.u[:amount] == integrator.u[:amount]
                @test restored.u.ownership == integrator.u.ownership == ones(Int32, 2, 2)
                @test read_vector(restored) == read_vector(integrator)
                solution = solve!(integrator)
                @test solution.u[end][:amount] == 80.0f0
                @test getp(solution, weights)(solution) == SVector(6.0f0, 9.0f0)
                @test getp(solution, weights[2])(solution) == 9.0f0
                saved_parameters = SymbolicIndexingInterface.parameter_values(solution)
                setp(restored, weights)(restored, [10.0, 11.0])
                @test SymbolicIndexingInterface.parameter_values(solution) == saved_parameters
                @test getp(solution, weights)(solution) == SVector(6.0f0, 9.0f0)
                @test getp(restored, weights)(restored) == SVector(10.0f0, 11.0f0)
            end
        end
    end

end

function _vector_parameter_units_and_imports_contract(algorithms, backend)
    @testset "an imported vector parameter retains one mutable scientific owner" begin
        example = VectorCoefficientsExample.problem()
        @test length(parameters(example.problem.system)) == 1
        @test isequal(only(parameters(example.problem.system)), example.coefficients)
        for algorithm in algorithms
            integrator = init(example.problem, algorithm; backend, scalar_type = Float32)
            step!(integrator)
            @test integrator.u[:response₊direction] == SVector(2.0f0, 3.0f0)
            @test integrator.u[:response₊amount] == 8.0f0
            setp(example.problem.system, example.coefficients[2])(integrator, 5.0)
            saved = checkpoint(integrator)
            restored = init(example.problem, algorithm; backend, scalar_type = Float32, checkpoint = saved)
            step!(integrator)
            step!(restored)
            @test integrator.u[:response₊direction] == restored.u[:response₊direction] == SVector(2.0f0, 5.0f0)
            @test integrator.u[:response₊amount] == restored.u[:response₊amount] == 20.0f0
            @test getp(integrator, example.coefficients)(integrator) == SVector(2.0f0, 5.0f0)
        end
    end

    return @testset "vector parameter quantities retain physical inputs and normalized continuation" begin
        @parameters target[1:2] = [2.0u"m", 4.0u"m"]
        @variables position[1:2]
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        source = PottsSystem(
            name = :dimensional_coefficients,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    ModelState(position; initial = SVector(0.0u"m", 0.0u"m")),
                    Synchronous(:target, Assign(position, target)),
                    ProposalConstraint(:held_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (position,), parameters = (target,),
        )
        completed = complete(source; reference_units = ReferenceUnits(length = 2.0u"m"))
        initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
        problem = PottsProblem(completed, initial, (0, 3); seed = 17)
        @test getp(problem, target)(problem) == SVector(2.0u"m", 4.0u"m")
        @test_throws ArgumentError remake(problem; p = Dict(target => [2.0, 3.0]))
        @test_throws ArgumentError remake(problem; p = Dict(target => [2.0u"m", 3.0u"s"]))
        updated = remake(problem; p = Dict(target[2] => 600.0u"cm"))
        @test getp(updated, target)(updated) == SVector(2.0u"m", 6.0u"m")
        for algorithm in algorithms
            integrator = init(updated, algorithm; backend, scalar_type = Float32)
            step!(integrator)
            @test integrator.u[:position] == SVector(1.0f0, 3.0f0)
            old = SymbolicIndexingInterface.parameter_values(integrator)
            setp(problem, target)(integrator, [400.0u"cm", 800.0u"cm"])
            @test getp(integrator, target)(integrator) == SVector(2.0f0, 4.0f0)
            @test old == (SVector(1.0f0, 3.0f0),)
            before_u = integrator.u
            @test_throws ArgumentError setp(integrator, (target[1], target[2]))(integrator, (6.0u"m", 7.0u"s"))
            @test integrator.u === before_u
            @test getp(integrator, target)(integrator) == SVector(2.0f0, 4.0f0)
            restored = init(updated, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator))
            step!(integrator)
            step!(restored)
            @test integrator.u[:position] == restored.u[:position] == SVector(2.0f0, 4.0f0)
            @test getp(restored, target)(restored) == getp(integrator, target)(integrator)
        end
    end

end
