using Test
using ProcessBigraphs

@testset "ProcessBigraphs primitives and canonical values" begin
    include("primitives/test_paths_time_canonical.jl")
    include("primitives/test_schema_store_effects.jl")
    include("runtime/test_serial_microfixtures.jl")
end

@testset "ProcessBigraphs authoring and validation" begin
    include("authoring/test_high_level_authoring.jl")
    include("examples/high_level_authoring.jl")
    include("fixtures/serial_runtime.jl")
    include("authoring/test_authoring_equivalence.jl")
end

@testset "ProcessBigraphs static and dynamic structure" begin
    include("structure/test_composite_preflight.jl")
    include("structure/test_algebraic_structure.jl")
    include("structure/test_open_composition.jl")
    include("structure/test_structural_transactions.jl")
end

@testset "ProcessBigraphs scheduling and runtime transactions" begin
    include("runtime/test_serial_scheduler.jl")
    include("runtime/test_adaptive_and_iteration.jl")
    include("runtime/test_semantic_rng.jl")
    include("runtime/test_observation.jl")
    include("runtime/test_observation_continuation.jl")
    include("runtime/test_properties_metamorphic.jl")
end

@testset "ProcessBigraphs engine and field protocols" begin
    include("engine/test_engine_field_protocol.jl")
    include("engine/test_solver_adapter_contract.jl")
end

@testset "ProcessBigraphs persistence and migration" begin
    include("persistence/test_checkpoint_v2.jl")
    include("persistence/test_failure_checkpoint.jl")
    include("persistence/test_restart_matrix.jl")
    include("persistence/test_logical_checkpoint.jl")
end

@testset "ProcessBigraphs current contract" begin
    include("contracts/test_internal_beta_contract.jl")
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
