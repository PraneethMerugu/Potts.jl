using Test
import LocalMath
import StaticArrays: SVector, MVector

struct RoutedProductValue{Resolve} end

@inline _routed_product(item::Int32) =
    (active = isodd(item), count = item, polarity = SVector(Float32(item), -Float32(item)))

@inline function (::RoutedProductValue{Resolve})(item::Int32, reads, parameters) where {Resolve}
    value = _routed_product(item)
    return Resolve ?
        (value = LocalMath.RoutedResolutionValue(item <= 2 ? Int32(1) : Int32(2), Int32(4) - item, value),) :
        (value = LocalMath.RoutedUniqueValue(Int32(4) - item, value),)
end

function test_routed_product_publication(backend)
    initial = _routed_product(Int32(0))
    for resolve in (false, true)
        source, destination = LocalMath.Space(3), LocalMath.Space(3)
        output = LocalMath.Field(destination, typeof(initial))
        relation = LocalMath.RuntimeRelation(source => destination; degree_bound = 1, key_type = Int32)
        publication = resolve ?
            LocalMath.Resolve(Int32, typeof(initial); lower = Int32(1), upper = Int32(3)) :
            LocalMath.Unique(typeof(initial))
        stage = LocalMath.Stage(
            source, NamedTuple(),
            (LocalMath.Publication((LocalMath.FieldPublication(output, relation, LocalMath.PublicationValue(:value)),), publication),),
            LocalMath.Evaluator(RoutedProductValue{resolve}()), LocalMath.Control(),
            LocalMath.SourceOrigin(:routed_product_publication, 1)
        )
        prepared = LocalMath.prepare(LocalMath.LocalLaw(stage), output => LocalMath.Allocate(fill(initial, 3)); backend)
        wait(LocalMath.execute!(prepared))
        expected = resolve ? Int32[2, 3, 0] : Int32[3, 2, 1]
        @test Array(LocalMath.storage(prepared, output)) == _routed_product.(expected)
    end
    return
end

struct ProductCopyValue end
@inline (::ProductCopyValue)(item::Int32, reads, parameters) =
    (value = LocalMath.UniqueValue(something(reads[1][1].value)),)

function _prepare_product_copy(backend, value)
    space = LocalMath.Space(1)
    input = LocalMath.Field(space, typeof(value))
    output = LocalMath.Field(space, typeof(value))
    relation = LocalMath.IdentityRelation(space)
    stage = LocalMath.Stage(
        space, (value = LocalMath.Access(input, relation; required = true),),
        (LocalMath.Publication((LocalMath.FieldPublication(output, relation, LocalMath.PublicationValue(:value)),), LocalMath.Unique(typeof(value))),),
        LocalMath.Evaluator(ProductCopyValue()), LocalMath.Control(), LocalMath.SourceOrigin(:product_layout, 1)
    )
    return LocalMath.prepare(LocalMath.LocalLaw(stage), input => LocalMath.Allocate(fill(value, 1)), output => LocalMath.Allocate(undef); backend)
end

function test_product_layout_rejections(
        backend, unsupported;
        unsupported_error = LocalMath.LocalMathValidationError,
        unsupported_message = string(typeof(unsupported))
    )
    oversized = (values = ntuple(_ -> 1.0f0, 17),)
    @test_throws LocalMath.LocalMathValidationError _prepare_product_copy(backend, oversized)
    failure = try
        _prepare_product_copy(backend, (inner = (unsupported = unsupported,),))
        nothing
    catch error
        error
    end
    @test failure isa unsupported_error
    @test occursin(unsupported_message, failure === nothing ? "" : sprint(showerror, failure))
    for value in ((inner = (pointer = Ptr{Float32}(0),),), (inner = (name = :metadata,),), (inner = MVector(1.0f0, 2.0f0),))
        @test_throws LocalMath.LocalMathValidationError LocalMath.Field(LocalMath.Space(1), typeof(value))
        capture = let captured = value
            (item, reads, parameters) -> (value = LocalMath.UniqueValue(captured),)
        end
        @test_throws LocalMath.LocalMathValidationError LocalMath.Evaluator(capture)
    end
    return
end
