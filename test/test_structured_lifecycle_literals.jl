using StaticArrays

@testset "structured retirement literals retain declared precision and units" begin
    @variables position[1:2]
    @variables status::NamedTuple{(:enabled, :count, :level), Tuple{Bool, Int32, Float64}}
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    anchor = CellBinding(:retiring)
    source = PottsSystem(
        name = :structured_retirement, statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                CellState(
                    position; initial = SVector(2.0u"m", 4.0u"m"),
                    retirement = RetireTo(SVector(600.0u"cm", 800.0u"cm"))
                ),
                CellState(
                    status; initial = (enabled = true, count = Int32(2), level = 1.0),
                    retirement = RetireTo((enabled = false, count = Int32(7), level = 2.5))
                ),
                ProposalConstraint(:fixed_ownership, false),
                LifecycleProcess(
                    :remove; domain = cells(cell), anchor, expression = true,
                    effects = (
                        RemoveCell(
                            anchor; replacement = medium,
                            on_inadmissible = ErrorOnInadmissible()
                        ),
                    ), cadence = AtMCS(1)
                ),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (position, status)
    )
    system = mtkcompile(complete(source; reference_units = ReferenceUnits(length = 2.0u"m")))
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    problem = PottsProblem(system, initial, (0, 1); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        result = solve(problem, algorithm; scalar_type = Float32)
        @test result.retcode == SciMLBase.ReturnCode.Success
        @test only(result.u[end][:position]) === SVector(3.0f0, 4.0f0)
        @test only(result.u[end][:status]) === (enabled = false, count = Int32(7), level = 2.5f0)
        @test all(owner -> owner <= 0, result.u[end].ownership)
    end
end

@testset "state-policy literals reject invalid structure and dimensions" begin
    reference = Potts._reference_descriptor(:length, 2.0u"m")
    manifest = Potts.ParameterManifest((), (), (reference,))
    state = (initial = SVector(0.0f0, 0.0f0), unit = reference)
    for value in (
            SVector(1.0u"m", 2.0u"m", 3.0u"m"),
            SVector(1.0u"s", 2.0u"s"), SVector(1.0, 2.0),
            SVector(NaN * u"m", 2.0u"m"), [1.0u"m", 2.0u"m"],
            MVector(1.0u"m", 2.0u"m"),
        )
        @test_throws ArgumentError Potts._static_literal(value, manifest, Float32; state)
    end
    product_state = (
        initial = (flag = true, values = SVector(0.0f0, 0.0f0)),
        unit = (flag = nothing, values = nothing),
    )
    @test_throws ArgumentError Potts._static_literal(
        (flag = true, values = MVector(1.0, 2.0)), manifest, Float32; state = product_state
    )
    @test_throws ArgumentError Potts._static_literal(
        (values = SVector(1.0, 2.0), flag = true), manifest, Float32; state = product_state
    )
end
