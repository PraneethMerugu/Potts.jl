using Test
using ProcessBigraphs

@testset "ProcessBigraphs PB0" begin
    include("test_paths_time_canonical.jl")
    include("test_schema_store_effects.jl")
    include("test_composite_preflight.jl")
    include("test_serial_microfixtures.jl")
    include("test_phase15a_algebraic_structure.jl")
end

@testset "Aqua" begin
    using Aqua
    # CI already installs, precompiles, loads, and exercises ProcessBigraphs from a clean
    # temporary project. Aqua's persistent-task probe repeats that work in a silent nested
    # precompile and can report an "unexpected exit" before its sentinel is written when the
    # Catlab dependency graph is cold. Keep Aqua's deterministic package-quality checks here and
    # leave clean-precompile qualification to the explicit CI gate.
    Aqua.test_all(ProcessBigraphs; ambiguities=false, persistent_tasks=false)
end
