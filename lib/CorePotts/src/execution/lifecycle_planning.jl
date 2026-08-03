# Source-local admissibility and immutable request planning.

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
