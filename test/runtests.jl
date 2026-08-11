include("setup.jl")

using Aqua
using ExplicitImports

include("test_runner_authority.jl")
verify_authoritative_runner(@__DIR__, AUTHORITATIVE_G5H_TESTS)

@testset "G5H-1 through G5H-3 authoritative package surface" begin
    for file in AUTHORITATIVE_G5H_TESTS
        @info "authoritative test file" file
        include(file)
    end
end
