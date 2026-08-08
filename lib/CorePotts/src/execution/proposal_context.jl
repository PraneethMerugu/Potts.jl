# Proposal geometry, immutable proposal views, and resource operations.

@inline function _neighbor_index(
        program,
        index::CartesianIndex{N},
        offsets::AbstractMatrix{Int8},
        direction::Int,
    ) where {N}
    return relation_neighbor_index(
        program.shape, program.periodic, index, offsets, direction
    )
end

@inline _owner_kind(runtime, owner::Int32) =
    owner > 0 ? @inbounds(runtime.cell_kinds[owner]) :
    owner == 0 ? runtime.program.medium_kind : Int16(-owner)

@inline ownership_state(runtime::ProgramRuntime) = runtime.ownership
@inline owner_kind(runtime::ProgramRuntime, owner::Integer) =
    _owner_kind(runtime, Int32(owner))
@inline function relationship_degree(
        runtime::ProgramRuntime,
        relationship_slot::Integer,
        endpoint::Integer,
    )
    1 <= relationship_slot <= length(runtime.relationships) || throw(ArgumentError(
        "runtime relationship slot is outside the compiled store"
    ))
    return _call_relationship_slot(
        _relationship_degree,
        runtime.relationships,
        Int32(relationship_slot),
        (Int32(endpoint),),
    )
end

function _cell_center(
        runtime,
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    )
    T = eltype(runtime.parameters)
    N = length(runtime.program.shape)
    cell > 0 || return nothing
    count, moments, old_owner, changed = _cell_moment_overlay(
        runtime.program.tracker_plan,
        runtime.trackers,
        runtime.ownership,
        cell,
        replaced_site,
        replacement_owner,
    )
    count > 0 || return nothing
    inverse = inv(T(count))
    return ntuple(N) do dimension
        total = @inbounds moments.first[dimension, Int(cell)]
        if changed
            coordinate = T(replaced_site[dimension]) - T(0.5)
            cell == old_owner && (total -= coordinate)
            cell == replacement_owner && (total += coordinate)
        end
        total * inverse
    end
end

@inline function _cell_moment_overlay(
        plan,
        trackers,
        ownership,
        cell::Int32,
        replaced_site,
        replacement_owner::Int32,
    )
    moments = tracker_values(plan, trackers, Val(:cell_moments))
    count = Int(tracker_value(plan, trackers, Val(:cell_volume), cell))
    old_owner = replaced_site === nothing ? Int32(-1) :
                @inbounds(ownership[replaced_site])
    changed = replaced_site !== nothing && old_owner != replacement_owner
    changed && cell == old_owner && (count -= 1)
    changed && cell == replacement_owner && (count += 1)
    return count, moments, old_owner, changed
end

function _cell_shape_statistics(
        runtime,
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    )
    T = eltype(runtime.parameters)
    N = length(runtime.program.shape)
    cell > 0 || return nothing
    count, moments, old_owner, changed = _cell_moment_overlay(
        runtime.program.tracker_plan,
        runtime.trackers,
        runtime.ownership,
        cell,
        replaced_site,
        replacement_owner,
    )
    count == 0 && return nothing
    inverse = inv(T(count))
    totals = ntuple(N) do dimension
        total = @inbounds moments.first[dimension, Int(cell)]
        if changed
            coordinate = T(replaced_site[dimension]) - T(0.5)
            cell == old_owner && (total -= coordinate)
            cell == replacement_owner && (total += coordinate)
        end
        total
    end
    center = ntuple(dimension -> totals[dimension] * inverse, N)
    covariance = ntuple(N * N) do slot
        row = rem(slot - 1, N) + 1
        column = div(slot - 1, N) + 1
        quadratic = @inbounds moments.second[slot, Int(cell)]
        if changed
            first_coordinate = T(replaced_site[row]) - T(0.5)
            second_coordinate = T(replaced_site[column]) - T(0.5)
            product = first_coordinate * second_coordinate
            cell == old_owner && (quadratic -= product)
            cell == replacement_owner && (quadratic += product)
        end
        quadratic * inverse - center[row] * center[column]
    end
    return count, center, covariance
end

@inline function _maximum_covariance_eigenvalue(
        ::Val{2}, covariance::NTuple{4, T}
    ) where {T}
    first_diagonal = covariance[1]
    off_diagonal = covariance[2]
    second_diagonal = covariance[4]
    discriminant = max(
        zero(T),
        (first_diagonal - second_diagonal)^2 +
        T(4) * off_diagonal^2,
    )
    return (
        first_diagonal + second_diagonal + sqrt(discriminant)
    ) / T(2)
end

function _maximum_covariance_eigenvalue(::Val{N}, covariance) where {N}
    throw(ArgumentError(
        "V1 cell elongation is qualified only for two-dimensional lattices"
    ))
end

function _cell_length(
        runtime::ProgramRuntime{T, N},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    statistics = _cell_shape_statistics(
        runtime, cell; replaced_site, replacement_owner
    )
    statistics === nothing && return zero(T)
    covariance = statistics[3]
    maximum_variance = _maximum_covariance_eigenvalue(Val(N), covariance)
    return T(4) * sqrt(max(zero(T), maximum_variance))
end

@inline function _center_distance(
        first::NTuple{2, T}, second::NTuple{2, T}
    ) where {T}
    return sqrt(
        (first[1] - second[1])^2 + (first[2] - second[2])^2
    )
end

@inline function _center_distance(first, second)
    return sqrt(sum((first[i] - second[i])^2 for i in eachindex(first)))
end

@inline _center_distance(::Nothing, second) = Inf
@inline _center_distance(first, ::Nothing) = Inf
@inline _center_distance(::Nothing, ::Nothing) = Inf

@inline _has_due_zero_volume_retirement(
    ::NoLifecycleExecutionPlan, kind::Int16
) = false

@inline function _has_due_zero_volume_retirement(
        plan::LifecycleExecutionPlan, kind::Int16
    )
    for descriptor in plan.descriptors
        if descriptor.compiler_synthesized &&
                descriptor.effect === RetireCellLifecycleEffect &&
                descriptor.domain === CellKindLifecycleDomain &&
                descriptor.domain_kind == kind
            return true
        end
    end
    return false
end

"""Whether one copy may remove the old owner's final occupied site."""
@inline function _extinction_copy_admitted(state, old_owner, new_owner)
    old_owner > 0 && old_owner != new_owner || return true
    volumes = tracker_values(
        state.program.tracker_plan, state.trackers, Val(:cell_volume)
    )
    @inbounds volumes[Int(old_owner)] == 1 || return true
    kind = @inbounds state.cell_kinds[Int(old_owner)]
    kind > 0 || return false
    plan = state.program.lifecycle_plan
    if plan isa LifecycleExecutionPlan &&
            @inbounds(plan.forbid_extinction[Int(kind)])
        return false
    end
    return _has_due_zero_volume_retirement(plan, kind)
end

function _commit_copy!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
        context,
    ) where {T, N}
    source = tracker_source_view(runtime.program, runtime.ownership)
    commit_tracker_updates!(
        runtime.trackers,
        runtime.program.tracker_plan,
        source,
        target,
        old_owner,
        new_owner,
    )
    @inbounds runtime.ownership[target] = new_owner
    old_owner == new_owner || _clear_ownership_changed_state!(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
        target,
    )
    _apply_accepted_copy_stage!(runtime, context)
    return nothing
end

struct _ProposalEvaluationContext{R, I} <:
       AbstractProposalEvaluationContext
    runtime::R
    source::I
    target::I
    old_owner::Int32
    new_owner::Int32
    attempt::Int
    subround::Int
end

@inline evaluator_parameters(context::_ProposalEvaluationContext) =
    context.runtime.parameters
@inline _compiled_evaluator_parameters(context::_ProposalEvaluationContext) =
    context.runtime.parameters
@inline proposal_source_site(context::_ProposalEvaluationContext) =
    context.source
@inline proposal_target_site(context::_ProposalEvaluationContext) =
    context.target
@inline proposal_source_owner(context::_ProposalEvaluationContext) =
    context.new_owner
@inline proposal_target_owner(context::_ProposalEvaluationContext) =
    context.old_owner
@inline proposal_source_kind(context::_ProposalEvaluationContext) =
    _owner_kind(context.runtime, context.new_owner)
@inline proposal_target_kind(context::_ProposalEvaluationContext) =
    _owner_kind(context.runtime, context.old_owner)
@inline owner_kind(
    context::_ProposalEvaluationContext, owner::Integer
) = _owner_kind(context.runtime, Int32(owner))
@inline proposal_site_owner(
    context::_ProposalEvaluationContext,
    site,
) = @inbounds context.runtime.ownership[site]

@inline function proposal_relation_count(
        context::_ProposalEvaluationContext,
        relation_handle::Integer,
    )
    _, count = _contact_domain_columns(
        context.runtime.program.descriptor_plan.domain_resources,
        Int32(relation_handle),
    )
    return Int(count)
end

@inline function proposal_relation_neighbor_site(
        context::_ProposalEvaluationContext,
        relation_handle::Integer,
        center,
        direction::Integer,
    )
    resources = context.runtime.program.descriptor_plan.domain_resources
    start, count = _contact_domain_columns(
        resources, Int32(relation_handle)
    )
    1 <= direction <= count || return nothing
    column = start + Int32(direction - 1)
    return _neighbor_index(
        context.runtime.program,
        center,
        resources.contact_offsets,
        Int(column),
    )
end

@inline function proposal_relation_neighbor_owner(
        context::_ProposalEvaluationContext{R, CartesianIndex{N}},
        relation_handle::Integer,
        offset::NTuple{N, <:Integer},
    ) where {R, N}
    resources = context.runtime.program.descriptor_plan.domain_resources
    start, count = _contact_domain_columns(resources, Int32(relation_handle))
    column = Int32(0)
    for candidate in start:(start + count - 1)
        matches = true
        for dimension in 1:N
            matches &= @inbounds(resources.contact_offsets[dimension, candidate]) ==
                       offset[dimension]
        end
        if matches
            column = candidate
            break
        end
    end
    iszero(column) && return typemin(Int32)
    neighbor = _neighbor_index(
        context.runtime.program,
        context.target,
        resources.contact_offsets,
        Int(column),
    )
    neighbor === nothing && return Int32(0)
    return @inbounds context.runtime.ownership[neighbor]
end

@inline function _compiled_context_value(
        operation::ContextOperation{Identity},
        context::_ProposalEvaluationContext,
    ) where {Identity}
    return invoke(
        context_value,
        Tuple{ContextOperation{Identity}, _ProposalEvaluationContext},
        operation,
        context,
    )
end

@inline function _compiled_resource_operation(
        operation::ResourceOperation{Identity},
        arguments::Tuple,
        context::_ProposalEvaluationContext,
    ) where {Identity}
    return invoke(
        apply_resource_operation,
        Tuple{ResourceOperation{Identity}, Tuple, _ProposalEvaluationContext},
        operation,
        arguments,
        context,
    )
end

@inline context_value(
    ::ContextOperation{:source_site},
    context::_ProposalEvaluationContext,
) = context.source
@inline context_value(
    ::ContextOperation{:target_site},
    context::_ProposalEvaluationContext,
) = context.target
@inline context_value(
    ::ContextOperation{:source_cell},
    context::_ProposalEvaluationContext,
) = context.new_owner
@inline context_value(
    ::ContextOperation{:target_cell},
    context::_ProposalEvaluationContext,
) = context.old_owner
@inline context_value(
    ::ContextOperation{:source_kind},
    context::_ProposalEvaluationContext,
) = _owner_kind(context.runtime, context.new_owner)
@inline context_value(
    ::ContextOperation{:target_kind},
    context::_ProposalEvaluationContext,
) = _owner_kind(context.runtime, context.old_owner)
@inline context_value(
    ::ContextOperation{:is_extension},
    context::_ProposalEvaluationContext,
) = context.old_owner <= 0 && context.new_owner > 0
@inline context_value(
    ::ContextOperation{:is_retraction},
    context::_ProposalEvaluationContext,
) = context.old_owner > 0 && context.new_owner <= 0

@inline function apply_resource_operation(
        ::ResourceOperation{:cell_volume},
        arguments,
        context::_ProposalEvaluationContext,
    )
    owner = Int(only(arguments))
    owner <= 0 && return Int32(0)
    return program_tracker_value(
        context.runtime, Val(:cell_volume), owner
    )
end

@inline function apply_resource_operation(
        ::ResourceOperation{:field_value},
        arguments,
        context::_ProposalEvaluationContext,
    )
    handle = first(arguments)
    site = last(arguments)
    return state_value(context, handle, site)
end

@inline function apply_resource_operation(
        ::ResourceOperation{:degree},
        arguments,
        context::_ProposalEvaluationContext,
    )
    relationship_handle = Int32(first(arguments))
    owner = Int32(last(arguments))
    owner <= 0 && return Int32(0)
    slot = _relationship_domain_slot(
        context.runtime.program.descriptor_plan.domain_resources,
        relationship_handle,
    )
    return _call_relationship_slot(
        _relationship_degree,
        context.runtime.relationships,
        slot,
        (owner,),
    )
end

@inline function apply_resource_operation(
        ::ResourceOperation{:linked},
        arguments,
        context::_ProposalEvaluationContext,
    )
    relationship_handle = Int32(arguments[1])
    endpoint_a = Int32(arguments[2])
    endpoint_b = Int32(arguments[3])
    (endpoint_a <= 0 || endpoint_b <= 0) && return false
    slot = _relationship_domain_slot(
        context.runtime.program.descriptor_plan.domain_resources,
        relationship_handle,
    )
    edge = _call_relationship_slot(
        _relationship_edge,
        context.runtime.relationships,
        slot,
        (endpoint_a, endpoint_b),
    )
    return edge !== nothing
end

@inline function _proposal_endpoint_pair(arguments, context)
    endpoint_a = Int32(first(arguments))
    endpoint_b = Int32(last(arguments))
    declared = _canonical_endpoints(endpoint_a, endpoint_b)
    transition = _canonical_endpoints(context.new_owner, context.old_owner)
    return endpoint_a > 0 && endpoint_b > 0 &&
           endpoint_a != endpoint_b && declared == transition
end

@inline apply_resource_operation(
    ::ResourceOperation{:new_contact}, arguments,
    context::_ProposalEvaluationContext,
) = _proposal_endpoint_pair(arguments, context)

@inline apply_resource_operation(
    ::ResourceOperation{:lost_contact}, arguments,
    context::_ProposalEvaluationContext,
) = _proposal_endpoint_pair(arguments, context)

@inline function apply_resource_operation(
        ::ResourceOperation{:draw},
        arguments,
        context::_ProposalEvaluationContext,
    )
    T = eltype(context.runtime.parameters)
    family = Int(arguments[1])
    first_parameter = T(arguments[2])
    second_parameter = T(arguments[3])
    operation = UInt16(arguments[4])
    first_uniform = _program_uniform(
        T,
        context.runtime,
        ExplicitProposalDrawStream,
        operation,
        context.attempt;
        subround = context.subround,
        draw = 0,
    )
    if family == 1
        return first_uniform < first_parameter
    elseif family == 2
        return muladd(
            first_uniform,
            second_parameter - first_parameter,
            first_parameter,
        )
    elseif family == 3
        iszero(second_parameter) && return first_parameter
        second_uniform = _program_uniform(
            T,
            context.runtime,
            ExplicitProposalDrawStream,
            operation,
            context.attempt;
            subround = context.subround,
            draw = 1,
        )
        normal = sqrt(-T(2) * log(first_uniform)) *
                 cos(T(2pi) * second_uniform)
        return muladd(second_parameter, normal, first_parameter)
    end
    return T(NaN)
end

@inline function state_value(
        context::_ProposalEvaluationContext,
        handle::StateHandle,
        site,
    )
    return @inbounds state_block(
        context.runtime.descriptor_state, handle
    ).values[site]
end

operation_context_supported(
    operation::ContextOperation,
    ::Type{AbstractProposalEvaluationContext},
) = hasmethod(
    context_value,
    Tuple{typeof(operation), _ProposalEvaluationContext},
)

operation_context_supported(
    operation::ResourceOperation,
    ::Type{AbstractProposalEvaluationContext},
) = hasmethod(
    apply_resource_operation,
    Tuple{typeof(operation), Tuple, _ProposalEvaluationContext},
)

@inline stage_site(
    ::ProposalTargetStageSite,
    context::_ProposalEvaluationContext,
) = context.target
