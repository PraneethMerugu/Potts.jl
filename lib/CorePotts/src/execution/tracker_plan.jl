# Typed derived-state trackers and their aligned runtime storage.

abstract type AbstractTrackerDescriptor end
abstract type AbstractTrackerPlan end
abstract type AbstractTrackerCheckpointPolicy end
abstract type AbstractTrackerConcurrency end
abstract type AbstractTrackerSource end
abstract type AbstractTrackerStorage end
abstract type AbstractTrackerVisibility end
abstract type AbstractTrackerUpdateBound end
abstract type AbstractTrackerCost end
abstract type AbstractTrackerDelta end

struct PersistTrackerCheckpoint <: AbstractTrackerCheckpointPolicy end
struct ReconstructTrackerCheckpoint <: AbstractTrackerCheckpointPolicy end
struct ClaimedOwnerExclusiveTrackerConcurrency <:
       AbstractTrackerConcurrency end
struct OwnershipTrackerSource <: AbstractTrackerSource end
struct OwnershipRelationTrackerSource <: AbstractTrackerSource
    relation_handle::Int32
end
struct DenseOwnerScalarStorage{T} <: AbstractTrackerStorage end
struct DenseOwnerMomentsStorage{N, T <: AbstractFloat} <:
       AbstractTrackerStorage end
struct AcceptedCommitTrackerVisibility <: AbstractTrackerVisibility end
struct SourceTargetOwnerUpdateBound <: AbstractTrackerUpdateBound end
struct ConstantTrackerCost <: AbstractTrackerCost end
struct DimensionSquaredTrackerCost <: AbstractTrackerCost end
struct BoundedNeighborhoodTrackerCost <: AbstractTrackerCost
    maximum_neighbors::Int16
end
struct LatticeLinearTrackerCost <: AbstractTrackerCost end

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

struct TrackerContract{
        Q <: Val,
        S <: AbstractTrackerSource,
        R <: AbstractTrackerStorage,
        V <: AbstractTrackerVisibility,
        C <: AbstractTrackerConcurrency,
        U <: AbstractTrackerUpdateBound,
        K <: AbstractTrackerCheckpointPolicy,
        P <: AbstractTrackerCost,
        B <: AbstractTrackerCost,
    }
    quantity::Q
    source::S
    storage::R
    visibility::V
    concurrency::C
    update_bound::U
    checkpoint::K
    support::TrackerSupport
    proposal_cost::P
    rebuild_cost::B
end

struct OwnerScalarDelta{T} <: AbstractTrackerDelta
    amount::T
end

"""Independent signed changes for the proposal's old and new finite owners."""
struct SourceTargetScalarDelta{T} <: AbstractTrackerDelta
    old_amount::T
    new_amount::T
end

struct OwnerMomentsDelta{F <: Tuple, S <: Tuple} <: AbstractTrackerDelta
    first::F
    second::S
end

"""Exact finite-cell occupancy derived from authoritative lattice ownership."""
struct OwnershipCountTracker <: AbstractTrackerDescriptor end

"""Per-owner boundary-bond count over one compiler-bound spatial relation."""
struct CellSurfaceTracker <: AbstractTrackerDescriptor
    relation_handle::Int32
    maximum_neighbors::Int16
end

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

function tracker_contract end
function tracker_rebuild end
function tracker_recompute end
function tracker_proposal_delta end
function tracker_adapt end

"""Read-only tracker source shared by rebuild, proposal, and oracle paths."""
struct TrackerSourceView{O, S, P, R}
    ownership::O
    shape::S
    periodic::P
    domain_resources::R
end

tracker_source_view(program, ownership) = TrackerSourceView(
    ownership,
    program.shape,
    program.periodic,
    program.descriptor_plan.domain_resources,
)

tracker_quantity(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).quantity
tracker_checkpoint_policy(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).checkpoint
tracker_support(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).support
tracker_concurrency(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).concurrency

tracker_adapt(to, descriptor::AbstractTrackerDescriptor) = descriptor

function _validate_tracker_descriptor(descriptor::AbstractTrackerDescriptor)
    isbits(descriptor) || throw(ArgumentError(
        "tracker descriptors crossing the execution boundary must be isbits"
    ))
    contract = tracker_contract(descriptor)
    contract isa TrackerContract || throw(ArgumentError(
        "tracker_contract must return a closed TrackerContract"
    ))
    contract.source isa Union{
        OwnershipTrackerSource,
        OwnershipRelationTrackerSource,
    } || throw(ArgumentError(
        "V1 trackers must derive from authoritative ownership"
    ))
    if contract.source isa OwnershipRelationTrackerSource
        contract.source.relation_handle > 0 || throw(ArgumentError(
            "relation-aware trackers require a positive relation handle"
        ))
    end
    contract.storage isa Union{
        DenseOwnerScalarStorage,
        DenseOwnerMomentsStorage,
    } || throw(ArgumentError("tracker storage strategy is not admitted in V1"))
    contract.visibility isa AcceptedCommitTrackerVisibility || throw(
        ArgumentError("V1 tracker visibility must be accepted-commit")
    )
    contract.update_bound isa SourceTargetOwnerUpdateBound || throw(
        ArgumentError("V1 tracker updates must be source/target-owner bounded")
    )
    contract.proposal_cost isa Union{
        ConstantTrackerCost,
        DimensionSquaredTrackerCost,
        BoundedNeighborhoodTrackerCost,
    } || throw(ArgumentError("tracker proposal cost is not admitted in V1"))
    if contract.proposal_cost isa BoundedNeighborhoodTrackerCost
        contract.proposal_cost.maximum_neighbors > 0 || throw(ArgumentError(
            "bounded-neighborhood tracker cost must be positive"
        ))
    end
    contract.rebuild_cost isa LatticeLinearTrackerCost || throw(
        ArgumentError("V1 tracker rebuilds must be lattice-linear")
    )
    support = contract.support
    concurrency = contract.concurrency
    support.checkerboard &&
        !(concurrency isa ClaimedOwnerExclusiveTrackerConcurrency) && throw(
            ArgumentError(
                "checkerboard trackers require claimed-owner-exclusive updates"
            )
        )
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
            descriptor -> typeof(tracker_contract(descriptor).quantity),
            descriptors,
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
        contract = tracker_contract(descriptor)
        support = contract.support
        support.gpu || throw(ArgumentError(
            "tracker $(contract.quantity) does not declare GPU " *
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

tracker_contract(::OwnershipCountTracker) = TrackerContract(
    Val(:cell_volume),
    OwnershipTrackerSource(),
    DenseOwnerScalarStorage{Int32}(),
    AcceptedCommitTrackerVisibility(),
    ClaimedOwnerExclusiveTrackerConcurrency(),
    SourceTargetOwnerUpdateBound(),
    PersistTrackerCheckpoint(),
    TrackerSupport(true, true, true, true),
    ConstantTrackerCost(),
    LatticeLinearTrackerCost(),
)

tracker_contract(descriptor::CellSurfaceTracker) = TrackerContract(
    Val(:cell_surface),
    OwnershipRelationTrackerSource(descriptor.relation_handle),
    DenseOwnerScalarStorage{Int32}(),
    AcceptedCommitTrackerVisibility(),
    ClaimedOwnerExclusiveTrackerConcurrency(),
    SourceTargetOwnerUpdateBound(),
    ReconstructTrackerCheckpoint(),
    TrackerSupport(true, true, true, true),
    BoundedNeighborhoodTrackerCost(descriptor.maximum_neighbors),
    LatticeLinearTrackerCost(),
)

tracker_contract(::CellMomentsTracker{N, T}) where {N, T} = TrackerContract(
    Val(:cell_moments),
    OwnershipTrackerSource(),
    DenseOwnerMomentsStorage{N, T}(),
    AcceptedCommitTrackerVisibility(),
    ClaimedOwnerExclusiveTrackerConcurrency(),
    SourceTargetOwnerUpdateBound(),
    ReconstructTrackerCheckpoint(),
    TrackerSupport(true, true, true, true),
    DimensionSquaredTrackerCost(),
    LatticeLinearTrackerCost(),
)

_tracker_quantity_symbol(::Val{Q}) where {Q} = Q
_tracker_source_symbol(::OwnershipTrackerSource) = :ownership
_tracker_source_symbol(source::OwnershipRelationTrackerSource) = (
    state = :ownership,
    relation_handle = source.relation_handle,
)
_tracker_visibility_symbol(::AcceptedCommitTrackerVisibility) =
    :accepted_commit
_tracker_concurrency_symbol(::ClaimedOwnerExclusiveTrackerConcurrency) =
    :claimed_owner_exclusive
_tracker_checkpoint_symbol(::PersistTrackerCheckpoint) = :persist
_tracker_checkpoint_symbol(::ReconstructTrackerCheckpoint) = :reconstruct
_tracker_cost_symbol(::ConstantTrackerCost) = :constant
_tracker_cost_symbol(::DimensionSquaredTrackerCost) = :dimension_squared
_tracker_cost_symbol(cost::BoundedNeighborhoodTrackerCost) = (
    class = :bounded_neighborhood,
    maximum_neighbors = cost.maximum_neighbors,
)
_tracker_cost_symbol(::LatticeLinearTrackerCost) = :lattice_linear
_tracker_storage_inspection(::DenseOwnerScalarStorage{T}) where {T} = (
    storage = Symbol(:dense_, lowercase(string(nameof(T)))),
    element_type = T,
)
_tracker_storage_inspection(
    ::DenseOwnerMomentsStorage{N, T}
) where {N, T} = (
    storage = :dense_coordinate_moments,
    dimensions = N,
    element_type = T,
)

function tracker_inspection(descriptor::AbstractTrackerDescriptor)
    contract = tracker_contract(descriptor)
    return merge((
        quantity = _tracker_quantity_symbol(contract.quantity),
        source = _tracker_source_symbol(contract.source),
        visibility = _tracker_visibility_symbol(contract.visibility),
        concurrency = _tracker_concurrency_symbol(contract.concurrency),
        checkpoint = _tracker_checkpoint_symbol(contract.checkpoint),
        proposal_cost = _tracker_cost_symbol(contract.proposal_cost),
        rebuild_cost = _tracker_cost_symbol(contract.rebuild_cost),
    ), _tracker_storage_inspection(contract.storage))
end

function tracker_rebuild(
        ::OwnershipCountTracker,
        source::TrackerSourceView,
        cell_kinds,
    )
    values = zeros(Int32, length(cell_kinds))
    for owner in source.ownership
        owner > 0 && (values[Int(owner)] += Int32(1))
    end
    return values
end


@inline function _surface_neighbor(
        descriptor::CellSurfaceTracker,
        source::TrackerSourceView,
        site,
        direction::Int,
    )
    start, count = _contact_domain_columns(
        source.domain_resources, descriptor.relation_handle
    )
    1 <= direction <= count || throw(BoundsError(1:count, direction))
    return relation_neighbor_index(
        source.shape,
        source.periodic,
        site,
        source.domain_resources.contact_offsets,
        start + direction - 1,
    )
end

@inline function _surface_neighbor_is_duplicate(
        descriptor::CellSurfaceTracker,
        source::TrackerSourceView,
        site,
        neighbor,
        direction::Int,
    )
    for prior in 1:(direction - 1)
        _surface_neighbor(descriptor, source, site, prior) == neighbor &&
            return true
    end
    return false
end

function tracker_rebuild(
        descriptor::CellSurfaceTracker,
        source::TrackerSourceView,
        cell_kinds,
    )
    values = zeros(Int32, length(cell_kinds))
    indices = CartesianIndices(source.ownership)
    for linear_index in eachindex(source.ownership)
        owner = @inbounds source.ownership[linear_index]
        owner > 0 || continue
        site = indices[linear_index]
        for direction in 1:Int(descriptor.maximum_neighbors)
            neighbor = _surface_neighbor(descriptor, source, site, direction)
            neighbor === nothing && continue
            neighbor == site && continue
            _surface_neighbor_is_duplicate(
                descriptor, source, site, neighbor, direction
            ) && continue
            @inbounds(source.ownership[neighbor]) == owner && continue
            @inbounds values[Int(owner)] += Int32(1)
        end
    end
    return values
end

function tracker_rebuild(
        ::CellMomentsTracker{N, T},
        source::TrackerSourceView,
        cell_kinds,
    ) where {N, T}
    ownership = source.ownership
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

function tracker_recompute(
        ::OwnershipCountTracker,
        source::TrackerSourceView,
        cell_kinds,
    )
    ownership = source.ownership
    expected = fill(Int32(0), length(cell_kinds))
    for linear_index in eachindex(ownership)
        owner = @inbounds ownership[linear_index]
        owner > 0 || continue
        expected[Int(owner)] += Int32(1)
    end
    return expected
end


function tracker_recompute(
        descriptor::CellSurfaceTracker,
        source::TrackerSourceView,
        cell_kinds,
    )
    expected = fill(Int32(0), length(cell_kinds))
    for site in CartesianIndices(source.ownership)
        owner = @inbounds source.ownership[site]
        owner > 0 || continue
        boundary = Int32(0)
        for direction in 1:Int(descriptor.maximum_neighbors)
            neighbor = _surface_neighbor(descriptor, source, site, direction)
            neighbor === nothing && continue
            neighbor == site && continue
            _surface_neighbor_is_duplicate(
                descriptor, source, site, neighbor, direction
            ) && continue
            boundary += Int32(@inbounds(source.ownership[neighbor]) != owner)
        end
        @inbounds expected[Int(owner)] += boundary
    end
    return expected
end

function tracker_recompute(
        ::CellMomentsTracker{N, T},
        source::TrackerSourceView,
        cell_kinds,
    ) where {N, T}
    ownership = source.ownership
    ndims(ownership) == N || throw(ArgumentError(
        "cell-moment oracle dimensionality does not match ownership"
    ))
    expected_first = fill(zero(T), N, length(cell_kinds))
    expected_second = fill(zero(T), N * N, length(cell_kinds))
    indices = CartesianIndices(ownership)
    for linear_index in eachindex(ownership)
        owner = @inbounds ownership[linear_index]
        owner > 0 || continue
        site = indices[linear_index]
        coordinates = map(dimension -> T(site[dimension]) - T(0.5), 1:N)
        for column in 1:N, row in 1:N
            coordinate = coordinates[row]
            column == 1 && (@inbounds expected_first[row, Int(owner)] +=
                coordinate)
            slot = row + (column - 1) * N
            @inbounds expected_second[slot, Int(owner)] +=
                coordinate * coordinates[column]
        end
    end
    return CellMomentsState(expected_first, expected_second)
end

@inline tracker_proposal_delta(
    ::OwnershipCountTracker,
    source::TrackerSourceView,
    target,
    old_owner::Int32,
    new_owner::Int32,
) = OwnerScalarDelta(Int32(1))

@inline function tracker_proposal_delta(
        ::CellMomentsTracker{N, T},
        source::TrackerSourceView,
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {N, T}
    coordinates = ntuple(
        dimension -> T(target[dimension]) - T(0.5), N
    )
    second = ntuple(N * N) do slot
        row = mod1(slot, N)
        column = fld(slot - 1, N) + 1
        coordinates[row] * coordinates[column]
    end
    return OwnerMomentsDelta(coordinates, second)
end


@inline function tracker_proposal_delta(
        descriptor::CellSurfaceTracker,
        source::TrackerSourceView,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    old_owner == new_owner && return SourceTargetScalarDelta(Int32(0), Int32(0))
    old_amount = Int32(0)
    new_amount = Int32(0)
    for direction in 1:Int(descriptor.maximum_neighbors)
        neighbor = _surface_neighbor(descriptor, source, target, direction)
        neighbor === nothing && continue
        neighbor == target && continue
        _surface_neighbor_is_duplicate(
            descriptor, source, target, neighbor, direction
        ) && continue
        neighbor_owner = @inbounds source.ownership[neighbor]
        old_owner > 0 && (old_amount += neighbor_owner == old_owner ?
            Int32(1) : Int32(-1))
        new_owner > 0 && (new_amount += neighbor_owner == new_owner ?
            Int32(-1) : Int32(1))
    end
    return SourceTargetScalarDelta(old_amount, new_amount)
end

function _validate_tracker_state(
        ::DenseOwnerScalarStorage{T}, values, cell_count
    ) where {T}
    values isa AbstractVector{T} && length(values) == cell_count || throw(
        ArgumentError("tracker rebuild violates its dense scalar storage contract")
    )
    return values
end

function _validate_tracker_state(
        ::DenseOwnerMomentsStorage{N, T}, state, cell_count
    ) where {N, T}
    state isa CellMomentsState{T} &&
        size(state.first) == (N, cell_count) &&
        size(state.second) == (N * N, cell_count) || throw(ArgumentError(
            "tracker rebuild violates its dense moments storage contract"
        ))
    return state
end

@inline function _apply_tracker_delta!(
        values::AbstractVector{T},
        ::DenseOwnerScalarStorage{T},
        delta::OwnerScalarDelta{T},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T}
    old_owner > 0 && (@inbounds values[Int(old_owner)] -= delta.amount)
    new_owner > 0 && (@inbounds values[Int(new_owner)] += delta.amount)
    return nothing
end


@inline function _apply_tracker_delta!(
        values::AbstractVector{T},
        ::DenseOwnerScalarStorage{T},
        delta::SourceTargetScalarDelta{T},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T}
    old_owner > 0 && (@inbounds values[Int(old_owner)] += delta.old_amount)
    new_owner > 0 && (@inbounds values[Int(new_owner)] += delta.new_amount)
    return nothing
end

@inline function _apply_tracker_delta!(
        state::CellMomentsState{T},
        ::DenseOwnerMomentsStorage{N, T},
        delta::OwnerMomentsDelta,
        old_owner::Int32,
        new_owner::Int32,
    ) where {N, T}
    length(delta.first) == N && length(delta.second) == N * N || throw(
        ArgumentError("tracker delta violates its bounded moments contract")
    )
    for row in 1:N
        coordinate = delta.first[row]
        old_owner > 0 && (@inbounds state.first[row, Int(old_owner)] -= coordinate)
        new_owner > 0 && (@inbounds state.first[row, Int(new_owner)] += coordinate)
        for column in 1:N
            slot = row + (column - 1) * N
            product = delta.second[slot]
            old_owner > 0 &&
                (@inbounds state.second[slot, Int(old_owner)] -= product)
            new_owner > 0 &&
                (@inbounds state.second[slot, Int(new_owner)] += product)
        end
    end
    return nothing
end

function initialize_tracker_state(
        plan::AbstractTrackerPlan, ownership, cell_kinds, program
    )
    source = tracker_source_view(program, ownership)
    return TrackerState(map(
        descriptor -> begin
            value = tracker_rebuild(descriptor, source, cell_kinds)
            _validate_tracker_state(
                tracker_contract(descriptor).storage,
                value,
                length(cell_kinds),
            )
        end,
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
        source,
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
        source,
    )
    value === nothing || throw(ArgumentError(
        "reconstructed tracker checkpoint unexpectedly stored logical state"
    ))
    rebuilt = tracker_rebuild(descriptor, source, cell_kinds)
    return _validate_tracker_state(
        tracker_contract(descriptor).storage,
        rebuilt,
        length(cell_kinds),
    )
end

function reconstruct_tracker_checkpoint(
        plan::AbstractTrackerPlan,
        checkpoint::TrackerCheckpointState,
        ownership,
        cell_kinds,
        program,
    )
    length(plan.descriptors) == length(checkpoint.values) || throw(
        ArgumentError("tracker checkpoint and plan are misaligned")
    )
    source = tracker_source_view(program, ownership)
    return TrackerState(map(
        (descriptor, value) -> _reconstruct_tracker_checkpoint(
            descriptor,
            tracker_checkpoint_policy(descriptor),
            value,
            ownership,
            cell_kinds,
            source,
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
    ::Tuple{}, ::Tuple{}, source, target, old_owner, new_owner
) = nothing

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
        quantity::Val,
        descriptors::Tuple,
        values::Tuple,
        source::TrackerSourceView,
        owner::Int32,
        target,
        old_owner::Int32,
        new_owner::Int32,
    )
    descriptor = first(descriptors)
    if tracker_contract(descriptor).quantity === quantity
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
        ::Val{Q}, ::Tuple{}, ::Tuple{}, source, owner, target, old_owner, new_owner
    ) where {Q}
    throw(ArgumentError("compiled tracker quantity `$Q` is unavailable"))
end

@inline tracker_value_after(
    plan::AbstractTrackerPlan,
    state::TrackerState,
    source::TrackerSourceView,
    quantity::Val,
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

@inline function _tracker_values(
        quantity::Val, descriptors::Tuple, values::Tuple
    )
    tracker_contract(first(descriptors)).quantity === quantity &&
        return first(values)
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
            tracker_contract(descriptor).storage,
            expected,
            length(cell_kinds),
        )
        state.values[index] == expected || throw(ArgumentError(
            "tracker $(tracker_inspection(plan.descriptors[index]).quantity) " *
            "differs from its independent recomputation oracle"
        ))
    end
    return state
end

tracker_plan_report(plan::TrackerExecutionPlan) = (
    count = length(plan.descriptors),
    quantities = map(
        descriptor -> _tracker_quantity_symbol(
            tracker_contract(descriptor).quantity
        ),
        plan.descriptors,
    ),
    descriptors = map(tracker_inspection, plan.descriptors),
    checkpoint = map(
        descriptor -> tracker_contract(descriptor).checkpoint,
        plan.descriptors,
    ),
    fingerprint = plan.fingerprint,
)

Adapt.@adapt_structure OwnershipCountTracker
Adapt.@adapt_structure CellSurfaceTracker
Adapt.@adapt_structure CellMomentsTracker
Adapt.@adapt_structure CellMomentsState
Adapt.@adapt_structure TrackerExecutionPlan
Adapt.@adapt_structure TrackerKernelPlan
Adapt.@adapt_structure TrackerState
Adapt.@adapt_structure TrackerCheckpointState
