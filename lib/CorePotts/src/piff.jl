# PIFF (CompuCell3D's Potts Initial File Format): one line per box of sites,
#     cell_id  cell_type  x_low x_high  y_low y_high  z_low z_high
# with 0-based inclusive coordinates (z is 0 in 2D). The medium may be listed (type
# `Medium`) or left implicit. Cell ids are arbitrary integers; a cell may span several
# lines.

"""
    read_piff(io_or_path, dims; medium = "Medium") -> (labels, kinds, ids)

Read a lattice from a PIFF file, CompuCell3D's Potts Initial File Format.

Each line is `cell_id cell_type x_low x_high y_low y_high z_low z_high`, a box of sites
with 0-based inclusive coordinates (`z` is 0 in 2D). Empty lines and lines starting with
`#` are skipped. A cell may span several lines, and its cell number is its order of first
appearance. The medium may be listed or left implicit. A box outside the lattice,
overlapping cells or a cell listed with two types throws an `ArgumentError`.

# Arguments
- `io_or_path`: an `IO`, or the path of the file.
- `dims::NTuple{N, Integer}`: the lattice size, 2D or 3D.

# Keywords
- `medium::AbstractString = "Medium"`: the type name of medium boxes.

# Returns
- `labels::Array{Int32, N}`: the cell number of every site (`0` = medium).
- `kinds::Vector{String}`: the type name of each cell.
- `ids::Vector{Int}`: the PIFF cell id of each cell.

# Examples
```jldoctest
julia> using CorePotts

julia> io = IOBuffer("7 A 0 1 0 0 0 0\\n9 B 1 1 1 1 0 0\\n");

julia> read_piff(io, (2, 2))
(Int32[1 0; 1 2], ["A", "B"], [7, 9])
```

See also [`write_piff`](@ref), [`initial_state`](@ref).
"""
read_piff(path::AbstractString, dims; kw...) = open(io -> read_piff(io, dims; kw...), path)

function read_piff(
        io::IO, dims::NTuple{N, Integer};
        medium::AbstractString = "Medium"
    ) where {N}
    N in (2, 3) ||
        throw(ArgumentError("PIFF describes 2D or 3D lattices, got $(N)D dims $dims; pass \
            a 2-tuple or 3-tuple for dims"))
    labels = zeros(Int32, dims)
    kinds = String[]
    ids = Int[]
    index = Dict{Int, Int32}()
    for (lineno, line) in enumerate(eachline(io))
        s = strip(line)
        (isempty(s) || startswith(s, '#')) && continue
        f = split(s)
        length(f) == 8 ||
            throw(ArgumentError("PIFF line $lineno: expected 8 fields, got $(length(f))"))
        id = parse(Int, f[1])
        kind = String(f[2])
        lo = ntuple(d -> parse(Int, f[1 + 2d]) + 1, 3)
        hi = ntuple(d -> parse(Int, f[2 + 2d]) + 1, 3)
        N == 2 && (
            lo[3] == hi[3] == 1 ||
                throw(ArgumentError("PIFF line $lineno: z must be 0 on a 2D lattice"))
        )
        for d in 1:N
            1 <= lo[d] <= hi[d] <= dims[d] ||
                throw(ArgumentError("PIFF line $lineno: box $(lo[d] - 1):$(hi[d] - 1) on \
                    axis $d is outside the lattice (size $(dims[d]))"))
        end
        box = CartesianIndices(ntuple(d -> lo[d]:hi[d], N))
        if kind == medium
            any(!=(0), view(labels, box)) &&
                throw(ArgumentError("PIFF line $lineno: medium box overlaps a cell"))
            continue
        end
        c = get!(index, id) do
            push!(kinds, kind)
            push!(ids, id)
            Int32(length(kinds))
        end
        kinds[c] == kind ||
            throw(ArgumentError("PIFF line $lineno: cell $id listed as both `$(kinds[c])` \
                and `$kind`"))
        for x in box
            labels[x] in (0, c) ||
                throw(ArgumentError("PIFF line $lineno: cell $id overlaps \
                    cell $(ids[labels[x]])"))
            labels[x] = c
        end
    end
    return labels, kinds, ids
end

"""
    write_piff(io_or_path, labels, kinds; medium = nothing, ids = 1:length(kinds))

Write a lattice as PIFF, one line per run of sites of one cell along the first axis.

# Arguments
- `io_or_path`: an `IO`, or the path of the file (overwritten).
- `labels::AbstractArray{<:Integer}`: the cell number of every site, 2D or 3D (`0` =
  medium).
- `kinds`: the type name of each cell: `kinds[c]` for cell `c`, a string or anything that
  `string` accepts.

# Keywords
- `medium = nothing`: the type name for medium sites. With `nothing`, medium sites are not
  written.
- `ids = 1:length(kinds)`: the PIFF cell id of each cell.

# Returns
- `nothing`.

# Examples
```jldoctest
julia> using CorePotts

julia> io = IOBuffer(); write_piff(io, Int32[1 1; 0 2], ["A", "B"]);

julia> print(String(take!(io)))
1 A 0 0 0 0 0 0
1 A 0 0 1 1 0 0
2 B 1 1 1 1 0 0
```

See also [`read_piff`](@ref).
"""
function write_piff(path::AbstractString, labels, kinds; kw...)
    return open(io -> write_piff(io, labels, kinds; kw...), path, "w")
end

function write_piff(
        io::IO, labels::AbstractArray{<:Integer, N}, kinds; medium = nothing,
        ids = 1:length(kinds)
    ) where {N}
    N in (2, 3) ||
        throw(ArgumentError("PIFF describes 2D or 3D lattices, got a $(N)D labels array; \
            pass a 2D or 3D array"))
    dims = size(labels)
    for rest in CartesianIndices(dims[2:end])
        x = 1
        while x <= dims[1]
            c = labels[x, rest]
            e = x
            while e < dims[1] && labels[e + 1, rest] == c
                e += 1
            end
            if c != 0 || medium !== nothing
                name = c == 0 ? string(medium) : string(kinds[c])
                id = c == 0 ? 0 : ids[c]
                y = rest[1] - 1
                z = N == 3 ? rest[2] - 1 : 0
                println(
                    io, id, ' ', name, ' ', x - 1, ' ',
                    e - 1, ' ', y, ' ', y, ' ', z, ' ', z
                )
            end
            x = e + 1
        end
    end
    return nothing
end
