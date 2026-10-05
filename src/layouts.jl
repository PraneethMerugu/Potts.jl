# Layouts (ROADMAP P6.1a, review §3 R2; protocol P6.1a6, D-075/D-091): host-side initial
# conditions composed from layers and returned as an SII operating point
# `[ownership => σ, kind => kinds]`.
#
# Every layout is a subtype of `AbstractLayout` with one method, `paint!(op::LayoutState, l,
# lat)`. `op` is opaque: a layer allocates cells with `new_cell!`, paints sites with
# `assign!`, reads the paint so far with `owner`/`kindof`/`ncells` and reports with
# `record!`. `lat` is read only through the lattice queries `size`, `isperiodic` and
# `indomain` (plus `core_lattice` for CorePotts' `shift`, `relation` and `embed`). Randomized
# layouts own their seed, so adding a layer never changes another layer's draws. Box
# coordinates are lattice indices: axial `(q, r)` on a hexagonal lattice, where a box is a
# rhombus. Shapes and points (`Circle`, `Point`, …; P6.1a5) are Cartesian (`embed`).

"""
    AbstractLayout

A layer of an initial condition. Turn layouts into an operating point with
[`layout`](@ref); compose them with [`overlay`](@ref).

A new layout is a subtype with one method, `Potts.paint!(op::Potts.LayoutState, l, lat)`
(the return value is ignored). `op` is opaque: the method reads and writes it only through
[`new_cell!`](@ref), [`assign!`](@ref), [`owner`](@ref), [`kindof`](@ref),
[`ncells`](@ref) and [`record!`](@ref), and reads the lattice only through `size(lat)`,
[`isperiodic`](@ref)`(lat, d)` and [`indomain`](@ref)`(lat, x)` (and
`core_lattice(lat)` for CorePotts' `shift`, `relation` and `embed`). Every name
is `public`, so a layout in another package passes ExplicitImports' qualified-access check.

```julia
struct Column <: AbstractLayout
    x::Int
    kind::Symbol
end
function Potts.paint!(op::Potts.LayoutState, l::Column, lat)
    id = Potts.new_cell!(op, l.kind)
    Potts.assign!(op, (l.x:l.x, 1:size(lat)[2]), id)
    Potts.record!(op; requested = 1, painted = 1)
end
```

Every built-in layer (`Tiling`, `Scattered`, `Frame`, `InsertUntil`, `Voronoi`, `Eden`,
`Splits`) takes
`splits = :warn | :allow` and can be rebuilt with changed keywords by
`remake(l; kw...)`, which re-runs the keyword constructor (so it validates).
"""
abstract type AbstractLayout end

# ---------------------------------------------------------------------------------------------
# The paint state and its accessors
# ---------------------------------------------------------------------------------------------

# One leaf layer's report entry (ids `first:last` are the cells it allocated).
mutable struct _LayerRow
    const type::Symbol
    const first::Int
    last::Int
    requested::Int
    painted::Int
    misses::Int
    counted::Int
    recorded::Bool
    splits::Int
    clipped::Int
end

"""
    LayoutState

The paint so far, handed to `paint!(op::LayoutState, l, lat)`. Opaque: use
[`new_cell!`](@ref), [`assign!`](@ref), [`owner`](@ref), [`kindof`](@ref),
[`ncells`](@ref) and [`record!`](@ref).
"""
mutable struct LayoutState{N}
    const σ::Array{Int32, N}
    const kinds::Vector{Any}
    const cutby::Vector{Int32}       # per cell before the current leaf: 0, the one cutter, or -1 (several)
    const cutwarn::Vector{Bool}      # … some cutter has `splits = :warn`
    const rows::Vector{_LayerRow}
    const pieces::Vector{Tuple{Int, Int, Bool}}   # `Splits`: (cell, row, warn) of its cells left in pieces
    layer::Int                       # the current leaf (0: none)
    base::Int                        # cells allocated before the current leaf
    warn::Bool                       # the current leaf has `splits = :warn`
end
LayoutState(dims::NTuple{N, Int}) where {N} =
    LayoutState{N}(zeros(Int32, dims), Any[], Int32[], Bool[], _LayerRow[], Tuple{Int, Int, Bool}[], 0, 0, true)

"""
    new_cell!(op::LayoutState, kind) -> id

Allocate the next cell, of `kind`, and return its id, `ncells(op) + 1`. Ids are those of the
paint so far: cells left with no site are dropped (and the rest renumbered) after the whole
layout is painted.
"""
function new_cell!(op::LayoutState, kind)
    push!(op.kinds, kind)
    return length(op.kinds)
end

"""
    assign!(op::LayoutState, x, id) -> Int

Paint the site `x` (a tuple of integers or a `CartesianIndex`) or the box `x` (a tuple of
unit ranges) with cell `id` (0 paints medium) and return the number of sites written.
Sites and boxes are lattice indices on the lattice: nothing wraps (a box crossing a periodic
edge is two `assign!` calls; `CorePotts.shift` maps a displaced site back).
"""
function assign!(op::LayoutState{N}, x::NTuple{N, Integer}, id::Integer) where {N}
    _assign_site!(op, CartesianIndex(x), _cell_id(op, id))
    return 1
end
function assign!(op::LayoutState{N}, x::CartesianIndex{N}, id::Integer) where {N}
    _assign_site!(op, x, _cell_id(op, id))
    return 1
end
function assign!(op::LayoutState{N}, x::NTuple{N, Union{Integer, AbstractUnitRange{<:Integer}}}, id::Integer) where {N}
    R = CartesianIndices(map(r -> r isa Integer ? (r:r) : r, x))
    return _assign_box!(op, R, _cell_id(op, id))
end

function _cell_id(op::LayoutState, id::Integer)
    0 <= id <= length(op.kinds) || _unallocated(op, id)
    return id % Int32
end
@noinline _unallocated(op, id) =
    throw(ArgumentError("assign!: cell $id is not allocated (ncells = $(length(op.kinds))); use new_cell!"))

# A site of a cell painted before the current leaf changes hands: the leaf cuts that cell.
function _cut!(op::LayoutState, o::Int32)
    j = Int32(op.layer)
    c = op.cutby[o]
    op.cutby[o] = (c == 0 || c == j) ? j : Int32(-1)
    op.warn && (op.cutwarn[o] = true)
    return nothing
end

function _assign_site!(op::LayoutState, i::CartesianIndex, id::Int32)
    σ = op.σ
    o = σ[i]
    0 < o <= op.base && o != id && _cut!(op, o)
    σ[i] = id
    return nothing
end

function _assign_box!(op::LayoutState, R::CartesianIndices, id::Int32)
    if op.base == 0                          # no cell before this leaf: nothing to cut
        op.σ[R] .= id
    else
        _assign_box_cut!(op, R, id)
    end
    return length(R)
end
@noinline function _assign_box_cut!(op::LayoutState, R::CartesianIndices, id::Int32)
    σ, base = op.σ, op.base
    checkbounds(σ, R)
    for i in R
        o = @inbounds σ[i]                   # inbounds: checkbounds(σ, R) above
        0 < o <= base && o != id && _cut!(op, o)
        @inbounds σ[i] = id
    end
    return nothing
end

"""
    owner(op::LayoutState, x) -> Integer

The cell owning site `x` (a tuple of integers or a `CartesianIndex`) in the paint so far;
0 is the medium.
"""
owner(op::LayoutState{N}, x::NTuple{N, Integer}) where {N} = op.σ[x...]
owner(op::LayoutState{N}, x::CartesianIndex{N}) where {N} = op.σ[x]

"""
    kindof(op::LayoutState, id)

The kind given to [`new_cell!`](@ref) for cell `id`.
"""
kindof(op::LayoutState, id::Integer) = op.kinds[id]

"""
    ncells(op::LayoutState) -> Int

The number of cells allocated so far (the largest id). Not `CorePotts.ncells`, which
counts the cells of a simulation state.
"""
ncells(op::LayoutState) = length(op.kinds)

"""
    record!(op::LayoutState; requested, painted, misses = 0, counted = painted, clipped = 0)

Set the current leaf layer's entry in the layout report (see [`layout`](@ref)): what it was
asked for, the cells it created, the draws that missed, what a stop rule counted and the
sites of its region lost to closed edges and the domain. A layer that does not call it
reports `requested = painted =` the cells it allocated and `clipped = 0`. A layer that
paints built-in layers inside its own `paint!` calls `record!` last: their entries go to the
same row.
"""
function record!(op::LayoutState; requested::Integer, painted::Integer, misses::Integer = 0,
        counted::Integer = painted, clipped::Integer = 0)
    op.layer == 0 && throw(ArgumentError("record!: called outside a layer's paint!"))
    r = op.rows[op.layer]
    r.requested, r.painted, r.misses, r.counted, r.clipped, r.recorded = requested, painted, misses, counted, clipped, true
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Lattice queries
# ---------------------------------------------------------------------------------------------

Base.size(lat::LatticeSpec) = lat.dims
Base.size(lat::LatticeSpec, d::Integer) = lat.dims[d]

_periodic(lat::LatticeSpec{N}) where {N} = (b = lat.boundary;
    map(x -> x isa Periodic, b isa CorePotts.AbstractBoundary ? ntuple(_ -> b, N) : Tuple(b)))

"""
    isperiodic(lat, d) -> Bool

Whether axis `d` of the lattice a layout is painted on is periodic.
"""
isperiodic(lat::LatticeSpec, d::Integer) = _periodic(lat)[d]

"""
    indomain(lat, x) -> Bool

Whether site `x` (a tuple of integers or a `CartesianIndex`) lies on the lattice and inside
its domain (every lattice site, without a domain). Unlike CorePotts' `in_domain(lattice, i)`
it checks bounds and takes a layout's `lat`.
"""
indomain(lat::LatticeSpec{N}, x::NTuple{N, Integer}) where {N} = indomain(lat, CartesianIndex(x))
function indomain(lat::LatticeSpec{N}, x::CartesianIndex{N}) where {N}
    checkbounds(Bool, CartesianIndices(lat.dims), x) || return false
    m = lat.domain
    return m === nothing || m[x]
end

# ---------------------------------------------------------------------------------------------
# Argument helpers
# ---------------------------------------------------------------------------------------------

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

function _splits_arg(s, what)
    s in (:warn, :allow) || throw(ArgumentError("$what: `splits` must be :warn or :allow, got $(repr(s))"))
    return s
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

# The `splits` setting of a layer (custom layers: :warn).
_splits(::AbstractLayout) = :warn

# ---------------------------------------------------------------------------------------------
# Tiling
# ---------------------------------------------------------------------------------------------

"""
    Tiling(size; spacing = 0, region = <whole lattice>, kinds, partial = :skip, splits = :warn)

Boxes of `size` (a tuple, one entry per axis), `spacing` medium sites apart (an integer or
a tuple), filling `region` (a tuple of ranges) in column-major order from its lower corner.
`kinds` is cycled over the cells in placement order.

- `partial = :skip` places whole boxes only; `region` must lie on the lattice.
- `partial = :clip` also starts boxes up to the end of the region and keeps the part of
  each box inside region ∩ lattice (`region` may reach beyond the lattice). Unlike
  CompuCell3D's uniform initializer, which clips at the lattice only, boxes are clipped at
  the region too.

On a periodic axis, trailing boxes closer than `spacing` to the first box through the wrap
are skipped, so the spacing also holds across the boundary.
"""
struct Tiling{N, K} <: AbstractLayout
    size::NTuple{N, Int}
    spacing::NTuple{N, Int}
    region::Union{Nothing, NTuple{N, UnitRange{Int}}}
    kinds::Vector{K}
    partial::Symbol
    splits::Symbol
end
function Tiling(size; spacing = 0, region = nothing, kinds, partial::Symbol = :skip, splits::Symbol = :warn)
    N = length(size)
    sz = _check_size(_tuple(size, N), "Tiling")
    sp = _tuple(spacing, N)
    all(>=(0), sp) || throw(ArgumentError("Tiling: spacing must be non-negative, got $sp"))
    partial in (:skip, :clip) ||
        throw(ArgumentError("Tiling: `partial` must be :skip or :clip, got $(repr(partial))"))
    return Tiling(sz, sp, _region_arg(region, N, "Tiling"), _kinds_arg(kinds, "Tiling"), partial,
        _splits_arg(splits, "Tiling"))
end
_splits(l::Tiling) = l.splits

"""
    Potts.paint!(op::LayoutState, l::AbstractLayout, lat)

Paint layer `l` into the layout state `op` on lattice `lat`: the one method a new layout
defines (see [`AbstractLayout`](@ref)). It allocates cells with [`new_cell!`](@ref), paints
with [`assign!`](@ref), may read the paint so far with [`owner`](@ref), [`kindof`](@ref) and
[`ncells`](@ref), and may report with [`record!`](@ref); `lat` is read with `size`,
[`isperiodic`](@ref) and [`indomain`](@ref). The return value is ignored. Call it only from
another layer's `paint!`; [`layout`](@ref) runs a layout.
"""
function paint! end

function paint!(op::LayoutState, l::Tiling{N}, lat) where {N}
    dims = size(lat)
    _check_rank(l, N, dims, "Tiling")
    clip = l.partial === :clip
    reg = clip && l.region !== nothing ? _clip_region(l.region, dims) : _region(l.region, dims, "Tiling")
    starts = ntuple(d -> _tiling_starts(reg[d], l.size[d], l.spacing[d], dims[d], isperiodic(lat, d), clip), Val(N))
    any(isempty, starts) &&
        throw(ArgumentError("Tiling: no box of size $(l.size) fits the region $reg"))
    n = 0
    for o in Iterators.product(starts...)
        n += 1
        id = new_cell!(op, l.kinds[mod1(n, length(l.kinds))])
        assign!(op, map((a, s, r) -> a:min(a + s - 1, last(r)), o, l.size, reg), id)
    end
    record!(op; requested = n, painted = n)
    return nothing
end

# region ∩ lattice (`partial = :clip`)
function _clip_region(region, dims)
    reg = map((r, n) -> max(first(r), 1):min(last(r), n), region, dims)
    any(isempty, reg) && throw(ArgumentError("Tiling: region $region does not meet the lattice $dims"))
    return reg
end

# The box starts along one axis: region `r`, box size `s`, spacing `p`, lattice length `n`.
function _tiling_starts(r, s, p, n, wrap, clip)
    st = first(r):(s + p):(clip ? last(r) : last(r) - s + 1)
    # sites between the last box (clipped to the region) and the first through the wrap
    while wrap && length(st) > 1 && n - min(last(st) + s - 1, last(r)) + first(st) - 1 < p
        st = first(st):step(st):(last(st) - step(st))
    end
    return st
end

# ---------------------------------------------------------------------------------------------
# Scattered
# ---------------------------------------------------------------------------------------------

"""
    Scattered(n, size; region = <whole lattice>, kinds, seed, gap = 1, splits = :warn)

`n` boxes of `size` at uniformly random positions inside `region`, at least `gap` medium
sites apart along some axis (Chebyshev: with `gap = 1` no two cells touch under Moore(1)).
On a periodic axis the separation is measured through the wrap. On a hexagonal lattice the
gap is Chebyshev in axial coordinates, which is conservative (hex neighbours are a subset of
Moore(1)). Like every layer it overwrites earlier layers (pass a `region` to keep clear of a
[`Frame`](@ref)).

Placement is random sequential: box after box is drawn with a `StableRNG(seed)` (so it is
deterministic in `seed` across Julia versions) and rejected while it is too close to a
box placed earlier by this layer (cells of earlier layers do not count). The test runs on an
occupancy mask of the region, so a draw costs `prod(size .+ 2gap)` site reads, independent
of the number placed. `kinds` is cycled over the cells. Throws an `ArgumentError` when the boxes
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
    splits::Symbol
end
function Scattered(n::Integer, size; region = nothing, kinds, seed::Integer, gap::Integer = 1,
        splits::Symbol = :warn)
    N = length(size)
    n >= 0 || throw(ArgumentError("Scattered: the number of boxes must be non-negative, got $n"))
    gap >= 0 || throw(ArgumentError("Scattered: gap must be non-negative, got $gap"))
    0 <= seed <= typemax(UInt64) || throw(ArgumentError("Scattered: seed must be in 0:typemax(UInt64), got $seed"))
    sz = _check_size(_tuple(size, N), "Scattered")
    return Scattered(Int(n), sz, _region_arg(region, N, "Scattered"), _kinds_arg(kinds, "Scattered"), UInt64(seed),
        Int(gap), _splits_arg(splits, "Scattered"))
end
_splits(l::Scattered) = l.splits

const _SCATTER_ATTEMPTS = 10_000   # rejection draws per box before giving up

# The overlap test runs on an occupancy mask of the region (`occ`, indexed from `first(r)`): a draw is
# rejected iff a site of an earlier box of this layer lies in the draw's box grown by `gap`
# on every side. Per axis this is exactly the Chebyshev rule `a + s + gap <= b || b + s + gap
# <= a` (closed) or `δ - s >= gap && n - δ - s >= gap` with `δ = mod(b - a, n)` (periodic):
# the grown window wraps on a periodic axis and covers the whole ring once `s + 2gap >= n`.
# Only boxes of this layer count, as before: sites painted by earlier layers do not.
#
# The window along one axis is at most two pieces of `1:n`, each cut to the region `r` and
# shifted into mask indices.
function _scatter_window(a, s, gap, n, wrap, r)
    lo, hi = a - gap, a + s - 1 + gap
    if !wrap
        p, q = max(lo, 1):min(hi, n), 1:0
    elseif s + 2gap >= n
        p, q = 1:n, 1:0
    elseif lo < 1
        p, q = 1:hi, (lo + n):n
    elseif hi > n
        p, q = lo:n, 1:(hi - n)
    else
        p, q = lo:hi, 1:0
    end
    cut(x) = (max(first(x), first(r)) - first(r) + 1):(min(last(x), last(r)) - first(r) + 1)
    return (cut(p), cut(q))
end

# Some site of `occ` in the window (the product over axes of one piece each) is set.
function _scatter_hit(occ, win::NTuple{N, Tuple{UnitRange{Int}, UnitRange{Int}}}) where {N}
    for k in 0:(2^N - 1)
        ranges = ntuple(d -> win[d][((k >> (d - 1)) & 1) + 1], Val(N))
        any(isempty, ranges) && continue
        for I in CartesianIndices(ranges)
            occ[I] && return true
        end
    end
    return false
end

function paint!(op::LayoutState, l::Scattered{N}, lat) where {N}
    dims = size(lat)
    _check_rank(l, N, dims, "Scattered")
    per = ntuple(d -> isperiodic(lat, d), Val(N))
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
    occ = falses(ext)                  # sites of the boxes placed so far, in region indices
    corners = Vector{NTuple{N, Int}}(undef, l.n)
    for k in 1:(l.n)
        placed = false
        for _ in 1:_SCATTER_ATTEMPTS
            o = map(r -> rand(rng, r), ranges)
            win = map((a, s, n, p, r) -> _scatter_window(a, s, l.gap, n, p, r), o, l.size, dims, per, reg)
            _scatter_hit(occ, win) && continue
            fill!(view(occ, map((a, s, r) -> (a - first(r) + 1):(a - first(r) + s), o, l.size, reg)...), true)
            corners[k] = o
            placed = true
            break
        end
        placed || throw(ArgumentError("Scattered: could not place box $k of $(l.n) (size $(l.size), gap $(l.gap)) " *
                                      "in the region $reg after $_SCATTER_ATTEMPTS draws (random sequential placement " *
                                      "jammed); use fewer or smaller boxes, a smaller gap or a larger region"))
    end
    for (k, o) in enumerate(corners)
        id = new_cell!(op, l.kinds[mod1(k, length(l.kinds))])
        assign!(op, map((a, s) -> a:(a + s - 1), o, l.size), id)
    end
    record!(op; requested = l.n, painted = l.n)
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------------------------

"""
    Frame(kind; width = 1, splits = :warn)

One cell of `kind` owning every site within `width` of the lattice edge (a wall; pair it
with a `[frozen]` kind). Periodic axes have no edge: on a `(Periodic(), Closed())` lattice
the frame is two walls, at both ends of y (a channel), that are still one cell (one id, one
kind). A lattice periodic along every axis has no edge and throws an `ArgumentError`.

On a lattice with a domain the frame follows the domain boundary: it owns every in-domain
site within Chebyshev distance `width`, in lattice indices, of a site outside the domain or
of a closed lattice edge (through the wrap on periodic axes). Without a domain this is the
rule above. Chebyshev distance is Moore(1) graph distance on a square lattice; on a
hexagonal lattice it is measured in axial indices and is conservative (hex neighbours are a
subset of Moore(1)), so the frame seals the domain under any Moore(1)/Hex(1)
neighbourhood. A domain whose only boundary would be periodic wrap throws, as above.
"""
struct Frame{K} <: AbstractLayout
    kind::K
    width::Int
    splits::Symbol
end
function Frame(kind; width::Integer = 1, splits::Symbol = :warn)
    width >= 1 || throw(ArgumentError("Frame: width must be at least 1, got $width"))
    return Frame(kind, Int(width), _splits_arg(splits, "Frame"))
end
_splits(l::Frame) = l.splits

function paint!(op::LayoutState, l::Frame, lat)
    dims = size(lat)
    N = length(dims)
    per = ntuple(d -> isperiodic(lat, d), N)
    sites = CartesianIndices(dims)
    if !all(i -> indomain(lat, i), sites)
        _paint_domain_frame!(op, l, BitArray(indomain(lat, i) for i in sites), dims, per)
    else
        all(per) && throw(ArgumentError("Frame: the lattice has no boundary (every axis is periodic, so it has no edge)"))
        id, w = new_cell!(op, l.kind), l.width
        for i in sites
            any(ntuple(d -> !per[d] && (i[d] <= w || i[d] > dims[d] - w), N)) && assign!(op, i, id)
        end
    end
    record!(op; requested = 1, painted = 1)
    return nothing
end

# The frame on a domain: dilate the out-of-domain set (plus the virtual sites beyond each
# closed edge) by a Chebyshev ball of radius `w`, one axis at a time (a box is the product
# of its axis segments), and paint the in-domain sites it reaches. O(sites · w).
function _paint_domain_frame!(op, l::Frame, mask, dims, per)
    w = l.width
    near = .!mask
    src = similar(near)
    for d in eachindex(dims)
        copyto!(src, near)
        n = dims[d]
        for i in CartesianIndices(near)
            near[i] && continue
            x = i[d]
            if !per[d] && (x <= w || x > n - w)          # within `w` of a closed edge
                near[i] = true
                continue
            end
            for s in (-w):w
                y = per[d] ? mod1(x + s, n) : x + s
                1 <= y <= n || continue
                if src[CartesianIndex(Base.setindex(Tuple(i), y, d))]
                    near[i] = true
                    break
                end
            end
        end
    end
    any(i -> mask[i] && near[i], eachindex(mask)) ||
        throw(ArgumentError("Frame: the domain has no boundary (it fills a lattice that is periodic along every axis)"))
    id = new_cell!(op, l.kind)
    for i in CartesianIndices(mask)
        mask[i] && near[i] && assign!(op, i, id)
    end
    return nothing
end

# ---------------------------------------------------------------------------------------------
# InsertUntil
# ---------------------------------------------------------------------------------------------

"""
    InsertUntil(kind; into, fraction = nothing, number = nothing, seed, region = <whole lattice>,
                misses = :retry, splits = :warn)

One-site cells of `kind` inserted at random into cells of the kinds `into`, until a count is
reached. Each draw picks a site of `region` (a tuple of ranges) uniformly with
`StableRNG(seed)`. It *hits* when the site belongs to a cell whose kind is in `into` and that
was painted before this layer: the site becomes a new one-site cell of `kind`. Any other
draw (medium, a site outside the domain, another kind, a cell this layer inserted) *misses*.

- `misses = :retry`: a miss changes nothing and is drawn again.
- `misses = :count`: a miss also counts towards the stop rule, without creating a cell (the
  empty cells that CompuCell3D-style seeding scripts create on a miss; they never own a site,
  so they are never alive and are not allocated).

The count is `counted` = hits (+ misses under `:count`). Give exactly one stop rule:

- `number = n`: stop once `counted ≥ n`;
- `fraction = r` (`0 < r < 1`): stop once `K + counted ≥ r·(N + counted)`, where `N` is
  the number of cells painted before this layer and `K` the number of those of `kind`, both
  counting only cells that still own a site.
  Pass a `Rational` (e.g. `1//4`) to emulate a script's `K/(N) < r` loop exactly: with a
  floating-point `r` the product form can disagree with the ratio form at the boundary.

The rule is checked before the first draw and after every hit, not after a miss, so under
`:count` the count can overshoot by the misses drawn since the last hit (as in a script that
recomputes its ratio only when it paints). A hit may take the last site of a cell, which then
drops out of `N` (and `K`). Throws an `ArgumentError` when `region` holds no site to insert
into, when the allowed sites run out before the rule is met, and for a missing, doubled or
out-of-range stop rule. `layout(l, x; report = true)` reports how many cells the layer
inserted (`painted`), how many draws missed (`misses`, in both modes) and what its stop rule
counted (`counted`); `requested` is `number`, or `counted` under a `fraction` rule.
"""
struct InsertUntil{K} <: AbstractLayout
    kind::K
    into::Vector{Any}
    fraction::Union{Nothing, Real}
    number::Int
    seed::UInt64
    region::Union{Nothing, Tuple{Vararg{UnitRange{Int}}}}
    count_misses::Bool
    splits::Symbol
end
function InsertUntil(kind; into, fraction = nothing, number = nothing, seed::Integer, region = nothing,
        misses::Symbol = :retry, splits::Symbol = :warn)
    (fraction === nothing) == (number === nothing) &&
        throw(ArgumentError("InsertUntil: give exactly one stop rule, `fraction` or `number`"))
    fraction === nothing || (fraction isa Real && 0 < fraction < 1) ||
        throw(ArgumentError("InsertUntil: `fraction` must lie strictly between 0 and 1, got $fraction"))
    number === nothing || (number isa Integer && number >= 0) ||
        throw(ArgumentError("InsertUntil: `number` must be a non-negative integer, got $number"))
    misses in (:retry, :count) ||
        throw(ArgumentError("InsertUntil: `misses` must be :retry or :count, got $(repr(misses))"))
    0 <= seed <= typemax(UInt64) ||
        throw(ArgumentError("InsertUntil: seed must be in 0:typemax(UInt64), got $seed"))
    reg = region === nothing ? nothing : _region_arg(region, length(region), "InsertUntil")
    return InsertUntil(kind, collect(Any, _kinds_arg(into, "InsertUntil")), fraction,
        number === nothing ? -1 : Int(number), UInt64(seed), reg, misses === :count, _splits_arg(splits, "InsertUntil"))
end
_splits(l::InsertUntil) = l.splits

# The stop rule, from the cells painted before the layer that still own a site (`N`, `K`
# of them of the inserted kind) and the count so far.
_insert_done(l::InsertUntil, N, K, counted) = l.number >= 0 ? counted >= l.number :
                                               K + counted >= l.fraction * (N + counted)

function paint!(op::LayoutState, l::InsertUntil, lat)
    dims = size(lat)
    l.region === nothing || _check_rank(l, length(l.region), dims, "InsertUntil")
    sites = CartesianIndices(_region(l.region, dims, "InsertUntil"))
    n0 = ncells(op)                              # cells painted before this layer
    nsites = zeros(Int, n0)
    for i in CartesianIndices(dims)
        s = owner(op, i)
        s > 0 && (nsites[s] += 1)
    end
    target = [kindof(op, c) in l.into for c in 1:n0]   # a hit needs one of these owners
    N = count(>(0), nsites)
    K = count(c -> nsites[c] > 0 && isequal(kindof(op, c), l.kind), 1:n0)
    free = 0                                     # sites of `region` a draw can hit
    for i in sites
        s = owner(op, i)
        s > 0 && target[s] && (free += 1)
    end
    free == 0 && throw(ArgumentError("InsertUntil: the region $(sites.indices) holds no site of the kinds $(l.into)"))
    rng = StableRNG(l.seed)
    painted = misses = 0
    done = _insert_done(l, N, K, 0)
    while !done
        free == 0 && throw(ArgumentError("InsertUntil: the region ran out of sites of the kinds $(l.into) after " *
                                         "$painted insertions, before the stop rule was met"))
        i = sites[rand(rng, 1:length(sites))]
        s = owner(op, i)
        if 0 < s <= n0 && target[s]
            assign!(op, i, new_cell!(op, l.kind))
            nsites[s] -= 1
            if nsites[s] == 0                    # the hit took the cell's last site
                N -= 1
                isequal(kindof(op, s), l.kind) && (K -= 1)
            end
            painted += 1
            free -= 1
            done = _insert_done(l, N, K, painted + (l.count_misses ? misses : 0))
        else
            misses += 1
        end
    end
    counted = painted + (l.count_misses ? misses : 0)
    record!(op; requested = l.number >= 0 ? l.number : counted, painted, misses, counted)
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Shapes and point patterns (P6.1a5, D-138)
# ---------------------------------------------------------------------------------------------
#
# Shapes are GeometryBasics' `HyperSphere`s (`Circle`, `Sphere`) in Cartesian coordinates:
# the lattice's `embed` of the index (the identity on square lattices, `(q + r/2, r√3/2)` on
# hexagonal ones). Site `x` is in shape `s` iff `|center − embed(x)| ≤ r·(1 + 1e-12)` (closed,
# up to rounding: on hexagonal lattices `embed` carries √3/2 rounding, so sites at exactly the
# radius would otherwise drop out unevenly) for `x` or one of its images through periodic
# edges, so a shape wraps
# through a periodic edge and is clipped at a closed edge and at the domain. Generators are
# kept in index coordinates, where distances are embedded and Lloyd's centroids are taken
# (the embedding is linear, so a centroid maps to the Cartesian centroid).

# The embedding as a matrix: column j is the embedded unit vector along axis j.
function _embedding(clat, ::Val{N}) where {N}
    unit(j) = ntuple(d -> Float64(d == j), Val(N))
    return SMatrix{N, N, Float64}(ntuple(k -> Float64(embed(clat, unit((k - 1) ÷ N + 1))[(k - 1) % N + 1]), Val(N * N)))
end

# Per axis, the index half-width of the box that holds a Cartesian ball of radius 1: the
# row norms of the inverse embedding (|xᵢ| = |(E⁻¹v)ᵢ| ≤ ‖rowᵢ(E⁻¹)‖ |v|).
_box_scale(Ei::SMatrix{N, N}) where {N} = ntuple(i -> sqrt(sum(abs2, Ei[i, :])), Val(N))

# The Cartesian point of index coordinates `x`.
_cart(clat, x::NTuple{N, Real}) where {N} = Point{N, Float64}(embed(clat, map(Float64, x)))

function _shape_arg(s::HyperSphere, what)
    (all(isfinite, s.center) && isfinite(s.r) && s.r >= 0) ||
        throw(ArgumentError("$what: a shape needs a finite centre and a finite, non-negative radius, got $s"))
    return s
end

# A layer's or pattern's region: the whole lattice (`nothing`), a shape or a box of ranges.
_place_arg(::Nothing, what) = nothing
_place_arg(s::HyperSphere, what) = _shape_arg(s, what)
_place_arg(region, what) = _region_arg(region, length(region), what)

function _check_dim(::HyperSphere{M}, N, what) where {M}
    M == N || throw(ArgumentError("$what: the shape is $(M)D, the lattice $(N)D"))
    return nothing
end

# The in-domain lattice sites of a region in column-major order, and its `clipped` count:
# the points of the region that are not in-domain lattice sites.
function _region_sites(::Nothing, lat::LatticeSpec{N}, what) where {N}
    return CartesianIndex{N}[x for x in CartesianIndices(size(lat)) if indomain(lat, x)], 0
end
function _region_sites(region::Tuple, lat::LatticeSpec{N}, what) where {N}
    length(region) == N || throw(ArgumentError("$what: the region has $(length(region)) ranges, the lattice is $(N)D"))
    box = CartesianIndices(_region(region, size(lat), what))
    sites = CartesianIndex{N}[x for x in box if indomain(lat, x)]
    return sites, length(box) - length(sites)
end

# A shape: the scan covers the index box of its bounding ball (one point per class along
# periodic axes), so it costs O(box volume × images), not O(lattice). U = index points with
# periodic coordinates in `1:n` that lie in the shape; `clipped = |U| − sites`.
function _region_sites(s::HyperSphere, lat::LatticeSpec{N}, what) where {N}
    _check_dim(s, N, what)
    clat = core_lattice(lat)
    Ei = inv(_embedding(clat, Val(N)))
    c = Ei * SVector{N, Float64}(s.center)
    w = _box_scale(Ei) .* Float64(s.r)
    dims = size(lat)
    per = _periodic(lat)
    lo = ntuple(d -> floor(Int, c[d] - w[d]) - 1, Val(N))
    hi = ntuple(d -> ceil(Int, c[d] + w[d]) + 1, Val(N))
    cand = ntuple(d -> per[d] ? _residues(lo[d], hi[d], dims[d]) : collect(lo[d]:hi[d]), Val(N))
    sites = CartesianIndex{N}[]
    clipped = 0
    for x in Iterators.product(cand...)            # column-major: the axes are ascending
        _in_shape(s, clat, x, lo, hi, dims, per) || continue
        if indomain(lat, x)
            push!(sites, CartesianIndex(x))
        else
            clipped += 1
        end
    end
    return sites, clipped
end
_residues(lo, hi, n) = hi - lo + 1 >= n ? collect(1:n) : sort!([mod1(x, n) for x in lo:hi])

# Closed membership with a relative rounding tolerance (D-138).
_in_closed(p::Point, s::HyperSphere) = sqrt(sum(abs2, p - s.center)) <= s.r * (1 + 1e-12)

# Index point `x`, or one of its images through periodic edges inside the box `lo:hi`, is in `s`.
function _in_shape(s::HyperSphere, clat, x::NTuple{N, Int}, lo, hi, dims, per) where {N}
    images = ntuple(d -> per[d] ? ((x[d] + dims[d] * cld(lo[d] - x[d], dims[d])):dims[d]:hi[d]) : (x[d]:1:x[d]), Val(N))
    for y in Iterators.product(images...)
        _in_closed(_cart(clat, y), s) && return true
    end
    return false
end

"""
    Center()

A point pattern: the centre of the lattice, the Cartesian point `embed((size(lat) .+ 1) ./ 2)`
(`(20.5, 21.5)` on a 40 × 42 square lattice). Use it as a [`Voronoi`](@ref) generator, alone
or in a vector of `Point`s. A shape's own centre is an explicit `Point`.
"""
struct Center end

"""
    RandomPoints(n; region = <whole lattice>, replace = false, seed)

A point pattern: `n` lattice sites of `region` that lie in the lattice's domain, drawn
uniformly. `region` is a shape (`Circle`, `Sphere`, `HyperSphere`; Cartesian, wrapping
through periodic edges) or a tuple of index ranges. With the region's in-domain sites in
column-major order s₁…sₘ and `rng = Potts.layer_rng(seed)`, each point draws
`i = rand(rng, 1:m)`:

- `replace = false`: the points are distinct; a draw is repeated while sᵢ is already taken,
  and `n > m` throws.
- `replace = true`: point k is sᵢ of its one draw, so points may coincide and `n > m` is
  allowed (TST-style seeding: coinciding seeds merge in [`Eden`](@ref)). The two rules
  draw the same stream, so they agree up to the first repeated site.

The points are in draw order (as a Cartesian `Point` each, see [`Potts.points`](@ref)).
Throws an `ArgumentError` for `n < 0`, a seed outside `0:typemax(UInt64)` and, on a lattice,
`n > m` (without replacement) or `n > 0` with `m = 0`. `remake(p; seed)` redraws;
`remake(p; replace = true)` switches the rule.
"""
struct RandomPoints{R}
    n::Int
    region::R
    seed::UInt64
    replace::Bool
end
function RandomPoints(n::Integer; region = nothing, replace::Bool = false, seed::Integer)
    n >= 0 || throw(ArgumentError("RandomPoints: n must be non-negative, got $n"))
    _check_seed(seed, "RandomPoints")
    return RandomPoints(Int(n), _place_arg(region, "RandomPoints"), UInt64(seed), replace)
end
_layout_args(p::RandomPoints) = (RandomPoints, (:n,), (; p.n, p.region, p.replace, p.seed))

# A point pattern argument: `RandomPoints`, `Center()`, a `Point`, or a non-empty vector of
# `Point`s and `Center()`s (copied).
_pattern_arg(p::Union{RandomPoints, Center}, what) = p
_pattern_arg(p::Point, what) = [_check_point(p, what)]
function _pattern_arg(v::AbstractVector, what)
    isempty(v) && throw(ArgumentError("$what: no generator (the point list is empty)"))
    all(p -> p isa Union{Point, Center}, v) ||
        throw(ArgumentError("$what: a point list holds `Point`s and `Center()`s, got a $(typeof(v))"))
    foreach(p -> p isa Point && _check_point(p, what), v)
    return copy(v)
end

# A generator's coordinates are finite and small enough to round to lattice indices.
function _check_point(p::Point, what)
    all(x -> isfinite(x) && abs(x) < 1e15, p) ||
        throw(ArgumentError("$what: point coordinates must be finite and below 1e15 in magnitude, got $p"))
    return p
end
_pattern_arg(p, what) =
    throw(ArgumentError("$what: $(repr(p)) is not a point pattern (RandomPoints, Center() or a vector of Points)"))

function _draw(p::RandomPoints, lat::LatticeSpec{N}, what) where {N}
    sites, _ = _region_sites(p.region, lat, what)
    m = length(sites)
    rng = layer_rng(p.seed)
    if p.replace                                 # one draw per point, no redraw (D-141)
        (p.n == 0 || m > 0) ||
            throw(ArgumentError("$what: RandomPoints draws $(p.n) sites from a region with no site in the domain"))
        return CartesianIndex{N}[sites[rand(rng, 1:m)] for _ in 1:(p.n)]
    end
    p.n <= m || throw(ArgumentError("$what: RandomPoints asks for $(p.n) distinct sites, the region holds $m in the domain"))
    taken = falses(m)
    out = Vector{CartesianIndex{N}}(undef, p.n)
    for k in 1:(p.n)
        i = rand(rng, 1:m)
        while taken[i]
            i = rand(rng, 1:m)
        end
        taken[i] = true
        out[k] = sites[i]
    end
    return out
end

_center_index(lat) = map(n -> (n + 1) / 2, size(lat))
function _point_index(p::Point{M}, Ei::SMatrix{N, N}, what) where {M, N}
    M == N || throw(ArgumentError("$what: a $(M)D point on a $(N)D lattice"))
    _check_point(p, what)
    return Tuple(Ei * SVector{N, Float64}(p))
end

# The points of a pattern in index coordinates (drawn sites stay exact integers).
_index_points(p::RandomPoints, lat::LatticeSpec{N}, what) where {N} =
    NTuple{N, Float64}[map(Float64, Tuple(x)) for x in _draw(p, lat, what)]
_index_points(::Center, lat::LatticeSpec{N}, what) where {N} = NTuple{N, Float64}[_center_index(lat)]
function _index_points(v::AbstractVector, lat::LatticeSpec{N}, what) where {N}
    Ei = inv(_embedding(core_lattice(lat), Val(N)))
    return NTuple{N, Float64}[p isa Center ? _center_index(lat) : _point_index(p, Ei, what) for p in v]
end

"""
    Potts.points(pattern, x) -> Vector{Point{N, Float64}}

The Cartesian points of a point pattern (`RandomPoints`, `Center()`, or a vector of `Point`s
and `Center()`s) on `x`, anything [`layout`](@ref) takes. A given `Point` is returned as is.
"""
function points(pattern, x)
    lat = _layout_spec(x)
    return _cartesian_points(_pattern_arg(pattern, "points"), lat)
end
function _cartesian_points(p::Union{RandomPoints, Center}, lat::LatticeSpec{N}) where {N}
    clat = core_lattice(lat)
    return Point{N, Float64}[_cart(clat, y) for y in _index_points(p, lat, "points")]
end
function _cartesian_points(v::AbstractVector, lat::LatticeSpec{N}) where {N}
    clat = core_lattice(lat)
    out = Point{N, Float64}[]
    for p in v
        p isa Center && (push!(out, _cart(clat, _center_index(lat))); continue)
        length(p) == N || throw(ArgumentError("points: a $(length(p))D point on a $(N)D lattice"))
        push!(out, Point{N, Float64}(p))
    end
    return out
end

# ---------------------------------------------------------------------------------------------
# Voronoi
# ---------------------------------------------------------------------------------------------

"""
    Voronoi(points; region = <whole lattice>, lloyd = 0, kinds, splits = :warn)

One cell per generator of `points` (`RandomPoints`, `Center()`, or a vector of `Point`s and
`Center()`s), ids in generator order, `kinds` cycled over them. It *fills*: it paints only the
sites of `region` (a shape or a tuple of index ranges) that are in the lattice's domain and
still medium, so earlier layers are never cut (Morpheus' InitVoronoi).

- Each site goes to the nearest generator, Euclidean in the lattice's Cartesian embedding,
  minimum image along periodic axes. Ties, in floating point, go to the lower generator; on
  hexagonal lattices rounding can break exact geometric ties either way.
- `lloyd = k`: k times, every generator that owns a site moves to the centroid of its sites
  (minimum image along periodic axes, Lloyd's algorithm), and the sites are reassigned: a
  centroidal tessellation of compact cells of similar volume.
- Then every cell is made one piece under the geometry's nearest-neighbour steps (the 2N axis
  steps on square lattices, the 6 neighbours on hexagonal ones; wrapping on periodic axes),
  hence under any neighbourhood that contains them: a stray piece joins the neighbouring
  cell whose largest piece it touches most (ties: the lower id), and a cell's largest piece
  never moves.

`Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd = 30, kinds)` with
`ball = Circle(Point(c), r)` is a round aggregate of `n` compact cells (D-063, the former
`VoronoiBall`). The report row has `requested = painted =` the generators, `dropped` those
left with no site and `clipped` the region's points lost to closed edges and the domain.
With a domain, `clipped` depends on whether a region is given: the default (the whole
lattice) is the domain's sites and clips nothing, while an explicit box, even the full
lattice, counts its out-of-domain sites.
Throws an `ArgumentError` for `lloyd < 0`, empty `kinds`, a bad `splits`, no generator, or a
shape or point of another dimension than the lattice. `remake(v; lloyd = …)` works.
"""
struct Voronoi{P, R, K} <: AbstractLayout
    points::P
    region::R
    lloyd::Int
    kinds::Vector{K}
    splits::Symbol
end
function Voronoi(points; region = nothing, lloyd::Integer = 0, kinds, splits::Symbol = :warn)
    lloyd >= 0 || throw(ArgumentError("Voronoi: lloyd must be non-negative, got $lloyd"))
    return Voronoi(_pattern_arg(points, "Voronoi"), _place_arg(region, "Voronoi"), Int(lloyd), _kinds_arg(kinds, "Voronoi"),
        _splits_arg(splits, "Voronoi"))
end
_splits(l::Voronoi) = l.splits
_layout_args(l::Voronoi) = (Voronoi, (:points,), (; l.points, l.region, l.lloyd, l.kinds, l.splits))

function paint!(op::LayoutState, l::Voronoi, lat)
    region, clipped = _region_sites(l.region, lat, "Voronoi")
    gens = _index_points(l.points, lat, "Voronoi")
    isempty(gens) && throw(ArgumentError("Voronoi: no generator (the point pattern is empty)"))
    sites = filter(x -> owner(op, x) == 0, region)          # fill medium only
    owners = _voronoi!(gens, sites, lat, l.lloyd)
    n = length(gens)
    ids = [new_cell!(op, l.kinds[mod1(k, length(l.kinds))]) for k in 1:n]
    for (i, x) in enumerate(sites)
        assign!(op, x, ids[owners[i]])
    end
    record!(op; requested = n, painted = n, clipped)
    return nothing
end

# The generator owning each of `sites` after `lloyd` centroid moves and the one-piece repair.
# `gens` (index coordinates) is moved in place.
function _voronoi!(gens::Vector{NTuple{N, Float64}}, sites::Vector{CartesianIndex{N}}, lat, lloyd) where {N}
    m, n = length(sites), length(gens)
    owner = zeros(Int, m)
    m == 0 && return owner
    clat = core_lattice(lat)
    dims = size(lat)
    per = _periodic(lat)
    index = zeros(Int, dims)                     # site => its position in `sites` (0: not painted here)
    for (i, x) in enumerate(sites)
        index[x] = i
    end
    scale = _box_scale(inv(_embedding(clat, Val(N))))
    best = zeros(m)
    image = Vector{NTuple{N, Int}}(undef, m)     # the period shift of the image nearest the owner
    sums, counts = zeros(N, n), zeros(Int, n)
    h = 2.0 * (m / n)^(1 / N)                     # about two cell radii (any h is exact)
    for _ in 1:lloyd
        h = _voronoi_assign!(owner, best, image, index, gens, clat, per, scale, h)
        h = max(1.0, 1.25sqrt(maximum(best)))    # the next pass starts near the need
        fill!(sums, 0.0)
        fill!(counts, 0)
        for (i, x) in enumerate(sites)
            k = owner[i]
            counts[k] += 1
            for d in 1:N
                sums[d, k] += x[d] + image[i][d]
            end
        end
        for k in 1:n
            counts[k] > 0 && (gens[k] = ntuple(d -> _wrap_coord(sums[d, k] / counts[k], dims[d], per[d]), Val(N)))
        end
    end
    _voronoi_assign!(owner, best, image, index, gens, clat, per, scale, h)
    _connect_pieces!(owner, sites, index, n, _nearest_steps(clat, Val(N)), per)
    return owner
end

# A coordinate moved back into [½, n + ½) on a periodic axis (unchanged when already inside).
_wrap_coord(g, n, periodic) = periodic && !(0.5 <= g < n + 0.5) ? g - n * fld(g - 0.5, n) : g

# Nearest generator of every site. Each generator scans the index box that holds its
# Cartesian `h`-ball (`_box_scale`, plus ½ for rounding its position), wrapping on periodic
# axes, so every image within `h` is seen. A site whose nearest scanned generator lies within
# `h` has found its true nearest one; otherwise `h` doubles. Ties go to the lower generator.
# Exact for any `h`; returns the `h` that sufficed.
function _voronoi_assign!(owner, best, image, index::Array{Int, N}, gens, clat, per, scale, h) where {N}
    dims = size(index)
    while true
        fill!(owner, 0)
        fill!(best, Inf)
        hh = h                                   # not captured while reassigned (no box)
        w = map(s -> ceil(Int, hh * s + 0.5), scale)
        for (k, g) in enumerate(gens)
            c = map(x -> round(Int, x), g)
            box = CartesianIndices(ntuple(d -> per[d] ? ((c[d] - w[d]):(c[d] + w[d])) :
                                               (max(1, c[d] - w[d]):min(dims[d], c[d] + w[d])), Val(N)))
            for y in box
                x = ntuple(d -> per[d] ? mod1(y[d], dims[d]) : y[d], Val(N))
                i = index[x...]
                i == 0 && continue
                d2 = sum(abs2, embed(clat, map((a, b) -> Float64(a) - b, Tuple(y), g)))
                if d2 < best[i]
                    best[i], owner[i], image[i] = d2, k, map(-, Tuple(y), x)
                end
            end
        end
        maximum(best) <= h^2 && return h
        h *= 2
    end
end

# The nearest-neighbour steps of the geometry: the offsets in {-1, 0, 1}ᴺ of shortest
# embedded length (2N axis steps on square lattices, 6 on hexagonal ones).
function _nearest_steps(clat, ::Val{N}) where {N}
    offs = [o for o in Iterators.product(ntuple(_ -> -1:1, Val(N))...) if any(!=(0), o)]
    len = [sum(abs2, embed(clat, map(Float64, o))) for o in offs]
    return offs[len .<= minimum(len) + 1e-9]
end

# The position in `sites` of the site one step `o` from `x` (wrapping on periodic axes; 0 off
# the lattice or not painted by this layer).
function _step_index(index::Array{Int, N}, x::CartesianIndex{N}, o, per) where {N}
    y = ntuple(d -> per[d] ? mod1(x[d] + o[d], size(index, d)) : x[d] + o[d], Val(N))
    checkbounds(Bool, index, y...) || return 0
    return index[y...]
end

# Make every cell one piece under the nearest-neighbour `steps` (D-063). Each pass labels the
# pieces. A piece that is not its cell's largest (a stray piece) and touches the largest piece
# of another cell goes to the cell whose largest piece it shares the most bonds with (ties:
# the lower id). If no stray piece touches a largest piece, the lowest stray piece goes to the
# neighbouring cell it shares the most bonds with. Either move lowers the number of stray
# sites or pieces and never splits a cell, so the loop ends. A stray piece with no
# neighbouring cell (a region split by the domain) stays.
function _connect_pieces!(owner, sites, index, n, steps, per)
    m = length(sites)
    piece = zeros(Int, m)
    stack = Int[]
    sizes, cellof, main = Int[], Int[], zeros(Int, n)
    bonds = Dict{Tuple{Int, Int}, Int}()          # (stray piece, cell) => bonds
    tomain = Dict{Tuple{Int, Int}, Int}()         # … with that cell's largest piece only
    while true
        fill!(piece, 0)
        empty!(sizes)
        empty!(cellof)
        for i in 1:m
            piece[i] == 0 || continue
            push!(sizes, 0)
            push!(cellof, owner[i])
            p = length(sizes)
            piece[i] = p
            push!(stack, i)
            while !isempty(stack)
                j = pop!(stack)
                sizes[p] += 1
                for o in steps
                    k = _step_index(index, sites[j], o, per)
                    (k != 0 && piece[k] == 0 && owner[k] == owner[j]) || continue
                    piece[k] = p
                    push!(stack, k)
                end
            end
        end
        fill!(main, 0)
        for p in eachindex(sizes)
            g = cellof[p]
            (main[g] == 0 || sizes[p] > sizes[main[g]]) && (main[g] = p)
        end
        any(p -> main[cellof[p]] != p, eachindex(sizes)) || return nothing
        empty!(bonds)
        empty!(tomain)
        for i in 1:m
            p = piece[i]
            main[cellof[p]] == p && continue
            for o in steps
                k = _step_index(index, sites[i], o, per)
                (k != 0 && owner[k] != owner[i]) || continue
                key = (p, owner[k])
                bonds[key] = get(bonds, key, 0) + 1
                main[owner[k]] == piece[k] && (tomain[key] = get(tomain, key, 0) + 1)
            end
        end
        isempty(bonds) && return nothing
        moves = isempty(tomain) ? _best_cells(bonds, minimum(first, keys(bonds))) : _best_cells(tomain, 0)
        for i in 1:m
            g = get(moves, piece[i], 0)
            g == 0 || (owner[i] = g)
        end
    end
end

# piece => the cell it shares the most bonds with (ties: the lower id), for every piece in
# `counts`, or for piece `only` alone when `only > 0`.
function _best_cells(counts::Dict{Tuple{Int, Int}, Int}, only::Int)
    best = Dict{Int, Tuple{Int, Int}}()           # piece => (bonds, cell)
    for ((p, g), b) in counts
        (only == 0 || p == only) || continue
        bb, gg = get(best, p, (0, 0))
        (b > bb || (b == bb && g < gg)) && (best[p] = (b, g))
    end
    return Dict(p => g for (p, (_, g)) in best)
end

# ---------------------------------------------------------------------------------------------
# shortfall (D-141)
# ---------------------------------------------------------------------------------------------

function _shortfall_arg(s, what)
    s in (:error, :warn, :allow) ||
        throw(ArgumentError("$what: `shortfall` must be :error, :warn or :allow, got $(repr(s))"))
    return s
end

# A layer that painted fewer cells than it was asked for, at the end of its own paint.
function _shortfall!(mode::Symbol, what, requested, painted)
    painted < requested || return nothing
    mode === :allow && return nothing
    msg = "$what: shortfall: $requested cells requested, $painted painted; pass `shortfall = :allow` to accept fewer"
    mode === :error && throw(ArgumentError(msg))
    @warn msg
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Eden (D-141)
# ---------------------------------------------------------------------------------------------

"""
    Eden(points; rounds, region = <whole lattice>, kinds, seed, neighborhood = nothing,
         shortfall = :error, splits = :warn)

Seed-and-grow (TST's `GrowInCells`): one-site cells at `points`, grown by `rounds` rounds of
synchronous random (Eden) growth into the medium.

- **Seeding.** `points` is a point pattern as for [`Voronoi`](@ref) (`RandomPoints`,
  `Center()`, a `Point`, or a vector of `Point`s and `Center()`s). Each point is mapped to
  lattice indices and rounded half up, `floor(xᵢ + 1/2)` (so `Center()` on 200² is site
  (101, 101), TST's `sizex/2`), wrapping along periodic axes. In point order, a point whose
  site is on the lattice, in `region` ∩ domain and still medium becomes a new one-site cell;
  any other point is not placed, so coinciding points merge (the first one wins). `kinds` is
  cycled over the cells created; ids follow creation order.
- **Growth.** Each round visits the medium sites of `region` ∩ domain in column-major order.
  A site with a neighbour (under `neighborhood`, default the lattice's own) owned by a cell
  of this layer at the start of the round draws one neighbour uniformly, `j = rand(rng,
  1:K)` over the `K` offsets of `CorePotts.relation`, with one `rng =
  Potts.layer_rng(seed, :eden)` for the whole layer; if that neighbour is a cell of this
  layer at the start of the round, the site joins it at the end of the round. This is TST's
  law (every medium site draws one of its neighbours and copies it only from a growing
  cell); sites with no growing neighbour cannot change, so they draw nothing. TST grows
  with 8 neighbours even on a lattice with a larger neighbourhood: pass `neighborhood =
  Moore(1)` there.

Eden only fills: it never paints a site an earlier layer owns, nor outside `region` (a box
of ranges or a shape) or the domain. Each cell grows from one site, so it is one piece under
`neighborhood`.

The report row has `requested` = the points, `painted` = the cells created, `misses` = the
points not placed, and `clipped` as for `Voronoi`. When fewer cells are painted than
requested, `shortfall = :error` (the default) throws, `:warn` warns and `:allow` accepts
it (seeds drawn with replacement merge by design: `RandomPoints(n; replace = true)`).

Throws an `ArgumentError` for `rounds < 0`, empty `kinds`, a bad seed, `shortfall` or
`splits`, a `neighborhood` that is not a relation spec such as `Moore(1)`, an empty point
list and (at layout) a point or shape of another dimension. `remake(e; rounds = …)` works.

```julia
# TST's de novo vasculogenesis start: 360 seeds with replacement, 10 rounds
overlay(Frame(:border), Eden(RandomPoints(360; region = (2:199, 2:199), replace = true, seed = 1);
    rounds = 10, kinds = [:endothelial], seed = 1, shortfall = :allow))
```
"""
struct Eden{P, R, K, H} <: AbstractLayout
    points::P
    region::R
    rounds::Int
    kinds::Vector{K}
    seed::UInt64
    neighborhood::H
    shortfall::Symbol
    splits::Symbol
end
function Eden(points; rounds::Integer, region = nothing, kinds, seed::Integer, neighborhood = nothing,
        shortfall::Symbol = :error, splits::Symbol = :warn)
    rounds >= 0 || throw(ArgumentError("Eden: rounds must be non-negative, got $rounds"))
    _check_seed(seed, "Eden")
    (neighborhood === nothing || neighborhood isa CorePotts.RelationSpec) ||
        throw(ArgumentError("Eden: `neighborhood` must be a relation spec such as Moore(1), got $(repr(neighborhood))"))
    return Eden(_pattern_arg(points, "Eden"), _place_arg(region, "Eden"), Int(rounds), _kinds_arg(kinds, "Eden"),
        UInt64(seed), neighborhood, _shortfall_arg(shortfall, "Eden"), _splits_arg(splits, "Eden"))
end
_splits(l::Eden) = l.splits

function paint!(op::LayoutState, l::Eden, lat)
    region, clipped = _region_sites(l.region, lat, "Eden")
    pts = _index_points(l.points, lat, "Eden")
    n = length(pts)
    placed = _eden!(op, l, lat, region, pts)
    record!(op; requested = n, painted = placed, misses = n - placed, clipped)
    _shortfall!(l.shortfall, "Eden", n, placed)
    return nothing
end

function _eden!(op::LayoutState{N}, l::Eden, lat::LatticeSpec{N}, region::Vector{CartesianIndex{N}},
        pts::Vector{NTuple{N, Float64}}) where {N}
    dims = size(lat)
    per = _periodic(lat)
    σ = op.σ
    allowed = falses(dims)                       # region ∩ domain
    for x in region
        allowed[x] = true
    end
    lo = ncells(op) + 1                          # this layer's cells are lo:ncells(op)
    placed = 0
    for p in pts
        r = ntuple(d -> floor(Int, p[d] + 0.5), Val(N))      # rounded half up
        x = ntuple(d -> per[d] ? mod1(r[d], dims[d]) : r[d], Val(N))
        checkbounds(Bool, σ, x...) || continue
        (allowed[x...] && σ[x...] == 0) || continue
        placed += 1
        assign!(op, x, new_cell!(op, l.kinds[mod1(placed, length(l.kinds))]))
    end
    (l.rounds == 0 || placed == 0) && return placed
    clat = core_lattice(lat)
    spec = l.neighborhood === nothing ? lat.neighborhood : l.neighborhood
    # a vector: the offset count is a runtime value (a tuple of them would not infer)
    offs = collect(NTuple{N, Int32}, CorePotts.relation(spec, clat).offsets)
    _eden_grow!(op, l, clat, offs, allowed, lo)
    return placed
end

# `rounds` synchronous growth rounds of the cells `lo:ncells(op)` under the offsets `offs`.
function _eden_grow!(op::LayoutState{N}, l::Eden, clat, offs, allowed, lo) where {N}
    σ = op.σ
    back = map(o -> map(-, o), offs)             # x with shift(x, o) = s is shift(s, -o)
    K = length(offs)
    rng = layer_rng(l.seed, :eden)
    ci = CartesianIndices(σ)
    # Candidates: medium sites that may have a growing neighbour (a superset of the
    # frontier). A site leaves when it is painted or found with no growing neighbour, and
    # re-enters when a neighbour is painted, so every eligible site of a round is a candidate.
    cand = Int[]
    incand = falses(size(σ))
    for s in eachindex(σ)
        σ[s] >= lo && _eden_enqueue!(cand, incand, s, allowed, σ, clat, back)
    end
    joins = Tuple{Int, Int32}[]
    keep = Int[]
    for _ in 1:(l.rounds)
        sort!(cand)                              # column-major, the order of the draws
        empty!(joins)
        empty!(keep)
        for k in cand
            x = Tuple(ci[k])
            front = false
            for o in offs
                inside, y = CorePotts.shift(clat, x, o)
                (inside && σ[y...] >= lo) && (front = true; break)
            end
            if !front
                incand[k] = false
                continue
            end
            push!(keep, k)
            inside, y = CorePotts.shift(clat, x, offs[rand(rng, 1:K)])
            c = σ[y...]
            inside && c >= lo && push!(joins, (k, c))
        end
        empty!(cand)
        append!(cand, keep)
        isempty(joins) && continue
        for (k, c) in joins                      # the round's end: σ was read as it started
            assign!(op, ci[k], c)
            incand[k] = false
        end
        filter!(k -> σ[k] == 0, cand)
        for (k, _) in joins
            _eden_enqueue!(cand, incand, k, allowed, σ, clat, back)
        end
    end
    return nothing
end

# Add the medium sites of region ∩ domain that have site `s` as a neighbour to the candidates.
function _eden_enqueue!(cand, incand, s, allowed, σ::Array{Int32, N}, clat, back) where {N}
    li, ci = LinearIndices(σ), CartesianIndices(σ)
    for o in back
        inside, y = CorePotts.shift(clat, Tuple(ci[s]), o)
        inside || continue
        k = li[y...]
        (allowed[k] && σ[k] == 0 && !incand[k]) || continue
        incand[k] = true
        push!(cand, k)
    end
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Splits (D-141)
# ---------------------------------------------------------------------------------------------

"""
    Splits(layer, k; shortfall = :error, splits = :warn)

`layer`, with each of its cells divided `k` times (`0 ≤ k ≤ 30`) on the host before the
simulation starts (TST's `DivideCells`): k passes, each cutting every cell of this layer
with at least 2 sites in two across its long axis. It is not the simulation's division
routine (no state, no trackers); it shares only the cut geometry with
`CorePotts.AlongMinorAxis`.

- Pass j visits the layer's cells in id order as they stand at the start of the pass; the
  daughter of each cut is a new cell of the mother's kind, allocated right after the cut.
  Cells of earlier layers are never touched.
- The cut: sites in Cartesian coordinates (`embed`), unwrapped along periodic axes to the
  image nearest the cell's first site in column-major order; `c` the centroid, `v` the unit
  eigenvector of the largest eigenvalue of `C = Σ (p − c)(p − c)ᵀ` (in 2D by
  `AlongMinorAxis`' rule; for a repeated largest eigenvalue, the first standard axis
  projected onto its eigenspace), its first nonzero component positive. The daughter takes
  the sites with `(p − c)·v > 0`; sites on the plane (up to a relative 1e-9 of the cell's
  largest `|(p − c)·v|`) stay with the mother. A cell spanning more than half a periodic axis
  is unwrapped relative to its first site all the same, so its cut can be torn into pieces
  (deterministically).
- After the passes, every cell of this layer that is not one piece under the lattice
  neighbourhood (whether a cut or `layer` itself left it so) counts once in the report row's
  `splits` and, under `splits = :warn`, `layout` names it, by its id in the result, in a
  warning; `splits = :allow` silences the warning, not the count.

The report row (one row for `Splits` and its `layer`) has `requested` = m·2ᵏ, m the cells of
`layer` that own a site, `painted` = the cells owning a site after the passes, `misses` =
their difference and the inner layer's `clipped`. A one-site cell cannot be cut, so fewer
cells than requested is a shortfall: `shortfall = :error` (the default) throws, `:warn`
warns, `:allow` accepts it. Throws an `ArgumentError` for `k` outside `0:30` or a bad
`shortfall` or `splits`. `remake(s; k = …)` works.

```julia
# TST's sprout start: one Eden blob of 50 rounds at the centre, divided 7 times (128 cells)
overlay(Frame(:border), Splits(Eden(Center(); rounds = 50, kinds = [:endothelial], seed = 1), 7; splits = :allow))
```
"""
struct Splits{L <: AbstractLayout} <: AbstractLayout
    layer::L
    k::Int
    shortfall::Symbol
    splits::Symbol
end
function Splits(layer::AbstractLayout, k::Integer; shortfall::Symbol = :error, splits::Symbol = :warn)
    0 <= k <= 30 || throw(ArgumentError("Splits: k must be in 0:30, got $k"))
    return Splits(layer, Int(k), _shortfall_arg(shortfall, "Splits"), _splits_arg(splits, "Splits"))
end
_splits(l::Splits) = l.splits

function paint!(op::LayoutState{N}, l::Splits, lat::LatticeSpec{N}) where {N}
    lo = ncells(op) + 1
    paint!(op, l.layer, lat)                     # into this row (a delegating layer, D-091)
    clipped = op.rows[op.layer].clipped
    sites = [CartesianIndex{N}[] for _ in lo:ncells(op)]
    for x in CartesianIndices(op.σ)
        c = op.σ[x]
        c >= lo && push!(sites[c - lo + 1], x)
    end
    m = count(!isempty, sites)
    clat = core_lattice(lat)
    dims, per = size(lat), _periodic(lat)
    P = NTuple{N, Float64}[]
    for _ in 1:(l.k), c in lo:ncells(op)        # the range is fixed at the pass's start
        S = sites[c - lo + 1]
        length(S) >= 2 || continue
        _split_points!(P, S, clat, dims, per)
        cen, v = _split_axis(P)
        side = _daughter_side(P, cen, v)
        any(side) || continue
        daughter = S[side]
        deleteat!(S, side)
        id = new_cell!(op, kindof(op, c))
        push!(sites, daughter)
        for x in daughter
            assign!(op, x, id)
        end
    end
    painted = count(!isempty, sites)
    requested = m << l.k
    check = falses(ncells(op))
    for c in lo:ncells(op)
        check[c] = length(sites[c - lo + 1]) > 1
    end
    # an inner Splits shares this row: its findings for these cells are superseded
    filter!(q -> q[1] < lo, op.pieces)
    warn, row = l.splits === :warn, op.layer
    _disconnected(op.σ, check, lat) do c
        push!(op.pieces, (c, row, warn))         # counted and warned by `layout` (final ids)
    end
    record!(op; requested, painted, misses = requested - painted, clipped)
    _shortfall!(l.shortfall, "Splits", requested, painted)
    return nothing
end

# The daughter's sites: (p − c)·v > 0, where "0" is relative to the largest |(p − c)·v| of the
# cell (1e-9): an inexact centroid and axis turn a site exactly on the plane into ±1e-16,
# and it must stay with the mother.
function _daughter_side(P, cen, v)
    d = [_dot_from(p, cen, v) for p in P]
    tol = 1e-9 * maximum(abs, d)
    return [x > tol for x in d]
end

_dot_from(p::NTuple{N, Float64}, c::NTuple{N, Float64}, v::NTuple{N, Float64}) where {N} =
    sum(d -> (p[d] - c[d]) * v[d], 1:N)

# The Cartesian positions of a cell's sites `S`, each unwrapped along periodic axes to the
# image nearest `S[1]` (displacement in [-n/2, n/2): ties to the lower image).
function _split_points!(P::Vector{NTuple{N, Float64}}, S::Vector{CartesianIndex{N}}, clat, dims, per) where {N}
    empty!(P)
    x0 = Tuple(S[1])
    for s in S
        u = ntuple(Val(N)) do d
            δ = s[d] - x0[d]
            h = fld(dims[d], 2)
            Float64(x0[d] + (per[d] ? mod(δ + h, dims[d]) - h : δ))
        end
        push!(P, NTuple{N, Float64}(embed(clat, u)))
    end
    return P
end

# The centroid of `P` and the unit eigenvector of the largest eigenvalue of its scatter
# matrix, sign-fixed (the first component of magnitude > 1e-9 is positive).
function _split_axis(P::Vector{NTuple{N, Float64}}) where {N}
    c = ntuple(d -> sum(p -> p[d], P) / length(P), Val(N))
    C = zeros(N, N)
    for p in P, i in 1:N, j in 1:N
        C[i, j] += (p[i] - c[i]) * (p[j] - c[j])
    end
    v = N == 2 ? _major_axis_2d(C) : _major_axis(C)
    v ./= sqrt(sum(abs2, v))
    f = findfirst(x -> abs(x) > 1e-9, v)
    f !== nothing && v[f] < 0 && (v .*= -1)
    return c, ntuple(d -> v[d], Val(N))
end

# CorePotts' 2D `AlongMinorAxis` rule: (λ − C₂₂, C₁₂), or the larger diagonal's axis (e₁ on a
# tie) when C₁₂ vanishes.
function _major_axis_2d(C)
    a, b, d = C[1, 1], C[1, 2], C[2, 2]
    λ = (a + d) / 2 + sqrt(((a - d) / 2)^2 + b^2)
    return abs(b) > eps() * (abs(a) + abs(d)) ? [λ - d, b] : (a >= d ? [1.0, 0.0] : [0.0, 1.0])
end

# Any dimension: the top eigenvector; for a repeated top eigenvalue, the first standard axis
# with a nonzero projection on its eigenspace, projected onto it.
function _major_axis(C)
    N = size(C, 1)
    E = eigen(Symmetric(C))
    λ = E.values                                 # ascending
    tied = findall(x -> λ[end] - x <= 1e-9 * max(λ[end], 1e-300), λ)
    length(tied) == 1 && return E.vectors[:, end]
    B = E.vectors[:, tied]
    for e in 1:N
        u = B * B[e, :]                          # the projection of eₑ onto span(B)
        sqrt(sum(abs2, u)) > 1e-6 && return u
    end
    return E.vectors[:, end]
end

# ---------------------------------------------------------------------------------------------
# remake
# ---------------------------------------------------------------------------------------------

# The keyword constructor of a layer, the names of its positional arguments, and every
# argument (positional and keyword) as it would be passed.
_layout_args(l::Tiling) = (Tiling, (:size,), (; l.size, l.spacing, l.region, l.kinds, l.partial, l.splits))
_layout_args(l::Scattered) = (Scattered, (:n, :size), (; l.n, l.size, l.region, l.kinds, l.seed, l.gap, l.splits))
_layout_args(l::Frame) = (Frame, (:kind,), (; l.kind, l.width, l.splits))
_layout_args(l::InsertUntil) = (InsertUntil, (:kind,), (; l.kind, l.into, l.fraction,
    number = l.number >= 0 ? l.number : nothing, l.seed, l.region, misses = l.count_misses ? :count : :retry, l.splits))
_layout_args(l::Eden) = (Eden, (:points,), (; l.points, l.region, l.rounds, l.kinds, l.seed, l.neighborhood, l.shortfall, l.splits))
_layout_args(l::Splits) = (Splits, (:layer, :k), (; l.layer, l.k, l.shortfall, l.splits))
_layout_args(l::AbstractLayout) =
    throw(ArgumentError("remake: $(nameof(typeof(l))) does not support remake (no keyword constructor is known)"))

function SciMLBase.remake(l::Union{AbstractLayout, RandomPoints}; kw...)
    ctor, pos, args = _layout_args(l)
    for k in keys(kw)
        haskey(args, k) || throw(ArgumentError("remake: $(nameof(typeof(l))) has no argument `$k`"))
    end
    merged = merge(args, values(kw))
    return ctor(map(k -> merged[k], pos)...; (k => merged[k] for k in keys(merged) if !(k in pos))...)
end

# ---------------------------------------------------------------------------------------------
# overlay
# ---------------------------------------------------------------------------------------------

# The layers of `overlay`, flattened.
struct Overlay <: AbstractLayout
    layers::Vector{AbstractLayout}
end

"""
    overlay(layers...)

Layers painted in order: later layers overwrite earlier ones, and cell ids follow layer
order. Cells left with no site are dropped (ids stay consecutive); a partly covered cell
keeps its remaining sites, which may fall apart into pieces. `layout` warns, naming the
cell, when later layers split a cell into pieces that are not connected under the lattice
neighbourhood, unless every layer that cut that cell has `splits = :allow`. Nested overlays
are flattened, so each leaf layer is one row of the layout report.
"""
function overlay(layers::AbstractLayout...)
    flat = AbstractLayout[]
    for l in layers
        l isa Overlay ? append!(flat, l.layers) : push!(flat, l)
    end
    return Overlay(flat)
end

# At the top of a layout every child is a leaf layer with its own report row; inside a leaf
# (a custom layer painting an overlay) the children paint into that leaf.
function paint!(op::LayoutState, l::Overlay, lat)
    for x in l.layers
        op.layer == 0 ? _paint_leaf!(op, x, lat) : paint!(op, x, lat)
    end
    return nothing
end

_paint_leaf!(op::LayoutState, l::Overlay, lat) = paint!(op, l, lat)
function _paint_leaf!(op::LayoutState, l::AbstractLayout, lat)
    base = ncells(op)
    push!(op.rows, _LayerRow(nameof(typeof(l)), base + 1, base, 0, 0, 0, 0, false, 0, 0))
    # the per-cell cut records cover the cells a leaf can cut: those before it
    n = length(op.cutby)
    resize!(op.cutby, base)
    resize!(op.cutwarn, base)
    if base > n
        fill!(view(op.cutby, (n + 1):base), 0)
        fill!(view(op.cutwarn, (n + 1):base), false)
    end
    op.layer, op.base, op.warn = length(op.rows), base, _splits(l) === :warn
    paint!(op, l, lat)
    r = op.rows[op.layer]
    r.last = ncells(op)
    if !r.recorded
        r.requested = r.painted = r.counted = r.last - base
    end
    op.layer = 0
    return nothing
end

# ---------------------------------------------------------------------------------------------
# The split check
# ---------------------------------------------------------------------------------------------

# Call `f(c)` for every cell `c` with `check[c]` (a vector over the cells, `true` for at most
# the cut ones) whose sites are not connected under the lattice neighbourhood, in id order.
# One pass records each candidate's first site, site count and bounding box in dense
# per-cell buffers; a cell that is still a full box is connected (every neighbourhood holds
# the unit axis steps) and skipped; the rest are flood-filled, stamping `visited` with the
# cell id so it never needs a reset. O(sites). `visited` (lattice-sized) is allocated only
# when the first cell needs a flood fill.
function _disconnected(f::F, σ::AbstractArray{<:Integer, N}, check, lat::LatticeSpec{N}) where {F, N}
    K = length(check)
    first_site = zeros(Int, K)
    ncount = zeros(Int, K)
    lo = fill(ntuple(_ -> typemax(Int), N), K)
    hi = fill(ntuple(_ -> typemin(Int), N), K)
    ci = CartesianIndices(σ)
    for i in eachindex(σ)
        c = σ[i]
        (c > 0 && check[c]) || continue
        ncount[c] == 0 && (first_site[c] = i)
        ncount[c] += 1
        x = Tuple(ci[i])
        lo[c] = min.(lo[c], x)
        hi[c] = max.(hi[c], x)
    end
    clat = core_lattice(lat)
    offs = CorePotts.relation(lat.neighborhood, clat).offsets
    units = all(d -> all(s -> ntuple(k -> Int32(k == d ? s : 0), N) in offs, (-1, 1)), 1:N)
    visited = Array{Int32, N}(undef, ntuple(_ -> 0, N))    # lazily lattice-sized
    stack = Int[]
    li = LinearIndices(σ)
    for c in 1:K
        (check[c] && ncount[c] > 0) || continue
        units && ncount[c] == prod(hi[c] .- lo[c] .+ 1) && continue      # still a box
        isempty(visited) && (visited = zeros(Int32, size(σ)))
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
        reached < ncount[c] && f(c)
    end
    return nothing
end

# The split cells of the paint: warn for those some :warn layer cut, and (for the report)
# count those cut by one layer only against that layer. Nothing to do when no cut cell
# could warn and no report is asked for.
function _check_splits!(op::LayoutState, lat::LatticeSpec, counts, report::Bool)
    cutby, cutwarn = op.cutby, op.cutwarn
    warned = falses(length(counts))
    any(!=(0), cutby) || return warned         # no cell was cut
    check = falses(length(counts))              # cells of the last leaf were never cut
    for c in eachindex(cutby)
        check[c] = cutby[c] != 0 && counts[c] > 0 && (cutwarn[c] || (report && cutby[c] > 0))
    end
    any(check) || return warned
    _disconnected(op.σ, check, lat) do c
        if cutwarn[c]
            warned[c] = true
            @warn "layout: later layers split cell $(_final_id(counts, c)) (kind $(op.kinds[c])) into disconnected pieces"
        end
        report && cutby[c] > 0 && (op.rows[cutby[c]].splits += 1)
    end
    return warned
end

# The id of paint cell `c` in the returned σ (cells with no site are dropped).
_final_id(counts, c) = count(>(0), view(counts, 1:c))

# The cells a `Splits` left in pieces at the end of its paint: counted in its row, and
# warned (under `splits = :warn`, by their final id) unless dropped later or already named by
# the split warning above.
function _report_pieces!(op::LayoutState, counts, warned)
    for (c, row, warn) in op.pieces
        op.rows[row].splits += 1
        (warn && counts[c] > 0 && !warned[c]) || continue
        @warn "layout: cell $(_final_id(counts, c)) (kind $(op.kinds[c])) of a Splits layer is not one piece " *
              "(pass `splits = :allow` to that Splits to accept it)"
    end
    return nothing
end

# ---------------------------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------------------------

const _LayoutTarget = Union{Tuple{Vararg{Integer}}, Lattice, LatticeSpec, PottsSystem, CompiledPottsSystem}

"""
    layout(l, x; report = false) -> [ownership => σ, kind => kinds]
    layout(l, x; report = true) -> ([ownership => σ, kind => kinds], report)

Paint the layout `l` (see [`overlay`](@ref)) on an empty lattice and return an operating
point for `PottsProblem`: `σ` is an `Int32` array (0 = medium).

`x` is a `dims` tuple, meaning a closed square lattice with the `Moore(1)` neighbourhood. For
a hexagonal, periodic, domain-restricted or non-Moore lattice pass the `PottsSystem` (or
`CompiledPottsSystem`), whose boundaries, neighbourhood, domain and geometry the layouts
use; a CorePotts `Lattice` carries boundaries, domain and geometry but no neighbourhood,
so `Moore(1)` is assumed (it only matters for split cells). On a lattice with a domain, no
cell may cover a site outside it.

With `report = true` it also returns one row per leaf layer, in paint order (an `overlay`
contributes its flattened leaves), with the properties

- `layer`: the leaf's position; `type`: `nameof` of its type (`:Tiling`, `:InsertUntil`, …);
- `requested`: `Tiling` the boxes placed, `Scattered` `n`, `Frame` 1, `InsertUntil` its
  `number` (`counted` under a `fraction` rule), `Voronoi` and `Eden` their points, `Splits`
  m·2ᵏ (m the inner layer's cells), a custom layer what it passed to [`record!`](@ref);
- `painted`: the cells the layer created; `dropped`: of those, the cells left with no site
  after the whole layout;
- `misses`: `InsertUntil` the missed draws (in both `misses` modes), `Eden` and `Splits`
  `requested − painted` (their shortfall), a custom layer its `record!` value, other layers 0;
- `counted`: `InsertUntil` what its stop rule counted (`painted`, plus `misses` under
  `misses = :count`), other layers `painted`;
- `clipped`: `Voronoi` and `Eden` (and a `Splits` of them) the points of its region (a shape or a box) that are not in-domain
  lattice sites, lost to closed edges and to the domain (nothing is lost through a periodic
  edge: a shape wraps); sites it skipped because an earlier layer owns them are not clipped.
  A custom layer its `record!` value, other layers 0;
- `splits`: the cells cut only by this layer (it took at least one of their sites) whose
  remaining sites are disconnected after the whole layout, whatever its `splits` setting;
  for `Splits`, plus its own cells left in pieces by its divisions.
"""
function layout(l::AbstractLayout, x::_LayoutTarget; report::Bool = false)
    lat = _layout_spec(x)
    _check_layout_kinds(x, _layer_kinds(l))                # before painting: `into` is never painted
    op = LayoutState(lat.dims)
    _paint_leaf!(op, l, lat)
    σ, kinds = op.σ, op.kinds
    _check_layout_kinds(x, kinds)                          # custom layers' kinds
    counts = zeros(Int, length(kinds))
    for s in σ
        s > 0 && (counts[s] += 1)
    end
    warned = _check_splits!(op, lat, counts, report)
    _report_pieces!(op, counts, warned)
    mask = lat.domain
    if mask !== nothing
        bad = findfirst(i -> σ[i] != 0 && !mask[i], CartesianIndices(σ))
        bad === nothing ||
            throw(ArgumentError("layout: cell $(σ[bad]) covers site $(Tuple(bad)), outside the lattice domain"))
    end
    rows = report ? [(; layer = j, r.type, r.requested, r.painted, dropped = count(c -> counts[c] == 0, r.first:r.last),
                         r.misses, r.counted, r.clipped, r.splits) for (j, r) in enumerate(op.rows)] : nothing
    σc, kindsc = _compact(σ, kinds, counts)
    point = [ownership => σc, kind => identity.(kindsc)]
    return report ? (point, rows) : point
end

# The kind names a layout's built-in layers name (cell kinds and `InsertUntil` hosts).
_layer_kinds(l::AbstractLayout) = ()
_layer_kinds(l::Overlay) = Any[k for x in l.layers for k in _layer_kinds(x)]
_layer_kinds(l::Union{Tiling, Scattered, Voronoi, Eden}) = l.kinds
_layer_kinds(l::Splits) = _layer_kinds(l.layer)
_layer_kinds(l::Frame) = (l.kind,)
_layer_kinds(l::InsertUntil) = Any[l.kind; l.into]

# Against a model, a layout's kind names may not be its kind classes (D-135): a class would
# never match a cell's kind (`InsertUntil(into = [g])` would silently miss). Names that are
# not the model's kinds pass here (a model may serve as a lattice only); `PottsProblem`
# rejects them in the operating point.
_check_layout_kinds(x, kinds) = nothing
_check_layout_kinds(c::CompiledPottsSystem, kinds) = _check_layout_kinds(c.sys, kinds)
function _check_layout_kinds(sys::PottsSystem, kinds)
    isempty(getfield(sys, :kind_classes)) && return nothing
    for k in kinds
        k isa Symbol && !(k in getfield(sys, :kinds)) && any(g -> g.name === k, getfield(sys, :kind_classes)) &&
            throw(ArgumentError("layout: `$k` is a kind class, not a kind: layers take kinds; kinds are $(getfield(sys, :kinds))"))
    end
    return nothing
end

function _layout_spec(dims::Tuple{Vararg{Integer}})
    all(>(0), dims) || throw(ArgumentError("layout: lattice dimensions must be positive, got $dims"))
    return lattice_spec(dims; boundary = Closed())
end
_layout_spec(lat::Lattice) = LatticeSpec(lat.dims, map(p -> p ? Periodic() : Closed(), lat.periodic), nothing,
    Moore(1), lat.mask, lat.geometry)
_layout_spec(lat::LatticeSpec) = lat
_layout_spec(sys::PottsSystem) = _layout_spec(getfield(sys, :lattice))
_layout_spec(sys::CompiledPottsSystem) = _layout_spec(sys.sys)

# Drop cells with no site left and renumber the rest in order.
function _compact(σ, kinds, counts)
    all(>(0), counts) && return σ, kinds
    new = Int32.(cumsum(counts .> 0))
    for i in eachindex(σ)
        σ[i] > 0 && (σ[i] = new[σ[i]])
    end
    return σ, kinds[counts .> 0]
end
