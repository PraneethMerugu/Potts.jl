using Test
import LocalMath

struct OrderedCollectionNode end
struct OrderedCollectionRecord
    slot::Int32
    key::Tuple{Int32, UInt32, UInt32, UInt32}
    identity::Tuple{UInt32, Int32, UInt32, Int32}
end
struct OrderedCollectionEvaluator end
@inline function (::OrderedCollectionEvaluator)(item::Int32, reads, parameters)
    odd_only, duplicate, tied_keys = parameters
    slot = duplicate ? Int32(1) : item
    record = OrderedCollectionRecord(
        slot,
        (tied_keys ? Int32(0) : -slot, UInt32(1), UInt32(0), UInt32(0)),
        (UInt32(1), -slot, UInt32(0), Int32(1))
    )
    return (; records = LocalMath.CollectedValue(record, !odd_only || isodd(item)))
end

function _prepare_canonical_order_fixture(backend, count)
    source = LocalMath.Space(OrderedCollectionNode, count)
    collection = LocalMath.Collection(OrderedCollectionRecord, count)
    enabled = LocalMath.Parameter(:enabled, Bool)
    odd_only = LocalMath.Parameter(:odd_only, Bool)
    duplicate = LocalMath.Parameter(:duplicate, Bool)
    tied_keys = LocalMath.Parameter(:tied_keys, Bool)
    publication = LocalMath.Publication(
        (
            LocalMath.CollectionPublication(
                collection, LocalMath.PublicationValue(:records)
            ),
        ),
        LocalMath.Collect(
            OrderedCollectionRecord; maximum = 1,
            order = LocalMath.canonical_by(:key, :identity)
        )
    )
    stage = LocalMath.Stage(
        source, NamedTuple(), (publication,),
        LocalMath.Evaluator(OrderedCollectionEvaluator(), (odd_only, duplicate, tied_keys)),
        LocalMath.Control(gate = enabled),
        LocalMath.SourceOrigin(:canonical_collection, 1)
    )
    law = LocalMath.LocalLaw(
        stage;
        parameters = LocalMath.ParameterSchema(odd_only, duplicate, tied_keys, enabled)
    )
    storage = LocalMath.CompactedStorage(
        backend, OrderedCollectionRecord, count;
        source_items = count
    )
    prepared = LocalMath.prepare(law, collection => storage; backend)
    return (; prepared, storage)
end

function _collect_canonical_order_contract(backend)
    host_records(storage) = collect(LocalMath.Adapt.adapt(Array, storage.records))
    return @testset "canonical tuple-key collection" begin
        for count in (1, 2, 255, 256, 257)
            @testset "capacity $count" begin
                (; prepared, storage) = _prepare_canonical_order_fixture(backend, count)
                @test Array(storage.count) == Int32[0]
                run(; enabled = true, odd_only = false, duplicate = false, tied_keys = false) =
                    wait(LocalMath.execute!(prepared; parameters = (; enabled, odd_only, duplicate, tied_keys)))
                run()
                @test Array(storage.count) == Int32[count]
                @test map(record -> record.slot, host_records(storage)) == Int32.(count:-1:1)
                run(; odd_only = true)
                expected = reverse(filter(isodd, Int32.(1:count)))
                @test Array(storage.count) == Int32[length(expected)]
                @test map(
                    record -> record.slot,
                    host_records(storage)[1:length(expected)]
                ) == expected
                run(; tied_keys = true)
                @test Array(storage.count) == Int32[count]
                @test map(record -> record.slot, host_records(storage)) == Int32.(count:-1:1)
                published = host_records(storage)
                run(; enabled = false)
                @test Array(storage.count) == Int32[0]
                @test host_records(storage) == published
                if count > 1
                    run()
                    published = host_records(storage)
                    previous_count = Array(storage.count)
                    failure = try
                        run(; duplicate = true)
                        nothing
                    catch error
                        error
                    end
                    @test failure isa LocalMath.LocalMathValidationError
                    @test failure.contract === :runtime_stage_validation
                    @test failure.actual.failure_class === :duplicate_identity
                    @test Array(storage.count) == previous_count
                    @test host_records(storage) == published
                end
            end
        end
    end
end
