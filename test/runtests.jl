using Test
using PottsToolkit
using ModelingToolkitBase
using Symbolics

@testset "Symbolic Potts V1" begin
    include("test_system_contract.jl")
    include("test_statements_and_traversal.jl")
    include("test_completion_and_diagnostics.jl")
end
