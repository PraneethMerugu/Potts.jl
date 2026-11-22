# Ordered relationships (chains) and energies over three consecutive members.
#
# A chain is a link store of degree 2 whose slots have fixed roles: slot 1 of cell `c` holds
# its predecessor, slot 2 its successor (0: none). Each link is still stored at both ends
# (`linked`, `link_slot` and `remove_link!` work as for any relationship), but only
# `add_chain_link!` creates links, so the roles hold. Every path that removes links zeroes
# slots in place, so removal keeps them too. A member's rank is its distance from the head
# of its chain plus one, found by walking the predecessors; it is never stored.

"""
    add_chain_link!(store, a, b; payload...) -> Bool

Link cell `a` to its successor `b` in an ordered link store on the host.

`b` becomes `a`'s successor (slot 2 of `a`) and `a` becomes `b`'s predecessor (slot 1 of
`b`). The link is refused when `a` already has a successor, `b` already has a predecessor,
or `b` is the head of `a`'s chain (the link would close a cycle). Payloads are written as
by [`add_link!`](@ref add_link!).

# Arguments
- `store`: an ordered link store, with two slots per cell (see
  [`maxdegree`](@ref maxdegree)), with host arrays.
- `a`, `b`: the cell numbers.

# Keywords
- `payload...`: the payload values of the new link.

# Returns
- `Bool`: `false` if `a == b`, if either is `0`, if they are already linked, or if the
  link would branch the chain or close a cycle; else `true`.

# Examples
```jldoctest
julia> using CorePotts

julia> s = empty_links(2, 4);

julia> add_chain_link!(s, 1, 2), add_chain_link!(s, 2, 3), add_chain_link!(s, 3, 1)
(true, true, false)

julia> chain_next(s, 1), chain_prev(s, 3), chain_rank(s, 3)
(2, 2, 3)
```

See also [`chain_prev`](@ref), [`chain_next`](@ref), [`chain_rank`](@ref).
"""
function add_chain_link!(cell, a, b; payload...)
    (a == b || a == 0 || b == 0 || linked(cell, a, b)) && return false
    (cell.links[2, a] == 0 && cell.links[1, b] == 0) || return false
    chain_head(cell, a) == b && return false
    cell.links[2, a] = b
    cell.links[1, b] = a
    for name in _payload_names(cell)             # payloads not given start at zero
        arr = getfield(cell, name)
        arr[2, a] = zero(eltype(arr))
        arr[1, b] = zero(eltype(arr))
    end
    for (name, v) in payload
        arr = getfield(cell, Symbol(:link_, name))
        arr[2, a] = v
        arr[1, b] = v
    end
    return true
end

"""
    chain_prev(store, c) -> Int32

Return the predecessor of cell `c` in an ordered link store, or `0` when `c` is a head or
`0`.

# Arguments
- `store`: an ordered link store (see [`add_chain_link!`](@ref)).
- `c`: the cell number, or `0`.

# Returns
- `Int32`: the predecessor, or `0`.

See also [`chain_next`](@ref), [`chain_rank`](@ref).
"""
@inline function chain_prev(cell, c)
    # bounds: slot 1 of a cell id c ∈ 1:capacity
    return c == 0 ? Int32(0) : Int32(@inbounds cell.links[1, c])
end

"""
    chain_next(store, c) -> Int32

Return the successor of cell `c` in an ordered link store, or `0` when `c` is a tail or
`0`.

# Arguments
- `store`: an ordered link store (see [`add_chain_link!`](@ref)).
- `c`: the cell number, or `0`.

# Returns
- `Int32`: the successor, or `0`.

See also [`chain_prev`](@ref), [`chain_rank`](@ref).
"""
@inline function chain_next(cell, c)
    # bounds: slot 2 of a cell id c ∈ 1:capacity
    return c == 0 ? Int32(0) : Int32(@inbounds cell.links[2, c])
end

"""
    chain_rank(store, c) -> Int32

Return the position of cell `c` in its chain: `1` for a head (a cell without a
predecessor), `2` for its successor, and so on. Return `0` for `c == 0`.

A cell in no link is the head of its own chain of one, so its rank is `1`. The rank is
found by walking the predecessors, at most as many steps as there are cell slots.

# Arguments
- `store`: an ordered link store (see [`add_chain_link!`](@ref)).
- `c`: the cell number, or `0`.

# Returns
- `Int32`: the rank, or `0`.

See also [`chain_prev`](@ref), [`add_chain_link!`](@ref).
"""
@inline function chain_rank(cell, c)
    c == 0 && return Int32(0)
    r = Int32(1)
    q = chain_prev(cell, c)
    n = size(cell.links, 2)
    while q != 0 && r <= n                   # `r ≤ n`: a cycle cannot loop forever
        r += Int32(1)
        q = chain_prev(cell, q)
    end
    return r
end

# The head of `c`'s chain (host; `add_chain_link!` refuses a link to it)
function chain_head(cell, c)
    h = c
    for _ in 1:size(cell.links, 2)
        q = chain_prev(cell, h)
        q == 0 && return h
        h = q
    end
    return h
end

"""
    pivot_angle(T, lattice, p, q, n) -> T

Return the angle at `q` between the directions to `p` and to `n`, in `[0, π]`.

The points are positions in lattice coordinates, such as cell centroids. Each arm is the
minimum-image vector on periodic axes, embedded on a hexagonal lattice, so the angle is
the one in the plane of the lattice. Three collinear points in order give `π`. When `q`
coincides with `p` or `n`, the angle is `π` (no bend).

# Arguments
- `T::Type`: the float type of the result.
- `lattice::Lattice`: the lattice.
- `p`, `q`, `n`: the three points, as `N`-tuples.

# Returns
- `T`: the angle, in radians.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((20, 20));

julia> pivot_angle(Float64, l, (1.0, 1.0), (3.0, 1.0), (3.0, 4.0)) ≈ π / 2
true
```

See also [`menger_curvature`](@ref).
"""
@inline function pivot_angle(::Type{T}, l::Lattice, p, q, n) where {T}
    return first(_triple_geometry(T, l, p, q, n))
end

"""
    menger_curvature(T, lattice, p, q, n) -> T

Return the curvature `1/R` of the circle through the points `p`, `q` and `n`: the Menger
curvature `2 sin(θ) / |p − n|`, where `θ` is the angle at `q`.

The arms are minimum-image vectors, as in [`pivot_angle`](@ref). Collinear points give
`0`, and so do points of which two coincide (the circle is undefined).

# Arguments
- `T::Type`: the float type of the result.
- `lattice::Lattice`: the lattice.
- `p`, `q`, `n`: the three points in lattice coordinates, as `N`-tuples.

# Returns
- `T`: the curvature, in inverse embedded lattice units.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((20, 20));

julia> menger_curvature(Float64, l, (1.0, 1.0), (2.0, 2.0), (3.0, 1.0))  # R = 1
1.0
```

See also [`pivot_angle`](@ref).
"""
@inline function menger_curvature(::Type{T}, l::Lattice, p, q, n) where {T}
    return last(_triple_geometry(T, l, p, q, n))
end

# (angle at q, curvature) of the points p, q, n (lattice coordinates)
@inline function _triple_geometry(::Type{T}, l::Lattice{N}, p, q, n) where {T, N}
    u = _min_image(T, l, ntuple(d -> T(p[d]) - T(q[d]), Val(N)))
    v = _min_image(T, l, ntuple(d -> T(n[d]) - T(q[d]), Val(N)))
    uu, vv, uv = zero(T), zero(T), zero(T)
    for d in 1:length(u)
        uu += u[d]^2
        vv += v[d]^2
        uv += u[d] * v[d]
    end
    c = _cross_norm(T, u, v)
    ww = max(uu + vv - 2uv, zero(T))         # |u − v|², the squared chord
    (uu == 0 || vv == 0) && return (T(π), zero(T))
    θ = atan(c, uv)
    den = sqrt(uu * vv * ww)
    return (θ, den == 0 ? zero(T) : 2c / den)
end
@inline _cross_norm(::Type{T}, u::NTuple{1}, v::NTuple{1}) where {T} = zero(T)
@inline _cross_norm(::Type{T}, u::NTuple{2}, v::NTuple{2}) where {T} = abs(
    u[1] * v[2] - u[2] * v[1]
)
@inline function _cross_norm(::Type{T}, u::NTuple{3}, v::NTuple{3}) where {T}
    return sqrt(
        (u[2] * v[3] - u[3] * v[2])^2 + (u[3] * v[1] - u[1] * v[3])^2 +
            (u[1] * v[2] - u[2] * v[1])^2
    )
end

"""
    angle_at(T, fr, cell, lattice, store, j) -> (q, p, n, mode, before, after)

Read the `j`-th triple a copy changes, for the exact energy change of an energy over
three consecutive chain members.

A copy moves one site from `old` to `new` and so shifts both centroids. Every triple
`p – q – n` (`p` the predecessor and `n` the successor of the pivot `q`) that contains
`old` or `new` changes. Its pivot is one of `old`, `new` or their neighbors in the chain,
so `j ∈ 1:6` enumerates the candidate pivots `old`, `prev(old)`, `next(old)`, `new`,
`prev(new)`, `next(new)`. A candidate that is `0`, repeats an earlier one, lacks a
neighbor, or has a dead member (volume 0) is skipped. A killing copy (`old` owns only the
target) removes the triples containing `old`.

Use it with [`link_frame`](@ref link_frame), as [`link_at`](@ref link_at) is used for
pairs.

# Arguments
- `T::Type`: the float type of the geometry.
- `fr`: the frame from [`link_frame`](@ref link_frame).
- `cell`: the cell state, with `volume` and the moment trackers.
- `lattice::Lattice`: the lattice.
- `store`: an ordered link store (see [`add_chain_link!`](@ref)).
- `j::Int`: the candidate, in `1:6`.

# Returns
- `(q, p, n, mode, before, after)`: the pivot, its predecessor and successor, the mode
  (`0`: no triple to count, `1`: the triple dies with `old`, `2`: it stays) and the
  geometry `(angle, curvature)` before and after the copy (see [`pivot_angle`](@ref) and
  [`menger_curvature`](@ref)).

# Examples
```julia
fr = link_frame(T, cell, lat, prop)
for j in 1:6
    q, p, n, m, g0, g1 = angle_at(T, fr, cell, lat, store, j)
    m == 0 && continue                         # no triple to count
    dH += m == 1 ? -E(g0...) : E(g1...) - E(g0...)
end
```
"""
@inline function angle_at(::Type{T}, fr, cell, lat::Lattice{N}, store, j::Int) where {T, N}
    zg = (zero(T), zero(T))
    a, b = fr.a, fr.b
    pa, na = chain_prev(store, a), chain_next(store, a)
    pb, nb = chain_prev(store, b), chain_next(store, b)
    cands = (Int32(a), pa, na, Int32(b), pb, nb)
    q = cands[j]
    none = (q, Int32(0), Int32(0), 0, zg, zg)
    q == 0 && return none
    for i in 1:(j - 1)
        cands[i] == q && return none            # each triple once
    end
    p, n = chain_prev(store, q), chain_next(store, q)
    (p == 0 || n == 0) && return none
    # bounds: p, q, n are linked cell ids ≤ capacity = length(volume)
    Vp, Vq, Vn = @inbounds(cell.volume[p]), @inbounds(cell.volume[q]),
        @inbounds(cell.volume[n])
    (Vp == 0 || Vq == 0 || Vn == 0) && return none        # a dead member: not counted
    cp, cq, cn = _member_centroid(T, cell, lat, fr, p, Vp),
        _member_centroid(T, cell, lat, fr, q, Vq), _member_centroid(T, cell, lat, fr, n, Vn)
    before = _triple_geometry(T, lat, cp, cq, cn)
    fr.kill && (p == a || q == a || n == a) && return (q, p, n, 1, before, zg)
    after = _triple_geometry(
        T, lat, _shifted(fr, cp, p, Val(N)), _shifted(fr, cq, q, Val(N)),
        _shifted(fr, cn, n, Val(N))
    )
    return (q, p, n, 2, before, after)
end
# a member's centroid before the copy (the frame's for `old` and `new`)
@inline function _member_centroid(::Type{T}, cell, lat, fr, c, V) where {T}
    c == fr.a && return fr.ca
    c == fr.b && return fr.cb
    return _centroid(T, cell, lat, c, V)
end
# the centroid after the copy: `old` and `new` shift, others stay
@inline function _shifted(fr, x, c, ::Val{N}) where {N}
    s = c == fr.a ? fr.sa : c == fr.b ? fr.sb : fr.z
    return ntuple(d -> x[d] + s[d], Val(N))
end
