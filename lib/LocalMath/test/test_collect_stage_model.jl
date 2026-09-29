using Test
import LocalMath
const LMC = LocalMath

struct CollectStageModelNode end
struct CollectStageModelEvaluator end
@inline (::CollectStageModelEvaluator)(item::Int32, reads, parameters) =
    (records = (
        LMC.CollectedValue(item),
        LMC.CollectedValue(item + Int32(10), isodd(item)),
    ),)

@testset "Collect is a bounded finite-sequence Stage law" begin
    source = LMC.Space(CollectStageModelNode, 3)
    collection = LMC.Collection(Int32, 4)
    law = LMC.Collect(Int32; maximum = 2,
        groups = LMC._OneGroup(), order = LMC._SourceOrder())
    publication = LMC.Publication((LMC.CollectionPublication(
        collection, LMC.PublicationValue(:records)),), law)
    stage = LMC.Stage(source, NamedTuple(), (publication,),
        LMC.Evaluator(CollectStageModelEvaluator()), LMC.Control(),
        LMC.SourceOrigin(:collect_stage_model_test, 1))

    @test only(stage.publications).law === law
    @test only(only(stage.publications).components).collection === collection
    @test LMC._publication_width(law) == 2
    @test LMC._publication_value_type(law) === Int32
    @test isnothing(LMC._validate_evaluator_result_type(
        stage.publications,
        NamedTuple{(:records,),Tuple{Tuple{
            LMC.CollectedValue{Int32},LMC.CollectedValue{Int32}}}},
    ))

    @test_throws LMC.LocalMathValidationError LMC.Publication((
        LMC.CollectionPublication(
            LMC.Collection(Float32, 4), LMC.PublicationValue(:records)),
    ), law)
    @test_throws LMC.LocalMathValidationError LMC.Stage(
        source, NamedTuple(), (publication, publication),
        LMC.Evaluator(CollectStageModelEvaluator()), LMC.Control(),
        LMC.SourceOrigin(:collect_stage_model_test, 2))
end
