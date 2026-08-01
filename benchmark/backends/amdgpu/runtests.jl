using AMDGPU

AMDGPU.functional() || error("the selected AMDGPU witness is not functional")

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")
include("../../../test/backend_conformance/g4_checkerboard_execution.jl")

report = run_g2_descriptor_boundary(
    AMDGPU.ROCArray,
    AMDGPU.zeros;
    backend_name = :amdgpu,
)
println(report)

checkerboard_report = run_g4_checkerboard_execution(
    AMDGPU.ROCArray;
    backend_name = :amdgpu,
)
println(checkerboard_report)
