using Test
using PottsToolkit
using DynamicQuantities
using ModelingToolkitBase
using SciMLBase
using SymbolicIndexingInterface
using Symbolics

@testset "Symbolic Potts V1" begin
    include("test_system_contract.jl")
    include("test_statements_and_traversal.jl")
    include("test_completion_and_diagnostics.jl")
    include("test_compilation_and_inspection.jl")
    include("test_initial_problem_remake.jl")
    include("test_runtime_solution_sii.jl")
    include("test_checkpoint.jl")
end
