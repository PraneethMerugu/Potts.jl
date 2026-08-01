using CUDA

CUDA.functional() || error("the selected CUDA witness is not functional")

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")
include("../../../test/backend_conformance/g4_checkerboard_execution.jl")

report = run_g2_descriptor_boundary(
    CUDA.CuArray,
    CUDA.zeros;
    backend_name = :cuda,
)
println(report)

checkerboard_report = run_g4_checkerboard_execution(
    CUDA.CuArray;
    backend_name = :cuda,
)
println(checkerboard_report)
