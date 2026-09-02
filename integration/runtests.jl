include("setup.jl")

const INTEGRATION_TESTS = (
    "test_modelingtoolkit_retention_and_structural_scheduling.jl",
    "test_modelingtoolkit_standard_library.jl",
    "test_native_functional_cpu.jl",
    "test_method_of_lines_field.jl",
    "test_ensemble_distributed.jl",
    "test_unitful_extension.jl",
    "test_optional_extension_loading.jl",
    "test_extension_load_order.jl",
)

@testset "Potts integrations" begin
    for file in INTEGRATION_TESTS
        @testset "$file" begin
            include(file)
        end
    end
end
