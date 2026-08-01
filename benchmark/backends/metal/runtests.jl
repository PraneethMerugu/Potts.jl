using Metal

Metal.functional() || error("the selected Metal witness is not functional")

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")
include("../../../test/backend_conformance/g4_checkerboard_execution.jl")

report = run_g2_descriptor_boundary(
    Metal.MtlArray,
    Metal.zeros;
    backend_name = :metal,
)
println(report)

checkerboard_report = run_g4_checkerboard_execution(
    Metal.MtlArray;
    backend_name = :metal,
)
println(checkerboard_report)
