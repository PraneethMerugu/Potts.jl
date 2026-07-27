function _site_index(frame::AbstractPottsRenderFrame{2}, index)
    index isa CartesianIndex && return index
    index isa Tuple && length(index) >= 2 &&
        return CartesianIndex(Int(index[1]), Int(index[2]))
    index isa Integer && return CartesianIndices(frame_size(frame))[index]
    throw(ArgumentError("unsupported image inspection index $index"))
end

function _owner_label(frame, owner::RenderOwner)
    if owner.kind === CellSite
        metadata = cell_metadata(frame, owner)
        return "Cell $(metadata.identity.id)\nGeneration $(metadata.identity.generation)\n" *
               "Cell type $(metadata.cell_type)"
    elseif owner.kind === ObstacleSite
        return "Obstacle medium $(owner.id)"
    else
        return "Medium $(owner.id)"
    end
end

"""
Return the semantic DataInspector label for one rendered site.
"""
function inspection_label(frame::AbstractPottsRenderFrame{2},
        encoding::AbstractPottsEncoding, index)
    site = _site_index(frame, index)
    owner = owner_at(frame, site)
    source_axes = frame_geometry(frame).source_axes
    coordinates = Tuple(site)
    base = "Site $(coordinates) · source axes $(source_axes)\n" *
           _owner_label(frame, owner)
    encoded = encode(frame, encoding)
    if encoding_kind(encoded.encoding) === ContinuousEncoding
        value = encoded.values[site]
        suffix = isfinite(value) ? string(value) : "missing"
        units = encoded.units === nothing ? "" : " $(encoded.units)"
        return "$base\n$(encoded.label): $suffix$units"
    end
    return base
end
