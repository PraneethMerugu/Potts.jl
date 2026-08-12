@testset "narrow package API and explicit SPIs" begin
    expected = Set((
        :CorePotts,
        :CompilerSPI,
        :BackendSPI,
        :LocalWorksets,
        :ProgramInitialState,
        :ProgramSnapshot,
        :ProgramRuntime,
        :ProgramFailureReport,
        :program_failed,
        :program_failure_report,
        :ProgramSettlementReceipt,
        :initialize_program,
        :program_snapshot,
        :advance_mcs!,
        :update_program_parameters!,
        :program_execution_report,
        :program_capability_report,
        :ProgramCheckpoint,
        :program_checkpoint,
        :restore_program_checkpoint,
        :CellIdentity,
        :QualifiedLifecycleRequestIdentity,
        :AbstractLifecycleEvent,
        :LifecycleEvent,
        :LifecycleReceipt,
        :MaybeLifecycleReceipt,
        :CreateLifecycleEvent,
        :RemoveCellLifecycleEvent,
        :RetireLifecycleEvent,
        :TransitionLifecycleEvent,
        :DivideLifecycleEvent,
        :ParentBeforeIdentity,
        :ParentAfterIdentity,
        :DaughterAfterIdentity,
        :lifecycle_request_identity,
        :lifecycle_events,
        :validate_lifecycle_receipt,
        :program_lifecycle_receipt,
    ))
    @test Set(names(CorePotts)) == expected
    @test CorePotts.LocalWorksets === LocalWorksets

    @test CorePotts.CompilerSPI.CompiledPottsProgram ===
          CorePotts.CompiledPottsProgram
    @test CorePotts.CompilerSPI.operation_callable ===
          CorePotts.operation_callable
    @test CorePotts.BackendSPI.SequentialProgramEngine ===
          CorePotts.SequentialProgramEngine
    @test CorePotts.BackendSPI.ProgramCapabilityReport ===
          CorePotts.ProgramCapabilityReport

    @test !Base.ispublic(CorePotts, :CompiledPottsProgram)
    @test !Base.ispublic(CorePotts, :SequentialProgramEngine)
    @test !Base.ispublic(CorePotts, :stage_program_descriptor_state!)
    @test Base.ispublic(CorePotts.CompilerSPI, :CompiledPottsProgram)
    @test Base.ispublic(CorePotts.BackendSPI, :SequentialProgramEngine)
    @test Base.ispublic(
        CorePotts.BackendSPI, :validate_program_checkpoint
    )
    @test Base.ispublic(
        CorePotts.BackendSPI, :stage_program_descriptor_state!
    )
end
