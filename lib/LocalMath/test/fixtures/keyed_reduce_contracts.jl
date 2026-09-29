struct KeyedReduceContractNode end
struct KeyedReduceContractEvaluator end
@inline function (::KeyedReduceContractEvaluator)(item::Int32, reads, parameters)
    direction = getfield(parameters, 1)
    key = (UInt32(isodd(item) ? 1 : 2), UInt32(11), UInt32(3))
    return (; delta = LocalMath.KeyedContribution(key, direction))
end

struct EmptyKeyedReduceEvaluator end
@inline (::EmptyKeyedReduceEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution(Int32(0), Int32(0), false))

struct OrderedLaneKeyedReduceEvaluator end
@inline function (::OrderedLaneKeyedReduceEvaluator)(item::Int32, reads, parameters)
    phase = getfield(parameters, 1)
    if phase == Int32(0)
        return (; delta = (
            LocalMath.KeyedContribution(Int32(7), Int32(9), item == Int32(1)),
            LocalMath.KeyedContribution(Int32(7), Int32(0), false),
        ))
    end
    first_value = Int32(2) * item - Int32(1)
    return (; delta = (
        LocalMath.KeyedContribution(Int32(7), first_value),
        LocalMath.KeyedContribution(Int32(7), first_value + Int32(1)),
    ))
end

struct OrderedLaneDecimalFold end
@inline (::OrderedLaneDecimalFold)(left::Int32, right::Int32) =
    Int32(10) * left + right

struct SignedExtremeKeyedReduceEvaluator end
@inline (::SignedExtremeKeyedReduceEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution(
        item == Int32(1) ? typemin(Int32) : typemax(Int32), item))

struct OverflowKeyedReduceEvaluator end
@inline (::OverflowKeyedReduceEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution(Int32(item), Int32(1)))

struct RebuildOrderedKeyedReduceEvaluator end
@inline (::RebuildOrderedKeyedReduceEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution(Int32(3), item))

struct FirstMixedKeyEvaluator end
@inline (::FirstMixedKeyEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution((item, UInt32(1)), Int32(1)))

struct SecondMixedKeyEvaluator end
@inline (::SecondMixedKeyEvaluator)(item::Int32, reads, parameters) =
    (; delta = LocalMath.KeyedContribution((UInt32(1), -item), Int32(1)))

function mixed_keyed_stage_sequence_contract(backend)
    return @testset "successive keyed reductions retain distinct key layouts" begin
        source = LocalMath.Space(KeyedReduceContractNode, 2)
        first_key = Tuple{Int32,UInt32}
        second_key = Tuple{UInt32,Int32}
        first = LocalMath.Collection(LocalMath.KeyedValue{first_key,Int32}, 2)
        second = LocalMath.Collection(LocalMath.KeyedValue{second_key,Int32}, 2)
        function stage(destination, key_type, evaluator, label)
            LocalMath.Stage(source, NamedTuple(), (
                LocalMath.Publication(destination,
                    LocalMath.KeyedReduce(key_type, Int32, +;
                        maximum = 1,
                        seed = LocalMath.RebuildFromIdentity(Int32(0)),
                        retention = LocalMath.DropIdentityKeys());
                    value = :delta),),
                LocalMath.Evaluator(evaluator), LocalMath.Control(),
                LocalMath.SourceOrigin(:keyed_reduce_contract, label))
        end
        law = LocalMath.sequence(
            LocalMath.LocalLaw(stage(
                first, first_key, FirstMixedKeyEvaluator(), 3)),
            LocalMath.LocalLaw(stage(
                second, second_key, SecondMixedKeyEvaluator(), 4)),
        )
        prepared = LocalMath.prepare(law,
            first => LocalMath.Allocate(),
            second => LocalMath.Allocate(); backend)
        wait(LocalMath.execute!(prepared))
        first_records = LocalMath.storage(prepared, first)
        second_records = LocalMath.storage(prepared, second)
        @test only(LocalMath.Adapt.adapt(Array, first_records.count)) == 2
        @test only(LocalMath.Adapt.adapt(Array, second_records.count)) == 2
        @test Set(LocalMath.Adapt.adapt(Array, first_records.records)) == Set([
            LocalMath.KeyedValue((Int32(1), UInt32(1)), Int32(1)),
            LocalMath.KeyedValue((Int32(2), UInt32(1)), Int32(1)),
        ])
        @test Set(LocalMath.Adapt.adapt(Array, second_records.records)) == Set([
            LocalMath.KeyedValue((UInt32(1), Int32(-1)), Int32(1)),
            LocalMath.KeyedValue((UInt32(1), Int32(-2)), Int32(1)),
        ])
    end
end

function _shared_keyed_program(backend, source_count, key_type, capacity,
        evaluator; maximum = 1, operation = +,
        seed = LocalMath.NewKeyIdentity(Int32(0)),
        retention = LocalMath.DropIdentityKeys(), parameters = (),
        control = LocalMath.Control(), storage = nothing)
    source = LocalMath.Space(KeyedReduceContractNode, source_count)
    records = LocalMath.Collection(LocalMath.KeyedValue{key_type,Int32}, capacity)
    stage = LocalMath.Stage(source, NamedTuple(), (
            LocalMath.Publication(records,
                LocalMath.KeyedReduce(key_type, Int32, operation;
                    maximum, seed, retention); value = :delta),),
        LocalMath.Evaluator(evaluator, parameters), control,
        LocalMath.SourceOrigin(:keyed_reduce_contract, 2))
    schema = isempty(parameters) ? LocalMath.ParameterSchema() :
        LocalMath.ParameterSchema(parameters...)
    binding = storage === nothing ? LocalMath.Allocate() : storage
    prepared = LocalMath.prepare(LocalMath.LocalLaw(stage; parameters = schema),
        records => binding; backend)
    return prepared, LocalMath.storage(prepared, records)
end

function _initialize_scalar_keyed_storage!(storage, keys, values, count)
    copyto!(getproperty(storage.records, :key), keys)
    copyto!(getproperty(storage.records, :value), values)
    copyto!(storage.count, Int32[count])
    return storage
end

function _keyed_failure(execution)
    try
        wait(execution)
        return nothing
    catch error
        return error
    end
end

function keyed_reduce_contract(backend)
    return @testset "keyed reduction CPU/Metal contract" begin
        source = LocalMath.Space(KeyedReduceContractNode, 3)
        key_type = Tuple{UInt32,UInt32,UInt32}
        record_type = LocalMath.KeyedValue{key_type,Int32}
        records = LocalMath.Collection(record_type, 4)
        direction = LocalMath.Parameter(:direction, Int32;
            bounds = (Int32(-1), Int32(1)))
        stage = LocalMath.Stage(source, NamedTuple(), (
            LocalMath.Publication(records,
                LocalMath.KeyedReduce(key_type, Int32, +;
                    maximum = 1,
                    seed = LocalMath.NewKeyIdentity(Int32(0)),
                    retention = LocalMath.DropIdentityKeys());
                value = :delta),),
            LocalMath.Evaluator(KeyedReduceContractEvaluator(), (direction,)),
            LocalMath.Control(),
            LocalMath.SourceOrigin(:keyed_reduce_contract, 1))
        prepared = LocalMath.prepare(LocalMath.LocalLaw(stage;
                parameters = LocalMath.ParameterSchema(direction)),
            records => LocalMath.Allocate(); backend)
        storage = LocalMath.storage(prepared, records)

        wait(LocalMath.execute!(prepared;
            parameters = (; direction = Int32(1))))
        @test Array(storage.count) == Int32[2]
        host = collect(LocalMath.Adapt.adapt(Array, storage.records))[1:2]
        @test host == [
            LocalMath.KeyedValue((UInt32(1), UInt32(11), UInt32(3)), Int32(2)),
            LocalMath.KeyedValue((UInt32(2), UInt32(11), UInt32(3)), Int32(1)),
        ]

        wait(LocalMath.execute!(prepared;
            parameters = (; direction = Int32(-1))))
        @test Array(storage.count) == Int32[0]

        empty, empty_storage = _shared_keyed_program(backend, 0, Int32, 0,
            EmptyKeyedReduceEvaluator())
        wait(LocalMath.execute!(empty))
        @test Array(empty_storage.count) == Int32[0]
        @test isempty(LocalMath.Adapt.adapt(Array, empty_storage.records))

        phase = LocalMath.Parameter(:phase, Int32;
            bounds = (Int32(0), Int32(1)))
        ordered, ordered_storage = _shared_keyed_program(backend, 2, Int32, 1,
            OrderedLaneKeyedReduceEvaluator(); maximum = 2,
            operation = OrderedLaneDecimalFold(),
            retention = LocalMath.RetainAllKeys(), parameters = (phase,))
        wait(LocalMath.execute!(ordered; parameters = (; phase = Int32(0))))
        wait(LocalMath.execute!(ordered; parameters = (; phase = Int32(1))))
        ordered_host = collect(LocalMath.Adapt.adapt(
            Array, ordered_storage.records))
        @test Array(ordered_storage.count) == Int32[1]
        @test ordered_host[1] == LocalMath.KeyedValue(Int32(7), Int32(91234))

        extremes, extremes_storage = _shared_keyed_program(backend, 2, Int32, 2,
            SignedExtremeKeyedReduceEvaluator();
            retention = LocalMath.RetainAllKeys())
        wait(LocalMath.execute!(extremes))
        extremes_host = collect(LocalMath.Adapt.adapt(
            Array, extremes_storage.records))[1:2]
        @test extremes_host == [
            LocalMath.KeyedValue(typemin(Int32), Int32(1)),
            LocalMath.KeyedValue(typemax(Int32), Int32(2)),
        ]

        overflow_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 1),
            Int32[9], Int32[4], 1)
        overflowing, overflow_storage = _shared_keyed_program(backend, 2,
            Int32, 1, OverflowKeyedReduceEvaluator();
            storage = overflow_storage)
        overflow_before = collect(LocalMath.Adapt.adapt(
            Array, overflow_storage.records))
        failure = _keyed_failure(LocalMath.execute!(overflowing))
        @test failure isa LocalMath.LocalMathValidationError
        @test failure.actual.failure_class === :capacity_overflow
        @test Array(overflow_storage.count) == Int32[1]
        @test collect(LocalMath.Adapt.adapt(
            Array, overflow_storage.records)) == overflow_before

        duplicate_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 2),
            Int32[4, 4], Int32[1, 2], 2)
        duplicate, duplicate_storage = _shared_keyed_program(backend, 0,
            Int32, 2, EmptyKeyedReduceEvaluator(); storage = duplicate_storage)
        duplicate_before = collect(LocalMath.Adapt.adapt(
            Array, duplicate_storage.records))
        failure = _keyed_failure(LocalMath.execute!(duplicate))
        @test failure isa LocalMath.LocalMathValidationError
        @test failure.actual.failure_class === :duplicate_key
        @test Array(duplicate_storage.count) == Int32[2]
        @test collect(LocalMath.Adapt.adapt(Array,
            duplicate_storage.records)) == duplicate_before

        count_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 1),
            Int32[8], Int32[5], -1)
        invalid_count, count_storage = _shared_keyed_program(backend, 0,
            Int32, 1, EmptyKeyedReduceEvaluator(); storage = count_storage)
        count_before = collect(LocalMath.Adapt.adapt(Array, count_storage.records))
        failure = _keyed_failure(LocalMath.execute!(invalid_count))
        @test failure isa LocalMath.LocalMathValidationError
        @test failure.actual.failure_class === :invalid_prior_count
        @test Array(count_storage.count) == Int32[-1]
        @test collect(LocalMath.Adapt.adapt(
            Array, count_storage.records)) == count_before

        rebuild_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 2),
            Int32[4, 4], Int32[6, 7], 2)
        rebuild, rebuild_storage = _shared_keyed_program(backend, 2,
            Int32, 2, OverflowKeyedReduceEvaluator();
            seed = LocalMath.RebuildFromIdentity(Int32(0)),
            storage = rebuild_storage)
        wait(LocalMath.execute!(rebuild))
        @test Array(rebuild_storage.count) == Int32[2]
        @test collect(LocalMath.Adapt.adapt(
            Array, rebuild_storage.records))[1:2] == [
                LocalMath.KeyedValue(Int32(1), Int32(1)),
                LocalMath.KeyedValue(Int32(2), Int32(1)),
            ]

        ordered_rebuild_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 4),
            Int32[8, 0, 0, 0], Int32[9, 0, 0, 0], 1)
        ordered_rebuild, ordered_rebuild_storage = _shared_keyed_program(
            backend, 2, Int32, 4, RebuildOrderedKeyedReduceEvaluator();
            operation = OrderedLaneDecimalFold(),
            seed = LocalMath.RebuildFromIdentity(Int32(0)),
            retention = LocalMath.RetainAllKeys(),
            storage = ordered_rebuild_storage)
        wait(LocalMath.execute!(ordered_rebuild))
        @test Array(ordered_rebuild_storage.count) == Int32[1]
        @test collect(LocalMath.Adapt.adapt(
            Array, ordered_rebuild_storage.records))[1] ==
                LocalMath.KeyedValue(Int32(3), Int32(12))
        incremental_peer, _ = _shared_keyed_program(
            backend, 2, Int32, 4, RebuildOrderedKeyedReduceEvaluator();
            operation = OrderedLaneDecimalFold(),
            seed = LocalMath.NewKeyIdentity(Int32(0)),
            retention = LocalMath.RetainAllKeys())
        rebuild_facts = LocalMath.inspect(ordered_rebuild)
        incremental_facts = LocalMath.inspect(incremental_peer)
        @test only(only(rebuild_facts.stages).publications).details.law.seed isa
            LocalMath.RebuildFromIdentity{Int32}
        @test LocalMath.lowering_identity(ordered_rebuild.plan) ===
            LocalMath.lowering_identity(incremental_peer.plan)
        @test only(rebuild_facts.planning.physical_segments).family ===
            only(incremental_facts.planning.physical_segments).family ===
            :sparse_keyed_sequence
        wait(LocalMath.execute!(rebuild))
        @test collect(LocalMath.Adapt.adapt(
            Array, rebuild_storage.records))[1:2] == [
                LocalMath.KeyedValue(Int32(1), Int32(1)),
                LocalMath.KeyedValue(Int32(2), Int32(1)),
            ]

        rebuild_overflow_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 1),
            Int32[9], Int32[4], 1)
        rebuild_overflow, rebuild_overflow_storage = _shared_keyed_program(
            backend, 2, Int32, 1, OverflowKeyedReduceEvaluator();
            seed = LocalMath.RebuildFromIdentity(Int32(0)),
            storage = rebuild_overflow_storage)
        rebuild_overflow_before = collect(LocalMath.Adapt.adapt(
            Array, rebuild_overflow_storage.records))
        failure = _keyed_failure(LocalMath.execute!(rebuild_overflow))
        @test failure isa LocalMath.LocalMathValidationError
        @test failure.actual.failure_class === :capacity_overflow
        @test Array(rebuild_overflow_storage.count) == Int32[1]
        @test collect(LocalMath.Adapt.adapt(Array,
            rebuild_overflow_storage.records)) == rebuild_overflow_before

        ignored_count_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 1),
            Int32[8], Int32[5], -1)
        ignored_count, ignored_count_storage = _shared_keyed_program(backend,
            0, Int32, 1, EmptyKeyedReduceEvaluator();
            seed = LocalMath.RebuildFromIdentity(Int32(0)),
            storage = ignored_count_storage)
        wait(LocalMath.execute!(ignored_count))
        @test Array(ignored_count_storage.count) == Int32[0]

        limit = LocalMath.Parameter(:limit, Int32;
            bounds = (Int32(0), Int32(2)))
        control_storage = _initialize_scalar_keyed_storage!(
            LocalMath.CompactedStorage(backend,
                LocalMath.KeyedValue{Int32,Int32}, 1),
            Int32[6], Int32[7], 1)
        invalid_control, control_storage = _shared_keyed_program(backend, 1,
            Int32, 1, OverflowKeyedReduceEvaluator(); parameters = (limit,),
            control = LocalMath.Control(prefix = limit), storage = control_storage)
        control_before = collect(LocalMath.Adapt.adapt(
            Array, control_storage.records))
        failure = _keyed_failure(LocalMath.execute!(invalid_control;
            parameters = (; limit = Int32(2))))
        @test failure isa LocalMath.LocalMathValidationError
        @test failure.actual.failure_class === :invalid_control
        @test Array(control_storage.count) == Int32[1]
        @test collect(LocalMath.Adapt.adapt(
            Array, control_storage.records)) == control_before
    end
end
