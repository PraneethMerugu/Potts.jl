# PIFF (CompuCell3D's Potts Initial File Format, ROADMAP M4.4): one line per box of sites,
#     cell_id  cell_type  x_low x_high  y_low y_high  z_low z_high
# with 0-based inclusive coordinates (z is 0 in 2D). The medium may be listed (type `Medium`)
# or left implicit. Cell ids are arbitrary integers; a cell may span several lines.

"""
    read_piff(io_or_path, dims; medium = "Medium") -> (labels, kinds, ids)

Labels (`Int32`, 1-based, `0` = medium) over a lattice of size `dims` from a PIFF file,
the kind name of each labelled cell and its PIFF cell id. Cells are numbered in order of
first appearance. Boxes outside the lattice, overlapping cells, or a cell listed with two
types are errors.
"""
read_piff(path::AbstractString, dims; kw...) = open(io -> read_piff(io, dims; kw...), path)

function read_piff(io::IO, dims::NTuple{N, Integer}; medium::AbstractString = "Medium") where {N}
    N in (2, 3) || throw(ArgumentError("PIFF describes 2D or 3D lattices"))
    labels = zeros(Int32, dims)
    kinds = String[]
    ids = Int[]
    index = Dict{Int, Int32}()
    for (lineno, line) in enumerate(eachline(io))
        s = strip(line)
        (isempty(s) || startswith(s, '#')) && continue
        f = split(s)
        length(f) == 8 || throw(ArgumentError("PIFF line $lineno: expected 8 fields, got $(length(f))"))
        id = parse(Int, f[1])
        kind = String(f[2])
        lo = ntuple(d -> parse(Int, f[1 + 2d]) + 1, 3)
        hi = ntuple(d -> parse(Int, f[2 + 2d]) + 1, 3)
        N == 2 && (lo[3] == hi[3] == 1 || throw(ArgumentError("PIFF line $lineno: z must be 0 on a 2D lattice")))
        for d in 1:N
            1 <= lo[d] <= hi[d] <= dims[d] ||
                throw(ArgumentError("PIFF line $lineno: box $(lo[d] - 1):$(hi[d] - 1) on axis $d is outside the lattice (size $(dims[d]))"))
        end
        box = CartesianIndices(ntuple(d -> lo[d]:hi[d], N))
        if kind == medium
            any(!=(0), view(labels, box)) && throw(ArgumentError("PIFF line $lineno: medium box overlaps a cell"))
            continue
        end
        c = get!(index, id) do
            push!(kinds, kind)
            push!(ids, id)
            Int32(length(kinds))
        end
        kinds[c] == kind || throw(ArgumentError("PIFF line $lineno: cell $id listed as both `$(kinds[c])` and `$kind`"))
        for x in box
            labels[x] in (0, c) || throw(ArgumentError("PIFF line $lineno: cell $id overlaps cell $(ids[labels[x]])"))
            labels[x] = c
        end
    end
    return labels, kinds, ids
end

"""
    write_piff(io_or_path, labels, kinds; medium = nothing, ids = 1:length(kinds))

Write a labelling as PIFF: one line per run of sites along the first axis. `kinds[c]` is the
type name of cell `c` (a name, or anything `string` accepts). With `medium` set to a type
name, medium sites are written too.
"""
write_piff(path::AbstractString, labels, kinds; kw...) = open(io -> write_piff(io, labels, kinds; kw...), path, "w")

function write_piff(io::IO, labels::AbstractArray{<:Integer, N}, kinds; medium = nothing,
        ids = 1:length(kinds)) where {N}
    N in (2, 3) || throw(ArgumentError("PIFF describes 2D or 3D lattices"))
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
                println(io, id, ' ', name, ' ', x - 1, ' ', e - 1, ' ', y, ' ', y, ' ', z, ' ', z)
            end
            x = e + 1
        end
    end
    return nothing
end
