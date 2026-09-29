# Spatial queries (ROADMAP M2.7): site predicates, per-cell reductions and the cell contact
# graph. Site predicates are device functions; `CellReduce` is a phase; the contact graph is
# rebuilt on the host at a synchronization point (only when a model references it).

"""`true` if some in-domain `relation` neighbour of site `i` has a different owner."""
@inline function is_boundary_site(σ, ctx, i; relation = ctx.contact)
    lat = ctx.lattice
    x = coordinates(lat, i)
    a = @inbounds σ[i]
    for k in 1:length(relation)
        inside, y = shift(lat, x, @inbounds relation.offsets[k])
        (inside && @inbounds(σ[linear_index(lat, y)]) != a) && return true
    end
    return false
end

"""Weighted count of in-domain `relation` neighbours `j` of site `i` with `pred(σ[j])`."""
@inline function count_neighbors(pred::F, σ, ctx, i; relation = ctx.contact) where {F}
    lat = ctx.lattice
    x = coordinates(lat, i)
    n = zero(weight(relation, 1))
    for k in 1:length(relation)
        inside, y = shift(lat, x, @inbounds relation.offsets[k])
        (inside && pred(@inbounds σ[linear_index(lat, y)])) && (n += weight(relation, k))
    end
    return n
end

"""
    CellReduce((:cell, :name), f; op = +)

Phase: `st.cell.name[c] = op_{i ∈ c} f(st, p, ctx, key, mcs, i)` over every cell's sites
(`op ∈ (+, max, min)`; atomics, so the result does not depend on thread order for integers,
and up to rounding for floats). Covers owner sums, means (divide by volume), counts of
sites satisfying a predicate (return a `Bool`/`Int32`), and structured owner sums.
"""
struct CellReduce{D <: Part, F, O}
    dst::D
    f::F
    op::O
end
CellReduce(dst::Tuple{Symbol, Symbol}, f; op = +) = CellReduce(Part(dst), f, op)

_identity(::typeof(+), T) = zero(T)
_identity(::typeof(max), T) = typemin(T)
_identity(::typeof(min), T) = typemax(T)

@kernel function _cell_reduce_kernel!(f, op, dst, st, p, ctx, key, mcs)
    i = @index(Global, Linear)
    c = @inbounds st.σ[i]
    if c != 0
        v = convert(eltype(dst), f(st, p, ctx, key, mcs, i))
        _atomic!(op, dst, c, v)
    end
end
@inline _atomic!(::typeof(+), a, c, v) = (Atomix.@atomic a[c] += v; nothing)
@inline _atomic!(op::Union{typeof(max), typeof(min)}, a, c, v::Integer) =
    (op === max ? (Atomix.@atomic a[c] max v) : (Atomix.@atomic a[c] min v); nothing)
@inline function _atomic!(op::Union{typeof(max), typeof(min)}, a, c, v)   # floats: CAS loop
    old = @inbounds a[c]
    while op(old, v) != old
        old, ok = Atomix.@atomicreplace a[c] old => v
        ok && break
    end
    return nothing
end

function (ph::CellReduce{D, F, O})(st, p, ctx, key, mcs, backend) where {D, F, O}
    dst = ph.dst(st)
    fill!(dst, _identity(ph.op, eltype(dst)))
    n = length(st.σ)
    _cell_reduce_kernel!(backend)(ph.f, ph.op, dst, st, p, ctx, key, mcs; ndrange = n,
        workgroupsize = _phase_groupsize(backend, n))
    return 2
end

# ---------------------------------------------------------------------------------------
# Contact graph (host)

"""
    ContactGraph

Cells that touch over a relation and their shared interface measure (weighted bond count),
in CSR form: the neighbours of `c` are `col[row_ptr[c]:row_ptr[c+1]-1]` with `measure`
alongside; `medium[c]` is `c`'s interface with the medium.
"""
struct ContactGraph{T}
    row_ptr::Vector{Int32}
    col::Vector{Int32}
    measure::Vector{T}
    medium::Vector{T}
end

"""
    contact_graph(σ, lattice, relation, ncell) -> ContactGraph

Build the graph from scratch (face-sharing neighbours with `VonNeumann(1)`, as CompuCell3D's
NeighborTracker; any relation, weighted or not, works).
"""
function contact_graph(σ, lat::Lattice, r::Relation, ncell::Integer)
    T = typeof(weight(r, 1))
    pairs = Dict{Tuple{Int32, Int32}, T}()
    medium = zeros(T, ncell)
    for i in 1:nsites(lat)
        a = σ[i]
        x = coordinates(lat, i)
        for k in 1:length(r)
            inside, y = shift(lat, x, r.offsets[k])
            inside || continue
            b = σ[linear_index(lat, y)]
            (a == b || a == 0) && continue
            w = weight(r, k)
            if b == 0
                medium[a] += w
            else
                pairs[(a, b)] = get(pairs, (a, b), zero(T)) + w
            end
        end
    end
    counts = zeros(Int32, ncell)
    for (a, _) in keys(pairs)
        counts[a] += 1
    end
    row_ptr = Int32[1; 1 .+ cumsum(counts)]
    col = zeros(Int32, length(pairs)); measure = zeros(T, length(pairs))
    fill_ptr = copy(row_ptr[1:ncell])
    for ((a, b), m) in sort!(collect(pairs); by = first)
        col[fill_ptr[a]] = b; measure[fill_ptr[a]] = m
        fill_ptr[a] += 1
    end
    return ContactGraph(row_ptr, col, measure, medium)
end

"""Neighbouring cells of `c` (sorted ids)."""
neighbors(g::ContactGraph, c) = view(g.col, g.row_ptr[c]:(g.row_ptr[c + 1] - 1))
"""Shared interface measure of cells `c` and `n` (zero if they do not touch)."""
function contact(g::ContactGraph{T}, c, n) where {T}
    n == 0 && return g.medium[c]
    r = g.row_ptr[c]:(g.row_ptr[c + 1] - 1)
    j = searchsortedfirst(view(g.col, r), n)
    return j <= length(r) && g.col[r[j]] == n ? g.measure[r[j]] : zero(T)
end
