isdefined(@__MODULE__, :_site_aggregate_problem) || include("fixtures/site_aggregates.jl")

_site_aggregate_maintenance_contract(; logical_shape = (2, 2))

@testset "tensor aggregate values retain component shape and physical units" begin
    references = ReferenceUnits(length = 2.0u"m", time = 1.0u"s")
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_aggregate_problem(;
            logical_shape = (2, 2), unit = 2.0u"m",
            reference_units = references, atol = 0.25u"m"
        )
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        expected = SMatrix{2, 2, Float32, 4}[
            SMatrix{2, 2}(3, -3, 6, 9), SMatrix{2, 2}(3, -3, 6, 9),
            zero(SMatrix{2, 2, Float32}),
        ]
        step!(integrator)
        @test integrator.u[:amount] == expected
        @test integrator.u[:repeated] == expected
        @test eltype(integrator.u[:amount]) === SMatrix{2, 2, Float32, 4}
        replacement = fill(SMatrix{2, 2}(4.0u"m", -2.0u"m", 6.0u"m", 10.0u"m"), 2, 2)
        setu(integrator, (model.signal, model.gain))(integrator, (replacement, 3.0))
        before_checkpoint = checkpoint(integrator)
        before = integrator.u
        detached = (;
            signal = copy(Array(before[:signal])), amount = copy(Array(before[:amount])),
            repeated = copy(Array(before[:repeated])), ownership = copy(before.ownership),
            gain = getp(integrator, model.gain)(integrator), mcs = integrator.t,
        )
        for invalid in (
                fill(SVector(1.0u"m", 2.0u"m"), 2, 2),
                fill(map(value -> value * u"s", zero(SMatrix{2, 2, Float64})), 2, 2),
            )
            @test_throws ArgumentError setu(integrator, model.signal)(integrator, invalid)
            @test integrator.u === before
            @test integrator.u[:signal] == detached.signal
            @test integrator.u[:amount] == detached.amount
            @test integrator.u[:repeated] == detached.repeated
            @test integrator.u.ownership == detached.ownership
            @test getp(integrator, model.gain)(integrator) == detached.gain
            @test integrator.t == detached.mcs
            @test checkpoint(integrator).checksum == before_checkpoint.checksum
        end
        restored = init(model.problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        expected = SMatrix{2, 2, Float32, 4}[
            SMatrix{2, 2}(12, -6, 18, 30), SMatrix{2, 2}(6, -3, 9, 15),
            zero(SMatrix{2, 2, Float32}),
        ]
        step!(integrator)
        step!(restored)
        @test integrator.u[:amount] == restored.u[:amount] == expected
        @test integrator.u[:repeated] == restored.u[:repeated] == expected
        @test restored.t == integrator.t == 2
    end
end
