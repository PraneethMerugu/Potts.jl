using Metal

Metal.functional() || error("the selected Metal witness is not functional")

include("../../../test/backend_conformance/g2_descriptor_boundary.jl")

report = run_g2_descriptor_boundary(
    Metal.MtlArray,
    Metal.zeros;
    backend_name = :metal,
)
println(report)
