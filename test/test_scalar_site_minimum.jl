isdefined(@__MODULE__, :_site_minimum_problem) || include("fixtures/site_aggregates.jl")

@testset "bounded scalar site minimum follows its declared source" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        model = _site_minimum_problem()
        integrator = init(model.problem, algorithm; scalar_type = Float32)
        SPI = CorePotts.CompilerSPI
        descriptors = filter(
            item -> item isa SPI.SiteMinimumTracker,
            SPI.tracker_instances(integrator.plan.core_program.tracker_plan),
        )
        @test length(descriptors) == 1
        descriptor = only(descriptors)
        key = SPI.tracker_quantity(descriptor)
        @test descriptor.empty == model.empty
        expected = _independent_owner_minimum(
            Array(integrator.u[:signal]), model.labels, model.empty,
            length(integrator.u.cell_kinds),
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
            changed, model.labels, model.empty, length(integrator.u.cell_kinds),
        )
        @test expected == Float32[3, 5]
        @test Array(SPI.program_tracker_values(integrator.runtime, key)) == expected
        step!(integrator)
        amount = Array(integrator.u[:amount])
        repeated = Array(integrator.u[:repeated])
        @test amount[eachindex(expected)] == expected
        @test repeated[eachindex(expected)] == expected
        @test iszero(amount[end])
        @test iszero(repeated[end])
        @test integrator.u.ownership == model.labels
    end
end

@testset "minimum aggregate executable lowering is bounded" begin
    for empty in (Inf, -Inf, NaN, true)
        @test_throws r"finite scalar literal" init(
            _site_minimum_problem(; empty).problem; scalar_type = Float32,
        )
    end
    for maximum_sites in (-1, true, big(typemax(Int32)) + 1)
        @test_throws r"nonnegative Int32 bound" init(
            _site_minimum_problem(; maximum_sites).problem; scalar_type = Float32,
        )
    end
    @test_throws r"maximum_sites of at least 4" init(
        _site_minimum_problem(; maximum_sites = 3).problem;
        scalar_type = Float32,
    )
    model = _site_minimum_problem()
    @test_throws r"scalar Float32" init(model.problem; scalar_type = Float64)
end
