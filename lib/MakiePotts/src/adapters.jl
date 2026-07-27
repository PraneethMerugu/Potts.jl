function _render_cells(state)
    return map(CorePotts.active_cell_ids(state)) do id
        identity = CellIdentity(CorePotts.value(id), CorePotts.value(
            CorePotts.generation(state, id)))
        cell_type = CorePotts.value(CorePotts.cell_type(state, id))
        RenderCellMetadata(identity, cell_type)
    end
end

function _render_cells(values::PottsToolkit.OwnershipValues)
    return [begin
        identity = CellIdentity(CorePotts.value(PottsToolkit.observed_cell_id(cell)),
            CorePotts.value(PottsToolkit.observed_cell_generation(cell)))
        RenderCellMetadata(identity,
            CorePotts.value(PottsToolkit.observed_cell_type(cell)))
    end for cell in PottsToolkit.ownership_cells(values)]
end

function _render_owners(state, geometry, cells)
    lookup = Dict(cell.identity.id => cell for cell in cells)
    dims = CorePotts.lattice_size(state)
    owners = Array{RenderOwner}(undef, dims)
    for site in CartesianIndices(owners)
        source_owner = CorePotts.owner_at(state, site)
        immutable = CorePotts.immutable_owner(geometry, site)
        if CorePotts.is_cell_owner(source_owner)
            id = CorePotts.value(CorePotts.cell_id(source_owner))
            haskey(lookup, id) || throw(InvalidRenderFrameError(
                ["finite owner $id has no active generation-aware metadata"]))
            owners[site] = RenderOwner(CellSite, id)
        else
            id = CorePotts.value(CorePotts.medium_id(source_owner))
            owners[site] = RenderOwner(
                immutable === nothing ? MediumSite : ObstacleSite, id)
        end
    end
    return owners
end

function _render_owners(values::PottsToolkit.OwnershipValues, geometry, cells)
    lookup = Dict(cell.identity.id => cell for cell in cells)
    owners = Array{RenderOwner}(undef, PottsToolkit.ownership_size(values))
    for site in CartesianIndices(owners)
        source_owner = PottsToolkit.ownership_owner_at(values, site)
        immutable = CorePotts.immutable_owner(geometry, site)
        if CorePotts.is_cell_owner(source_owner)
            id = CorePotts.value(CorePotts.cell_id(source_owner))
            haskey(lookup, id) || throw(InvalidRenderFrameError(
                ["finite owner $id has no observed generation-aware metadata"]))
            owners[site] = RenderOwner(CellSite, id)
        else
            id = CorePotts.value(CorePotts.medium_id(source_owner))
            owners[site] = RenderOwner(
                immutable === nothing ? MediumSite : ObstacleSite, id)
        end
    end
    return owners
end

function _project_extent(owners::AbstractArray{RenderOwner, N}, spacing,
        extent::FullDomain) where {N}
    geometry = RenderGeometry(size(owners); spacing = spacing)
    return copy(owners), geometry
end

function _project_extent(owners::AbstractArray{RenderOwner, 3}, spacing,
        extent::OrthogonalSlice)
    extent.index <= size(owners, extent.axis) || throw(BoundsError(
        axes(owners, extent.axis), extent.index))
    projected = copy(selectdim(owners, extent.axis, extent.index))
    retained = Tuple(filter(!=(extent.axis), (1, 2, 3)))
    projected_spacing = ntuple(i -> spacing[retained[i]], Val(2))
    geometry = RenderGeometry(size(projected);
        spacing = projected_spacing, source_axes = retained)
    return projected, geometry
end

function _project_extent(owners::AbstractArray{RenderOwner, 2}, spacing,
        ::OrthogonalSlice)
    throw(ArgumentError("OrthogonalSlice is valid only for a three-dimensional source"))
end

function _project_site_values(values::AbstractArray, extent::FullDomain)
    return copy(values)
end

function _project_site_values(values::AbstractArray{T, 3},
        extent::OrthogonalSlice) where {T}
    return copy(selectdim(values, extent.axis, extent.index))
end

function _project_site_values(values::AbstractArray{T, 2},
        ::OrthogonalSlice) where {T}
    throw(ArgumentError("OrthogonalSlice is valid only for a three-dimensional source"))
end

function materialize_channel(state, cells,
        request::CellPropertyRequest{T}) where {T}
    values = Dict{CellIdentity, T}()
    for cell in cells
        id = CorePotts.CellID(cell.identity.id)
        value = CorePotts.property_value(state, request.property, id)
        values[cell.identity] = convert(T, value)
    end
    return RenderChannel(request.key, values;
        label = request.label, units = request.units)
end

function materialize_channel(values::PottsToolkit.OwnershipValues, cells,
        request::AbstractChannelRequest)
    throw(RenderMaterializationError(typeof(values),
        "the retained ownership observable does not include channel $(request.key); " *
        "declare and retain that visualization-neutral observation explicitly"))
end

function materialize_channel(values::PottsToolkit.OwnershipValues, cells,
        request::CellPropertyRequest)
    throw(RenderMaterializationError(typeof(values),
        "the retained ownership observable does not include cell property " *
        "`$(request.property)`; declare and retain that visualization-neutral " *
        "observation explicitly"))
end

function _build_renderframe(source, geometry_source, mcs::Integer,
        request::RenderRequest; source_name::Symbol, source_type,
        residency::Symbol)
    cells = _render_cells(source)
    owners = _render_owners(source, geometry_source, cells)
    spacing = CorePotts.domain_spacing(geometry_source)
    projected_owners, geometry = _project_extent(owners, spacing, request.extent)
    channels = map(request.channels) do requested
        item = materialize_channel(source, cells, requested)
        if item.key isa RenderChannelKey{SiteChannelScope}
            RenderChannel(item.key,
                _project_site_values(item.values, request.extent);
                label = item.label, units = item.units)
        else
            item
        end
    end
    metadata = request.include_cell_metadata ? cells : RenderCellMetadata[]
    any(owner -> owner.kind === CellSite, projected_owners) &&
        isempty(metadata) && throw(ArgumentError(
            "cell metadata cannot be omitted while the requested extent contains finite cells"))
    provenance = RenderProvenance(source_name, source_type, residency, request)
    return PottsRenderFrame(mcs, projected_owners, metadata;
        channels = channels, geometry = geometry, provenance = provenance)
end

"""
    renderframe(state, problem, request=RenderRequest(); mcs=0)

Explicitly materialize a complete host render frame from a logical CorePotts
state. The method copies all published data before returning.
"""
function renderframe(state::CorePotts.LogicalPottsState,
        problem::CorePotts.PottsProblem,
        request::RenderRequest = RenderRequest(); mcs::Integer = 0)
    return _build_renderframe(state, CorePotts.problem_geometry(problem), mcs, request;
        source_name = :logical_state, source_type = typeof(state), residency = :host)
end

function renderframe(saved::CorePotts.SavedPottsState,
        problem::CorePotts.PottsProblem,
        request::RenderRequest = RenderRequest())
    state = try
        CorePotts.snapshot_state(saved)
    catch error
        error isa ArgumentError || rethrow()
        throw(RenderMaterializationError(typeof(saved), sprint(showerror, error)))
    end
    return _build_renderframe(state, CorePotts.problem_geometry(problem),
        CorePotts.snapshot_mcs(saved), request;
        source_name = :saved_state, source_type = typeof(saved),
        residency = CorePotts.snapshot_residency(saved))
end

function renderframe(solution::CorePotts.PottsSolution,
        request::RenderRequest = RenderRequest(); index::Integer = lastindex(solution))
    checkbounds(firstindex(solution):lastindex(solution), index)
    return renderframe(solution[index], CorePotts.solution_problem(solution), request)
end

function renderframe(frame::PottsToolkit.SpatialFrame,
        problem::CorePotts.PottsProblem,
        request::RenderRequest = RenderRequest())
    values = PottsToolkit.spatial_values(frame)
    return _build_renderframe(values, CorePotts.problem_geometry(problem),
        PottsToolkit.spatial_mcs(frame), request;
        source_name = :ownership_observation, source_type = typeof(values),
        residency = :observable)
end

function renderframe(values::PottsToolkit.OwnershipValues,
        problem::CorePotts.PottsProblem,
        request::RenderRequest = RenderRequest(); mcs::Integer = 0)
    return _build_renderframe(values, CorePotts.problem_geometry(problem), mcs, request;
        source_name = :ownership_observation, source_type = typeof(values),
        residency = :observable)
end

"""Eagerly materialize independently valid frames from a retained solution."""
function renderframes(solution::CorePotts.PottsSolution,
        request::RenderRequest = RenderRequest())
    return [renderframe(solution, request; index)
            for index in firstindex(solution):lastindex(solution)]
end

function renderframes(series::PottsToolkit.SpatialSeries,
        problem::CorePotts.PottsProblem,
        request::RenderRequest = RenderRequest())
    return [renderframe(frame, problem, request) for frame in series]
end
