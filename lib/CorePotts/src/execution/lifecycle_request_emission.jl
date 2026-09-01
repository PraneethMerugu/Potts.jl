# Engine-neutral lifecycle transaction orchestration. The sequential engine
# calls this reference path directly; later engines reuse the same plan,
# request ordering, status, and publication contracts.

const _LIFECYCLE_STATUS_DETAILS = (
    :none => LifecycleDetailNone,
    :ownership_exceeds_cell_capacity => LifecycleDetailOwnershipExceedsCellCapacity,
    :cell_site_index_exceeds_lattice => LifecycleDetailCellSiteIndexExceedsLattice,
    :cell_site_index_missing_owned_site => LifecycleDetailCellSiteIndexMissingOwnedSite,
    :nonfinite_result => LifecycleDetailNonfiniteResult,
    :evaluation_error => LifecycleDetailEvaluationError,
    :request_bound_exceeded => LifecycleDetailRequestBoundExceeded,
    :trigger_not_boolean => LifecycleDetailTriggerNotBoolean,
    :placement_selection_invalid => LifecycleDetailPlacementSelectionInvalid,
    :placement_not_integral => LifecycleDetailPlacementNotIntegral,
    :placement_out_of_bounds => LifecycleDetailPlacementOutOfBounds,
    :placement_selection_empty => LifecycleDetailPlacementSelectionEmpty,
    :placement_emission_bound_exceeded => LifecycleDetailPlacementEmissionBoundExceeded,
    :placement_bound_exceeded => LifecycleDetailPlacementBoundExceeded,
    :duplicate_placement_site => LifecycleDetailDuplicatePlacementSite,
    :placement_site_unavailable => LifecycleDetailPlacementSiteUnavailable,
    :empty_source_cell => LifecycleDetailEmptySourceCell,
    :partition_label_invalid => LifecycleDetailPartitionLabelInvalid,
    :partition_geometry_invalid => LifecycleDetailPartitionGeometryInvalid,
    :partition_empty_descendant => LifecycleDetailPartitionEmptyDescendant,
    :partition_parent_disconnected => LifecycleDetailPartitionParentDisconnected,
    :partition_daughter_disconnected => LifecycleDetailPartitionDaughterDisconnected,
    :retire_nonempty => LifecycleDetailRetireNonempty,
    :unknown_effect => LifecycleDetailUnknownEffect,
    :relationship_policy_rejected => LifecycleDetailRelationshipPolicyRejected,
    :unknown_distribution => LifecycleDetailUnknownDistribution,
    :split_fraction_out_of_bounds => LifecycleDetailSplitFractionOutOfBounds,
    :unsupported_state_policy => LifecycleDetailUnsupportedStatePolicy,
    :tracker_plan_state_misalignment => LifecycleDetailTrackerPlanStateMisalignment,
    :active_occupancy_mismatch => LifecycleDetailActiveOccupancyMismatch,
    :forbidden_extinction => LifecycleDetailForbiddenExtinction,
    :division_plan_missing => LifecycleDetailDivisionPlanMissing,
    :state_value_invalid => LifecycleDetailStateValueInvalid,
    :tracker_storage_invalid => LifecycleDetailTrackerStorageInvalid,
    :relationship_integrity_invalid => LifecycleDetailRelationshipIntegrityInvalid,
    :tracker_commit_invalid => LifecycleDetailTrackerCommitInvalid,
    :relationship_commit_invalid => LifecycleDetailRelationshipCommitInvalid,
    :acceptance_nonfinite => LifecycleDetailAcceptanceNonfinite,
    :acceptance_zero_temperature_drive =>
        LifecycleDetailAcceptanceZeroTemperatureDrive,
)

@inline function _lifecycle_detail_code(reason::Symbol)
    for pair in _LIFECYCLE_STATUS_DETAILS
        first(pair) === reason && return last(pair)
    end
    return LifecycleDetailNone
end

function _program_status_detail_symbol(detail::ProgramStatusDetailCode)
    for pair in _LIFECYCLE_STATUS_DETAILS
        last(pair) === detail && return first(pair)
    end
    return :none
end

@inline function _set_lifecycle_status!(
        workspace,
        code::ProgramStatusCode;
        source::Integer = 0,
        action_identity::Integer = 0,
        mcs::Integer = 0,
        stage::ProgramExecutionStage = ProgramStageNone,
        secondary_source::Integer = 0,
        anchor::Integer = 0,
        detail::ProgramStatusDetailCode = LifecycleDetailNone,
        required::Integer = 0,
        available::Integer = 0,
        maximum::Integer = 0,
    )
    @inbounds workspace.status[1] = ProgramStatus(
        code,
        Int32(mcs),
        stage,
        Int32(source),
        UInt64(action_identity),
        Int32(secondary_source),
        Int32(anchor),
        detail,
        Int32(required),
        Int32(available),
        Int32(maximum),
    )
    return false
end

@inline _lifecycle_succeeded(workspace) =
    lifecycle_workspace_status(workspace).code === ProgramStatusSuccess

function _validate_lifecycle_ownership!(runtime, workspace)
    maximum = length(runtime.cell_kinds)
    for owner in runtime.ownership
        owner <= 0 && continue
        owner <= maximum || return _set_lifecycle_status!(
            workspace,
            ProgramStatusInvariant;
            anchor = owner,
            detail = LifecycleDetailOwnershipExceedsCellCapacity,
        )
    end
    return true
end

struct LifecycleEvaluationFailed end

abstract type AbstractLifecycleExecutionMode end
struct HostLifecycleExecution <: AbstractLifecycleExecutionMode end
struct BackendLifecycleExecution <: AbstractLifecycleExecutionMode end

@inline function _lifecycle_due(
        descriptor::LifecycleDescriptor, next_mcs::Int
    )
    descriptor.cadence === EveryMCSLifecycleCadence && return true
    descriptor.cadence === AtMCSLifecycleCadence &&
        return next_mcs == descriptor.cadence_value
    descriptor.cadence === PeriodicLifecycleCadence &&
        return rem(next_mcs, Int(descriptor.cadence_value)) == 0
    return false
end

@inline function _lifecycle_context_site(runtime, workspace, anchor::Int32)
    linear = Int32(0)
    if anchor > 0
        records = _lifecycle_site_records(workspace, anchor)
        isempty(records) || (linear = @inbounds records[1].site)
    end
    iszero(linear) && (linear = Int32(1))
    return CartesianIndices(runtime.ownership)[Int(linear)]
end

function _evaluate_lifecycle_checked(
        ::HostLifecycleExecution,
        plan,
        index::Integer,
        context,
        descriptor::LifecycleDescriptor,
        workspace,
    )
    try
        value = evaluate_lifecycle(plan.evaluators, index, context)
        if value isa AbstractFloat && !isfinite(value)
            _set_lifecycle_status!(
                workspace,
                ProgramStatusEvaluator;
                source = descriptor.source_handle,
                anchor = context.anchor,
                detail = LifecycleDetailNonfiniteResult,
            )
            return LifecycleEvaluationFailed()
        end
        return value
    catch error
        _set_lifecycle_status!(
            workspace,
            ProgramStatusEvaluator;
            source = descriptor.source_handle,
            anchor = context.anchor,
            detail = LifecycleDetailEvaluationError,
        )
        return LifecycleEvaluationFailed()
    end
end

@inline function _evaluate_lifecycle_checked(
        ::BackendLifecycleExecution,
        plan,
        index::Integer,
        context,
        descriptor::LifecycleDescriptor,
        workspace,
    )
    value = evaluate_lifecycle(plan.evaluators, index, context)
    if value isa AbstractFloat && !isfinite(value)
        _set_lifecycle_status!(
            workspace,
            ProgramStatusEvaluator;
            source = descriptor.source_handle,
            anchor = context.anchor,
            detail = LifecycleDetailNonfiniteResult,
        )
        return LifecycleEvaluationFailed()
    end
    return value
end

@inline _evaluate_lifecycle_checked(
    plan, index, context, descriptor, workspace
) = _evaluate_lifecycle_checked(
    HostLifecycleExecution(), plan, index, context, descriptor, workspace
)

@inline function _linear_neighbor(
        program,
        linear::Int,
        offset::NTuple{N, <:Integer},
    ) where {N}
    center = CartesianIndices(program.shape)[linear]
    coordinates = ntuple(N) do dimension
        value = center[dimension] + Int(offset[dimension])
        if program.periodic[dimension]
            mod1(value, program.shape[dimension])
        elseif 1 <= value <= program.shape[dimension]
            value
        else
            0
        end
    end
    any(iszero, coordinates) && return 0
    return LinearIndices(program.shape)[CartesianIndex(coordinates)]
end
