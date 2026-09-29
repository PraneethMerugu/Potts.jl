using Test
import LocalMath
import KernelAbstractions
import StaticArrays: SVector

include(joinpath(@__DIR__, "fixtures", "product_publication_contracts.jl"))

struct ProductValueUpdate{P}
    increment::P
end

struct TupleProductValueUpdate{T}
    operations::T
end

@inline function (operation::TupleProductValueUpdate)(item::Int32, reads, parameters)
    return only(operation.operations)(item, reads, parameters)
end

@inline function (operation::ProductValueUpdate)(item::Int32, reads, parameters)
    before = something(reads[1][1].value)
    increment = operation.increment
    after = (
        active = !before.active,
        count = before.count + increment.count,
        polarity = before.polarity + increment.polarity,
    )
    return (value = LocalMath.UniqueValue(after),)
end

function test_product_value_publication(backend; wrap = identity)
    initial = (active = false, count = Int32(2), polarity = SVector(1.0f0, 2.0f0))
    increment = (count = Int32(3), polarity = SVector(0.5f0, 1.0f0))
    space = LocalMath.Space(3)
    input = LocalMath.Field(space, typeof(initial))
    output = LocalMath.Field(space, typeof(initial))
    relation = LocalMath.IdentityRelation(space)
    stage = LocalMath.Stage(
        space, (value = LocalMath.Access(input, relation; required = true),),
        (LocalMath.Publication((LocalMath.FieldPublication(output, relation, LocalMath.PublicationValue(:value)),), LocalMath.Unique(typeof(initial))),),
        LocalMath.Evaluator(wrap(ProductValueUpdate(increment))), LocalMath.Control(),
        LocalMath.SourceOrigin(:product_value_publication, 1),
    )
    prepared = LocalMath.prepare(
        LocalMath.LocalLaw(stage),
        input => LocalMath.Allocate(fill(initial, 3)), output => LocalMath.Allocate(undef); backend
    )
    wait(LocalMath.execute!(prepared))
    values = Array(LocalMath.storage(prepared, output))
    @test values == fill((active = true, count = Int32(5), polarity = SVector(1.5f0, 3.0f0)), 3)
    @test eltype(values) === typeof(initial)
    return @test Array(LocalMath.storage(prepared, input)) == fill(initial, 3)
end

@testset "named products share ordinary field publication" begin
    test_product_value_publication(KernelAbstractions.CPU())
    test_product_value_publication(
        KernelAbstractions.CPU(); wrap = operation -> TupleProductValueUpdate((operation,))
    )
    for value in ((name = :metadata,), (values = Float32[1],), (pointer = Ptr{Float32}(0),))
        @test_throws LocalMath.LocalMathValidationError LocalMath.Field(LocalMath.Space(1), typeof(value))
        @test_throws LocalMath.LocalMathValidationError LocalMath.Evaluator(ProductValueUpdate(value))
        @test_throws LocalMath.LocalMathValidationError LocalMath.Evaluator(
            TupleProductValueUpdate((ProductValueUpdate(value),))
        )
    end
end

@testset "routed products and nested layout contracts" begin
    test_routed_product_publication(KernelAbstractions.CPU())
    test_product_layout_rejections(KernelAbstractions.CPU(), Int64(1))
end
