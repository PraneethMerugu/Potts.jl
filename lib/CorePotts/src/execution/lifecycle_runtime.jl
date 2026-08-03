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
    :division_replan_mismatch => LifecycleDetailDivisionReplanMismatch,
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

function _plan_creation!(runtime, plan, workspace, request, descriptor)
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    site = _lifecycle_context_site(runtime, workspace, anchor)
    context = _LifecyclePlacementContext(
        runtime,
        descriptor.source_identity,
        descriptor.action_identity,
        descriptor.placement_workspace_maximum,
        Int32(request),
        anchor,
        generation,
        site,
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    result = _evaluate_lifecycle_checked(
        plan, descriptor.placement_evaluator, context, descriptor, workspace
    )
    result isa LifecycleEvaluationFailed && return :status_failure
    external = descriptor.placement === ExternalLifecyclePlacement
    selection = external && result isa LifecycleSiteSelection ? result : nothing
    external && selection === nothing && return :placement_selection_invalid
    !external && !(result isa Integer) && return :placement_not_integral
    center = external ? 0 : Int(result)
    !external && !(1 <= center <= length(runtime.ownership)) &&
        return :placement_out_of_bounds
    count = external ? Int(selection.count) :
        descriptor.placement === SeedStencilLifecyclePlacement ?
        Int(descriptor.stencil_count) : 1
    count > 0 || return :placement_selection_empty
    if count > descriptor.placement_maximum
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusFootprint;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailPlacementEmissionBoundExceeded,
        )
        return :status_failure
    end
    if count > size(workspace.planned_sites, 1)
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusFootprint;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailPlacementBoundExceeded,
        )
        return :status_failure
    end
    for position in 1:count
        selected = if external
            Int(@inbounds selection.sites[position])
        elseif descriptor.placement === SeedStencilLifecyclePlacement
            offset_index = Int(descriptor.stencil_offset) + position - 1
            _linear_neighbor(
                runtime.program, center, @inbounds(plan.stencil_offsets[offset_index])
            )
        else
            center
        end
        selected > 0 || return :placement_out_of_bounds
        for prior in 1:(position - 1)
            @inbounds workspace.planned_sites[prior, request] == selected &&
                return :duplicate_placement_site
        end
        owner = @inbounds runtime.ownership[selected]
        owner <= 0 || return :placement_site_unavailable
        @inbounds workspace.planned_sites[position, request] = Int32(selected)
    end
    @inbounds workspace.planned_site_count[request] = Int32(count)
    return :ok
end

@inline function _partition_normal(runtime, descriptor, anchor, generation)
    T = eltype(runtime.parameters)
    N = length(runtime.program.shape)
    if descriptor.partition === SpecifiedNormalLifecyclePartition
        return descriptor.normal
    elseif descriptor.partition === RandomPlaneLifecyclePartition
        N == 2 || return nothing
        draw = _lifecycle_uniform(
            T,
            runtime,
            LifecyclePartitionStream,
            descriptor.geometry_draw,
            anchor,
            generation,
            0,
        )
        angle = T(2pi) * draw
        return (cos(angle), sin(angle))
    elseif descriptor.partition in (
            PrincipalMajorLifecyclePartition,
            PrincipalMinorLifecyclePartition,
        )
        N == 2 || return nothing
        statistics = _cell_shape_statistics(runtime, anchor)
        statistics === nothing && return nothing
        covariance = statistics[3]
        a, b, d = covariance[1], covariance[2], covariance[4]
        λmajor = _maximum_covariance_eigenvalue(Val(2), covariance)
        λ = descriptor.partition === PrincipalMajorLifecyclePartition ?
            λmajor : a + d - λmajor
        vector = abs(b) > eps(T) ? (b, λ - a) :
            abs(a - λ) <= abs(d - λ) ? (one(T), zero(T)) :
            (zero(T), one(T))
        norm = sqrt(vector[1]^2 + vector[2]^2)
        return (vector[1] / norm, vector[2] / norm)
    end
    return nothing
end

function _partition_connected(
        runtime, plan, workspace, request, descriptor, label::UInt8
    )
    anchor = @inbounds workspace.anchor[request]
    positions = _cell_site_range(workspace, anchor)
    for position in positions
        linear = Int(@inbounds workspace.cell_sites[position])
        @inbounds workspace.site_seen[linear] = false
    end
    first_site = Int32(0)
    expected = 0
    for position in positions
        @inbounds workspace.partition_labels[position] == label || continue
        expected += 1
        iszero(first_site) &&
            (first_site = @inbounds workspace.cell_sites[position])
    end
    iszero(first_site) && return false
    head = 1
    tail = 1
    workspace.site_queue[1] = first_site
    workspace.site_seen[first_site] = true
    visited = 0
    relation = @inbounds plan.relations[Int(descriptor.relation_slot)]
    while head <= tail
        linear = Int(@inbounds workspace.site_queue[head])
        head += 1
        visited += 1
        center = CartesianIndices(runtime.program.shape)[linear]
        for direction in axes(relation, 2)
            neighbor = _neighbor_index(
                runtime.program, center, relation, Int(direction)
            )
            neighbor === nothing && continue
            neighbor_linear = LinearIndices(runtime.program.shape)[neighbor]
            @inbounds runtime.ownership[neighbor_linear] == anchor || continue
            position = Int(@inbounds workspace.site_position[neighbor_linear])
            position > 0 || return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                source = descriptor.source_handle,
                anchor,
                detail = LifecycleDetailCellSiteIndexMissingOwnedSite,
            )
            @inbounds workspace.partition_labels[position] == label || continue
            @inbounds workspace.site_seen[neighbor_linear] && continue
            tail += 1
            @inbounds begin
                workspace.site_queue[tail] = Int32(neighbor_linear)
                workspace.site_seen[neighbor_linear] = true
            end
        end
    end
    return visited == expected
end

function _plan_division!(runtime, plan, workspace, request, descriptor)
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    positions = _cell_site_range(workspace, anchor)
    for position in positions
        @inbounds workspace.partition_labels[position] = 0
    end
    external = descriptor.partition === ExternalLifecyclePartition
    center = external ? nothing : descriptor.point_from_centroid ?
        _cell_center(runtime, anchor) : descriptor.point
    !external && center === nothing && return :empty_source_cell
    normal = external ? nothing :
        _partition_normal(runtime, descriptor, anchor, generation)
    first_count = 0
    second_count = 0
    for position in positions
        linear = Int(@inbounds workspace.cell_sites[position])
        site = CartesianIndices(runtime.program.shape)[linear]
        label = if descriptor.partition === ExternalLifecyclePartition
            context = _LifecyclePartitionContext(
                runtime,
                descriptor.source_identity,
                descriptor.action_identity,
                descriptor.partition_workspace_maximum,
                Int32(request),
                anchor,
                generation,
                site,
                Int32(0),
                UInt16(descriptor.source_handle),
            )
            value = _evaluate_lifecycle_checked(
                plan, descriptor.partition_evaluator, context, descriptor, workspace
            )
            value isa LifecycleEvaluationFailed && return :status_failure
            value isa Integer && value in (1, 2) ||
                return :partition_label_invalid
            UInt8(value)
        else
            normal === nothing && return :partition_geometry_invalid
            projection = sum(
                (eltype(runtime.parameters)(site[dimension]) -
                 eltype(runtime.parameters)(0.5) - center[dimension]) *
                normal[dimension]
                for dimension in eachindex(normal)
            )
            projection <= 0 ? UInt8(1) : UInt8(2)
        end
        @inbounds workspace.partition_labels[position] = label
        label == 1 ? (first_count += 1) : (second_count += 1)
    end
    first_count > 0 && second_count > 0 || return :partition_empty_descendant
    if descriptor.side === StableRandomLifecycleSide
        flip = _lifecycle_uniform(
            eltype(runtime.parameters),
            runtime,
            LifecyclePartitionStream,
            descriptor.side_draw,
            anchor,
            generation,
            0,
        ) < eltype(runtime.parameters)(0.5)
        if flip
            for position in positions
                @inbounds workspace.partition_labels[position] == 1 ?
                    (workspace.partition_labels[position] = 2) :
                    workspace.partition_labels[position] == 2 &&
                    (workspace.partition_labels[position] = 1)
            end
        end
    end
    parent_connected = _partition_connected(
        runtime, plan, workspace, request, descriptor, UInt8(1)
    )
    _lifecycle_succeeded(workspace) || return :status_failure
    parent_connected || return :partition_parent_disconnected
    daughter_connected = _partition_connected(
        runtime, plan, workspace, request, descriptor, UInt8(2)
    )
    _lifecycle_succeeded(workspace) || return :status_failure
    daughter_connected || return :partition_daughter_disconnected
    return :ok
end

@inline function _relationship_kinds_match(kind, other, rule)
    return (kind == rule.kind_a && other == rule.kind_b) ||
           (kind == rule.kind_b && other == rule.kind_a)
end

function _relationship_rule_admissible(
        state, cell_kinds, anchor, destination_kind, rule
    )
    degree = Int(@inbounds state.degree[anchor])
    rule.action in (
        RejectWhileLinkedLifecycleRelationship,
        PreserveCompatibleLifecycleRelationship,
        RejectIncompatibleLifecycleRelationship,
    ) && begin
        if rule.action === RejectWhileLinkedLifecycleRelationship
            return iszero(degree)
        end
        for position in 1:degree
            edge = Int(@inbounds state.incident_edges[position, anchor])
            other = @inbounds state.endpoint_a[edge] == anchor ?
                state.endpoint_b[edge] : state.endpoint_a[edge]
            other_kind = @inbounds cell_kinds[other]
            _relationship_kinds_match(destination_kind, other_kind, rule) ||
                return false
        end
    end
    return true
end

function _lifecycle_relationships_admissible(
        runtime, plan, descriptor, anchor
    )
    count = Int(descriptor.relationship_rule_count)
    count == 0 && return true
    destination_kind = descriptor.effect === TransitionCellLifecycleEffect ?
        descriptor.destination_kind : Int16(0)
    for offset in 0:(count - 1)
        rule = @inbounds plan.relationship_rules[
            Int(descriptor.relationship_rule_offset) + offset
        ]
        state = runtime.relationships[Int(rule.relationship_slot)]
        _relationship_rule_admissible(
            state, runtime.cell_kinds, Int(anchor), destination_kind, rule
        ) || return false
    end
    return true
end

function _plan_lifecycle_request!(runtime, plan, workspace, request)
    descriptor = @inbounds plan.descriptors[
        Int(workspace.descriptor[request])
    ]
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    if anchor > 0
        if !(1 <= anchor <= length(runtime.cell_kinds)) ||
                @inbounds(runtime.cell_generations[anchor]) != generation ||
                @inbounds(runtime.cell_kinds[anchor]) == 0
            _set_lifecycle_status!(
                workspace, LifecycleStatusStaleGeneration; anchor
            )
            return :status_failure
        end
    end
    reason = if descriptor.effect === CreateCellLifecycleEffect
        _plan_creation!(runtime, plan, workspace, request, descriptor)
    elseif descriptor.effect === RetireCellLifecycleEffect
        program_tracker_value(runtime, Val(:cell_volume), anchor) == 0 ?
            :ok : :retire_nonempty
    elseif descriptor.effect === RemoveCellLifecycleEffect
        :ok
    elseif descriptor.effect === TransitionCellLifecycleEffect
        :ok
    elseif descriptor.effect === DivideCellLifecycleEffect
        _plan_division!(runtime, plan, workspace, request, descriptor)
    else
        :unknown_effect
    end
    reason === :ok && !_lifecycle_relationships_admissible(
        runtime, plan, descriptor, anchor
    ) && (reason = :relationship_policy_rejected)
    return reason
end

function _filter_lifecycle_requests!(runtime, plan, workspace)
    for request in 1:Int(workspace.request_count)
        @inbounds workspace.active[request] || continue
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        reason = _plan_lifecycle_request!(runtime, plan, workspace, request)
        reason === :status_failure && return false
        reason === :ok && continue
        if descriptor.on_inadmissible === FilterLifecycleInadmissible
            @inbounds begin
                workspace.active[request] = false
                workspace.filtered[request] = true
            end
        else
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInadmissible;
                source = descriptor.source_handle,
                anchor = @inbounds(workspace.anchor[request]),
                detail = _lifecycle_detail_code(reason),
            )
        end
    end
    return true
end

@inline function _lifecycle_request_key(plan, workspace, request)
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    return (
        descriptor.source_identity,
        descriptor.action_identity,
        @inbounds(workspace.anchor[request]),
        @inbounds(workspace.generation[request]),
    )
end

@inline function _lifecycle_requests_equivalent(plan, workspace, left, right)
    return _lifecycle_request_key(plan, workspace, left) ==
           _lifecycle_request_key(plan, workspace, right)
end

function _lifecycle_relationship_footprints_conflict(
        runtime, plan, workspace, left, right
    )
    left_descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[left])]
    right_descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[right])]
    left_descriptor.relationship_rule_count > 0 || return false
    right_descriptor.relationship_rule_count > 0 || return false
    left_anchor = @inbounds workspace.anchor[left]
    right_anchor = @inbounds workspace.anchor[right]
    left_anchor > 0 && right_anchor > 0 || return false
    for left_offset in 0:(Int(left_descriptor.relationship_rule_count) - 1)
        left_rule = @inbounds plan.relationship_rules[
            Int(left_descriptor.relationship_rule_offset) + left_offset
        ]
        left_state = runtime.relationships[Int(left_rule.relationship_slot)]
        for right_offset in 0:(Int(right_descriptor.relationship_rule_count) - 1)
            right_rule = @inbounds plan.relationship_rules[
                Int(right_descriptor.relationship_rule_offset) + right_offset
            ]
            left_rule.relationship_slot == right_rule.relationship_slot || continue
            left_degree = Int(@inbounds left_state.degree[left_anchor])
            right_degree = Int(@inbounds left_state.degree[right_anchor])
            for left_position in 1:left_degree, right_position in 1:right_degree
                @inbounds left_state.incident_edges[left_position, left_anchor] ==
                    left_state.incident_edges[right_position, right_anchor] &&
                    return true
            end
        end
    end
    return false
end

function _lifecycle_requests_conflict(runtime, plan, workspace, left, right)
    left_anchor = @inbounds workspace.anchor[left]
    right_anchor = @inbounds workspace.anchor[right]
    left_anchor > 0 && left_anchor == right_anchor && return true
    left_count = Int(@inbounds workspace.planned_site_count[left])
    right_count = Int(@inbounds workspace.planned_site_count[right])
    for left_position in 1:left_count, right_position in 1:right_count
        @inbounds workspace.planned_sites[left_position, left] ==
                  workspace.planned_sites[right_position, right] && return true
    end
    return _lifecycle_relationship_footprints_conflict(
        runtime, plan, workspace, left, right
    )
end

function _deduplicate_lifecycle_requests!(plan, workspace)
    for right in 1:Int(workspace.request_count)
        @inbounds workspace.active[right] || continue
        for left in 1:(right - 1)
            @inbounds workspace.active[left] || continue
            _lifecycle_requests_equivalent(plan, workspace, left, right) || continue
            @inbounds workspace.active[right] = false
            break
        end
    end
    return workspace
end

function _resolve_lifecycle_conflicts!(runtime, plan, workspace)
    _deduplicate_lifecycle_requests!(plan, workspace)
    count = Int(workspace.request_count)
    if plan.conflict_policy === RejectLifecycleConflicts
        first_conflict = 0
        second_conflict = 0
        for right in 1:count
            @inbounds workspace.active[right] || continue
            for left in 1:(right - 1)
                @inbounds workspace.active[left] || continue
                _lifecycle_requests_conflict(
                    runtime, plan, workspace, left, right
                ) || continue
                left_key = _lifecycle_request_key(plan, workspace, left)
                right_key = _lifecycle_request_key(plan, workspace, right)
                candidate_first, candidate_second = left_key <= right_key ?
                    (left, right) : (right, left)
                if iszero(first_conflict) ||
                        (_lifecycle_request_key(
                            plan, workspace, candidate_first
                        ), _lifecycle_request_key(
                            plan, workspace, candidate_second
                        )) <
                        (_lifecycle_request_key(
                            plan, workspace, first_conflict
                        ), _lifecycle_request_key(
                            plan, workspace, second_conflict
                        ))
                    first_conflict = candidate_first
                    second_conflict = candidate_second
                end
            end
        end
        if !iszero(first_conflict)
            first_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[first_conflict])
            ]
            second_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[second_conflict])
            ]
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusConflict;
                source = first_descriptor.source_handle,
                secondary_source = second_descriptor.source_handle,
                anchor = @inbounds(workspace.anchor[second_conflict]),
            )
        end
        for request in 1:count
            @inbounds workspace.active[request] || continue
            @inbounds workspace.selected[request] = true
        end
        return true
    end
    fill!(workspace.conflict_seen, false)
    for seed in 1:count
        @inbounds workspace.active[seed] || continue
        @inbounds workspace.conflict_seen[seed] && continue
        head = 1
        tail = 1
        workspace.canonical_order[1] = Int32(seed)
        workspace.conflict_seen[seed] = true
        while head <= tail
            current = Int(@inbounds workspace.canonical_order[head])
            head += 1
            for candidate in 1:count
                @inbounds workspace.active[candidate] || continue
                @inbounds workspace.conflict_seen[candidate] && continue
                _lifecycle_requests_conflict(
                    runtime, plan, workspace, current, candidate
                ) || continue
                tail += 1
                @inbounds begin
                    workspace.canonical_order[tail] = Int32(candidate)
                    workspace.conflict_seen[candidate] = true
                end
            end
        end
        best = 0
        tied = 0
        best_priority = typemin(Int32)
        for position in 1:tail
            candidate = Int(@inbounds workspace.canonical_order[position])
            priority = @inbounds plan.descriptors[
                Int(workspace.descriptor[candidate])
            ].priority
            if priority > best_priority
                best = candidate
                tied = 0
                best_priority = priority
            elseif priority == best_priority
                if _lifecycle_request_key(plan, workspace, candidate) <
                        _lifecycle_request_key(plan, workspace, best)
                    tied = best
                    best = candidate
                elseif iszero(tied) || _lifecycle_request_key(
                        plan, workspace, candidate
                    ) < _lifecycle_request_key(plan, workspace, tied)
                    tied = candidate
                end
            end
        end
        if !iszero(tied)
            best_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[best])
            ]
            tied_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[tied])
            ]
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusConflict;
                source = best_descriptor.source_handle,
                secondary_source = tied_descriptor.source_handle,
                anchor = @inbounds(workspace.anchor[tied]),
            )
        end
        @inbounds workspace.selected[best] = true
    end
    return true
end

function _sort_selected_requests!(plan, workspace)
    selected_count = 0
    for request in 1:Int(workspace.request_count)
        @inbounds workspace.selected[request] || continue
        selected_count += 1
        workspace.canonical_order[selected_count] = Int32(request)
    end
    for index in 2:selected_count
        request = @inbounds workspace.canonical_order[index]
        key = _lifecycle_request_key(plan, workspace, Int(request))
        position = index
        while position > 1 && _lifecycle_request_key(
                plan,
                workspace,
                Int(@inbounds workspace.canonical_order[position - 1]),
            ) > key
            @inbounds workspace.canonical_order[position] =
                workspace.canonical_order[position - 1]
            position -= 1
        end
        @inbounds workspace.canonical_order[position] = request
    end
    return selected_count
end

function _preflight_lifecycle_capacity!(runtime, plan, workspace)
    selected_count = _sort_selected_requests!(plan, workspace)
    requested = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        effect = plan.descriptors[Int(workspace.descriptor[request])].effect
        effect in (CreateCellLifecycleEffect, DivideCellLifecycleEffect) &&
            (requested += 1)
    end
    free_count = 0
    high_water = 0
    for cell in eachindex(runtime.cell_kinds)
        generation = @inbounds runtime.cell_generations[cell]
        !iszero(generation) && (high_water = cell)
        if @inbounds runtime.cell_kinds[cell] == 0 && !iszero(generation)
            free_count += 1
            workspace.free_slots[free_count] = Int32(cell)
        end
    end
    for cell in (high_water + 1):length(runtime.cell_kinds)
        @inbounds iszero(runtime.cell_generations[cell]) || continue
        free_count += 1
        workspace.free_slots[free_count] = Int32(cell)
    end
    if requested > free_count
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusCellCapacity;
            required = requested,
            available = free_count,
            maximum = plan.cell_capacity,
        )
        return -1
    end
    allocation_position = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        effect = plan.descriptors[Int(workspace.descriptor[request])].effect
        effect in (CreateCellLifecycleEffect, DivideCellLifecycleEffect) || continue
        allocation_position += 1
        slot = @inbounds workspace.free_slots[allocation_position]
        generation = @inbounds runtime.cell_generations[slot]
        if generation == typemax(UInt32)
            _set_lifecycle_status!(
                workspace, LifecycleStatusGenerationOverflow; anchor = slot
            )
            return -1
        end
        @inbounds workspace.allocation[request] = slot
    end
    return selected_count
end

@inline function _stage_owner_change!(runtime, plan, workspace, linear, new_owner)
    old_owner = @inbounds workspace.staged_ownership[linear]
    old_owner == new_owner && return nothing
    site = CartesianIndices(runtime.program.shape)[linear]
    source = tracker_source_view(
        runtime.program, workspace.staged_ownership
    )
    commit_tracker_updates!(
        workspace.staged_trackers,
        runtime.program.tracker_plan,
        source,
        site,
        old_owner,
        new_owner,
    )
    @inbounds workspace.staged_ownership[linear] = new_owner
    for rule in plan.ownership_rules
        rule.action === ClearLifecycleOwnershipState || continue
        values = state_block(workspace.staged_descriptor_state, rule.handle).values
        @inbounds values[linear] = zero(eltype(values))
    end
    return nothing
end

@inline function _state_rule_value(
        runtime,
        plan,
        workspace,
        descriptor,
        rule,
        evaluator,
        request,
        source,
        destination,
        role,
    )
    source_generation = source > 0 ?
        @inbounds(runtime.cell_generations[source]) : UInt32(0)
    destination_generation = destination > 0 ?
        @inbounds(workspace.staged_cell_generations[destination]) : UInt32(0)
    anchor = source > 0 ? source : destination
    generation = source > 0 ? source_generation : destination_generation
    context = _LifecycleStateContext(
        runtime,
        descriptor.source_identity,
        descriptor.action_identity,
        descriptor.state_workspace_maximum,
        Int32(request),
        anchor,
        generation,
        source,
        source_generation,
        destination,
        destination_generation,
        role,
        rule.source_identity,
        rule.handle,
        _lifecycle_context_site(runtime, workspace, anchor),
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    return _evaluate_lifecycle_checked(
        plan, evaluator, context, descriptor, workspace
    )
end

function _lifecycle_distribution_draw(
        runtime,
        workspace,
        descriptor,
        family,
        first_parameter,
        second_parameter,
        operation,
        destination,
        generation,
        daughter,
    )
    T = eltype(runtime.parameters)
    first_uniform = _lifecycle_uniform(
        T,
        runtime,
        LifecycleStateStream,
        operation,
        destination,
        generation,
        0;
        destination = true,
        draw = 0,
    )
    family == 1 && return first_uniform < T(first_parameter)
    family == 2 && return muladd(
        first_uniform, T(second_parameter) - T(first_parameter), T(first_parameter)
    )
    if family != 3
        _set_lifecycle_status!(
            workspace,
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor = destination,
            detail = LifecycleDetailUnknownDistribution,
        )
        return LifecycleEvaluationFailed()
    end
    iszero(second_parameter) && return T(first_parameter)
    second_uniform = _lifecycle_uniform(
        T,
        runtime,
        LifecycleStateStream,
        operation,
        destination,
        generation,
        0;
        destination = true,
        draw = 1,
    )
    normal = sqrt(-T(2) * log(first_uniform)) * cos(T(2pi) * second_uniform)
    return muladd(T(second_parameter), normal, T(first_parameter))
end

function _apply_lifecycle_state_rule!(
        rule,
        runtime,
        plan,
        workspace,
        descriptor,
        request::Int,
        source::Int32,
        destination::Int32,
    )
    values = state_block(
        workspace.staged_descriptor_state, rule.handle
    ).values
    source_generation = source > 0 ?
        @inbounds(runtime.cell_generations[source]) : UInt32(0)
    destination_generation = destination > 0 ?
        @inbounds(workspace.staged_cell_generations[destination]) : UInt32(0)
    if rule.action === InitializeLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, DestinationLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[destination] = value_a
    elseif rule.action === RetireToLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, SourceLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[source] = value_a
    elseif rule.action === PreserveLifecycleState
        nothing
    elseif rule.action in (ResetLifecycleState, TransformLifecycleState)
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, SourceLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[source] = value_a
    elseif rule.action === CopyDaughtersLifecycleState
        @inbounds values[destination] = values[source]
    elseif rule.action === PreserveParentResetDaughterLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        @inbounds values[destination] = value_a
    elseif rule.action === ResetBothLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_b isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif rule.action === SplitConservativelyLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        if !(isfinite(value_a) && zero(value_a) <= value_a <= one(value_a))
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusEvaluator;
                source = descriptor.source_handle,
                anchor = source,
                detail = LifecycleDetailSplitFractionOutOfBounds,
            )
        end
        old = @inbounds values[source]
        fraction = value_a
        parent = old * fraction
        daughter = old - parent
        if eltype(values) <: Integer
            parent = rule.rounding === FloorLifecycleRounding ? floor(parent) :
                rule.rounding === CeilLifecycleRounding ? ceil(parent) :
                rule.rounding === NearestLifecycleRounding ? round(parent) : parent
            daughter = old - parent
        end
        @inbounds begin
            values[source] = parent
            values[destination] = daughter
        end
    elseif rule.action === TransformDaughtersLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        value_a isa LifecycleEvaluationFailed && return false
        value_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, DaughterLifecycleStateRole,
        )
        value_b isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif rule.action === RedrawDaughtersLifecycleState
        first_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_a, request,
            source, destination, ParentLifecycleStateRole,
        )
        first_a isa LifecycleEvaluationFailed && return false
        second_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_b, request,
            source, destination, ParentLifecycleStateRole,
        )
        second_a isa LifecycleEvaluationFailed && return false
        first_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_c, request,
            source, destination, DaughterLifecycleStateRole,
        )
        first_b isa LifecycleEvaluationFailed && return false
        second_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule, rule.evaluator_d, request,
            source, destination, DaughterLifecycleStateRole,
        )
        second_b isa LifecycleEvaluationFailed && return false
        parent_value = _lifecycle_distribution_draw(
            runtime,
            workspace,
            descriptor,
            rule.parent_distribution,
            first_a,
            second_a,
            rule.parent_draw,
            source,
            source_generation,
            false,
        )
        parent_value isa LifecycleEvaluationFailed && return false
        daughter_value = _lifecycle_distribution_draw(
            runtime,
            workspace,
            descriptor,
            rule.daughter_distribution,
            first_b,
            second_b,
            rule.daughter_draw,
            destination,
            destination_generation,
            true,
        )
        daughter_value isa LifecycleEvaluationFailed && return false
        @inbounds begin
            values[source] = parent_value
            values[destination] = daughter_value
        end
    else
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            source = descriptor.source_handle,
            anchor = source,
            detail = LifecycleDetailUnsupportedStatePolicy,
        )
    end
    return true
end

function _apply_lifecycle_state_rules!(
        runtime, plan, workspace, descriptor, request, source, destination
    )
    for offset in 0:(Int(descriptor.state_rule_count) - 1)
        index = Int(descriptor.state_rule_offset) + offset
        succeeded = call_lifecycle_state_rule(
            _apply_lifecycle_state_rule!,
            plan.state_rules,
            index,
            runtime,
            plan,
            workspace,
            descriptor,
            request,
            source,
            destination,
        )
        succeeded || return false
    end
    return true
end

function _remove_all_incident!(state, anchor)
    while @inbounds(state.degree[anchor]) > 0
        edge = Int(@inbounds state.incident_edges[1, anchor])
        apply_validated_relationship_request!(
            state, RemoveRelationshipRequest(edge)
        )
    end
    return state
end

function _apply_relationship_rule!(
        state, runtime, workspace, descriptor, rule, anchor
    )
    if rule.action === RemoveIncidentLifecycleRelationship
        return _remove_all_incident!(state, anchor)
    elseif rule.action in (
            PreserveCompatibleLifecycleRelationship,
            RemoveIncompatibleLifecycleRelationship,
        )
        destination_kind = descriptor.destination_kind
        position = 1
        while position <= @inbounds(state.degree[anchor])
            edge = Int(@inbounds state.incident_edges[position, anchor])
            other = @inbounds state.endpoint_a[edge] == anchor ?
                state.endpoint_b[edge] : state.endpoint_a[edge]
            other_kind = @inbounds workspace.staged_cell_kinds[other]
            compatible = _relationship_kinds_match(
                destination_kind, other_kind, rule
            )
            if !compatible && rule.action === RemoveIncompatibleLifecycleRelationship
                apply_validated_relationship_request!(
                    state, RemoveRelationshipRequest(edge)
                )
            else
                position += 1
            end
        end
    end
    return state
end

function _apply_lifecycle_relationship_rules!(
        runtime, plan, workspace, descriptor, anchor
    )
    for offset in 0:(Int(descriptor.relationship_rule_count) - 1)
        rule = @inbounds plan.relationship_rules[
            Int(descriptor.relationship_rule_offset) + offset
        ]
        _call_relationship_slot(
            _apply_relationship_rule!,
            workspace.staged_relationships,
            rule.relationship_slot,
            (runtime, workspace, descriptor, rule, Int(anchor)),
        )
    end
    return nothing
end

function _allocated_generation(runtime, slot)
    generation = @inbounds runtime.cell_generations[slot]
    return iszero(generation) ? UInt32(1) : generation + UInt32(1)
end

function _apply_lifecycle_request!(runtime, plan, workspace, request)
    descriptor = @inbounds plan.descriptors[Int(workspace.descriptor[request])]
    anchor = @inbounds workspace.anchor[request]
    allocation = @inbounds workspace.allocation[request]
    if descriptor.effect === CreateCellLifecycleEffect
        generation = _allocated_generation(runtime, allocation)
        @inbounds begin
            workspace.staged_cell_kinds[allocation] = descriptor.destination_kind
            workspace.staged_cell_generations[allocation] = generation
        end
        for position in 1:Int(workspace.planned_site_count[request])
            linear = Int(@inbounds workspace.planned_sites[position, request])
            _stage_owner_change!(runtime, plan, workspace, linear, allocation)
        end
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, Int32(0), allocation
        ) || return -1
    elseif descriptor.effect === RemoveCellLifecycleEffect
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        for position in _cell_site_range(workspace, anchor)
            linear = Int(@inbounds workspace.cell_sites[position])
            _stage_owner_change!(
                runtime,
                plan,
                workspace,
                linear,
                -Int32(descriptor.replacement_medium),
            )
        end
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, Int32(0)
        ) || return -1
        @inbounds workspace.staged_cell_kinds[anchor] = 0
    elseif descriptor.effect === RetireCellLifecycleEffect
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, Int32(0)
        ) || return -1
        @inbounds workspace.staged_cell_kinds[anchor] = 0
    elseif descriptor.effect === TransitionCellLifecycleEffect
        @inbounds workspace.staged_cell_kinds[anchor] = descriptor.destination_kind
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, Int32(0)
        ) || return -1
    elseif descriptor.effect === DivideCellLifecycleEffect
        generation = _allocated_generation(runtime, allocation)
        parent_kind = descriptor.parent_kind == 0 ?
            @inbounds(runtime.cell_kinds[anchor]) : descriptor.parent_kind
        daughter_kind = descriptor.daughter_kind == 0 ?
            @inbounds(runtime.cell_kinds[anchor]) : descriptor.daughter_kind
        @inbounds begin
            workspace.staged_cell_kinds[anchor] = parent_kind
            workspace.staged_cell_kinds[allocation] = daughter_kind
            workspace.staged_cell_generations[allocation] = generation
        end
        reason = _plan_division!(runtime, plan, workspace, request, descriptor)
        reason === :status_failure && return -1
        if reason !== :ok
            _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                source = descriptor.source_handle,
                anchor,
                detail = _lifecycle_detail_code(reason),
            )
            return -1
        end
        for position in _cell_site_range(workspace, anchor)
            @inbounds workspace.partition_labels[position] == 2 || continue
            linear = Int(@inbounds workspace.cell_sites[position])
            _stage_owner_change!(runtime, plan, workspace, linear, allocation)
        end
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, request, anchor, allocation
        ) || return -1
    end
    return descriptor.effect in (
        RemoveCellLifecycleEffect, RetireCellLifecycleEffect
    ) ? 1 : 0
end

@inline _validate_tracker_storage_shapes!(::Tuple{}, ::Tuple{}, cell_count) = nothing

@inline function _validate_tracker_storage_shapes!(
        descriptors::Tuple{D, Vararg}, values::Tuple{V, Vararg}, cell_count
    ) where {D, V}
    _validate_tracker_state(
        tracker_storage(first(descriptors)), first(values), cell_count
    )
    _validate_tracker_storage_shapes!(
        Base.tail(descriptors), Base.tail(values), cell_count
    )
    return nothing
end

function _validate_staged_lifecycle!(runtime, plan, workspace)
    tracker_plan = runtime.program.tracker_plan
    length(tracker_plan.descriptors) == length(workspace.staged_trackers.values) ||
        return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            detail = LifecycleDetailTrackerPlanStateMisalignment,
        )
    _validate_tracker_storage_shapes!(
        tracker_plan.descriptors,
        workspace.staged_trackers.values,
        length(workspace.staged_cell_kinds),
    )
    volumes = tracker_values(
        runtime.program.tracker_plan,
        workspace.staged_trackers,
        Val(:cell_volume),
    )
    for cell in eachindex(workspace.staged_cell_kinds)
        active = @inbounds workspace.staged_cell_kinds[cell] != 0
        occupied = @inbounds volumes[cell] != 0
        active == occupied || return _set_lifecycle_status!(
            workspace,
            LifecycleStatusInvariant;
            anchor = cell,
            detail = LifecycleDetailActiveOccupancyMismatch,
        )
        if active && @inbounds plan.forbid_extinction[
                workspace.staged_cell_kinds[cell]
            ] && !occupied
            return _set_lifecycle_status!(
                workspace,
                LifecycleStatusInvariant;
                anchor = cell,
                detail = LifecycleDetailForbiddenExtinction,
            )
        end
    end
    for slot in eachindex(workspace.staged_relationships)
        validate_relationship_integrity(
            workspace.staged_relationships[slot],
            runtime.program.relationships[slot],
            workspace.staged_cell_kinds,
            workspace.staged_cell_generations,
        )
    end
    for entry in runtime.program.descriptor_plan.state_layout.entries
        validate_state_block(
            entry.schema,
            state_block(workspace.staged_descriptor_state, entry.handle),
        )
    end
    return true
end

function _stage_lifecycle_transactions!(
        runtime, plan, workspace, selected_count
    )
    copyto!(workspace.staged_ownership, runtime.ownership)
    copyto!(workspace.staged_cell_kinds, runtime.cell_kinds)
    copyto!(workspace.staged_cell_generations, runtime.cell_generations)
    copyto_tracker_state!(workspace.staged_trackers, runtime.trackers)
    copyto!(workspace.staged_relationships, runtime.relationships)
    copyto_auxiliary_state!(
        workspace.staged_descriptor_state, runtime.descriptor_state
    )
    retired = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        result = _apply_lifecycle_request!(runtime, plan, workspace, request)
        result < 0 && return -1
        retired += result
    end
    _validate_staged_lifecycle!(runtime, plan, workspace) || return -1
    return retired
end

function _publish_lifecycle_transactions!(runtime, workspace, retired)
    copyto!(runtime.ownership, workspace.staged_ownership)
    copyto!(runtime.cell_kinds, workspace.staged_cell_kinds)
    copyto!(runtime.cell_generations, workspace.staged_cell_generations)
    copyto_tracker_state!(runtime.trackers, workspace.staged_trackers)
    copyto!(runtime.relationships, workspace.staged_relationships)
    copyto_auxiliary_state!(
        runtime.descriptor_state, workspace.staged_descriptor_state
    )
    runtime.retired_cells += retired
    return runtime
end

_execute_lifecycle_status!(
    runtime, ::NoLifecycleExecutionPlan, ::NoLifecycleWorkspace
) = true

function _execute_lifecycle_status!(
        runtime,
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
    )
    _reset_lifecycle_workspace!(workspace)
    _index_lifecycle_representative_sites!(runtime, workspace) || return false
    _emit_lifecycle_requests!(runtime, plan, workspace) || return false
    _filter_lifecycle_requests!(runtime, plan, workspace) || return false
    _resolve_lifecycle_conflicts!(runtime, plan, workspace) || return false
    selected_count = _preflight_lifecycle_capacity!(runtime, plan, workspace)
    selected_count < 0 && return false
    iszero(selected_count) && return true
    retired = _stage_lifecycle_transactions!(
        runtime, plan, workspace, selected_count
    )
    retired < 0 && return false
    _publish_lifecycle_transactions!(runtime, workspace, retired)
    return true
end

function _translate_lifecycle_status(status::LifecycleStatusPayload)
    code = status.code
    code === LifecycleStatusSuccess && return nothing
    reason = _lifecycle_detail_symbol(status.detail)
    code === LifecycleStatusInadmissible && return LifecycleInadmissibilityFailure(
        status.source, status.anchor, reason
    )
    code === LifecycleStatusConflict && return LifecycleConflictFailure(
        status.source, status.secondary_source, status.anchor
    )
    code === LifecycleStatusCellCapacity && return CellCapacityFailure(
        status.maximum, status.required, status.available
    )
    code === LifecycleStatusRelationshipCapacity &&
        return RelationshipCapacityFailure(status.source)
    code === LifecycleStatusStaleGeneration &&
        return StaleGenerationFailure(status.anchor)
    code === LifecycleStatusGenerationOverflow &&
        return GenerationOverflowFailure(status.anchor)
    code === LifecycleStatusEvaluator && return LifecycleEvaluatorFailure(
        status.source, status.anchor, reason
    )
    code === LifecycleStatusFootprint && return LifecycleFootprintFailure(
        status.source, status.anchor, reason
    )
    code === LifecycleStatusInvariant && return LifecycleInvariantFailure(
        status.source, status.anchor, reason
    )
    return LifecycleBackendFailure(nothing)
end

function execute_lifecycle!(runtime)
    backend_error = nothing
    succeeded = try
        _execute_lifecycle_status!(
            runtime, runtime.program.lifecycle_plan, runtime.lifecycle_workspace
        )
    catch error
        backend_error = error
        workspace = runtime.lifecycle_workspace
        workspace isa LifecycleWorkspace && _set_lifecycle_status!(
            workspace, LifecycleStatusBackend
        )
        false
    end
    backend_error === nothing || throw(LifecycleBackendFailure(backend_error))
    succeeded && return runtime
    failure = _translate_lifecycle_status(runtime.lifecycle_workspace.status)
    failure === nothing && return runtime
    throw(failure)
end
