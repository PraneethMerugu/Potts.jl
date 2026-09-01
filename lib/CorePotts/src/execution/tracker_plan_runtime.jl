@inline function copyto_tracker_state!(
        destination::TrackerState,
        source::TrackerState,
        to_host = identity,
    )
    _copyto_tracker_state!(destination.values, source.values, to_host)
    return destination
end

@inline _commit_tracker_updates!(
    ::Tuple{}, ::Tuple{}, source, target, old_owner, new_owner
) = nothing

@inline function _apply_group_tracker_delta!(
        values,
        column::Int,
        delta::OwnerScalarDelta,
        old_owner::Int32,
        new_owner::Int32,
    )
    old_owner > 0 && (@inbounds values[Int(old_owner), column] -= delta.amount)
    new_owner > 0 && (@inbounds values[Int(new_owner), column] += delta.amount)
    return nothing
end

@inline function _apply_group_tracker_delta!(
        values,
        column::Int,
        delta::SourceTargetScalarDelta,
        old_owner::Int32,
        new_owner::Int32,
    )
    old_owner > 0 &&
        (@inbounds values[Int(old_owner), column] += delta.old_amount)
    new_owner > 0 &&
        (@inbounds values[Int(new_owner), column] += delta.new_amount)
    return nothing
end

@inline function _commit_tracker_updates!(
        descriptors::Tuple{G, Vararg},
        values::Tuple,
        source,
        target,
        old_owner,
        new_owner,
    ) where {G <: DenseScalarTrackerGroup}
    group = first(descriptors)
    group_values = first(values)
    for index in eachindex(group.descriptors)
        descriptor = @inbounds group.descriptors[index]
        delta = tracker_proposal_delta(
            descriptor, source, target, old_owner, new_owner
        )
        _apply_group_tracker_delta!(
            group_values, index, delta, old_owner, new_owner
        )
    end
    return _commit_tracker_updates!(
        Base.tail(descriptors),
        Base.tail(values),
        source,
        target,
        old_owner,
        new_owner,
    )
end

@inline function _commit_tracker_updates!(
        descriptors::Tuple,
        values::Tuple,
        source,
        target,
        old_owner,
        new_owner,
    )
    descriptor = first(descriptors)
    contract = tracker_contract(descriptor)
    contract.update_bound isa SourceTargetOwnerUpdateBound || throw(
        ArgumentError("unsupported tracker update bound")
    )
    delta = tracker_proposal_delta(
        descriptor, source, target, old_owner, new_owner
    )
    delta isa AbstractTrackerDelta || throw(ArgumentError(
        "tracker proposal delta must satisfy the closed delta protocol"
    ))
    _apply_tracker_delta!(
        first(values), contract.storage, delta, old_owner, new_owner
    )
    return _commit_tracker_updates!(
        Base.tail(descriptors),
        Base.tail(values),
        source,
        target,
        old_owner,
        new_owner,
    )
end

@inline function commit_tracker_updates!(
        state::TrackerState,
        plan::AbstractTrackerPlan,
        source::TrackerSourceView,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    _commit_tracker_updates!(
        plan.descriptors, state.values, source, target, old_owner, new_owner
    )
    return nothing
end


@inline function _scalar_value_after(
        value,
        delta::OwnerScalarDelta,
        owner::Int32,
        old_owner::Int32,
        new_owner::Int32,
    )
    owner == old_owner && (value -= delta.amount)
    owner == new_owner && (value += delta.amount)
    return value
end

@inline function _scalar_value_after(
        value,
        delta::SourceTargetScalarDelta,
        owner::Int32,
        old_owner::Int32,
        new_owner::Int32,
    )
    owner == old_owner && (value += delta.old_amount)
    owner == new_owner && (value += delta.new_amount)
    return value
end

@inline function _tracker_value_after(
        quantity,
        descriptors::Tuple,
        values::Tuple,
        source::TrackerSourceView,
        owner::Int32,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    descriptor = first(descriptors)
    if isequal(tracker_quantity(descriptor), quantity)
        owner <= 0 && return zero(eltype(first(values)))
        value = @inbounds first(values)[Int(owner)]
        delta = tracker_proposal_delta(
            descriptor, source, target, old_owner, new_owner
        )
        return _scalar_value_after(
            value, delta, owner, old_owner, new_owner
        )
    end
    return _tracker_value_after(
        quantity,
        Base.tail(descriptors),
        Base.tail(values),
        source,
        owner,
        target,
        old_owner,
        new_owner,
    )
end


@inline function _tracker_value_after(
        quantity,
        ::Tuple{},
        ::Tuple{},
        source::TrackerSourceView,
        owner::Int32,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    throw(ArgumentError("compiled tracker quantity $(repr(quantity)) is unavailable"))
end

@inline tracker_value_after(
    plan::AbstractTrackerPlan,
    state::TrackerState,
    source::TrackerSourceView,
    quantity,
    owner::Int32,
    target,
    old_owner::Int32,
    new_owner::Int32,
) = _tracker_value_after(
    quantity,
    plan.descriptors,
    state.values,
    source,
    owner,
    target,
    old_owner,
    new_owner,
)

@generated function _qualified_scalar_value_after(
        quantity::Val{Q},
        source_handle::Int32,
        descriptors::D,
        values::V,
        source::TrackerSourceView,
        owner::Int32,
        target,
        old_owner::Int32,
        new_owner::Int32,
    ) where {Q, D <: Tuple, V <: Tuple}
    indices = findall(
        descriptor_type -> descriptor_type <: AbstractTrackerDescriptor,
        D.parameters,
    )
    group_indices = findall(
        descriptor_type -> descriptor_type <:
            DenseScalarTrackerGroup{Val{Q}},
        D.parameters,
    )
    result = :(throw(ArgumentError(
        "compiled qualified tracker source is unavailable"
    )))
    for index in reverse(indices)
        result = quote
            key = tracker_quantity(descriptors[$index])
            if key isa QualifiedTrackerKey{Val{$(QuoteNode(Q))}} &&
                    key.source_handle == source_handle
                owner <= 0 && return zero(eltype(values[$index]))
                value = @inbounds values[$index][Int(owner)]
                delta = tracker_proposal_delta(
                    descriptors[$index],
                    source,
                    target,
                    old_owner,
                    new_owner,
                )
                return _scalar_value_after(
                    value, delta, owner, old_owner, new_owner
                )
            end
            $result
        end
    end
    for index in reverse(group_indices)
        result = quote
            group = descriptors[$index]
            group_values = values[$index]
            for column in eachindex(group.descriptors)
                descriptor = @inbounds group.descriptors[column]
                if @inbounds(group.source_handles[column]) == source_handle
                    owner <= 0 && return zero(eltype(group_values))
                    value = @inbounds group_values[Int(owner), column]
                    delta = tracker_proposal_delta(
                        descriptor,
                        source,
                        target,
                        old_owner,
                        new_owner,
                    )
                    return _scalar_value_after(
                        value, delta, owner, old_owner, new_owner
                    )
                end
            end
            $result
        end
    end
    return result
end

@generated function _qualified_scalar_value(
        quantity::Val{Q},
        source_handle::Int32,
        descriptors::D,
        values::V,
        owner::Int32,
    ) where {Q, D <: Tuple, V <: Tuple}
    indices = findall(
        descriptor_type -> descriptor_type <: AbstractTrackerDescriptor,
        D.parameters,
    )
    group_indices = findall(
        descriptor_type -> descriptor_type <:
            DenseScalarTrackerGroup{Val{Q}},
        D.parameters,
    )
    result = :(throw(ArgumentError(
        "compiled qualified tracker source is unavailable"
    )))
    for index in reverse(indices)
        result = quote
            key = tracker_quantity(descriptors[$index])
            if key isa QualifiedTrackerKey{Val{$(QuoteNode(Q))}} &&
                    key.source_handle == source_handle
                owner <= 0 && return zero(eltype(values[$index]))
                return @inbounds values[$index][Int(owner)]
            end
            $result
        end
    end
    for index in reverse(group_indices)
        result = quote
            group = descriptors[$index]
            group_values = values[$index]
            for column in eachindex(group.source_handles)
                if @inbounds(group.source_handles[column]) == source_handle
                    owner <= 0 && return zero(eltype(group_values))
                    return @inbounds group_values[Int(owner), column]
                end
            end
            $result
        end
    end
    return result
end

@inline qualified_tracker_value(
    plan::AbstractTrackerPlan,
    state::TrackerState,
    quantity::Val,
    source_handle::Int32,
    owner::Int32,
) = _qualified_scalar_value(
    quantity, source_handle, plan.descriptors, state.values, owner
)

@inline tracker_value_after(
    plan::AbstractTrackerPlan,
    state::TrackerState,
    source::TrackerSourceView,
    key::QualifiedTrackerKey,
    owner::Int32,
    target,
    old_owner::Int32,
    new_owner::Int32,
) = _qualified_scalar_value_after(
    key.quantity,
    key.source_handle,
    plan.descriptors,
    state.values,
    source,
    owner,
    target,
    old_owner,
    new_owner,
)

@inline tracker_value_after(
    plan::AbstractTrackerPlan,
    state::TrackerState,
    source::TrackerSourceView,
    quantity::Val,
    source_handle::Int32,
    owner::Int32,
    target,
    old_owner::Int32,
    new_owner::Int32,
) = _qualified_scalar_value_after(
    quantity,
    source_handle,
    plan.descriptors,
    state.values,
    source,
    owner,
    target,
    old_owner,
    new_owner,
)

@inline function _tracker_values(
        quantity, descriptors::Tuple, values::Tuple
    )
    isequal(tracker_quantity(first(descriptors)), quantity) &&
        return first(values)
    return _tracker_values(quantity, Base.tail(descriptors), Base.tail(values))
end

@inline function _tracker_values(
        key::QualifiedTrackerKey,
        descriptors::Tuple{G, Vararg},
        values::Tuple,
    ) where {G <: DenseScalarTrackerGroup}
    group = first(descriptors)
    isequal(group.quantity, key.quantity) || return _tracker_values(
        key, Base.tail(descriptors), Base.tail(values)
    )
    index = findfirst(==(key.source_handle), group.source_handles)
    index === nothing || return view(first(values), :, index)
    return _tracker_values(key, Base.tail(descriptors), Base.tail(values))
end

@inline function _tracker_values(
        quantity,
        descriptors::Tuple{G, Vararg},
        values::Tuple,
    ) where {G <: DenseScalarTrackerGroup}
    return _tracker_values(quantity, Base.tail(descriptors), Base.tail(values))
end

@inline function _tracker_values(quantity, ::Tuple{}, ::Tuple{})
    throw(ArgumentError("compiled tracker quantity $(repr(quantity)) is unavailable"))
end

@inline tracker_values(
    plan::AbstractTrackerPlan, state::TrackerState, quantity
) = _tracker_values(quantity, plan.descriptors, state.values)

@inline function tracker_value(
        plan::AbstractTrackerPlan,
        state::TrackerState,
        quantity,
        index::Integer,
    )
    return @inbounds tracker_values(plan, state, quantity)[Int(index)]
end

"""Return the runtime storage associated with a qualified tracker quantity."""
@inline program_tracker_values(runtime, quantity) = tracker_values(
    runtime.program.tracker_plan, runtime.trackers, quantity
)

@inline program_tracker_values(program, snapshot, quantity) = tracker_values(
    program.tracker_plan, snapshot.trackers, quantity
)

@inline program_tracker_value(runtime, quantity, index::Integer) =
    tracker_value(runtime.program.tracker_plan, runtime.trackers, quantity, index)

function validate_tracker_state!(
        plan::AbstractTrackerPlan,
        state::TrackerState,
        ownership,
        cell_kinds,
        program,
    )
    length(plan.descriptors) == length(state.values) || throw(ArgumentError(
        "tracker plan and runtime state are misaligned"
    ))
    source = tracker_source_view(program, ownership)
    for index in eachindex(state.values)
        descriptor = plan.descriptors[index]
        expected = tracker_recompute(descriptor, source, cell_kinds)
        _validate_tracker_state(
            tracker_storage(descriptor),
            expected,
            length(cell_kinds),
        )
        state.values[index] == expected || throw(ArgumentError(
            "tracker $(tracker_quantities(plan.descriptors[index])) " *
            "differs from its independent recomputation oracle"
        ))
    end
    return state
end

_tracker_instances(::Tuple{}) = ()
_tracker_instances(descriptors::Tuple{D, Vararg}) where {D} =
    (first(descriptors), _tracker_instances(Base.tail(descriptors))...)
_tracker_instances(
    descriptors::Tuple{G, Vararg},
) where {G <: DenseScalarTrackerGroup} = (
    Tuple(first(descriptors).descriptors)...,
    _tracker_instances(Base.tail(descriptors))...,
)

"""Flatten a tracker plan into its ordered concrete descriptor instances."""
function tracker_instances(plan::AbstractTrackerPlan)
    return _tracker_instances(plan.descriptors)
end

function tracker_plan_report(plan::TrackerExecutionPlan)
    instances = tracker_instances(plan)
    return (
        count = length(instances),
        groups = length(plan.descriptors),
        quantities = map(
            descriptor -> _tracker_quantity_symbol(
                tracker_quantity(descriptor)
            ),
            instances,
        ),
        descriptors = map(tracker_inspection, instances),
        checkpoint = map(tracker_checkpoint_policy, instances),
        fingerprint = plan.fingerprint,
    )
end

Adapt.@adapt_structure OwnershipCountTracker
Adapt.@adapt_structure CellSurfaceTracker
Adapt.@adapt_structure DenseScalarTrackerGroup
Adapt.adapt_structure(to, descriptor::CellMomentsTracker) = descriptor
Adapt.@adapt_structure CellMomentsState
Adapt.@adapt_structure TrackerExecutionPlan
Adapt.@adapt_structure TrackerKernelPlan
Adapt.@adapt_structure TrackerState
Adapt.@adapt_structure TrackerCheckpointState
