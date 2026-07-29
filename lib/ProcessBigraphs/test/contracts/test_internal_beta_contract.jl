using CommonSolve
using SciMLBase

@testset "internal-beta dependency and extension boundary" begin
    @test isdefined(ProcessBigraphs, :AlgebraicRewriting)
    @test :AlgebraicRewriting ∉ names(ProcessBigraphs)
    @test :SciMLBase ∉ names(ProcessBigraphs; all=true)
    @test :CommonSolve ∉ names(ProcessBigraphs; all=true)

    extension_module =
        Base.get_extension(ProcessBigraphs, :ProcessBigraphsSciMLExt)
    @test !isnothing(extension_module)
    @test extension_module.CONTRACT_VERSION ==
          "process-bigraphs-sciml-extension-v2"

    qualified_exports = Set(Symbol[
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
    ])
    @test intersect(qualified_exports, Set(names(ProcessBigraphs))) ==
          qualified_exports
    @test all(name -> Base.ispublic(ProcessBigraphs, name),
        qualified_exports)
    engine_extension_names = setdiff(qualified_exports, Set(Symbol[
        :FieldDescriptor,
        :FieldGeometry,
        :FieldBoundary,
        :FieldState,
    ]))
    @test all(name -> !Base.isexported(ProcessBigraphs, name),
        engine_extension_names)
    @test Base.isexported(ProcessBigraphs, :managed_field_process)
    @test !Base.ispublic(
        ProcessBigraphs, :ManagedFieldAdvanceProcess)

    reserved_exports = Set(Symbol[
        :StructuralRequest,
        :StructuralResult,
    ])
    @test isempty(intersect(reserved_exports, Set(names(ProcessBigraphs))))

    @test ProcessBigraphs.LogicalCheckpointV3 === CoupledLogicalCheckpoint
    @test ProcessBigraphs.RestoredPhase16Checkpoint === RestoredLogicalCheckpoint
    @test ProcessBigraphs.phase16_checkpoint === capture_logical_checkpoint
    @test ProcessBigraphs.decode_phase16_checkpoint === decode_logical_checkpoint
    @test ProcessBigraphs.restore_phase16_checkpoint === restore_logical_checkpoint
    @test ProcessBigraphs.PHASE16_CHECKPOINT_VERSION ==
          ProcessBigraphs.COUPLED_CHECKPOINT_FORMAT_VERSION
    @test ProcessBigraphs.PHASE16_CHECKPOINT_SCHEMA ==
          ProcessBigraphs.COUPLED_CHECKPOINT_SCHEMA
end
