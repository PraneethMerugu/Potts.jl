# ------------------------------------------------------------------------------------------
# Bars, rods, chains and fibers: shapes placed at random to a density, and cells along
# polylines
# ------------------------------------------------------------------------------------------
#
# A bar, a rod and a chain are *bands*: the sites within half the width of a polyline. For
# one straight piece from `a` with unit direction `u` and length `len`, the Cartesian point
# `p` is in the band when `0 < (p - a)·u ≤ len` and `-w/2 < (p - a)·n ≤ w/2` for each unit
# normal `n` of `u` (one in 2D, two in 3D). The half-open intervals make an axis-aligned
# band of integer length `ℓ` and width `w` exactly `ℓ × w` sites (`ℓ × w × w` in 3D)
# wherever it lies. A point in several pieces of a polyline belongs to the first; the
# outer side of a corner can miss a few sites. Both bounds carry a relative 1e-12 slack
# (shifted up), as the round shapes do (D-138), so hexagonal √3/2 rounding does not drop
# sites at the edge unevenly.

"""
    Bar(length, width)

A straight bar of `length` by `width` (Cartesian), a shape for
[`InsertUntil`](@ref) and
[`Fibers`](@ref).

A copy is centered at its anchor site and points along a direction that the layer draws.
A site belongs to the bar when its embedded position lies within `length / 2` of the center
along the direction and within `width / 2` across it, both intervals half-open. An
axis-aligned bar of integer `length` and `width` is then exactly `length × width` sites
(`length × width × width` in 3D, where the cross-section is a square). Bars are 2D and 3D.

# Arguments
- `length::Real`: the length, finite and positive.
- `width::Real`: the width, finite and positive.

Throws an `ArgumentError` for a value out of range.

# Examples
```julia
InsertUntil(Bar(6, 2); kinds = [:fiber], density = 0.3, seed = 1)
```

See also [`Rod`](@ref), [`Fibers`](@ref).
"""
struct Bar
    length::Float64
    width::Float64
    function Bar(length::Real, width::Real)
        (isfinite(length) && length > 0 && isfinite(width) && width > 0) ||
            throw(ArgumentError("Bar: length and width must be finite and positive, got \
                $length and $width"))
        return new(Float64(length), Float64(width))
    end
end

"""
    Rod(n; length, width, link = nothing)

A straight rod of `n` segments, each `length` long and `width` wide, a shape for
[`InsertUntil`](@ref).

A copy is `n` cells: the [`Bar`](@ref) of length `n · length`, cut across into `n` equal
pieces. Segment 1, the head, is at the front along the drawn direction, and segment `n` is
the tail. With `link = name`, each copy links segment `i` to segment `i + 1` in the
relationship `name` (see [`link!`](@ref)), so in an ordered relationship the head has rank
1. A copy whose segments do not all get a site is redrawn. Rods are 2D and 3D.

# Arguments
- `n::Integer`: the number of segments (at least 1).

# Keywords
- `length::Real`: the length of one segment, finite and positive.
- `width::Real`: the width, finite and positive.
- `link = nothing`: a relationship name (a `Symbol`), or `nothing` for no links.

Throws an `ArgumentError` for a value out of range.

# Examples
```julia
# rods of 8 segments of 3 × 2 sites, linked head to tail, on 20% of the sites
InsertUntil(Rod(8; length = 3, width = 2, link = :chain); kinds = [:segment], density = 0.2,
    seed = 1)
```

See also [`Chains`](@ref), [`Bar`](@ref).
"""
struct Rod
    n::Int
    length::Float64
    width::Float64
    link::Union{Nothing, Symbol}
end
function Rod(n::Integer; length::Real, width::Real, link::Union{Nothing, Symbol} = nothing)
    n >= 1 || throw(ArgumentError("Rod: the number of segments must be at least 1, got $n"))
    b = Bar(length, width)                       # validates
    return Rod(Int(n), b.length, b.width, link)
end

# A shape that `InsertUntil` places at random.
const _Placeable = Union{Bar, Rod, HyperSphere, Interior}

_nparts(::Union{Bar, HyperSphere, Interior}) = 1
_nparts(r::Rod) = r.n

# The shape-placement settings of `InsertUntil(shape; …)`.
struct _Placement{S}
    shape::S
    kinds::Vector{Any}
    density::Union{Nothing, Float64}
    angles::Union{Nothing, Vector{Float64}, Vector{Vector{Float64}}}
    occupied::Union{Symbol, Vector{Any}}
    collective::Bool
    partial::Symbol
end

"""
    InsertUntil(shape; kinds, density = nothing, number = nothing, angles = nothing,
        occupied = :all, collective = false, partial = :reject, seed, region = nothing,
        splits = :warn)

A layer of copies of `shape`, placed at random until they cover a `density` of the region
or `number` copies are placed.

`shape` is a [`Bar`](@ref), a [`Rod`](@ref) or a round shape (`Circle`, `Sphere`,
`HyperSphere` or an [`Interior`](@ref) of one, centered at the origin). Each draw, with
`Potts.layer_rng(seed)`, picks an anchor site uniformly from the in-domain sites of
`region` and, for a bar or a rod, a direction. The copy is the shape centered at the anchor
(at its Cartesian position) along that direction. A draw is *rejected* when the copy

- covers a site of a cell that blocks it (see `occupied`);
- covers a point off the lattice (beyond a closed edge), outside the domain or outside
  `region`, under `partial = :reject`; under `:clip` those points are left out;
- covers no site, or leaves a segment of a rod with no site.

Otherwise the copy is painted: one cell per copy (`n` cells for a rod), of
`kinds[mod1(k, end)]` for copy `k`. The kinds cycle over copies, so all the segments of a
rod have one kind ([`Chains`](@ref) cycles them over segments). With `collective = true`
every copy paints the same one cell, of `kinds[1]` (a matrix of fibers as one cell), and
copies overlap where `occupied` does not block that kind. Copies wrap through periodic
edges.

Give exactly one stop rule:

- `density = ρ` (`0 < ρ ≤ 1`): stop once the sites of the layer's cells reach `ρ` times the
  in-domain sites of `region`. Each copy adds at most its own sites, so the final density is
  at least `ρ` and less than `ρ` plus one copy's share. `density` is a fraction of sites;
  the host form of `InsertUntil` takes `fraction`, a fraction of cells.
- `number = n`: stop after `n` copies.

The rule is checked before the first draw and after each copy. `layout` throws an
`ArgumentError` after 10,000 rejected draws in a row (the region is jammed: random
sequential placement stalls well below the densest packing), and for a region with no
in-domain site.

The report row has `requested` the `number` (the copies placed under a `density` rule),
`painted` the cells created, `misses` the rejected draws and `counted` the copies placed.

# Arguments
- `shape`: a [`Bar`](@ref), a [`Rod`](@ref), or a round shape centered at the origin.

# Keywords
- `kinds`: a non-empty collection of kinds; one kind when `collective = true`.
- `density = nothing`: the density stop rule, a real number in `(0, 1]`.
- `number = nothing`: the count stop rule, a non-negative integer.
- `angles = nothing`: the directions a bar or a rod is drawn from, uniformly. In 2D a
  collection of angles in radians from the first axis; in 3D a collection of direction
  vectors (normalized). `nothing` draws a uniform direction (an angle in `[0, 2π)`, or a
  point on the unit sphere).
- `occupied = :all`: the cells a copy may not cover. `:all` is every cell, painted before
  this layer or by it. A collection of kinds blocks only the cells of those kinds, and the
  copy paints over the others (an empty collection blocks nothing). Copies of a layer with
  `collective = false` never cover each other.
- `collective::Bool = false`: paint every copy into one cell. With `occupied = :all` the
  copies do not cross, because the shared cell blocks the later copies.
- `partial = :reject`: `:reject` or `:clip` (see above).
- `seed::Integer`: the seed, in `0:typemax(UInt64)`.
- `region = nothing`: a tuple of unit ranges; `nothing` is the whole lattice.
- `splits = :warn`: `:warn` or `:allow` (see [`overlay`](@ref)).

The constructor throws an `ArgumentError` for a missing or doubled stop rule and for a
value out of range.

# Examples
```julia
# 2 × 6 bars at six angles on 40% of a fluid background, as one matrix cell
angles = deg2rad.([0, 30, -30, 45, -45, 60, -60, 90])
overlay(Fill(:fluid), InsertUntil(Bar(6, 2); kinds = [:matrix], density = 0.4,
    angles, occupied = (), collective = true, partial = :clip, seed = 1, splits = :allow))
```

See also [`Fibers`](@ref), [`Rod`](@ref), [`Bar`](@ref).
"""
function InsertUntil(
        shape::_Placeable; kinds, density = nothing, number = nothing, angles = nothing,
        occupied = :all, collective::Bool = false, partial::Symbol = :reject,
        seed::Integer, region = nothing, splits::Symbol = :warn
    )
    what = "InsertUntil"
    (density === nothing) == (number === nothing) &&
        throw(ArgumentError("$what: give exactly one stop rule, `density` or `number`"))
    density === nothing || (density isa Real && 0 < density <= 1) ||
        throw(ArgumentError("$what: `density` must lie in (0, 1], got $density"))
    number === nothing || (number isa Integer && number >= 0) ||
        throw(ArgumentError("$what: `number` must be a non-negative integer, got $number"))
    partial in (:reject, :clip) ||
        throw(ArgumentError("$what: `partial` must be :reject or :clip, got \
            $(repr(partial))"))
    _check_seed(seed, what)
    ks = collect(Any, _kinds_arg(kinds, what))
    collective && length(ks) != 1 &&
        throw(ArgumentError("$what: a collective layer paints one cell, so give one kind, \
            got $(length(ks))"))
    collective && shape isa Rod &&
        throw(ArgumentError("$what: a rod is several linked cells, so it cannot be \
            collective"))
    s = shape isa HyperSphere ? _shape_arg(shape, what) : shape
    reg = region === nothing ? nothing : _region_arg(region, length(region), what)
    pl = _Placement(
        s, ks, density === nothing ? nothing : Float64(density), _angles_arg(angles, what),
        _occupied_arg(occupied, what), collective, partial
    )
    return InsertUntil(
        nothing, Any[], nothing, number === nothing ? -1 : Int(number), UInt64(seed), reg,
        false, _splits_arg(splits, what), pl
    )
end

function _angles_arg(angles, what)
    angles === nothing && return nothing
    v = collect(angles)
    isempty(v) && throw(ArgumentError("$what: `angles` is empty; pass at least one"))
    if all(a -> a isa Real && isfinite(a), v)
        return Float64.(v)
    elseif all(a -> length(a) >= 1 && all(x -> x isa Real && isfinite(x), a), v)
        out = Vector{Float64}[]
        for a in v
            n = sqrt(sum(abs2, a))
            n > 0 || throw(ArgumentError("$what: a direction in `angles` is zero"))
            push!(out, Float64.(collect(a)) ./ n)
        end
        return out
    end
    throw(ArgumentError("$what: `angles` holds finite angles (2D) or direction vectors \
        (3D), got $(repr(angles))"))
end

function _occupied_arg(o, what)
    o === :all && return :all
    o isa Symbol &&
        throw(ArgumentError("$what: `occupied` is :all or a collection of kinds, got \
            $(repr(o)); wrap one kind in a vector"))
    return collect(Any, o)
end

# Whether the cell `o` (0: none) blocks a copy of a layer whose cells come after `base`.
function _blocked(op, o, base, pl::_Placement)
    o == 0 && return false
    o > base && !pl.collective && return true
    return _blocks(pl.occupied, kindof(op, o))
end
_blocks(occupied::Symbol, k) = true                 # :all
_blocks(occupied::Vector{Any}, k) = any(isequal(k), occupied)

function _layout_args(l::InsertUntil{Nothing, <:_Placement})
    pl = l.placement
    return (
        InsertUntil, (:shape,),
        (;
            pl.shape, pl.kinds, pl.density,
            number = l.number >= 0 ? l.number : nothing, pl.angles,
            pl.occupied, pl.collective, pl.partial, l.seed, l.region, l.splits,
        ),
    )
end

# --- geometry -----------------------------------------------------------------------------

_slack(h) = 1.0e-12 * max(abs(h), 1.0)

# The unit normals of the direction `u` (2D: one; 3D: two, a right-handed frame built from
# the axis least aligned with `u`).
_normals(u::SVector{2, Float64}) = (SVector(-u[2], u[1]),)
function _normals(u::SVector{3, Float64})
    k = argmin(abs.(u))
    e = SVector{3, Float64}(ntuple(d -> Float64(d == k), Val(3)))
    n1 = e - (e' * u) * u
    n1 = n1 / sqrt(n1' * n1)
    n2 = SVector(
        u[2] * n1[3] - u[3] * n1[2], u[3] * n1[1] - u[1] * n1[3],
        u[1] * n1[2] - u[2] * n1[1]
    )
    return (n1, n2)
end
function _normals(::SVector{N, Float64}) where {N}
    throw(ArgumentError("bars, rods and chains are 2D or 3D; the lattice is $(N)D"))
end

# The index box that holds the Cartesian box `lo:hi` (its corners mapped by `Ei`), one site
# wider on every side.
function _index_box(lo::SVector{N, Float64}, hi::SVector{N, Float64}, Ei) where {N}
    mn = fill(Inf, N)
    mx = fill(-Inf, N)
    for k in 0:(2^N - 1)
        c = SVector{N, Float64}(
            ntuple(d -> ((k >> (d - 1)) & 1) == 1 ? hi[d] : lo[d], Val(N))
        )
        x = Ei * c
        for d in 1:N
            mn[d] = min(mn[d], x[d])
            mx[d] = max(mx[d], x[d])
        end
    end
    return ntuple(d -> (floor(Int, mn[d]) - 1):(ceil(Int, mx[d]) + 1), Val(N))
end

# The unwrapped index points of the band of width `w` around the polyline `path`
# (Cartesian), cut into `nseg` equal pieces of arc length from `path[1]`, and the piece of
# each point.
function _band_points(path::Vector{SVector{N, Float64}}, w, nseg, E, Ei) where {N}
    m = length(path) - 1
    len = [sqrt(sum(abs2, path[k + 1] - path[k])) for k in 1:m]
    u = [(path[k + 1] - path[k]) / len[k] for k in 1:m]
    nrm = [_normals(u[k]) for k in 1:m]
    cum = [0.0; cumsum(len)]
    total = cum[end]
    h = w / 2
    lo = reduce((a, b) -> min.(a, b), path) .- w
    hi = reduce((a, b) -> max.(a, b), path) .+ w
    xs = NTuple{N, Int}[]
    seg = Int[]
    for x in Iterators.product(_index_box(lo, hi, Ei)...)
        p = E * SVector{N, Float64}(x)
        for k in 1:m
            v = p - path[k]
            s = v' * u[k]
            (_slack(len[k]) < s <= len[k] + _slack(len[k])) || continue
            all(n -> (-h + _slack(h) < v' * n <= h + _slack(h)), nrm[k]) || continue
            t = cum[k] + s
            push!(xs, x)
            push!(seg, clamp(ceil(Int, (t - _slack(total)) * nseg / total), 1, nseg))
            break
        end
    end
    return xs, seg
end

# The unwrapped index points of a round shape centered at the Cartesian point `c`.
function _round_points(s::_Round, c::SVector{N, Float64}, E, Ei) where {N}
    b = _ball(s)
    r = Float64(b.r)
    t = _translate(s, c)
    xs = NTuple{N, Int}[]
    for x in Iterators.product(_index_box(c .- r, c .+ r, Ei)...)
        _member(Point{N, Float64}(E * SVector{N, Float64}(x)), t) && push!(xs, x)
    end
    return xs, ones(Int, length(xs))
end

# The points of one copy of `shape` at the Cartesian anchor `c`, direction `u`.
function _copy_points(b::Bar, c, u, E, Ei)
    return _band_points([c + (b.length / 2) * u, c - (b.length / 2) * u], b.width, 1, E, Ei)
end
function _copy_points(r::Rod, c, u, E, Ei)
    L = r.n * r.length
    return _band_points([c + (L / 2) * u, c - (L / 2) * u], r.width, r.n, E, Ei)
end
_copy_points(s::_Round, c, u, E, Ei) = _round_points(s, c, E, Ei)

# The lattice site of the unwrapped index point `x`, wrapped on periodic axes, or `nothing`
# beyond a closed edge.
function _wrap_site(x::NTuple{N, Int}, dims, per) where {N}
    for d in 1:N
        per[d] || 1 <= x[d] <= dims[d] || return nothing
    end
    return CartesianIndex(ntuple(d -> per[d] ? mod1(x[d], dims[d]) : x[d], Val(N)))
end

_oriented(::Union{Bar, Rod}) = true
_oriented(::_Round) = false

# A direction: a draw from `angles`, or uniform on the circle or the sphere.
function _draw_direction(rng, angles, ::Val{2})
    θ = angles === nothing ? 2π * rand(rng) : rand(rng, angles)
    θ isa Real || throw(ArgumentError("InsertUntil: on a 2D lattice `angles` holds angles"))
    return SVector(cos(θ), sin(θ))
end
function _draw_direction(rng, angles, ::Val{3})
    if angles === nothing
        z = 2 * rand(rng) - 1
        φ = 2π * rand(rng)
        ρ = sqrt(max(0.0, 1 - z^2))
        return SVector(ρ * cos(φ), ρ * sin(φ), z)
    end
    v = rand(rng, angles)
    (v isa AbstractVector && length(v) == 3) ||
        throw(ArgumentError("InsertUntil: on a 3D lattice `angles` holds 3-vectors"))
    return SVector{3, Float64}(v)
end
function _draw_direction(rng, angles, ::Val{N}) where {N}
    throw(ArgumentError("InsertUntil: bars and rods are 2D or 3D; the lattice is \
        $(N)D"))
end

function _check_shape_dim(s::_Round, N)
    return _check_dim(s, N, "InsertUntil")
end
function _check_shape_dim(::Union{Bar, Rod}, N)
    N in (2, 3) ||
        throw(ArgumentError("InsertUntil: bars and rods are 2D or 3D; the lattice is \
            $(N)D"))
    return nothing
end

function _placement_done(l::InsertUntil, copies, covered, total)
    return l.number >= 0 ? copies >= l.number : covered >= l.placement.density * total
end

function paint!(
        op::LayoutState, l::InsertUntil{Nothing, <:_Placement}, lat::LatticeSpec{N}
    ) where {N}
    pl = l.placement
    dims = size(lat)
    per = _periodic(lat)
    l.region === nothing || _check_rank(l, length(l.region), dims, "InsertUntil")
    _check_shape_dim(pl.shape, N)
    reg = _region(l.region, dims, "InsertUntil")
    anchors = CartesianIndex{N}[x for x in CartesianIndices(reg) if indomain(lat, x)]
    total = length(anchors)
    total == 0 &&
        throw(ArgumentError("InsertUntil: the region $reg has no site in the lattice's \
            domain; choose a region overlapping the domain"))
    E = _embedding(core_lattice(lat), Val(N))
    Ei = inv(E)
    base = ncells(op)                            # this layer's cells are base+1:ncells(op)
    nparts = _nparts(pl.shape)
    rng = layer_rng(l.seed)
    covered = copies = misses = streak = 0
    shared = 0                                   # the collective cell (0: not yet made)
    sites = CartesianIndex{N}[]
    parts = Int[]
    seen = falses(nparts)
    while !_placement_done(l, copies, covered, total)
        streak >= _SCATTER_ATTEMPTS && throw(
            ArgumentError(
                "InsertUntil: $_SCATTER_ATTEMPTS draws in a row were rejected after \
                    $copies copies (density $(round(covered / total; digits = 3))); the \
                        region is jammed. Use a lower density or number, a smaller shape, \
                        `partial = :clip` or a larger region"
            )
        )
        c = E * SVector{N, Float64}(Tuple(anchors[rand(rng, 1:total)]))
        u = _oriented(pl.shape) ? _draw_direction(rng, pl.angles, Val(N)) : c
        xs, seg = _copy_points(pl.shape, c, u, E, Ei)
        empty!(sites)
        empty!(parts)
        fill!(seen, false)
        ok = true
        for (x, k) in zip(xs, seg)
            y = _wrap_site(x, dims, per)
            if y === nothing || !indomain(lat, y) || !all(d -> y[d] in reg[d], 1:N)
                pl.partial === :reject && (ok = false; break)
                continue
            end
            _blocked(op, owner(op, y), base, pl) && (ok = false; break)
            push!(sites, y)
            push!(parts, k)
            seen[k] = true
        end
        if !(ok && all(seen))
            misses += 1
            streak += 1
            continue
        end
        streak = 0
        copies += 1
        ids = if pl.collective
            shared == 0 && (shared = new_cell!(op, pl.kinds[1]))
            fill(shared, nparts)
        else
            [new_cell!(op, pl.kinds[mod1(copies, length(pl.kinds))]) for _ in 1:nparts]
        end
        for (y, k) in zip(sites, parts)
            owner(op, y) > base || (covered += 1)
            assign!(op, y, ids[k])
        end
        r = pl.shape
        if r isa Rod && r.link !== nothing
            for i in 1:(nparts - 1)
                link!(op, r.link, ids[i], ids[i + 1])
            end
        end
    end
    record!(
        op; requested = l.number >= 0 ? l.number : copies, painted = ncells(op) - base,
        misses, counted = copies
    )
    return nothing
end

"""
    Fibers(kind; length, width = 1, angles = nothing, density = nothing, number = nothing,
        occupied = (), collective = true, partial = :clip, seed, region = nothing,
        splits = :warn)

A layer of straight fiber bundles of `kind`, `length` by `width`, at random positions and
at directions drawn from `angles`, until they cover a `density` of the region.

`Fibers` is [`InsertUntil`](@ref)
with a [`Bar`](@ref) and these defaults: the bundles form one cell (`collective = true`),
they may cross (`occupied = ()`), and a bundle that reaches a closed edge is cut there
(`partial = :clip`). Paint it over a background, such as `Fill(:fluid)`, whose sites the
bundles take. The background is then cut into pieces wherever the bundles enclose part of
it, so pass `splits = :allow` to accept that. The report row is that of `InsertUntil`,
with `type = :Fibers`.

# Arguments
- `kind`: the kind of the bundles.

# Keywords
- `length::Real`, `width::Real = 1`: the bundle size (see [`Bar`](@ref)).
- `angles = nothing`, `density = nothing`, `number = nothing`, `occupied = ()`,
  `collective::Bool = true`, `partial = :clip`, `seed::Integer`, `region = nothing`,
  `splits = :warn`: as for `InsertUntil` (give exactly one of `density` and `number`).

# Examples
```julia
# 2 × 6 bundles at the angles 0, ±30, ±45, ±60 and 90 degrees on 40% of a fluid background
angles = deg2rad.([0, 30, -30, 45, -45, 60, -60, 90])
overlay(Fill(:fluid), Fibers(:matrix; length = 6, width = 2, angles, density = 0.4,
    seed = 1, splits = :allow))
```

See also [`Bar`](@ref), [`Fill`](@ref).
"""
struct Fibers{K} <: AbstractLayout
    kind::K
    length::Float64
    width::Float64
    angles::Any
    density::Any
    number::Any
    occupied::Any
    collective::Bool
    partial::Symbol
    seed::UInt64
    region::Any
    splits::Symbol
end
function Fibers(
        kind; length::Real, width::Real = 1, angles = nothing, density = nothing,
        number = nothing, occupied = (), collective::Bool = true, partial::Symbol = :clip,
        seed::Integer, region = nothing, splits::Symbol = :warn
    )
    kind isa Union{AbstractArray, Tuple} &&
        throw(ArgumentError("Fibers: `kind` is one kind, got $(repr(kind))"))
    l = Fibers(
        kind, Float64(length), Float64(width), angles, density, number, occupied,
        collective, partial, (_check_seed(seed, "Fibers"); UInt64(seed)), region, splits
    )
    _fiber_layer(l)                              # validates every argument
    return l
end
function _fiber_layer(l::Fibers)
    return InsertUntil(
        Bar(l.length, l.width); kinds = [l.kind], l.density, l.number, l.angles,
        l.occupied, l.collective, l.partial, l.seed, l.region, l.splits
    )
end
_splits(l::Fibers) = l.splits
paint!(op::LayoutState, l::Fibers, lat) = paint!(op, _fiber_layer(l), lat)
function _layout_args(l::Fibers)
    return (
        Fibers, (:kind,),
        (;
            l.kind, l.length, l.width, l.angles, l.density, l.number, l.occupied,
            l.collective, l.partial, l.seed, l.region, l.splits,
        ),
    )
end

"""
    Chains(paths; segments, width, kinds, link = nothing, splits = :warn)

A layer of chains of cells, one chain along each polyline of `paths`, each chain cut into
`segments` cells of equal arc length. The chains always paint over earlier layers: unlike
[`InsertUntil`](@ref), `Chains` has no `occupied` keyword.

A chain owns the in-domain sites within `width / 2` of its polyline (the band of a
[`Bar`](@ref) along each straight piece, half-open, so a straight axis-aligned chain of
integer length `ℓ` and width `w` is exactly `ℓ × w` sites). Its cells follow the polyline
from its first point: cell 1 is the head. The sites wrap through periodic edges and are
clipped at closed edges and at the domain. Within the layer the first chain wins a site,
and within a chain the first piece of the polyline does.

`kinds` is cycled over the segments of each chain, head first, so
`kinds = [:pinned; fill(:segment, s - 1)]` with `segments = s` gives a pinned head and
`s - 1` free segments. (A [`Rod`](@ref) in `InsertUntil` cycles `kinds` over copies
instead.) With `link = name`, cell `i` of each chain is linked to
cell `i + 1` in the relationship `name` (see [`link!`](@ref)): in an ordered relationship
the head has rank 1.

The report row has `requested = painted =` the cells (chains × `segments`), `dropped` those
left with no site, and `clipped` the points of the bands lost to closed edges and the
domain.

# Arguments
- `paths`: a polyline (a vector of at least two Cartesian `Point`s, consecutive points
  distinct) or a vector of polylines. Throws an `ArgumentError` otherwise.

# Keywords
- `segments::Integer`: the cells per chain (at least 1).
- `width::Real`: the band width, finite and positive.
- `kinds`: a non-empty collection of kinds, cycled along each chain.
- `link = nothing`: a relationship name (a `Symbol`), or `nothing`.
- `splits = :warn`: `:warn` or `:allow` (see [`overlay`](@ref)).

# Examples
```julia
# a bent rod of 12 cells (a U), linked head to tail
u = [Point(30.0, 10.5), Point(10.0, 10.5), Point(10.0, 22.5), Point(30.0, 22.5)]
Chains(u; segments = 12, width = 2, kinds = [:segment], link = :chain)
```

See also [`Rod`](@ref), [`link!`](@ref).
"""
struct Chains{K} <: AbstractLayout
    paths::Vector{Vector{Point}}
    segments::Int
    width::Float64
    kinds::Vector{K}
    link::Union{Nothing, Symbol}
    splits::Symbol
end
function Chains(
        paths; segments::Integer, width::Real, kinds,
        link::Union{Nothing, Symbol} = nothing, splits::Symbol = :warn
    )
    ps = _paths_arg(paths)
    segments >= 1 ||
        throw(ArgumentError("Chains: `segments` must be at least 1, got $segments"))
    (isfinite(width) && width > 0) ||
        throw(ArgumentError("Chains: `width` must be finite and positive, got $width"))
    return Chains(
        ps, Int(segments), Float64(width), _kinds_arg(kinds, "Chains"), link,
        _splits_arg(splits, "Chains")
    )
end
function _paths_arg(paths)
    v = paths isa AbstractVector && !isempty(paths) && first(paths) isa Point ? [paths] :
        paths
    (v isa AbstractVector && !isempty(v)) ||
        throw(ArgumentError("Chains: `paths` is a polyline or a non-empty vector of them"))
    out = Vector{Point}[]
    for p in v
        (p isa AbstractVector && length(p) >= 2 && all(x -> x isa Point, p)) ||
            throw(ArgumentError("Chains: a polyline is a vector of at least two `Point`s, \
                got $(repr(p))"))
        length(unique(length.(p))) == 1 ||
            throw(ArgumentError("Chains: the points of a polyline have one dimension"))
        foreach(x -> _check_point(x, "Chains"), p)
        any(k -> p[k] == p[k + 1], 1:(length(p) - 1)) &&
            throw(ArgumentError("Chains: consecutive points of a polyline must differ"))
        push!(out, collect(Point, p))
    end
    return out
end
_splits(l::Chains) = l.splits
function _layout_args(l::Chains)
    return (Chains, (:paths,), (; l.paths, l.segments, l.width, l.kinds, l.link, l.splits))
end

function paint!(op::LayoutState, l::Chains, lat::LatticeSpec{N}) where {N}
    dims = size(lat)
    per = _periodic(lat)
    E = _embedding(core_lattice(lat), Val(N))
    Ei = inv(E)
    base = ncells(op)
    clipped = 0
    for p in l.paths
        length(p[1]) == N ||
            throw(ArgumentError("Chains: a $(length(p[1]))D polyline on a $(N)D lattice"))
        path = [SVector{N, Float64}(Tuple(x)) for x in p]
        xs, seg = _band_points(path, l.width, l.segments, E, Ei)
        ids = [new_cell!(op, l.kinds[mod1(i, length(l.kinds))]) for i in 1:(l.segments)]
        for (x, k) in zip(xs, seg)
            y = _wrap_site(x, dims, per)
            if y === nothing || !indomain(lat, y)
                clipped += 1
                continue
            end
            owner(op, y) > base && continue      # an earlier chain or piece of this layer
            assign!(op, y, ids[k])
        end
        if l.link !== nothing
            for i in 1:(l.segments - 1)
                link!(op, l.link, ids[i], ids[i + 1])
            end
        end
    end
    n = length(l.paths) * l.segments
    record!(op; requested = n, painted = n, clipped)
    return nothing
end

_layer_kinds(l::InsertUntil{Nothing, <:_Placement}) = l.placement.kinds
_layer_kinds(l::Fibers) = (l.kind,)
_layer_kinds(l::Chains) = l.kinds
