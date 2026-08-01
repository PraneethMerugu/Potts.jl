# Typed derived-state trackers and their aligned runtime storage.

abstract type AbstractTrackerDescriptor end
abstract type AbstractTrackerPlan end

"""Exact finite-cell occupancy derived from authoritative lattice ownership."""
struct OwnershipCountTracker <: AbstractTrackerDescriptor end

struct TrackerExecutionPlan{D <: Tuple} <: AbstractTrackerPlan
    descriptors::D
    fingerprint::String
    function TrackerExecutionPlan(descriptors::D, fingerprint) where {D <: Tuple}
        quantities = map(
            descriptor -> typeof(tracker_quantity(descriptor)), descriptors
        )
        allunique(quantities) || throw(ArgumentError(
            "a tracker execution plan contains duplicate scientific quantities"
        ))
        return new{D}(descriptors, String(fingerprint))
    end
end

"""Minimal structural tracker plan permitted to cross a kernel boundary."""
struct TrackerKernelPlan{D <: Tuple} <: AbstractTrackerPlan
    descriptors::D
end

tracker_kernel_plan(plan::TrackerExecutionPlan) =
    TrackerKernelPlan(plan.descriptors)
tracker_kernel_plan(plan::TrackerKernelPlan) = plan

struct TrackerState{S <: Tuple}
    values::S
end

function tracker_quantity end
function tracker_rebuild end
function tracker_proposal_update! end
function tracker_checkpoint_policy end
function tracker_inspection end

tracker_quantity(::OwnershipCountTracker) = Val(:cell_volume)
tracker_checkpoint_policy(::OwnershipCountTracker) = :persist_logical_state
tracker_inspection(::OwnershipCountTracker) = (
    quantity = :cell_volume,
    source = :ownership,
    relation = :identity,
    domain = :cell,
    storage = :dense_int32,
    rebuild = :ownership_histogram,
    proposal_update = :source_target_unit_delta,
    visibility = :accepted_commit,
    concurrency = :claimed_owner_exclusive,
    checkpoint = :persist_logical_state,
    proposal_cost = :constant,
    rebuild_cost = :lattice_linear,
)

function tracker_rebuild(
        ::OwnershipCountTracker,
        ownership,
        cell_kinds,
    )
    values = zeros(Int32, length(cell_kinds))
    for owner in ownership
        owner > 0 && (values[Int(owner)] += Int32(1))
    end
    return values
end

@inline function tracker_proposal_update!(
        values,
        ::OwnershipCountTracker,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    old_owner > 0 && (@inbounds values[Int(old_owner)] -= Int32(1))
    new_owner > 0 && (@inbounds values[Int(new_owner)] += Int32(1))
    return nothing
end

function initialize_tracker_state(plan::AbstractTrackerPlan, ownership, cell_kinds)
    return TrackerState(map(
        descriptor -> tracker_rebuild(descriptor, ownership, cell_kinds),
        plan.descriptors,
    ))
end

function copy_tracker_state(state::TrackerState)
    return TrackerState(map(copy, state.values))
end

@inline _copyto_tracker_state!(::Tuple{}, ::Tuple{}, to_host) = nothing
@inline function _copyto_tracker_state!(destination, source, to_host)
    copyto!(first(destination), to_host(first(source)))
    return _copyto_tracker_state!(
        Base.tail(destination), Base.tail(source), to_host
    )
end

function copyto_tracker_state!(
        destination::TrackerState,
        source::TrackerState,
        to_host = identity,
    )
    _copyto_tracker_state!(destination.values, source.values, to_host)
    return destination
end

@inline _commit_tracker_updates!(
    ::Tuple{}, ::Tuple{}, target, old_owner, new_owner
) = nothing

@inline function _commit_tracker_updates!(
        descriptors::Tuple,
        values::Tuple,
        target,
        old_owner,
        new_owner,
    )
    tracker_proposal_update!(
        first(values), first(descriptors), target, old_owner, new_owner
    )
    return _commit_tracker_updates!(
        Base.tail(descriptors),
        Base.tail(values),
        target,
        old_owner,
        new_owner,
    )
end

@inline function commit_tracker_updates!(
        state::TrackerState,
        plan::AbstractTrackerPlan,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    _commit_tracker_updates!(
        plan.descriptors, state.values, target, old_owner, new_owner
    )
    return nothing
end

@inline function _tracker_values(
        quantity::Val, descriptors::Tuple, values::Tuple
    )
    tracker_quantity(first(descriptors)) === quantity && return first(values)
    return _tracker_values(quantity, Base.tail(descriptors), Base.tail(values))
end

@inline function _tracker_values(::Val{Q}, ::Tuple{}, ::Tuple{}) where {Q}
    throw(ArgumentError("compiled tracker quantity `$Q` is unavailable"))
end

@inline tracker_values(
    plan::AbstractTrackerPlan, state::TrackerState, quantity::Val
) = _tracker_values(quantity, plan.descriptors, state.values)

@inline function tracker_value(
        plan::AbstractTrackerPlan,
        state::TrackerState,
        quantity::Val,
        index::Integer,
    )
    return @inbounds tracker_values(plan, state, quantity)[Int(index)]
end

@inline program_tracker_values(runtime, quantity::Val) = tracker_values(
    runtime.program.tracker_plan, runtime.trackers, quantity
)

@inline program_tracker_values(program, snapshot, quantity::Val) = tracker_values(
    program.tracker_plan, snapshot.trackers, quantity
)

@inline program_tracker_value(runtime, quantity::Val, index::Integer) =
    tracker_value(runtime.program.tracker_plan, runtime.trackers, quantity, index)

function validate_tracker_state!(
        plan::AbstractTrackerPlan,
        state::TrackerState,
        ownership,
        cell_kinds,
    )
    length(plan.descriptors) == length(state.values) || throw(ArgumentError(
        "tracker plan and runtime state are misaligned"
    ))
    rebuilt = initialize_tracker_state(plan, ownership, cell_kinds)
    for index in eachindex(state.values)
        state.values[index] == rebuilt.values[index] || throw(ArgumentError(
            "tracker $(tracker_inspection(plan.descriptors[index]).quantity) " *
            "differs from independent reconstruction"
        ))
    end
    return state
end

tracker_plan_report(plan::TrackerExecutionPlan) = (
    count = length(plan.descriptors),
    quantities = map(
        descriptor -> tracker_inspection(descriptor).quantity,
        plan.descriptors,
    ),
    descriptors = map(tracker_inspection, plan.descriptors),
    checkpoint = map(tracker_checkpoint_policy, plan.descriptors),
    fingerprint = plan.fingerprint,
)

Adapt.@adapt_structure OwnershipCountTracker
Adapt.@adapt_structure TrackerExecutionPlan
Adapt.@adapt_structure TrackerKernelPlan
Adapt.@adapt_structure TrackerState
