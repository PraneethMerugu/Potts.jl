using Test
using PottsToolkit
using CorePotts

@testset "PottsToolkit" begin
    include("test_level2_authoring.jl")
    include("test_level1_authoring.jl")
    include("test_phase11_equivalence.jl")
    include("test_phase11_fragments.jl")
    include("test_phase11_inspection.jl")
    include("test_phase11_inventory.jl")
    include("test_phase11_macro_contract.jl")
    include("test_phase12_5_tiled.jl")
    include("test_phase13_contract_versions.jl")
    include("test_phase13_quality_gates.jl")
    include("test_phase14_generic_fragments.jl")
end
