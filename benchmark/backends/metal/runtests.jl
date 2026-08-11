using Metal
using LocalWorksets
using PottsToolkit
using Test

include("extension_load_order.jl")

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

include("../../../test/localworksets_witnesses/lbm_d2q9.jl")
include("../../../test/localworksets_witnesses/lattice_spring.jl")
include("../../../test/localworksets_witnesses/matrix_free_fem.jl")
include("../../../test/localworksets_witnesses/zbuffer.jl")
include("../../../test/localworksets_witnesses/performance.jl")

lw4b_witness_cache_before = length(Metal.compiler_cache(Metal.device()))
@testset "LocalWorksets cross-domain real-Metal witnesses" begin
    backend = Metal.MetalBackend()
    lbm = run_lw_d2q9_witness(Metal.MtlArray; backend)
    spring_deterministic = run_lw_lattice_spring_witness(
        Metal.MtlArray; backend
    )
    spring_fast = run_lw_lattice_spring_witness(
        Metal.MtlArray; backend, force_mode = :fast
    )
    fem = run_lw_matrix_free_fem_witness(Metal.MtlArray; backend)
    zbuffer = run_lw_zbuffer_witness(Metal.MtlArray; backend)

    @test lbm.launches == 1
    @test spring_deterministic.launches == 2
    @test spring_fast.launches == 3
    @test fem.launches == 2
    @test zbuffer.launches == 2
    @test all(report -> report.waits == 2, (
        lbm, spring_deterministic, spring_fast, fem, zbuffer,
    ))
    @test all(report -> report.invalid_rejected, (
        lbm, spring_deterministic, spring_fast, fem, zbuffer,
    ))
    @test spring_fast.determinism.same_run_replay.guarantee ==
        :not_claimed_for_fast_ports
end
lw4b_witness_cache_after = length(Metal.compiler_cache(Metal.device()))
lw4b_witness_cache_report = (
    before = lw4b_witness_cache_before,
    after = lw4b_witness_cache_after,
    compiled = lw4b_witness_cache_after - lw4b_witness_cache_before,
)
println(lw4b_witness_cache_report)
@test lw4b_witness_cache_after >= lw4b_witness_cache_before

lw4b_d2q9_performance = run_lw4b_d2q9_performance(
    Metal.MtlArray; backend = Metal.MetalBackend()
)
println(lw4b_d2q9_performance)
@test lw4b_d2q9_performance.passed

lw4b_zbuffer_performance = run_lw4b_zbuffer_performance(
    Metal.MtlArray; backend = Metal.MetalBackend()
)
println(lw4b_zbuffer_performance)
@test lw4b_zbuffer_performance.passed

include("native_component_execution.jl")

include("../../../test/backend_conformance/descriptor_boundary.jl")
include("../../../test/backend_conformance/checkerboard_execution.jl")
include("../../../test/backend_conformance/relationship_execution.jl")
include("../../../test/backend_conformance/surface_execution.jl")
include("../../../test/backend_conformance/lifecycle_execution.jl")
include("../../../test/backend_conformance/lifecycle_policy_execution.jl")
include("../../../lib/LocalWorksets/test/backend_conformance.jl")
include("../../../test/backend_conformance/localworksets_execution.jl")

localworksets_report = run_localworksets_execution(
    Metal.MtlArray;
    backend_name = :metal,
    compiler_cache_size = () -> length(
        Metal.compiler_cache(Metal.device())
    ),
)
println(localworksets_report)

localworksets_failure_task = Task() do
    run_localworksets_device_failure(
        Metal.MtlArray;
        backend_name = :metal,
    )
end
schedule(localworksets_failure_task)
localworksets_failure_report = fetch(localworksets_failure_task)
println(localworksets_failure_report)

localworksets_shared_failure_task = Task() do
    run_localworksets_shared_failure_scope(
        Metal.MtlArray;
        backend_name = :metal,
    )
end
schedule(localworksets_shared_failure_task)
localworksets_shared_failure_report = fetch(
    localworksets_shared_failure_task
)
println(localworksets_shared_failure_report)

localworksets_checkerboard_report = run_localworksets_checkerboard_vertical(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(localworksets_checkerboard_report)

localworksets_checkerboard_failure_task = Task() do
    run_localworksets_checkerboard_failures(
        Metal.MtlArray;
        backend_name = :metal,
    )
end
schedule(localworksets_checkerboard_failure_task)
localworksets_checkerboard_failure_report = fetch(
    localworksets_checkerboard_failure_task
)
println(localworksets_checkerboard_failure_report)

report = run_descriptor_boundary(
    Metal.MtlArray,
    Metal.zeros;
    backend_name = :metal,
)
println(report)

@testset "external Metal mechanisms reject without reviewed evidence" begin
    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        run_checkerboard_execution(
            Metal.MtlArray;
            backend_name = :metal,
            kernel_convert = Metal.mtlconvert,
        )
    end
end

checkerboard_boundary_report = run_checkerboard_boundary_sizes(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(checkerboard_boundary_report)

@testset "external relationship mechanism rejects without reviewed evidence" begin
    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        run_relationship_execution(
            Metal.MtlArray;
            backend_name = :metal,
            kernel_convert = Metal.mtlconvert,
        )
    end
end

@testset "external surface operation rejects without reviewed evidence" begin
    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        run_surface_execution(
            Metal.MtlArray;
            backend_name = :metal,
            kernel_convert = Metal.mtlconvert,
        )
    end
end

lifecycle_report = run_lifecycle_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(lifecycle_report)

lifecycle_mcs_report = run_lifecycle_mcs_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(lifecycle_mcs_report)

lifecycle_capacity_report = run_lifecycle_capacity_failure(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(lifecycle_capacity_report)

canonical_state_failure_report = run_lifecycle_canonical_state_failure(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(canonical_state_failure_report)

public_lifecycle_report = run_public_device_lifecycle_execution(
    PottsToolkit.MetalBackend()
)
println(public_lifecycle_report)

state_policy_report = run_lifecycle_state_policy_execution(
    Metal.MtlArray; backend_name = :metal
)
println(state_policy_report)

planned_tracker_report = run_lifecycle_planned_tracker_execution(
    Metal.MtlArray; backend_name = :metal
)
println(planned_tracker_report)

partition_policy_report = run_lifecycle_partition_policy_execution(
    Metal.MtlArray; backend_name = :metal
)
println(partition_policy_report)

relationship_policy_report = run_lifecycle_relationship_policy_execution(
    Metal.MtlArray; backend_name = :metal
)
println(relationship_policy_report)

retirement_report = run_lifecycle_retirement_execution(
    Metal.MtlArray; backend_name = :metal
)
println(retirement_report)

forbid_extinction_report = run_forbid_extinction_execution(
    Metal.MtlArray; backend_name = :metal
)
println(forbid_extinction_report)

@testset "external lifecycle mechanism rejects without reviewed evidence" begin
    @test_throws CorePotts.BackendSPI.ProgramCapabilityError begin
        run_external_lifecycle_operation_execution(
            Metal.MtlArray; backend_name = :metal
        )
    end
end

resolution_policy_report = run_lifecycle_resolution_policy_execution(
    Metal.MtlArray; backend_name = :metal
)
println(resolution_policy_report)

include("lw3_localworksets_parity.jl")
