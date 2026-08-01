# Typed derived-state trackers and their aligned runtime storage.

abstract type AbstractTrackerDescriptor end
abstract type AbstractTrackerPlan end
abstract type AbstractTrackerCheckpointPolicy end
abstract type AbstractTrackerConcurrency end

struct PersistTrackerCheckpoint <: AbstractTrackerCheckpointPolicy end
struct ReconstructTrackerCheckpoint <: AbstractTrackerCheckpointPolicy end
struct ClaimedOwnerExclusiveTrackerConcurrency <:
       AbstractTrackerConcurrency end

struct TrackerSupport
    sequential::Bool
    checkerboard::Bool
    cpu::Bool
    gpu::Bool
    reason_code::UInt16
end

TrackerSupport(
    sequential::Bool,
    checkerboard::Bool,
    cpu::Bool,
    gpu::Bool,
    reason_code::Integer = 0,
) = TrackerSupport(
    sequential, checkerboard, cpu, gpu, UInt16(reason_code)
)

"""Exact finite-cell occupancy derived from authoritative lattice ownership."""
struct OwnershipCountTracker <: AbstractTrackerDescriptor end

"""Coordinate first and second moments derived from lattice ownership."""
struct CellMomentsTracker{N, T <: AbstractFloat} <:
       AbstractTrackerDescriptor end

struct CellMomentsState{
        T <: AbstractFloat,
        F <: AbstractMatrix{T},
        Q <: AbstractMatrix{T},
    }
    first::F
    second::Q
end

function tracker_quantity end
function tracker_rebuild end
function tracker_proposal_update! end
function tracker_checkpoint_policy end
function tracker_inspection end
function tracker_support end
function tracker_concurrency end
function tracker_adapt end

tracker_adapt(to, descriptor::AbstractTrackerDescriptor) = descriptor

function _validate_tracker_descriptor(descriptor::AbstractTrackerDescriptor)
    isbits(descriptor) || throw(ArgumentError(
        "tracker descriptors crossing the execution boundary must be isbits"
    ))
    tracker_quantity(descriptor) isa Val || throw(ArgumentError(
        "tracker_quantity must return a Val identity"
    ))
    support = tracker_support(descriptor)
    support isa TrackerSupport || throw(ArgumentError(
        "tracker_support must return TrackerSupport"
    ))
    concurrency = tracker_concurrency(descriptor)
    concurrency isa AbstractTrackerConcurrency || throw(ArgumentError(
        "tracker_concurrency must return a closed tracker concurrency value"
    ))
    support.checkerboard &&
        !(concurrency isa ClaimedOwnerExclusiveTrackerConcurrency) && throw(
            ArgumentError(
                "checkerboard trackers require claimed-owner-exclusive updates"
            )
        )
    tracker_checkpoint_policy(descriptor) isa
        AbstractTrackerCheckpointPolicy || throw(ArgumentError(
            "tracker_checkpoint_policy must return a closed policy value"
        ))
    tracker_inspection(descriptor) isa NamedTuple || throw(ArgumentError(
        "tracker_inspection must return a NamedTuple"
    ))
    return descriptor
end

struct TrackerExecutionPlan{D <: Tuple} <: AbstractTrackerPlan
    descriptors::D
    fingerprint::String
    function TrackerExecutionPlan(descriptors::D, fingerprint) where {D <: Tuple}
        all(descriptor -> descriptor isa AbstractTrackerDescriptor, descriptors) ||
            throw(ArgumentError(
                "tracker plans admit only AbstractTrackerDescriptor values"
            ))
        foreach(_validate_tracker_descriptor, descriptors)
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

function adapt_tracker_kernel_plan(to, plan::AbstractTrackerPlan)
    descriptors = map(plan.descriptors) do descriptor
        support = tracker_support(descriptor)
        support.gpu || throw(ArgumentError(
            "tracker $(tracker_quantity(descriptor)) does not declare GPU " *
            "support (reason code $(support.reason_code))"
        ))
        adapted = tracker_adapt(to, descriptor)
        typeof(adapted) === typeof(descriptor) || throw(ArgumentError(
            "tracker adaptation changed its structural descriptor type"
        ))
        adapted
    end
    return TrackerKernelPlan(descriptors)
end

struct TrackerState{S <: Tuple}
    values::S
end

struct TrackerCheckpointState{S <: Tuple}
    values::S
end

Base.copy(state::CellMomentsState) = CellMomentsState(
    copy(state.first), copy(state.second)
)
Base.:(==)(left::CellMomentsState, right::CellMomentsState) =
    left.first == right.first && left.second == right.second

function Base.copyto!(
        destination::CellMomentsState, source::CellMomentsState
    )
    copyto!(destination.first, source.first)
    copyto!(destination.second, source.second)
    return destination
end

tracker_quantity(::OwnershipCountTracker) = Val(:cell_volume)
tracker_checkpoint_policy(::OwnershipCountTracker) = PersistTrackerCheckpoint()
tracker_support(::OwnershipCountTracker) = TrackerSupport(
    true, true, true, true
)
tracker_concurrency(::OwnershipCountTracker) =
    ClaimedOwnerExclusiveTrackerConcurrency()
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
    checkpoint = :persist,
    proposal_cost = :constant,
    rebuild_cost = :lattice_linear,
)

tracker_quantity(::CellMomentsTracker) = Val(:cell_moments)
tracker_checkpoint_policy(::CellMomentsTracker) =
    ReconstructTrackerCheckpoint()
tracker_support(::CellMomentsTracker) = TrackerSupport(
    true, true, true, true
)
tracker_concurrency(::CellMomentsTracker) =
    ClaimedOwnerExclusiveTrackerConcurrency()
tracker_inspection(::CellMomentsTracker{N, T}) where {N, T} = (
    quantity = :cell_moments,
    source = :ownership,
    relation = :lattice_coordinates,
    domain = :cell,
    storage = :dense_coordinate_moments,
    dimensions = N,
    element_type = T,
    rebuild = :ownership_coordinate_moments,
    proposal_update = :source_target_coordinate_delta,
    visibility = :accepted_commit,
    concurrency = :claimed_owner_exclusive,
    checkpoint = :reconstruct,
    proposal_cost = :dimension_squared,
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

function tracker_rebuild(
        ::CellMomentsTracker{N, T},
        ownership,
        cell_kinds,
    ) where {N, T}
    ndims(ownership) == N || throw(ArgumentError(
        "cell-moment tracker dimensionality does not match ownership"
    ))
    first = zeros(T, N, length(cell_kinds))
    second = zeros(T, N * N, length(cell_kinds))
    for site in CartesianIndices(ownership)
        owner = @inbounds ownership[site]
        owner > 0 || continue
        coordinates = ntuple(
            dimension -> T(site[dimension]) - T(0.5), N
        )
        for row in 1:N
            @inbounds first[row, Int(owner)] += coordinates[row]
            for column in 1:N
                slot = row + (column - 1) * N
                @inbounds second[slot, Int(owner)] +=
                    coordinates[row] * coordinates[column]
            end
        end
    end
    return CellMomentsState(first, second)
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

@inline function tracker_proposal_update!(
        state::CellMomentsState{T},
        ::CellMomentsTracker{N, T},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {N, T}
    old_owner == new_owner && return nothing
    coordinates = ntuple(
        dimension -> T(target[dimension]) - T(0.5), N
    )
    for row in 1:N
        coordinate = coordinates[row]
        old_owner > 0 && (@inbounds state.first[row, Int(old_owner)] -= coordinate)
        new_owner > 0 && (@inbounds state.first[row, Int(new_owner)] += coordinate)
        for column in 1:N
            slot = row + (column - 1) * N
            product = coordinate * coordinates[column]
            old_owner > 0 &&
                (@inbounds state.second[slot, Int(old_owner)] -= product)
            new_owner > 0 &&
                (@inbounds state.second[slot, Int(new_owner)] += product)
        end
    end
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

_tracker_state_to_host(to_host, value::AbstractArray) = to_host(value)
_tracker_state_to_host(to_host, value::CellMomentsState) = CellMomentsState(
    to_host(value.first), to_host(value.second)
)

@inline _copyto_tracker_state!(::Tuple{}, ::Tuple{}, to_host) = nothing
@inline function _copyto_tracker_state!(destination, source, to_host)
    copyto!(
        first(destination),
        _tracker_state_to_host(to_host, first(source)),
    )
    return _copyto_tracker_state!(
        Base.tail(destination), Base.tail(source), to_host
    )
end


_encode_tracker_checkpoint(::PersistTrackerCheckpoint, value) = copy(value)
_encode_tracker_checkpoint(::ReconstructTrackerCheckpoint, value) = nothing

function encode_tracker_checkpoint(
        plan::AbstractTrackerPlan, state::TrackerState
    )
    return TrackerCheckpointState(map(
        (descriptor, value) -> _encode_tracker_checkpoint(
            tracker_checkpoint_policy(descriptor), value
        ),
        plan.descriptors,
        state.values,
    ))
end

function _reconstruct_tracker_checkpoint(
        descriptor,
        ::PersistTrackerCheckpoint,
        value,
        ownership,
        cell_kinds,
    )
    value === nothing && throw(ArgumentError(
        "persisted tracker checkpoint state is missing"
    ))
    return copy(value)
end

function _reconstruct_tracker_checkpoint(
        descriptor,
        ::ReconstructTrackerCheckpoint,
        value,
        ownership,
        cell_kinds,
    )
    value === nothing || throw(ArgumentError(
        "reconstructed tracker checkpoint unexpectedly stored logical state"
    ))
    return tracker_rebuild(descriptor, ownership, cell_kinds)
end

function reconstruct_tracker_checkpoint(
        plan::AbstractTrackerPlan,
        checkpoint::TrackerCheckpointState,
        ownership,
        cell_kinds,
    )
    length(plan.descriptors) == length(checkpoint.values) || throw(
        ArgumentError("tracker checkpoint and plan are misaligned")
    )
    return TrackerState(map(
        (descriptor, value) -> _reconstruct_tracker_checkpoint(
            descriptor,
            tracker_checkpoint_policy(descriptor),
            value,
            ownership,
            cell_kinds,
        ),
        plan.descriptors,
        checkpoint.values,
    ))
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
Adapt.@adapt_structure CellMomentsTracker
Adapt.@adapt_structure CellMomentsState
Adapt.@adapt_structure TrackerExecutionPlan
Adapt.@adapt_structure TrackerKernelPlan
Adapt.@adapt_structure TrackerState
Adapt.@adapt_structure TrackerCheckpointState
