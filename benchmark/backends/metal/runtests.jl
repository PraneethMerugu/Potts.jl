using Metal

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

include("../../../test/backend_conformance/descriptor_boundary.jl")
include("../../../test/backend_conformance/checkerboard_execution.jl")
include("../../../test/backend_conformance/relationship_execution.jl")
include("../../../test/backend_conformance/surface_execution.jl")
include("../../../test/backend_conformance/lifecycle_execution.jl")

report = run_descriptor_boundary(
    Metal.MtlArray,
    Metal.zeros;
    backend_name = :metal,
)
println(report)

checkerboard_report = run_checkerboard_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(checkerboard_report)

checkerboard_boundary_report = run_checkerboard_boundary_sizes(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(checkerboard_boundary_report)

relationship_report = run_relationship_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(relationship_report)

surface_report = run_surface_execution(
    Metal.MtlArray;
    backend_name = :metal,
    kernel_convert = Metal.mtlconvert,
)
println(surface_report)

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
