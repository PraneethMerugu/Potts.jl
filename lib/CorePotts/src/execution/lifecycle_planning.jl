# Source-local admissibility and immutable request planning.

abstract type _AbstractLifecyclePlanClass end
struct _CreateLifecyclePlan <: _AbstractLifecyclePlanClass end
struct _RetireLifecyclePlan <: _AbstractLifecyclePlanClass end
struct _RemoveLifecyclePlan <: _AbstractLifecyclePlanClass end
struct _TransitionLifecyclePlan <: _AbstractLifecyclePlanClass end
struct _DivideLifecyclePlan <: _AbstractLifecyclePlanClass end

abstract type _AbstractLifecyclePartitionPlan end
struct _RandomPlanePartitionPlan <: _AbstractLifecyclePartitionPlan end
struct _PrincipalMajorPartitionPlan <: _AbstractLifecyclePartitionPlan end
struct _PrincipalMinorPartitionPlan <: _AbstractLifecyclePartitionPlan end
struct _SpecifiedNormalPartitionPlan <: _AbstractLifecyclePartitionPlan end
struct _ExternalPartitionPlan <: _AbstractLifecyclePartitionPlan end

abstract type _AbstractLifecycleSidePlan end
struct _CanonicalSidePlan <: _AbstractLifecycleSidePlan end
struct _StableRandomSidePlan <: _AbstractLifecycleSidePlan end

struct _DivideLifecycleVariantPlan{
        P <: _AbstractLifecyclePartitionPlan,
        S <: _AbstractLifecycleSidePlan,
    } <: _AbstractLifecyclePlanClass
    partition::P
    side::S
end

@inline _lifecycle_plan_effect(::_CreateLifecyclePlan) =
    CreateCellLifecycleEffect
@inline _lifecycle_plan_effect(::_RetireLifecyclePlan) =
    RetireCellLifecycleEffect
@inline _lifecycle_plan_effect(::_RemoveLifecyclePlan) =
    RemoveCellLifecycleEffect
@inline _lifecycle_plan_effect(::_TransitionLifecyclePlan) =
    TransitionCellLifecycleEffect
@inline _lifecycle_plan_effect(::_DivideLifecyclePlan) =
    DivideCellLifecycleEffect
@inline _lifecycle_plan_effect(::_DivideLifecycleVariantPlan) =
    DivideCellLifecycleEffect

@inline _lifecycle_partition_code(::_RandomPlanePartitionPlan) =
    RandomPlaneLifecyclePartition
@inline _lifecycle_partition_code(::_PrincipalMajorPartitionPlan) =
    PrincipalMajorLifecyclePartition
@inline _lifecycle_partition_code(::_PrincipalMinorPartitionPlan) =
    PrincipalMinorLifecyclePartition
@inline _lifecycle_partition_code(::_SpecifiedNormalPartitionPlan) =
    SpecifiedNormalLifecyclePartition
@inline _lifecycle_partition_code(::_ExternalPartitionPlan) =
    ExternalLifecyclePartition

@inline _lifecycle_side_code(::_CanonicalSidePlan) = CanonicalLifecycleSide
@inline _lifecycle_side_code(::_StableRandomSidePlan) =
    StableRandomLifecycleSide

@inline _lifecycle_plan_matches(descriptor, plan_class) =
    descriptor.effect === _lifecycle_plan_effect(plan_class)
@inline function _lifecycle_plan_matches(
        descriptor, plan_class::_DivideLifecycleVariantPlan
    )
    return descriptor.effect === DivideCellLifecycleEffect &&
           descriptor.partition === _lifecycle_partition_code(
               plan_class.partition
           ) &&
           descriptor.side === _lifecycle_side_code(plan_class.side)
end

function _plan_creation!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
    )
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    site = _lifecycle_context_site(runtime, workspace, anchor)
    context = _LifecyclePlacementContext(
        runtime,
        descriptor.source_identity,
        descriptor.action_identity,
        descriptor.placement_workspace_maximum,
        Int32(0),
        Int32(request),
        anchor,
        generation,
        site,
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    result = _evaluate_lifecycle_checked(
        mode, plan, descriptor.placement_evaluator, context, descriptor, workspace
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
            ProgramStatusFootprint;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailPlacementEmissionBoundExceeded,
        )
        return :status_failure
    end
    if count > size(workspace.planned_sites, 1)
        _set_lifecycle_status!(
            workspace,
            ProgramStatusFootprint;
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

@inline _partition_normal(
    runtime, descriptor, anchor, generation, ::_SpecifiedNormalPartitionPlan
) = descriptor.normal

@inline function _partition_normal(
        runtime, descriptor, anchor, generation, ::_RandomPlanePartitionPlan
    )
    T = eltype(runtime.parameters)
    N = length(runtime.program.shape)
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
end

@inline function _principal_partition_normal(
        runtime, anchor, ::Val{Major}
    ) where {Major}
    T = eltype(runtime.parameters)
    length(runtime.program.shape) == 2 || return nothing
    statistics = _cell_shape_statistics(runtime, anchor)
    statistics === nothing && return nothing
    covariance = statistics[3]
    a, b, d = covariance[1], covariance[2], covariance[4]
    λmajor = _maximum_covariance_eigenvalue(Val(2), covariance)
    λ = Major ? λmajor : a + d - λmajor
    vector = abs(b) > eps(T) ? (b, λ - a) :
        abs(a - λ) <= abs(d - λ) ? (one(T), zero(T)) :
        (zero(T), one(T))
    norm = sqrt(vector[1]^2 + vector[2]^2)
    return (vector[1] / norm, vector[2] / norm)
end

@inline _partition_normal(
    runtime, descriptor, anchor, generation, ::_PrincipalMajorPartitionPlan
) = _principal_partition_normal(runtime, anchor, Val(true))
@inline _partition_normal(
    runtime, descriptor, anchor, generation, ::_PrincipalMinorPartitionPlan
) = _principal_partition_normal(runtime, anchor, Val(false))

function _label_division_sites!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor::LifecycleDescriptor{N, T},
        partition_plan::_AbstractLifecyclePartitionPlan,
    ) where {N, T}
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    positions = _cell_site_range(workspace, anchor)
    center = descriptor.point_from_centroid ?
        _cell_center(runtime, anchor) : descriptor.point
    center === nothing && return :empty_source_cell
    normal = _partition_normal(
        runtime, descriptor, anchor, generation, partition_plan
    )
    normal === nothing && return :partition_geometry_invalid
    center_value = center::NTuple{N, T}
    normal_value = normal::NTuple{N, T}
    for position in positions
        linear = Int(@inbounds workspace.cell_sites[position])
        site = CartesianIndices(runtime.program.shape)[linear]
        projection = zero(T)
        for dimension in 1:N
            projection += (
                T(site[dimension]) - T(0.5) - center_value[dimension]
            ) * normal_value[dimension]
        end
        @inbounds workspace.partition_scratch[position] =
            projection <= 0 ? UInt8(1) : UInt8(2)
    end
    return :ok
end

function _label_division_sites!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor::LifecycleDescriptor{N, T},
        ::_ExternalPartitionPlan,
    ) where {N, T}
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    positions = _cell_site_range(workspace, anchor)
    for position in positions
        linear = Int(@inbounds workspace.cell_sites[position])
        site = CartesianIndices(runtime.program.shape)[linear]
        context = _LifecyclePartitionContext(
            runtime,
            descriptor.source_identity,
            descriptor.action_identity,
            descriptor.partition_workspace_maximum,
            Int32(0),
            Int32(request),
            anchor,
            generation,
            site,
            Int32(0),
            UInt16(descriptor.source_handle),
        )
        value = _evaluate_lifecycle_checked(
            mode,
            plan,
            descriptor.partition_evaluator,
            context,
            descriptor,
            workspace,
        )
        value isa LifecycleEvaluationFailed && return :status_failure
        value isa Integer && value in (1, 2) ||
            return :partition_label_invalid
        @inbounds workspace.partition_scratch[position] = UInt8(value)
    end
    return :ok
end

@inline _apply_division_side!(
    runtime, workspace, request, descriptor, ::_CanonicalSidePlan
) = nothing

function _apply_division_side!(
        runtime, workspace, request, descriptor, ::_StableRandomSidePlan
    )
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    flip = _lifecycle_uniform(
        eltype(runtime.parameters),
        runtime,
        LifecyclePartitionStream,
        descriptor.side_draw,
        anchor,
        generation,
        0,
    ) < eltype(runtime.parameters)(0.5)
    flip || return nothing
    for position in _cell_site_range(workspace, anchor)
        @inbounds workspace.partition_scratch[position] == 1 ?
            (workspace.partition_scratch[position] = 2) :
            workspace.partition_scratch[position] == 2 &&
            (workspace.partition_scratch[position] = 1)
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
        @inbounds workspace.partition_scratch[position] == label || continue
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
    relation = lifecycle_relation(
        plan.relations, Int(descriptor.relation_slot)
    )
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
                ProgramStatusInvariant;
                source = descriptor.source_handle,
                anchor,
                detail = LifecycleDetailCellSiteIndexMissingOwnedSite,
            )
            @inbounds workspace.partition_scratch[position] == label || continue
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

@inline function _lifecycle_partition_plan(code::LifecyclePartitionCode)
    code === RandomPlaneLifecyclePartition && return _RandomPlanePartitionPlan()
    code === PrincipalMajorLifecyclePartition && return _PrincipalMajorPartitionPlan()
    code === PrincipalMinorLifecyclePartition && return _PrincipalMinorPartitionPlan()
    code === SpecifiedNormalLifecyclePartition && return _SpecifiedNormalPartitionPlan()
    code === ExternalLifecyclePartition && return _ExternalPartitionPlan()
    return nothing
end

@inline function _lifecycle_side_plan(code::LifecycleSideCode)
    code === CanonicalLifecycleSide && return _CanonicalSidePlan()
    code === StableRandomLifecycleSide && return _StableRandomSidePlan()
    return nothing
end

function _plan_division!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        partition_plan::_AbstractLifecyclePartitionPlan,
        side_plan::_AbstractLifecycleSidePlan,
    )
    anchor = @inbounds workspace.anchor[request]
    positions = _cell_site_range(workspace, anchor)
    for position in positions
        @inbounds workspace.partition_scratch[position] = 0
    end
    reason = _label_division_sites!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        partition_plan,
    )
    reason === :ok || return reason
    first_count = 0
    second_count = 0
    for position in positions
        label = @inbounds workspace.partition_scratch[position]
        label == 1 ? (first_count += 1) : (second_count += 1)
    end
    first_count > 0 && second_count > 0 || return :partition_empty_descendant
    _apply_division_side!(
        runtime, workspace, request, descriptor, side_plan
    )
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
    for position in positions
        @inbounds workspace.partition_labels[position] =
            workspace.partition_scratch[position]
    end
    @inbounds workspace.partition_owner[anchor] = Int32(request)
    return :ok
end

function _plan_division!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
    )
    partition_plan = _lifecycle_partition_plan(descriptor.partition)
    partition_plan === nothing && return :partition_geometry_invalid
    side_plan = _lifecycle_side_plan(descriptor.side)
    side_plan === nothing && return :partition_geometry_invalid
    return _plan_division!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        partition_plan,
        side_plan,
    )
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

@inline function _plan_lifecycle_effect!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        ::_CreateLifecyclePlan,
    )
    return _plan_creation!(
        mode, runtime, plan, workspace, request, descriptor
    )
end

@inline function _plan_lifecycle_effect!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        ::_RetireLifecyclePlan,
    )
    anchor = @inbounds workspace.anchor[request]
    return program_tracker_value(runtime, Val(:cell_volume), anchor) == 0 ?
        :ok : :retire_nonempty
end

@inline _plan_lifecycle_effect!(
    mode, runtime, plan, workspace, request, descriptor, ::_RemoveLifecyclePlan
) = :ok

@inline _plan_lifecycle_effect!(
    mode,
    runtime,
    plan,
    workspace,
    request,
    descriptor,
    ::_TransitionLifecyclePlan,
) = :ok

@inline function _plan_lifecycle_effect!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        ::_DivideLifecyclePlan,
    )
    return _plan_division!(
        mode, runtime, plan, workspace, request, descriptor
    )
end

@inline function _plan_lifecycle_effect!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        plan_class::_DivideLifecycleVariantPlan,
    )
    return _plan_division!(
        mode,
        runtime,
        plan,
        workspace,
        request,
        descriptor,
        plan_class.partition,
        plan_class.side,
    )
end

function _plan_lifecycle_request_effect!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        request,
        plan_class::_AbstractLifecyclePlanClass,
    )
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
                workspace, ProgramStatusStaleGeneration; anchor
            )
            return :status_failure
        end
    end
    reason = _plan_lifecycle_effect!(
        mode, runtime, plan, workspace, request, descriptor, plan_class
    )
    reason === :ok && !_lifecycle_relationships_admissible(
        runtime, plan, descriptor, anchor
    ) && (reason = :relationship_policy_rejected)
    return reason
end

function _plan_lifecycle_request!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        request,
    )
    descriptor = @inbounds plan.descriptors[
        Int(workspace.descriptor[request])
    ]
    plan_class = if descriptor.effect === CreateCellLifecycleEffect
        _CreateLifecyclePlan()
    elseif descriptor.effect === RetireCellLifecycleEffect
        _RetireLifecyclePlan()
    elseif descriptor.effect === RemoveCellLifecycleEffect
        _RemoveLifecyclePlan()
    elseif descriptor.effect === TransitionCellLifecycleEffect
        _TransitionLifecyclePlan()
    elseif descriptor.effect === DivideCellLifecycleEffect
        _DivideLifecyclePlan()
    else
        return :unknown_effect
    end
    return _plan_lifecycle_request_effect!(
        mode, runtime, plan, workspace, request, plan_class
    )
end

@inline function _initialize_lifecycle_canonical_order!(
        ::HostLifecycleExecution, workspace, count
    )
    for request in 1:count
        @inbounds workspace.canonical_order[request] = Int32(request)
    end
    return nothing
end

@inline _initialize_lifecycle_canonical_order!(
    ::BackendLifecycleExecution, workspace, count
) = nothing

function _sort_lifecycle_requests!(
        mode::AbstractLifecycleExecutionMode, runtime, plan, workspace
    )
    count = Int(lifecycle_request_count(workspace))
    _initialize_lifecycle_canonical_order!(mode, workspace, count)
    for index in 2:count
        request = Int(@inbounds workspace.canonical_order[index])
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        key = _lifecycle_request_key(plan, workspace, request)
        position = index
        while position > 1
            prior = Int(@inbounds workspace.canonical_order[position - 1])
            prior_descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[prior])
            ]
            ordered_before = prior_descriptor.priority < descriptor.priority ||
                (prior_descriptor.priority == descriptor.priority &&
                 _lifecycle_request_key(plan, workspace, prior) < key)
            ordered_before && break
            @inbounds workspace.canonical_order[position] = Int32(prior)
            position -= 1
        end
        @inbounds workspace.canonical_order[position] = Int32(request)
    end
    return count
end

function _plan_and_filter_lifecycle_requests!(
        mode::AbstractLifecycleExecutionMode,
        runtime,
        plan,
        workspace,
        count::Integer,
    )
    for position in 1:count
        request = Int(@inbounds workspace.canonical_order[position])
        @inbounds workspace.active[request] || continue
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        reason = _plan_lifecycle_request!(
            mode, runtime, plan, workspace, request
        )
        reason === :status_failure && return false
        reason === :ok && continue
        if descriptor.on_inadmissible === FilterLifecycleInadmissible
            @inbounds begin
                workspace.active[request] = false
                workspace.filtered[request] = true
                workspace.filtered_detail[request] =
                    _lifecycle_detail_code(reason)
            end
        else
            return _set_lifecycle_status!(
                workspace,
                ProgramStatusInadmissible;
                source = descriptor.source_handle,
                anchor = @inbounds(workspace.anchor[request]),
                detail = _lifecycle_detail_code(reason),
            )
        end
    end
    return true
end

function _filter_lifecycle_requests!(
        mode::AbstractLifecycleExecutionMode, runtime, plan, workspace
    )
    count = _sort_lifecycle_requests!(mode, runtime, plan, workspace)
    return _plan_and_filter_lifecycle_requests!(
        mode, runtime, plan, workspace, count
    )
end

_filter_lifecycle_requests!(runtime, plan, workspace) =
    _filter_lifecycle_requests!(
        HostLifecycleExecution(), runtime, plan, workspace
    )
