using Metal

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")
include("../../../test/backend_conformance/g4_checkerboard_execution.jl")
include("../../../test/backend_conformance/g5_relationship_execution.jl")
include("../../../test/backend_conformance/g5_surface_execution.jl")

report = run_g2_descriptor_boundary(
    Metal.MtlArray,
    Metal.zeros;
    backend_name = :metal,
)
println(report)

checkerboard_report = run_g4_checkerboard_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(checkerboard_report)

checkerboard_boundary_report = run_g4_checkerboard_boundary_sizes(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(checkerboard_boundary_report)

relationship_report = run_g5_relationship_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(relationship_report)

surface_report = run_g5_surface_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(surface_report)
