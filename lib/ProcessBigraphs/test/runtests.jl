using Test
using ProcessBigraphs

@testset "ProcessBigraphs PB0" begin
    include("test_paths_time_canonical.jl")
    include("test_schema_store_effects.jl")
    include("test_composite_preflight.jl")
    include("test_serial_microfixtures.jl")
end

@testset "Aqua" begin
    using Aqua
    Aqua.test_all(ProcessBigraphs; ambiguities=false)
end
