using Aqua
using Test
import LocalWorksets

@testset "LocalWorksets package quality" begin
    Aqua.test_all(LocalWorksets; ambiguities = false)
    @test isempty(Test.detect_ambiguities(
        LocalWorksets, Base; recursive = true
    ))
end

include("support.jl")
include("test_api.jl")
include("test_mechanisms.jl")
include("test_generic.jl")
include("test_runtime.jl")

# These tests deliberately install hostile external methods. Keep them last so
# their irreversible world changes cannot contaminate functional checks.
include("test_admission.jl")
