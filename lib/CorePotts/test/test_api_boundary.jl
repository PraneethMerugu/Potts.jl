@testset "narrow package API and explicit SPIs" begin
    expected = Set((
        :CorePotts,
        :CompilerSPI,
        :BackendSPI,
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
    @test !Base.ispublic(CorePotts, :LocalMath)

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
    @test all((
            :OwnershipTrackerSource,
            :AcceptedCommitTrackerVisibility,
            :ClaimedOwnerExclusiveTrackerConcurrency,
            :SourceTargetOwnerUpdateBound,
            :PersistTrackerCheckpoint,
            :ReconstructTrackerCheckpoint,
            :TrackerSupport,
            :ConstantTrackerCost,
            :LatticeLinearTrackerCost,
            :OwnerScalarDelta,
            :SourceTargetScalarDelta,
            :tracker_rebuild,
            :tracker_recompute,
            :tracker_proposal_delta,
        )) do name
        Base.ispublic(CorePotts.CompilerSPI, name)
    end

    compiler_names = Set(
        names(
            CorePotts.CompilerSPI; all = false, imported = false
        )
    )
    backend_names = Set(
        names(
            CorePotts.BackendSPI; all = false, imported = false
        )
    )
    @test isempty(intersect(compiler_names, backend_names))
    @test isempty(Base.Docs.undocumented_names(
        CorePotts.CompilerSPI; private = false
    ))
    for (spi, spi_names) in (
            (CorePotts.CompilerSPI, compiler_names),
            (CorePotts.BackendSPI, backend_names),
        )
        @test all(spi_names) do name
            isdefined(CorePotts, name) &&
                getfield(spi, name) === getfield(CorePotts, name)
        end
    end
end

@testset "every public CorePotts binding owns help" begin
    for module_value in (
            CorePotts,
            CorePotts.CompilerSPI,
            CorePotts.BackendSPI,
        )
        public_names = filter(
            name -> Base.ispublic(module_value, name) &&
                    !startswith(String(name), "#"),
            names(module_value; all = true),
        )
        undocumented = filter(
            name -> !Docs.hasdoc(module_value, name), public_names
        )
        @test isempty(undocumented)
    end
end
