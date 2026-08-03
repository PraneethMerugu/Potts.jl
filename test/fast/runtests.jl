include("../setup.jl")
include("../backend_conformance/descriptor_boundary.jl")
include("../backend_conformance/checkerboard_execution.jl")
include("../backend_conformance/relationship_execution.jl")
include("../backend_conformance/surface_execution.jl")
include("../backend_conformance/lifecycle_execution.jl")

@testset "Symbolic Potts V1 fast compiler/runtime boundary" begin
    @testset "registered external descriptor boundary" begin
        report = run_descriptor_boundary(
            Array,
            zeros;
            backend_name = :cpu,
            descriptor_count = 1,
        )
        @test report.backend === :cpu
    end
    @testset "checkerboard CPU boundary conformance" begin
        report = run_checkerboard_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test report.backend === :cpu
        boundary_report = run_checkerboard_boundary_sizes(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test boundary_report.backend === :cpu
    end
    @testset "relationship CPU boundary conformance" begin
        report = run_relationship_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test report.backend === :cpu
    end
    @testset "surface CPU boundary conformance" begin
        report = run_surface_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_device_isbits = false,
        )
        @test report.backend === :cpu
    end
    @testset "asynchronous lifecycle settlement" begin
        success = run_lifecycle_mcs_execution(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_isbits = false,
        )
        @test success.committed_mcs == 2
        @test success.settlements == 1
        failure = run_lifecycle_capacity_failure(
            Array;
            backend_name = :cpu,
            kernel_convert = identity,
            to_host = identity,
            require_isbits = false,
        )
        @test failure.failure_mcs == 1
        @test failure.committed_mcs == 0
        @test failure.settlements == 1
    end
    include("../test_compiler_boundary_repairs.jl")
    include("../test_lifecycle_compiler.jl")
    include("../test_checkpoint.jl")
end
