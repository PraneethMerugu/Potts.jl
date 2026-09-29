using Test
import Metal
import LocalMath
include("../fixtures/keyed_reduce_contracts.jl")

Metal.functional() || error("keyed reduction checks require real Metal")
Metal.allowscalar(false)
keyed_reduce_contract(Metal.MetalBackend())
mixed_keyed_stage_sequence_contract(Metal.MetalBackend())
