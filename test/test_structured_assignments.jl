include(joinpath(@__DIR__, "fixtures", "vector_rotation.jl"))

@testset "authored vector rotation retains one logical state" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        _vector_rotation_contract(algorithm, Potts.CPUBackend())
    end
end

@testset "compound scalar and vector assignments share entry values" begin
    @variables amount pair[1:2]
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    function source(vector_value)
        return PottsSystem(
            name = :compound_scalar_vector,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    ModelState(amount; initial = 3.0),
                    ModelState(pair; initial = SVector(1.0, 2.0)),
                    ProposalConstraint(:fixed_ownership, false),
                    Synchronous(
                        :exchange,
                        Assign(amount, pair[1]),
                        Assign(pair, vector_value)
                    ),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (amount, pair),
        )
    end
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
    )
    problem = PottsProblem(source(SVector(amount, 0.0)), initial, (0, 2); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        # Exchange the old scalar and first vector component; reset the second.
        for (expected_amount, expected_pair) in (
                (1.0f0, SVector(3.0f0, 0.0f0)), (3.0f0, SVector(1.0f0, 0.0f0)),
            )
            step!(integrator)
            @test integrator.u[:amount] === expected_amount
            @test integrator.u[:pair] == expected_pair
        end
        mismatched = PottsProblem(source(SVector(amount, 0.0, 0.0)), initial, (0, 1))
        @test_throws r"logical value shape" init(mismatched, algorithm; scalar_type = Float32)
    end
end

@testset "authored assignments reject mismatched logical vector shapes" begin
    @variables polarity[1:2]
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    mismatched = PottsSystem(
        name = :mismatched_vector,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(polarity; initial = SVector(1.0, 0.0)),
                Synchronous(:replace, Assign(polarity, SVector(1.0, 2.0, 3.0))),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = (polarity,),
    )
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    @test_throws r"logical value shape" init(PottsProblem(mismatched, initial, (0, 1)))
end
