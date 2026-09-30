# Layouts (ROADMAP P6.1a, review §3 R2): host-side initial conditions composed from layers
# and returned as an SII operating point `[ownership => σ, kind => kinds]`.
#
# Every layout is a subtype of `AbstractLayout` with one method,
# `paint!(σ, kinds, l, lat::LatticeSpec)`: it writes new cell ids `length(kinds) + 1, …` into
# `σ` (an `Int32` array of size `lat.dims`, 0 = medium) and pushes their kinds. `lat` carries
# the boundaries, the neighbourhood, the domain mask and the geometry; `core_lattice(lat)`
# gives the CorePotts `Lattice` for `shift`, `relation` and `embed`. Randomized layouts own
# their seed, so adding a layer never changes another layer's draws. Coordinates are lattice
# indices: axial `(q, r)` on a hexagonal lattice, where a box is a rhombus.

"""
    AbstractLayout

A layer of an initial condition. A new layout is a subtype with one method,
`paint!(σ, kinds, l, lat)`, that paints new cells over `σ` and pushes their kinds. `lat` is
the model's `LatticeSpec` (dims, boundaries, neighbourhood, domain, geometry; a bare `dims`
tuple becomes a closed `Moore(1)` lattice); `core_lattice(lat)` is the CorePotts `Lattice`. Turn
layouts into an operating point with [`layout`](@ref); compose them with `overlay`.
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
    for d in 1:N
        (first(region[d]) >= 1 && last(region[d]) <= dims[d]) ||
            throw(ArgumentError("$what: region $region lies outside the lattice $dims"))
    end
    return region
end

function _check_rank(l, N, dims, what)
    N == length(dims) || throw(ArgumentError("$what: the layout is $(N)D, the lattice $(length(dims))D"))
end

_periodic(lat::LatticeSpec{N}) where {N} = (b = lat.boundary;
    map(x -> x isa Periodic, b isa CorePotts.AbstractBoundary ? ntuple(_ -> b, N) : Tuple(b)))

_paint_box!(σ, id, lo, sz) = (σ[CartesianIndices(map((o, s) -> o:(o + s - 1), lo, sz))] .= id)

"""
    Tiling(size; spacing = 0, region = <whole lattice>, kinds)

Boxes of `size` (a tuple, one entry per axis), `spacing` medium sites apart (an integer or
a tuple), filling `region` (a tuple of ranges) in column-major order from its lower corner.
Only whole boxes are placed. `kinds` is cycled over the cells in placement order. On a
periodic axis, trailing boxes closer than `spacing` to the first box through the wrap are
skipped, so the spacing also holds across the boundary.
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

function paint!(σ, kinds, l::Tiling{N}, lat::LatticeSpec) where {N}
    dims = lat.dims
    _check_rank(l, N, dims, "Tiling")
    reg = _region(l.region, dims, "Tiling")
    per = _periodic(lat)
    starts = map(reg, l.size, l.spacing, dims, per) do r, s, p, n, wrap
        st = first(r):(s + p):(last(r) - s + 1)
        # sites between the last box and the first through the wrap
        while wrap && length(st) > 1 && n - (last(st) + s - 1) + first(st) - 1 < p
            st = first(st):step(st):(last(st) - step(st))
        end
        st
    end
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
sites apart along some axis (Chebyshev: with `gap = 1` no two cells touch under Moore(1)).
On a periodic axis the separation is measured through the wrap. On a hexagonal lattice the
gap is Chebyshev in axial coordinates, which is conservative (hex neighbours are a subset of
Moore(1)). Like every layer it overwrites earlier layers (pass a `region` to keep clear of a
[`Frame`](@ref)).

Placement is random sequential: box after box is drawn with a `StableRNG(seed)` (so it is
deterministic in `seed` across Julia versions) and rejected while it is too close to a
placed box. `kinds` is cycled over the cells. Throws an `ArgumentError` when the boxes
cannot fit the region, and also when a box cannot be placed after 10,000 draws: random
sequential placement jams at about half of the densest packing, so a feasible but dense
request can throw.
"""
struct Scattered{N, K} <: AbstractLayout
    n::Int
    size::NTuple{N, Int}
    region::Union{Nothing, NTuple{N, UnitRange{Int}}}
    kinds::Vector{K}
    seed::UInt64
    gap::Int
end
function Scattered(n::Integer, size; region = nothing, kinds, seed::Integer, gap::Integer = 1)
    N = length(size)
    n >= 0 || throw(ArgumentError("Scattered: the number of boxes must be non-negative, got $n"))
    gap >= 0 || throw(ArgumentError("Scattered: gap must be non-negative, got $gap"))
    0 <= seed <= typemax(UInt64) || throw(ArgumentError("Scattered: seed must be in 0:typemax(UInt64), got $seed"))
    sz = _check_size(_tuple(size, N), "Scattered")
    return Scattered(Int(n), sz, _region_arg(region, N, "Scattered"), _kinds_arg(kinds, "Scattered"), UInt64(seed),
        Int(gap))
end

const _SCATTER_ATTEMPTS = 10_000   # rejection draws per box before giving up

# Boxes at lower corners `a` and `b` are at least `gap` sites apart along some axis; on a
# periodic axis of length `n` in both directions around the ring.
function _apart1(a, b, s, gap, n, wrap)
    wrap || return a + s + gap <= b || b + s + gap <= a
    δ = mod(b - a, n)
    return δ - s >= gap && n - δ - s >= gap
end
_apart(a, b, sz, gap, dims, per) = any(ntuple(d -> _apart1(a[d], b[d], sz[d], gap, dims[d], per[d]), length(a)))

function paint!(σ, kinds, l::Scattered{N}, lat::LatticeSpec) where {N}
    dims = lat.dims
    _check_rank(l, N, dims, "Scattered")
    per = _periodic(lat)
    reg = _region(l.region, dims, "Scattered")
    ext = map(length, reg)
    all(map(>=, ext, l.size)) || throw(ArgumentError("Scattered: boxes of size $(l.size) do not fit the region $reg"))
    # necessary: the boxes grown by `gap` on their upper sides are disjoint in the region
    # grown by `gap`; on a periodic axis they are disjoint around the ring, so at most `n`
    room = map((e, n, p) -> p ? min(e + l.gap, n) : e + l.gap, ext, dims, per)
    grown = map((s, n, p) -> p ? min(s + l.gap, n) : s + l.gap, l.size, dims, per)
    prod(room) >= l.n * prod(grown) ||
        throw(ArgumentError("Scattered: $(l.n) boxes of size $(l.size) with gap $(l.gap) cannot fit the region $reg"))
    rng = StableRNG(l.seed)
    ranges = map((r, s) -> first(r):(last(r) - s + 1), reg, l.size)
    corners = NTuple{N, Int}[]
    for k in 1:(l.n)
        placed = false
        for _ in 1:_SCATTER_ATTEMPTS
            o = map(r -> rand(rng, r), ranges)
            if all(c -> _apart(o, c, l.size, l.gap, dims, per), corners)
                push!(corners, o)
                placed = true
                break
            end
        end
        placed || throw(ArgumentError("Scattered: could not place box $k of $(l.n) (size $(l.size), gap $(l.gap)) " *
                                      "in the region $reg after $_SCATTER_ATTEMPTS draws (random sequential placement " *
                                      "jammed); use fewer or smaller boxes, a smaller gap or a larger region"))
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
with a `[frozen]` kind). Periodic axes have no edge: on a `(Periodic(), Closed())` lattice
the frame is two walls, at both ends of y (a channel), that are still one cell (one id, one
kind). A lattice periodic along every axis has no edge and throws an `ArgumentError`.
"""
struct Frame{K} <: AbstractLayout
    kind::K
    width::Int
end
function Frame(kind; width::Integer = 1)
    width >= 1 || throw(ArgumentError("Frame: width must be at least 1, got $width"))
    return Frame(kind, Int(width))
end

function paint!(σ, kinds, l::Frame, lat::LatticeSpec)
    dims, per = lat.dims, _periodic(lat)
    all(per) && throw(ArgumentError("Frame: every axis of the lattice is periodic, so it has no edge"))
    push!(kinds, l.kind)
    id, w = Int32(length(kinds)), l.width
    for i in CartesianIndices(σ)
        any(ntuple(d -> !per[d] && (i[d] <= w || i[d] > dims[d] - w), length(dims))) && (σ[i] = id)
    end
    return σ
end

"""
    overlay(layers...)

Layers painted in order: later layers overwrite earlier ones, and cell ids follow layer
order. Cells left with no site are dropped (ids stay consecutive); a partly covered cell
keeps its remaining sites, which may fall apart into pieces: `layout` warns, naming the cell,
when a later layer splits a cell into pieces that are not connected under the lattice
neighbourhood.
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

function paint!(σ, kinds, l::Overlay, lat::LatticeSpec)
    cut = Set{Int32}()                      # cells that lost sites to a later layer
    prev = similar(σ, 0)                    # one buffer, refilled before each later layer
    for (j, x) in enumerate(l.layers)
        if j > 1
            j == 2 && (prev = similar(σ))
            copyto!(prev, σ)
        end
        paint!(σ, kinds, x, lat)
        j == 1 && continue
        for i in eachindex(σ)
            0 < prev[i] != σ[i] && push!(cut, prev[i])
        end
    end
    isempty(cut) || _warn_split(σ, kinds, cut, lat)
    return σ
end

# Warn about cut cells whose remaining sites are not connected under the neighbourhood.
# One pass records each cut cell's first site, site count and bounding box in dense per-cell
# buffers; a cell that is still a full box is connected (every neighbourhood holds the unit
# axis steps) and skipped; the rest are flood-filled, stamping `visited` with the cell id so
# it never needs a reset. O(sites).
function _warn_split(σ, kinds, cut, lat::LatticeSpec{N}) where {N}
    K = length(kinds)
    iscut = falses(K)
    for c in cut
        iscut[c] = true
    end
    first_site = zeros(Int, K)
    nsites = zeros(Int, K)
    lo = fill(ntuple(_ -> typemax(Int), N), K)
    hi = fill(ntuple(_ -> typemin(Int), N), K)
    alive = falses(K)
    ci = CartesianIndices(σ)
    for i in eachindex(σ)
        c = σ[i]
        c > 0 || continue
        alive[c] = true
        iscut[c] || continue
        nsites[c] == 0 && (first_site[c] = i)
        nsites[c] += 1
        x = Tuple(ci[i])
        lo[c] = min.(lo[c], x)
        hi[c] = max.(hi[c], x)
    end
    clat = core_lattice(lat)
    offs = CorePotts.relation(lat.neighborhood, clat).offsets
    units = all(d -> all(s -> ntuple(k -> Int32(k == d ? s : 0), N) in offs, (-1, 1)), 1:N)
    visited = zeros(Int32, size(σ))
    stack = Int[]
    li = LinearIndices(σ)
    for c in sort!(collect(cut))
        nsites[c] == 0 && continue
        units && nsites[c] == prod(hi[c] .- lo[c] .+ 1) && continue      # still a box
        visited[first_site[c]] = c
        push!(stack, first_site[c])
        reached = 1
        while !isempty(stack)
            x = Tuple(ci[pop!(stack)])
            for o in offs
                inside, y = CorePotts.shift(clat, x, o)
                inside || continue
                k = li[y...]
                (σ[k] == c && visited[k] != c) || continue
                visited[k] = c
                reached += 1
                push!(stack, k)
            end
        end
        reached < nsites[c] &&
            @warn "overlay: later layers split cell $(count(view(alive, 1:c))) (kind $(kinds[c])) into disconnected pieces"
    end
    return nothing
end

"""
    layout(l, dims) -> [ownership => σ, kind => kinds]

Paint the layout `l` (see `overlay`) on an empty lattice and return an operating
point for `PottsProblem`: `σ` is an `Int32` array (0 = medium).

A `dims` tuple means a closed square lattice with the `Moore(1)` neighbourhood. For a
hexagonal, periodic, domain-restricted or non-Moore lattice pass the `PottsSystem` (or
`CompiledPottsSystem`), whose boundaries, neighbourhood, domain and geometry the layouts
use; a CorePotts `Lattice` carries boundaries, domain and geometry but no neighbourhood,
so `Moore(1)` is assumed (it only matters for the split warning of `overlay`). On a
lattice with a domain, no cell may cover a site outside it.
"""
function layout(l::AbstractLayout, dims::Tuple{Vararg{Integer}})
    all(>(0), dims) || throw(ArgumentError("layout: lattice dimensions must be positive, got $dims"))
    return _layout(l, lattice_spec(dims; boundary = Closed()))
end
layout(l::AbstractLayout, lat::Lattice) = _layout(l,
    LatticeSpec(lat.dims, map(p -> p ? Periodic() : Closed(), lat.periodic), nothing, Moore(1), lat.mask,
        lat.geometry))
layout(l::AbstractLayout, lat::LatticeSpec) = _layout(l, lat)
layout(l::AbstractLayout, sys::PottsSystem) = layout(l, sys.lattice)
layout(l::AbstractLayout, sys::CompiledPottsSystem) = layout(l, sys.sys)

function _layout(l, lat::LatticeSpec)
    σ = zeros(Int32, lat.dims)
    kinds = Any[]
    paint!(σ, kinds, l, lat)
    σ, kinds = _compact(σ, kinds)
    mask = lat.domain
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
