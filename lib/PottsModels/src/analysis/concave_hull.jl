# The concave hull of a planar point cloud: a Graham-scan convex hull followed by
# concaveman (mapbox/concaveman, through S. Adaszewski's C++ port), as the OpenVT
# consortium's `metrics.cpp` builds a tissue boundary.
#
# Floating point: every kernel below is written operation for operation as in the C++
# reference, with plain `*`, `+`, `-` and `/` (no fused or reassociated arithmetic; spec 15
# D11, D-149). The hull is ill-conditioned: one ulp in an orientation test can change it.
# The spatial grids only decide which points and edges are examined; the arithmetic on
# each one is the reference's.

const _Point2 = NTuple{2, Float64}

"""
    concave_hull(points; concavity = 2.0, length_threshold = 0.0) -> Vector{NTuple{2, Float64}}

The concave hull of the planar points `points` (any collection of 2-tuples or 2-vectors of
reals; converted to `Float64`, and not modified). The result is the closed boundary, without
repeating the first vertex.

The construction is the OpenVT monolayer benchmark's (`metrics.cpp` and `concaveman.h` in
the consortium repository), step for step:

1. A strictly convex hull by Graham scan, collinear points excluded. The pivot `p₀` is
   the point with the least `(y, x)`; the other points are sorted by orientation about
   `p₀` (clockwise first; on one ray from `p₀`, nearer first). A two-vertex hull of equal
   points keeps one vertex.
2. If the convex hull holds every point, it is returned (from `p₀`, clockwise).
3. Otherwise concaveman: the hull edges are processed first in, first out. An edge
   `(b, c)` with ``|bc|² ≥`` `length_threshold²` looks at the interior points within
   squared segment distance ``d ≤ |bc|²/\\mathrm{concavity}²``, nearest first. The first
   point `p` with `d` strictly below its squared distance to both neighbouring edges
   `(a, b)` and `(c, d′)`, and whose new edges `b–p` and `c–p` cross no current edge, is
   inserted between `b` and `c` when ``\\min(|pb|², |pc|²) ≤ |bc|²/\\mathrm{concavity}²``.
   The two new edges join the queue; the point and its duplicates leave the candidates.
4. The vertices are listed clockwise, starting at the successor of the last convex-hull
   vertex, so points carved into the closing edge come first.

A larger `concavity` gives a simpler hull (`Inf`: the convex hull); `metrics.cpp` uses 1.5.
An empty `points`, a non-finite coordinate, a `concavity` that is not positive or a negative
`length_threshold` is an `ArgumentError`.

The arithmetic follows the C++ operation for operation, without fused multiply-adds. The
result is identical to the reference (`metrics.cpp` built with `-ffp-contract=off`) on the
25 OpenVT parameter-plane colonies and on fuzzed clouds without ties. It departs from the
reference on purpose in two places, recorded as defects D12 and D13 of the benchmark spec.
In both, the reference's result depends on luck, and this one is the correct hull:

- **D12, the Graham order.** `metrics.cpp` sorts with a floating-point orientation whose
  sign is rounding noise for points collinear with `p₀`, which is not a strict weak
  ordering. Here the orientation sign is exact: it is `metrics.cpp`'s value wherever that
  value's rounding bound decides the sign, and is computed in exact rational arithmetic
  otherwise. Points on one ray from `p₀` go nearer first, and collinear points are dropped,
  so the convex hull is strictly convex and does not depend on the sort algorithm.
- **D13, the candidate search.** concaveman's R-tree prunes boxes by a segment–box distance
  that overestimates next to near-parallel or axis-aligned edges, so it can miss the
  nearest candidate. Here every live point within the distance limit is examined, nearest
  first.

Two further caveats:

- **Exact ties.** When two candidates are at exactly the same distance, the C++ takes them
  in the order of its R-tree, which depends on the standard library (libc++ and libstdc++
  differ on a perfect lattice). Here a tie goes to the point that comes first in the Graham
  order.
- **Platform.** All arithmetic is `Float64`. The reference was validated on arm64, where
  `long double` is `double`; an x86 build of `metrics.cpp` with 80-bit `long double` may
  differ in the last bits.

Points and hull edges are indexed by uniform grids: a hull of ``10⁴`` colony centroids
takes milliseconds. Near-degenerate input whose orientation signs need exact rational
arithmetic (many points exactly collinear at non-integer coordinates) is slower, up to
seconds for ``10⁴`` points on one line.
"""
function concave_hull(points; concavity::Real = 2.0, length_threshold::Real = 0.0)
    pts = _Point2[(Float64(p[1]), Float64(p[2])) for p in points]
    isempty(pts) && throw(ArgumentError("concave_hull: no points"))
    concavity > 0 || throw(ArgumentError("concave_hull: concavity must be positive (got $concavity)"))
    length_threshold >= 0 ||
        throw(ArgumentError("concave_hull: length_threshold must be non-negative (got $length_threshold)"))
    all(p -> isfinite(p[1]) && isfinite(p[2]), pts) ||
        throw(ArgumentError("concave_hull: the points must have finite coordinates"))
    hull = _graham_hull!(pts)
    length(hull) == length(pts) && return pts[hull]
    return _concaveman(pts, hull, Float64(concavity), Float64(length_threshold))
end

# ── kernels (metrics.cpp and concaveman.h, operation for operation) ────────────────────────

# metrics.cpp `orientation`, with the sign made exact: −1 clockwise, +1 counter-clockwise,
# 0 collinear. The value is metrics.cpp's expression; when its magnitude is within the
# expression's rounding bound the sign is decided in exact rational arithmetic. Wherever the
# floating-point sign is certain the result is metrics.cpp's; elsewhere metrics.cpp's sign is
# rounding noise, which made its Graham order inconsistent (spec 15 D12).
function _orientation(a::_Point2, b::_Point2, c::_Point2)
    t1 = a[1] * (b[2] - c[2])
    t2 = b[1] * (c[2] - a[2])
    t3 = c[1] * (a[2] - b[2])
    v = t1 + t2 + t3
    # absolute term: below ≈ 1e-150 the products are subnormal and the error is absolute
    bound = 8 * eps(Float64) * (abs(t1) + abs(t2) + abs(t3)) + 4 * nextfloat(0.0)
    abs(v) > bound && return v < 0 ? -1 : 1
    _small_integers(a, b, c) && return Int(sign(v))   # every operation above was exact
    return _orientation_exact(a, b, c)
end

# Integer coordinates below 2²⁵ in magnitude: differences < 2²⁶, products < 2⁵¹ and the
# three-term sum < 2⁵³, all exact in Float64, so `v` itself is exact (lattice data).
_small_int(x) = isinteger(x) & (abs(x) < 33554432.0)
_small_integers(a, b, c) = _small_int(a[1]) & _small_int(a[2]) & _small_int(b[1]) & _small_int(b[2]) &
    _small_int(c[1]) & _small_int(c[2])

function _orientation_exact(a::_Point2, b::_Point2, c::_Point2)
    R(x) = Rational{BigInt}(x)
    v = R(a[1]) * (R(b[2]) - R(c[2])) + R(b[1]) * (R(c[2]) - R(a[2])) + R(c[1]) * (R(a[2]) - R(b[2]))
    return Int(sign(v))
end

# concaveman.h `orient2d`
_orient2d(p1::_Point2, p2::_Point2, p3::_Point2) =
    (p2[2] - p1[2]) * (p3[1] - p2[1]) - (p2[1] - p1[1]) * (p3[2] - p2[2])

# concaveman.h `intersects`: edges (p1, q1) and (p2, q2) cross
_intersects(p1::_Point2, q1::_Point2, p2::_Point2, q2::_Point2) =
    p1 != q2 && q1 != p2 &&
    (_orient2d(p1, q1, p2) > 0) != (_orient2d(p1, q1, q2) > 0) &&
    (_orient2d(p2, q2, p1) > 0) != (_orient2d(p2, q2, q1) > 0)

# concaveman.h `getSqDist`
function _sqdist(p1::_Point2, p2::_Point2)
    dx = p1[1] - p2[1]
    dy = p1[2] - p2[2]
    return dx * dx + dy * dy
end

# concaveman.h `sqSegDist`: squared distance from p to the segment (p1, p2)
function _sqsegdist(p::_Point2, p1::_Point2, p2::_Point2)
    x, y = p1
    dx = p2[1] - x
    dy = p2[2] - y
    if dx != 0 || dy != 0
        t = ((p[1] - x) * dx + (p[2] - y) * dy) / (dx * dx + dy * dy)
        if t > 1
            x, y = p2
        elseif t > 0
            x += dx * t
            y += dy * t
        end
    end
    dx = p[1] - x
    dy = p[2] - y
    return dx * dx + dy * dy
end

# ── Graham scan (metrics.cpp `convex_hull`, include_collinear = false) ─────────────────────

# Sorts `pts` in place into Graham order and returns the strictly convex hull as indices into
# it. The order is a strict weak ordering (exact orientation about p₀; on one ray from p₀,
# nearer first), so the result does not depend on the sort algorithm; metrics.cpp's
# comparator is not one for points collinear with p₀ (spec 15 D12).
function _graham_hull!(pts::Vector{_Point2})
    p0 = pts[1]
    for p in pts
        (p[2], p[1]) < (p0[2], p0[1]) && (p0 = p)
    end
    sort!(pts; lt = (a, b) -> _graham_before(p0, a, b))
    hull = Int[]
    for i in eachindex(pts)
        while length(hull) > 1 && !(_orientation(pts[hull[end - 1]], pts[hull[end]], pts[i]) < 0)
            pop!(hull)
        end
        push!(hull, i)
    end
    length(hull) == 2 && pts[hull[1]] == pts[hull[2]] && pop!(hull)
    return hull
end

# a before b in Graham order: clockwise about p0 first; on one ray, nearer first. The squared
# distance is metrics.cpp's (monotone along a ray, as rounding is monotone); distinct points
# whose distances round alike are ordered by |Δx|, |Δy| (also monotone), then by coordinates.
function _graham_before(p0::_Point2, a::_Point2, b::_Point2)
    o = _orientation(p0, a, b)
    o == 0 || return o < 0
    da = (p0[1] - a[1]) * (p0[1] - a[1]) + (p0[2] - a[2]) * (p0[2] - a[2])
    db = (p0[1] - b[1]) * (p0[1] - b[1]) + (p0[2] - b[2]) * (p0[2] - b[2])
    da == db || return da < db
    return (abs(a[1] - p0[1]), abs(a[2] - p0[2]), a[1], a[2]) < (abs(b[1] - p0[1]), abs(b[2] - p0[2]), b[1], b[2])
end

# ── a uniform grid over the points' bounding box ───────────────────────────────────────────

# Cells are `h` wide from (x0, y0); coordinates outside the box clamp to the border cells.
# The grid only selects what to examine, so its own rounding cannot change a result as long
# as every query covers its region with a margin (see `_cellspan`).
struct _Grid
    x0::Float64
    y0::Float64
    h::Float64
    nx::Int
    ny::Int
end

function _Grid(pts::Vector{_Point2})
    xmin, xmax = extrema(p -> p[1], pts)
    ymin, ymax = extrema(p -> p[2], pts)
    W, H = xmax - xmin, ymax - ymin
    n = length(pts)
    h = max(sqrt(2 * W * H / n), max(W, H) / n)   # about two points per cell
    (isfinite(h) && h > 0) || (h = 1.0)
    nx = min(floor(Int, W / h) + 1, 4n + 1)
    ny = min(floor(Int, H / h) + 1, 4n + 1)
    h = max(h, W / nx, H / ny)
    return _Grid(xmin, ymin, h, nx, ny)
end

_cellaxis(v, v0, h, n) = (s = (v - v0) / h; s < 1 ? 1 : s >= n ? n : floor(Int, s) + 1)
_cell(g::_Grid, p::_Point2) = (_cellaxis(p[1], g.x0, g.h, g.nx), _cellaxis(p[2], g.y0, g.h, g.ny))
_cellid(g::_Grid, i::Int, j::Int) = i + (j - 1) * g.nx

# the cells covering the box [xlo, xhi] × [ylo, yhi], widened by a relative margin
function _cellspan(g::_Grid, xlo, xhi, ylo, yhi)
    m = 1.0e-9 * (abs(g.x0) + abs(g.y0) + (g.nx + g.ny) * g.h)
    i1 = _cellaxis(xlo - m, g.x0, g.h, g.nx)
    i2 = _cellaxis(xhi + m, g.x0, g.h, g.nx)
    j1 = _cellaxis(ylo - m, g.y0, g.h, g.ny)
    j2 = _cellaxis(yhi + m, g.y0, g.h, g.ny)
    return i1:i2, j1:j2
end

# ── concaveman (concaveman.h `concaveman` and `findCandidate`) ─────────────────────────────

mutable struct _Concaveman
    const pts::Vector{_Point2}
    const alive::Vector{Bool}         # still a candidate (in the C++ point R-tree)
    const grid::_Grid
    const cellstart::Vector{Int}      # points by cell, compressed: cell k holds
    const cellpts::Vector{Int}        #   cellpts[cellstart[k]:cellstart[k+1]-1]
    # the boundary as a circular list of vertices; vertex e owns the edge e → nxt[e]
    const P::Vector{_Point2}
    const nxt::Vector{Int}
    const prv::Vector{Int}
    # the edges by cell (the C++ segment R-tree): entries (vertex, version); an entry is
    # current while its version is the vertex's
    const segcells::Vector{Vector{NTuple{2, Int}}}
    const version::Vector{Int}
    const seen::Vector{Int}
    stamp::Int
end

function _Concaveman(pts::Vector{_Point2})
    grid = _Grid(pts)
    ncell = grid.nx * grid.ny
    cellof = [_cellid(grid, _cell(grid, p)...) for p in pts]
    cellstart = zeros(Int, ncell + 1)
    for k in cellof
        cellstart[k + 1] += 1
    end
    cellstart[1] = 1
    for k in 1:ncell
        cellstart[k + 1] += cellstart[k]
    end
    cursor = copy(cellstart)
    cellpts = Vector{Int}(undef, length(pts))
    for (i, k) in enumerate(cellof)       # increasing point index within each cell
        cellpts[cursor[k]] = i
        cursor[k] += 1
    end
    return _Concaveman(pts, fill(true, length(pts)), grid, cellstart, cellpts,
        _Point2[], Int[], Int[], [NTuple{2, Int}[] for _ in 1:ncell], Int[], Int[], 0)
end

# C++ `tree.erase(p)`: the point and every duplicate of it leave the candidates
function _erase_point!(cm::_Concaveman, p::_Point2)
    k = _cellid(cm.grid, _cell(cm.grid, p)...)
    for q in cm.cellstart[k]:(cm.cellstart[k + 1] - 1)
        i = cm.cellpts[q]
        cm.pts[i] == p && (cm.alive[i] = false)
    end
    return nothing
end

function _edgebox(cm::_Concaveman, e::Int)
    p, q = cm.P[e], cm.P[cm.nxt[e]]
    return min(p[1], q[1]), min(p[2], q[2]), max(p[1], q[1]), max(p[2], q[2])
end

# (re)index the edge e → nxt[e] under its current bounding box
function _index_edge!(cm::_Concaveman, e::Int)
    cm.version[e] += 1
    v = cm.version[e]
    xlo, ylo, xhi, yhi = _edgebox(cm, e)
    is, js = _cellspan(cm.grid, xlo, xhi, ylo, yhi)
    for j in js, i in is
        push!(cm.segcells[_cellid(cm.grid, i, j)], (e, v))
    end
    return nothing
end

# concaveman.h `noIntersections`: no current edge whose bounding box meets that of (a, b)
# crosses (a, b)
function _no_intersections(cm::_Concaveman, a::_Point2, b::_Point2)
    xlo, ylo = min(a[1], b[1]), min(a[2], b[2])
    xhi, yhi = max(a[1], b[1]), max(a[2], b[2])
    cm.stamp += 1
    is, js = _cellspan(cm.grid, xlo, xhi, ylo, yhi)
    for j in js, i in is
        for (e, v) in cm.segcells[_cellid(cm.grid, i, j)]
            (v == cm.version[e] && cm.seen[e] != cm.stamp) || continue
            cm.seen[e] = cm.stamp
            exlo, eylo, exhi, eyhi = _edgebox(cm, e)
            (exlo > xhi || exhi < xlo || eylo > yhi || eyhi < ylo) && continue
            _intersects(cm.P[e], cm.P[cm.nxt[e]], a, b) && return false
        end
    end
    return true
end

# the live points with squared distance to the segment (b, c) at most maxsq, as
# (distance, index), nearest first (ties: lower Graham index first)
function _candidates!(out::Vector{Tuple{Float64, Int}}, cm::_Concaveman, b::_Point2, c::_Point2, maxsq::Float64)
    empty!(out)
    r = isnan(maxsq) ? Inf : sqrt(maxsq)   # NaN: the C++ `dist > maxDist` keeps every point
    r = r + 1.0e-9 * r
    is, js = _cellspan(cm.grid, min(b[1], c[1]) - r, max(b[1], c[1]) + r, min(b[2], c[2]) - r, max(b[2], c[2]) + r)
    for j in js, i in is
        k = _cellid(cm.grid, i, j)
        for q in cm.cellstart[k]:(cm.cellstart[k + 1] - 1)
            n = cm.cellpts[q]
            cm.alive[n] || continue
            d = _sqsegdist(cm.pts[n], b, c)
            d > maxsq && continue
            push!(out, (d, n))
        end
    end
    return sort!(out)
end

function _concaveman(pts::Vector{_Point2}, hull::Vector{Int}, concavity::Float64, length_threshold::Float64)
    cm = _Concaveman(pts)
    for h in hull
        _erase_point!(cm, pts[h])
    end
    nh = length(hull)
    for (k, h) in enumerate(hull)
        push!(cm.P, pts[h])
        push!(cm.nxt, k == nh ? 1 : k + 1)
        push!(cm.prv, k == 1 ? nh : k - 1)
        push!(cm.version, 0)
        push!(cm.seen, 0)
    end
    last = nh
    for e in 1:nh
        _index_edge!(cm, e)
    end
    queue = collect(1:nh)
    head = 1
    sqconcavity = concavity * concavity
    sqlenthreshold = length_threshold * length_threshold
    cands = Tuple{Float64, Int}[]
    while head <= length(queue)
        elem = queue[head]
        head += 1
        a = cm.P[cm.prv[elem]]
        b = cm.P[elem]
        c = cm.P[cm.nxt[elem]]
        d = cm.P[cm.nxt[cm.nxt[elem]]]
        sqlen = _sqdist(b, c)
        sqlen < sqlenthreshold && continue
        maxsqlen = sqlen / sqconcavity
        found = 0
        for (dist, n) in _candidates!(cands, cm, b, c, maxsqlen)
            p = pts[n]
            if dist < _sqsegdist(p, a, b) && dist < _sqsegdist(p, c, d) &&
               _no_intersections(cm, b, p) && _no_intersections(cm, c, p)
                found = n
                break
            end
        end
        found == 0 && continue
        p = pts[found]
        min(_sqdist(p, b), _sqdist(p, c)) <= maxsqlen || continue
        # insert p after elem; queue the two new edges
        push!(cm.P, p)
        push!(cm.version, 0)
        push!(cm.seen, 0)
        new = length(cm.P)
        push!(cm.nxt, cm.nxt[elem])
        push!(cm.prv, elem)
        cm.prv[cm.nxt[elem]] = new
        cm.nxt[elem] = new
        push!(queue, elem, new)
        _erase_point!(cm, p)
        _index_edge!(cm, elem)
        _index_edge!(cm, new)
    end
    out = _Point2[]
    e = cm.nxt[last]
    while true
        push!(out, cm.P[e])
        e == last && break
        e = cm.nxt[e]
    end
    return out
end
