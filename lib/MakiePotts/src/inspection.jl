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
        return "Cell $(metadata.identity.id)\n" *
            "Generation $(metadata.identity.generation)\n" *
            "Cell type $(metadata.cell_type)"
    elseif owner.kind === ObstacleSite
        return "Obstacle medium $(owner.id)"
    else
        return "Medium $(owner.id)"
    end
end

"""
    inspection_label(frame, encoding, index) -> String

Return the `DataInspector` text of one site of a 2D render frame.

The text gives the site, the frame's source axes and the owner: number, generation and
kind of a cell, or the medium number (marked as an obstacle when it is one). A
continuous encoding adds its title, the value (or `"missing"`) and the units.

# Arguments

  - `frame::AbstractPottsRenderFrame{2}`: the frame.
  - `encoding::AbstractPottsEncoding`: the encoding.
  - `index`: the site, a `CartesianIndex`, a tuple of at least two integers or a linear
    index. Throws an `ArgumentError` otherwise.

# Returns

  - `String`: the text.

# Examples

```jldoctest
julia> using MakiePotts

julia> m = RenderOwner(MediumSite, 1);

julia> frame = PottsRenderFrame(0, [m m; m m], RenderCellMetadata[]);

julia> print(inspection_label(frame, CellTypeEncoding(), (1, 2)))
Site (1, 2) · source axes (1, 2)
Medium 1
```

See also [`pottsplot`](@ref).
"""
function inspection_label(
        frame::AbstractPottsRenderFrame{2},
        encoding::AbstractPottsEncoding, index
    )
    site = _site_index(frame, index)
    owner = owner_at(frame, site)
    source_axes = frame_geometry(frame).source_axes
    coordinates = Tuple(site)
    base = "Site $(coordinates) · source axes $(source_axes)\n" *
        _owner_label(frame, owner)
    encoded = encode_frame(frame, encoding)
    if encoding_kind(encoded.encoding) === ContinuousEncoding
        value = encoded.values[site]
        suffix = isfinite(value) ? string(value) : "missing"
        units = encoded.units === nothing ? "" : " $(encoded.units)"
        return "$base\n$(encoded.label): $suffix$units"
    end
    return base
end
