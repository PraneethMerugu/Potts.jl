# ---------------------------------------------------------------------------------------
# Whole-cell connectivity (P6.9a; D-075 Q6, D-189, D-197): the `Global(; window, adjacency)`
# rule and the cell-scope `pieces` / `largest_piece` trackers.
#
# PIECES of a cell are the connected components of its sites under an adjacency: `:face`
# (4 square, 6 hex, 6 cubic) or `:full` (8 square, 26 cubic; hex has one). A copy moves the
# target x from `old` to `new`.
#
# - Global, losing side: the copy does not increase `old`'s pieces iff `old`'s sites
#   adjacent to x (its TOUCHES) are connected in `old` without x. The local test (the
#   touches meet inside x's shell) proves it; otherwise a search decides: exact (a flood
#   with the host scratch `FloodScratch`), or, on the checkerboard with a window W, a
#   search inside the index-space box |Δ| ≤ W round x (minimum image), with a fixed-size
#   `MVector` stack, that refuses conservatively when every touching piece leaves the box.
# - Global, gaining side: gaining x does not increase `new`'s pieces iff x touches `new`.
# - `pieces`, `largest_piece`: exact per-cell trackers. A copy's after-values come from the
#   shell when the cell is one piece and the local test holds (or the target is isolated),
#   else from floods over the scratch. The values a ΔH computes are kept per target
#   (`FloodScratch.after`) for the commit, which may run in another kernel.
#
# No `Float64`, no `throw`, no allocation: device code reaches only the shell tests, the
# windowed search and (in the serial kernel) the floods over device scratch.

# face offsets (the shell tables' `xface` positions as offsets)
const _FACE2 = map(o -> Int32.(o), ((1, 0), (-1, 0), (0, 1), (0, -1)))
const _FACE3 = map(o -> Int32.(o), (
    (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)))

"""
The adjacency offsets of a cell's sites: face (`Val(false)`) or full (`Val(true)`).
"""
@inline _adjacency_offsets(::Lattice{2, M, Hexagonal}, ::Val{false}) where {M} = _HEX_SHELL
@inline _adjacency_offsets(::Lattice{2, M, Hexagonal}, ::Val{true}) where {M} = _HEX_SHELL
@inline _adjacency_offsets(::Lattice{2, M, Square}, ::Val{false}) where {M} = _FACE2
@inline _adjacency_offsets(::Lattice{2, M, Square}, ::Val{true}) where {M} = _SQUARE_SHELL
@inline _adjacency_offsets(::Lattice{3}, ::Val{false}) = _FACE3
@inline _adjacency_offsets(::Lattice{3}, ::Val{true}) = _CUBE_SHELL

# the shell positions adjacent to x under the adjacency, in shell (`shell_offsets`) order
const _SQUARE_XFACE = _bits(_SQUARE_SHELL, o -> sum(abs, o) == 1)
@inline _touch_bits(::Lattice{2, M, Hexagonal}, ::Val{F}) where {M, F} = _RING_ALL6
@inline _touch_bits(::Lattice{2, M, Square}, ::Val{F}) where {M, F} = F ? _RING_ALL8 :
                                                                      _SQUARE_XFACE
@inline _touch_bits(::Lattice{3}, ::Val{F}) where {F} = F ? _CUBE_TABLES.all :
                                                        _CUBE_TABLES.xface

# the shell pieces of the mask `m` (shell order) that meet its touches `touch`, with the
# shell kernels (P6.3h): runs of the ring in 2D, dilation in the 3×3×3 box in 3D
@inline _touched_pieces(lat::Lattice, m::UInt32, touch::UInt32, ::Val{F}) where {F} = _touched_pieces(
    _ring_bits(lat), m, touch, F)
@inline function _touched_pieces(r::Val{:ring8}, m::UInt32, touch::UInt32, full::Bool)
    mr = _to_ring8(m)
    # full: every position of m is a touch; face: the runs holding a face neighbour
    return full ? _pieces(mr, true, r, nothing) : _runs8_touching(mr)
end
@inline _touched_pieces(r::Val{:ring6}, m::UInt32, touch::UInt32, full::Bool) = _pieces(
    m, full, r, nothing)                     # every hex position is a touch
@inline _touched_pieces(::Val{:box}, m::UInt32, touch::UInt32, full::Bool) = _components27(
    m, full, touch)

"""
Evaluation of `Global` for the search: exact everywhere (`GlobalExact`, host algorithms)
or windowed where the rule has a window (`GlobalBoard`, `CheckerboardCPM`).
"""
struct GlobalExact end
struct GlobalBoard end
"""
Stage of the veto (`ConnectivityHooks.post`): the local test only (`GlobalLocal`: 0 pass,
1 needs the search, 2 refused) or the full decision (`GlobalSearch`: 0 pass, 1 refused for
want of window, 2 refused).
"""
struct GlobalLocal end
struct GlobalSearch end

const GLOBAL_PASS = Int32(0)
const GLOBAL_WINDOW = Int32(1)
const GLOBAL_REFUSED = Int32(2)

"""
    ConnectivityHooks(; post = nothing, defer = nothing, uses_global = false,
                      exact_veto = false, after_slots = 0)

The whole-cell connectivity parts of a `CPMFunction` (P6.9a):

  - `post(st, p, prop, ctx, stage) -> Int32`: the `Global` veto, evaluated after the
    acceptance draw (order local → ΔH → draw → Global): `stage` is `GlobalLocal()` or
    `GlobalSearch()`; 0 passes, 1 is a refusal for want of window, 2 a refusal;
  - `defer(st, p, prop, ctx) -> Bool`: on the checkerboard, whether a copy needs the exact
    floods (cell-scope `pieces`, an inline `Global` without window); such copies run in a
    serial kernel over the scratch;
  - `uses_global`: the model uses `Global` (veto, penalty or `connected`): the integrator
    counts `stats.connectivity_deferred`;
  - `exact_veto`: a veto `Global()` without window (exact search: host only on the checkerboard);
  - `after_slots`: the cell-scope adjacencies tracked (0, 1 or 2): the after-value buffer.
"""
Base.@kwdef struct ConnectivityHooks{PO, DF}
    post::PO = nothing
    defer::DF = nothing
    uses_global::Bool = false
    exact_veto::Bool = false
    after_slots::Int = 0
end

"""
Host (or, in the serial kernel, device) scratch of the exact floods: a mark per site, the
stamp of the last flood (marks equal to a stamp are visited; a new flood takes new stamps,
so nothing is cleared), a stack of sites, and the after-values of each target's last copy
(`4 × after_slots` rows: pieces and largest piece of old, then of new, per adjacency).
"""
struct FloodScratch{M, S, C, A}
    mark::M
    stack::S
    stamp::C
    after::A
end
Adapt.@adapt_structure FloodScratch

function FloodScratch(backend, lat::Lattice, after_slots::Integer)
    n = nsites(lat)
    z(T, dims...) = KernelAbstractions.zeros(backend, T, dims...)   # host or device scratch
    return FloodScratch(z(UInt32, n), z(Int32, n), z(UInt32, 1),
        after_slots > 0 ? z(Int32, 4 * after_slots, n) : nothing)
end

"""
    connectivity_ctx(backend, f, lattice, mode)

The run-context fields of a model with whole-cell connectivity (`f.connectivity`): the
flood scratch and the evaluation mode (`GlobalExact()` or `GlobalBoard()`); empty otherwise.
"""
function connectivity_ctx(backend, f, lat, mode)
    _connectivity_ctx(backend, f.connectivity, lat, mode)
end
_connectivity_ctx(backend, ::Nothing, lat, mode) = (;)
function _connectivity_ctx(backend, h::ConnectivityHooks, lat, mode)
    (; flood = FloodScratch(backend, lat, h.after_slots), global_mode = mode)
end

# `k` fresh stamps; the marks are cleared when the counter would wrap (serial callers only)
@inline function _stamps!(fl::FloodScratch, k::UInt32)
    s = @inbounds fl.stamp[1]                    # stamp has one entry
    if s >= typemax(UInt32) - k - UInt32(1)
        for i in eachindex(fl.mark)
            @inbounds fl.mark[i] = UInt32(0)
        end
        s = UInt32(0)
    end
    @inbounds fl.stamp[1] = s + k
    return s + UInt32(1)
end

# the site of shell position k (1-based) of x; a touch is always in the domain
@inline function _shell_site(lat, x, k)
    _, y = shift(lat, x, @inbounds shell_offsets(lat)[k])
    return linear_index(lat, y)
end

# Flood cell `c` from site `s0` (marked `S` by the caller), never through `skip`: marks
# reached sites `S`, counts the touches it meets (sites pre-marked `S + 1`) into `found`,
# and stops once `found == stop` (`stop = 0`: never). Returns (sites reached, found).
@inline function _flood!(σ, lat, fl::FloodScratch, s0::Int, c, skip::Int,
        S::UInt32, adj::Val, found::Int, stop::Int)
    mark = fl.mark
    stack = fl.stack
    offs = _adjacency_offsets(lat, adj)
    top = 1
    @inbounds stack[1] = Int32(s0)              # stack has nsites entries: each site enters once
    size = 1
    while top > 0
        s = Int(@inbounds stack[top])
        top -= 1
        xs = coordinates(lat, s)
        for o in offs
            inside, y = shift(lat, xs, o)
            inside || continue
            r = linear_index(lat, y)
            r == skip && continue
            @inbounds(σ[r]) == c || continue
            m = @inbounds mark[r]               # r in 1:nsites
            m == S && continue
            if m == S + UInt32(1)
                found += 1
                found == stop && return size + 1, found
            end
            @inbounds mark[r] = S
            top += 1
            @inbounds stack[top] = Int32(r)
            size += 1
        end
    end
    return size, found
end

# pre-mark the touches (shell positions in `touch`) of x with `S + 1`; their count and the first
@inline function _mark_touches!(lat, fl::FloodScratch, x, touch::UInt32, S::UInt32)
    n = 0
    first = 0
    m = touch
    while m != 0
        k = trailing_zeros(m) + 1
        m &= m - UInt32(1)
        s = _shell_site(lat, x, k)
        if @inbounds(fl.mark[s]) != S + UInt32(1)        # a short periodic axis may repeat a site
            @inbounds fl.mark[s] = S + UInt32(1)
            n += 1
            first == 0 && (first = s)
        end
    end
    return n, first
end

# ---------------------------------------------------------------------------------------
# Global: the losing side

# the shell data of the losing side: (owners mask of `old`, touches, local test holds)
@inline function _losing_shell(σ, lat, x, c, adj::Val)
    m = shell_mask(shell_owners(lat, σ, x), c)
    touch = m & _touch_bits(lat, adj)
    ok = touch == 0 || _touched_pieces(lat, m, touch, adj) <= 1
    return m, touch, ok
end

# exact: the touches are connected in `c` without x
@inline function _keeps_exact(
        σ, lat, fl::FloodScratch, x, t::Int, c, touch::UInt32, adj::Val)
    S = _stamps!(fl, UInt32(2))
    n, s0 = _mark_touches!(lat, fl, x, touch, S)
    n <= 1 && return true
    @inbounds fl.mark[s0] = S
    _, found = _flood!(σ, lat, fl, s0, c, t, S, adj, 1, n)
    return found == n
end

# the box index of y (0-based) round x, or −1 outside the box |Δ| ≤ W (minimum image); an
# axis no longer than 2W + 1 indexes by y itself (the box may cover it)
@inline function _box_index(lat::Lattice{N}, x, y, W::Int) where {N}
    idx = 0
    stride = 1
    for d in 1:N
        n = lat.dims[d]
        Δ = y[d] - x[d]
        if lat.periodic[d]
            Δ > n ÷ 2 && (Δ -= n)
            Δ < -((n - 1) ÷ 2) && (Δ += n)
        end
        abs(Δ) <= W || return -1
        if n <= 2W + 1
            idx += (y[d] - 1) * stride
            stride *= n
        else
            idx += (Δ + W) * stride
            stride *= 2W + 1
        end
    end
    return idx
end
@inline _box_size(lat::Lattice{N}, W::Int) where {N} = prod(ntuple(
    d -> min(lat.dims[d], 2W +
                          1), Val(N)))

@inline _bit(v, i::Int) = (@inbounds(v[(i >> 5) + 1]) >> (i & 31)) & UInt32(1) != 0      # i < 32 length(v)
@inline _setbit!(v, i::Int) = (@inbounds(v[(i >> 5) + 1] |= UInt32(1) << (i & 31)); nothing)

"""
The windowed decision for the losing cell `c` (`GLOBAL_PASS`, `GLOBAL_WINDOW` or
`GLOBAL_REFUSED`): its touches are connected through its own sites other than x inside the
box |Δ| ≤ W round x; otherwise a touching piece that stays inside the box is a true split
(refused), and if every one leaves it the copy is refused for want of window. The stack and
the visited bits are `MVector`s sized by `CAP` (no allocation, device-safe). `CAP` bounds
the box (`_box_size`); a larger box is refused for want of window.
"""
@inline function _keeps_window(σ, lat::Lattice{N}, x, t::Int, c, touch::UInt32,
        adj::Val, ::Val{W}, ::Val{CAP}) where {N, W, CAP}
    _box_size(lat, W) <= CAP || return GLOBAL_WINDOW
    seen = MVector{cld(CAP, 32), UInt32}(ntuple(_ -> UInt32(0), Val(cld(CAP, 32))))
    tmark = MVector{cld(CAP, 32), UInt32}(ntuple(_ -> UInt32(0), Val(cld(CAP, 32))))
    stack = MVector{CAP, Int32}(undef)
    offs = _adjacency_offsets(lat, adj)
    # the touches, marked in `tmark` (each inside the box: W ≥ 1)
    ntouch = 0
    m = touch
    while m != 0
        k = trailing_zeros(m) + 1
        m &= m - UInt32(1)
        _, y = shift(lat, x, @inbounds shell_offsets(lat)[k])
        i = _box_index(lat, x, y, W)
        (i >= 0 && !_bit(tmark, i)) || continue
        _setbit!(tmark, i)
        ntouch += 1
    end
    ntouch <= 1 && return GLOBAL_PASS
    found = 0
    first = true
    m = touch
    while m != 0
        k = trailing_zeros(m) + 1
        m &= m - UInt32(1)
        _, y0 = shift(lat, x, @inbounds shell_offsets(lat)[k])
        i0 = _box_index(lat, x, y0, W)
        (i0 >= 0 && !_bit(seen, i0)) || continue
        # one piece of `c` inside the box, from this touch
        _setbit!(seen, i0)
        found += 1
        top = 1
        @inbounds stack[1] = Int32(linear_index(lat, y0))         # each box site enters once: top ≤ CAP
        escaped = false
        while top > 0
            s = Int(@inbounds stack[top])
            top -= 1
            xs = coordinates(lat, s)
            for o in offs
                inside, y = shift(lat, xs, o)
                inside || continue
                r = linear_index(lat, y)
                (r == t || @inbounds(σ[r]) != c) && continue
                i = _box_index(lat, x, y, W)
                if i < 0
                    escaped = true
                    continue
                end
                _bit(seen, i) && continue
                _setbit!(seen, i)
                _bit(tmark, i) && (found += 1)
                top += 1
                @inbounds stack[top] = Int32(r)
            end
        end
        first && found == ntouch && return GLOBAL_PASS
        first = false
        escaped || return GLOBAL_REFUSED           # a whole piece inside the box: a true split
    end
    return GLOBAL_WINDOW
end

"""
    global_keeps(σ, ctx, prop, Val(full), Val(window), Val(cap), stage) -> Int32

`Global`'s decision for the losing cell `old` (always `GLOBAL_PASS` for the medium): 0
passes, 1 is a refusal for want of window, 2 a refusal. `GlobalLocal()` runs the local
test only (1: undecided); `GlobalSearch()` decides, exactly under `ctx.global_mode = GlobalExact()` (or without window), in the box of radius `window` under `GlobalBoard()`.
"""
@inline function global_keeps(σ, ctx, prop::Proposal, adj::Val, w::Val, cap::Val, stage)
    prop.old == 0 && return GLOBAL_PASS
    lat = ctx.lattice
    _, touch, ok = _losing_shell(σ, lat, prop.x, prop.old, adj)
    ok && return GLOBAL_PASS
    stage isa GlobalLocal && return GLOBAL_WINDOW
    return _keeps_search(ctx.global_mode, σ, ctx, prop, touch, adj, w, cap)
end
@inline _keeps_search(::GlobalExact, σ, ctx, prop, touch, adj, w, cap) = _keeps_exact(
    σ, ctx.lattice, ctx.flood, prop.x, prop.target, prop.old, touch, adj) ? GLOBAL_PASS :
                                                                         GLOBAL_REFUSED
@inline _keeps_search(
    ::GlobalBoard, σ, ctx, prop, touch, adj, ::Val{nothing}, cap) = _keeps_search(
    GlobalExact(), σ, ctx, prop, touch, adj, Val(nothing), cap)
@inline _keeps_search(::GlobalBoard, σ, ctx, prop, touch, adj, w::Val, cap) = _keeps_window(
    σ, ctx.lattice, prop.x, prop.target, prop.old, touch, adj, w, cap)

"""
    global_gains(σ, ctx, prop, Val(full)) -> Bool

`Global` for the gaining cell `new` (`true` for the medium): gaining x does not increase its
pieces, i.e. x is adjacent to `new` under the adjacency.
"""
@inline function global_gains(σ, ctx, prop::Proposal, adj::Val)
    prop.new == 0 && return true
    lat = ctx.lattice
    return (shell_mask(read_shell(σ, ctx, prop).owners, prop.new) &
            _touch_bits(lat, adj)) != 0
end

"""
Whether `global_keeps` needs the search for this copy (the local test fails).
"""
@inline global_defer(σ, ctx, prop::Proposal, adj::Val) = prop.old != 0 &&
                                                         !_losing_shell(
    σ, ctx.lattice, prop.x, prop.old, adj)[3]

# ---------------------------------------------------------------------------------------
# Cell-scope pieces and largest_piece

# after-values of the losing cell `a`: (pieces, largest piece)
@inline function _pieces_lose(σ, ctx, prop::Proposal, P, L, V, adj::Val)
    a = prop.old
    v = Int(@inbounds V[a])                 # a nonzero owner is a cell id in 1:capacity
    p0 = Int(@inbounds P[a])
    l0 = Int(@inbounds L[a])
    v == 1 && return Int32(0), Int32(0)
    lat = ctx.lattice
    _, touch, ok = _losing_shell(σ, lat, prop.x, a, adj)
    touch == 0 && return Int32(p0 - 1), Int32(l0)          # an isolated site: its piece goes
    p0 == 1 && ok && return Int32(1), Int32(v - 1)
    # the pieces of P_x \ {x}, from the touches
    fl = ctx.flood
    S = _stamps!(fl, UInt32(2))
    n, _ = _mark_touches!(lat, fl, prop.x, touch, S)
    k = 0
    total = 0
    maxc = 0
    found = 0
    m = touch
    while m != 0
        q = trailing_zeros(m) + 1
        m &= m - UInt32(1)
        s = _shell_site(lat, prop.x, q)
        @inbounds(fl.mark[s]) == S && continue
        @inbounds fl.mark[s] = S
        found += 1
        sz, found = _flood!(
            σ, lat, fl, s, a, prop.target, S, adj, found, p0 == 1 && k == 0 ? n : 0)
        p0 == 1 && k == 0 && found == n && return Int32(1), Int32(v - 1)   # one piece, still connected
        k += 1
        total += sz
        maxc = max(maxc, sz)
    end
    size_x = total + 1
    size_x < l0 && return Int32(p0 - 1 + k), Int32(l0)
    p0 == 1 && return Int32(k), Int32(maxc)
    rest = v - size_x
    maxc >= rest && return Int32(p0 - 1 + k), Int32(maxc)
    # x's piece was a largest one and the rest may hold a larger new largest: flood the rest
    for r in 1:nsites(lat)
        (r == prop.target || @inbounds(σ[r]) != a || @inbounds(fl.mark[r]) == S) && continue
        @inbounds fl.mark[r] = S
        sz, _ = _flood!(σ, lat, fl, r, a, prop.target, S, adj, 0, 0)
        maxc = max(maxc, sz)
    end
    return Int32(p0 - 1 + k), Int32(maxc)
end

# after-values of the gaining cell `b`
@inline function _pieces_gain(σ, ctx, prop::Proposal, P, L, V, adj::Val)
    b = prop.new
    v = Int(@inbounds V[b])
    p0 = Int(@inbounds P[b])
    l0 = Int(@inbounds L[b])
    lat = ctx.lattice
    touch = shell_mask(read_shell(σ, ctx, prop).owners, b) & _touch_bits(lat, adj)
    touch == 0 && return Int32(p0 + 1), Int32(max(l0, 1))
    p0 == 1 && return Int32(1), Int32(v + 1)
    fl = ctx.flood
    S = _stamps!(fl, UInt32(2))
    _mark_touches!(lat, fl, prop.x, touch, S)
    merged = 0
    joined = 0
    m = touch
    while m != 0
        q = trailing_zeros(m) + 1
        m &= m - UInt32(1)
        s = _shell_site(lat, prop.x, q)
        @inbounds(fl.mark[s]) == S && continue
        @inbounds fl.mark[s] = S
        sz, _ = _flood!(σ, lat, fl, s, b, prop.target, S, adj, 0, 0)
        merged += sz
        joined += 1
    end
    return Int32(p0 - joined + 1), Int32(max(l0, merged + 1))
end

"""
    pieces_after!(σ, ctx, prop, P, L, V, Val(full), slot) -> (pieces_old, largest_old, pieces_new, largest_new)

The exact pieces and largest piece of the old and new cells after the copy (0 for the
medium), from the trackers `P`, `L` (this adjacency) and the volumes `V`. The values are
also stored for the target in `ctx.flood.after` (rows `4(slot − 1) + 1:4`) for
[`commit_pieces!`](@ref).
"""
@inline function pieces_after!(σ, ctx, prop::Proposal, P, L, V, adj::Val, slot::Int)
    po, lo = prop.old == 0 ? (Int32(0), Int32(0)) : _pieces_lose(σ, ctx, prop, P, L, V, adj)
    pn, ln = prop.new == 0 ? (Int32(0), Int32(0)) : _pieces_gain(σ, ctx, prop, P, L, V, adj)
    a = ctx.flood.after
    r = 4 * (slot - 1)
    t = prop.target
    # rows 4·slot ≤ size(after, 1); t in 1:nsites = size(after, 2)
    @inbounds a[r + 1, t] = po
    @inbounds a[r + 2, t] = lo
    @inbounds a[r + 3, t] = pn
    @inbounds a[r + 4, t] = ln
    return po, lo, pn, ln
end

"""
Whether `pieces_after!` needs the floods for this copy (the checkerboard defers it).
"""
@inline function pieces_defer(σ, ctx, prop::Proposal, P, V, adj::Val)
    lat = ctx.lattice
    owners = read_shell(σ, ctx, prop).owners
    if prop.old != 0
        a = prop.old
        m = shell_mask(owners, a)
        touch = m & _touch_bits(lat, adj)
        fast = @inbounds(V[a]) == 1 || touch == 0 ||
               (@inbounds(P[a]) == 1 && _touched_pieces(lat, m, touch, adj) <= 1)
        fast || return true
    end
    if prop.new != 0
        touch = shell_mask(owners, prop.new) & _touch_bits(lat, adj)
        (touch == 0 || @inbounds(P[prop.new]) == 1) || return true
    end
    return false
end

"""
Apply the after-values `pieces_after!` stored for the target to the trackers `P`, `L`.
"""
@inline function commit_pieces!(P, L, prop::Proposal, ctx, slot::Int)
    a = ctx.flood.after
    r = 4 * (slot - 1)
    t = prop.target
    if prop.old != 0                           # a nonzero owner is a cell id in 1:capacity
        @inbounds P[prop.old] = a[r + 1, t]
        @inbounds L[prop.old] = a[r + 2, t]
    end
    if prop.new != 0
        @inbounds P[prop.new] = a[r + 3, t]
        @inbounds L[prop.new] = a[r + 4, t]
    end
    return nothing
end

"""
    recompute_pieces(σ, lattice, Val(full), ncell) -> (pieces, largest)

The pieces and largest piece of cells `1:ncell` under face (`Val(false)`) or full
(`Val(true)`) adjacency, from scratch (host): problem construction, lifecycle events, host
edits of σ. A dead cell has (0, 0).
"""
function recompute_pieces(σ, lat::Lattice, adj::Val, ncell::Integer)
    P = zeros(Int32, ncell)
    L = zeros(Int32, ncell)
    fl = FloodScratch(CPU(), lat, 0)
    S = _stamps!(fl, UInt32(2))
    for i in 1:nsites(lat)
        c = σ[i]
        (c > 0 && fl.mark[i] != S) || continue
        fl.mark[i] = S
        sz, _ = _flood!(σ, lat, fl, i, c, 0, S, adj, 0, 0)
        P[c] += Int32(1)
        L[c] = max(L[c], Int32(sz))
    end
    return P, L
end

# host rebuild of the pieces columns (`_rebuild_trackers!`); `haskey` on the cell NamedTuple
# folds at compile time, so each branch is type-stable (as `_rebuild_euler!`)
function _rebuild_pieces!(stats, st, σ, lat, cap)
    if haskey(st.cell, :pieces)
        P, L = recompute_pieces(σ, lat, Val(false), cap)
        _copy!(stats, st.cell.pieces, P)
        _copy!(stats, st.cell.largest_piece, L)
    end
    if haskey(st.cell, :pieces_full)
        P, L = recompute_pieces(σ, lat, Val(true), cap)
        _copy!(stats, st.cell.pieces_full, P)
        _copy!(stats, st.cell.largest_piece_full, L)
    end
    return nothing
end
