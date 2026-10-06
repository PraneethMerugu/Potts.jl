# Per-cell contact counts with a kind predicate (D-150 G1).
#
# For cell c, a contact count over relation R and kind set M is
#
#     n_c = #{(s, s′) : σ(s) = c, s′ ∈ R(s) inside the lattice, σ(s′) ≠ c, kind(σ(s′)) ∈ M}
#
# with the medium (owner 0) of kind 0. With M every kind it is the unweighted surface over R.
# The count is exact after every accepted copy: `commit_contact_count!` updates the old and
# new cells and every third cell next to the target, atomically (concurrent checkerboard
# copies share third cells). Lifecycle events (divisions, removals, transitions) recompute it
# from σ, on the host (`rebuild_trackers!`) or on the device (`_dcount_*_body!`).
#
# The trackers a lifecycle must rebuild are named in the run context as `ctx.contact_counts`
# (a `ContactCounts`, passed among a problem's `relations`). Models without one pay nothing.

"""
    ContactCount(column, relation, mask)

One contact-count tracker: the cell column `column` (an `Int32` vector of the cell state),
its relation (a symmetric relation without the origin, e.g. `Moore(1)`) and the kind set
`mask` (bit `k` set: a partner of kind `k` counts; the medium is kind 0). Pairs are counted
once each, whatever the relation's weights.
"""
struct ContactCount{P <: Part, R}
    column::P
    relation::R
    mask::UInt64
end
ContactCount(column::Symbol, relation, mask::Integer) = ContactCount(Part((:cell, column)), relation, UInt64(mask))

"""
    ContactCounts(counts::Tuple)

The contact-count trackers of a model, as one entry of a problem's `relations`
(`relations = (; contact_counts = ContactCounts((ContactCount(:n_medium, Moore(1), 0b1),)))`):
it is resolved on the lattice like a relation and exposed as `ctx.contact_counts`, from
which the lifecycle (host and device) recomputes the counts after events.
"""
struct ContactCounts{C <: Tuple}
    counts::C
end
relation(c::ContactCounts, l::Lattice) =
    ContactCounts(map(x -> ContactCount(x.column, relation(x.relation, l), x.mask), c.counts))
radius(c::ContactCounts) = maximum(x -> radius(x.relation), c.counts; init = 0)

"""Whether partner kind `k` (0 = medium) is in the kind set `mask`, as 0 or 1."""
@inline _kind_bit(mask::UInt64, k) = Int32((mask >> (UInt32(k) & 0x3f)) & UInt64(1))
"""Kind of owner `q` (0 for the medium)."""
@inline _owner_kind(kind, q) = q == 0 ? Int32(0) : Int32(@inbounds kind[q])

"""
    commit_contact_count!(count, σ, kind, relation, mask, lattice, prop)

Apply accepted copy `prop` to the contact count `count` (one `Int32` per cell): the target
leaves `old` and joins `new`, and every other cell next to the target swaps its partner
`old` for `new`. Valid before or after the ownership write (the relation excludes the
origin). Atomic, so concurrent checkerboard copies may share third cells.
"""
@inline function commit_contact_count!(count, σ, kind, rel, mask::UInt64, lat, prop)
    o, n = prop.old, prop.new
    bo = _kind_bit(mask, _owner_kind(kind, o))
    bn = _kind_bit(mask, _owner_kind(kind, n))
    δo = Int32(0)
    δn = Int32(0)
    for k in 1:length(rel)
        inside, y = shift(lat, prop.x, @inbounds rel.offsets[k])
        inside || continue
        q = @inbounds σ[linear_index(lat, y)]
        bq = _kind_bit(mask, _owner_kind(kind, q))
        δo += ifelse(q == o, bn, -bq)      # old: loses (t, s′); gains (s′, t) if s′ stays in old
        δn += ifelse(q == n, -bo, bq)      # new: gains (t, s′); loses (s′, t) if s′ is in new
        if q != 0 && q != o && q != n && bn != bo
            Atomix.@atomic count[q] += bn - bo                 # a third cell: partner old → new
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
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        q = @inbounds σ[linear_index(lat, y)]
        q != c && (a += _kind_bit(mask, _owner_kind(kind, q)))
    end
    return a
end

"""
    recompute_contact_count(σ, kind, lattice, relation, mask, ncell; T = Int32) -> Vector{T}

A contact count from scratch (initialization, lifecycle rebuilds and checks).
"""
recompute_contact_count(σ, kind, lat::Lattice, r, mask::Integer, ncell::Integer; T::Type = Int32) =
    _recompute_contact_count(T, σ, kind, lat, relation(r, lat), UInt64(mask), ncell)

function _recompute_contact_count(::Type{T}, σ, kind, lat::Lattice, rel::Relation, mask::UInt64, ncell::Integer) where {T}
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
    kind = _to_host(stats, st.cell.kind)
    cap = length(kind)
    foreach(cc.counts) do x
        col = x.column(st)
        _copy!(stats, col, _recompute_contact_count(eltype(col), σ, kind, lat, x.relation, x.mask, cap))
        return nothing
    end
    return nothing
end
_contact_counts(ctx) = haskey(ctx, :contact_counts) ? ctx.contact_counts : nothing

# Device lifecycle: on an event round every count is zeroed (cells) and then summed from σ
# (sites), after the partition and the rules (kinds of transitions are final)
_count_columns(st, ::Nothing) = nothing
_count_columns(st, cc::ContactCounts) = map(x -> x.column(st), cc.counts)

@inline function _dcount_zero_body!(c, dv, par, cols)
    _on(dv, par) || return nothing
    map(a -> (@inbounds a[c] = zero(eltype(a)); nothing), cols)       # c ≤ capacity = length(a)
    return nothing
end

@inline function _dcount_body!(i, dv, par, σ, kind, cc, cols, lat)
    _on(dv, par) || return nothing
    s = @inbounds σ[i]
    s > 0 || return nothing
    map(cols, cc.counts) do a, x
        v = _site_contacts(σ, kind, lat, x.relation, x.mask, Int(i), s)
        v != 0 && Atomix.@atomic a[s] += eltype(a)(v)
        nothing
    end
    return nothing
end
