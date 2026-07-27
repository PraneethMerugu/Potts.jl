PrecompileTools.@setup_workload begin
    owners = fill(RenderOwner(MediumSite, 1), 4, 4)
    owners[2:3, 2:3] .= Ref(RenderOwner(CellSite, 1))
    cell = RenderCellMetadata(CellIdentity(1, 0), 1)
    key = CellChannelKey(:precompile_value, Float64)
    values = Dict(cell.identity => 0.5)
    frame = PottsRenderFrame(0, owners, [cell];
        channels = (RenderChannel(key, values),))

    PrecompileTools.@compile_workload begin
        encode(frame, CellTypeEncoding())
        encode(frame, CellIdentityEncoding())
        encode(frame, ChannelEncoding(key))
        _boundary_segments(frame)
        inspection_label(frame, CellTypeEncoding(), CartesianIndex(2, 2))
        render_frame_conformance(frame)
    end
end
