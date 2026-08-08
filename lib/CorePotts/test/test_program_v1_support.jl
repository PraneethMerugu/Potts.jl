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
    )
    T = Float64
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

struct ExternalDoubleOccupancyTracker <: CorePotts.AbstractTrackerDescriptor end
CorePotts.tracker_contract(::ExternalDoubleOccupancyTracker) =
    CorePotts.TrackerContract(
    Val(:external_double_occupancy),
    CorePotts.OwnershipTrackerSource(),
    CorePotts.DenseOwnerScalarStorage{Int32}(),
    CorePotts.AcceptedCommitTrackerVisibility(),
    CorePotts.ClaimedOwnerExclusiveTrackerConcurrency(),
    CorePotts.SourceTargetOwnerUpdateBound(),
    CorePotts.PersistTrackerCheckpoint(),
    CorePotts.TrackerSupport(true, true, true, true),
    CorePotts.ConstantTrackerCost(),
    CorePotts.LatticeLinearTrackerCost(),
)
function CorePotts.tracker_rebuild(
        ::ExternalDoubleOccupancyTracker, source, cell_kinds
    )
    values = zeros(Int32, length(cell_kinds))
    for owner in source.ownership
        owner > 0 && (values[Int(owner)] += Int32(2))
    end
    return values
end
function CorePotts.tracker_recompute(
        ::ExternalDoubleOccupancyTracker, source, cell_kinds
    )
    values = fill(Int32(0), length(cell_kinds))
    for index in eachindex(source.ownership)
        owner = source.ownership[index]
        owner > 0 && (values[Int(owner)] += Int32(2))
    end
    return values
end
@inline CorePotts.tracker_proposal_delta(
        ::ExternalDoubleOccupancyTracker,
        source,
        target,
        old_owner::Int32,
        new_owner::Int32,
    ) = CorePotts.OwnerScalarDelta(Int32(2))

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
        CorePotts.DescriptorSupport(true, false, true, false),
        1,
        0,
    )
    group = CorePotts.StageDescriptorGroup([descriptor])
    return CorePotts.StageExecutionPlan(
        (), (group,), 0, 0, "injected-failure-stage-plan-v1"
    )
end
