include("fixtures/cell_processes.jl")

@testset "structured retirement literals retain declared precision and units" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        _structured_retirement_contract(algorithm, CPUBackend())
    end
end

@testset "state-policy literals reject invalid structure and dimensions" begin
    reference = Potts._reference_descriptor(:length, 2.0u"m")
    manifest = Potts.ParameterManifest(Potts.RuntimeParameter[], NamedTuple[], (reference,))
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
