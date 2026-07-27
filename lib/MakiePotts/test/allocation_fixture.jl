function allocation_frame(dims = (256, 256); cell_width = 16)
    owners = Array{RenderOwner}(undef, dims)
    cells_per_row = cld(dims[1], cell_width)
    cells = RenderCellMetadata[]
    seen = Set{UInt32}()
    for site in CartesianIndices(owners)
        x, y = Tuple(site)
        id = UInt32((x - 1) ÷ cell_width +
                    ((y - 1) ÷ cell_width) * cells_per_row + 1)
        owners[site] = RenderOwner(CellSite, id)
        id in seen && continue
        push!(seen, id)
        push!(cells, RenderCellMetadata(CellIdentity(id, 0), mod1(id, 6)))
    end
    return PottsRenderFrame(0, owners, cells)
end

function _minimum_allocated(operation; samples = 3)
    operation()
    GC.gc()
    return minimum(@allocated(operation()) for _ in 1:samples)
end

function allocation_measurements(frame = allocation_frame())
    return (
        cell_type = _minimum_allocated(
            () -> encode(frame, CellTypeEncoding())),
        identity = _minimum_allocated(
            () -> encode(frame, CellIdentityEncoding())),
        boundaries = _minimum_allocated(
            () -> MakiePotts._boundary_segments(frame)),
        conformance = _minimum_allocated(
            () -> render_frame_conformance(frame)),
    )
end
