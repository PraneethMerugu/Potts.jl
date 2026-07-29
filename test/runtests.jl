using Test
using PottsToolkit
using CorePotts

@testset "PottsToolkit" begin
    include("test_level2_authoring.jl")
    include("test_level1_authoring.jl")
    include("test_authoring_equivalence.jl")
    include("test_model_fragments.jl")
    include("test_model_inspection.jl")
    include("test_component_inventory.jl")
    include("test_authoring_macro_contract.jl")
    include("test_tiled_authoring.jl")
    include("test_reference_model_families.jl")
    include("test_contract_versions.jl")
    include("test_package_quality.jl")
    include("test_generic_model_fragments.jl")
    include("test_documentation_quality_checker.jl")
end
