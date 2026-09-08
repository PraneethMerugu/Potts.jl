using StaticArrays

@testset "fixed state arrays use ordinary reference inference and ambiguity rules" begin
    @variables position[1:2]
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    function reference_problem(value; references = nothing)
        source = PottsSystem(
            name = :reference_position,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    ModelState(position; initial = value),
                    ProposalConstraint(:fixed_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (position,),
        )
        completed = references === nothing ? complete(source) : complete(source; reference_units = references)
        return PottsProblem(mtkcompile(completed), initial, (0, 1); seed = 17)
    end
    inferred = reference_problem(SVector(2.0u"m", -2.0u"m"))
    @test init(inferred; scalar_type = Float32).u[:position] == SVector(1.0f0, -1.0f0)
    @test_throws r"ambiguous declared reference scale" reference_problem(SVector(1.0u"m", 2.0u"m"))
    @test_throws r"finite nonzero scale" reference_problem(SVector(0.0u"m", 0.0u"m"))
    explicit = reference_problem(SVector(1.0u"m", 2.0u"m"); references = ReferenceUnits(length = 1.0u"m"))
    @test init(explicit; scalar_type = Float32).u[:position] == SVector(1.0f0, 2.0f0)
    for value in (SVector(1.0u"m", 1.0u"s"), SVector{2, Any}(1.0u"m", 1.0))
        mixed = reference_problem(value; references = ReferenceUnits(length = 1.0u"m", time = 1.0u"s"))
        @test_throws r"one compatible reference dimension" init(mixed)
    end
end
