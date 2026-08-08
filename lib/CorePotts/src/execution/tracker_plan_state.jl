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
    start, count = _contact_domain_columns(
        source.domain_resources, descriptor.relation_handle
    )
    count == Int(descriptor.maximum_neighbors) || throw(ArgumentError(
        "surface tracker relation degree differs from its compiled bound"
    ))
    for site in CartesianIndices(source.ownership)
        owner = @inbounds source.ownership[site]
        owner > 0 || continue
        boundary = Int32(0)
        for direction in 1:count
            neighbor = relation_neighbor_index(
                source.shape,
                source.periodic,
                site,
                source.domain_resources.contact_offsets,
                start + direction - 1,
            )
            neighbor === nothing && continue
            neighbor == site && continue
            duplicate = false
            for prior in 1:(direction - 1)
                prior_neighbor = relation_neighbor_index(
                    source.shape,
                    source.periodic,
                    site,
                    source.domain_resources.contact_offsets,
                    start + prior - 1,
                )
                if prior_neighbor == neighbor
                    duplicate = true
                    break
                end
            end
            duplicate && continue
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
        ::DenseOwnerScalarGroupStorage{T}, values, cell_count
    ) where {T}
    values isa AbstractMatrix{T} && size(values, 1) == cell_count || throw(
        ArgumentError(
            "tracker-group rebuild violates its dense scalar storage contract"
        )
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
                tracker_storage(descriptor),
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

@inline _tracker_state_to_host(to_host, value::AbstractArray) = to_host(value)
@inline _tracker_state_to_host(to_host, value::CellMomentsState) = CellMomentsState(
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
        tracker_storage(descriptor),
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
