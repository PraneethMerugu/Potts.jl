include(joinpath(@__DIR__, "..", "test_product_values.jl"))

@testset "named product publication on Metal" begin
    test_product_value_publication(Metal.MetalBackend())
    test_routed_product_publication(Metal.MetalBackend())
    test_product_layout_rejections(
        Metal.MetalBackend(), 1.0;
        unsupported_error = ErrorException,
        unsupported_message = "Metal does not support Float64"
    )
end
