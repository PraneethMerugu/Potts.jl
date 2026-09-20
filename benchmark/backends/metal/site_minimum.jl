using Test
using Potts
using SciMLBase
import CorePotts
import Metal

include(joinpath(
    @__DIR__, "..", "..", "..", "test", "fixtures", "site_aggregates.jl",
))

@testset "bounded site minimum authoring executes on CPU and Metal" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)
    model = _site_minimum_problem()
    active_owners = Int(maximum(model.labels))
    for backend in (Potts.CPUBackend(), Potts.MetalBackend())
        @testset "$(nameof(typeof(backend)))" begin
            integrator = init(
                model.problem, CheckerboardSweepCPM(); backend, scalar_type = Float32,
            )
            SPI = CorePotts.CompilerSPI
            descriptor = only(filter(
                item -> item isa SPI.SiteMinimumTracker,
                SPI.tracker_instances(integrator.plan.core_program.tracker_plan),
            ))
            key = SPI.tracker_quantity(descriptor)
            @test descriptor.empty == model.empty

            expected = _independent_owner_minimum(
                Array(integrator.u[:signal]), model.labels, model.empty,
                active_owners,
            )
            @test Array(SPI.program_tracker_values(integrator.runtime, key)) == expected
            step!(integrator)
            amount = Array(integrator.u[:amount])
            repeated = Array(integrator.u[:repeated])
            @test amount[eachindex(expected)] == expected
            @test repeated[eachindex(expected)] == expected
            @test iszero(amount[end])
            @test iszero(repeated[end])

            changed = Float32[8 5; 3 4]
            setu(integrator, model.signal)(integrator, changed)
            expected = _independent_owner_minimum(
                changed, model.labels, model.empty, active_owners,
            )
            @test Array(SPI.program_tracker_values(integrator.runtime, key)) == expected
            step!(integrator)
            amount = Array(integrator.u[:amount])
            repeated = Array(integrator.u[:repeated])
            @test amount[eachindex(expected)] == expected
            @test repeated[eachindex(expected)] == expected
            @test iszero(amount[end])
            @test iszero(repeated[end])
            @test Array(integrator.u.ownership) == model.labels
        end
    end
end
