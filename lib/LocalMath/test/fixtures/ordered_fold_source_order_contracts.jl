using Test
import KernelAbstractions
import LocalMath

struct OrderedFoldSourceOrderDomain end
struct OrderedFoldSourceOrderEvaluator end

struct OrderedFoldCanonicalKey end
@inline (::OrderedFoldCanonicalKey)(value::Int32) = value
struct OrderedFoldCanonicalIdentity end
@inline (::OrderedFoldCanonicalIdentity)(value::Int32) = value
struct AlternateOrderedFoldCanonicalKey end
@inline (::AlternateOrderedFoldCanonicalKey)(value::Int32) = value
struct AlternateOrderedFoldCanonicalIdentity end
@inline (::AlternateOrderedFoldCanonicalIdentity)(value::Int32) = value

@inline function (::OrderedFoldSourceOrderEvaluator)(item::Int32, reads, parameters)
    return (event = LocalMath.FoldValue(
        item, something(reads[1][1].value)),)
end

struct OrderedFoldSourceOrderTrace
    halt_at::Int32
    invalid_at::Int32
end

@inline function (transition::OrderedFoldSourceOrderTrace)(
        state, value, item, reads)
    destination = item == transition.invalid_at ? Int32(2) : Int32(1)
    next = state.result[Int32(1)] * Int32(10) + value
    return LocalMath.FoldStep((result = LocalMath.BoundedWrites(
        (destination,), (next,), Int32(1)),);
        halt = item == transition.halt_at)
end

function _ordered_fold_source_order_prepared(
        array_type, selected_values, emitted_values;
        selection::Symbol, halt_at::Int32 = Int32(0),
        invalid_at::Int32 = Int32(0), order = LocalMath.source_order())
    n = length(selected_values)
    source = LocalMath.Space(OrderedFoldSourceOrderDomain, n)
    singleton = LocalMath.Space(OrderedFoldSourceOrderDomain, 1)
    selected = LocalMath.Field(source, Bool)
    emitted = LocalMath.Field(source, Bool)
    initial = LocalMath.Field(singleton, Int32)
    result = LocalMath.Field(singleton, Int32)
    identity_relation = LocalMath.IdentityRelation(source)
    control = selection === :mask ? LocalMath.Control(; mask = selected) :
        selection === :subset ? LocalMath.Control(; subset =
            LocalMath.MaskedRelation(identity_relation, selected)) :
        error("unknown source-order selection")
    state = LocalMath.initialized_state(;
        result = LocalMath.FoldComponent(result; from = initial))
    publication = LocalMath.Publication((LocalMath.FoldPublication(
        LocalMath.PublicationValue(:event)),), LocalMath.OrderedFold(
            Int32, state,
            OrderedFoldSourceOrderTrace(halt_at, invalid_at); order))
    stage = LocalMath.Stage(
        source,
        (emitted = LocalMath.Access(emitted, identity_relation;
            required = true),),
        (publication,), LocalMath.Evaluator(OrderedFoldSourceOrderEvaluator()),
        control,
        LocalMath.SourceOrigin(
            @__FILE__, @__LINE__; label = :source_order_direct_traversal))
    selected_storage = array_type(selected_values)
    emitted_storage = array_type(emitted_values)
    destination = array_type(Int32[91])
    prepared = LocalMath.prepare(
        LocalMath.LocalLaw(stage),
        selected => selected_storage,
        emitted => emitted_storage,
        initial => array_type(Int32[0]), result => destination;
        backend = KernelAbstractions.get_backend(destination))
    return (; prepared, destination)
end

function _ordered_fold_source_order_execute(prepared)
    return try
        wait(LocalMath.execute!(prepared))
        nothing
    catch error
        error
    end
end

function ordered_fold_source_order_contracts(array_type)
    return @testset "source-order direct traversal preserves sparse semantics" begin
        selected = Bool[false, true, true, false, true, false, true]
        emitted = Bool[true, true, false, true, true, true, true]
        for selection in (:mask, :subset)
            witness = _ordered_fold_source_order_prepared(
                array_type, selected, emitted; selection)
            @test _ordered_fold_source_order_execute(witness.prepared) === nothing
            @test Array(witness.destination) == Int32[257]
            facts = LocalMath.inspect(witness.prepared)
            phases = map(phase -> phase.kind,
                only(facts.stages).planning.phases)
            @test :ordered_fold_bitonic ∉ phases
            @test facts.planning.base_provider_launch_count == 6

            halted = _ordered_fold_source_order_prepared(
                array_type, selected, emitted; selection,
                halt_at = Int32(5))
            @test _ordered_fold_source_order_execute(halted.prepared) === nothing
            @test Array(halted.destination) == Int32[25]

            rejected = _ordered_fold_source_order_prepared(
                array_type, selected, emitted; selection,
                invalid_at = Int32(7))
            failure = _ordered_fold_source_order_execute(rejected.prepared)
            @test failure isa LocalMath.LocalMathValidationError
            @test failure.contract === :runtime_ordered_fold_validation
            @test failure.actual.failure_class === :invalid_destination
            @test failure.actual.source_item == Int32(7)
            @test failure.actual.canonical_position == Int32(3)
            @test failure.actual.witness == Int32(2)
            @test Array(rejected.destination) == Int32[91]
        end

        empty = _ordered_fold_source_order_prepared(
            array_type, Bool[], Bool[]; selection = :mask)
        @test _ordered_fold_source_order_execute(empty.prepared) === nothing
        @test Array(empty.destination) == Int32[0]
        @test LocalMath.inspect(empty.prepared).planning.base_provider_launch_count == 6

        canonical = _ordered_fold_source_order_prepared(
            array_type, trues(7), trues(7); selection = :mask,
            order = LocalMath.canonical_by(
                OrderedFoldCanonicalKey(), OrderedFoldCanonicalIdentity()))
        @test _ordered_fold_source_order_execute(canonical.prepared) === nothing
        @test Array(canonical.destination) == Int32[1234567]
        canonical_facts = LocalMath.inspect(canonical.prepared)
        canonical_phases = map(phase -> phase.kind,
            only(canonical_facts.stages).planning.phases)
        @test :ordered_fold_bitonic in canonical_phases
        @test canonical_facts.planning.base_provider_launch_count == 12

        alternate_canonical = _ordered_fold_source_order_prepared(
            array_type, trues(7), trues(7); selection = :mask,
            order = LocalMath.canonical_by(
                AlternateOrderedFoldCanonicalKey(),
                AlternateOrderedFoldCanonicalIdentity()))
        @test _ordered_fold_source_order_execute(
            alternate_canonical.prepared) === nothing
        @test Array(alternate_canonical.destination) == Int32[1234567]
        alternate_facts = LocalMath.inspect(alternate_canonical.prepared)
        @test only(alternate_facts.stages).planning.phases ==
            only(canonical_facts.stages).planning.phases
        @test alternate_facts.planning.base_provider_launch_count ==
            canonical_facts.planning.base_provider_launch_count
    end
end
