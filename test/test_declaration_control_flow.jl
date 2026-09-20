module DeclarationFactoryHelpers
    using Potts
    state(variable, value) = StatementSet((ModelState(variable; initial = value),))
end

@testset "declaration control flow preserves Julia evaluation and enrollment order" begin
    @variables first_value second_value
    visits = Int[]
    declarations = @statements begin
        for (index, variable) in enumerate((first_value, second_value))
            if (push!(visits, index); index == 1)
                DeclarationFactoryHelpers.state(variable, 1.0)
            elseif index == 2
                ModelState(variable; initial = 2.0)
            else
                error("unselected declaration branch executed")
            end
        end
    end
    @test visits == [1, 2]
    source = PottsSystem(declarations; name = :factory_loop)
    @test isequal(unknowns(source), [first_value, second_value])
    @test length(declarations) == 2
    @test all(statement -> statement_source(statement) isa SourceLocation, declarations)

    visits = Int[]
    index = 99
    selected = @statements begin
        for index in 1:4
            if (push!(visits, index); index == 1)
                continue
            elseif index == 3
                break
            end
            ModelState(first_value; initial = index)
        end
    end
    @test visits == [1, 2, 3]
    @test index == 99
    @test length(selected) == 1
    counter = Ref(0)
    while_selected = @statements begin
        while (counter[] += 1; counter[] <= 2)
            ModelState(counter[] == 1 ? first_value : second_value; initial = counter[])
        end
    end
    @test counter[] == 3
    @test length(while_selected) == 2
    empty = @statements begin
        for index in 1:0
            error("empty declaration loop executed")
        end
    end
    @test isempty(empty)
end

@testset "conditional symbolic enrollment assembles a complete numerical model" begin
    calls = Symbol[]
    recorded_increment() = (push!(calls, :default); 3.0)
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = @statements PottsSystem(; name = (push!(calls, :constructor); :loop_model)) begin
        @variables first_value second_value
        if (push!(calls, :condition); true)
            @parameters increment = recorded_increment()
        else
            @parameters absent = error("unused branch evaluated")
        end
        begin
            Lattice((2, 2); boundary = Closed())
            cell
            medium
        end
        for (variable, initial) in ((first_value, 1.0), (second_value, 2.0))
            ModelState(variable; initial)
        end
        for (name, variable) in ((:advance_first, first_value), (:advance_second, second_value))
            Synchronous(name, Assign(variable, variable + increment))
        end
        ProposalConstraint(:fixed_ownership, false)
        Protocol(Sweep(; temperature = 0.0); name = :main)
    end
    @test calls == [:condition, :default, :constructor]
    @test isequal(parameters(source), [increment])
    @test isequal(unknowns(source), [first_value, second_value])
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    problem = PottsProblem(source, initial, (0, 1); seed = 51)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm)
        step!(integrator)
        @test integrator.u[:first_value] == 4.0f0
        @test integrator.u[:second_value] == 5.0f0
        @test failure_report(integrator) === nothing
    end

    duplicate = @statements PottsSystem(; name = :repeated_declaration) begin
        @variables amount
        for index in 1:2
            ModelState(amount; initial = 0.0)
        end
    end
    @test_throws Potts.PottsValidationError complete(duplicate)
end
