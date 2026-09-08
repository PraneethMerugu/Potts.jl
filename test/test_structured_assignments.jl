include(joinpath(@__DIR__, "fixtures", "vector_rotation.jl"))

@testset "authored vector rotation retains one logical state" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        _vector_rotation_contract(algorithm, Potts.CPUBackend())
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
