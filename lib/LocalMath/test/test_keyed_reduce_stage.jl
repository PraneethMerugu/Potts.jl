using Test
import KernelAbstractions
import LocalMath
const LMKR = LocalMath
include("fixtures/keyed_reduce_contracts.jl")

@test_throws LMKR.LocalMathValidationError LMKR.RebuildFromIdentity(:metadata)
@test_throws LMKR.LocalMathValidationError LMKR.KeyedReduce(
    Int32, Int32, +; seed = LMKR.RebuildFromIdentity(0.0f0))

keyed_reduce_contract(KernelAbstractions.CPU())
mixed_keyed_stage_sequence_contract(KernelAbstractions.CPU())

struct KeyedReduceNode end
struct KeyedReduceEvaluator end
@inline function (::KeyedReduceEvaluator)(item::Int32, reads, parameters)
    remove = getfield(parameters, 1)
    key = (UInt32(isodd(item) ? 1 : 2), UInt32(7))
    delta = remove ? Int32(-1) : Int32(1)
    return (; delta = LMKR.KeyedContribution(key, delta))
end

struct DecimalKeyedFold end
@inline (::DecimalKeyedFold)(left::Int32, right::Int32) =
    Int32(10) * left + right
struct DecimalKeyedEvaluator end
@inline (::DecimalKeyedEvaluator)(item::Int32, reads, parameters) =
    (; delta = LMKR.KeyedContribution((UInt32(1), UInt32(9)), item))

struct DistinctKeyedEvaluator end
@inline (::DistinctKeyedEvaluator)(item::Int32, reads, parameters) =
    (; delta = LMKR.KeyedContribution((UInt32(item), UInt32(3)), Int32(1)))

struct InactiveKeyedEvaluator end
@inline (::InactiveKeyedEvaluator)(item::Int32, reads, parameters) =
    (; delta = LMKR.KeyedContribution((UInt32(9), UInt32(9)), Int32(0), false))

function _keyed_reduce_program(source_count, collection, evaluator;
        operation = +, retention = LMKR.DropIdentityKeys())
    source = LMKR.Space(KeyedReduceNode, source_count)
    stage = LMKR.Stage(source, NamedTuple(), (
        LMKR.Publication(collection,
            LMKR.KeyedReduce(Tuple{UInt32,UInt32}, Int32, operation;
                maximum = 1, seed = LMKR.NewKeyIdentity(Int32(0)), retention);
            value = :delta),), LMKR.Evaluator(evaluator), LMKR.Control(),
        LMKR.SourceOrigin(:keyed_reduce_test, 2))
    return LMKR.LocalLaw(stage)
end

function _keyed_reduce_fixture(; capacity = 4)
    source = LMKR.Space(KeyedReduceNode, 3)
    collection = LMKR.Collection(
        LMKR.KeyedValue{Tuple{UInt32,UInt32},Int32}, capacity)
    remove = LMKR.Parameter(:remove, Bool)
    stage = LMKR.Stage(source, NamedTuple(), (
        LMKR.Publication(collection,
            LMKR.KeyedReduce(Tuple{UInt32,UInt32}, Int32, +;
                maximum = 1, seed = LMKR.NewKeyIdentity(Int32(0)),
                retention = LMKR.DropIdentityKeys()); value = :delta),),
        LMKR.Evaluator(KeyedReduceEvaluator(), (remove,)), LMKR.Control(),
        LMKR.SourceOrigin(:keyed_reduce_test, 1))
    prepared = LMKR.prepare(LMKR.LocalLaw(stage;
        parameters = LMKR.ParameterSchema(remove)),
        collection => LMKR.Allocate(); backend = KernelAbstractions.CPU())
    return prepared, collection
end


@testset "keyed reduction canonical order and failure atomicity" begin
    backend = KernelAbstractions.CPU()
    record_type = LMKR.KeyedValue{Tuple{UInt32,UInt32},Int32}

    ordered_collection = LMKR.Collection(record_type, 3)
    ordered = LMKR.prepare(_keyed_reduce_program(3, ordered_collection,
            DecimalKeyedEvaluator(); operation = DecimalKeyedFold(),
            retention = LMKR.RetainAllKeys()),
        ordered_collection => LMKR.Allocate(); backend)
    wait(LMKR.execute!(ordered))
    ordered_store = LMKR.storage(ordered, ordered_collection)
    @test collect(LMKR.Adapt.adapt(Array, ordered_store.records))[1].value == 123
    wait(LMKR.execute!(ordered))
    @test collect(LMKR.Adapt.adapt(Array, ordered_store.records))[1].value == 123123

    overflow_collection = LMKR.Collection(record_type, 1)
    overflow_store = LMKR.CompactedStorage(backend, record_type, 1)
    overflow_store.records[1] = LMKR.KeyedValue((UInt32(9), UInt32(9)), Int32(4))
    overflow_store.count[1] = Int32(1)
    overflowing = LMKR.prepare(_keyed_reduce_program(2, overflow_collection,
            DistinctKeyedEvaluator()), overflow_collection => overflow_store;
        backend)
    before = collect(LMKR.Adapt.adapt(Array, overflow_store.records))
    failure = try
        wait(LMKR.execute!(overflowing))
        nothing
    catch error
        error
    end
    @test failure isa LMKR.LocalMathValidationError
    @test failure.actual.failure_class === :capacity_overflow
    @test Array(overflow_store.count) == Int32[1]
    @test collect(LMKR.Adapt.adapt(Array, overflow_store.records)) == before

    duplicate_collection = LMKR.Collection(record_type, 2)
    duplicate_store = LMKR.CompactedStorage(backend, record_type, 2)
    duplicate_store.records[1] = LMKR.KeyedValue((UInt32(4), UInt32(4)), Int32(1))
    duplicate_store.records[2] = LMKR.KeyedValue((UInt32(4), UInt32(4)), Int32(2))
    duplicate_store.count[1] = Int32(2)
    duplicate = LMKR.prepare(_keyed_reduce_program(1, duplicate_collection,
            InactiveKeyedEvaluator()), duplicate_collection => duplicate_store;
        backend)
    before = collect(LMKR.Adapt.adapt(Array, duplicate_store.records))
    failure = try
        wait(LMKR.execute!(duplicate))
        nothing
    catch error
        error
    end
    @test failure isa LMKR.LocalMathValidationError
    @test failure.actual.failure_class === :duplicate_key
    @test Array(duplicate_store.count) == Int32[2]
    @test collect(LMKR.Adapt.adapt(Array, duplicate_store.records)) == before

    duplicate_store.count[1] = Int32(-1)
    failure = try
        wait(LMKR.execute!(duplicate))
        nothing
    catch error
        error
    end
    @test failure isa LMKR.LocalMathValidationError
    @test failure.actual.failure_class === :invalid_prior_count
    @test Array(duplicate_store.count) == Int32[-1]
end

@testset "exact sparse keyed reduction" begin
    prepared, collection = _keyed_reduce_fixture()
    store = LMKR.storage(prepared, collection)
    wait(LMKR.execute!(prepared; parameters = (; remove = false)))
    @test Array(store.count) == Int32[2]
    records = collect(LMKR.Adapt.adapt(Array, store.records))[1:2]
    @test records == [
        LMKR.KeyedValue((UInt32(1), UInt32(7)), Int32(2)),
        LMKR.KeyedValue((UInt32(2), UInt32(7)), Int32(1)),
    ]
    wait(LMKR.execute!(prepared; parameters = (; remove = true)))
    @test Array(store.count) == Int32[0]
end
