using Test
import LocalMath
const LMF = LocalMath

struct OrderedFoldStageModelNode end
struct OrderedFoldStageEvaluator end
@inline (::OrderedFoldStageEvaluator)(item::Int32, reads, parameters) =
    (event = LMF.FoldValue(item),)
struct OrderedFoldStageTransition end
@inline function (::OrderedFoldStageTransition)(state, value, item, reads)
    return LMF.FoldStep((accumulator = LMF.BoundedWrites(
        (Int32(1),), (value,), Int32(1)),))
end

@testset "OrderedFold is a terminal typed recurrence Stage law" begin
    source = LMF.Space(OrderedFoldStageModelNode, 5)
    state_space = LMF.Space(OrderedFoldStageModelNode, 2)
    initial = LMF.Field(state_space, Int32)
    accumulator = LMF.Field(state_space, Int32)
    state = LMF.InitializedState(; accumulator =
        LMF.FoldComponent(accumulator; from = initial))
    law = LMF.OrderedFold(
        Int32, state, OrderedFoldStageTransition();
        order = LMF._SourceOrder())
    publication = LMF.Publication((LMF.FoldPublication(
        LMF.PublicationValue(:event)),), law)
    stage = LMF.Stage(source, NamedTuple(), (publication,),
        LMF.Evaluator(OrderedFoldStageEvaluator()), LMF.Control(),
        LMF.SourceOrigin(:ordered_fold_stage_model_test, 1))

    @test only(stage.publications).law === law
    @test only(values(law.state.components)).target === accumulator
    @test only(values(law.state.components)).source === initial
    @test LMF._publication_width(law) == 1
    @test isnothing(LMF._validate_evaluator_result_type(
        stage.publications,
        NamedTuple{(:event,),Tuple{LMF.FoldValue{Int32}}},
    ))

    other = LMF.Collection(Int32, 1)
    collect = LMF.Publication((LMF.CollectionPublication(
        other, LMF.PublicationValue(:other)),), LMF.Collect(Int32))
    @test_throws LMF.LocalMathValidationError LMF.Stage(
        source, NamedTuple(), (publication, collect),
        LMF.Evaluator(OrderedFoldStageEvaluator()), LMF.Control(),
        LMF.SourceOrigin(:ordered_fold_stage_model_test, 2))
end
