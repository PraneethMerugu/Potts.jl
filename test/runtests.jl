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
