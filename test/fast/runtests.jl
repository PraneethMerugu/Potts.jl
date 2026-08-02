include("../setup.jl")
include("../backend_conformance/g2_descriptor_boundary.jl")
include("../backend_conformance/g4_checkerboard_execution.jl")
include("../backend_conformance/g5_relationship_execution.jl")
include("../backend_conformance/g5_surface_execution.jl")

@testset "Symbolic Potts V1 fast compiler/runtime boundary" begin
    @testset "registered external descriptor boundary" begin
        report = run_g2_descriptor_boundary(
            Array,
            zeros;
            backend_name = :cpu,
            descriptor_count = 1,
        )
        @test report.backend === :cpu
    end
    @testset "checkerboard CPU boundary conformance" begin
        report = run_g4_checkerboard_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test report.backend === :cpu
        boundary_report = run_g4_checkerboard_boundary_sizes(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test boundary_report.backend === :cpu
    end
    @testset "relationship CPU boundary conformance" begin
        report = run_g5_relationship_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test report.backend === :cpu
    end
    @testset "surface CPU boundary conformance" begin
        report = run_g5_surface_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test report.backend === :cpu
    end
    include("../test_g2_r1_repairs.jl")
    include("../test_checkpoint.jl")
end
