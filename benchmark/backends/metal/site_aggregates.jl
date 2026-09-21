using Test
using Potts
using SciMLBase
using StaticArrays
import Metal

include(joinpath(
    @__DIR__, "..", "..", "..", "test", "fixtures", "site_aggregates.jl",
))

function _independent_evolved_site_source(values, logical_shape)
    return map(values) do value
        isempty(logical_shape) && return value + 1.0f0
        logical_shape == (2,) && return value + SVector(1.0f0, 2.0f0)
        return 2.0f0 * value
    end
end

@testset "authored site sums execute for scalar and structured evolving sources" begin
    Metal.functional() || error("the selected Metal witness is not functional")
    Metal.allowscalar(false)

    for logical_shape in ((), (2,), (2, 2))
        @testset "logical shape $logical_shape" begin
            for backend in (Potts.CPUBackend(), Potts.MetalBackend())
                @testset "$(nameof(typeof(backend)))" begin
                    model = _site_aggregate_problem(; logical_shape, evolve = true)
                    integrator = init(
                        model.problem, CheckerboardSweepCPM();
                        backend, scalar_type = Float32,
                    )

                    for _ in 1:2
                        source = Array(integrator.u[:signal])
                        expected = _independent_owner_sum(source, model.labels, 1.0f0)
                        expected_source =
                            _independent_evolved_site_source(source, logical_shape)

                        step!(integrator)

                        @test Array(integrator.u[:amount]) == expected
                        @test Array(integrator.u[:repeated]) == expected
                        @test Array(integrator.u[:signal]) == expected_source
                        @test Array(integrator.u.ownership) == model.labels
                    end
                end
            end
        end
    end
end
