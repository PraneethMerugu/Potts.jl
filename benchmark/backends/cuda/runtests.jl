using CUDA

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")

CUDA.functional() || error("the selected CUDA witness is not functional")

report = run_g2_descriptor_boundary(
    CUDA.CuArray,
    CUDA.zeros;
    backend_name = :cuda,
)
println(report)
