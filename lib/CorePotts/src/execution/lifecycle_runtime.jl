# Engine-neutral lifecycle transaction orchestration. The sequential engine
# calls this reference path directly; later engines reuse the same plan,
# request ordering, status, and publication contracts.

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
    for linear in eachindex(runtime.ownership)
        owner = @inbounds runtime.ownership[linear]
        owner > 0 || continue
        owner <= length(workspace.representative_site) || throw(
            LifecycleInvariantFailure(
                Int32(0), owner, :ownership_exceeds_cell_capacity
            )
        )
        @inbounds iszero(workspace.representative_site[owner]) &&
            (workspace.representative_site[owner] = Int32(linear))
    end
    return workspace
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
    )
    try
        value = evaluate_lifecycle(plan.evaluators, index, context)
        if value isa AbstractFloat && !isfinite(value)
            throw(LifecycleEvaluatorFailure(
                descriptor.source_handle, context.anchor, :nonfinite_result
            ))
        end
        return value
    catch error
        error isa AbstractLifecycleFailure && rethrow()
        throw(LifecycleEvaluatorFailure(
            descriptor.source_handle, context.anchor, :evaluation_error
        ))
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
    index <= length(workspace.descriptor) || throw(
        LifecycleFootprintFailure(
            descriptor.source_handle, anchor, :request_bound_exceeded
        )
    )
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
                Int32(0),
                UInt32(0),
                _lifecycle_context_site(runtime, workspace, Int32(0)),
                Int32(0),
                UInt16(descriptor.source_handle),
            )
            enabled = _evaluate_lifecycle_checked(
                plan, descriptor.trigger_evaluator, context, descriptor
            )
            enabled isa Bool || throw(LifecycleEvaluatorFailure(
                descriptor.source_handle, 0, :trigger_not_boolean
            ))
            enabled && _emit_lifecycle_request!(
                workspace,
                descriptor_index,
                descriptor,
                Int32(0),
                UInt32(0),
            )
        else
            for cell in eachindex(runtime.cell_kinds)
                kind = @inbounds runtime.cell_kinds[cell]
                kind == descriptor.domain_kind || continue
                generation = @inbounds runtime.cell_generations[cell]
                iszero(generation) && throw(StaleGenerationFailure(Int32(cell)))
                context = _LifecycleTriggerContext(
                    runtime,
                    Int32(cell),
                    generation,
                    _lifecycle_context_site(runtime, workspace, Int32(cell)),
                    Int32(0),
                    UInt16(descriptor.source_handle),
                )
                enabled = _evaluate_lifecycle_checked(
                    plan, descriptor.trigger_evaluator, context, descriptor
                )
                enabled isa Bool || throw(LifecycleEvaluatorFailure(
                    descriptor.source_handle, Int32(cell), :trigger_not_boolean
                ))
                enabled && _emit_lifecycle_request!(
                    workspace,
                    descriptor_index,
                    descriptor,
                    Int32(cell),
                    generation,
                )
            end
        end
    end
    return workspace
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
        anchor,
        generation,
        site,
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    center = _evaluate_lifecycle_checked(
        plan, descriptor.placement_evaluator, context, descriptor
    )
    center isa Integer || return :placement_not_integral
    center = Int(center)
    1 <= center <= length(runtime.ownership) || return :placement_out_of_bounds
    count = descriptor.placement === SeedStencilLifecyclePlacement ?
        Int(descriptor.stencil_count) : 1
    count <= size(workspace.planned_sites, 1) || throw(
        LifecycleFootprintFailure(
            descriptor.source_handle, anchor, :placement_bound_exceeded
        )
    )
    for position in 1:count
        selected = if descriptor.placement === SeedStencilLifecyclePlacement
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
    labels = view(workspace.partition_labels, :, request)
    fill!(workspace.site_seen, false)
    first_site = findfirst(==(label), labels)
    first_site === nothing && return false
    head = 1
    tail = 1
    workspace.site_queue[1] = Int32(first_site)
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
            @inbounds labels[neighbor_linear] == label || continue
            @inbounds workspace.site_seen[neighbor_linear] && continue
            tail += 1
            @inbounds begin
                workspace.site_queue[tail] = Int32(neighbor_linear)
                workspace.site_seen[neighbor_linear] = true
            end
        end
    end
    return visited == count(==(label), labels)
end

function _plan_division!(runtime, plan, workspace, request, descriptor)
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    labels = view(workspace.partition_labels, :, request)
    fill!(labels, 0)
    external = descriptor.partition === ExternalLifecyclePartition
    center = external ? nothing : descriptor.point_from_centroid ?
        _cell_center(runtime, anchor) : descriptor.point
    !external && center === nothing && return :empty_source_cell
    normal = external ? nothing :
        _partition_normal(runtime, descriptor, anchor, generation)
    first_count = 0
    second_count = 0
    for linear in eachindex(runtime.ownership)
        @inbounds runtime.ownership[linear] == anchor || continue
        site = CartesianIndices(runtime.program.shape)[linear]
        label = if descriptor.partition === ExternalLifecyclePartition
            context = _LifecyclePartitionContext(
                runtime,
                anchor,
                generation,
                site,
                Int32(0),
                UInt16(descriptor.source_handle),
            )
            value = _evaluate_lifecycle_checked(
                plan, descriptor.partition_evaluator, context, descriptor
            )
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
        @inbounds labels[linear] = label
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
            for index in eachindex(labels)
                @inbounds labels[index] == 1 ? (labels[index] = 2) :
                    labels[index] == 2 && (labels[index] = 1)
            end
        end
    end
    _partition_connected(
        runtime, plan, workspace, request, descriptor, UInt8(1)
    ) || return :partition_parent_disconnected
    _partition_connected(
        runtime, plan, workspace, request, descriptor, UInt8(2)
    ) || return :partition_daughter_disconnected
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
        1 <= anchor <= length(runtime.cell_kinds) ||
            throw(StaleGenerationFailure(anchor))
        @inbounds runtime.cell_generations[anchor] == generation ||
            throw(StaleGenerationFailure(anchor))
        @inbounds runtime.cell_kinds[anchor] != 0 ||
            throw(StaleGenerationFailure(anchor))
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
        reason === :ok && continue
        if descriptor.on_inadmissible === FilterLifecycleInadmissible
            @inbounds begin
                workspace.active[request] = false
                workspace.filtered[request] = true
            end
        else
            throw(LifecycleInadmissibilityFailure(
                descriptor.source_handle,
                @inbounds(workspace.anchor[request]),
                reason,
            ))
        end
    end
    return workspace
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
        for right in 1:count
            @inbounds workspace.active[right] || continue
            for left in 1:(right - 1)
                @inbounds workspace.active[left] || continue
                _lifecycle_requests_conflict(
                    runtime, plan, workspace, left, right
                ) || continue
                throw(LifecycleConflictFailure(
                    plan.descriptors[Int(workspace.descriptor[left])].source_handle,
                    plan.descriptors[Int(workspace.descriptor[right])].source_handle,
                    workspace.anchor[right],
                ))
            end
            @inbounds workspace.selected[right] = true
        end
        return workspace
    end
    fill!(workspace.conflict_seen, false)
    for seed in 1:count
        @inbounds workspace.active[seed] || continue
        @inbounds workspace.conflict_seen[seed] && continue
        head = 1
        tail = 1
        workspace.canonical_order[1] = Int32(seed)
        workspace.conflict_seen[seed] = true
        best = seed
        best_priority = plan.descriptors[Int(workspace.descriptor[seed])].priority
        tied = false
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
                priority = plan.descriptors[
                    Int(workspace.descriptor[candidate])
                ].priority
                if priority > best_priority
                    best = candidate
                    best_priority = priority
                    tied = false
                elseif priority == best_priority
                    tied = true
                end
            end
        end
        tied && throw(LifecycleConflictFailure(
            plan.descriptors[Int(workspace.descriptor[best])].source_handle,
            plan.descriptors[Int(workspace.descriptor[seed])].source_handle,
            workspace.anchor[seed],
        ))
        @inbounds workspace.selected[best] = true
    end
    return workspace
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
    requested <= free_count || throw(CellCapacityFailure(
        plan.cell_capacity, Int32(requested), Int32(free_count)
    ))
    allocation_position = 0
    for position in 1:selected_count
        request = Int(@inbounds workspace.canonical_order[position])
        effect = plan.descriptors[Int(workspace.descriptor[request])].effect
        effect in (CreateCellLifecycleEffect, DivideCellLifecycleEffect) || continue
        allocation_position += 1
        slot = @inbounds workspace.free_slots[allocation_position]
        generation = @inbounds runtime.cell_generations[slot]
        generation == typemax(UInt32) && throw(GenerationOverflowFailure(slot))
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
        runtime, plan, workspace, descriptor, evaluator, anchor, generation
    )
    context = _LifecycleStateContext(
        runtime,
        anchor,
        generation,
        _lifecycle_context_site(runtime, workspace, anchor),
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    return _evaluate_lifecycle_checked(plan, evaluator, context, descriptor)
end

function _lifecycle_distribution_draw(
        runtime,
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
    family == 3 || throw(LifecycleEvaluatorFailure(
        descriptor.source_handle, destination, :unknown_distribution
    ))
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
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        @inbounds values[destination] = value_a
    elseif rule.action === RetireToLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        @inbounds values[source] = value_a
    elseif rule.action === PreserveLifecycleState
        nothing
    elseif rule.action in (ResetLifecycleState, TransformLifecycleState)
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        @inbounds values[source] = value_a
    elseif rule.action === CopyDaughtersLifecycleState
        @inbounds values[destination] = values[source]
    elseif rule.action === PreserveParentResetDaughterLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        @inbounds values[destination] = value_a
    elseif rule.action === ResetBothLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        value_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_b, source, source_generation
        )
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif rule.action === SplitConservativelyLifecycleState
        value_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        (isfinite(value_a) && zero(value_a) <= value_a <= one(value_a)) ||
            throw(LifecycleEvaluatorFailure(
                descriptor.source_handle,
                source,
                :split_fraction_out_of_bounds,
            ))
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
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        value_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_b, source, source_generation
        )
        @inbounds begin
            values[source] = value_a
            values[destination] = value_b
        end
    elseif rule.action === RedrawDaughtersLifecycleState
        first_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_a, source, source_generation
        )
        second_a = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_b, source, source_generation
        )
        first_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_c, source, source_generation
        )
        second_b = _state_rule_value(
            runtime, plan, workspace, descriptor, rule.evaluator_d, source, source_generation
        )
        @inbounds begin
            values[source] = _lifecycle_distribution_draw(
                runtime,
                descriptor,
                rule.parent_distribution,
                first_a,
                second_a,
                rule.parent_draw,
                source,
                source_generation,
                false,
            )
            values[destination] = _lifecycle_distribution_draw(
                runtime,
                descriptor,
                rule.daughter_distribution,
                first_b,
                second_b,
                rule.daughter_draw,
                destination,
                destination_generation,
                true,
            )
        end
    else
        throw(LifecycleInvariantFailure(
            descriptor.source_handle, source, :unsupported_state_policy
        ))
    end
    return nothing
end

function _apply_lifecycle_state_rules!(
        runtime, plan, workspace, descriptor, source, destination
    )
    for offset in 0:(Int(descriptor.state_rule_count) - 1)
        index = Int(descriptor.state_rule_offset) + offset
        call_lifecycle_state_rule(
            _apply_lifecycle_state_rule!,
            plan.state_rules,
            index,
            runtime,
            plan,
            workspace,
            descriptor,
            source,
            destination,
        )
    end
    return nothing
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
            runtime, plan, workspace, descriptor, Int32(0), allocation
        )
    elseif descriptor.effect === RemoveCellLifecycleEffect
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        for linear in eachindex(workspace.staged_ownership)
            @inbounds workspace.staged_ownership[linear] == anchor || continue
            _stage_owner_change!(
                runtime,
                plan,
                workspace,
                linear,
                -Int32(descriptor.replacement_medium),
            )
        end
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, anchor, Int32(0)
        )
        @inbounds workspace.staged_cell_kinds[anchor] = 0
    elseif descriptor.effect === RetireCellLifecycleEffect
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, anchor, Int32(0)
        )
        @inbounds workspace.staged_cell_kinds[anchor] = 0
    elseif descriptor.effect === TransitionCellLifecycleEffect
        @inbounds workspace.staged_cell_kinds[anchor] = descriptor.destination_kind
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, anchor, Int32(0)
        )
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
        labels = view(workspace.partition_labels, :, request)
        for linear in eachindex(labels)
            @inbounds labels[linear] == 2 || continue
            _stage_owner_change!(runtime, plan, workspace, linear, allocation)
        end
        _apply_lifecycle_relationship_rules!(
            runtime, plan, workspace, descriptor, anchor
        )
        _apply_lifecycle_state_rules!(
            runtime, plan, workspace, descriptor, anchor, allocation
        )
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
        throw(LifecycleInvariantFailure(
            Int32(0), Int32(0), :tracker_plan_state_misalignment
        ))
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
        active == occupied || throw(LifecycleInvariantFailure(
            Int32(0), Int32(cell), :active_occupancy_mismatch
        ))
        if active && @inbounds plan.forbid_extinction[
                workspace.staged_cell_kinds[cell]
            ] && !occupied
            throw(LifecycleInvariantFailure(
                Int32(0), Int32(cell), :forbidden_extinction
            ))
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
    return workspace
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
        retired += _apply_lifecycle_request!(runtime, plan, workspace, request)
    end
    _validate_staged_lifecycle!(runtime, plan, workspace)
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

_execute_lifecycle!(runtime, ::NoLifecycleExecutionPlan, ::NoLifecycleWorkspace) =
    runtime

function _record_lifecycle_failure!(workspace, error)
    workspace.status = error isa LifecycleInadmissibilityFailure ?
        LifecycleStatusInadmissible :
        error isa LifecycleConflictFailure ? LifecycleStatusConflict :
        error isa CellCapacityFailure ? LifecycleStatusCellCapacity :
        error isa RelationshipCapacityFailure ? LifecycleStatusRelationshipCapacity :
        error isa StaleGenerationFailure ? LifecycleStatusStaleGeneration :
        error isa GenerationOverflowFailure ? LifecycleStatusGenerationOverflow :
        error isa LifecycleEvaluatorFailure ? LifecycleStatusEvaluator :
        error isa LifecycleFootprintFailure ? LifecycleStatusFootprint :
        error isa LifecycleInvariantFailure ? LifecycleStatusInvariant :
        LifecycleStatusBackend
    if hasproperty(error, :source)
        workspace.status_source = Int32(getproperty(error, :source))
    elseif hasproperty(error, :first_source)
        workspace.status_source = Int32(getproperty(error, :first_source))
    end
    hasproperty(error, :anchor) &&
        (workspace.status_anchor = Int32(getproperty(error, :anchor)))
    return workspace
end

function _execute_lifecycle!(
        runtime,
        plan::LifecycleExecutionPlan,
        workspace::LifecycleWorkspace,
    )
    _reset_lifecycle_workspace!(workspace)
    try
        _index_lifecycle_representative_sites!(runtime, workspace)
        _emit_lifecycle_requests!(runtime, plan, workspace)
        _filter_lifecycle_requests!(runtime, plan, workspace)
        _resolve_lifecycle_conflicts!(runtime, plan, workspace)
        selected_count = _preflight_lifecycle_capacity!(runtime, plan, workspace)
        iszero(selected_count) && return runtime
        retired = _stage_lifecycle_transactions!(
            runtime, plan, workspace, selected_count
        )
        _publish_lifecycle_transactions!(runtime, workspace, retired)
        return runtime
    catch error
        translated = error isa AbstractLifecycleFailure ? error :
            LifecycleBackendFailure(error)
        _record_lifecycle_failure!(workspace, translated)
        throw(translated)
    end
end

function execute_lifecycle!(runtime)
    return _execute_lifecycle!(
        runtime, runtime.program.lifecycle_plan, runtime.lifecycle_workspace
    )
end
