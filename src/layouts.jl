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
end
function Frame(kind; width::Integer = 1)
    width >= 1 || throw(ArgumentError("Frame: width must be at least 1, got $width"))
    return Frame(kind, Int(width))
end

function paint!(σ, kinds, l::Frame, lat::LatticeSpec)
    dims, per = lat.dims, _periodic(lat)
    lat.domain === nothing || return _paint_domain_frame!(σ, kinds, l, lat.domain, dims, per)
    all(per) && throw(ArgumentError("Frame: every axis of the lattice is periodic, so it has no edge"))
    push!(kinds, l.kind)
    id, w = Int32(length(kinds)), l.width
    for i in CartesianIndices(σ)
        any(ntuple(d -> !per[d] && (i[d] <= w || i[d] > dims[d] - w), length(dims))) && (σ[i] = id)
    end
    return σ
end

# The frame on a domain: dilate the out-of-domain set (plus the virtual sites beyond each
# closed edge) by a Chebyshev ball of radius `w`, one axis at a time (a box is the product
# of its axis segments), and paint the in-domain sites it reaches. O(sites · w).
function _paint_domain_frame!(σ, kinds, l::Frame, mask, dims, per)
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
    push!(kinds, l.kind)
    id = Int32(length(kinds))
    for i in eachindex(σ)
        mask[i] && near[i] && (σ[i] = id)
    end
    return σ
end

"""
    InsertUntil(kind; into, fraction = nothing, number = nothing, seed, region = <whole lattice>,
                misses = :retry)

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

The rule is checked before the first draw and after every hit, not after a miss, so under
`:count` the count can overshoot by the misses drawn since the last hit (as in a script that
recomputes its ratio only when it paints). A hit may take the last site of a cell, which then
drops out of `N` (and `K`). Throws an `ArgumentError` when `region` holds no site to insert
into, when the allowed sites run out before the rule is met, and for a missing, doubled or
out-of-range stop rule. Use [`layout_tally`](@ref) to read how many cells a layer inserted
and how many draws missed.
"""
struct InsertUntil{K} <: AbstractLayout
    kind::K
    into::Vector{Any}
    fraction::Union{Nothing, Real}
    number::Int
    seed::UInt64
    region::Union{Nothing, Tuple{Vararg{UnitRange{Int}}}}
    count_misses::Bool
end
function InsertUntil(kind; into, fraction = nothing, number = nothing, seed::Integer, region = nothing,
        misses::Symbol = :retry)
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
        number === nothing ? -1 : Int(number), UInt64(seed), reg, misses === :count)
end

const _InsertTally = NamedTuple{(:painted, :misses, :counted), NTuple{3, Int}}

paint!(σ, kinds, l::InsertUntil, lat::LatticeSpec) = (_insert_until!(σ, kinds, l, lat); σ)

function _paint!(σ, kinds, l::InsertUntil, lat::LatticeSpec, tallies)
    t = _insert_until!(σ, kinds, l, lat)
    tallies === nothing || push!(tallies, t)
    return σ
end

# The stop rule, from the cells painted before the layer that still own a site (`N`, `K`
# of them of the inserted kind) and the count so far.
_insert_done(l::InsertUntil, N, K, counted) = l.number >= 0 ? counted >= l.number :
                                               K + counted >= l.fraction * (N + counted)

function _insert_until!(σ, kinds, l::InsertUntil, lat::LatticeSpec)
    dims = lat.dims
    l.region === nothing || _check_rank(l, length(l.region), dims, "InsertUntil")
    sites = CartesianIndices(_region(l.region, dims, "InsertUntil"))
    n0 = length(kinds)                           # cells painted before this layer
    nsites = zeros(Int, n0)
    for s in σ
        s > 0 && (nsites[s] += 1)
    end
    target = [k in l.into for k in kinds]        # a hit needs one of these owners
    N = count(>(0), nsites)
    K = count(c -> nsites[c] > 0 && isequal(kinds[c], l.kind), 1:n0)
    free = 0                                     # sites of `region` a draw can hit
    for i in sites
        s = σ[i]
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
        s = σ[i]
        if 0 < s <= n0 && target[s]
            push!(kinds, l.kind)
            σ[i] = length(kinds)
            nsites[s] -= 1
            if nsites[s] == 0                    # the hit took the cell's last site
                N -= 1
                isequal(kinds[s], l.kind) && (K -= 1)
            end
            painted += 1
            free -= 1
            done = _insert_done(l, N, K, painted + (l.count_misses ? misses : 0))
        else
            misses += 1
        end
    end
    return (; painted, misses, counted = painted + (l.count_misses ? misses : 0))
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

paint!(σ, kinds, l::Overlay, lat::LatticeSpec) = _paint!(σ, kinds, l, lat, nothing)

# `paint!` that also records the tally of every `InsertUntil` layer in `tallies` (a vector,
# or `nothing`), for `layout_tally`. A layout without tallies paints as usual.
_paint!(σ, kinds, l::AbstractLayout, lat, tallies) = paint!(σ, kinds, l, lat)

function _paint!(σ, kinds, l::Overlay, lat::LatticeSpec, tallies)
    cut = Set{Int32}()                      # cells that lost sites to a later layer
    prev = similar(σ, 0)                    # one buffer, refilled before each later layer
    for (j, x) in enumerate(l.layers)
        if j > 1
            j == 2 && (prev = similar(σ))
            copyto!(prev, σ)
        end
        _paint!(σ, kinds, x, lat, tallies)
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
# it never needs a reset. O(sites). `visited` (lattice-sized) is allocated only when the
# first cell needs a flood fill, so an overlay whose cut cells are all boxes skips it.
function _warn_split(σ, kinds, cut, lat::LatticeSpec{N}) where {N}
    K = length(kinds)
    iscut = falses(K)
    for c in cut
        iscut[c] = true
    end
    first_site = zeros(Int, K)
    ncount = zeros(Int, K)
    lo = fill(ntuple(_ -> typemax(Int), N), K)
    hi = fill(ntuple(_ -> typemin(Int), N), K)
    alive = falses(K)
    ci = CartesianIndices(σ)
    for i in eachindex(σ)
        c = σ[i]
        c > 0 || continue
        alive[c] = true
        iscut[c] || continue
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
    for c in sort!(collect(cut))
        ncount[c] == 0 && continue
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
        reached < ncount[c] &&
            @warn "overlay: later layers split cell $(count(view(alive, 1:c))) (kind $(kinds[c])) into disconnected pieces"
    end
    return nothing
end

const _LayoutTarget = Union{Tuple{Vararg{Integer}}, Lattice, LatticeSpec, PottsSystem, CompiledPottsSystem}

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
layout(l::AbstractLayout, lat::_LayoutTarget) = _layout(l, _layout_spec(lat), nothing)

"""
    layout_tally(l, lat) -> (point, tallies)

[`layout`](@ref) that also reports what every [`InsertUntil`](@ref) layer of `l` did:
`point == layout(l, lat)`, and `tallies` holds one `(; painted, misses, counted)` per
`InsertUntil` layer, in paint order. `painted` is the number of cells it inserted, `misses`
the number of draws that missed (in both `misses` modes) and `counted` what its stop rule
counted (`painted`, plus `misses` under `misses = :count`).
"""
function layout_tally(l::AbstractLayout, lat::_LayoutTarget)
    tallies = _InsertTally[]
    return _layout(l, _layout_spec(lat), tallies), tallies
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

function _layout(l, lat::LatticeSpec, tallies)
    σ = zeros(Int32, lat.dims)
    kinds = Any[]
    _paint!(σ, kinds, l, lat, tallies)
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
