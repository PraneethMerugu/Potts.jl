# Layouts (ROADMAP P6.1a, review §3 R2): host-side initial conditions composed from layers
# and returned as an SII operating point `[ownership => σ, kind => kinds]`.
#
# Every layout is a subtype of `AbstractLayout` with one method,
# `paint!(σ, kinds, l, dims)`: it writes new cell ids `length(kinds) + 1, …` into `σ` (an
# `Int32` array of size `dims`, 0 = medium) and pushes their kinds. Randomized layouts own
# their seed, so adding a layer never changes another layer's draws. Coordinates are lattice
# indices: axial `(q, r)` on a hexagonal lattice, where a box is a rhombus.

"""
    AbstractLayout

A layer of an initial condition. A new layout is a subtype with one method,
`paint!(σ, kinds, l, dims)`, that paints new cells over `σ` and pushes their kinds. Turn
layouts into an operating point with [`layout`](@ref); compose them with [`overlay`](@ref).
"""
abstract type AbstractLayout end

_tuple(x::Integer, N) = ntuple(_ -> Int(x), N)
_tuple(x, N) = (length(x) == N || throw(ArgumentError("expected $N values, got $(length(x))")); Int.(Tuple(x)))

function _check_size(sz, what)
    all(>(0), sz) || throw(ArgumentError("$what: box size must be positive, got $sz"))
    return sz
end

function _region_arg(region, N, what)
    region === nothing && return nothing
    length(region) == N ||
        throw(ArgumentError("$what: region has $(length(region)) ranges, the box is $(N)D"))
    r = map(x -> (x isa AbstractUnitRange ? UnitRange{Int}(x) :
                  throw(ArgumentError("$what: region ranges must be unit ranges, got $x"))), Tuple(region))
    any(isempty, r) && throw(ArgumentError("$what: region $r is empty"))
    return r
end

function _kinds_arg(kinds, what)
    k = collect(kinds)
    isempty(k) && throw(ArgumentError("$what: `kinds` is empty"))
    return k
end

# The region of a layer on a lattice of size `dims` (default: the whole lattice).
function _region(region, dims::NTuple{N, Int}, what) where {N}
    region === nothing && return map(d -> 1:d, dims)
    length(region) == N ||
        throw(ArgumentError("$what: region $region is $(length(region))D, the lattice $(N)D"))
    for d in 1:N
        (first(region[d]) >= 1 && last(region[d]) <= dims[d]) ||
            throw(ArgumentError("$what: region $region lies outside the lattice $dims"))
    end
    return region
end

function _check_rank(l, N, dims, what)
    N == length(dims) || throw(ArgumentError("$what: the layout is $(N)D, the lattice $(length(dims))D"))
end

_paint_box!(σ, id, lo, sz) = (σ[CartesianIndices(map((o, s) -> o:(o + s - 1), lo, sz))] .= id)

"""
    Tiling(size; spacing = 0, region = <whole lattice>, kinds)

Boxes of `size` (a tuple, one entry per axis), `spacing` medium sites apart (an integer or
a tuple), filling `region` (a tuple of ranges) in column-major order from its lower corner.
Only whole boxes are placed. `kinds` is cycled over the cells in placement order.
"""
struct Tiling{N, K} <: AbstractLayout
    size::NTuple{N, Int}
    spacing::NTuple{N, Int}
    region::Union{Nothing, NTuple{N, UnitRange{Int}}}
    kinds::Vector{K}
end
function Tiling(size; spacing = 0, region = nothing, kinds)
    N = length(size)
    sz = _check_size(_tuple(size, N), "Tiling")
    sp = _tuple(spacing, N)
    all(>=(0), sp) || throw(ArgumentError("Tiling: spacing must be non-negative, got $sp"))
    return Tiling(sz, sp, _region_arg(region, N, "Tiling"), _kinds_arg(kinds, "Tiling"))
end

function paint!(σ, kinds, l::Tiling{N}, dims) where {N}
    _check_rank(l, N, dims, "Tiling")
    reg = _region(l.region, dims, "Tiling")
    starts = map((r, s, p) -> first(r):(s + p):(last(r) - s + 1), reg, l.size, l.spacing)
    any(isempty, starts) &&
        throw(ArgumentError("Tiling: no box of size $(l.size) fits the region $reg"))
    n = 0
    for o in Iterators.product(starts...)
        n += 1
        push!(kinds, l.kinds[mod1(n, length(l.kinds))])
        _paint_box!(σ, Int32(length(kinds)), o, l.size)
    end
    return σ
end

"""
    Scattered(n, size; region = <whole lattice>, kinds, seed, gap = 1)

`n` boxes of `size` at uniformly random positions inside `region`, at least `gap` medium
sites apart along some axis (with `gap = 1` no two cells touch, Moore neighbourhood
included). Placement is by rejection with a `StableRNG(seed)`, so it is deterministic in
`seed` across Julia versions. `kinds` is cycled over the cells. Throws an `ArgumentError`
when the boxes cannot be placed.
"""
struct Scattered{N, K} <: AbstractLayout
    n::Int
    size::NTuple{N, Int}
    region::Union{Nothing, NTuple{N, UnitRange{Int}}}
    kinds::Vector{K}
    seed::Int
    gap::Int
end
function Scattered(n::Integer, size; region = nothing, kinds, seed::Integer, gap::Integer = 1)
    N = length(size)
    n >= 0 || throw(ArgumentError("Scattered: the number of boxes must be non-negative, got $n"))
    gap >= 0 || throw(ArgumentError("Scattered: gap must be non-negative, got $gap"))
    sz = _check_size(_tuple(size, N), "Scattered")
    return Scattered(Int(n), sz, _region_arg(region, N, "Scattered"), _kinds_arg(kinds, "Scattered"), Int(seed), Int(gap))
end

const _SCATTER_ATTEMPTS = 10_000   # rejection draws per box before giving up

# Boxes at lower corners `a` and `b` are at least `gap` sites apart along some axis.
_apart(a, b, sz, gap) = any(ntuple(d -> a[d] + sz[d] + gap <= b[d] || b[d] + sz[d] + gap <= a[d], length(a)))

function paint!(σ, kinds, l::Scattered{N}, dims) where {N}
    _check_rank(l, N, dims, "Scattered")
    reg = _region(l.region, dims, "Scattered")
    ext = map(length, reg)
    all(map(>=, ext, l.size)) || throw(ArgumentError("Scattered: boxes of size $(l.size) do not fit the region $reg"))
    # necessary: the boxes grown by `gap` on their upper sides are disjoint in the region
    # grown by `gap`
    prod(ext .+ l.gap) >= l.n * prod(l.size .+ l.gap) ||
        throw(ArgumentError("Scattered: $(l.n) boxes of size $(l.size) with gap $(l.gap) cannot fit the region $reg"))
    rng = StableRNG(l.seed)
    ranges = map((r, s) -> first(r):(last(r) - s + 1), reg, l.size)
    corners = NTuple{N, Int}[]
    for k in 1:(l.n)
        placed = false
        for _ in 1:_SCATTER_ATTEMPTS
            o = map(r -> rand(rng, r), ranges)
            if all(c -> _apart(o, c, l.size, l.gap), corners)
                push!(corners, o)
                placed = true
                break
            end
        end
        placed || throw(ArgumentError("Scattered: could not place box $k of $(l.n) (size $(l.size), gap $(l.gap)) " *
                                      "in the region $reg after $_SCATTER_ATTEMPTS draws; use fewer or smaller boxes"))
    end
    for (k, o) in enumerate(corners)
        push!(kinds, l.kinds[mod1(k, length(l.kinds))])
        _paint_box!(σ, Int32(length(kinds)), o, l.size)
    end
    return σ
end

"""
    Frame(kind; width = 1)

One cell of `kind` owning every site within `width` of the lattice edge (a wall; pair it
with a `[frozen]` kind).
"""
struct Frame{K} <: AbstractLayout
    kind::K
    width::Int
end
function Frame(kind; width::Integer = 1)
    width >= 1 || throw(ArgumentError("Frame: width must be at least 1, got $width"))
    return Frame(kind, Int(width))
end

function paint!(σ, kinds, l::Frame, dims)
    push!(kinds, l.kind)
    id, w = Int32(length(kinds)), l.width
    for i in CartesianIndices(σ)
        any(ntuple(d -> i[d] <= w || i[d] > dims[d] - w, length(dims))) && (σ[i] = id)
    end
    return σ
end

"""
    overlay(layers...)

Layers painted in order: later layers overwrite earlier ones, and cell ids follow layer
order. Cells left with no site are dropped (ids stay consecutive); a partly covered cell
keeps its remaining sites.
"""
struct Overlay <: AbstractLayout
    layers::Vector{AbstractLayout}
end
function overlay(layers::AbstractLayout...)
    flat = AbstractLayout[]
    for l in layers
        l isa Overlay ? append!(flat, l.layers) : push!(flat, l)
    end
    return Overlay(flat)
end

function paint!(σ, kinds, l::Overlay, dims)
    for x in l.layers
        paint!(σ, kinds, x, dims)
    end
    return σ
end

"""
    layout(l, dims) -> [ownership => σ, kind => kinds]

Paint the layout `l` (see [`overlay`](@ref)) on an empty lattice and return an operating
point for [`PottsProblem`](@ref): `σ` is an `Int32` array (0 = medium). In place of `dims`
pass a `Lattice`, a `PottsSystem` or a `CompiledPottsSystem`; on a lattice with a domain,
no cell may cover a site outside it.
"""
layout(l::AbstractLayout, dims::Tuple{Vararg{Integer}}) = _layout(l, Int.(dims), nothing)
layout(l::AbstractLayout, lat::Lattice) = _layout(l, lat.dims, lat.mask)
layout(l::AbstractLayout, lat::LatticeSpec) = _layout(l, lat.dims, lat.domain)
layout(l::AbstractLayout, sys::PottsSystem) = layout(l, sys.lattice)
layout(l::AbstractLayout, sys::CompiledPottsSystem) = layout(l, sys.sys)

function _layout(l, dims::NTuple{N, Int}, mask) where {N}
    all(>(0), dims) || throw(ArgumentError("layout: lattice dimensions must be positive, got $dims"))
    σ = zeros(Int32, dims)
    kinds = Any[]
    paint!(σ, kinds, l, dims)
    σ, kinds = _compact(σ, kinds)
    if mask !== nothing
        bad = findfirst(i -> σ[i] != 0 && !mask[i], CartesianIndices(σ))
        bad === nothing ||
            throw(ArgumentError("layout: cell $(σ[bad]) covers site $(Tuple(bad)), outside the lattice domain"))
    end
    return [ownership => σ, kind => identity.(kinds)]
end

# Drop cells with no site left and renumber the rest in order.
function _compact(σ, kinds)
    counts = zeros(Int, length(kinds))
    for s in σ
        s > 0 && (counts[s] += 1)
    end
    all(>(0), counts) && return σ, kinds
    new = Int32.(cumsum(counts .> 0))
    for i in eachindex(σ)
        σ[i] > 0 && (σ[i] = new[σ[i]])
    end
    return σ, kinds[counts .> 0]
end
