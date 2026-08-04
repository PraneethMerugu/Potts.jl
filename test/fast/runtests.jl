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
        public_failure = run_public_lifecycle_capacity_failure()
        @test public_failure.committed_mcs == 0
        @test public_failure.failure_mcs == 1
        @test public_failure.settlements == 1
        sequential_failure = run_public_lifecycle_capacity_failure(
            engine = SequentialEngine()
        )
        @test sequential_failure.committed_mcs == 0
        @test sequential_failure.failure_mcs == 1
        schedule = run_public_lifecycle_settlement_schedule()
        @test schedule == (final_only = 1, saveat = 4, public_steps = 4)
        late_failure = run_public_lifecycle_late_capacity_failure()
        @test late_failure == (
            submitted_mcs = 100,
            committed_mcs = 36,
            failure_mcs = 37,
            settlements = 1,
        )
        consumers = run_public_settlement_consumers()
        @test consumers == (checkpoint = 1, index_read = 1, statistics = 1)
        @test run_lifecycle_enqueue_allocation() <= 128 * 1024
        canonical_failure = run_lifecycle_canonical_state_failure(
            Array;
            backend_name = :cpu,
            to_host = identity,
            require_isbits = false,
        )
        @test canonical_failure.permutations == 2
        @test canonical_failure.selected == (2, 2)
    end
    include("../test_compiler_boundary_repairs.jl")
    include("../test_lifecycle_compiler.jl")
    include("../test_checkpoint.jl")
end
