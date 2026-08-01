using AMDGPU

AMDGPU.functional() || error("the selected AMDGPU witness is not functional")

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")

report = run_g2_descriptor_boundary(
    AMDGPU.ROCArray,
    AMDGPU.zeros;
    backend_name = :amdgpu,
)
println(report)
