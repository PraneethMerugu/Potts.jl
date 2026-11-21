# Per-cell contact counts with a kind predicate (D-150 G1).
#
# For cell c, a contact count over relation R and kind set M is
#
#     n_c = #{(s, s′) : σ(s) = c, s′ ∈ R(s) inside the lattice, σ(s′) ≠ c, kind(σ(s′)) ∈ M}
#
# with the medium (owner 0) of kind 0. With M every kind it is the unweighted surface over
# R. The count is exact after every accepted copy: `commit_contact_count!` updates the old
# and new cells and every third cell next to the target, atomically (concurrent checkerboard
# copies share third cells). Lifecycle events (divisions, removals, transitions) recompute
# it from σ, on the host (`rebuild_trackers!`) or on the device (`_dcount_*_body!`).
#
# The trackers a lifecycle must rebuild are named in the run context as `ctx.contact_counts`
# (a `ContactCounts`, passed among a problem's `relations`). Models without one pay nothing.

"""
    ContactCount(column, relation, mask; kinds = 64)

One contact-count tracker: for each cell, the number of its neighbor pairs, over
`relation`, with a site of another cell whose kind is in `mask`.

For cell `c` the count is the number of pairs `(s, s′)` with `σ(s) = c`, `s′` a neighbor
of `s` inside the lattice, `σ(s′) ≠ c` and the kind of `σ(s′)` in `mask`. The medium has
kind 0. Each pair counts once, whatever the relation's weights. With every kind in `mask`
it is the unweighted surface over `relation`. Pass the trackers to a problem in a
[`ContactCounts`](@ref).

# Arguments
- `column::Symbol`: the cell column that holds the counts, an `Int32` vector in
  `st.cell`.
- `relation`: a symmetric relation without the zero offset, for example `Moore(1)`.
- `mask::Integer`: the kind set: bit `k` set means a partner of kind `k` counts. It holds
  kinds 0 to 63.

# Keywords
- `kinds::Integer = 64`: the number of kinds of the model, medium included, at most 64.
  A mask with a bit at or above `kinds` throws an `ArgumentError`.

# Examples
```jldoctest
julia> using CorePotts

julia> ContactCount(:n_medium, Moore(1), 0b1; kinds = 3).mask
0x0000000000000001
```

See also [`ContactCounts`](@ref), [`commit_contact_count!`](@ref).
"""
struct ContactCount{P <: Part, R}
    column::P
    relation::R
    mask::UInt64
end
function ContactCount(column::Symbol, relation, mask::Integer; kinds::Integer = 64)
    kinds <= 64 || throw(
        ArgumentError(
            "ContactCount `$column`: a kind mask holds at most 64 kinds (medium " *
                "included), the model has $kinds"
        )
    )
    (mask >= 0 && (kinds == 64 || mask >> kinds == 0)) || throw(
        ArgumentError(
            "ContactCount `$column`: mask $(repr(mask)) names kinds beyond the \
                model's $kinds"
        )
    )
    return ContactCount(Part((:cell, column)), relation, UInt64(mask))
end

"""
    ContactCounts(counts::Tuple)

The contact-count trackers of a model, passed as one entry of a problem's `relations`.

It is resolved on the lattice like a relation and is exposed to the model's functions as
`ctx.contact_counts`. The lifecycle, on the host and on a device, recomputes the counts
from it after divisions, removals and transitions. A model without one pays nothing.

# Arguments
- `counts::Tuple`: the [`ContactCount`](@ref) trackers.

# Examples
```julia
relations = (; contact_counts = ContactCounts((ContactCount(:n_medium, Moore(1), 0b1),)))
prob = PottsProblem(f, st, lattice, p, (0, 100); relations)
```

See also [`ContactCount`](@ref), [`PottsProblem`](@ref).
"""
struct ContactCounts{C <: Tuple}
    counts::C
end
function relation(c::ContactCounts, l::Lattice)
    return ContactCounts(
        map(x -> ContactCount(x.column, relation(x.relation, l), x.mask), c.counts)
    )
end
radius(c::ContactCounts) = maximum(x -> radius(x.relation), c.counts; init = 0)

"""Whether partner kind `k` (0 = medium) is in the kind set `mask`, as 0 or 1."""
@inline function _kind_bit(mask::UInt64, k)
    return Int32(
        ifelse(
            UInt32(k) < UInt32(64), (mask >> (UInt32(k) & 0x3f)) & UInt64(1), UInt64(0)
        )
    )
end   # kind ≥ 64: never
# bounds: q is an owner from σ, so q ≤ capacity = length(kind)
"""Kind of owner `q` (0 for the medium)."""
@inline _owner_kind(kind, q) = q == 0 ? Int32(0) : Int32(@inbounds kind[q])

"""
    commit_contact_count!(count, σ, kind, relation, mask, lattice, prop) -> nothing

Apply an accepted copy to a contact count.

The target leaves the losing cell and joins the gaining cell, and every other cell next to
the target swaps its partner from the losing to the gaining cell. It may run before or
after the `ownership` write, because the relation excludes the zero offset. The adds are
atomic, so concurrent checkerboard copies may share a third cell.

# Arguments
- `count::AbstractVector{Int32}`: the tracker, one entry per cell.
- `σ`: the `ownership` array.
- `kind`: the kind of every cell (`st.cell.kind`).
- `relation`: the resolved relation.
- `mask::UInt64`: the kind set.
- `lattice::Lattice`: the lattice.
- `prop::Proposal`: the accepted copy.

# Returns
- `nothing`.

See also [`recompute_contact_count`](@ref), [`ContactCount`](@ref).
"""
@inline function commit_contact_count!(count, σ, kind, rel, mask::UInt64, lat, prop)
    o, n = prop.old, prop.new
    bo = _kind_bit(mask, _owner_kind(kind, o))
    bn = _kind_bit(mask, _owner_kind(kind, n))
    δo = Int32(0)
    δn = Int32(0)
    for k in 1:length(rel)
        # bounds: k ≤ length(rel); inside sites have linear indices ≤ nsites
        inside, y = shift(lat, prop.x, @inbounds rel.offsets[k])
        inside || continue
        q = @inbounds σ[linear_index(lat, y)]
        bq = _kind_bit(mask, _owner_kind(kind, q))
        # old: loses (t, s′); gains (s′, t) if s′ stays in old
        δo += ifelse(q == o, bn, -bq)
        # new: gains (t, s′); loses (s′, t) if s′ is in new
        δn += ifelse(q == n, -bo, bq)
        if q != 0 && q != o && q != n && bn != bo
            # a third cell: partner old → new
            Atomix.@atomic count[q] += bn - bo
        end
    end
    o != 0 && δo != 0 && Atomix.@atomic count[o] += δo
    n != 0 && δn != 0 && Atomix.@atomic count[n] += δn
    return nothing
end

"""The counted pairs of site `i`, owned by `c ≠ 0`."""
@inline function _site_contacts(σ, kind, lat, rel, mask::UInt64, i::Int, c)
    x = coordinates(lat, i)
    a = Int32(0)
    for k in 1:length(rel)
        # bounds: k ≤ length(rel); inside sites have linear indices ≤ nsites
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        q = @inbounds σ[linear_index(lat, y)]
        q != c && (a += _kind_bit(mask, _owner_kind(kind, q)))
    end
    return a
end

"""
    recompute_contact_count(σ, kind, lattice, relation, mask, ncell; T = Int32) -> Vector{T}

Compute a contact count from scratch: for initialization, lifecycle rebuilds and checks.

# Arguments
- `σ`: the `ownership` array, on the host.
- `kind`: the kind of every cell.
- `lattice::Lattice`: the lattice.
- `relation`: a relation specification or a resolved relation.
- `mask::Integer`: the kind set (bit `k`: kind `k` counts; the medium is kind 0).
- `ncell::Integer`: the number of cell slots.

# Keywords
- `T::Type = Int32`: the element type.

# Returns
- `Vector{T}`: one count per cell slot.

# Examples
```jldoctest
julia> using CorePotts

julia> l = Lattice((4, 4)); σ = zeros(Int32, 4, 4); σ[2:3, 2:3] .= 1;

julia> recompute_contact_count(σ, Int32[1], l, Moore(1), 0b1, 1)
1-element Vector{Int32}:
 20
```

See also [`commit_contact_count!`](@ref), [`ContactCount`](@ref).
"""
function recompute_contact_count(
        σ, kind, lat::Lattice, r, mask::Integer, ncell::Integer; T::Type = Int32
    )
    return _recompute_contact_count(T, σ, kind, lat, relation(r, lat), UInt64(mask), ncell)
end

function _recompute_contact_count(
        ::Type{T}, σ, kind, lat::Lattice, rel::Relation,
        mask::UInt64, ncell::Integer
    ) where {T}
    S = zeros(T, ncell)
    for i in 1:nsites(lat)
        c = σ[i]
        c == 0 && continue
        S[c] += T(_site_contacts(σ, kind, lat, rel, mask, i, c))
    end
    return S
end

# Host rebuild of every count named in `ctx.contact_counts` (`_rebuild_trackers!`)
_rebuild_contact_counts!(stats, st, σ, lat, ::Nothing) = nothing
function _rebuild_contact_counts!(stats, st, σ, lat, cc::ContactCounts)
    kind = to_host(stats, st.cell.kind)
    cap = length(kind)
    foreach(cc.counts) do x
        col = x.column(st)
        counted_copy!(
            stats, col, _recompute_contact_count(
                eltype(col), σ, kind, lat, x.relation, x.mask, cap
            )
        )
        return nothing
    end
    return nothing
end
_contact_counts(ctx) = haskey(ctx, :contact_counts) ? ctx.contact_counts : nothing

# Device lifecycle: on an event round every count is zeroed (cells) and then summed from σ
# (sites), after the partition and the rules (kinds of transitions are final)
_count_columns(st, ::Nothing) = nothing
_count_columns(st, cc::ContactCounts) = map(x -> x.column(st), cc.counts)

# the per-column work of the two kernels below: functors, not per-call closures
struct _ZeroAt{C}
    c::C
end
@inline function (f::_ZeroAt)(a)
    # c ≤ capacity = length(a)
    @inbounds a[f.c] = zero(eltype(a))
    return nothing
end
struct _AddContacts{S, K, L, I, C}
    σ::S
    kind::K
    lat::L
    i::I
    s::C
end
@inline function (f::_AddContacts)(a, x)
    v = _site_contacts(f.σ, f.kind, f.lat, x.relation, x.mask, Int(f.i), f.s)
    v != 0 && Atomix.@atomic a[f.s] += eltype(a)(v)
    return nothing
end

@inline function _dcount_zero_body!(c, dv, par, cols)
    _on(dv, par) || return nothing
    map(_ZeroAt(c), cols)
    return nothing
end

@inline function _dcount_body!(i, dv, par, σ, kind, cc, cols, lat)
    _on(dv, par) || return nothing
    # bounds: i ≤ nsites = length(σ); owners s ≤ capacity
    s = @inbounds σ[i]
    s > 0 || return nothing
    map(_AddContacts(σ, kind, lat, i, s), cols, cc.counts)
    return nothing
end
