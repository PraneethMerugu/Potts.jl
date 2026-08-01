# Proposal geometry, immutable proposal views, and resource operations.

@inline function _neighbor_index(
        program,
        index::CartesianIndex{N},
        offsets::AbstractMatrix{Int8},
        direction::Int,
    ) where {N}
    coords = Tuple(index)
    candidate = ntuple(N) do dimension
        value = coords[dimension] + Int(offsets[dimension, direction])
        if program.periodic[dimension]
            mod1(value, program.shape[dimension])
        elseif 1 <= value <= program.shape[dimension]
            value
        else
            0
        end
    end
    any(iszero, candidate) && return nothing
    return CartesianIndex(candidate)
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
        runtime::ProgramRuntime{T, N},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    totals = zeros(T, N)
    count = 0
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        coordinates = Tuple(site)
        for dimension in 1:N
            totals[dimension] += T(coordinates[dimension]) - T(0.5)
        end
        count += 1
    end
    count > 0 || return nothing
    return ntuple(dimension -> totals[dimension] / T(count), N)
end

function _cell_center(
        runtime::ProgramRuntime{T, 2},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T}
    first_total = zero(T)
    second_total = zero(T)
    count = 0
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        first_total += T(site[1]) - T(0.5)
        second_total += T(site[2]) - T(0.5)
        count += 1
    end
    count > 0 || return nothing
    inverse = inv(T(count))
    return first_total * inverse, second_total * inverse
end

function _cell_shape_statistics(
        runtime::ProgramRuntime{T, N},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T, N}
    count = 0
    totals = zeros(T, N)
    quadratic = zeros(T, N, N)
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        coordinates = ntuple(
            dimension -> T(Tuple(site)[dimension]) - T(0.5), N
        )
        for row in 1:N
            totals[row] += coordinates[row]
            for column in 1:N
                quadratic[row, column] +=
                    coordinates[row] * coordinates[column]
            end
        end
        count += 1
    end
    count == 0 && return nothing
    inverse = inv(T(count))
    covariance = Matrix{T}(undef, N, N)
    for row in 1:N, column in 1:N
        covariance[row, column] =
            quadratic[row, column] * inverse -
            (totals[row] * inverse) * (totals[column] * inverse)
    end
    return count, totals .* inverse, covariance
end

function _cell_shape_statistics(
        runtime::ProgramRuntime{T, 2},
        cell::Int32;
        replaced_site = nothing,
        replacement_owner::Int32 = Int32(-1),
    ) where {T}
    first_total = zero(T)
    second_total = zero(T)
    first_squared = zero(T)
    cross_product = zero(T)
    second_squared = zero(T)
    count = 0
    for site in CartesianIndices(runtime.ownership)
        owner = site == replaced_site ?
                replacement_owner : @inbounds(runtime.ownership[site])
        owner == cell || continue
        first_coordinate = T(site[1]) - T(0.5)
        second_coordinate = T(site[2]) - T(0.5)
        first_total += first_coordinate
        second_total += second_coordinate
        first_squared += first_coordinate^2
        cross_product += first_coordinate * second_coordinate
        second_squared += second_coordinate^2
        count += 1
    end
    count == 0 && return nothing
    inverse = inv(T(count))
    first_center = first_total * inverse
    second_center = second_total * inverse
    covariance = (
        first_squared * inverse - first_center^2,
        cross_product * inverse - first_center * second_center,
        cross_product * inverse - first_center * second_center,
        second_squared * inverse - second_center^2,
    )
    return count, (first_center, second_center), covariance
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

_maximum_covariance_eigenvalue(::Val, covariance::AbstractMatrix) =
    maximum(eigen(Symmetric(covariance)).values)

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

function _commit_copy!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
        context,
    ) where {T, N}
    @inbounds runtime.ownership[target] = new_owner
    commit_tracker_updates!(
        runtime.trackers,
        runtime.program.tracker_plan,
        target,
        old_owner,
        new_owner,
    )
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
    owner <= 0 && return 0
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
    owner <= 0 && return 0
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
