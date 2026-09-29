using Test
import Metal
include("../fixtures/collect_canonical_order_contracts.jl")

Metal.functional() || error("canonical collection checks require real Metal")
Metal.allowscalar(false)
_collect_canonical_order_contract(Metal.MetalBackend())
