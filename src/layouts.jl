# Layouts (ROADMAP P6.1a, review §3 R2; protocol P6.1a6, D-075/D-091): host-side initial
# conditions composed from layers and returned as an SII operating point
# `[ownership => σ, kind => kinds]`.
#
# Every layout is a subtype of `AbstractLayout` with one method, `paint!(op::LayoutState, l,
# lat)`. `op` is opaque: a layer allocates cells with `new_cell!`, paints sites with
# `assign!`, reads the paint so far with `owner`/`kindof`/`ncells` and reports with
# `record!`. `lat` is read only through the lattice queries `size`, `isperiodic` and
# `indomain` (plus `core_lattice` for CorePotts' `shift`, `relation` and `embed`). Randomized
# layouts own their seed, so adding a layer never changes another layer's draws. Coordinates
# are lattice indices: axial `(q, r)` on a hexagonal lattice, where a box is a rhombus.

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

Every built-in layer (`Tiling`, `Scattered`, `Frame`, `InsertUntil`) takes
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
    layer::Int                       # the current leaf (0: none)
    base::Int                        # cells allocated before the current leaf
    warn::Bool                       # the current leaf has `splits = :warn`
end
LayoutState(dims::NTuple{N, Int}) where {N} =
    LayoutState{N}(zeros(Int32, dims), Any[], Int32[], Bool[], _LayerRow[], 0, 0, true)

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
    record!(op::LayoutState; requested, painted, misses = 0, counted = painted)

Set the current leaf layer's entry in the layout report (see [`layout`](@ref)): what it was
asked for, the cells it created, the draws that missed and what a stop rule counted. A layer
that does not call it reports `requested = painted =` the cells it allocated. A layer that
paints built-in layers inside its own `paint!` calls `record!` last: their entries go to the
same row.
"""
function record!(op::LayoutState; requested::Integer, painted::Integer, misses::Integer = 0,
        counted::Integer = painted)
    op.layer == 0 && throw(ArgumentError("record!: called outside a layer's paint!"))
    r = op.rows[op.layer]
    r.requested, r.painted, r.misses, r.counted, r.recorded = requested, painted, misses, counted, true
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

# Boxes at lower corners `a` and `b` are at least `gap` sites apart along some axis; on a
# periodic axis of length `n` in both directions around the ring.
function _apart1(a, b, s, gap, n, wrap)
    wrap || return a + s + gap <= b || b + s + gap <= a
    δ = mod(b - a, n)
    return δ - s >= gap && n - δ - s >= gap
end
_apart(a, b, sz, gap, dims, per) = any(ntuple(d -> _apart1(a[d], b[d], sz[d], gap, dims[d], per[d]), length(a)))

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
# remake
# ---------------------------------------------------------------------------------------------

# The keyword constructor of a layer, the names of its positional arguments, and every
# argument (positional and keyword) as it would be passed.
_layout_args(l::Tiling) = (Tiling, (:size,), (; l.size, l.spacing, l.region, l.kinds, l.partial, l.splits))
_layout_args(l::Scattered) = (Scattered, (:n, :size), (; l.n, l.size, l.region, l.kinds, l.seed, l.gap, l.splits))
_layout_args(l::Frame) = (Frame, (:kind,), (; l.kind, l.width, l.splits))
_layout_args(l::InsertUntil) = (InsertUntil, (:kind,), (; l.kind, l.into, l.fraction,
    number = l.number >= 0 ? l.number : nothing, l.seed, l.region, misses = l.count_misses ? :count : :retry, l.splits))
_layout_args(l::AbstractLayout) =
    throw(ArgumentError("remake: $(nameof(typeof(l))) does not support remake (no keyword constructor is known)"))

function SciMLBase.remake(l::AbstractLayout; kw...)
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
    push!(op.rows, _LayerRow(nameof(typeof(l)), base + 1, base, 0, 0, 0, 0, false, 0))
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
    any(!=(0), cutby) || return nothing        # no cell was cut
    check = falses(length(counts))              # cells of the last leaf were never cut
    for c in eachindex(cutby)
        check[c] = cutby[c] != 0 && counts[c] > 0 && (cutwarn[c] || (report && cutby[c] > 0))
    end
    any(check) || return nothing
    _disconnected(op.σ, check, lat) do c
        if cutwarn[c]
            id = count(>(0), view(counts, 1:c))
            @warn "layout: later layers split cell $id (kind $(op.kinds[c])) into disconnected pieces"
        end
        report && cutby[c] > 0 && (op.rows[cutby[c]].splits += 1)
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
  `number` (`counted` under a `fraction` rule), a custom layer what it passed to
  [`record!`](@ref);
- `painted`: the cells the layer created; `dropped`: of those, the cells left with no site
  after the whole layout;
- `misses`: `InsertUntil` the missed draws (in both `misses` modes), a custom layer its
  `record!` value, other layers 0;
- `counted`: `InsertUntil` what its stop rule counted (`painted`, plus `misses` under
  `misses = :count`), other layers `painted`;
- `splits`: the cells cut only by this layer (it took at least one of their sites) whose
  remaining sites are disconnected after the whole layout, whatever its `splits` setting.
"""
function layout(l::AbstractLayout, x::_LayoutTarget; report::Bool = false)
    lat = _layout_spec(x)
    op = LayoutState(lat.dims)
    _paint_leaf!(op, l, lat)
    σ, kinds = op.σ, op.kinds
    counts = zeros(Int, length(kinds))
    for s in σ
        s > 0 && (counts[s] += 1)
    end
    _check_splits!(op, lat, counts, report)
    mask = lat.domain
    if mask !== nothing
        bad = findfirst(i -> σ[i] != 0 && !mask[i], CartesianIndices(σ))
        bad === nothing ||
            throw(ArgumentError("layout: cell $(σ[bad]) covers site $(Tuple(bad)), outside the lattice domain"))
    end
    rows = report ? [(; layer = j, r.type, r.requested, r.painted, dropped = count(c -> counts[c] == 0, r.first:r.last),
                         r.misses, r.counted, r.splits) for (j, r) in enumerate(op.rows)] : nothing
    σc, kindsc = _compact(σ, kinds, counts)
    point = [ownership => σc, kind => identity.(kindsc)]
    return report ? (point, rows) : point
end

function _layout_spec(dims::Tuple{Vararg{Integer}})
    all(>(0), dims) || throw(ArgumentError("layout: lattice dimensions must be positive, got $dims"))
    return lattice_spec(dims; boundary = Closed())
end
_layout_spec(lat::Lattice) = LatticeSpec(lat.dims, map(p -> p ? Periodic() : Closed(), lat.periodic), nothing,
    Moore(1), lat.mask, lat.geometry)
_layout_spec(lat::LatticeSpec) = lat
_layout_spec(sys::PottsSystem) = _layout_spec(sys.lattice)
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
