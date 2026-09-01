# Typed derived-state trackers and their aligned runtime storage.

abstract type AbstractTrackerPlanEntry end
"""Compiler-owned description of one derived scientific quantity."""
abstract type AbstractTrackerDescriptor <: AbstractTrackerPlanEntry end
abstract type AbstractTrackerPlan end
"""Checkpoint policy for derived tracker storage."""
abstract type AbstractTrackerCheckpointPolicy end
"""Concurrency contract governing proposal-time tracker updates."""
abstract type AbstractTrackerConcurrency end
"""Authoritative scientific source from which a tracker is derived."""
abstract type AbstractTrackerSource end
"""Closed physical-storage strategy for a tracker quantity."""
abstract type AbstractTrackerStorage end
"""Visibility boundary at which tracker changes become observable."""
abstract type AbstractTrackerVisibility end
"""Bound on the owners or sites touched by one tracker update."""
abstract type AbstractTrackerUpdateBound end
"""Static complexity class used to qualify tracker execution."""
abstract type AbstractTrackerCost end
"""Typed proposal-local change to a derived tracker quantity."""
abstract type AbstractTrackerDelta end

"""Persist tracker values in checkpoints."""
struct PersistTrackerCheckpoint <: AbstractTrackerCheckpointPolicy end
"""Reconstruct tracker values from authoritative state after restoration."""
struct ReconstructTrackerCheckpoint <: AbstractTrackerCheckpointPolicy end
"""Permit concurrent updates only after exclusive-owner claims succeed."""
struct ClaimedOwnerExclusiveTrackerConcurrency <:
       AbstractTrackerConcurrency end
"""Derive a tracker directly from lattice ownership."""
struct OwnershipTrackerSource <: AbstractTrackerSource end
"""Derive a tracker from ownership and one compiler-bound relation."""
struct OwnershipRelationTrackerSource <: AbstractTrackerSource
    relation_handle::Int32
end
"""Scientific tracker quantity qualified by one value-level source handle."""
struct QualifiedTrackerKey{Q <: Val}
    quantity::Q
    source_handle::Int32
    function QualifiedTrackerKey(quantity::Q, source_handle::Integer) where {Q <: Val}
        source_handle > 0 || throw(ArgumentError(
            "qualified tracker keys require a positive source handle"
        ))
        return new{Q}(quantity, Int32(source_handle))
    end
end
"""Store one scalar of type `T` per finite owner."""
struct DenseOwnerScalarStorage{T} <: AbstractTrackerStorage end
struct DenseOwnerScalarGroupStorage{T} <: AbstractTrackerStorage end
"""Store first and second coordinate moments for each finite owner."""
struct DenseOwnerMomentsStorage{N, T <: AbstractFloat} <:
       AbstractTrackerStorage end
"""Publish tracker changes with the accepted-state commit."""
struct AcceptedCommitTrackerVisibility <: AbstractTrackerVisibility end
"""Bound a proposal update to its old and new finite owners."""
struct SourceTargetOwnerUpdateBound <: AbstractTrackerUpdateBound end
"""Declare constant work per proposal."""
struct ConstantTrackerCost <: AbstractTrackerCost end
"""Declare proposal work proportional to squared spatial dimension."""
struct DimensionSquaredTrackerCost <: AbstractTrackerCost end
"""Declare proposal work bounded by `maximum_neighbors`."""
struct BoundedNeighborhoodTrackerCost <: AbstractTrackerCost
    maximum_neighbors::Int16
end
"""Declare rebuild work linear in lattice size."""
struct LatticeLinearTrackerCost <: AbstractTrackerCost end

"""Engine and backend qualification declared by a tracker contract."""
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

"""Closed scientific, storage, concurrency, checkpoint, and cost contract."""
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

"""One signed scalar change for a single owner."""
struct OwnerScalarDelta{T} <: AbstractTrackerDelta
    amount::T
end

"""Independent signed changes for the proposal's old and new finite owners."""
struct SourceTargetScalarDelta{T} <: AbstractTrackerDelta
    old_amount::T
    new_amount::T
end

"""First- and second-moment changes for a single owner."""
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

"""Homogeneous value-level instances sharing one scalar tracker strategy."""
struct DenseScalarTrackerGroup{
        Q <: Val,
        D <: AbstractTrackerDescriptor,
        A <: AbstractVector{D},
        H <: AbstractVector{Int32},
    } <: AbstractTrackerPlanEntry
    quantity::Q
    descriptors::A
    source_handles::H
    function DenseScalarTrackerGroup(
            quantity::Q,
            descriptors::A,
            source_handles::H,
        ) where {
            Q <: Val,
            D <: AbstractTrackerDescriptor,
            A <: AbstractVector{D},
            H <: AbstractVector{Int32},
        }
        isempty(descriptors) && throw(ArgumentError(
            "dense scalar tracker groups cannot be empty"
        ))
        length(descriptors) == length(source_handles) || throw(ArgumentError(
            "dense scalar tracker groups require one source handle per member"
        ))
        return new{Q, D, A, H}(quantity, descriptors, source_handles)
    end
end

function DenseScalarTrackerGroup(descriptors::A) where {
        D <: AbstractTrackerDescriptor,
        A <: AbstractVector{D},
    }
    keys = tracker_quantity.(descriptors)
    all(key -> key isa QualifiedTrackerKey, keys) || throw(ArgumentError(
        "dense scalar tracker groups require qualified tracker keys"
    ))
    quantity = first(keys).quantity
    all(key -> key.quantity === quantity, keys) || throw(ArgumentError(
        "dense scalar tracker groups require one structural quantity"
    ))
    source_handles = Int32[key.source_handle for key in keys]
    return DenseScalarTrackerGroup(
        quantity, descriptors, source_handles
    )
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

"""Return the closed `TrackerContract` for a descriptor."""
function tracker_contract end
"""Construct complete tracker values from an authoritative source view."""
function tracker_rebuild end
"""Independently recompute complete tracker storage from authoritative state."""
function tracker_recompute end
"""Return the bounded tracker change produced by one proposal."""
function tracker_proposal_delta end
"""Adapt an isbits tracker descriptor to an execution backend."""
function tracker_adapt end

"""Read-only tracker source shared by rebuild, proposal, and oracle paths."""
struct TrackerSourceView{O, S, P, R}
    ownership::O
    shape::S
    periodic::P
    domain_resources::R
end

"""Construct the read-only authoritative source used by tracker protocols."""
tracker_source_view(program, ownership) = TrackerSourceView(
    ownership,
    program.shape,
    program.periodic,
    program.descriptor_plan.domain_resources,
)

"""Return the stable value-level identity of a tracker quantity."""
tracker_quantity(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).quantity
tracker_quantity(descriptor::CellSurfaceTracker) = QualifiedTrackerKey(
    tracker_contract(descriptor).quantity,
    descriptor.relation_handle,
)
"""Return all stable quantity identities produced by a descriptor or group."""
tracker_quantities(descriptor::AbstractTrackerDescriptor) =
    (tracker_quantity(descriptor),)
tracker_quantities(group::DenseScalarTrackerGroup) =
    Tuple(QualifiedTrackerKey(group.quantity, handle)
          for handle in group.source_handles)
"""Return the checkpoint policy declared by a tracker contract."""
tracker_checkpoint_policy(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).checkpoint
tracker_checkpoint_policy(group::DenseScalarTrackerGroup) =
    tracker_checkpoint_policy(first(group.descriptors))
"""Return the engine and backend qualification for a tracker."""
tracker_support(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).support
tracker_support(group::DenseScalarTrackerGroup) =
    tracker_support(first(group.descriptors))
"""Return the proposal-update concurrency contract for a tracker."""
tracker_concurrency(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).concurrency
tracker_concurrency(group::DenseScalarTrackerGroup) =
    tracker_concurrency(first(group.descriptors))
"""Return the closed physical-storage strategy for a tracker."""
tracker_storage(descriptor::AbstractTrackerDescriptor) =
    tracker_contract(descriptor).storage
function tracker_storage(group::DenseScalarTrackerGroup)
    storage = tracker_storage(first(group.descriptors))
    storage isa DenseOwnerScalarStorage || throw(ArgumentError(
        "dense scalar tracker groups require scalar member storage"
    ))
    return DenseOwnerScalarGroupStorage{_tracker_storage_eltype(storage)}()
end

_tracker_storage_eltype(::DenseOwnerScalarStorage{T}) where {T} = T

tracker_adapt(to, descriptor::AbstractTrackerDescriptor) = descriptor
tracker_adapt(to, group::DenseScalarTrackerGroup) =
    DenseScalarTrackerGroup(
        group.quantity,
        Adapt.adapt(to, group.descriptors),
        Adapt.adapt(to, group.source_handles),
    )

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
        "trackers must derive from authoritative ownership"
    ))
    contract.quantity isa Val || throw(ArgumentError(
        "tracker contracts must declare a closed scientific quantity"
    ))
    if contract.source isa OwnershipRelationTrackerSource
        contract.source.relation_handle > 0 || throw(ArgumentError(
            "relation-aware trackers require a positive relation handle"
        ))
    end
    contract.storage isa Union{
        DenseOwnerScalarStorage,
        DenseOwnerMomentsStorage,
    } || throw(ArgumentError("tracker storage strategy is not admitted"))
    contract.visibility isa AcceptedCommitTrackerVisibility || throw(
        ArgumentError("tracker visibility must be accepted-commit")
    )
    contract.update_bound isa SourceTargetOwnerUpdateBound || throw(
        ArgumentError("tracker updates must be source/target-owner bounded")
    )
    contract.proposal_cost isa Union{
        ConstantTrackerCost,
        DimensionSquaredTrackerCost,
        BoundedNeighborhoodTrackerCost,
    } || throw(ArgumentError("tracker proposal cost is not admitted"))
    if contract.proposal_cost isa BoundedNeighborhoodTrackerCost
        contract.proposal_cost.maximum_neighbors > 0 || throw(ArgumentError(
            "bounded-neighborhood tracker cost must be positive"
        ))
    end
    contract.rebuild_cost isa LatticeLinearTrackerCost || throw(
        ArgumentError("tracker rebuilds must be lattice-linear")
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

function _validate_tracker_descriptor(group::DenseScalarTrackerGroup)
    foreach(_validate_tracker_descriptor, group.descriptors)
    for index in eachindex(group.descriptors, group.source_handles)
        tracker_quantity(group.descriptors[index]) == QualifiedTrackerKey(
            group.quantity, group.source_handles[index]
        ) || throw(ArgumentError(
            "dense scalar tracker group metadata differs from its member key"
        ))
    end
    first_contract = tracker_contract(first(group.descriptors))
    first_contract.storage isa DenseOwnerScalarStorage || throw(ArgumentError(
        "dense scalar tracker groups require dense scalar member storage"
    ))
    for descriptor in Iterators.drop(group.descriptors, 1)
        contract = tracker_contract(descriptor)
        typeof(contract.storage) === typeof(first_contract.storage) || throw(
            ArgumentError("grouped trackers must share one storage representation")
        )
        typeof(contract.visibility) === typeof(first_contract.visibility) ||
            throw(ArgumentError("grouped trackers must share visibility"))
        typeof(contract.concurrency) === typeof(first_contract.concurrency) ||
            throw(ArgumentError("grouped trackers must share concurrency"))
        typeof(contract.update_bound) === typeof(first_contract.update_bound) ||
            throw(ArgumentError("grouped trackers must share an update bound"))
        typeof(contract.checkpoint) === typeof(first_contract.checkpoint) ||
            throw(ArgumentError("grouped trackers must share checkpoint policy"))
        contract.support == first_contract.support || throw(ArgumentError(
            "grouped trackers must share backend support"
        ))
    end
    allunique(tracker_quantities(group)) || throw(ArgumentError(
        "a dense scalar tracker group contains duplicate instance keys"
    ))
    return group
end

"""Validated ordered tracker descriptors and their stable plan fingerprint."""
struct TrackerExecutionPlan{D <: Tuple} <: AbstractTrackerPlan
    descriptors::D
    fingerprint::String
    function TrackerExecutionPlan(descriptors::D, fingerprint) where {D <: Tuple}
        all(descriptor -> descriptor isa AbstractTrackerPlanEntry, descriptors) ||
            throw(ArgumentError(
                "tracker plans admit only typed tracker-plan entries"
            ))
        foreach(_validate_tracker_descriptor, descriptors)
        quantities = map(
            tracker_quantities,
            descriptors,
        )
        flattened_quantities = Tuple(Iterators.flatten(quantities))
        allunique(flattened_quantities) || throw(ArgumentError(
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
            "tracker $(tracker_quantities(descriptor)) does not declare GPU " *
            "support (reason code $(support.reason_code))"
        ))
        adapted = tracker_adapt(to, descriptor)
        if descriptor isa DenseScalarTrackerGroup
            eltype(adapted.descriptors) === eltype(descriptor.descriptors) ||
                throw(ArgumentError(
                    "tracker-group adaptation changed its structural member type"
                ))
            eltype(adapted.source_handles) === Int32 || throw(ArgumentError(
                "tracker-group adaptation changed its source-handle type"
            ))
        else
            typeof(adapted) === typeof(descriptor) || throw(ArgumentError(
                "tracker adaptation changed its structural descriptor type"
            ))
        end
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

function tracker_rebuild(
        group::DenseScalarTrackerGroup,
        source::TrackerSourceView,
        cell_kinds,
    )
    first_values = tracker_rebuild(
        first(group.descriptors), source, cell_kinds
    )
    values = Matrix{eltype(first_values)}(
        undef, length(first_values), length(group.descriptors)
    )
    copyto!(view(values, :, 1), first_values)
    for index in 2:length(group.descriptors)
        member_values = tracker_rebuild(
            group.descriptors[index], source, cell_kinds
        )
        copyto!(view(values, :, index), member_values)
    end
    return values
end

function tracker_recompute(
        group::DenseScalarTrackerGroup,
        source::TrackerSourceView,
        cell_kinds,
    )
    first_values = tracker_recompute(
        first(group.descriptors), source, cell_kinds
    )
    values = Matrix{eltype(first_values)}(
        undef, length(first_values), length(group.descriptors)
    )
    copyto!(view(values, :, 1), first_values)
    for index in 2:length(group.descriptors)
        member_values = tracker_recompute(
            group.descriptors[index], source, cell_kinds
        )
        copyto!(view(values, :, index), member_values)
    end
    return values
end

_tracker_quantity_symbol(::Val{Q}) where {Q} = Q
_tracker_quantity_symbol(key::QualifiedTrackerKey) =
    _tracker_quantity_symbol(key.quantity)
_tracker_binding_inspection(::Val) = NamedTuple()
_tracker_binding_inspection(key::QualifiedTrackerKey) = (
    source_handle = key.source_handle,
)
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

"""Return stable scientific and execution facts for a tracker descriptor."""
function tracker_inspection(descriptor::AbstractTrackerDescriptor)
    contract = tracker_contract(descriptor)
    key = tracker_quantity(descriptor)
    return merge((
        quantity = _tracker_quantity_symbol(key),
        source = _tracker_source_symbol(contract.source),
        visibility = _tracker_visibility_symbol(contract.visibility),
        concurrency = _tracker_concurrency_symbol(contract.concurrency),
        checkpoint = _tracker_checkpoint_symbol(contract.checkpoint),
        proposal_cost = _tracker_cost_symbol(contract.proposal_cost),
        rebuild_cost = _tracker_cost_symbol(contract.rebuild_cost),
    ), _tracker_binding_inspection(key),
        _tracker_storage_inspection(contract.storage))
end
