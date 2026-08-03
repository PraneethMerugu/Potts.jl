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
)

@inline function _lifecycle_detail_code(reason::Symbol)
    for pair in _LIFECYCLE_STATUS_DETAILS
        first(pair) === reason && return last(pair)
    end
    return LifecycleDetailNone
end

function _lifecycle_detail_symbol(detail::LifecycleStatusDetailCode)
    for pair in _LIFECYCLE_STATUS_DETAILS
        last(pair) === detail && return first(pair)
    end
    return :none
end

@inline function _set_lifecycle_status!(
        workspace,
        code::LifecycleStatusCode;
        source::Integer = 0,
        secondary_source::Integer = 0,
        anchor::Integer = 0,
        detail::LifecycleStatusDetailCode = LifecycleDetailNone,
        required::Integer = 0,
        available::Integer = 0,
        maximum::Integer = 0,
    )
    workspace.status = LifecycleStatusPayload(
        code,
        Int32(source),
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
    workspace.status.code === LifecycleStatusSuccess

struct LifecycleEvaluationFailed end

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

function _index_lifecycle_representative_sites!(runtime, workspace)
    fill!(workspace.cell_site_counts, 0)
    fill!(workspace.cell_site_starts, 0)
    fill!(workspace.cell_site_cursor, 0)
    fill!(workspace.site_position, 0)
    for linear in eachindex(runtime.ownership)
        owner = @inbounds runtime.ownership[linear]
        owner > 0 || continue
        if owner > length(workspace.representative_site)
            _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                anchor = owner,
                detail = LifecycleDetailOwnershipExceedsCellCapacity,
            )
            return false
        end
        @inbounds iszero(workspace.representative_site[owner]) &&
            (workspace.representative_site[owner] = Int32(linear))
        @inbounds workspace.cell_site_counts[owner] += Int32(1)
    end
    cursor = Int32(1)
    for cell in eachindex(workspace.cell_site_counts)
        @inbounds begin
            workspace.cell_site_starts[cell] = cursor
            workspace.cell_site_cursor[cell] = cursor
            cursor += workspace.cell_site_counts[cell]
        end
    end
    if cursor > length(runtime.ownership) + 1
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            detail = LifecycleDetailCellSiteIndexExceedsLattice,
        )
        return false
    end
    for linear in eachindex(runtime.ownership)
        owner = @inbounds runtime.ownership[linear]
        owner > 0 || continue
        position = @inbounds workspace.cell_site_cursor[owner]
        @inbounds begin
            workspace.cell_sites[position] = Int32(linear)
            workspace.site_position[linear] = position
            workspace.cell_site_cursor[owner] = position + Int32(1)
        end
    end
    return true
end

@inline function _cell_site_range(workspace, cell::Int32)
    start = Int(@inbounds workspace.cell_site_starts[cell])
    count = Int(@inbounds workspace.cell_site_counts[cell])
    return start:(start + count - 1)
end

@inline function _lifecycle_context_site(runtime, workspace, anchor::Int32)
    linear = anchor > 0 ?
        @inbounds(workspace.representative_site[anchor]) : Int32(0)
    iszero(linear) && (linear = Int32(1))
    return CartesianIndices(runtime.ownership)[Int(linear)]
end

function _evaluate_lifecycle_checked(
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
                LifecycleStatusEvaluator;
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
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor = context.anchor,
            detail = LifecycleDetailEvaluationError,
        )
        return LifecycleEvaluationFailed()
    end
end

function _emit_lifecycle_request!(
        workspace::LifecycleWorkspace,
        descriptor_index::Int,
        descriptor::LifecycleDescriptor,
        anchor::Int32,
        generation::UInt32,
    )
    index = Int(workspace.request_count) + 1
    if index > length(workspace.descriptor)
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusFootprint;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailRequestBoundExceeded,
        )
        return 0
    end
    @inbounds begin
        workspace.descriptor[index] = Int32(descriptor_index)
        workspace.anchor[index] = anchor
        workspace.generation[index] = generation
        workspace.occurrence[index] = 0
        workspace.active[index] = true
    end
    workspace.request_count = Int32(index)
    return index
end

function _emit_lifecycle_requests!(runtime, plan, workspace)
    next_mcs = runtime.mcs + 1
    for descriptor_index in eachindex(plan.descriptors)
        descriptor = @inbounds plan.descriptors[descriptor_index]
        _lifecycle_due(descriptor, next_mcs) || continue
        if descriptor.domain === ModelLifecycleDomain
            context = _LifecycleTriggerContext(
                runtime,
                descriptor.source_identity,
                descriptor.action_identity,
                descriptor.trigger_workspace_maximum,
                Int32(0),
                Int32(workspace.request_count + 1),
                Int32(0),
                UInt32(0),
                _lifecycle_context_site(runtime, workspace, Int32(0)),
                Int32(0),
                UInt16(descriptor.source_handle),
            )
            enabled = _evaluate_lifecycle_checked(
                plan, descriptor.trigger_evaluator, context, descriptor, workspace
            )
            enabled isa LifecycleEvaluationFailed && return false
            enabled isa Bool || return _set_lifecycle_status!(
                workspace,
                LifecycleStatusEvaluator;
                source = descriptor.source_handle,
                detail = LifecycleDetailTriggerNotBoolean,
            )
            if enabled
                emitted = _emit_lifecycle_request!(
                workspace,
                descriptor_index,
                descriptor,
                Int32(0),
                UInt32(0),
            )
                iszero(emitted) && return false
            end
        else
            for cell in eachindex(runtime.cell_kinds)
                kind = @inbounds runtime.cell_kinds[cell]
                kind == descriptor.domain_kind || continue
                generation = @inbounds runtime.cell_generations[cell]
                iszero(generation) && return _set_lifecycle_status!(
                    workspace, LifecycleStatusStaleGeneration; anchor = cell
                )
                context = _LifecycleTriggerContext(
                    runtime,
                    descriptor.source_identity,
                    descriptor.action_identity,
                    descriptor.trigger_workspace_maximum,
                    Int32(0),
                    Int32(workspace.request_count + 1),
                    Int32(cell),
                    generation,
                    _lifecycle_context_site(runtime, workspace, Int32(cell)),
                    Int32(0),
                    UInt16(descriptor.source_handle),
                )
                enabled = _evaluate_lifecycle_checked(
                    plan, descriptor.trigger_evaluator, context, descriptor, workspace
                )
                enabled isa LifecycleEvaluationFailed && return false
                enabled isa Bool || return _set_lifecycle_status!(
                    workspace,
                    LifecycleStatusEvaluator;
                    source = descriptor.source_handle,
                    anchor = cell,
                    detail = LifecycleDetailTriggerNotBoolean,
                )
                if enabled
                    emitted = _emit_lifecycle_request!(
                    workspace,
                    descriptor_index,
                    descriptor,
                    Int32(cell),
                    generation,
                )
                    iszero(emitted) && return false
                end
            end
        end
    end
    return true
end

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
