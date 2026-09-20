include(joinpath(@__DIR__, "..", "setup.jl"))

@testset "native exact replay" begin
    include("test_maintained_native_snapshot.jl")
    include(joinpath(@__DIR__, "..", "test_native_runtime.jl"))
    include(joinpath(@__DIR__, "..", "test_native_batched_cpu.jl"))
    include("test_modelingtoolkit_standard_library_replay.jl")
end
