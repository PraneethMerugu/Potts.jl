function expression_reference_problem()
    @parameters length_input = 6.0u"m" time_input = 2.0u"s" area_input = 25.0u"m^2" threshold = 4.0u"m/s"
    @variables multiplied divided powered rooted added smallest largest ratio reciprocal
    @variables comparison::Bool counter::Int32
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :expression_scales, statements = StatementSet(
            (
                Lattice((1, 1); boundary = Closed()), medium,
                ModelState(multiplied; initial = 0.0u"m*s"),
                ModelState(divided; initial = 0.0u"m/s"),
                ModelState(powered; initial = 0.0u"m^2"),
                ModelState(rooted; initial = 0.0u"m"),
                ModelState(added; initial = 0.0u"m/s"),
                ModelState(smallest; initial = 0.0u"m/s"),
                ModelState(largest; initial = 0.0u"m/s"),
                ModelState(ratio; initial = 0.0),
                ModelState(reciprocal; initial = 0.0u"s^-1"),
                ModelState(comparison; initial = true),
                ModelState(counter; initial = Int32(4)),
                Synchronous(
                    :evaluate,
                    Assign(multiplied, length_input * time_input),
                    Assign(divided, length_input / time_input),
                    Assign(powered, length_input^2),
                    Assign(rooted, sqrt(area_input)),
                    Assign(added, length_input / time_input + threshold),
                    Assign(smallest, min(length_input / time_input, threshold)),
                    Assign(largest, max(length_input / time_input, threshold)),
                    Assign(ratio, length_input / length_input),
                    Assign(reciprocal, 1 / time_input),
                    Assign(comparison, length_input / time_input > threshold),
                    Assign(counter, counter * Int32(3))
                ),
                ProposalConstraint(:held, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), parameters = (length_input, time_input, area_input, threshold),
        unknowns = (multiplied, divided, powered, rooted, added, smallest, largest, ratio, reciprocal, comparison, counter)
    )
    references = ReferenceUnits(length = 2.0u"m", time = 3.0u"s", area = 5.0u"m^2", rate = 11.0u"m/s", length_time = 17.0u"m*s", inverse_time = 7.0u"s^-1")
    initial = PottsInitialState(ownership = LabelledCells(zeros(Int, 1, 1); cells = CellKind[], medium))
    return PottsProblem(complete(source; reference_units = references), initial, (0, 1); seed = 17)
end

@testset "ordinary expressions use their declared dimension reference scales" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM()), T in (Float32, Float64)
        integrator = init(expression_reference_problem(), algorithm; scalar_type = T)
        step!(integrator)
        @test integrator.u[:multiplied] ≈ 12 / 17 rtol = 10eps(T)
        @test integrator.u[:divided] ≈ 3 / 11 rtol = 10eps(T)
        @test integrator.u[:powered] ≈ 36 / 5 rtol = 10eps(T)
        @test integrator.u[:rooted] ≈ 5 / 2 rtol = 10eps(T)
        @test integrator.u[:added] ≈ 7 / 11 rtol = 10eps(T)
        @test integrator.u[:smallest] ≈ 3 / 11 rtol = 10eps(T)
        @test integrator.u[:largest] ≈ 4 / 11 rtol = 10eps(T)
        @test integrator.u[:ratio] == 1
        @test integrator.u[:reciprocal] ≈ 0.5 / 7 rtol = 10eps(T)
        @test integrator.u[:comparison] === false
        @test integrator.u[:counter] === Int32(12)
        @test failure_report(integrator) === nothing
    end
end

@testset "lifecycle expression products use the same dimensional normalization" begin
    @parameters length_input = 6.0u"m" time_input = 2.0u"s"
    @variables accumulated
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :lifecycle_scales, statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                CellState(accumulated; initial = 0.0u"m*s", creation = InitializeFrom(length_input * time_input)),
                LifecycleProcess(
                    :create; domain = model(), expression = true,
                    effects = (CreateCell(cell; placement = SeedAt(1), on_inadmissible = ErrorOnInadmissible()),),
                    cadence = AtMCS(1)
                ),
                ProposalConstraint(:held, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), parameters = (length_input, time_input), unknowns = (accumulated,)
    )
    initial = PottsInitialState(ownership = LabelledCells(zeros(Int, 2, 2); cells = CellKind[], medium))
    references = ReferenceUnits(length = 2.0u"m", time = 3.0u"s", length_time = 17.0u"m*s")
    problem = PottsProblem(complete(source; reference_units = references), initial, (0, 1); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm)
        step!(integrator)
        @test integrator.u[:accumulated] ≈ Float32[12 / 17]
        @test integrator.u.ownership[1] == 1
        @test failure_report(integrator) === nothing
    end
end

@testset "unanchored intermediate dimensions use SI without a parallel reference inventory" begin
    @parameters length_input = 3.0u"m" inverse_length = 2.0u"m^-1"
    @variables result
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :intermediate_scales, statements = StatementSet(
            (
                Lattice((1, 1); boundary = Closed()), medium,
                ModelState(result; initial = 0.0u"m"),
                Synchronous(:evaluate, Assign(result, length_input^2 * inverse_length)),
                ProposalConstraint(:held, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (result,), parameters = (length_input, inverse_length)
    )
    references = ReferenceUnits(length = 2.0u"m", inverse_length = 7.0u"m^-1")
    initial = PottsInitialState(ownership = LabelledCells(zeros(Int, 1, 1); cells = CellKind[], medium))
    problem = PottsProblem(complete(source; reference_units = references), initial, (0, 1); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        step!(integrator)
        @test integrator.u[:result] ≈ 9.0f0
        @test failure_report(integrator) === nothing
    end
end

function dimensionless_reference_problem(scale)
    @variables ratio
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :dimensionless_reference, statements = StatementSet(
            (
                Lattice((1, 1); boundary = Closed()), medium, ModelState(ratio; initial = 1.0u"m/m"),
                Synchronous(:increment, Assign(ratio, ratio + 1)),
                ProposalConstraint(:held, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (ratio,)
    )
    completed = complete(source; reference_units = ReferenceUnits(ratio = scale * u"m/m"))
    initial = PottsInitialState(ownership = LabelledCells(zeros(Int, 1, 1); cells = CellKind[], medium))
    return PottsProblem(completed, initial, (0, 1); seed = 17)
end

@testset "dimensionless references cannot redefine plain numeric values" begin
    @test_throws r"dimensionless reference unit.*scale one" init(dimensionless_reference_problem(2.0), SequentialCPM())
    integrator = init(dimensionless_reference_problem(1.0), SequentialCPM())
    step!(integrator)
    @test integrator.u[:ratio] == 2.0
end

@testset "negative powers retain precision independent of ambient BigFloat settings" begin
    @parameters duration = 2.0u"s"
    @variables inverse_square
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :negative_power_scales, statements = StatementSet(
            (
                Lattice((1, 1); boundary = Closed()), medium,
                ModelState(inverse_square; initial = 0.0u"s^-2"),
                Synchronous(:evaluate, Assign(inverse_square, duration^-2)),
                ProposalConstraint(:held, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), parameters = (duration,), unknowns = (inverse_square,)
    )
    initial = PottsInitialState(ownership = LabelledCells(zeros(Int, 1, 1); cells = CellKind[], medium))
    references = ReferenceUnits(time = 3.0u"s", inverse_square_time = 13.0u"s^-2")
    problem = PottsProblem(complete(source; reference_units = references), initial, (0, 1); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = setprecision(BigFloat, 32) do
            result = init(problem, algorithm; scalar_type = Float64)
            @test precision(BigFloat) == 32
            result
        end
        step!(integrator)
        @test integrator.u[:inverse_square] ≈ 0.25 / 13 rtol = 10eps(Float64)
        @test failure_report(integrator) === nothing
    end
end
