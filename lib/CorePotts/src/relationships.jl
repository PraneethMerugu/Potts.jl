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

Return empty link storage to merge into the cell state.

The storage is a padded adjacency matrix (`0` is an empty slot) plus a `link_<p>` payload
matrix of the same shape for each payload. Being cell columns, links grow with the state.

# Arguments
- `maxdeg::Integer`: the most links a cell can hold.
- `ncell::Integer`: the number of cell slots.
- `name::Symbol`: the relationship's name. Without it, the adjacency column is `links`;
  with it, the column is [`adjacency_name(name)`](@ref adjacency_name).

# Keywords
- `payloads...`: the element type of each payload, for example `rest = Float64`.

# Returns
- `NamedTuple`: the adjacency matrix (`Int32`, `maxdeg × ncell`) and the payload
  matrices.

# Examples
```jldoctest
julia> using CorePotts

julia> keys(empty_links(4, 10, :bond; rest = Float64))
(:links__bond, :link_rest)
```

See also [`add_link!`](@ref), [`linked`](@ref).
"""
function empty_links(maxdeg::Integer, ncell::Integer; payloads...)
    return merge(
        (; links = zeros(Int32, maxdeg, ncell)),
        _empty_payloads(maxdeg, ncell, payloads)
    )
end
function empty_links(maxdeg::Integer, ncell::Integer, name::Symbol; payloads...)
    return merge(
        NamedTuple{(adjacency_name(name),)}((zeros(Int32, maxdeg, ncell),)),
        _empty_payloads(maxdeg, ncell, payloads)
    )
end
function _empty_payloads(maxdeg, ncell, payloads)
    return NamedTuple(Symbol(:link_, k) => zeros(T, maxdeg, ncell) for (k, T) in payloads)
end

"""
    adjacency_name(name) -> Symbol

Return the cell-state column of relationship `name`'s adjacency, `links__<name>`.

# Arguments
- `name::Symbol`: the relationship's name.

# Returns
- `Symbol`.

# Examples
```jldoctest
julia> using CorePotts

julia> CorePotts.adjacency_name(:bond)
:links__bond
```

See also [`empty_links`](@ref).
"""
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

"""
    maxdegree(store) -> Int

Return the most links a cell can hold in the link store `store`.

A link store is anything with a `links` adjacency matrix and its `link_<p>` payloads: the
cell state itself, or a `NamedTuple` view such as
`(; links = st.cell.links__bond, link_rest = st.cell.link_rest)`.

# Arguments
- `store`: the link store.

# Returns
- `Int`: the number of rows of `store.links`.

See also [`link_count`](@ref).
"""
@inline maxdegree(cell) = size(cell.links, 1)

"""
    link_slot(store, a, b) -> Int

Return the slot of cell `b` in cell `a`'s link row, or `0` if `b` is not there.

With `b = 0` it returns the first empty slot, or `0` if the row is full.

# Arguments
- `store`: the link store (see [`maxdegree`](@ref)).
- `a`, `b`: the cell numbers.

# Returns
- `Int`: the slot, or `0`.

See also [`linked`](@ref).
"""
@inline function link_slot(cell, a, b)
    for k in 1:maxdegree(cell)
        # bounds: k ≤ maxdegree(cell), the rows of links; a ≤ capacity
        @inbounds(cell.links[k, a]) == b && return k
    end
    return 0
end
"""
    linked(store, a, b) -> Bool

Return `true` if cells `a` and `b` are nonzero and linked in the link store `store`.

# Arguments
- `store`: the link store (see [`maxdegree`](@ref)).
- `a`, `b`: the cell numbers.

# Returns
- `Bool`.

# Examples
```jldoctest
julia> using CorePotts

julia> s = empty_links(2, 3);

julia> add_link!(s, 1, 2), linked(s, 2, 1), linked(s, 1, 3), link_count(s, 1)
(true, true, false, 1)
```

See also [`add_link!`](@ref), [`link_slot`](@ref).
"""
@inline linked(cell, a, b) = a != 0 && b != 0 && link_slot(cell, a, b) != 0

# bounds: k ≤ maxdegree(cell), the rows of links; a ≤ capacity
"""
    link_count(store, a) -> Int

Return the number of links of cell `a` in the link store `store`.

# Arguments
- `store`: the link store (see [`maxdegree`](@ref)).
- `a`: the cell number.

# Returns
- `Int`.

See also [`linked`](@ref).
"""
@inline function link_count(cell, a)
    return count(
        k -> @inbounds(cell.links[k, a]) != 0,
        1:maxdegree(cell)
    )
end

_payload_names(cell) = Tuple(k for k in keys(cell) if startswith(String(k), "link_"))

"""
    add_link!(store, a, b; payload...) -> Bool

Link cells `a` and `b` symmetrically in a link store on the host.

The given payload values are written to both slots (`rest = 5.0` writes `link_rest`). The
store's other payloads start at zero, so a slot's payload values mean something only
while it holds a link.

# Arguments
- `store`: the link store (see [`maxdegree`](@ref)), with host arrays.
- `a`, `b`: the cell numbers.

# Keywords
- `payload...`: the payload values of the new link.

# Returns
- `Bool`: `false` if `a == b`, if either is `0`, if they are already linked, or if
  either row is full; else `true`.

# Examples
```jldoctest
julia> using CorePotts

julia> s = empty_links(2, 3; rest = Float64);

julia> add_link!(s, 1, 3; rest = 5.0), s.link_rest[1, 3]
(true, 5.0)
```

See also [`remove_link!`](@ref), [`remove_incident!`](@ref).
"""
function add_link!(cell, a, b; payload...)
    (a == b || a == 0 || b == 0 || linked(cell, a, b)) && return false
    ka = link_slot(cell, a, 0)
    kb = link_slot(cell, b, 0)
    (ka == 0 || kb == 0) && return false
    cell.links[ka, a] = b
    cell.links[kb, b] = a
    for name in _payload_names(cell)             # payloads not given start at zero
        arr = getfield(cell, name)
        arr[ka, a] = zero(eltype(arr))
        arr[kb, b] = zero(eltype(arr))
    end
    for (name, v) in payload
        arr = getfield(cell, Symbol(:link_, name))
        arr[ka, a] = v
        arr[kb, b] = v
    end
    return true
end

"""
    remove_link!(store, a, b) -> Bool

Remove the link between cells `a` and `b` from a link store on the host.

Both slots and their payloads are set to zero.

# Arguments
- `store`: the link store (see [`maxdegree`](@ref)), with host arrays.
- `a`, `b`: the cell numbers.

# Returns
- `Bool`: whether the link existed.

See also [`add_link!`](@ref).
"""
function remove_link!(cell, a, b)
    ka = link_slot(cell, a, b)
    kb = link_slot(cell, b, a)
    ka == 0 && return false
    cell.links[ka, a] = 0
    cell.links[kb, b] = 0
    for name in _payload_names(cell)
        arr = getfield(cell, name)
        arr[ka, a] = zero(eltype(arr))
        arr[kb, b] = zero(eltype(arr))
    end
    return true
end

"""
    remove_incident!(store, c) -> nothing

Remove every link of cell `c` from a link store on the host.

# Arguments
- `store`: the link store (see [`maxdegree`](@ref)), with host arrays.
- `c`: the cell number.

# Returns
- `nothing`.

See also [`remove_link!`](@ref).
"""
function remove_incident!(cell, c)
    for k in 1:maxdegree(cell)
        b = cell.links[k, c]
        b != 0 && remove_link!(cell, c, b)
    end
    return nothing
end

"""
    centroid_distance(T, cell, lattice, a, b) -> T

Return the minimum-image distance between the centroids of cells `a` and `b`, in float
type `T`.

It is the norm of [`centroid_separation`](@ref). Both cells must be alive.

# Arguments
- `T::Type`: the float type of the result.
- `cell`: the cell state, with the moment trackers.
- `lattice::Lattice`: the lattice.
- `a`, `b`: the cell numbers.

# Returns
- `T`: the distance, in embedded lattice units.

See also [`centroid_separation`](@ref).
"""
@inline function centroid_distance(::Type{T}, cell, l::Lattice{N}, a, b) where {T, N}
    ca = centroid(T, cell, l, a)
    cb = centroid(T, cell, l, b)
    return _periodic_norm(T, l, ntuple(d -> ca[d] - cb[d], Val(N)))
end
"""
    centroid_separation(T, cell, lattice, a, b) -> NTuple{N, T}

Return the embedded minimum-image vector from the centroid of cell `b` to that of cell
`a`, in float type `T`.

On a square lattice the minimum image is the per-axis wrap. On a periodic hexagonal
lattice it is the nearest image on the rhombic torus. Its norm is
[`centroid_distance`](@ref). Both cells must be alive.

# Arguments
- `T::Type`: the float type of the result.
- `cell`: the cell state, with the moment trackers.
- `lattice::Lattice`: the lattice.
- `a`, `b`: the cell numbers.

# Returns
- `NTuple{N, T}`: the separation vector.

See also [`centroid_distance`](@ref).
"""
@inline function centroid_separation(::Type{T}, cell, l::Lattice{N}, a, b) where {T, N}
    ca = centroid(T, cell, l, a)
    cb = centroid(T, cell, l, b)
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
    w1 = T(δ[1])
    w2 = T(δ[2])
    L1 = T(l.dims[1])
    L2 = T(l.dims[2])
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

Compute the change of `Σ_links E(a, b, k, distance)` when `prop` moves the target from
`prop.old` to `prop.new`.

Each link counts once; `k` is the slot in `a`'s row, for payload lookup. Every link of
`old` or `new` sees their centroids shift. Centroids come from `cell` and links from
`store`. A model with several relationships sums one call per store.

A partner with `volume == 0` (dead: it lost its last site to copies) is skipped, so its
links contribute nothing until a boundary drops them; its centroid would be 0/0. `old` and
`new` each own a site, so they are alive. A killing copy (`old` owns one site, the target)
removes `old`'s links: each link of `old` contributes `-E(before)` and no post-copy term.
So for every copy, ΔH equals the change of the brute-force sum over the links with two
alive ends. The function does not allocate and does not throw, so it runs on a device.

# Arguments
- `T::Type`: the float type of the distances and of the result.
- `cell`: the cell state, with `volume` and the moment trackers.
- `store`: the link store (default: `cell`).
- `ctx`: the kernel context; the function reads `ctx.lattice`.
- `prop::Proposal`: the copy attempt.
- `E`: the link energy, `E(a, b, k, distance)`.

# Returns
- `T`: the energy change.

See also [`link_frame`](@ref), [`link_at`](@ref).
"""
@inline function link_delta(::Type{T}, cell, ctx, prop::Proposal, E::F) where {T, F}
    return link_delta(
        T, cell, cell, ctx, prop, E
    )
end
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

# `link_delta` in two steps, so generated code can evaluate the link energy inline instead
# of passing it as a closure (a closure in a RuntimeGeneratedFunction body becomes an opaque
# closure, which a downstream package cannot precompile):
#   fr = link_frame(T, cell, lat, prop)
#   for side in 1:2, k in 1:maxdegree(store)
#       c, n, m, before, after = link_at(T, fr, cell, lat, store, side, k)
#       m == 0: no link; m == 1: the link dies with `old`, ΔH −= E(before); m == 2: ΔH +=
#       E(after) − E(before)

"""
    link_frame(T, cell, lattice, prop) -> NamedTuple

Return the per-copy values that [`link_at`](@ref) reads.

Together the two functions compute [`link_delta`](@ref) in two steps, so that generated
code can evaluate the link energy inline instead of passing it as a closure. The frame
holds the copy's two cells, whether the copy kills `old`, and their centroid shifts and
centroids.

# Arguments
- `T::Type`: the float type of the values.
- `cell`: the cell state, with `volume` and the moment trackers.
- `lattice::Lattice`: the lattice.
- `prop::Proposal`: the copy attempt.

# Returns
- `(; a, b, kill, sa, sb, ca, cb, z)`.

# Examples
The loop that `link_delta` runs:
```julia
fr = link_frame(T, cell, lat, prop)
for side in 1:2, k in 1:maxdegree(store)
    c, n, m, before, after = link_at(T, fr, cell, lat, store, side, k)
    m == 0 && continue                         # no link to count
    dH += m == 1 ? -E(c, n, k, before) :       # the link dies with `old`
        E(c, n, k, after) - E(c, n, k, before)
end
```
"""
@inline function link_frame(::Type{T}, cell, lat::Lattice{N}, prop::Proposal{N}) where {
        T, N,
    }
    a, b = prop.old, prop.new
    z = ntuple(_ -> zero(T), Val(N))
    # bounds: nonzero owners a, b are cell ids ≤ capacity = length(volume)
    Va = a == 0 ? zero(eltype(cell.volume)) : @inbounds cell.volume[a]
    Vb = b == 0 ? zero(eltype(cell.volume)) : @inbounds cell.volume[b]
    # the copy takes a's last site: a dies (D-083)
    kill = Va == 1
    sa = (a == 0 || kill) ? z : centroid_shift(T, cell, lat, a, prop.x, -1)
    sb = b == 0 ? z : centroid_shift(T, cell, lat, b, prop.x, +1)
    ca = a == 0 ? z : _centroid(T, cell, lat, a, Va)
    cb = b == 0 ? z : _centroid(T, cell, lat, b, Vb)
    return (; a, b, kill, sa, sb, ca, cb, z)
end

"""
    link_at(T, fr, cell, lattice, store, side, k) -> (c, n, mode, before, after)

Read link slot `k` of one side of the frame `fr` from [`link_frame`](@ref).

The link between `old` and `new` counts once, from `old`. A dead partner is skipped.

# Arguments
- `T::Type`: the float type of the distances.
- `fr`: the frame.
- `cell`: the cell state, with `volume` and the moment trackers.
- `lattice::Lattice`: the lattice.
- `store`: the link store.
- `side::Int`: `1` for `old`, `2` for `new`.
- `k::Int`: the slot.

# Returns
- `(c, n, mode, before, after)`: the cell, its partner, the mode (`0`: no link to count,
  `1`: the link dies with `old`, `2`: it stays) and the centroid distances before and
  after the copy.

See also [`link_delta`](@ref).
"""
@inline function link_at(
        ::Type{T}, fr, cell, lat::Lattice{N}, store, side::Int, k::Int
    ) where {T, N}
    c, sc, cc, other, so = if side == 1
        (fr.a, fr.sa, fr.ca, fr.b, fr.sb)
    else
        (fr.b, fr.sb, fr.cb, fr.a, fr.sa)
    end
    c == 0 && return (c, c, 0, zero(T), zero(T))
    # (k ≤ maxdegree(store), c a cell of the copy)
    n = @inbounds store.links[k, c]
    n == 0 && return (c, n, 0, zero(T), zero(T))
    # the old–new link is counted once (from a)
    n == other && c == fr.b && return (c, n, 0, zero(T), zero(T))
    Vn = @inbounds cell.volume[n]
    Vn == 0 && return (c, n, 0, zero(T), zero(T))     # dead partner: skipped (D-066 item 5)
    cn = _centroid(T, cell, lat, n, Vn)
    before = _periodic_norm(T, lat, ntuple(d -> cc[d] - cn[d], Val(N)))
    # a's links die with it: E(before) → 0
    fr.kill && c == fr.a && return (c, n, 1, before, zero(T))
    sn = n == other ? so : fr.z
    after = _periodic_norm(T, lat, ntuple(d -> cc[d] + sc[d] - cn[d] - sn[d], Val(N)))
    return (c, n, 2, before, after)
end

"""
    HostPhase(f!; every = 1, reads = nothing, writes = nothing)

Construct a phase that synchronizes and calls `f!(cell, st, p, ctx, mcs)` on host copies
every `every` MCS.

Use it for rare host work, for example creating, removing or retuning relationships from
the contact graph. `cell` is `st.cell`. `ctx.lattice` is a host copy, made once per run
(the domain mask never changes). `p` is the live parameter object, as given to the
integrator.

`reads` and `writes` declare what the body touches, so that on a device only those leaves
cross. `reads` columns are read-only. Writing a `reads`-only or undeclared leaf is
undefined: on the host the change persists (the body runs on the live arrays), and on a
device it is dropped (only `writes` go back). What the body sees in leaves it does not
declare is unspecified; on a device it is the device array, which must not be read on the
host. A name that is neither `:ownership` nor a cell column of the state throws an
`ArgumentError` the first time the phase runs, on every backend. Model, site and history
quantities cannot be declared: a body that reads them leaves `reads = nothing`, and they
are never written back.

# Arguments
- `f!`: the body, `f!(cell, st, p, ctx, mcs)`.

# Keywords
- `every::Integer = 1`: run when `mcs % every == 0`.
- `reads = nothing`: `:ownership` and cell column names to copy to the host before the
  body. `nothing` copies the whole state.
- `writes = nothing`: `:ownership` and cell column names to copy to the host before the
  body and back after it; they are the only leaves written back. `nothing` writes every
  cell column back (and so copies every cell column to the host).

# Examples
```julia
HostPhase((cell, st, p, ctx, mcs) -> (cell.y .+= cell.x; nothing);
          reads = (:x,), writes = (:y,))
```
"""
struct HostPhase{F, R, W}
    f!::F
    every::Int
    reads::R                     # `nothing` or a tuple of Symbols
    writes::W
end
function HostPhase(f!; every::Integer = 1, reads = nothing, writes = nothing)
    return HostPhase(f!, Int(every), _declared(reads), _declared(writes))
end
_declared(::Nothing) = nothing
_declared(s::Symbol) = (s,)
function _declared(names)
    t = Tuple(names)
    all(n -> n isa Symbol, t) ||
        throw(ArgumentError("HostPhase `reads`/`writes` take Symbols (`:ownership` or \
            cell column names); got $(repr(names))"))
    return t
end

function (ph::HostPhase{F})(st, p, ctx, key, mcs, backend) where {F}
    return run_phase(ph, st, p, ctx, key, mcs, backend, nothing)
end

function run_phase(ph::HostPhase{F}, st, p, ctx, key, mcs, backend, stats) where {F}
    _check_declared(ph.reads, st)
    _check_declared(ph.writes, st)
    mcs % ph.every == 0 || return 0
    sync!(stats, backend)
    host = _host_state(ph, stats, backend, st)
    ph.f!(
        host.cell, host, p, merge(ctx, (; lattice = host_lattice(stats, ctx.lattice))), mcs
    )
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
                "HostPhase declares `$n`, which is neither `:ownership` nor a cell " *
                    "column of the state (cell columns: $(join(keys(st.cell), ", ")))"
            )
        )
    end
    return nothing
end

# The body's host state: the whole state (`reads = nothing`, as before D-092), or only the
# declared leaves (written columns too; every cell column when `writes = nothing`). On the
# host, declared leaves are the live arrays (no copy).
function _host_state(ph::HostPhase, stats, backend, st)
    ph.reads === nothing && return snapshot(stats, backend, st)
    used = if ph.writes === nothing
        (ph.reads..., keys(st.cell)...)
    else
        (ph.reads..., ph.writes...)
    end
    cell = unique(n for n in used if n !== :ownership)
    return host_leaves(stats, st; ownership = :ownership in used, cell)
end

# a host copy back to its live array (nothing when the body ran on the live array itself)
function _write_back!(stats, live, host)
    return live === host ? nothing : (counted_copy!(stats, live, host); nothing)
end
