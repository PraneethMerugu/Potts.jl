using Statistics

const LMBR = LocalMath

@testset "bounded reductions match ordinary Julia values and types" begin
    for T in (
            Bool,
            Int8, Int16, Int32, Int64,
            UInt8, UInt16, UInt32, UInt64,
            Float16, Float32, Float64,
        )
        data = T === Bool ? Bool[true, false, true] : T[T(1), T(1), T(2)]
        view = LMBR._bounded_group_view(data, Int32(1), Int32(3), Val(3))
        @test sum(view) == sum(data)
        @test typeof(sum(view)) === typeof(sum(data))
        @test minimum(view) == minimum(data)
        @test typeof(minimum(view)) === typeof(minimum(data))
        @test maximum(view) == maximum(data)
        @test typeof(maximum(view)) === typeof(maximum(data))
        @test mean(view) == mean(data)
        @test typeof(mean(view)) === typeof(mean(data))

        empty_view = LMBR._bounded_group_view(
            T[], Int32(1), Int32(0), Val(3))
        @test sum(empty_view) == sum(T[])
        @test typeof(sum(empty_view)) === typeof(sum(T[]))
        @test isnan(mean(empty_view))
        @test typeof(mean(empty_view)) === typeof(mean(T[]))
    end

    floating = Float32[1, 4, 16]
    floating_view = LMBR._bounded_group_view(
        floating, Int32(1), Int32(3), Val(3))
    geometric = LMBR.geometric_mean(floating_view)
    @test geometric ≈ 4.0f0
    @test geometric isa Float32

    exceptional = Float32[NaN, Inf, -0.0f0, 0.0f0]
    exceptional_view = LMBR._bounded_group_view(
        exceptional, Int32(1), Int32(4), Val(4))
    @test isnan(sum(exceptional_view))
    @test isnan(minimum(exceptional_view))
    @test isnan(maximum(exceptional_view))
end

@testset "authored bounded reductions use transaction validation" begin
    source = LMBR.Space(1)
    values_space = LMBR.Space(3)
    values = LMBR.Field(values_space, Float32)
    totals = LMBR.Field(source, Float32)
    minima = LMBR.Field(source, Float32)
    maxima = LMBR.Field(source, Float32)
    averages = LMBR.Field(source, Float32)
    neighbors = LMBR.FixedRelation(source => values_space; degree = 3)
    sum_law = LMBR.@localmath item ∈ source begin
        gathered = values[neighbors(item)]
        totals[item] = sum(gathered)
    end
    minimum_law = LMBR.@localmath item ∈ source begin
        gathered = values[neighbors(item)]
        minima[item] = minimum(gathered)
    end
    maximum_law = LMBR.@localmath item ∈ source begin
        gathered = values[neighbors(item)]
        maxima[item] = maximum(gathered)
    end
    mean_law = LMBR.@localmath item ∈ source begin
        gathered = values[neighbors(item)]
        averages[item] = Statistics.mean(gathered)
    end
    law = LMBR.sequence(sum_law, minimum_law, maximum_law, mean_law)
    prepared = LMBR.prepare(
        law,
        values => Float32[1, 2, 3],
        totals => zeros(Float32, 1),
        minima => zeros(Float32, 1),
        maxima => zeros(Float32, 1),
        averages => zeros(Float32, 1),
        neighbors => reshape(Int32[1, 2, 3], 3, 1);
        backend = KernelAbstractions.CPU(),
    )
    wait(LMBR.execute!(prepared))
    @test LMBR.storage(prepared, totals) == Float32[6]
    @test LMBR.storage(prepared, minima) == Float32[1]
    @test LMBR.storage(prepared, maxima) == Float32[3]
    @test LMBR.storage(prepared, averages) == Float32[2]

    keys = LMBR.Field(source, Int32)
    optional = LMBR.IndexRelation(keys => values_space; optional = true)
    rejected_output = LMBR.Field(source, Float32)
    rejected_law = LMBR.@localmath item ∈ source begin
        gathered = samples(values[optional(item)])
        rejected_output[item] = minimum(gathered)
    end
    rejected = LMBR.prepare(
        rejected_law,
        keys => Int32[0],
        values => Float32[1, 2, 3],
        rejected_output => Float32[-1];
        backend = KernelAbstractions.CPU(),
    )
    @test_throws LMBR.LocalMathValidationError wait(LMBR.execute!(rejected))
    @test LMBR.storage(rejected, rejected_output) == Float32[-1]

    floating = LMBR.Field(values_space, Float32)
    geometric_output = LMBR.Field(source, Float32)
    geometric_law = LMBR.@localmath item ∈ source begin
        gathered = floating[neighbors(item)]
        geometric_output[item] = LMBR.geometric_mean(gathered)
    end
    geometric_rejected = LMBR.prepare(
        geometric_law,
        floating => Float32[1, 0, 4],
        geometric_output => Float32[-1],
        neighbors => reshape(Int32[1, 2, 3], 3, 1);
        backend = KernelAbstractions.CPU(),
    )
    @test_throws LMBR.LocalMathValidationError wait(
        LMBR.execute!(geometric_rejected))
    @test LMBR.storage(geometric_rejected, geometric_output) == Float32[-1]
end
