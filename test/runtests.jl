include("setup.jl")
include("backend_conformance/lifecycle_execution.jl")

using Aqua
using ExplicitImports

@testset "Symbolic Potts V1" begin
    include("test_system_contract.jl")
    include("test_statements_and_traversal.jl")
    include("test_completion_and_diagnostics.jl")
    include("test_host_compiler_facts.jl")
    include("test_descriptor_compiler.jl")
    include("test_compiler_boundary_repairs.jl")
    include("test_architecture_freeze.jl")
    include("test_sequential_reference.jl")
    include("test_relationship_runtime.jl")
    include("test_surface_tracker.jl")
    include("test_lifecycle_compiler.jl")
    include("test_lifecycle_sequential.jl")
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
    end
    include("test_units_and_parameters.jl")
    include("test_compilation_and_inspection.jl")
    include("test_initial_problem_remake.jl")
    include("test_runtime_solution_sii.jl")
    include("test_checkpoint.jl")
    include("test_wortel_fixture.jl")
    include("test_merks_fixture.jl")
    include("test_focal_fixture.jl")
    include("test_package_quality.jl")
end
