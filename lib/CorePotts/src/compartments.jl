# Compartments (ROADMAP M2.10a, D-036): cells grouped into clusters (CompuCell3D's
# clusterId). `st.cell.cluster[c]` is the cluster of cell `c`, named by one of its live
# members (the root, `cluster[r] == r`); a cell alone is its own cluster. Internal vs
# external contact energies are plain model code (`same_cluster`); cluster volume and
# surface are trackers indexed by cluster id; `Lifecycle(…; clusters = true)` divides a
# cluster as a unit.

"""Cluster of cell `c` (`0` for the medium)."""
@inline cluster_of(cell, c) = c == 0 ? Int32(0) : @inbounds cell.cluster[c]

"""`true` if `a` and `b` are cells of the same cluster (use for internal contact energies)."""
@inline same_cluster(cell, a, b) = a != 0 && b != 0 && cluster_of(cell, a) == cluster_of(cell, b)

"""
    init_clusters(σ, cluster, lattice; relation = nothing, T = Float64, kind = nothing,
                  prefer = ()) -> NamedTuple

Compartment storage to merge into the cell state: `cluster` (the given ids, normalized so
each cluster is named by one live member, its root) and `cluster_volume`, plus
`cluster_surface` over `relation` if given (element type `T`). The root is the lowest
member whose `kind` is in `prefer` (the kinds that name clusters, e.g. the cytoplasm),
else the lowest member. Roots are stable: they change only when the root dies, and then
to the lowest live member of the same kind if there is one.
"""
function init_clusters(σ, cluster::AbstractVector, lat::Lattice; relation = nothing,
        T::Type = Float64, kind = nothing, prefer = ())
    cl = Int32.(cluster)
    _normalize_clusters!(cl, _live(σ, length(cl)); kind, prefer, keep = false)
    out = (; cluster = cl, cluster_volume = recompute_cluster_volume(σ, cl))
    relation === nothing && return out
    return merge(out, (; cluster_surface = recompute_cluster_surface(σ, cl, lat, relation; T)))
end

_live(σ, n) = (v = zeros(Bool, n); foreach(s -> s > 0 && (v[s] = true), σ); v)

# Name each cluster by a live member (its root); free and dead slots are their own cluster.
# `keep`: an id that is itself a live member of its cluster stays the root. Otherwise the
# lowest live member whose kind is in `prefer` (or, when re-rooting, the old root's kind),
# else the lowest live member.
function _normalize_clusters!(cl, live; kind = nothing, prefer = (), keep = true)
    members = Dict{Int32, Vector{Int32}}()
    for c in eachindex(cl)
        live[c] && push!(get!(members, cl[c], Int32[]), Int32(c))
    end
    root = Dict{Int32, Int32}()
    for (k, ms) in members
        r = if keep && k in ms
            k
        else
            want = !keep ? prefer : (kind !== nothing && 1 <= k <= length(cl)) ? (kind[k],) : ()
            i = kind === nothing ? nothing : findfirst(m -> kind[m] in want, ms)
            i === nothing ? minimum(ms) : ms[i]
        end
        root[k] = r
    end
    for c in eachindex(cl)
        cl[c] = live[c] ? root[cl[c]] : Int32(c)
    end
    return cl
end

# Ids that name a cluster with live members (not free for reuse, even if that cell died).
_referenced_clusters(cl, volume) = Set(cl[c] for c in eachindex(cl) if volume[c] > 0)

"""Cluster volumes from scratch (indexed by cluster id)."""
function recompute_cluster_volume(σ, cluster)
    v = zeros(Int32, length(cluster))
    for s in σ
        s > 0 && (v[cluster[s]] += Int32(1))
    end
    return v
end

"""Cluster surfaces (bonds to sites outside the cluster) over `relation`, from scratch."""
recompute_cluster_surface(σ, cluster, lat::Lattice, r; T::Type = Float64) =
    _recompute_cluster_surface(T, σ, cluster, lat, r isa Relation ? r : relation(r, lat))

function _recompute_cluster_surface(::Type{T}, σ, cluster, lat::Lattice, rel::Relation) where {T}
    σK = map(s -> s == 0 ? Int32(0) : Int32(cluster[s]), σ)
    return _recompute_surface(T, σK, lat, rel, length(cluster))
end

"""
    commit_cluster_volume!(cell, prop)

Move the target between the clusters of `old` and `new` in `cell.cluster_volume` (atomic,
so it is safe under checkerboard without `cluster_claims`).
"""
@inline function commit_cluster_volume!(cell, prop)
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    a == b && return nothing
    a != 0 && (Atomix.@atomic cell.cluster_volume[a] -= one(eltype(cell.cluster_volume)))
    b != 0 && (Atomix.@atomic cell.cluster_volume[b] += one(eltype(cell.cluster_volume)))
    return nothing
end

"""
    cluster_volume_delta(cell, prop, E)

Change of `Σ_clusters E(cluster_volume, k)` when `prop` moves the target between clusters.
"""
@inline function cluster_volume_delta(cell, prop, E::F) where {F}
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    V = cell.cluster_volume
    dH = zero(typeof(E(zero(eltype(V)), Int32(1))))
    a == b && return dH
    a != 0 && (v = @inbounds V[a]; dH += E(v - one(v), a) - E(v, a))
    b != 0 && (v = @inbounds V[b]; dH += E(v + one(v), b) - E(v, b))
    return dH
end

"""
    cluster_surface_change(σ, cell, ctx, prop; relation = ctx.surface, T) -> (δa, δb)

Change of the surfaces of the clusters of `old` and `new` (zero if they are the same
cluster): `surface_change` with owners replaced by their clusters.
"""
@inline function cluster_surface_change(σ, cell, ctx, prop::Proposal{N}; relation = ctx.surface,
        T::Type = typeof(weight(relation, 1))) where {N}
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    δa = zero(T)
    δb = δa
    a == b && return δa, δb
    for k in 1:length(relation)
        inside, y = shift(ctx.lattice, prop.x, @inbounds relation.offsets[k])
        inside || continue
        n = cluster_of(cell, @inbounds σ[linear_index(ctx.lattice, y)])
        w = T(weight(relation, k))
        δa += ifelse(n == a, w, -w)
        δb += ifelse(n == b, -w, w)
    end
    return δa, δb
end

"""Change of `Σ_clusters E(cluster_surface, k)` given `δ = cluster_surface_change(…)`."""
@inline function cluster_surface_delta(cell, prop, δ, E::F) where {F}
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    S = cell.cluster_surface
    dH = zero(typeof(E(zero(eltype(S)), Int32(1))))
    a == b && return dH
    a != 0 && (s = @inbounds S[a]; dH += E(s + δ[1], a) - E(s, a))
    b != 0 && (s = @inbounds S[b]; dH += E(s + δ[2], b) - E(s, b))
    return dH
end

"""Apply `δ = cluster_surface_change(…)` to `cell.cluster_surface` (atomic)."""
@inline function commit_cluster_surface!(cell, prop, δ)
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    a == b && return nothing
    a != 0 && (Atomix.@atomic cell.cluster_surface[a] += δ[1])
    b != 0 && (Atomix.@atomic cell.cluster_surface[b] += δ[2])
    return nothing
end

"""
    cluster_claims(cell, prop)

Checkerboard claims on the clusters of `old` and `new` (their root ids), so a cluster
changes at most once per color and cluster energies read exact trackers. Without them,
members of one cluster may commit in the same color and see a stale cluster volume (the
trackers themselves stay exact: commits are atomic).
"""
@inline cluster_claims(cell, prop) = (cluster_of(cell, prop.old), cluster_of(cell, prop.new))

# ---------------------------------------------------------------------------------------
# Lifecycle support (host)

_has_clusters(st) = haskey(st.cell, :cluster)

# Re-root clusters after lifecycle events (a root may have been removed or emptied) and
# make free slots their own cluster. Host arrays.
function _fix_clusters!(st)
    cl = Array(st.cell.cluster)
    _normalize_clusters!(cl, _live(Array(st.σ), length(cl)); kind = Array(st.cell.kind))
    copyto!(st.cell.cluster, cl)
    return nothing
end

function _rebuild_cluster_trackers!(st, σ, ctx)
    haskey(st.cell, :cluster_volume) || haskey(st.cell, :cluster_surface) || return nothing
    cl = Array(st.cell.cluster)
    haskey(st.cell, :cluster_volume) && copyto!(st.cell.cluster_volume, recompute_cluster_volume(σ, cl))
    if haskey(st.cell, :cluster_surface) && haskey(ctx, :surface)
        copyto!(st.cell.cluster_surface, _recompute_cluster_surface(eltype(st.cell.cluster_surface),
            σ, cl, ctx.lattice, ctx.surface))
    end
    return nothing
end

# Cluster-mode division plan: the host evaluates `normal` for each dividing root on the
# cluster's own moments, and every member splits along that plane through the cluster
# centroid (`bias[m]` = (member centroid − cluster centroid) · normal).
function _cluster_planes!(normals, bias, lc, st, p, ctx, key, mcs, roots, members)
    lat = host_lattice(ctx.lattice)
    ctx = merge(ctx, (; lattice = lat))
    N = ndims(lat)
    T = eltype(normals)
    σ = Array(st.σ)
    cl = Array(st.cell.cluster)
    cap = length(cl)
    σK = map(s -> s == 0 ? Int32(0) : cl[s], σ)
    mK = init_moments(σK, lat, cap)
    cellK = merge(mK, (; volume = recompute_cluster_volume(σ, cl),
        generation = Array(st.cell.generation), kind = Array(st.cell.kind), cluster = cl))
    stK = (; σ = σK, cell = cellK)
    cell = (; volume = Array(st.cell.volume), anchor = Array(st.cell.anchor), m1 = Array(st.cell.m1))
    nh = zeros(T, N, cap); bh = zeros(T, cap)
    for r in roots
        n = lc.normal(stK, p, ctx, key, mcs, Int32(r))
        cK = centroid(T, cellK, lat, r)
        for m in members[r]
            cm = centroid(T, cell, lat, m)
            δ = embed(lat, ntuple(Val(N)) do d                  # member − cluster centroid (minimum image)
                x = cm[d] - cK[d]
                lat.periodic[d] ? x - T(lat.dims[d]) * round(x / T(lat.dims[d])) : x
            end)
            s = zero(T)
            for d in 1:N
                s += T(δ[d]) * T(n[d])
                nh[d, m] = T(n[d])
            end
            bh[m] = s
        end
    end
    copyto!(normals, nh); copyto!(bias, bh)
    return nothing
end
