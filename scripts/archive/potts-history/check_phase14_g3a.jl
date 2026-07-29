using Test
using CorePotts
using PottsToolkit

repository = normpath(joinpath(@__DIR__, ".."))

include(joinpath(repository, "test", "test_phase14_generic_fragments.jl"))
include(joinpath(repository, "integration", "conformance",
    "test_phase14_wang_authoring.jl"))

println("Phase 14.1 G3-A generic authoring gate: PASS")
