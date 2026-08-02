using AMDGPU

AMDGPU.functional() || error("the selected AMDGPU witness is not functional")
AMDGPU.allowscalar(false)

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")
include("../../../test/backend_conformance/g4_checkerboard_execution.jl")
include("../../../test/backend_conformance/g5_relationship_execution.jl")
include("../../../test/backend_conformance/g5_surface_execution.jl")

report = run_g2_descriptor_boundary(
    AMDGPU.ROCArray,
    AMDGPU.zeros;
    backend_name = :amdgpu,
)
println(report)

checkerboard_report = run_g4_checkerboard_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(checkerboard_report)

checkerboard_boundary_report = run_g4_checkerboard_boundary_sizes(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(checkerboard_boundary_report)

relationship_report = run_g5_relationship_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(relationship_report)

surface_report = run_g5_surface_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(surface_report)
