using CUDA

CUDA.functional() || error("the selected CUDA witness is not functional")
CUDA.allowscalar(false)

include("../../../integration/backend_conformance/descriptor_boundary.jl")
include("../../../integration/backend_conformance/checkerboard_execution.jl")
include("../../../integration/backend_conformance/relationship_execution.jl")
include("../../../integration/backend_conformance/surface_execution.jl")

report = run_descriptor_boundary(
    CUDA.CuArray,
    CUDA.zeros;
    backend_name = :cuda,
)
println(report)

checkerboard_report = run_checkerboard_execution(
    CUDA.CuArray;
    backend_name = :cuda,
    kernel_convert = CUDA.cudaconvert,
)
println(checkerboard_report)

checkerboard_boundary_report = run_checkerboard_boundary_sizes(
    CUDA.CuArray;
    backend_name = :cuda,
    kernel_convert = CUDA.cudaconvert,
)
println(checkerboard_boundary_report)

relationship_report = run_relationship_execution(
    CUDA.CuArray;
    backend_name = :cuda,
    kernel_convert = CUDA.cudaconvert,
)
println(relationship_report)

surface_report = run_surface_execution(
    CUDA.CuArray;
    backend_name = :cuda,
    kernel_convert = CUDA.cudaconvert,
)
println(surface_report)
