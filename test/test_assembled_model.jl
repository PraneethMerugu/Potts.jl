include(joinpath(@__DIR__, "..", "examples", "compartment_exchange.jl"))

@testset "assembled factory executes simultaneous conservative exchange" begin
    @test_throws ArgumentError CompartmentExchangeExample.exchange_problem(; fraction_value = -0.1)
    @test_throws ArgumentError CompartmentExchangeExample.exchange_problem(; fraction_value = 1.1)
    problem = CompartmentExchangeExample.exchange_problem()
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        # Independent values of the discrete geometric depletion law.
        for expected in ((6.0f0, 2.0f0), (4.5f0, 3.5f0), (3.375f0, 4.625f0))
            step!(integrator)
            @test (integrator.u[:stored], integrator.u[:released]) == expected
            @test integrator.u[:stored] + integrator.u[:released] == 8.0f0
            @test failure_report(integrator) === nothing
        end
    end
end
