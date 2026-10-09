# The Euler-characteristic tracker (P6.3j, D-192; design note
# `docs/design/research/euler-tracker.md`). A cell's site set X is a cell complex whose
# topology the adjacency names; its complement is read with the dual adjacency (the
# Rosenfeld pairing):
#
#   square `:face` 4/8   sites, 4-adjacent pairs, full 2×2 blocks
#   square `:full` 8/4   the union of closed unit pixels
#   hex (6/6)            sites, adjacent pairs, triangles (`:face` and `:full` alike)
#   cubic `:face` 6/26   sites, 6-adjacent pairs, full 2×2 squares, full 2×2×2 cubes
#   cubic `:full` 26/6   the union of closed unit voxels
#
# Out-of-domain sites are never in X; on a periodic axis χ is that of the subcomplex of the
# torus. A copy changes χ of the losing and the gaining cell only, by `∓D(m)` with `m` the
# cell's membership mask on the target's 8-, 6- or 26-site shell: popcounts and mask tests,
# no table, no float.

# Square shell, bit k-1 ↔ offset k: round the box from (−1, −1).
const _EULER_RING2 = ((-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1))
const _EULER_FACE4 = UInt32(0b10101010)
# corner | face | face: x and the trio make one 2×2 block
const _EULER_TRIOS2 = (UInt32(0b10000011), UInt32(0b00001110), UInt32(0b00111000), UInt32(0b11100000))

# Cubic shell: bit k-1 ↔ `_CUBIC_SHELL[k]`.
_euler_bit3(o) = UInt32(1) << (findfirst(==(o), _CUBIC_SHELL) - 1)
const _EULER_FACE6 = reduce(|, _euler_bit3(o) for o in _CUBIC_SHELL if count(!=(0), o) == 1)
# an edge-diagonal neighbour with its two face neighbours: x and the trio make one 2×2 square
const _EULER_TRIOS3 = Tuple(_euler_bit3(o) | _euler_bit3(ntuple(k -> k == a ? o[a] : 0, 3)) |
                            _euler_bit3(ntuple(k -> k == b ? o[b] : 0, 3))
                            for o in _CUBIC_SHELL if count(!=(0), o) == 2
                            for (a, b) in ((findfirst(!=(0), o), findlast(!=(0), o)),))
# the 7 shell voxels of one 2×2×2 cube containing x
const _EULER_OCTANTS = Tuple(reduce(|, _euler_bit3(o) for o in _CUBIC_SHELL if all(k -> o[k] == 0 || o[k] == s[k], 1:3))
                             for s in Iterators.product((-1, 1), (-1, 1), (-1, 1)))
const _EULER_ALL26 = UInt32(0x03ffffff)

@inline _popcount32(m::UInt32) = count_ones(m) % Int32
@inline _has(m::UInt32, t::UInt32) = (m & t) == t
@inline function _count_has(m::UInt32, ts::NTuple{K, UInt32}) where {K}
    n = Int32(0)
    for k in 1:K
        n += Int32(_has(m, ts[k]))
    end
    return n
end

# Δχ when the target joins a set with shell mask `m`
@inline _euler_d4(m::UInt32) = Int32(1) - _popcount32(m & _EULER_FACE4) + _count_has(m, _EULER_TRIOS2)
@inline _euler_d8(m::UInt32) = _euler_d4(~m & UInt32(0xff))                 # 2D duality
@inline _euler_dhex(m::UInt32) = Int32(1) - _popcount32(m) + _popcount32(m & ((m >> 1) | ((m & UInt32(1)) << 5)))
@inline _euler_d6(m::UInt32) = Int32(1) - _popcount32(m & _EULER_FACE6) + _count_has(m, _EULER_TRIOS3) -
                               _count_has(m, _EULER_OCTANTS)
@inline _euler_d26(m::UInt32) = -_euler_d6(~m & _EULER_ALL26)              # 3D: χ(X) = χ(Xᶜ)

# membership masks of `a` and `b` on a shell of owners
@inline function _shell_masks(owners::NTuple{K}, a, b) where {K}
    ma = UInt32(0)
    mb = UInt32(0)
    for k in 1:K
        o = owners[k]
        ma |= UInt32(o == a) << (k - 1)
        mb |= UInt32(o == b) << (k - 1)
    end
    return ma, mb
end

"""
    euler_change(σ, ctx, prop, Val(adjacency)) -> (δold::Int32, δnew::Int32)

Exact change of the Euler characteristics of the old and new cells under `adjacency`
(`:face` or `:full`; hexagonal lattices have one self-dual adjacency) when `prop`'s target
changes owner. Reads the target's neighbour shell; the target itself is not read, so the
result is the same before and after the ownership write. The medium's side is zero.
"""
@inline euler_change(σ, ctx, prop::Proposal, adj::Val) = _euler_change(ctx.lattice, σ, prop, adj)

@inline function _euler_change(lat::Lattice{2, M, Hexagonal}, σ, prop::Proposal{2}, ::Val) where {M}
    mo, mn = _shell_masks(_owners(lat, σ, prop.x, _HEX_RING), prop.old, prop.new)
    return _euler_sides(prop, _euler_dhex(mo), _euler_dhex(mn))
end
@inline function _euler_change(lat::Lattice{2}, σ, prop::Proposal{2}, ::Val{A}) where {A}
    mo, mn = _shell_masks(_owners(lat, σ, prop.x, _EULER_RING2), prop.old, prop.new)
    A === :full && return _euler_sides(prop, _euler_d8(mo), _euler_d8(mn))
    return _euler_sides(prop, _euler_d4(mo), _euler_d4(mn))
end
@inline function _euler_change(lat::Lattice{3}, σ, prop::Proposal{3}, ::Val{A}) where {A}
    mo, mn = _shell_masks(_owners(lat, σ, prop.x, _CUBIC_SHELL), prop.old, prop.new)
    A === :full && return _euler_sides(prop, _euler_d26(mo), _euler_d26(mn))
    return _euler_sides(prop, _euler_d6(mo), _euler_d6(mn))
end
# the old cell loses the target, the new one gains it; the medium has no entry
@inline _euler_sides(prop, dold::Int32, dnew::Int32) =
    (ifelse(prop.old == 0, Int32(0), -dold), ifelse(prop.new == 0, Int32(0), dnew))

"""Apply `δ = euler_change(…)` to an Euler tracker (the old and new cells only)."""
@inline function commit_euler!(euler, prop, δ)
    prop.old != 0 && @inbounds(euler[prop.old] += δ[1])
    prop.new != 0 && @inbounds(euler[prop.new] += δ[2])
    return nothing
end

# ---------------------------------------------------------------------------------------
# From scratch: one anchor per vertex of the grid, `dims .+ 1` on a closed axis (the far
# corners of the last sites), `dims` on a periodic one. Each anchor adds the signed counts
# of the complex cells it anchors to their cells (atomically: the same body runs as a device
# kernel, `_deuler_body!`), so the per-cell sums are exact integers in any order.

@inline _euler_extent(lat::Lattice{N}) where {N} = ntuple(d -> lat.dims[d] + (lat.periodic[d] ? 0 : 1), Val(N))
"""Number of anchors of the rebuild (`_euler_window!`)."""
@inline _euler_anchors(lat::Lattice) = prod(_euler_extent(lat))

@inline function _euler_anchor(lat::Lattice{N}, a::Int) where {N}
    E = _euler_extent(lat)
    return ntuple(Val(N)) do d
        stride = prod(ntuple(e -> e < d ? E[e] : 1, Val(N)))
        rem(div(a - 1, stride), E[d]) + 1
    end
end

# the owner of index `j` (wrapped on periodic axes), −1 outside the lattice or its domain
@inline function _euler_owner(lat::Lattice{N}, σ, j::NTuple{N, Int}) where {N}
    inside = all(ntuple(d -> lat.periodic[d] || 1 <= j[d] <= lat.dims[d], Val(N)))
    w = ntuple(d -> lat.periodic[d] ? mod1(j[d], lat.dims[d]) : clamp(j[d], 1, lat.dims[d]), Val(N))
    inside || return -one(eltype(σ))
    i = linear_index(lat, w)
    _euler_in_domain(lat.mask, i) || return -one(eltype(σ))
    return @inbounds σ[i]
end
@inline _euler_in_domain(::Nothing, i) = true
@inline _euler_in_domain(m, i) = @inbounds m[i]

@inline _euler_add!(col, c, s) = (c > 0 && (Atomix.@atomic col[c] += s); nothing)

# corner `v` plus the 0/1 pattern `e` (bit d-1 ↔ axis d), signed
@inline _euler_offset(v::NTuple{N, Int}, e::Int, sgn::Int) where {N} = ntuple(d -> v[d] + sgn * ((e >> (d - 1)) & 1), Val(N))

"""
Add the contributions of anchor `a` (`1:_euler_anchors(lat)`) to `col`, the Euler tracker
under `adjacency`.
"""
@inline function _euler_window!(col, σ, lat::Lattice{2, M, Hexagonal}, a::Int, ::Val) where {M}
    v = _euler_anchor(lat, a)
    all(ntuple(d -> v[d] <= lat.dims[d], Val(2))) || return nothing
    c = _euler_owner(lat, σ, v)
    r = _euler_owner(lat, σ, (v[1] + 1, v[2]))
    u = _euler_owner(lat, σ, (v[1], v[2] + 1))
    s = Int32(1) - Int32(r == c) - Int32(u == c) - Int32(_euler_owner(lat, σ, (v[1] - 1, v[2] + 1)) == c) +
        Int32(r == c && u == c)
    _euler_add!(col, c, s)
    # the triangle (v + (1, 0), v + (0, 1), v + (1, 1)), which v is not in
    (r == u && _euler_owner(lat, σ, (v[1] + 1, v[2] + 1)) == r) && _euler_add!(col, r, Int32(1))
    return nothing
end

@inline function _euler_window!(col, σ, lat::Lattice{N}, a::Int, ::Val{A}) where {N, A}
    v = _euler_anchor(lat, a)
    A === :full ? _euler_closed!(col, σ, lat, v) : _euler_graph!(col, σ, lat, v)
    return nothing
end

# graph complex (`:face`): the cells v + {0,1}^S (S a set of axes) all owned by v's owner
@inline function _euler_graph!(col, σ, lat::Lattice{N}, v) where {N}
    all(ntuple(d -> v[d] <= lat.dims[d], Val(N))) || return nothing
    c = _euler_owner(lat, σ, v)
    c > 0 || return nothing
    s = Int32(0)
    for S in 0:((1 << N) - 1)
        full = true
        for e in 1:S                            # the non-empty sub-patterns of S
            (e & S) == e || continue
            _euler_owner(lat, σ, _euler_offset(v, e, 1)) == c || (full = false)
        end
        full && (s += isodd(count_ones(S)) ? Int32(-1) : Int32(1))
    end
    _euler_add!(col, c, s)
    return nothing
end

# union of closed unit voxels (`:full`): the face of corner v spanning the axes S belongs to
# each distinct owner of the voxels around it, v − e with e over the axes outside S
@inline function _euler_closed!(col, σ, lat::Lattice{N}, v) where {N}
    all1 = (1 << N) - 1
    for S in 0:all1
        sgn = isodd(count_ones(S)) ? Int32(-1) : Int32(1)
        rest = all1 & ~S
        for e in 0:rest
            (e & rest) == e || continue
            c = _euler_owner(lat, σ, _euler_offset(v, e, -1))
            c > 0 || continue
            seen = false
            for f in 0:(e - 1)                  # owners of the earlier voxels round this face
                (f & rest) == f || continue
                _euler_owner(lat, σ, _euler_offset(v, f, -1)) == c && (seen = true)
            end
            seen || _euler_add!(col, c, sgn)
        end
    end
    return nothing
end

"""
    recompute_euler(σ, lattice, Val(adjacency), ncell) -> Vector{Int32}

Euler characteristics of cells `1:ncell` under `adjacency` (`:face` or `:full`), from
scratch (initialization, lifecycle events, host edits of σ).
"""
function recompute_euler(σ, lat::Lattice, adj::Val, ncell::Integer)
    χ = zeros(Int32, ncell)
    for a in 1:_euler_anchors(lat)
        _euler_window!(χ, σ, lat, a, adj)
    end
    return χ
end

# the Euler columns present in a cell state: `(face, full)`, each a column or `nothing`;
# `nothing` when there is none (no code runs)
@inline _euler_columns(cell) = _euler_columns(haskey(cell, :euler) ? cell.euler : nothing,
    haskey(cell, :euler_full) ? cell.euler_full : nothing)
@inline _euler_columns(::Nothing, ::Nothing) = nothing
@inline _euler_columns(a, b) = (a, b)

# host rebuild of every Euler column (`_rebuild_trackers!`)
function _rebuild_euler!(stats, st, σ, lat, cap)
    haskey(st.cell, :euler) && _copy!(stats, st.cell.euler, recompute_euler(σ, lat, Val(:face), cap))
    haskey(st.cell, :euler_full) && _copy!(stats, st.cell.euler_full, recompute_euler(σ, lat, Val(:full), cap))
    return nothing
end

# device rebuild (`lifecycle_device.jl`): zero every slot, then sum the windows
@inline _ezero!(::Nothing, c) = nothing
@inline _ezero!(col, c) = (@inbounds col[c] = Int32(0); nothing)
@inline function _deuler_zero_body!(c, dv, par, cols)
    _on(dv, par) || return nothing
    _ezero!(cols[1], c)
    _ezero!(cols[2], c)
    return nothing
end
@inline _ewin!(::Nothing, σ, lat, a, adj) = nothing
@inline _ewin!(col, σ, lat, a, adj) = _euler_window!(col, σ, lat, a, adj)
@inline function _deuler_body!(a, dv, par, σ, cols, lat)
    _on(dv, par) || return nothing
    _ewin!(cols[1], σ, lat, a, Val(:face))
    _ewin!(cols[2], σ, lat, a, Val(:full))
    return nothing
end
