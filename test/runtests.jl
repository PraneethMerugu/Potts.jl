include("setup.jl")

using Aqua
using ExplicitImports

@testset "Symbolic Potts V1" begin
    include("test_system_contract.jl")
    include("test_statements_and_traversal.jl")
    include("test_completion_and_diagnostics.jl")
    include("test_host_compiler_facts.jl")
    include("test_descriptor_compiler.jl")
    include("test_g2_r1_repairs.jl")
    include("test_architecture_freeze.jl")
    include("test_g3_sequential_reference.jl")
    include("test_g5_relationship_runtime.jl")
    include("test_units_and_parameters.jl")
    include("test_compilation_and_inspection.jl")
    include("test_initial_problem_remake.jl")
    include("test_runtime_solution_sii.jl")
    include("test_checkpoint.jl")
    include("test_wortel_fixture.jl")
    include("test_merks_fixture.jl")
    include("test_focal_fixture.jl")
    include("test_package_quality.jl")
end
