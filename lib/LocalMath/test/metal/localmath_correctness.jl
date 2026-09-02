using Test
using LocalMath
using Metal

struct ProductRelationMetalEvaluator end
@inline function (::ProductRelationMetalEvaluator)(item::Int32, reads, parameters)
    sample = getfield(reads, 1)[1]
    return (value = LocalMath.UniqueValue(something(sample.value)),)
end

@testset "LocalMath selected source-position lanes on real Metal" begin
    backend = Metal.MetalBackend()
    source = Space(3)
    records = Collection(Int32, 6)
    lane_one = Field(source, Int32)
    lane_two = Field(source, Int32)

    law = @localmath begin
        @stage produce(item ∈ source) begin
            records[item] = bounded_collect((
                Int32(10) * item, Int32(20) * item,
            ); maximum=2, when=(true, item != Int32(2)),
                projection=:source_position)
        end
        @stage consume(item ∈ source) begin
            lane_one[item] = source_position(records, item; lane=1)
            lane_two[item] = source_position(records, item; lane=2)
        end
    end

    prepared = @prepare (law; backend) begin
        records = allocate()
        lane_one = allocate(Int32(-1))
        lane_two = allocate(Int32(-1))
    end
    wait(execute!(prepared))

    @test Array(LocalMath.storage(prepared, lane_one)) == Int32[1, 3, 4]
    @test Array(LocalMath.storage(prepared, lane_two)) == Int32[2, 0, 5]
end

@testset "LocalMath public Cartesian product relation on real Metal" begin
    backend = Metal.MetalBackend()
    rows = Space(2)
    columns = Space(3)
    product_domain = Space((rows, columns))
    product_codomain = Space((rows, columns))
    relation = ProductRelation(
        product_domain => product_codomain,
        (IdentityRelation(rows), IdentityRelation(columns)),
    )
    input = Field(product_codomain, Int32)
    output = Field(product_domain, Int32)

    publication = LocalMath.Publication(
        output, IdentityRelation(product_domain), LocalMath.Unique(Int32))
    stage = LocalMath.Stage(product_domain,
        (input = LocalMath.Access(input, relation),),
        (publication,), ProductRelationMetalEvaluator())
    law = LocalLaw(stage)
    prepared = @prepare (law; backend) begin
        input = Metal.MtlArray(Int32[11, 12, 13, 14, 15, 16])
        output = allocate(Int32(-1))
    end
    wait(execute!(prepared))

    @test Array(LocalMath.storage(prepared, output)) ==
        Int32[11, 12, 13, 14, 15, 16]
end
