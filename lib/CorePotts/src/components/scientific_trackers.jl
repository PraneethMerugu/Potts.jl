"""Exact finite-cell and conceptual-medium occupancy tracker."""
struct OwnershipVolumeTracker <: AbstractTracker end

function component_identity(::OwnershipVolumeTracker)
    ComponentIdentity(:ownership_volume_tracker, v"1.0.0", :tracker)
end

function rebuild_tracker(::OwnershipVolumeTracker, state::LogicalPottsState)
    finite = Int32.(derived_state(state).finite_volumes)
    media = Int32.(derived_state(state).medium_volumes)
    return (finite = finite, media = media)
end

"""One cached finite-cell boundary measure with a complete metric/relation identity."""
struct BoundaryMeasureTracker{M <: AbstractBoundaryMetric,
    R <: StaticCartesianRelation{<:SurfaceRole}} <: AbstractTracker
    metric::M
    relation::R
    identity::NTuple{2, UInt64}
end

function BoundaryMeasureTracker(metric::AbstractBoundaryMetric,
        relation::StaticCartesianRelation{<:SurfaceRole})
    return BoundaryMeasureTracker(metric, relation,
        _boundary_tracker_identity(metric, relation))
end

function component_identity(::BoundaryMeasureTracker)
    ComponentIdentity(:boundary_measure_tracker, v"1.0.0", :tracker)
end
required_relations(::BoundaryMeasureTracker) = (:surface,)

function rebuild_tracker(tracker::BoundaryMeasureTracker, state::LogicalPottsState,
        domain::Union{CartesianDomain, CompiledCartesianDomain})
    T = tracker.metric isa BoundaryEdgeCount ? Int64 : eltype(tracker.relation.weights)
    result = zeros(T, nslots(capacity(state)))
    for id in active_cell_ids(state)
        result[Int(value(id))] = boundary_measure(state, domain, tracker.relation,
            CellOwner(id), tracker.metric)
    end
    return result
end

"""Zero-storage marker used when no center-dependent component is compiled."""
struct NoMomentStorage end
struct NoMomentDelta end

compile_derived_observable(::Nothing, state, domain) = NoMomentStorage()
derived_observable_arrays(::NoMomentStorage) = ()
stage_derived_observable_delta(::Nothing, state, proposal) = NoMomentDelta()
@inline apply_derived_observable_delta!(::NoMomentStorage, ::NoMomentDelta, delta) = nothing

"""Device-adaptable tracker arrays owned by one compiled scientific model."""
struct ScientificTrackerStorage{V, M, B, U}
    finite_volumes::V
    medium_volumes::M
    boundary_measures::B
    moments::U
end

function Adapt.adapt_structure(to, storage::ScientificTrackerStorage)
    return ScientificTrackerStorage(
        Adapt.adapt(to, storage.finite_volumes),
        Adapt.adapt(to, storage.medium_volumes),
        Adapt.adapt(to, storage.boundary_measures),
        Adapt.adapt(to, storage.moments)
    )
end

"""Compiled state, ownership domain, derived caches, and device-safe retirement defaults."""
struct CompiledScientificState{P <: CompiledPottsState, D <: CompiledCartesianDomain,
    T <: ScientificTrackerStorage, B <: BoundaryMeasureTracker, R <: NamedTuple}
    potts::P
    domain::D
    trackers::T
    boundary_tracker::B
    retirement_defaults::R
end

"""Device-valid scientific state and immutable tracker identity passed to hot kernels."""
struct ScientificExecutionState{C <: CompiledStateStorage, D <: CompiledCartesianDomain,
    T <: ScientificTrackerStorage, B <: BoundaryMeasureTracker, R <: NamedTuple,
    M <: Tuple}
    core::C
    domain::D
    trackers::T
    boundary_tracker::B
    retirement_defaults::R
    medium_ids::M
end

function scientific_execution(state::CompiledScientificState)
    ScientificExecutionState(
        state.potts.storage, state.domain, state.trackers, state.boundary_tracker,
        state.retirement_defaults, state.potts.descriptor.medium_ids)
end

function Adapt.adapt_structure(to, state::ScientificExecutionState)
    return ScientificExecutionState(
        Adapt.adapt(to, state.core),
        Adapt.adapt(to, state.domain),
        Adapt.adapt(to, state.trackers),
        state.boundary_tracker,
        state.retirement_defaults,
        state.medium_ids
    )
end

_proposal_state_dims(state::ScientificExecutionState) = state.domain.descriptor.dims
@inline function _proposal_owner_at(state::ScientificExecutionState, site)
    ownership = state.core.ownership
    return _owner_ref_unchecked(
        @inbounds(ownership.tags[site]), @inbounds(ownership.ids[site]))
end
@inline _property_column(state::ScientificExecutionState, ::CellPropertyRef{K}) where {K} = getproperty(
    state.core.properties, K)
@inline function owner_type(state::ScientificExecutionState, table::MediumTypeTable,
        owner::OwnerRef)
    return is_cell_owner(owner) ? @inbounds(state.core.cell_types[Int(owner.value)]) :
           _medium_type(table, owner)
end

function energy_change(component::QuadraticVolumeHamiltonian, proposal::CopyProposal,
        state::ScientificExecutionState)
    targets = _property_column(state, _volume_target(component))
    strengths = _property_column(state, _volume_strength(component))
    T = float(promote_type(eltype(targets), eltype(strengths)))
    delta = zero(T)
    if is_cell_owner(proposal.losing)
        index = Int(proposal.losing.value)
        volume = @inbounds state.trackers.finite_volumes[index]
        delta += @inbounds _quadratic_volume_owner_change(
            T(strengths[index]), T(targets[index]), volume, Int32(-1))
    end
    if is_cell_owner(proposal.gaining)
        index = Int(proposal.gaining.value)
        volume = @inbounds state.trackers.finite_volumes[index]
        delta += @inbounds _quadratic_volume_owner_change(
            T(strengths[index]), T(targets[index]), volume, Int32(1))
    end
    return delta
end

function energy_change(component::QuadraticBoundaryHamiltonian, proposal::CopyProposal,
        state::ScientificExecutionState)
    (component.tracker_identity[1] == state.boundary_tracker.identity[1] &&
     component.tracker_identity[2] == state.boundary_tracker.identity[2]) ||
        throw(ArgumentError(
            "boundary component does not match the compiled boundary tracker descriptor"))
    targets = _property_column(state, _boundary_target(component))
    strengths = _property_column(state, _boundary_strength(component))
    T = float(promote_type(eltype(targets), eltype(strengths),
        eltype(component.relation.weights)))
    changes = boundary_measure_change(state, state.domain, component.relation,
        proposal, component.metric)
    result = zero(T)
    if is_cell_owner(proposal.losing)
        index = Int(proposal.losing.value)
        measure = @inbounds state.trackers.boundary_measures[index]
        volume = @inbounds state.trackers.finite_volumes[index]
        result += @inbounds _quadratic_boundary_owner_change(T(strengths[index]),
            T(targets[index]), T(measure), volume, T(changes.losing), Int32(-1))
    end
    if is_cell_owner(proposal.gaining)
        index = Int(proposal.gaining.value)
        measure = @inbounds state.trackers.boundary_measures[index]
        volume = @inbounds state.trackers.finite_volumes[index]
        result += @inbounds _quadratic_boundary_owner_change(T(strengths[index]),
            T(targets[index]), T(measure), volume, T(changes.gaining), Int32(1))
    end
    return result
end

function Adapt.adapt_structure(to, state::CompiledScientificState)
    return CompiledScientificState(
        adapt_execution(to, state.potts),
        Adapt.adapt(to, state.domain),
        Adapt.adapt(to, state.trackers),
        state.boundary_tracker,
        state.retirement_defaults
    )
end

function _retirement_defaults(schema::PropertySchema)
    names = Tuple(property_keys(schema))
    defaults = map(descriptor -> _default_property_value(descriptor), schema.descriptors)
    return NamedTuple{names}(defaults)
end

function _validate_domain_owners(state::LogicalPottsState, domain::CartesianDomain)
    declared_media = Set(value.(medium_ids(state)))
    for axis in domain.boundaries, face in (axis.negative, axis.positive)

        if face isa FixedExterior && !(face.owner.value in declared_media)
            throw(ArgumentError(
                "fixed-exterior owner is not a declared conceptual medium domain"))
        end
    end
    for site in eachindex(domain.mutable_mask)
        domain.mutable_mask[site] && continue
        owner = OwnerRef(domain.immutable_tags[site], domain.immutable_ids[site])
        owner.value in declared_media || throw(ArgumentError(
            "obstacle owner is not a declared conceptual medium domain"))
        owner_at(state, site) == owner || throw(ArgumentError(
            "logical ownership does not match the immutable obstacle owner"))
    end
    return domain
end

function compile_scientific_state(state::LogicalPottsState, domain::CartesianDomain,
        boundary_tracker::BoundaryMeasureTracker; moment_tracker = nothing)
    lattice_size(state) == domain.dims || throw(ArgumentError(
        "logical state and ownership domain dimensions must match"))
    _validate_domain_owners(state, domain)
    validate_relation_domain(domain, boundary_tracker.relation)
    occupancy = rebuild_tracker(OwnershipVolumeTracker(), state)
    all(value -> typemin(Int32) <= value <= typemax(Int32),
        derived_state(state).finite_volumes) || throw(OverflowError(
        "finite-cell volumes do not fit the compiled Int32 tracker"))
    all(value -> typemin(Int32) <= value <= typemax(Int32),
        derived_state(state).medium_volumes) || throw(OverflowError(
        "medium volumes do not fit the compiled Int32 tracker"))
    boundary = rebuild_tracker(boundary_tracker, state, domain)
    moments = compile_derived_observable(moment_tracker, state, domain)
    trackers = ScientificTrackerStorage(occupancy.finite, occupancy.media, boundary, moments)
    return CompiledScientificState(compile_state(state), compile_domain(domain), trackers,
        boundary_tracker, _retirement_defaults(state.properties.schema))
end

function _tracker_arrays(storage::ScientificTrackerStorage)
    return (storage.finite_volumes, storage.medium_volumes, storage.boundary_measures,
        derived_observable_arrays(storage.moments)...)
end

function scientific_storage_valid(state::CompiledScientificState)
    device_storage_valid(state.potts.storage) || return false
    domain_storage_valid(state.domain.storage) || return false
    all(_device_array_value, _tracker_arrays(state.trackers)) || return false
    arrays = (_storage_arrays(state.potts.storage)...,
        state.domain.storage.mutable_mask, state.domain.storage.mutable_sites,
        state.domain.storage.immutable_tags, state.domain.storage.immutable_ids,
        _tracker_arrays(state.trackers)...)
    backends = map(KernelAbstractions.get_backend, arrays)
    return all(isequal(first(backends)), backends) && isbits(state.boundary_tracker) &&
           isbits(state.retirement_defaults)
end

function scientific_state_bytes(state::CompiledScientificState)
    sum(_array_bytes,
        (
            _storage_arrays(state.potts.storage)...,
            state.domain.storage.mutable_mask, state.domain.storage.mutable_sites,
            state.domain.storage.immutable_tags, state.domain.storage.immutable_ids,
            _tracker_arrays(state.trackers)...
        ))
end

"""Pure tracker delta staged from one common pre-copy snapshot."""
struct ScientificTrackerDelta{T, U}
    losing_cell::UInt32
    gaining_cell::UInt32
    losing_medium::UInt32
    gaining_medium::UInt32
    losing_boundary::T
    gaining_boundary::T
    moments::U
end

"""Immutable ownership-plus-tracker transaction; construction performs no writes."""
struct StagedCopyTransaction{T, U}
    proposal::CopyProposal
    trackers::ScientificTrackerDelta{T, U}
end

@inline function _medium_index(medium_ids::Tuple, owner::OwnerRef)
    is_medium_owner(owner) || return UInt32(0)
    @inbounds for index in eachindex(medium_ids)
        medium_ids[index] == owner.value && return UInt32(index)
    end
    throw(ArgumentError("proposal references an undeclared medium owner"))
end

function stage_copy_transaction(state::CompiledScientificState,
        tracker::BoundaryMeasureTracker, proposal::CopyProposal; moment_tracker = nothing)
    return stage_copy_transaction(
        scientific_execution(state), tracker, proposal; moment_tracker)
end

@inline function stage_copy_transaction(state::ScientificExecutionState,
        tracker::BoundaryMeasureTracker, proposal::CopyProposal; moment_tracker = nothing)
    tracker == state.boundary_tracker || throw(ArgumentError(
        "staged transaction tracker does not match the compiled boundary tracker descriptor"))
    core = state.core
    domain = state.domain
    1 <= proposal.recipient <= prod(domain.descriptor.dims) || throw(BoundsError(
        1:prod(domain.descriptor.dims), proposal.recipient))
    domain.storage.mutable_mask[proposal.recipient] != 0 || throw(ArgumentError(
        "an immutable domain site cannot be a copy recipient"))
    owner_at(core.ownership, proposal.recipient) == proposal.losing ||
        throw(ArgumentError(
            "proposal losing owner does not match the staged snapshot"))
    owner_at(core.ownership, proposal.donor) == proposal.gaining ||
        throw(ArgumentError(
            "proposal gaining owner does not match the staged snapshot"))
    return _stage_copy_transaction_unchecked(
        state, tracker, proposal; moment_tracker)
end

@inline function _stage_copy_transaction_unchecked(state::ScientificExecutionState,
        tracker::BoundaryMeasureTracker, proposal::CopyProposal; moment_tracker = nothing)
    # Proposal construction proves recipient/donor bounds and snapshot ownership.
    domain = state.domain
    changes = _boundary_measure_change_unchecked(
        state, domain, tracker.relation, proposal, tracker.metric)
    T = eltype(state.trackers.boundary_measures)
    medium_ids = state.medium_ids
    moment_change = stage_derived_observable_delta(moment_tracker, state, proposal)
    delta = ScientificTrackerDelta(
        is_cell_owner(proposal.losing) ? proposal.losing.value : UInt32(0),
        is_cell_owner(proposal.gaining) ? proposal.gaining.value : UInt32(0),
        _medium_index(medium_ids, proposal.losing),
        _medium_index(medium_ids, proposal.gaining),
        T(changes.losing), T(changes.gaining), moment_change
    )
    return StagedCopyTransaction(proposal, delta)
end

@inline _reset_columns!(::Tuple{}, ::Tuple{}, index) = nothing

@inline function _reset_columns!(columns::Tuple, defaults::Tuple, index)
    @inbounds first(columns)[index] = first(defaults)
    _reset_columns!(Base.tail(columns), Base.tail(defaults), index)
    return nothing
end

@inline function _commit_staged!(state::CompiledScientificState,
        transaction::StagedCopyTransaction)
    return _commit_staged!(scientific_execution(state), transaction)
end

@inline function _decrement_medium!(trackers, index, ::Val{false})
    @inbounds trackers.medium_volumes[index] -= Int32(1)
    return nothing
end

@inline function _decrement_medium!(trackers, index, ::Val{true})
    Atomix.@atomic trackers.medium_volumes[index] -= Int32(1)
    return nothing
end

@inline function _increment_medium!(trackers, index, ::Val{false})
    @inbounds trackers.medium_volumes[index] += Int32(1)
    return nothing
end

@inline function _increment_medium!(trackers, index, ::Val{true})
    Atomix.@atomic trackers.medium_volumes[index] += Int32(1)
    return nothing
end

@inline _apply_staged_moments!(trackers, delta, ::Val{false}) = nothing
@inline function _apply_staged_moments!(trackers, delta, ::Val{true})
    apply_derived_observable_delta!(trackers.moments, delta.moments, delta)
    return nothing
end

@inline function _commit_staged_core!(state::ScientificExecutionState,
        transaction::StagedCopyTransaction, atomic_medium, apply_moments)
    proposal = transaction.proposal
    delta = transaction.trackers
    core = state.core
    trackers = state.trackers
    recipient = proposal.recipient
    @inbounds begin
        core.ownership.tags[recipient] = proposal.gaining.tag
        core.ownership.ids[recipient] = proposal.gaining.value
        if delta.losing_cell != 0
            losing = Int(delta.losing_cell)
            trackers.finite_volumes[losing] -= Int32(1)
            trackers.boundary_measures[losing] += delta.losing_boundary
            if trackers.finite_volumes[losing] == 0
                core.active[losing] = UInt8(0)
                core.cell_types[losing] = UInt32(0)
                _reset_columns!(Tuple(core.properties), Tuple(state.retirement_defaults), losing)
            end
        else
            _decrement_medium!(trackers, Int(delta.losing_medium), atomic_medium)
        end
        if delta.gaining_cell != 0
            gaining = Int(delta.gaining_cell)
            trackers.finite_volumes[gaining] += Int32(1)
            trackers.boundary_measures[gaining] += delta.gaining_boundary
        else
            _increment_medium!(trackers, Int(delta.gaining_medium), atomic_medium)
        end
        _apply_staged_moments!(trackers, delta, apply_moments)
    end
    return nothing
end

@inline function _commit_staged!(state::ScientificExecutionState,
        transaction::StagedCopyTransaction)
    return _commit_staged_core!(state, transaction, Val(false), Val(true))
end

"""Commit exactly once when accepted; rejection is a guaranteed no-write operation."""
function commit_staged!(state::CompiledScientificState,
        transaction::StagedCopyTransaction; accepted::Bool)
    accepted || return false
    proposal = transaction.proposal
    owner_at(state.potts.storage.ownership, proposal.recipient) == proposal.losing ||
        throw(ArgumentError("staged transaction is stale at commit"))
    _commit_staged!(state, transaction)
    return true
end

@kernel function _commit_staged_kernel!(state, transaction, accepted)
    index = @index(Global, Linear)
    index == 1 && accepted && _commit_staged!(state, transaction)
end

"""Launch one device-resident staged commit without an implicit synchronization."""
function launch_staged_commit!(plan::ExecutionPlan, state::CompiledScientificState,
        transaction::StagedCopyTransaction; accepted::Bool)
    kernel = _commit_staged_kernel!(plan.backend, 1)
    return launch!(
        plan, kernel, scientific_execution(state), transaction, accepted; ndrange = 1)
end

function tracker_conformance_errors(state::CompiledScientificState,
        tracker::BoundaryMeasureTracker, logical::LogicalPottsState)
    errors = String[]
    tracker == state.boundary_tracker || push!(errors,
        "requested boundary tracker does not match the compiled tracker descriptor")
    occupancy = rebuild_tracker(OwnershipVolumeTracker(), logical)
    state.trackers.finite_volumes == occupancy.finite || push!(errors,
        "finite-cell volume tracker differs from ownership recomputation")
    state.trackers.medium_volumes == occupancy.media || push!(errors,
        "medium volume tracker differs from ownership recomputation")
    boundary = rebuild_tracker(tracker, logical, state.domain)
    _tracker_values_conform(state.trackers.boundary_measures, boundary) || push!(errors,
        "boundary tracker differs from ownership recomputation")
    return errors
end

function _tracker_values_conform(observed::AbstractArray{<:Integer}, expected::AbstractArray)
    observed == expected
end

function _tracker_values_conform(observed::AbstractArray{T}, expected::AbstractArray) where {
        T <: AbstractFloat}
    tolerance = T(16) * eps(T)
    return all(isapprox.(observed, expected; rtol = tolerance, atol = tolerance))
end
