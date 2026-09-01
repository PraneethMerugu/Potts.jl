empty_descriptor_plan() = CorePotts.DescriptorExecutionPlan(
    (),
    CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
    CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
    (),
    Any[],
    Int32(0),
    "empty-descriptor-plan-v1",
    CorePotts.HamiltonianDomainResources(0, 0),
)

function test_program(
        engine;
        relationships = (),
        temperature = 3,
        descriptor_plan = empty_descriptor_plan(),
        stage_plan = CorePotts.StageExecutionPlan(),
        attempts_per_site = 1,
        tracker_plan = CorePotts.TrackerExecutionPlan(
            (CorePotts.OwnershipCountTracker(),),
            "ownership-count-tracker-v1-test",
        ),
        ownership_change_handles = (),
        lifecycle_plan = CorePotts.NoLifecycleExecutionPlan(),
        parameter_defaults = Float64[],
        scalar_type = Float64,
    )
    T = scalar_type
    scalar(value) = CorePotts.CompiledScalar(T(value))
    offsets = Int8[
        1 -1 0 0
        0 0 1 -1
    ]
    checkerboard_plan = engine isa CorePotts.CheckerboardProgramEngine ?
        CorePotts.CheckerboardPlan((6, 6), (true, true), offsets) :
        CorePotts.NoCheckerboardPlan()
    return CorePotts.CompiledPottsProgram(
        (6, 6),
        (true, true),
        offsets,
        2,
        1,
        scalar(temperature),
        attempts_per_site,
        T.(parameter_defaults),
        relationships,
        tracker_plan,
        descriptor_plan,
        stage_plan,
        engine,
        CorePotts.CPUProgramBackend(),
        "core-program-v1-test";
        checkerboard_plan,
        ownership_change_handles,
        lifecycle_plan,
    )
end

function test_initial(scalar_type = Float64)
    ownership = zeros(Int32, 6, 6)
    ownership[3:4, 3:4] .= 1
    return CorePotts.ProgramInitialState(
        ownership, Int16[2]; scalar_type
    )
end

function capability_test_program(
        program::CorePotts.CompiledPottsProgram;
        backend = program.backend,
        scalar_type = eltype(program.parameter_defaults),
        tracker_plan = program.tracker_plan,
        descriptor_plan = program.descriptor_plan,
        stage_plan = program.stage_plan,
        relationships = program.relationships,
    )
    T = scalar_type
    checkerboard_plan = program.engine isa CorePotts.CheckerboardProgramEngine ?
                        program.checkerboard_plan : CorePotts.NoCheckerboardPlan()
    return CorePotts.CompiledPottsProgram(
        program.shape, program.periodic, program.proposal_offsets,
        program.kind_count, program.medium_kind, CorePotts.CompiledScalar(T(3)),
        program.attempts_per_site, T[], relationships, tracker_plan,
        descriptor_plan, stage_plan, program.engine, backend,
        program.fingerprint * "-capability";
        medium_kinds = program.medium_kinds,
        lifecycle_plan = program.lifecycle_plan,
        checkerboard_plan,
        ownership_change_handles = program.ownership_change_handles,
        mechanism_authority = program.mechanism_authority,
    )
end

struct CPUOnlyCapabilityTracker <:
       CorePotts.CompilerSPI.AbstractTrackerDescriptor end

CorePotts.CompilerSPI.tracker_contract(::CPUOnlyCapabilityTracker) =
    CorePotts.CompilerSPI.TrackerContract(
        Val(:cpu_only_capability_tracker),
        CorePotts.CompilerSPI.OwnershipTrackerSource(),
        CorePotts.CompilerSPI.DenseOwnerScalarStorage{Int32}(),
        CorePotts.CompilerSPI.AcceptedCommitTrackerVisibility(),
        CorePotts.CompilerSPI.ClaimedOwnerExclusiveTrackerConcurrency(),
        CorePotts.CompilerSPI.SourceTargetOwnerUpdateBound(),
        CorePotts.CompilerSPI.PersistTrackerCheckpoint(),
        CorePotts.CompilerSPI.TrackerSupport(true, true, true, false, 0x5a02),
        CorePotts.CompilerSPI.ConstantTrackerCost(),
        CorePotts.CompilerSPI.LatticeLinearTrackerCost(),
    )

function cpu_only_descriptor_plan()
    descriptor = CorePotts.ProposalDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, false),
        (), (), CorePotts.ProposalDriveRole(), 1,
    )
    launch = CorePotts.DescriptorLaunch(nothing, [descriptor], (), ())
    group = CorePotts.DescriptorGroup(launch, :unsplit)
    return CorePotts.DescriptorExecutionPlan(
        (group,),
        CorePotts.StateLayout(CorePotts.StateBlockSchema[]),
        CorePotts.WorkspaceLayout(CorePotts.WorkspaceSchema[]),
        (), Any[:cpu_only_descriptor], 1,
        "cpu-only-descriptor-plan-v1",
        CorePotts.HamiltonianDomainResources(0, 0),
    )
end

function cpu_only_stage_plan()
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        CorePotts.SiteAssignmentEffect(CorePotts.StateHandle(1, 1)),
        CorePotts.AcceptedCopyStage(),
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, false),
        1, 1,
    )
    return CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([descriptor]),), (),
        1, 0, "cpu-only-stage-plan-v1",
    )
end

function contradictory_relationship_test_program()
    schema = CorePotts.RelationshipStoreSchema(
        4, 2, (CorePotts.CompiledScalar(0.0f0),)
    )
    endpoint_a = CorePotts.StaticEvaluator(
        CorePotts.LiteralExpression(Int32(1))
    )
    endpoint_b = CorePotts.StaticEvaluator(
        CorePotts.LiteralExpression(Int32(2))
    )
    descriptor(payload, source_handle, buffer_slot) =
        CorePotts.CompiledStageDescriptor(
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
            CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
            CorePotts.RelationshipCreateEffect(
                1, endpoint_a, endpoint_b,
                (CorePotts.StaticEvaluator(
                    CorePotts.LiteralExpression(payload)
                ),),
            ),
            CorePotts.AcceptedCopyStage(),
            CorePotts.ResourceAccess(
                (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
                CorePotts.NoWriteAccess(),
            ),
            CorePotts.DescriptorSupport(true, true, true, true),
            source_handle, buffer_slot,
        )
    stage_plan = CorePotts.StageExecutionPlan(
        (CorePotts.StageDescriptorGroup([
            descriptor(11.0f0, 1, 2), descriptor(22.0f0, 2, 1),
        ]),),
        (), 2, 0, "contradictory-relationship-payload-plan-v1",
    )
    program = test_program(
        CorePotts.CheckerboardProgramEngine();
        relationships = CorePotts.RelationshipStorage((schema,)),
        stage_plan,
        scalar_type = Float32,
    )
    ownership = zeros(Int32, 6, 6)
    ownership[2:3, 2:3] .= 1
    ownership[4:5, 4:5] .= 2
    initial = CorePotts.ProgramInitialState(
        ownership, Int16[2, 2];
        scalar_type = Float32, relationships = ((),),
    )
    return program, initial
end

struct ExternalDoubleOccupancyTracker <:
       CorePotts.CompilerSPI.AbstractTrackerDescriptor end
CorePotts.CompilerSPI.tracker_contract(::ExternalDoubleOccupancyTracker) =
    CorePotts.CompilerSPI.TrackerContract(
    Val(:external_double_occupancy),
    CorePotts.CompilerSPI.OwnershipTrackerSource(),
    CorePotts.CompilerSPI.DenseOwnerScalarStorage{Int32}(),
    CorePotts.CompilerSPI.AcceptedCommitTrackerVisibility(),
    CorePotts.CompilerSPI.ClaimedOwnerExclusiveTrackerConcurrency(),
    CorePotts.CompilerSPI.SourceTargetOwnerUpdateBound(),
    CorePotts.CompilerSPI.PersistTrackerCheckpoint(),
    CorePotts.CompilerSPI.TrackerSupport(true, true, true, true),
    CorePotts.CompilerSPI.ConstantTrackerCost(),
    CorePotts.CompilerSPI.LatticeLinearTrackerCost(),
)
function CorePotts.CompilerSPI.tracker_rebuild(
        ::ExternalDoubleOccupancyTracker, source, cell_kinds
    )
    values = zeros(Int32, length(cell_kinds))
    for owner in source.ownership
        owner > 0 && (values[Int(owner)] += Int32(2))
    end
    return values
end
function CorePotts.CompilerSPI.tracker_recompute(
        ::ExternalDoubleOccupancyTracker, source, cell_kinds
    )
    values = fill(Int32(0), length(cell_kinds))
    for index in eachindex(source.ownership)
        owner = source.ownership[index]
        owner > 0 && (values[Int(owner)] += Int32(2))
    end
    return values
end
@inline CorePotts.CompilerSPI.tracker_proposal_delta(
        ::ExternalDoubleOccupancyTracker,
        source,
        target,
        old_owner::Int32,
        new_owner::Int32,
    ) = CorePotts.CompilerSPI.OwnerScalarDelta(Int32(2))

struct SingleSiteOwnershipProbe{A <: AbstractMatrix{Int32}} <:
       AbstractMatrix{Int32}
    values::A
    permitted::CartesianIndex{2}
    accesses::Base.RefValue{Int}
end

Base.IndexStyle(::Type{<:SingleSiteOwnershipProbe}) = IndexCartesian()
Base.size(values::SingleSiteOwnershipProbe) = size(values.values)
function Base.getindex(
        values::SingleSiteOwnershipProbe, index::CartesianIndex{2}
    )
    index == values.permitted || error(
        "proposal geometry escaped its target-local ownership access"
    )
    values.accesses[] += 1
    return @inbounds values.values[index]
end

struct UnsupportedHostCallbackEffect <: CorePotts.AbstractCompiledEffect
    count::Base.RefValue{Int}
end

function unsupported_host_callback_stage_plan(count::Base.RefValue{Int})
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        UnsupportedHostCallbackEffect(count),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, false),
        1,
        0,
    )
    return CorePotts.StageExecutionPlan(
        (), (CorePotts.StageDescriptorGroup([descriptor]),),
        0, 0, "unsupported-host-callback-stage-plan-v1",
    )
end

# SequentialCPM deliberately remains the independent host scientific
# reference.  This test-only effect exercises its public rollback boundary;
# checkerboard compilation never admits or executes it.
struct InjectedAfterMCSFailureEffect <: CorePotts.AbstractCompiledEffect end

function CorePotts._emit_after_mcs_descriptor!(
        runtime,
        ::CorePotts.CompiledStageDescriptor{
            C, V, InjectedAfterMCSFailureEffect, CorePotts.AfterMCSStage,
        },
    ) where {C, V}
    error("injected unexpected after-MCS failure")
end

function CorePotts._apply_after_mcs_descriptor!(
        runtime,
        ::CorePotts.CompiledStageDescriptor{
            C, V, InjectedAfterMCSFailureEffect, CorePotts.AfterMCSStage,
        },
    ) where {C, V}
    return runtime
end

function injected_failure_stage_plan()
    descriptor = CorePotts.CompiledStageDescriptor(
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(true)),
        CorePotts.StaticEvaluator(CorePotts.LiteralExpression(0.0)),
        InjectedAfterMCSFailureEffect(),
        CorePotts.AfterMCSStage(),
        CorePotts.ResourceAccess(
            (), (), CorePotts.EmptyFootprint(), CorePotts.EmptyFootprint(),
            CorePotts.NoWriteAccess(),
        ),
        CorePotts.DescriptorSupport(true, true, true, false),
        1,
        0,
    )
    group = CorePotts.StageDescriptorGroup([descriptor])
    return CorePotts.StageExecutionPlan(
        (), (group,), 0, 0, "injected-failure-stage-plan-v1"
    )
end
