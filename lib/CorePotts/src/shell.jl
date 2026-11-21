# ---------------------------------------------------------------------------------------
# The target's neighbour shell and the local connectivity rules over it (D-189)
#
# The SHELL of a target x is the 8 sites of its 3×3 box (square 2D), its 6 neighbours (hex)
# or the 26 sites of its 3×3×3 box (cubic 3D), whatever the model's neighbourhood. A shell
# position off a closed face (or outside the domain mask) is out of domain: its owner reads
# −1 (an `Int32`, whatever σ's eltype), never the medium (0) nor a cell (> 0). The rules
# below work on bit masks over the shell positions: runs of a ring in 2D, whole-mask
# dilation in a 3×3×3 box in 3D; no `Float64`, no `throw`, no allocation.

# Shell offsets: ternary order (axis 1 fastest, the origin left out) on square and cubic
# lattices, angular order on the hexagonal one.
const _SQUARE_SHELL = Tuple(Int32.((i, j)) for j in -1:1 for i in -1:1 if (i, j) != (0, 0))
const _HEX_SHELL = map(o -> Int32.(o), ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)))
const _CUBE_SHELL = Tuple(
    Int32.((i, j, k)) for k in -1:1 for j in -1:1
        for i in -1:1 if (i, j, k) != (0, 0, 0)
)

"""
    shell_offsets(lattice) -> Tuple

Return the offsets of the target's neighbor shell.

The shell is the 8 sites of the 3×3 box on a square lattice, the 6 neighbors on a
hexagonal lattice, and the 26 sites of the 3×3×3 box on a cubic lattice, whatever the
model's neighborhood. The square and cubic offsets are in ternary order (axis 1 fastest,
the origin left out); the hexagonal offsets go round the target.

# Arguments
- `lattice::Lattice`: a 2D or 3D lattice.

# Returns
- A tuple of `Int32` offset tuples. Shell masks use bit `k - 1` for offset `k`.

# Examples
```jldoctest
julia> using CorePotts

julia> o = CorePotts.shell_offsets(Lattice((5, 5)));

julia> length(o), o[1], o[8]
(8, (-1, -1), (1, 1))
```

See also [`shell_owners`](@ref).
"""
@inline shell_offsets(::Lattice{2, M, Hexagonal}) where {M} = _HEX_SHELL
@inline shell_offsets(::Lattice{2}) = _SQUARE_SHELL
@inline shell_offsets(::Lattice{3}) = _CUBE_SHELL

function _bits(offs, pred)
    return foldl(
        (m, j) -> pred(offs[j]) ? m | (UInt32(1) << (j - 1)) : m, eachindex(offs);
        init = UInt32(0)
    )
end

# cubic masks over `_CUBE_SHELL`: the face neighbours of x, the near set of `Simple()` (the
# 18-neighbourhood), every position. The 2D shells are rings (`_RING_BIT2`, below).
const _CUBE_TABLES = (;
    xface = _bits(_CUBE_SHELL, o -> sum(abs, o) == 1), near = _bits(
        _CUBE_SHELL, o -> sum(abs, o) <=
            2
    ),
    all = _bits(_CUBE_SHELL, _ -> true),
)

@inline _shell_tables(::Lattice{2}) = nothing
@inline _shell_tables(::Lattice{3}) = _CUBE_TABLES

"""
    shell_owners(lattice, σ, x) -> NTuple{K, Int32}

Return the owners of the shell positions of site `x`, in the order of
[`shell_offsets`](@ref).

A position off a closed face, or outside the domain mask, reads `-1`, whatever the
element type of `σ`. If `x` itself is outside the domain mask, every position reads `-1`.

# Arguments
- `lattice::Lattice`: the lattice of `σ`.
- `σ`: the `ownership` array.
- `x`: the site, as a coordinate tuple.

# Returns
- `NTuple{K, Int32}`: one owner per shell position.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((3, 3); boundary = Closed()); σ = Int32[1 2 0; 1 1 0; 3 0 0];

julia> CorePotts.shell_owners(l, σ, (1, 1))
(-1, -1, -1, -1, 1, -1, 2, 1)
```

See also [`read_shell`](@ref), [`shell_mask`](@ref).
"""
@inline function shell_owners(lat::Lattice{N}, σ, x) where {N}
    offs = shell_offsets(lat)
    # one wrap per axis (x[d] − 1, x[d], x[d] + 1) instead of one `shift` per position
    ax = ntuple(d -> _box_axis(lat, x, d), Val(N))
    xin = _mask_at(lat.mask, linear_index(lat, x))
    return ntuple(Val(length(offs))) do k
        # bounds: k ≤ length(offs); o[d] ∈ -1:1, so o[d] + 2 ∈ 1:3, the axis entries
        o = @inbounds offs[k]
        i = 1 + sum(ntuple(d -> @inbounds(ax[d][1][o[d] + 2]), Val(N)))
        inside = all(ntuple(d -> @inbounds(ax[d][2][o[d] + 2]), Val(N)))
        # i is in 1:nsites (each axis term is clamped onto the lattice), so the load is safe
        # even off a closed face, where `inside` discards it
        inside &= xin & _mask_at(lat.mask, i)
        ifelse(inside, Int32(@inbounds σ[i]), Int32(-1))
    end
end

# axis d of the 3^N box round x: the strided offsets of x[d] − 1, x[d], x[d] + 1 (wrapped on
# a periodic axis, clamped onto a closed one, as `shift`) and whether each is in the lattice
@inline function _box_axis(lat::Lattice{N}, x, d) where {N}
    n = lat.dims[d]
    p = lat.periodic[d]
    v = x[d]
    stride = prod(ntuple(e -> e < d ? lat.dims[e] : 1, Val(N)))
    lo = ifelse(v > 1, v - 1, ifelse(p, n, 1))
    hi = ifelse(v < n, v + 1, ifelse(p, 1, n))
    return ((lo - 1) * stride, (v - 1) * stride, (hi - 1) * stride),
        (p | (v > 1), true, p | (v < n))
end
@inline _mask_at(::Nothing, i) = true
@inline _mask_at(m, i) = @inbounds m[i]          # i in 1:nsites (`shell_owners`)

"""
    check_shell_lattice(lattice, quantity) -> nothing

Throw an `ArgumentError` that names `quantity` when `lattice` has a periodic axis of
length 1.

On such an axis the target's neighbor shell wraps onto the target itself, so every
quantity that reads the shell would read the target as its own neighbor. Potts runs the
check on the host when a problem is built, and [`recompute_euler`](@ref) runs it too.

# Arguments
- `lattice::Lattice`: the lattice.
- `quantity::AbstractString`: the name of the quantity, for the error message.

# Returns
- `nothing`.

See also [`shell_owners`](@ref).
"""
function check_shell_lattice(lat::Lattice{N}, quantity::AbstractString) where {N}
    for d in 1:N
        lat.periodic[d] && lat.dims[d] == 1 && throw(
            ArgumentError(
                "`$quantity` reads the target's neighbor shell, which needs every " *
                    "periodic axis to have length ≥ 2: axis $d is periodic with length " *
                    "1, so the shell wraps onto the target itself; use a $(N - 1)D \
                        lattice, or make axis $d Closed (or longer)"
            )
        )
    end
    return nothing
end

"""
    ShellRead(owners)

The owners of a target's shell, read once and shared by every shell kernel of one
generated function.

[`local_rule`](@ref), [`arc_or_pair`](@ref), [`simple_point`](@ref),
[`euler_change`](@ref) and the `ring_*` built-ins take it in place of `σ`.

# Fields
- `owners::NTuple{K, Int32}`: the owners, as [`shell_owners`](@ref) returns them.

See also [`read_shell`](@ref).
"""
struct ShellRead{K}
    owners::NTuple{K, Int32}
end
"""
    read_shell(σ, ctx, prop) -> ShellRead

Read the shell of the copy's target into a [`ShellRead`](@ref).

If `σ` is already a `ShellRead`, it is returned as it is.

# Arguments
- `σ`: the `ownership` array, or a `ShellRead`.
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `ShellRead`.

See also [`shell_owners`](@ref).
"""
@inline read_shell(σ, ctx, prop::Proposal) = ShellRead(shell_owners(ctx.lattice, σ, prop.x))
@inline read_shell(s::ShellRead, ctx, prop::Proposal) = s

"""
    shell_mask(owners, c) -> UInt32

Return the mask of the shell positions owned by `c`: bit `k - 1` is set when
`owners[k] == c`.

# Arguments
- `owners::NTuple{K, Int32}`: the shell owners.
- `c`: the owner to match; `-1` matches the out-of-domain positions.

# Returns
- `UInt32`: the mask.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.shell_mask(Int32.((1, 2, 1)), 1)
0x00000005
```

See also [`shell_pieces`](@ref).
"""
@inline function shell_mask(owners::NTuple{K, Int32}, c) where {K}
    m = UInt32(0)
    for k in 1:K
        # bounds: k ≤ K = length(owners)
        m |= ifelse(@inbounds(owners[k]) == c, UInt32(1) << (k - 1), UInt32(0))
    end
    return m
end

# ---------------------------------------------------------------------------------------
# Ring masks. On the square 2D shell the kernels place position k at bit
# `_RING_BIT2[k]`: round the box from (−1, −1) (`_SQUARE_RING`, the Euler tracker's order),
# so corners sit at the even bits, face neighbours at the odd ones, and consecutive bits
# (cyclically) are exactly the face-adjacent pairs. Face pieces are then runs; the hexagonal
# 6-ring (`_HEX_SHELL`, angular order) is a ring already.
const _SQUARE_RING = ((-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1))
const _RING_BIT2 = map(o -> Int32(findfirst(==(Int.(o)), _SQUARE_RING) - 1), _SQUARE_SHELL)
const _RING_ALL8 = UInt32(0xff)
const _RING_EDGES8 = UInt32(0xaa)
const _RING_CORNERS8 = UInt32(0x55)
const _RING_ALL6 = UInt32(0x3f)

@inline _ring_bits(::Lattice{2, M, Hexagonal}) where {M} = Val(:ring6)
@inline _ring_bits(::Lattice{2}) = Val(:ring8)
@inline _ring_bits(::Lattice{3}) = Val(:box)

# masks of `a` and `b` over the owners, in the lattice's bit order
@inline _bitpos(::Val{:ring8}, k) = @inbounds _RING_BIT2[k]
@inline _bitpos(::Val, k) = Int32(k - 1)
@inline function _masks2(owners::NTuple{K, Int32}, a, b, r::Val) where {K}
    # bounds: k ≤ K = length(owners)
    ma = reduce(|, ntuple(k -> UInt32(@inbounds(owners[k]) == a) << _bitpos(r, k), Val(K)))
    mb = reduce(|, ntuple(k -> UInt32(@inbounds(owners[k]) == b) << _bitpos(r, k), Val(K)))
    return ma, mb
end
@inline _mask1(owners, c, r::Val) = _masks2(owners, c, c, r)[1]

@inline _rotl8(m::UInt32) = ((m << 1) | (m >> 7)) & _RING_ALL8      # bit i ← bit i − 1
@inline _rotr8(m::UInt32) = ((m >> 1) | (m << 7)) & _RING_ALL8      # bit i ← bit i + 1
@inline _rotl6(m::UInt32) = ((m << 1) | (m >> 5)) & _RING_ALL6
# runs of a cyclic ring mask (1 when every bit is set)
@inline function _runs8(m::UInt32)
    return ifelse(
        m == _RING_ALL8, Int32(1), count_ones(m & ~_rotl8(m)) %
            Int32
    )
end
@inline function _runs6(m::UInt32)
    return ifelse(
        m == _RING_ALL6, Int32(1), count_ones(m & ~_rotl6(m)) %
            Int32
    )
end
# square ring: 8-adjacent pieces are the runs once each corner between two set face
# neighbours is filled in (the two are diagonal neighbours)
@inline _fill8(m::UInt32) = m | (_RING_CORNERS8 & _rotl8(m) & _rotr8(m))
# face pieces that contain a face neighbour of x: the runs less the isolated corners
@inline function _runs8_touching(m::UInt32)
    return _runs8(m) - (count_ones(m & _RING_CORNERS8 & ~(_rotl8(m) | _rotr8(m))) % Int32)
end

# pieces of a mask in the lattice's bit order
@inline function _pieces(
        m::UInt32, full::Bool, ::Val{:ring8},
        t
    )
    return _runs8(ifelse(full, _fill8(m), m))
end
@inline _pieces(m::UInt32, full::Bool, ::Val{:ring6}, t) = _runs6(m)
@inline _pieces(m::UInt32, full::Bool, ::Val{:box}, t) = _components27(m, full)
@inline _all_bits(::Val{:ring8}, t) = _RING_ALL8
@inline _all_bits(::Val{:ring6}, t) = _RING_ALL6
@inline _all_bits(::Val{:box}, t) = t.all
@inline _xface_bits(::Val{:ring8}, t) = _RING_EDGES8
@inline _xface_bits(::Val{:ring6}, t) = _RING_ALL6
@inline _xface_bits(::Val{:box}, t) = t.xface

# ternary-order square mask → ring order
@inline function _to_ring8(m::UInt32)
    return reduce(
        |, ntuple(k -> ((m >> (k - 1)) & UInt32(1)) << _bitpos(Val(:ring8), k), Val(8))
    )
end

# Pieces of a cubic shell mask: the 26 positions sit in a 27-bit 3×3×3 box (bit
# i + 3j + 9k, the empty centre at bit 13), where one face step is a shift by 1, 3 or 9 and
# a full step the product of the three axis dilations. Each piece grows from its lowest bit
# by whole-mask dilation until it stops; no table, no division. The pieces counted are those
# meeting `touch`.
@inline _to27(m::UInt32) = (m & UInt32(0x1fff)) | ((m & ~UInt32(0x1fff)) << 1)
const _BOX27 = Tuple((i, j, k) for k in 0:2 for j in 0:2 for i in 0:2)
function _box27(f)
    return reduce(
        |, (UInt32(1) << (p - 1) for p in 1:27 if f(_BOX27[p]...));
        init = UInt32(0)
    )
end
const _NOT_I2 = ~_box27((i, j, k) -> i == 2)
const _NOT_I0 = ~_box27((i, j, k) -> i == 0)
const _NOT_J2 = ~_box27((i, j, k) -> j == 2)
const _NOT_J0 = ~_box27((i, j, k) -> j == 0)
@inline _step_i(r::UInt32) = ((r & _NOT_I2) << 1) | ((r & _NOT_I0) >> 1)
@inline _step_j(r::UInt32) = ((r & _NOT_J2) << 3) | ((r & _NOT_J0) >> 3)
@inline _step_k(r::UInt32) = (r << 9) | (r >> 9)
@inline _dilate_face(r::UInt32) = r | _step_i(r) | _step_j(r) | _step_k(r)
@inline function _dilate_full(r::UInt32)
    a = r | _step_i(r)
    b = a | _step_j(a)
    return b | _step_k(b)
end
@inline function _components27(m::UInt32, full::Bool, touch::UInt32 = typemax(UInt32))
    mask = _to27(m)
    touch27 = _to27(touch)
    n = Int32(0)
    while mask != 0
        reached = mask & (~mask + UInt32(1))         # the lowest set bit
        while true
            grown = (full ? _dilate_full(reached) : _dilate_face(reached)) & mask
            grown == reached && break
            reached = grown
        end
        mask &= ~reached
        n += Int32((reached & touch27) != 0)
    end
    return n
end

"""
    shell_pieces(lattice, mask, full) -> Int32

Count the components of the shell positions in `mask`.

Two positions are joined when they are face neighbors (`full = false`) or any neighbors
(`full = true`). On a hexagonal lattice the two adjacencies are the same.

# Arguments
- `lattice::Lattice`: the lattice, which sets the shell.
- `mask::UInt32`: the positions, bit `k - 1` for offset `k` of
  [`shell_offsets`](@ref).
- `full::Bool`: join any neighbors, not only face neighbors.

# Returns
- `Int32`: the number of components.

# Examples
The shell positions `(0, -1)` and `(1, 0)` are diagonal neighbors:
```jldoctest
julia> using CorePotts

julia> l = Lattice((5, 5)); m = UInt32(0b10010);

julia> CorePotts.shell_pieces(l, m, false), CorePotts.shell_pieces(l, m, true)
(2, 1)
```

See also [`shell_mask`](@ref).
"""
@inline function shell_pieces(lat::Lattice, mask::UInt32, full::Bool)
    r = _ring_bits(lat)
    return _pieces(r isa Val{:ring8} ? _to_ring8(mask) : mask, full, r, _shell_tables(lat))
end

"""
    local_rule(σ, ctx, prop, gain, full) -> Bool

Evaluate the local connectivity rule `Local(; gain, adjacency)` for the losing cell.

The result is `true` when the losing cell is the medium. Otherwise it is `true` when
all of these hold:

- the losing cell's shell positions form exactly one piece (zero pieces fails);
- the shell is not full (every position in the domain and owned by the losing cell);
- if `gain`, the gaining cell owns a shell site adjacent to the target: a face neighbor,
  or any shell site when `full`.

# Arguments
- `σ`: the `ownership` array, or a [`ShellRead`](@ref).
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.
- `gain::Bool`: also require the gaining cell next to the target.
- `full::Bool`: use full adjacency for the pieces and the gain test.

# Returns
- `Bool`: whether the copy keeps the rule.

See also [`simple_point`](@ref), [`arc_or_pair`](@ref).
"""
@inline function local_rule(σ, ctx, prop::Proposal, gain::Bool, full::Bool)
    return prop.old == 0 ||
        _local_rule(read_shell(σ, ctx, prop), ctx.lattice, prop, gain, full)
end
@inline function _local_rule(s::ShellRead, lat, prop::Proposal, gain::Bool, full::Bool)
    r = _ring_bits(lat)
    t = _shell_tables(lat)
    m, mn = _masks2(s.owners, prop.old, prop.new, r)
    m == _all_bits(r, t) && return false
    _pieces(m, full, r, t) == 1 || return false
    gain || return true
    return (mn & (full ? _all_bits(r, t) : _xface_bits(r, t))) != 0
end

"""
    arc_or_pair(σ, ctx, prop) -> Bool

Evaluate the connectivity rule `ArcOrPair()` for the losing cell.

The result is `true` when the losing cell is the medium. Otherwise it is `true` when the
losing cell's shell positions form at most one face piece, or when exactly two distinct
cells and no medium are on the shell. The out-of-domain positions, if any, count as one
extra cell (the frame of the Tissue Simulation Toolkit).

# Arguments
- `σ`: the `ownership` array, or a [`ShellRead`](@ref).
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.

# Returns
- `Bool`: whether the copy keeps the rule.

See also [`local_rule`](@ref), [`simple_point`](@ref).
"""
@inline function arc_or_pair(σ, ctx, prop::Proposal)
    return prop.old == 0 ||
        _arc_or_pair(read_shell(σ, ctx, prop), ctx.lattice, prop)
end
@inline function _arc_or_pair(s::ShellRead, lat, prop::Proposal)
    r = _ring_bits(lat)
    owners = s.owners
    _pieces(_mask1(owners, prop.old, r), false, r, _shell_tables(lat)) <= 1 && return true
    shell_mask(owners, 0) == 0 || return false
    # exactly two of {cells on the shell, the frame}: `old` (present, it has ≥ 2 pieces) and
    # either one other cell owning every remaining position, or the frame alone (O(K), no
    # pairwise distinct count)
    neg = shell_mask(owners, -1)
    rest = ~(shell_mask(owners, prop.old) | neg) &
        ((UInt32(1) << length(owners)) - UInt32(1))
    rest == 0 && return neg != 0
    other = reduce(max, map(o -> ifelse(o == prop.old, Int32(0), o), owners))
    return neg == 0 && shell_mask(owners, other) == rest
end

"""
    simple_point(σ, ctx, prop, c, full) -> Bool

Return `true` if the target is a simple point of cell `c`: the connectivity rule
`Simple(; adjacency)`.

The test reads `c`'s shell sites with the target. Out-of-domain positions count as
background. The result is `true` when `c` is the medium.

- 2D, `full = false`: one 4-component of `c` in the 8-site shell that touches a face
  neighbor, and one 8-component of the background. `full = true` swaps the adjacencies.
- 3D: the same with 6-adjacency (over the 18-neighborhood) and 26-adjacency.
- Hexagonal: one arc of `c` and one arc of the background.

# Arguments
- `σ`: the `ownership` array, or a [`ShellRead`](@ref).
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt; the function reads its target.
- `c`: the cell to test.
- `full::Bool`: use full adjacency for `c`.

# Returns
- `Bool`: whether the target is a simple point of `c`.

See also [`local_rule`](@ref), [`arc_or_pair`](@ref).
"""
@inline function simple_point(σ, ctx, prop::Proposal, c, full::Bool)
    return c == 0 || _simple_point(read_shell(σ, ctx, prop), ctx.lattice, c, full)
end
@inline function _simple_point(s::ShellRead, lat, c, full::Bool)
    r = _ring_bits(lat)
    t = _shell_tables(lat)
    X = _mask1(s.owners, c, r)
    Bg = ~X & _all_bits(r, t)
    return _simple(X, Bg, full, r, t)
end
@inline _simple(X, Bg, full, ::Val{:ring6}, t) = _runs6(X) == 1 && _runs6(Bg) == 1
@inline function _simple(X, Bg, full, ::Val{:ring8}, t)
    if full
        return _runs8(_fill8(X)) == 1 && _runs8_touching(Bg) == 1
    else
        return _runs8_touching(X) == 1 && _runs8(_fill8(Bg)) == 1
    end
end
@inline function _simple(X, Bg, full, ::Val{:box}, t)
    if full
        return _components27(X, true) == 1 &&
            _components27(Bg & t.near, false, t.xface) == 1
    end
    return _components27(X & t.near, false, t.xface) == 1 && _components27(Bg, true) == 1
end
