using Metal
using PottsToolkit
using Test

include("extension_load_order.jl")

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

include("native_component_execution.jl")

include("../../../test/backend_conformance/descriptor_boundary.jl")
include("../../../test/backend_conformance/checkerboard_execution.jl")
include("../../../test/backend_conformance/relationship_execution.jl")
include("../../../test/backend_conformance/surface_execution.jl")
include("../../../test/backend_conformance/lifecycle_execution.jl")
include("../../../test/backend_conformance/lifecycle_policy_execution.jl")

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
