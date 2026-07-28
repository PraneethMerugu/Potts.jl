@testset "typed paths" begin
    root = Path()
    mass = path("cells", 1, :mass)
    @test string(mass) == "/cells/[1]/mass"
    @test parentpath(mass) == path("cells", 1)
    @test child(root, "cells", 1) == path("cells", 1)
    @test isprefixpath(path("cells"), mass)
    @test !isprefixpath(path("cell"), mass)
    @test path("1") != path(1)
    @test sort([path(1), path("a"), path("a", 1)]) ==
        [path("a"), path("a", 1), path(1)]
    @test_throws ProcessBigraphError path("")
    @test_throws ProcessBigraphError path(-1)
    @test_throws ProcessBigraphError parentpath(root)
end

@testset "exact normalized time" begin
    scale = common_timescale(1 // 2, 1 // 3, 5 // 6; unit=:minute)
    @test scale == TimeScale(1, 6, :minute)
    @test ticks(5 // 6, scale) == 5
    @test physical_value(Duration(5, scale)) == 5 // 6
    @test logical_time(1 // 2, scale) == LogicalTime(3, scale)
    @test LogicalTime(2, scale) + Duration(3, scale) == LogicalTime(5, scale)
    @test LogicalTime(5, scale) - LogicalTime(2, scale) == Duration(3, scale)
    @test convert_scale(LogicalTime(3, scale), TimeScale(1, 2, :minute)) ==
        LogicalTime(1, TimeScale(1, 2, :minute))
    @test_throws ProcessBigraphError ticks(1 // 4, TimeScale(1, 2))
    @test_throws ProcessBigraphError Duration(-1, scale)
    @test_throws ProcessBigraphError LogicalTime(big(typemax(Int64)) + 1, scale)
    @test_throws ProcessBigraphError LogicalTime(1, scale) <
        LogicalTime(1, TimeScale(1, 6, :second))
end

@testset "canonical encoding" begin
    left = Dict("b" => 2, "a" => 1)
    right = Dict("a" => 1, "b" => 2)
    @test canonical_bytes(left) == canonical_bytes(right)
    @test canonical_fingerprint(left) == canonical_fingerprint(right)
    @test canonical_fingerprint(path("1")) != canonical_fingerprint(path(1))
    @test canonical_fingerprint(-0.0) != canonical_fingerprint(0.0)
    @test canonical_fingerprint(1 // 2) != canonical_fingerprint(2 // 3)
    @test_throws ProcessBigraphError canonical_bytes(identity)
end

@testset "canonical numeric array specialization parity" begin
    function elementwise_array_bytes(values)
        io = IOBuffer()
        write(io, 'A')
        ProcessBigraphs._canonical(io, string(eltype(values)))
        ProcessBigraphs._canonical(io, size(values))
        for value in values
            ProcessBigraphs._canonical(io, value)
        end
        take!(io)
    end

    for values in (
        UInt8[0, 1, typemax(UInt8)],
        UInt32[0, 17, typemax(UInt32)],
        Int32[typemin(Int32), -1, 0, typemax(Int32)],
        Float32[-0.0, 0.0, 1.25, Inf, NaN],
        Float64[-0.0, 0.0, 1.25, Inf, NaN],
    )
        @test canonical_bytes(values) ==
            elementwise_array_bytes(values)
    end
end
