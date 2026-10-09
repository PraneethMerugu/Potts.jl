# ---------------------------------------------------------------------------------------
# The target's neighbour shell and the local connectivity rules over it (P6.3g, D-189)
#
# The SHELL of a target x is the 8 sites of its 3×3 box (square 2D), its 6 neighbours (hex)
# or the 26 sites of its 3×3×3 box (cubic 3D), whatever the model's neighbourhood. A shell
# position off a closed face (or outside the domain mask) is out of domain: its owner reads
# −1 (an `Int32`, whatever σ's eltype), never the medium (0) nor a cell (> 0). The rules
# below work on bit masks over the shell positions (bit k − 1 for position k), with the
# adjacency between positions in constant tables; no `Float64`, no `throw`, no allocation.

# Shell offsets: ternary order (axis 1 fastest, the origin left out) on square and cubic
# lattices, angular order on the hexagonal one.
const _SQUARE_SHELL = Tuple(Int32.((i, j)) for j in -1:1 for i in -1:1 if (i, j) != (0, 0))
const _HEX_SHELL = map(o -> Int32.(o), ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)))
const _CUBE_SHELL = Tuple(Int32.((i, j, k)) for k in -1:1 for j in -1:1 for i in -1:1 if (i, j, k) != (0, 0, 0))

"""
    shell_offsets(lattice)

The offsets of the target's neighbour shell: the 8 sites of the 3×3 box on a square
lattice, the 6 neighbours on a hexagonal one, the 26 sites of the 3×3×3 box in 3D.
"""
@inline shell_offsets(::Lattice{2, M, Hexagonal}) where {M} = _HEX_SHELL
@inline shell_offsets(::Lattice{2}) = _SQUARE_SHELL
@inline shell_offsets(::Lattice{3}) = _CUBE_SHELL

# Adjacency tables: for each shell position, the mask of the shell positions adjacent to it.
function _adjacency_masks(offs, adj)
    return ntuple(length(offs)) do i
        m = UInt32(0)
        for j in eachindex(offs)
            j != i && adj(offs[i], offs[j]) && (m |= UInt32(1) << (j - 1))
        end
        m
    end
end
_bits(offs, pred) = foldl((m, j) -> pred(offs[j]) ? m | (UInt32(1) << (j - 1)) : m, eachindex(offs); init = UInt32(0))
_l1(a, b) = sum(abs, a .- b)
_linf(a, b) = maximum(abs, a .- b)

# (face, full, face neighbours of x, the near set of `Simple()`, every position)
const _SQUARE_TABLES = (; face = _adjacency_masks(_SQUARE_SHELL, (a, b) -> _l1(a, b) == 1),
    full = _adjacency_masks(_SQUARE_SHELL, (a, b) -> _linf(a, b) == 1),
    xface = _bits(_SQUARE_SHELL, o -> sum(abs, o) == 1), near = _bits(_SQUARE_SHELL, _ -> true),
    all = _bits(_SQUARE_SHELL, _ -> true))
const _HEX_ADJ = _adjacency_masks(_HEX_SHELL, (a, b) -> (a .- b) in _HEX_SHELL)
const _HEX_TABLES = (; face = _HEX_ADJ, full = _HEX_ADJ, xface = _bits(_HEX_SHELL, _ -> true),
    near = _bits(_HEX_SHELL, _ -> true), all = _bits(_HEX_SHELL, _ -> true))
const _CUBE_TABLES = (; face = _adjacency_masks(_CUBE_SHELL, (a, b) -> _l1(a, b) == 1),
    full = _adjacency_masks(_CUBE_SHELL, (a, b) -> _linf(a, b) == 1),
    xface = _bits(_CUBE_SHELL, o -> sum(abs, o) == 1), near = _bits(_CUBE_SHELL, o -> sum(abs, o) <= 2),
    all = _bits(_CUBE_SHELL, _ -> true))

@inline _shell_tables(::Lattice{2, M, Hexagonal}) where {M} = _HEX_TABLES
@inline _shell_tables(::Lattice{2}) = _SQUARE_TABLES
@inline _shell_tables(::Lattice{3}) = _CUBE_TABLES
@inline _ishex(::Lattice{2, M, Hexagonal}) where {M} = true
@inline _ishex(::Lattice) = false

"""
    shell_owners(lattice, σ, x) -> NTuple{K, Int32}

The owners of the shell positions of `x` (see [`shell_offsets`](@ref)); −1 off a closed face
or outside the domain mask, whatever σ's eltype.
"""
@inline function shell_owners(lat::Lattice, σ, x)
    offs = shell_offsets(lat)
    return ntuple(Val(length(offs))) do k
        inside, y = shift(lat, x, @inbounds offs[k])
        inside ? Int32(@inbounds σ[linear_index(lat, y)]) : Int32(-1)
    end
end

"""The mask of the shell positions owned by `c`."""
@inline function shell_mask(owners::NTuple{K, Int32}, c) where {K}
    m = UInt32(0)
    for k in 1:K
        m |= ifelse(@inbounds(owners[k]) == c, UInt32(1) << (k - 1), UInt32(0))
    end
    return m
end

# Components of `mask` under the adjacency table `adj` that contain a position of `touch`.
@inline function _components(mask::UInt32, adj::NTuple{K, UInt32}, touch::UInt32 = typemax(UInt32)) where {K}
    n = Int32(0)
    while mask != 0
        reached = mask & (~mask + UInt32(1))         # the lowest set bit
        frontier = reached
        while frontier != 0
            p = trailing_zeros(frontier)
            frontier &= frontier - UInt32(1)
            grown = @inbounds(adj[p + 1]) & mask & ~reached
            reached |= grown
            frontier |= grown
        end
        mask &= ~reached
        n += Int32((reached & touch) != 0)
    end
    return n
end

"""
    shell_pieces(lattice, mask, full) -> Int32

Components of the shell positions in `mask`, two positions joined when they are face
neighbours (`full = false`) or any neighbours (`full = true`; on a hexagonal lattice the
two are the same).
"""
@inline function shell_pieces(lat::Lattice, mask::UInt32, full::Bool)
    t = _shell_tables(lat)
    return _components(mask, full ? t.full : t.face)
end

"""
    local_rule(σ, ctx, prop, gain, full) -> Bool

`Local(; gain, adjacency)` for the losing cell: `true` for the medium; otherwise its shell
positions form exactly one piece (zero pieces is refused), the shell is not full (every
position in the domain and owned by `old`), and, if `gain`, `new` owns a shell site adjacent
to the target (a face neighbour, or any shell site when `full`).
"""
@inline function local_rule(σ, ctx, prop::Proposal, gain::Bool, full::Bool)
    prop.old == 0 && return true
    lat = ctx.lattice
    t = _shell_tables(lat)
    owners = shell_owners(lat, σ, prop.x)
    m = shell_mask(owners, prop.old)
    m == t.all && return false
    _components(m, full ? t.full : t.face) == 1 || return false
    gain || return true
    return (shell_mask(owners, prop.new) & (full ? t.all : t.xface)) != 0
end

"""
    arc_or_pair(σ, ctx, prop) -> Bool

`ArcOrPair()` for the losing cell: `true` for the medium; otherwise its shell positions form
at most one face piece, or exactly two distinct cells and no medium are on the shell, the
out-of-domain positions (if any) counting as one extra cell (TST's frame).
"""
@inline function arc_or_pair(σ, ctx, prop::Proposal)
    prop.old == 0 && return true
    lat = ctx.lattice
    owners = shell_owners(lat, σ, prop.x)
    _components(shell_mask(owners, prop.old), _shell_tables(lat).face) <= 1 && return true
    shell_mask(owners, 0) == 0 || return false
    return _distinct_cells(owners) + (shell_mask(owners, -1) != 0) == 2
end

"""
    simple_point(σ, ctx, prop, c, full) -> Bool

`Simple(; adjacency)` for cell `c` (`true` for the medium): the target is a simple point of
`c`'s shell sites with the target, out-of-domain positions counting as background. 2D
`full = false`: one 4-component of `c` in the 8-shell touching a face neighbour, and one
8-component of the background; `full = true` swaps the adjacencies. 3D: the same with 6
(over the 18-neighbourhood) and 26. Hex: one arc of each.
"""
@inline function simple_point(σ, ctx, prop::Proposal, c, full::Bool)
    c == 0 && return true
    lat = ctx.lattice
    t = _shell_tables(lat)
    X = shell_mask(shell_owners(lat, σ, prop.x), c)
    Bg = ~X & t.all
    _ishex(lat) && return _components(X, t.face) == 1 && _components(Bg, t.face) == 1
    if full
        return _components(X, t.full) == 1 && _components(Bg & t.near, t.face, t.xface) == 1
    end
    return _components(X & t.near, t.face, t.xface) == 1 && _components(Bg, t.full) == 1
end
