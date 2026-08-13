include("setup.jl")

using Aqua
using ExplicitImports

include("test_runner_authority.jl")
verify_test_inventory(@__DIR__, POTTS_TOOLKIT_TESTS)

@testset "PottsToolkit package suite" begin
    for file in POTTS_TOOLKIT_TESTS
        @info "package test file" file
        include(file)
    end
end
