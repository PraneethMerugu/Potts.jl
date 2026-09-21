isdefined(@__MODULE__, :_site_aggregate_problem) || include("fixtures/site_aggregates.jl")

@testset "scheduled source changes preserve simultaneous aggregate entry reads" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_aggregate_problem(; evolve = true)
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        original = Array(integrator.u[:signal])
        for boundary in 1:3
            expected = _independent_owner_sum(original .+ Float32(boundary - 1), model.labels, 1.0f0)
            step!(integrator)
            @test Array(integrator.u[:amount]) == expected
            @test Array(integrator.u[:repeated]) == expected
            @test Array(integrator.u[:signal]) == original .+ Float32(boundary)
            @test integrator.u.ownership == model.labels
        end
    end
end
