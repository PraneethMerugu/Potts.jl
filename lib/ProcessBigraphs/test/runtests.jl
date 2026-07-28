using Test
using ProcessBigraphs

@testset "ProcessBigraphs PB0" begin
    include("test_paths_time_canonical.jl")
    include("test_schema_store_effects.jl")
    include("test_composite_preflight.jl")
    include("test_serial_microfixtures.jl")
    include("test_high_level_authoring.jl")
    include("examples/high_level_authoring.jl")
    include("test_phase15a_algebraic_structure.jl")
    include("test_phase15b_open_composition.jl")
end

@testset "ProcessBigraphs Phase 15.C" begin
    include("phase15c/fixtures.jl")
    include("phase15c/test_serial_scheduler.jl")
    include("phase15c/test_adaptive_and_iteration.jl")
    include("phase15c/test_semantic_rng.jl")
    include("phase15c/test_observation.jl")
    include("phase15c/test_observation_continuation.jl")
    include("phase15c/test_checkpoint_v2.jl")
    include("phase15c/test_failure_checkpoint.jl")
    include("phase15c/test_properties_metamorphic.jl")
    include("phase15c/test_authoring_equivalence.jl")
    include("phase15c/test_restart_matrix.jl")
end

@testset "ProcessBigraphs Phase 16" begin
    include("phase16/test_phase16a_entry.jl")
    include("phase16/test_phase16b_engine_field.jl")
    include("phase16/test_phase16d_structural_transactions.jl")
    include("phase16/test_phase16e_checkpoint.jl")
    include("phase16/test_phase16f_solver_plurality.jl")
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
