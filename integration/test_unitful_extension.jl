@testset "Unitful boundary conversion" begin
    unitful = 2.5Unitful.u"μm"
    dynamic = PottsToolkit.to_dynamic_quantity(unitful)
    @test dynamic isa DynamicQuantities.UnionAbstractQuantity
    roundtrip = PottsToolkit.to_unitful_quantity(dynamic)
    @test Unitful.ustrip(Unitful.u"μm", roundtrip) ≈ 2.5

    values = [1.0Unitful.u"s", 2.0Unitful.u"s"]
    dynamic_values = PottsToolkit.to_dynamic_quantity(values)
    @test length(dynamic_values) == 2
    @test Unitful.ustrip.(
        Unitful.u"s", PottsToolkit.to_unitful_quantity(dynamic_values)
    ) == [1.0, 2.0]

    matrix = reshape(
        [1.0Unitful.u"kg", 2.0Unitful.u"kg", 3.0Unitful.u"kg", 4.0Unitful.u"kg"],
        2,
        2,
    )
    dynamic_matrix = PottsToolkit.to_dynamic_quantity(matrix)
    restored_matrix = PottsToolkit.to_unitful_quantity(dynamic_matrix)
    @test size(restored_matrix) == (2, 2)
    @test Unitful.ustrip.(Unitful.u"kg", restored_matrix) == [1.0 3.0; 2.0 4.0]
    @test_throws Unitful.DimensionError Unitful.ustrip(Unitful.u"s", roundtrip)
end
