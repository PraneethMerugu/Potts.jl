using CommonSolve
using SciMLBase

@testset "Phase 16.A dependency and extension boundary" begin
    @test isdefined(ProcessBigraphs, :AlgebraicRewriting)
    @test :AlgebraicRewriting ∉ names(ProcessBigraphs)
    @test :SciMLBase ∉ names(ProcessBigraphs; all=true)
    @test :CommonSolve ∉ names(ProcessBigraphs; all=true)

    extension_module =
        Base.get_extension(ProcessBigraphs, :ProcessBigraphsSciMLExt)
    @test !isnothing(extension_module)
    @test extension_module.CONTRACT_VERSION ==
          "process-bigraphs-sciml-extension-v1"

    planned = Set(Symbol[
        :AbstractEngineAdapter,
        :AbstractEngineInstance,
        :EngineDeclaration,
        :EngineCapabilities,
        :AbstractEngineOperation,
        :IntervalAdvance,
        :BoundarySolve,
        :DiscreteBatch,
        :EngineInvocation,
        :AbstractCompletionHandle,
        :EngineCandidate,
        :EngineEarlyReturn,
        :EngineEventRequest,
        :EngineFailure,
        :FieldDescriptor,
        :FieldGeometry,
        :FieldBoundary,
        :FieldState,
        :StructuralRequest,
        :StructuralResult,
    ])
    @test isempty(intersect(planned, Set(names(ProcessBigraphs))))
end
