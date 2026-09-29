using Metal
include(joinpath(@__DIR__, "..", "fixtures", "reduction_control_contracts.jl"))
Metal.functional() || error("reduction control tests require functional Metal")
Metal.allowscalar(false)
reduction_control_contracts(Metal.MtlArray)
reduction_control_producer_totality(Metal.MtlArray)
reduction_control_filtered_producers(Metal.MtlArray)
reduction_control_atomic_prefix(Metal.MtlArray)
