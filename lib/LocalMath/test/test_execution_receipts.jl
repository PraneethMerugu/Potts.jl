using Test
import LocalMath
const LWER = LocalMath

struct ReceiptProviderFailureEvaluator end
@inline function (::ReceiptProviderFailureEvaluator)(
        item::Int32, reads, parameters)
    item == Int32(0) && return (value = LWER.UniqueValue(item),)
    error("intentional provider execution failure")
end

function _receipt_test_conflict_preparation(; dependency_arity::Int = 0)
    source = LWER.Space(ReceiptTestNode, 2)
    destination = LWER.Space(ReceiptTestNode, 1)
    output = LWER.Field(destination, Int32)
    collision = LWER.FixedRelation(source => destination; degree = 1)
    publication = LWER.Publication((LWER.FieldPublication(
        output, collision, LWER.PublicationValue(:value)),),
        LWER.Unique(Int32))
    stage = LWER.Stage(source, NamedTuple(), (publication,),
        LWER.Evaluator(ReceiptTestEvaluator(Int32(7))), LWER.Control(),
        LWER.SourceOrigin(:execution_receipt_conflict, 1))
    storage = Int32[91]
    bound = LWER._bind_law(LWER.LocalLaw(stage),
        LWER._StructuralBinding(
            (LWER._field_storage_binding(output, storage),),
            (LWER._relation_storage_binding(collision, (
                endpoints = reshape(Int32[1, 1], 1, 2),
                counts = Int32[1, 1])),)))
    backend = LWER.KernelAbstractions.get_backend(storage)
    prepared = LWER.prepare(LWER.plan(bound; backend); dependency_arity)
    return prepared, storage
end

function _warm_receipt_bookkeeping_bytes(prepared, dependencies)
    wait(LWER.execute!(prepared; dependencies))
    return @allocated wait(LWER.execute!(prepared; dependencies))
end

@testset "logical receipts admit exact dependency arities" begin
    root_a, storage_a = _receipt_test_preparation(Int32(10))
    root_b, storage_b = _receipt_test_preparation(Int32(20))
    unary, storage_1 = _receipt_test_preparation(Int32(30);
        dependency_arity = 1)
    binary, storage_2 = _receipt_test_preparation(Int32(40);
        dependency_arity = 2)
    quaternary, storage_4 = _receipt_test_preparation(Int32(50);
        dependency_arity = 4)
    wide, storage_17 = _receipt_test_preparation(Int32(55);
        dependency_arity = 17)

    event_a = LWER.execute!(root_a)
    @test !applicable(LWER.execute!, root_a, (;))
    event_b = LWER.execute!(root_b; dependencies = ())
    event_1 = LWER.execute!(unary; dependencies = (event_a,))
    event_2 = LWER.execute!(binary; dependencies = (event_a, event_1))
    event_4 = LWER.execute!(quaternary;
        dependencies = (event_a, event_b, event_1, event_2))
    event_17 = LWER.execute!(wide;
        dependencies = ntuple(_ -> event_a, 17))

    @test typeof(root_a) === typeof(unary) === typeof(binary) ===
        typeof(quaternary) === typeof(wide)
    @test !isdefined(LWER, :_ReceiptDependencyBundle)

    @test map(event -> length(event.dependencies),
        (event_a, event_1, event_2, event_4, event_17)) ==
        (0, 1, 2, 4, 17)
    @test event_a.scope_ordinal < event_1.scope_ordinal <
        event_2.scope_ordinal < event_4.scope_ordinal
    @test_throws LWER.LocalMathValidationError LWER.execute!(unary)
    @test unary.submitted == UInt64(1)

    wait(event_4)
    @test storage_a == Int32[11, 12]
    @test storage_b == Int32[21, 22]
    @test storage_1 == Int32[31, 32]
    @test storage_2 == Int32[41, 42]
    @test storage_4 == Int32[51, 52]
    wait(event_17)
    @test storage_17 == Int32[56, 57]
    @test !LWER.ispending(event_4)
    @test LWER.ispending(event_a)

    completions =
        LWER.inspect(quaternary).realized.state.provider_scope_completions
    LWER.waitall(event_a, event_b, event_1, event_2)
    @test LWER.inspect(quaternary).realized.state.provider_scope_completions ==
        completions
    @test all(prepared -> LWER.submission_capacity(prepared).outstanding == 0,
        (root_a, root_b, unary, binary, quaternary, wide))
    wait(event_a)
    @test LWER.inspect(quaternary).realized.state.provider_scope_completions ==
        completions

    compatible, _ = _receipt_test_preparation(Int32(35);
        dependency_arity = 1)
    @test typeof(compatible) === typeof(unary)
    @test LWER.inspect(event_1).dependency_join_count == Int32(1)
    @test LWER.inspect(event_2).dependency_join_count == Int32(2)
    @test LWER.inspect(event_4).dependency_join_count == Int32(4)
    @test LWER.inspect(event_17).dependency_join_count == Int32(17)
    dependency_facts = only(LWER.inspect(event_1).dependencies)
    @test dependency_facts.state === :success
    @test dependency_facts.failure === nothing
    @test keys(dependency_facts) ==
        (:serial, :scope_ordinal, :state, :failure)
    join_arguments = Tuple{typeof(unary.runtime.execution_gate), Int32,
        typeof(unary.runtime.execution_gate), Int32}
    compatible_join_arguments = Tuple{
        typeof(compatible.runtime.execution_gate), Int32,
        typeof(compatible.runtime.execution_gate), Int32}
    @test join_arguments === compatible_join_arguments
    stage_arguments = Tuple{typeof(only(unary.runtime.launches)), Tuple{},
        Tuple{typeof(unary.runtime.execution_gate)}, Int32}
    compatible_stage_arguments = Tuple{
        typeof(only(compatible.runtime.launches)), Tuple{},
        Tuple{typeof(compatible.runtime.execution_gate)}, Int32}
    @test Base.method_instance(LWER._enqueue_stage!, stage_arguments) ===
        Base.method_instance(
            LWER._enqueue_stage!, compatible_stage_arguments)

    settled, settled_storage = _receipt_test_preparation(Int32(70);
        dependency_arity = 1)
    settled_event = LWER.execute!(settled; dependencies = (event_a,))
    @test LWER.inspect(settled_event).dependency_join_count == Int32(0)
    wait(settled_event)
    @test settled_storage == Int32[71, 72]

    warm_zero, _ = _receipt_test_preparation(Int32(90); lease_capacity = 1)
    zero_bytes = _warm_receipt_bookkeeping_bytes(warm_zero, ())
    warm_four, _ = _receipt_test_preparation(Int32(100);
        dependency_arity = 4, lease_capacity = 1)
    four_dependencies = (event_a, event_b, event_1, event_2)
    four_bytes = _warm_receipt_bookkeeping_bytes(
        warm_four, four_dependencies)
    @test zero_bytes <= 1024
    @test four_bytes <= 1024
end

@testset "status copies complete one shared provider scope" begin
    root, root_storage = _receipt_test_preparation(Int32(110))
    dependent, dependent_storage = _receipt_test_preparation(Int32(120);
        dependency_arity = 4)
    root_event = LWER.execute!(root)
    dependent_event = LWER.execute!(dependent;
        dependencies = ntuple(_ -> root_event, 4))
    root_before = LWER.inspect(root).realized.state
    dependent_before = LWER.inspect(dependent).realized.state

    wait(dependent_event)

    root_after = LWER.inspect(root).realized.state
    dependent_after = LWER.inspect(dependent).realized.state
    @test root_storage == Int32[111, 112]
    @test dependent_storage == Int32[121, 122]
    @test root_after.validation_transfers ==
        root_before.validation_transfers + 1
    @test dependent_after.validation_transfers ==
        dependent_before.validation_transfers + 1
    @test dependent_after.provider_scope_completions ==
        dependent_before.provider_scope_completions + 1

    first, first_storage = _receipt_test_preparation(Int32(130))
    second, second_storage = _receipt_test_preparation(Int32(140))
    first_event = LWER.execute!(first)
    second_event = LWER.execute!(second)
    @test first_event.scope_ordinal < second_event.scope_ordinal
    first_before = LWER.inspect(first).realized.state
    second_before = LWER.inspect(second).realized.state

    LWER.waitall(second_event, first_event)

    first_after = LWER.inspect(first).realized.state
    second_after = LWER.inspect(second).realized.state
    @test first_storage == Int32[131, 132]
    @test second_storage == Int32[141, 142]
    @test first_after.validation_transfers ==
        first_before.validation_transfers + 1
    @test second_after.validation_transfers ==
        second_before.validation_transfers + 1
    @test second_after.provider_scope_completions ==
        second_before.provider_scope_completions + 1
end

@testset "only same-scope unresolved dependencies reach recursive settlement" begin
    published = Channel{Any}(1)
    release = Channel{Nothing}(1)
    producer_task = @async begin
        producer, producer_storage = _receipt_test_preparation(Int32(150))
        producer_event = LWER.execute!(producer)
        put!(published, producer_event)
        take!(release)
        wait(producer_event)
        producer_storage
    end
    producer_event = take!(published)
    consumer, consumer_storage = _receipt_test_preparation(Int32(160);
        dependency_arity = 1)

    rejection = try
        LWER.execute!(consumer; dependencies = (producer_event,))
        nothing
    catch error
        error
    end
    @test rejection isa LWER.LocalMathValidationError
    @test rejection.contract === :execution_dependency_scope
    @test rejection.actual === :unresolved_cross_scope
    @test consumer.submitted == 0

    put!(release, nothing)
    @test fetch(producer_task) == Int32[151, 152]
    consumer_event = LWER.execute!(consumer;
        dependencies = (producer_event,))
    wait(consumer_event)
    @test consumer_storage == Int32[161, 162]
end

@testset "receipt failures are exact, cached, and dependency-local" begin
    failing, failing_storage = _receipt_test_conflict_preparation()
    dependent, dependent_storage = _receipt_test_preparation(Int32(60);
        dependency_arity = 1)
    failed = LWER.execute!(failing)
    child = LWER.execute!(dependent; dependencies = (failed,))

    child_error = try
        LWER.waitall(child, failed)
        nothing
    catch error
        error
    end
    @test child_error isa LWER.LocalMathValidationError
    @test child_error.contract === :execution_dependency
    @test child_error.origin ==
        LWER.SourceOrigin(:execution_receipt_conflict, 1)
    @test dependent_storage == fill(Int32(-1), 2)
    @test failing_storage == Int32[91]

    failure = try
        LWER.waitall(failed, child)
        nothing
    catch error
        error
    end
    @test failure isa LWER.LocalMathValidationError
    @test failure.contract === :runtime_stage_validation
    @test failure.origin ==
        LWER.SourceOrigin(:execution_receipt_conflict, 1)
    cached_failure = try
        wait(failed)
        nothing
    catch error
        error
    end
    @test cached_failure === failure
    @test LWER.submission_capacity(failing).outstanding == 0
    @test LWER.submission_capacity(dependent).outstanding == 0
    producer_summary = only(LWER.inspect(child).dependencies)
    @test producer_summary.state === :semantic_failure
    @test producer_summary.failure === failure

    rejected, _ = _receipt_test_preparation(Int32(70);
        dependency_arity = 1)
    @test_throws LWER.LocalMathValidationError LWER.execute!(rejected;
        dependencies = (failed,))
    @test rejected.submitted == 0

    healthy, healthy_storage = _receipt_test_preparation(Int32(80))
    wait(LWER.execute!(healthy))
    @test healthy_storage == Int32[81, 82]
end

@testset "validation settlement rejects an unprepared stage reference" begin
    prepared, _ = _receipt_test_preparation(Int32(90))
    receipt = LWER.execute!(prepared)
    status = prepared.runtime.execution_gate
    lease_index = receipt.lease_index
    @inbounds begin
        status[LWER._VALIDATION_FAILURE_CLASS, lease_index] = UInt32(1)
        status[LWER._VALIDATION_STAGE_INDEX, lease_index] =
            reinterpret(UInt32, Int32(typemax(Int32)))
    end

    failure = try
        wait(receipt)
        nothing
    catch error
        error
    end
    @test failure isa LWER.LocalMathValidationError
    @test failure.contract === :validation_status_stage
    @test failure.stage === :wait
    @test failure.actual == (
        recorded_stage = typemax(Int32),
        failure_class = Int32(1),
    )
    @test !LWER.ispending(receipt)
    @test LWER.submission_capacity(prepared).outstanding == 0
    cached_failure = try
        wait(receipt)
        nothing
    catch error
        error
    end
    @test cached_failure === failure
end

@testset "provider failures poison only their provider scope" begin
    facts = fetch(@async begin
        failing, _ = _receipt_test_preparation(Int32(0);
            evaluator = ReceiptProviderFailureEvaluator())
        same_scope, _ = _receipt_test_preparation(Int32(5))
        first_error = try
            LWER.execute!(failing)
            nothing
        catch error
            error
        end
        second_error = try
            LWER.execute!(same_scope)
            nothing
        catch error
            error
        end
        (; first_error, second_error,
            failing_poisoned = failing.poisoned,
            same_scope_submitted = same_scope.submitted)
    end)
    @test facts.first_error !== nothing
    @test facts.first_error isa LWER.LocalMathValidationError
    @test facts.first_error.contract === :stage_enqueue
    @test facts.first_error.origin ==
        LWER.SourceOrigin(:execution_receipt_test, 1)
    @test facts.second_error !== nothing
    @test facts.failing_poisoned
    @test facts.same_scope_submitted == 0
end
