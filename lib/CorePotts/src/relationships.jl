# Cell–cell relationships: symmetric links with payloads, stored as fixed-
# degree padded adjacency (`maxdeg × capacity`, 0 = empty slot) plus any payload matrices
# `st.cell.link_<name>` of the same shape. Being cell quantities, links grow with
# `with_capacity`; the lifecycle clears a daughter's links and drops the incident links of
# removed cells (the `RemoveIncident` policy).
#
# A *link store* is anything with a `links` adjacency matrix and its `link_<name>` payloads:
# the cell state itself (one unnamed relationship, column `links`), or a NamedTuple view
# `(; links = st.cell.links__bond, link_rest = st.cell.link_rest)` over the columns of a
# named relationship. Several relationships live side by side as adjacency
# columns `links__<name>` (`adjacency_name`); payload names are unique per model, so a
# payload column belongs to exactly one relationship. Views are plain NamedTuples of the
# state's arrays: building one costs nothing, on the host or in a kernel.

"""
    empty_links(maxdeg, ncell; payloads...) -> NamedTuple
    empty_links(maxdeg, ncell, name; payloads...) -> NamedTuple

Link storage to merge into the cell state: the adjacency (`links`, or
`links__<name>` for relationship `name`, see `adjacency_name`) plus `link_<p>` payload
matrices (`payloads` gives the element type of each, e.g. `rest = Float64`).
"""
empty_links(maxdeg::Integer, ncell::Integer; payloads...) =
    merge((; links = zeros(Int32, maxdeg, ncell)), _empty_payloads(maxdeg, ncell, payloads))
empty_links(maxdeg::Integer, ncell::Integer, name::Symbol; payloads...) =
    merge(NamedTuple{(adjacency_name(name),)}((zeros(Int32, maxdeg, ncell),)), _empty_payloads(maxdeg, ncell, payloads))
_empty_payloads(maxdeg, ncell, payloads) =
    NamedTuple(Symbol(:link_, k) => zeros(T, maxdeg, ncell) for (k, T) in payloads)

"""`adjacency_name(name)`: the cell-state column of relationship `name`'s adjacency, `links__<name>`."""
adjacency_name(name::Symbol) = Symbol(:links__, name)
_is_adjacency(name::Symbol) = name === :links || startswith(String(name), "links__")

"""
    link_store(cell, name) -> NamedTuple

Relationship `name`'s adjacency in cell state `cell`, as a link store `(; links)` for the
queries `linked`, `link_slot` and `link_count` (e.g.
`linked(link_store(u.cell, :bond), 1, 2)`). Payloads are left out: which `link_<p>`
columns belong to `name` is the model's knowledge (generated code builds full views).
"""
link_store(cell, name::Symbol) = (; links = getfield(cell, adjacency_name(name)))

"""The most links a cell can hold (the link store's capacity per cell)."""
@inline maxdegree(cell) = size(cell.links, 1)

"""Slot of `b` in `a`'s link row, or 0."""
@inline function link_slot(cell, a, b)
    for k in 1:maxdegree(cell)
        @inbounds(cell.links[k, a]) == b && return k
    end
    return 0
end
"""
    linked(cell, a, b) -> Bool

Return `true` if cells `a` and `b` are nonzero and linked in link store `cell`.
"""
@inline linked(cell, a, b) = a != 0 && b != 0 && link_slot(cell, a, b) != 0

"""
    link_count(cell, a) -> Int

Number of active links incident on cell `a` in link store `cell`.
"""
@inline link_count(cell, a) = count(k -> @inbounds(cell.links[k, a]) != 0, 1:maxdegree(cell))

_payload_names(cell) = Tuple(k for k in keys(cell) if startswith(String(k), "link_"))

"""
    add_link!(cell, a, b; payload...) -> Bool

Link cells `a` and `b` symmetrically (host arrays), writing payload values
(`rest = 5.0` → `link_rest`; the store's other payloads start at zero, so a slot's payload
values are only meaningful while it holds a link). `cell` is a link store (the cell state
or a view, see the file header). Returns `false` if already linked or either row is full.
"""
function add_link!(cell, a, b; payload...)
    (a == b || a == 0 || b == 0 || linked(cell, a, b)) && return false
    ka = link_slot(cell, a, 0); kb = link_slot(cell, b, 0)
    (ka == 0 || kb == 0) && return false
    cell.links[ka, a] = b; cell.links[kb, b] = a
    for name in _payload_names(cell)             # payloads not given start at zero
        arr = getfield(cell, name)
        arr[ka, a] = zero(eltype(arr)); arr[kb, b] = zero(eltype(arr))
    end
    for (name, v) in payload
        arr = getfield(cell, Symbol(:link_, name))
        arr[ka, a] = v; arr[kb, b] = v
    end
    return true
end

"""Remove the link between `a` and `b` (host arrays); returns whether it existed."""
function remove_link!(cell, a, b)
    ka = link_slot(cell, a, b); kb = link_slot(cell, b, a)
    ka == 0 && return false
    cell.links[ka, a] = 0; cell.links[kb, b] = 0
    for name in _payload_names(cell)
        arr = getfield(cell, name)
        arr[ka, a] = zero(eltype(arr)); arr[kb, b] = zero(eltype(arr))
    end
    return true
end

"""Drop every link of cell `c` (host arrays)."""
function remove_incident!(cell, c)
    for k in 1:maxdegree(cell)
        b = cell.links[k, c]
        b != 0 && remove_link!(cell, c, b)
    end
    return nothing
end

"""Minimum-image distance between the centroids of `a` and `b`, in float type `T`."""
@inline function centroid_distance(::Type{T}, cell, l::Lattice{N}, a, b) where {T, N}
    ca = centroid(T, cell, l, a); cb = centroid(T, cell, l, b)
    return _periodic_norm(T, l, ntuple(d -> ca[d] - cb[d], Val(N)))
end
"""
    centroid_separation(T, cell, lattice, a, b)

Embedded minimum-image vector from the centroid of `b` to that of `a` (an `NTuple`), in float
type `T`: on a square lattice the per-axis wrap, on a periodic hexagonal lattice the nearest
image on the rhombic torus, so its norm is `centroid_distance`. Both cells must be alive.
"""
@inline function centroid_separation(::Type{T}, cell, l::Lattice{N}, a, b) where {T, N}
    ca = centroid(T, cell, l, a); cb = centroid(T, cell, l, b)
    return _min_image(T, l, ntuple(d -> ca[d] - cb[d], Val(N)))
end
@inline function _periodic_norm(::Type{T}, l::Lattice{N}, δ) where {T, N}
    e = _min_image(T, l, δ)
    s = zero(T)
    for d in 1:N
        s += T(e[d])^2
    end
    return sqrt(s)
end

"""
Embedded minimum-image displacement of the lattice-coordinate difference `δ`. On a square
lattice the per-axis wrap is the minimum; on the skewed hexagonal torus the nearest image
may be a diagonal one, so the images one period away on each periodic axis are compared.
"""
@inline function _min_image(::Type{T}, l::Lattice{N}, δ) where {T, N}
    w = ntuple(Val(N)) do d
        x = T(δ[d])
        l.periodic[d] ? x - T(l.dims[d]) * round(x / T(l.dims[d])) : x
    end
    return embed(l, w)
end
@inline function _min_image(::Type{T}, l::Lattice{2, M, Hexagonal}, δ) where {T, M}
    w1 = T(δ[1]); w2 = T(δ[2])
    L1 = T(l.dims[1]); L2 = T(l.dims[2])
    l.periodic[1] && (w1 -= L1 * round(w1 / L1))
    l.periodic[2] && (w2 -= L2 * round(w2 / L2))
    best = embed(l, (w1, w2))
    bn = best[1]^2 + best[2]^2
    for i in -1:1, j in -1:1
        ((i == 0 || l.periodic[1]) && (j == 0 || l.periodic[2])) || continue
        e = embed(l, (w1 + i * L1, w2 + j * L2))
        n = e[1]^2 + e[2]^2
        n < bn && (best = e; bn = n)
    end
    return best
end

"""
    link_delta(T, cell, ctx, prop, E)
    link_delta(T, cell, store, ctx, prop, E)

Change of `Σ_links E(a, b, k, distance)` (each link once; `k` is the slot in `a`'s row, for
payload lookup) when `prop` moves the target from `old` to `new`: every link incident to
`old` or `new` sees their centroids shift (`centroid_shift`). Centroids come from `cell`,
links from `store` (default: `cell` itself); a model with several relationships sums one
call per store.

A partner with `volume == 0` (dead: it lost its last site to copies) is skipped, so its
links contribute nothing until a boundary drops them: its centroid
would be 0/0. The skip tests the volume load the centroid uses anyway (one load, so a
racing write cannot slip a zero in between). `old` and `new` own a site each, so they are
alive.

A killing copy (`old` owns one site, the target) removes `old`'s links: each edge of `old`
contributes `-E(before)`, its pre-copy energy, and no post-copy term. So for every
copy ΔH equals the change of the brute-force sum over links with two alive ends. The kill
test reads the same volume load as `old`'s centroid. Device-safe: no allocation, no
`throw`.
"""
@inline link_delta(::Type{T}, cell, ctx, prop::Proposal, E::F) where {T, F} = link_delta(T, cell, cell, ctx, prop, E)
@inline function link_delta(::Type{T}, cell, store, ctx, prop::Proposal, E::F) where {T, F}
    lat = ctx.lattice
    fr = link_frame(T, cell, lat, prop)
    dH = zero(T)
    for side in 1:2, k in 1:maxdegree(store)
        c, n, m, before, after = link_at(T, fr, cell, lat, store, side, k)
        m == 0 && continue
        e0 = E(c, n, k, before)
        dH += m == 1 ? -e0 : E(c, n, k, after) - e0
    end
    return dH
end

# `link_delta` in two steps, so generated code can evaluate the link energy inline instead of
# passing it as a closure (a closure in a RuntimeGeneratedFunction body becomes an opaque
# closure, which a downstream package cannot precompile):
#   fr = link_frame(T, cell, lat, prop)
#   for side in 1:2, k in 1:maxdegree(store)
#       c, n, m, before, after = link_at(T, fr, cell, lat, store, side, k)
#       m == 0: no link; m == 1: the link dies with `old`, ΔH −= E(before); m == 2: ΔH += E(after) − E(before)

"""The copy's two cells, the kill flag, their centroid shifts and centroids (`link_at`)."""
@inline function link_frame(::Type{T}, cell, lat::Lattice{N}, prop::Proposal{N}) where {T, N}
    a, b = prop.old, prop.new
    z = ntuple(_ -> zero(T), Val(N))
    Va = a == 0 ? zero(eltype(cell.volume)) : @inbounds cell.volume[a]
    Vb = b == 0 ? zero(eltype(cell.volume)) : @inbounds cell.volume[b]
    kill = Va == 1                                    # the copy takes a's last site: a dies (D-083)
    sa = (a == 0 || kill) ? z : centroid_shift(T, cell, lat, a, prop.x, -1)
    sb = b == 0 ? z : centroid_shift(T, cell, lat, b, prop.x, +1)
    ca = a == 0 ? z : _centroid(T, cell, lat, a, Va)
    cb = b == 0 ? z : _centroid(T, cell, lat, b, Vb)
    return (; a, b, kill, sa, sb, ca, cb, z)
end

"""
Link slot `k` of side `side` (1: `old`, 2: `new`) of frame `fr`: `(c, n, mode, before,
after)`, the cell, its partner, the mode (0: no link to count, 1: the link dies with `old`,
2: it stays) and the centroid distances before and after the copy.
"""
@inline function link_at(::Type{T}, fr, cell, lat::Lattice{N}, store, side::Int, k::Int) where {T, N}
    c, sc, cc, other, so = side == 1 ? (fr.a, fr.sa, fr.ca, fr.b, fr.sb) : (fr.b, fr.sb, fr.cb, fr.a, fr.sa)
    c == 0 && return (c, c, 0, zero(T), zero(T))
    n = @inbounds store.links[k, c]                   # (k ≤ maxdegree(store), c a cell of the copy)
    n == 0 && return (c, n, 0, zero(T), zero(T))
    n == other && c == fr.b && return (c, n, 0, zero(T), zero(T))   # the old–new link is counted once (from a)
    Vn = @inbounds cell.volume[n]
    Vn == 0 && return (c, n, 0, zero(T), zero(T))     # dead partner: skipped (D-066 item 5)
    cn = _centroid(T, cell, lat, n, Vn)
    before = _periodic_norm(T, lat, ntuple(d -> cc[d] - cn[d], Val(N)))
    fr.kill && c == fr.a && return (c, n, 1, before, zero(T))   # a's links die with it: E(before) → 0
    sn = n == other ? so : fr.z
    after = _periodic_norm(T, lat, ntuple(d -> cc[d] + sc[d] - cn[d] - sn[d], Val(N)))
    return (c, n, 2, before, after)
end

"""
    HostPhase(f!; every = 1, reads = nothing, writes = nothing)

Phase that synchronizes and calls `f!(cell, st, p, ctx, mcs)` on host copies every `every`
MCS (`cell` is `st.cell`), e.g. relationship creation/removal/retuning from the contact
graph. Host-shaped and rare by design. `ctx.lattice` is a host copy (made once per run: the
domain mask never changes); `p` is the live parameter object, as given to the integrator.

`reads` and `writes` declare what the body touches, as tuples of `:ownership` (the labels) and cell
column names, so that on a device only those leaves cross:
- `reads`: copied to the host before the body;
- `writes`: copied to the host before the body (bodies update them in place) and back after
  it; they are the only leaves written back.
- `nothing` (the default) keeps the whole-state behavior: `reads = nothing` copies the whole
  state down; `writes = nothing` writes every cell column back (and so copies every cell
  column down).

`reads` columns are read-only. Writing a `reads`-only or undeclared leaf is undefined: on
the host the change persists (the body runs on the live arrays), on a device it is dropped
(only `writes` go back). What the body sees in leaves it does not declare is unspecified (on
a device it is the device array, which must not be read on the host). A name that is neither `:ownership` nor a cell
column of the state is an `ArgumentError` the first time the phase runs, on every backend.
Model, site and history quantities are not declarable: a body that reads them leaves
`reads = nothing`; it never writes them back.

```julia
HostPhase((cell, st, p, ctx, mcs) -> (cell.y .+= cell.x; nothing); reads = (:x,), writes = (:y,))
```
"""
struct HostPhase{F, R, W}
    f!::F
    every::Int
    reads::R                     # `nothing` or a tuple of Symbols
    writes::W
end
HostPhase(f!; every::Integer = 1, reads = nothing, writes = nothing) =
    HostPhase(f!, Int(every), _declared(reads), _declared(writes))
_declared(::Nothing) = nothing
_declared(s::Symbol) = (s,)
function _declared(names)
    t = Tuple(names)
    all(n -> n isa Symbol, t) || throw(ArgumentError("HostPhase `reads`/`writes` take Symbols (`:ownership` or cell column names); got $(repr(names))"))
    return t
end

(ph::HostPhase{F})(st, p, ctx, key, mcs, backend) where {F} =
    run_phase(ph, st, p, ctx, key, mcs, backend, nothing)

function run_phase(ph::HostPhase{F}, st, p, ctx, key, mcs, backend, stats) where {F}
    _check_declared(ph.reads, st)
    _check_declared(ph.writes, st)
    mcs % ph.every == 0 || return 0
    sync!(stats, backend)
    host = _host_state(ph, stats, backend, st)
    ph.f!(host.cell, host, p, merge(ctx, (; lattice = host_lattice(stats, ctx.lattice))), mcs)
    if ph.writes === nothing
        foreach(keys(st.cell)) do name
            _write_back!(stats, getfield(st.cell, name), getfield(host.cell, name))
        end
    else
        foreach(ph.writes) do name
            if name === :ownership
                _write_back!(stats, st.ownership, host.ownership)
            else
                _write_back!(stats, getfield(st.cell, name), getfield(host.cell, name))
            end
        end
    end
    return 0
end

_check_declared(::Nothing, st) = nothing
function _check_declared(names, st)
    for n in names
        n === :ownership || haskey(st.cell, n) || throw(
            ArgumentError(
                "HostPhase declares `$n`, which is neither `:ownership` nor a cell column of the state " *
            "(cell columns: $(join(keys(st.cell), ", ")))"))
    end
    return nothing
end

# The body's host state: the whole state (`reads = nothing`, as before D-092), or only the
# declared leaves (written columns too; every cell column when `writes = nothing`). On the
# host, declared leaves are the live arrays (no copy).
function _host_state(ph::HostPhase, stats, backend, st)
    ph.reads === nothing && return snapshot(stats, backend, st)
    used = ph.writes === nothing ? (ph.reads..., keys(st.cell)...) : (ph.reads..., ph.writes...)
    cell = unique(n for n in used if n !== :ownership)
    return host_leaves(stats, st; ownership = :ownership in used, cell)
end

# a host copy back to its live array (nothing when the body ran on the live array itself)
_write_back!(stats, live, host) = live === host ? nothing : (counted_copy!(stats, live, host); nothing)
