using StaticArrays

@testset "operation family snapshots reject conflicting scientific contracts" begin
    source = complete(PottsSystem(name = :schema_owner, statements = StatementSet(Observation(:coefficient, 1.0))))
    record = only(Potts._completion_data(source).records)
    contract(; gpu = true) = Potts.OperationTransfer(
        :coefficient_construction;
        arity = 1:3, result_rule = :real, unit_rule = :dimensionless,
        footprint_rule = Potts.InheritFootprintRule(), gpu,
    )
    snapshot = Potts.FrozenOperationSchema[]
    Potts._insert_operation_schema!(snapshot, Potts.FrozenOperationSchema(nothing, 2, contract(), +), record)
    Potts._insert_operation_schema!(snapshot, Potts.FrozenOperationSchema(+, 3, contract(), +), record)
    @test length(snapshot) == 1
    for conflicting in (
            Potts.FrozenOperationSchema(+, 2, contract(; gpu = false), +),
            Potts.FrozenOperationSchema(+, 2, contract(), -),
        )
        error = try
            Potts._insert_operation_schema!(snapshot, conflicting, record)
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        if error isa Potts.PottsValidationError
            @test only(error.diagnostics).kind === :conflicting_operation_schema
            @test only(error.diagnostics).identity == record.identity
            @test only(error.diagnostics).source == record.source
        end
    end
end

@testset "different fixed-vector lengths share one declared operation family" begin
    @parameters plane[1:2] = [2.0, 3.0]
    @parameters space[1:3] = [4.0, 5.0, 6.0]
    @parameters scale = 1.0
    @variables direction[1:2] orientation[1:3] unrelated
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :different_vector_lengths,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(direction; initial = SVector(0.0, 0.0)),
                ModelState(orientation; initial = SVector(0.0, 0.0, 0.0)),
                Synchronous(:plane_coefficients, Assign(direction, plane)),
                Synchronous(:space_coefficients, Assign(orientation, space)),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        parameters = (plane, space, scale), unknowns = (direction, orientation),
    )
    initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
    problem = PottsProblem(source, initial, (0, 2); seed = 19)
    for provider in (source, complete(source), problem.system)
        @test SymbolicIndexingInterface.is_parameter(provider, :scale)
        for parameter in (plane, space, scale)
            @test SymbolicIndexingInterface.is_parameter(provider, parameter)
            @test SymbolicIndexingInterface.is_parameter(provider, Symbolics.unwrap(parameter))
        end
        @test !SymbolicIndexingInterface.is_parameter(provider, unrelated)
        @test !SymbolicIndexingInterface.is_parameter(provider, Symbolics.unwrap(unrelated))
        @test !SymbolicIndexingInterface.is_parameter(provider, :unrelated)
    end
    remade = remake(problem; p = Dict(plane => [7.0, 8.0], space => [9.0, 10.0, 11.0]))
    overlaid = remake(remade; p = Dict(space[2] => 20.0))
    @test getp(overlaid, plane)(overlaid) == SVector(7.0, 8.0)
    @test getp(overlaid, space)(overlaid) == SVector(9.0, 20.0, 11.0)
    @test getp(remade, space)(remade) == SVector(9.0, 10.0, 11.0)
    @test getp(problem, plane)(problem) == SVector(2.0, 3.0)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(overlaid, algorithm; scalar_type = Float32)
        step!(integrator)
        @test integrator.u[:direction] == SVector(7.0f0, 8.0f0)
        @test integrator.u[:orientation] == SVector(9.0f0, 20.0f0, 11.0f0)
        setp(integrator, (plane, space[3]))(integrator, ([1.0, 2.0], 30.0))
        step!(integrator)
        @test integrator.u[:direction] == SVector(1.0f0, 2.0f0)
        @test integrator.u[:orientation] == SVector(9.0f0, 20.0f0, 30.0f0)
    end
end

@testset "required vector components and remake overlays preserve source values" begin
    @parameters required[1:2]
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :required_coefficients,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        parameters = (required,),
    )
    initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
    @test_throws r"missing required runtime parameters" PottsProblem(source, initial, (0, 1); seed = 19)
    @test_throws r"missing required runtime parameters" PottsProblem(source, initial, (0, 1); p = Dict(required[1] => 2.0), seed = 19)
    problem = PottsProblem(source, initial, (0, 1); p = Dict(required[1] => 2.0, required[2] => 3.0), seed = 19)
    @test getp(problem, required)(problem) == SVector(2.0, 3.0)
    @test_throws ArgumentError remake(problem; p = Dict(required[2] => Inf))
    @test getp(problem, required)(problem) == SVector(2.0, 3.0)
    changed = remake(problem; p = Dict(required[2] => 4.0))
    @test getp(changed, required)(changed) == SVector(2.0, 4.0)
    @test getp(problem, required)(problem) == SVector(2.0, 3.0)
end

@testset "effective parameter values are validated after defaults and overrides" begin
    @parameters coefficient = Inf
    @variables amount
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :default_override,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(amount; initial = 0.0),
                Synchronous(:advance, Assign(amount, amount + coefficient)),
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        parameters = (coefficient,), unknowns = (amount,),
    )
    initial = PottsInitialState(ownership = LabelledCells(ones(Int32, 2, 2); cells = [cell], medium))
    problem = PottsProblem(source, initial, (0, 1); p = Dict(coefficient => 3.0), seed = 13)
    @test_throws ArgumentError PottsProblem(source, initial, (0, 1); seed = 13)
    @test_throws ArgumentError remake(problem; p = Dict(coefficient => Inf))
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        before = integrator.u
        @test_throws ArgumentError setp(integrator, coefficient)(integrator, Inf)
        @test integrator.u === before
        @test getp(integrator, coefficient)(integrator) == 3.0f0
        step!(integrator)
        @test integrator.u[:amount] == 3.0f0
    end
end
