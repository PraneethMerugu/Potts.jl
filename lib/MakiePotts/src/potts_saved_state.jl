function _render_cells(state::CorePotts.CPMState)
    kinds, generations, vols = CorePotts.cell_kinds(state), CorePotts.cell_generations(state),
    CorePotts.volumes(state)
    return [
        RenderCellMetadata(RenderCellIdentity(id, Int(generations[id])), Int(kinds[id]))
        for id in eachindex(kinds) if vols[id] > 0
    ]
end

function _render_owners(state::CorePotts.CPMState, cells, frozen)
    active = Set(cell.identity.id for cell in cells)
    σ = CorePotts.ownership(state)
    owners = Array{RenderOwner}(undef, size(σ))
    for site in CartesianIndices(owners)
        id = Int(σ[site])
        if id == 0
            owners[site] = RenderOwner(frozen !== nothing && frozen[site] ? ObstacleSite : MediumSite, 1)
        else
            id in active || throw(InvalidRenderFrameError(
                ["finite owner $id has no active metadata"]
            ))
            owners[site] = RenderOwner(CellSite, id)
        end
    end
    return owners
end

_project_spatial_array(values::AbstractArray, ::FullDomain) = values

function _project_spatial_array(
        values::AbstractArray{T, 3}, extent::OrthogonalSlice
    ) where {T}
    extent.index <= size(values, extent.axis) ||
        throw(BoundsError(axes(values, extent.axis), extent.index))
    return selectdim(values, extent.axis, extent.index)
end

function _project_spatial_array(
        ::AbstractArray{T, 2}, ::OrthogonalSlice
    ) where {T}
    throw(ArgumentError(
        "OrthogonalSlice is valid only for a three-dimensional source"
    ))
end

function _project_extent(
        owners::AbstractArray{RenderOwner, N}, spacing, extent::FullDomain
    ) where {N}
    projected = copy(_project_spatial_array(owners, extent))
    return projected, RenderGeometry(size(projected); spacing)
end

function _project_extent(
        owners::AbstractArray{RenderOwner, 3},
        spacing,
        extent::OrthogonalSlice,
    )
    projected = copy(_project_spatial_array(owners, extent))
    retained = Tuple(filter(!=(extent.axis), (1, 2, 3)))
    projected_spacing = ntuple(i -> spacing[retained[i]], Val(2))
    return projected, RenderGeometry(
        size(projected);
        spacing = projected_spacing,
        source_axes = retained,
    )
end

function _project_extent(
        owners::AbstractArray{RenderOwner, 2}, spacing, extent::OrthogonalSlice
    )
    _project_spatial_array(owners, extent)
end

function _project_saved_state_channels(
        channels::Tuple,
        source_size::Tuple,
        extent::AbstractRenderExtent,
    )
    all(item -> item isa RenderChannel, channels) ||
        throw(InvalidRenderFrameError(
            ["saved-state channels must be an ordered tuple of RenderChannel values"]
        ))
    return map(channels) do item
        item.key isa RenderChannelKey{SiteChannelScope} || return item
        item.values isa AbstractArray || return item
        size(item.values) == source_size ||
            throw(InvalidRenderFrameError([
                "saved-state site-channel size must equal the full saved domain; " *
                "expected $source_size, got $(size(item.values))",
            ]))
        values = _project_spatial_array(item.values, extent)
        RenderChannel(item.key, values; label = item.label, units = item.units)
    end
end

function _build_renderframe(
        state::CorePotts.CPMState,
        request::RenderRequest,
        channels::Tuple,
        mcs::Integer,
        frozen,
        spacing,
    )
    cells = _render_cells(state)
    owners = _render_owners(state, cells, frozen)
    spacing = spacing === nothing ? ntuple(_ -> 1.0, ndims(owners)) : Float64.(Tuple(spacing))
    projected_owners, geometry =
        _project_extent(owners, spacing, request.extent)
    metadata = request.include_cell_metadata ? cells : RenderCellMetadata[]
    any(owner -> owner.kind === CellSite, projected_owners) &&
        isempty(metadata) && throw(ArgumentError(
            "cell metadata cannot be omitted while the requested extent contains cells"
        ))
    provenance = RenderProvenance(
        :saved_state, typeof(state), :host, request
    )
    projected_channels = _project_saved_state_channels(
        channels, size(owners), request.extent)
    return PottsRenderFrame(
        Int(mcs),
        projected_owners,
        metadata;
        channels = projected_channels,
        geometry,
        provenance,
    )
end

"""
    renderframe(state::CPMState, request=RenderRequest(); mcs=0, channels=(), frozen=nothing, spacing=nothing)

Defensively materialize one native Makie frame from a saved host state (a
`CorePotts.CPMState` snapshot). Site-channel arrays describe the full saved domain and use
the same full-domain or orthogonal-slice projection as ownership. Cell and medium
channels retain their identity-keyed representation. Frozen medium sites render as
obstacles.
"""
function renderframe(
        state::CorePotts.CPMState,
        request::RenderRequest = RenderRequest();
        mcs::Integer = 0,
        channels::Tuple = (),
        frozen = nothing,
        spacing = nothing,
    )
    return _build_renderframe(state, request, channels, mcs, frozen, spacing)
end

function renderframe(
        solution::CorePotts.PottsSolution,
        request::RenderRequest = RenderRequest();
        index::Integer = lastindex(solution.u),
        channels::Tuple = (),
    )
    checkbounds(solution.u, index)
    return renderframe(solution.u[index], request; mcs = solution.t[index], channels,
        # the saved state's own obstacles: a frozen mask that follows the state (D-081) differs
        # from the problem's t0 mask once a cell enters or leaves a frozen kind
        frozen = CorePotts.frozen_sites(solution.prob, solution.u[index]), spacing = solution.prob.spacing)
end

"""Eagerly materialize independent frames from a retained solution."""
function renderframes(
        solution::CorePotts.PottsSolution,
        request::RenderRequest = RenderRequest(),
    )
    return [renderframe(solution, request; index) for index in eachindex(solution.u)]
end
