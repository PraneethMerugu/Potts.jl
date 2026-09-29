using Metal
include(joinpath(@__DIR__, "..", "fixtures", "ordered_fold_control_contracts.jl"))
include(joinpath(@__DIR__, "..", "fixtures", "ordered_fold_source_order_contracts.jl"))
Metal.functional() || error("ordered-fold control tests require functional Metal")
Metal.allowscalar(false)
ordered_fold_control_contracts(Metal.MtlArray)
ordered_fold_source_order_contracts(Metal.MtlArray)
