using AMDGPU

AMDGPU.functional() || error("the selected AMDGPU witness is not functional")
AMDGPU.allowscalar(false)

include("../../../lib/CorePotts/test/backend_conformance/descriptor_boundary.jl")
include("../../../lib/CorePotts/test/backend_conformance/checkerboard_execution.jl")
include("../../../lib/CorePotts/test/backend_conformance/relationship_execution.jl")
include("../../../lib/CorePotts/test/backend_conformance/surface_execution.jl")

report = run_descriptor_boundary(
    AMDGPU.ROCArray,
    AMDGPU.zeros;
    backend_name = :amdgpu,
)
println(report)

checkerboard_report = run_checkerboard_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(checkerboard_report)

checkerboard_boundary_report = run_checkerboard_boundary_sizes(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(checkerboard_boundary_report)

relationship_report = run_relationship_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(relationship_report)

surface_report = run_surface_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
    kernel_convert = AMDGPU.rocconvert,
)
println(surface_report)
