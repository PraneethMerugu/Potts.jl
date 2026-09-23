using StaticArrays

@testset "product field substitution preserves its declared structural type" begin
    @variables first_product::NamedTuple{(:direction,), Tuple{SVector{2, Float64}}}
    @variables same_product::NamedTuple{(:direction,), Tuple{SVector{2, Float64}}}
    @variables changed_shape::NamedTuple{(:direction,), Tuple{SVector{3, Float64}}}
    expression = ModelState(first_product).direction
    same = Symbolics.substitute(expression, Dict(first_product => same_product))
    @test size(same) == (2,)
    @test Symbolics.symtype(Symbolics.unwrap(same)) === SVector{2, Float64}
    @test isequal(Symbolics.unwrap(only(Symbolics.get_variables(same))), Symbolics.unwrap(same_product))
    @test_throws r"same declared product type" Symbolics.substitute(expression, Dict(first_product => changed_shape))

    @variables ordered::NamedTuple{(:amount, :rate), Tuple{Float64, Float64}}
    @variables reordered::NamedTuple{(:rate, :amount), Tuple{Float64, Float64}}
    @test_throws r"same declared product type" Symbolics.substitute(ModelState(ordered).amount, Dict(ordered => reordered))

    @variables nested::NamedTuple{(:memory,), Tuple{NamedTuple{(:count,), Tuple{Int}}}}
    @variables changed_nested::NamedTuple{(:memory,), Tuple{NamedTuple{(:count,), Tuple{Float64}}}}
    @test_throws r"same declared product type" Symbolics.substitute(ModelState(nested).memory.count, Dict(nested => changed_nested))
end
