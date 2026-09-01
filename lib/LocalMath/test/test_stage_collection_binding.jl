using Test
import KernelAbstractions
import LocalMath
const LMCB = LocalMath

struct SCBNode end
struct SCBCollectEvaluator end
@inline (::SCBCollectEvaluator)(item::Int32, reads, parameters) =
    (records = LMCB.CollectedValue(item),)

struct SCBFoldEvaluator end
@inline (::SCBFoldEvaluator)(item::Int32, reads, parameters) =
    (step = LMCB.FoldValue(item),)
struct SCBFoldTransition end
@inline function (::SCBFoldTransition)(state, value::Int32, item::Int32, reads)
    writes = LMCB.BoundedWrites((Int32(1),),
        (@inbounds(state.accumulator[1]) + value,), Int32(1))
    return LMCB.FoldStep((accumulator = writes,))
end
struct SCBBadFoldTransition end
@inline function (::SCBBadFoldTransition)(state, value::Int32, item::Int32, reads)
    return LMCB.FoldStep((wrong = LMCB.BoundedWrites(Int32),))
end
struct SCBBadFoldValueTransition end
@inline function (::SCBBadFoldValueTransition)(state, value::Int32, item::Int32, reads)
    return LMCB.FoldStep((accumulator = LMCB.BoundedWrites(Float32),))
end

function _scb_storage(::Type{T}, capacity::Integer;
        groups = nothing, positions = nothing,
    ) where {T}
    LMCB.CompactedStorage(
        LMCB._CONSTRUCTION_TOKEN, zeros(T, capacity), zeros(Int32, 1),
        groups, zeros(Int32, capacity), zeros(Int32, capacity), positions,
    )
end

@testset "Collection and OrderedFold structural Stage boundary" begin
    backend = KernelAbstractions.CPU()
    allocated = LMCB.CompactedStorage(
        backend, Int32, 4; group_count = 2, source_position = true)
    @test length(allocated.records) == 4
    @test length(allocated.count) == 1
    @test length(allocated.segment_starts) == 3
    @test length(allocated.source_position) == 4
    nodes = LMCB.Space(SCBNode, 3)

    collection = LMCB.Collection(Int32, 4)
    collect_publication = LMCB.Publication((LMCB.CollectionPublication(
        collection, LMCB.PublicationValue(:records),
    ),), LMCB.Collect(Int32; maximum = 1))
    collect_stage = LMCB.Stage(
        nodes, NamedTuple(), (collect_publication,),
        LMCB.Evaluator(SCBCollectEvaluator()), LMCB.Control(),
        LMCB.SourceOrigin(:stage_collection_binding, 1),
    )
    collect_storage = _scb_storage(Int32, 4)
    collect_bound = LMCB._bind_law(
        LMCB.LocalLaw(collect_stage),
        LMCB._StructuralBinding((), (), (
            LMCB._collection_storage_binding(collection, collect_storage),
        )),
    )
    @test collect_bound.binding.collections[1].storage === collect_storage
    validated_collect_bound = LMCB._validate_bound_law(collect_bound)
    @test validated_collect_bound.binding.collection_slots ==
        (LMCB._CollectionSlot(1),)
    collect_projection = LMCB._stage_planning_entry(
        validated_collect_bound, 1).projection
    @test only(only(collect_projection.publications)).slot == LMCB._CollectionSlot(1)
    collect_admission = _test_stage_admission(collect_bound; backend)
    collect_prepared = only(collect_admission.stage.publications)
    @test only(collect_prepared.components).storage === collect_storage
    @test collect_prepared.law isa LMCB._PreparedCollectLaw{Int32,1}
    @test !hasproperty(only(collect_prepared.components), :collection)
    missing_collection_error = try
        LMCB._validate_bound_law(LMCB._bind_law(
            LMCB.LocalLaw(collect_stage), LMCB._StructuralBinding((), ()),
        ))
        nothing
    catch error
        error
    end
    @test missing_collection_error isa LMCB.LocalMathValidationError
    @test missing_collection_error.contract == :collection_resolution

    projected_collection = LMCB.Collection(Int32, 4)
    projected_publication = LMCB.Publication((LMCB.CollectionPublication(
        projected_collection, LMCB.PublicationValue(:records),
    ),), LMCB.Collect(
        Int32; maximum = 1,
        projection = LMCB._PersistentSourcePosition(),
    ))
    projected_stage = LMCB.Stage(
        nodes, NamedTuple(), (projected_publication,),
        LMCB.Evaluator(SCBCollectEvaluator()), LMCB.Control(),
        LMCB.SourceOrigin(:stage_collection_binding, 3),
    )
    projected_bound = LMCB._bind_law(
        LMCB.LocalLaw(projected_stage),
        LMCB._StructuralBinding((), (), (
            LMCB._collection_storage_binding(
                projected_collection, _scb_storage(Int32, 4),
            ),
        )),
    )
    projection_error = try
        _test_stage_admission(projected_bound; backend)
        nothing
    catch error
        error
    end
    @test projection_error isa LMCB.LocalMathValidationError
    @test projection_error.contract == :collect_storage_schema

    source = LMCB.Field(nodes, Int32)
    target = LMCB.Field(nodes, Int32)
    state = LMCB.InitializedState(
        accumulator = LMCB.FoldComponent(target; from = source),
    )
    fold_publication = LMCB.Publication((LMCB.FoldPublication(
        LMCB.PublicationValue(:step),
    ),), LMCB.OrderedFold(Int32, state, SCBFoldTransition()))
    fold_stage = LMCB.Stage(
        nodes, NamedTuple(), (fold_publication,),
        LMCB.Evaluator(SCBFoldEvaluator()), LMCB.Control(),
        LMCB.SourceOrigin(:stage_collection_binding, 2),
    )
    fold_bound = LMCB._bind_law(
        LMCB.LocalLaw(fold_stage),
        LMCB._StructuralBinding((
            LMCB._field_storage_binding(target, zeros(Int32, 3)),
            LMCB._field_storage_binding(source, Int32[1, 2, 3]),
        ), ()),
    )
    fold_projection = LMCB._stage_planning_entry(
        LMCB._validate_bound_law(fold_bound), 1).projection
    projected_state = only(only(fold_projection.publications)).components.accumulator
    @test projected_state.target isa LMCB._PreparedFieldSlot{1}
    @test projected_state.source isa LMCB._PreparedFieldSlot{2}
    fold_admission = _test_stage_admission(fold_bound; backend)
    fold_prepared = only(fold_admission.stage.publications)
    prepared_state = only(fold_prepared.components).state.components.accumulator
    @test prepared_state.target isa LMCB._PreparedFieldSlot{1}
    @test prepared_state.source isa LMCB._PreparedFieldSlot{2}
    @test fold_prepared.law isa LMCB._PreparedOrderedFoldLaw{Int32}
    @test !hasproperty(fold_prepared.law, :state)

    bad_fold_publication = LMCB.Publication((LMCB.FoldPublication(
        LMCB.PublicationValue(:step),
    ),), LMCB.OrderedFold(Int32, state, SCBBadFoldTransition()))
    bad_fold_stage = LMCB.Stage(
        nodes, NamedTuple(), (bad_fold_publication,),
        LMCB.Evaluator(SCBFoldEvaluator()), LMCB.Control(),
        LMCB.SourceOrigin(:stage_collection_binding, 4),
    )
    bad_fold_bound = LMCB._bind_law(
        LMCB.LocalLaw(bad_fold_stage), fold_bound.binding,
    )
    bad_transition_error = try
        _test_stage_admission(bad_fold_bound; backend)
        nothing
    catch error
        error
    end
    @test bad_transition_error isa LMCB.LocalMathValidationError
    @test bad_transition_error.contract == :ordered_fold_step_components

    bad_value_publication = LMCB.Publication((LMCB.FoldPublication(
        LMCB.PublicationValue(:step),
    ),), LMCB.OrderedFold(Int32, state, SCBBadFoldValueTransition()))
    bad_value_stage = LMCB.Stage(
        nodes, NamedTuple(), (bad_value_publication,),
        LMCB.Evaluator(SCBFoldEvaluator()), LMCB.Control(),
        LMCB.SourceOrigin(:stage_collection_binding, 5),
    )
    bad_value_bound = LMCB._bind_law(
        LMCB.LocalLaw(bad_value_stage), fold_bound.binding,
    )
    bad_value_error = try
        _test_stage_admission(bad_value_bound; backend)
        nothing
    catch error
        error
    end
    @test bad_value_error isa LMCB.LocalMathValidationError
    @test bad_value_error.contract == :ordered_fold_step_value_type

    control_source = LMCB.Field(nodes, Bool)
    control_target = LMCB.Field(nodes, Bool)
    subset_relation = LMCB.MaskedRelation(
        LMCB.IdentityRelation(nodes), control_source,
    )
    subset_state = LMCB.InitializedState(
        accumulator = LMCB.FoldComponent(control_target; from = control_source),
    )
    subset_publication = LMCB.Publication((LMCB.FoldPublication(
        LMCB.PublicationValue(:step),
    ),), LMCB.OrderedFold(Bool, subset_state, SCBFoldTransition()))
    subset_error = try
        LMCB.Stage(
            nodes, NamedTuple(), (subset_publication,),
            LMCB.Evaluator(SCBFoldEvaluator()),
            LMCB.Control(; subset = LMCB._SubsetSelection(subset_relation)),
            LMCB.SourceOrigin(:stage_collection_binding, 6),
        )
        nothing
    catch error
        error
    end
    @test subset_error isa LMCB.LocalMathValidationError
    @test subset_error.contract == :ordered_fold_source_control_alias
end
