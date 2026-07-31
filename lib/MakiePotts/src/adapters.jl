function _render_cells(state::PottsToolkit.PottsSavedState)
    return [
        RenderCellMetadata(
            CellIdentity(id, Int(state.cell_generations[id])),
            Int(state.cell_kinds[id]),
        )
        for id in eachindex(state.cell_kinds)
        if state.volumes[id] > 0
    ]
end

function _render_owners(state::PottsToolkit.PottsSavedState, cells)
    active = Set(cell.identity.id for cell in cells)
    owners = Array{RenderOwner}(undef, size(state.ownership))
    for site in CartesianIndices(owners)
        id = Int(state.ownership[site])
        if id == 0
            owners[site] = RenderOwner(MediumSite, 1)
        else
            id in active || throw(InvalidRenderFrameError(
                ["finite owner $id has no active metadata"]
            ))
            owners[site] = RenderOwner(CellSite, id)
        end
    end
    return owners
end

function _project_extent(
        owners::AbstractArray{RenderOwner, N}, spacing, ::FullDomain
    ) where {N}
    return copy(owners), RenderGeometry(size(owners); spacing)
end

function _project_extent(
        owners::AbstractArray{RenderOwner, 3},
        spacing,
        extent::OrthogonalSlice,
    )
    extent.index <= size(owners, extent.axis) ||
        throw(BoundsError(axes(owners, extent.axis), extent.index))
    projected = copy(selectdim(owners, extent.axis, extent.index))
    retained = Tuple(filter(!=(extent.axis), (1, 2, 3)))
    projected_spacing = ntuple(i -> spacing[retained[i]], Val(2))
    return projected, RenderGeometry(
        size(projected);
        spacing = projected_spacing,
        source_axes = retained,
    )
end

function _project_extent(
        ::AbstractArray{RenderOwner, 2}, spacing, ::OrthogonalSlice
    )
    throw(ArgumentError(
        "OrthogonalSlice is valid only for a three-dimensional source"
    ))
end

function materialize_channel(
        ::PottsToolkit.PottsSavedState,
        cells,
        request::AbstractChannelRequest,
    )
    throw(RenderMaterializationError(
        PottsToolkit.PottsSavedState,
        "saved V1 state does not contain channel $(request.key); request a " *
        "declared visualization-neutral observation when solving",
    ))
end

function _build_renderframe(
        state::PottsToolkit.PottsSavedState,
        request::RenderRequest,
    )
    cells = _render_cells(state)
    owners = _render_owners(state, cells)
    spacing = ntuple(_ -> 1.0, ndims(owners))
    projected_owners, geometry =
        _project_extent(owners, spacing, request.extent)
    isempty(request.channels) || throw(RenderMaterializationError(
        typeof(state),
        "V1 saved-state channels must be explicitly materialized before rendering",
    ))
    metadata = request.include_cell_metadata ? cells : RenderCellMetadata[]
    any(owner -> owner.kind === CellSite, projected_owners) &&
        isempty(metadata) && throw(ArgumentError(
            "cell metadata cannot be omitted while the requested extent contains cells"
        ))
    provenance = RenderProvenance(
        :saved_state, typeof(state), :host, request
    )
    return PottsRenderFrame(
        state.mcs,
        projected_owners,
        metadata;
        geometry,
        provenance,
    )
end

"""
    renderframe(state::PottsSavedState, request=RenderRequest())

Defensively materialize one native Makie frame from an immutable V1 saved
boundary.
"""
renderframe(
    state::PottsToolkit.PottsSavedState,
    request::RenderRequest = RenderRequest(),
) = _build_renderframe(state, request)

function renderframe(
        solution::PottsToolkit.PottsSolution,
        request::RenderRequest = RenderRequest();
        index::Integer = lastindex(solution),
    )
    checkbounds(firstindex(solution):lastindex(solution), index)
    return renderframe(solution[index], request)
end

"""Eagerly materialize independent frames from a retained V1 solution."""
function renderframes(
        solution::PottsToolkit.PottsSolution,
        request::RenderRequest = RenderRequest(),
    )
    return [
        renderframe(solution, request; index)
        for index in firstindex(solution):lastindex(solution)
    ]
end
