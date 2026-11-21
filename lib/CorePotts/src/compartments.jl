# Compartments (D-036): cells grouped into clusters (CompuCell3D's
# clusterId). `st.cell.cluster[c]` is the cluster of cell `c`, named by one of its live
# members (the root, `cluster[r] == r`); a cell alone is its own cluster. Internal vs
# external contact energies are plain model code (`same_cluster`); cluster volume and
# surface are trackers indexed by cluster id; `EVENT_DIVIDE_CLUSTER` divides a
# cluster as a unit.

# bounds: c is a cell id from σ or a copy proposal, ≤ capacity
"""
    cluster_of(cell, c) -> Int32

Return the cluster of cell `c`: `cell.cluster[c]`, or `0` for the medium.

A cluster is named by one of its live members, its root. A cell alone is its own cluster.

# Arguments
- `cell`: the cell state, with a `cluster` column.
- `c`: the cell number.

# Returns
- The cluster id, or `0` when `c == 0`.

# Examples
```jldoctest
julia> using CorePotts

julia> cell = (; cluster = Int32[1, 1, 3]);

julia> cluster_of(cell, 2), cluster_of(cell, 0)
(1, 0)
```

See also [`same_cluster`](@ref), [`init_clusters`](@ref).
"""
@inline cluster_of(cell, c) = c == 0 ? Int32(0) : @inbounds cell.cluster[c]

"""
    same_cluster(cell, a, b) -> Bool

Return `true` if `a` and `b` are cells of the same cluster.

Use it to tell internal from external contact energies. The medium (`0`) is in no
cluster, so the result is `false` if `a` or `b` is `0`.

# Arguments
- `cell`: the cell state, with a `cluster` column.
- `a`, `b`: the cell numbers.

# Returns
- `Bool`.

# Examples
```jldoctest
julia> using CorePotts

julia> cell = (; cluster = Int32[1, 1, 3]);

julia> same_cluster(cell, 1, 2), same_cluster(cell, 1, 3), same_cluster(cell, 0, 0)
(true, false, false)
```

See also [`cluster_of`](@ref).
"""
@inline function same_cluster(cell, a, b)
    return a != 0 && b != 0 &&
        cluster_of(cell, a) == cluster_of(cell, b)
end

"""
    init_clusters(σ, cluster, lattice; relation = nothing, T = Float64, kind = nothing,
                  prefer = ()) -> NamedTuple

Build the compartment columns to merge into the cell state.

The given cluster ids are normalized so that each cluster is named by one live member,
its root. The root is the lowest member whose kind is in `prefer` (the kinds that name
clusters, for example the cytoplasm), else the lowest member. Free and dead slots are
their own cluster. During a run, roots change only when the root dies, and then to the
lowest live member of the same kind if there is one.

# Arguments
- `σ`: the `ownership` array, on the host.
- `cluster::AbstractVector`: a cluster id for every cell slot.
- `lattice::Lattice`: the lattice of `σ`.

# Keywords
- `relation = nothing`: the relation of the cluster surface. With `nothing`, no
  `cluster_surface` column is built.
- `T::Type = Float64`: the element type of `cluster_surface`.
- `kind = nothing`: the kind of every cell slot, read with `prefer`.
- `prefer = ()`: the kinds whose members name their cluster.

# Returns
- `(; cluster, cluster_volume)`, plus `cluster_surface` when `relation` is given.

# Examples
```jldoctest
julia> using CorePotts

julia> σ = Int32[1 2; 3 0]; l = Lattice((2, 2); boundary = Closed());

julia> init_clusters(σ, [2, 2, 3], l; relation = VonNeumann(), T = Int)
(cluster = Int32[1, 1, 3], cluster_volume = Int32[2, 0, 1], cluster_surface = [2, 0, 2])
```

See also [`cluster_of`](@ref), [`recompute_cluster_volume`](@ref),
[`recompute_cluster_surface`](@ref).
"""
function init_clusters(
        σ, cluster::AbstractVector, lat::Lattice; relation = nothing,
        T::Type = Float64, kind = nothing, prefer = ()
    )
    cl = Int32.(cluster)
    _normalize_clusters!(cl, _live(σ, length(cl)); kind, prefer, keep = false)
    out = (; cluster = cl, cluster_volume = recompute_cluster_volume(σ, cl))
    relation === nothing && return out
    return merge(
        out, (;
            cluster_surface = recompute_cluster_surface(σ, cl, lat, relation; T),
        )
    )
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
            want = if !keep
                prefer
            elseif kind !== nothing && 1 <= k <= length(cl)
                (kind[k],)
            else
                ()
            end
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

"""
    recompute_cluster_volume(σ, cluster) -> Vector{Int32}

Compute the volume of every cluster from scratch, indexed by cluster id.

# Arguments
- `σ`: the `ownership` array, on the host.
- `cluster`: the cluster id of every cell slot.

# Returns
- `Vector{Int32}`: the number of sites of each cluster, one entry per cell slot.

See also [`commit_cluster_volume!`](@ref), [`init_clusters`](@ref).
"""
function recompute_cluster_volume(σ, cluster)
    v = zeros(Int32, length(cluster))
    for s in σ
        s > 0 && (v[cluster[s]] += Int32(1))
    end
    return v
end

"""
    recompute_cluster_surface(σ, cluster, lattice, relation; T = Float64) -> Vector{T}

Compute the surface of every cluster from scratch, indexed by cluster id.

The surface of a cluster counts the bonds of `relation` from its sites to sites outside
the cluster, with the relation's weights.

# Arguments
- `σ`: the `ownership` array, on the host.
- `cluster`: the cluster id of every cell slot.
- `lattice::Lattice`: the lattice of `σ`.
- `relation`: an [`AbstractRelationSpec`](@ref) or a resolved relation.

# Keywords
- `T::Type = Float64`: the element type of the result.

# Returns
- `Vector{T}`: one surface per cell slot.

See also [`commit_cluster_surface!`](@ref), [`init_clusters`](@ref).
"""
function recompute_cluster_surface(σ, cluster, lat::Lattice, r; T::Type = Float64)
    return _recompute_cluster_surface(
        T, σ, cluster, lat, r isa Relation ? r : relation(r, lat)
    )
end

function _recompute_cluster_surface(
        ::Type{T}, σ, cluster, lat::Lattice, rel::Relation
    ) where {T}
    σK = map(s -> s == 0 ? Int32(0) : Int32(cluster[s]), σ)
    return _recompute_surface(T, σK, lat, rel, length(cluster))
end

"""
    commit_cluster_volume!(cell, prop) -> nothing

Move the target of the accepted copy `prop` between the clusters of `prop.old` and
`prop.new` in `cell.cluster_volume`.

Nothing changes when both cells are in the same cluster. The updates are atomic, so the
call is safe in a checkerboard phase.

# Arguments
- `cell`: the cell state, with `cluster` and `cluster_volume` columns.
- `prop::Proposal`: the accepted copy.

# Returns
- `nothing`.

See also [`cluster_volume_delta`](@ref).
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

Compute the change of `Σ_clusters E(cluster_volume, k)` when `prop` moves the target
between clusters.

The result is zero when both cells are in the same cluster. The medium has no term.

# Arguments
- `cell`: the cell state, with `cluster` and `cluster_volume` columns.
- `prop::Proposal`: the copy attempt.
- `E`: the energy term, `E(volume, k)` for a cluster `k`.

# Returns
- The energy change, of the type that `E` returns.

# Examples
A volume constraint on clusters, with target volume 4 and strength 2. The copy moves a
site from cluster 3 (volume 1) to cluster 1 (volume 2):
```jldoctest
julia> using CorePotts

julia> cell = (; cluster = Int32[1, 1, 3], cluster_volume = Int32[2, 0, 1]);

julia> prop = CorePotts.Proposal{2}(1, 2, (1, 1), 1, Int32(3), Int32(1));

julia> cluster_volume_delta(cell, prop, (v, k) -> 2.0 * (v - 4)^2)
8.0
```

See also [`commit_cluster_volume!`](@ref), [`cluster_surface_delta`](@ref).
"""
@inline function cluster_volume_delta(cell, prop, E::F) where {F}
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    V = cell.cluster_volume
    dH = zero(typeof(E(zero(eltype(V)), Int32(1))))
    a == b && return dH
    # bounds: a, b are cluster ids of cells, ≤ capacity = length(V)
    a != 0 && (v = @inbounds V[a]; dH += E(v - one(v), a) - E(v, a))
    b != 0 && (v = @inbounds V[b]; dH += E(v + one(v), b) - E(v, b))
    return dH
end

"""
    cluster_surface_change(σ, cell, ctx, prop; relation = ctx.surface,
                           T = typeof(weight(relation, 1))) -> (δa, δb)

Compute the change of the surfaces of the clusters of `prop.old` and `prop.new`.

It is the surface change with each owner replaced by its cluster. Both changes are zero
when the two cells are in the same cluster.

# Arguments
- `σ`: the `ownership` array.
- `cell`: the cell state, with a `cluster` column.
- `ctx`: the kernel context; the function reads `ctx.lattice` and, by default,
  `ctx.surface`.
- `prop::Proposal`: the copy attempt.

# Keywords
- `relation = ctx.surface`: the resolved relation of the surface.
- `T::Type = typeof(weight(relation, 1))`: the type of the changes.

# Returns
- `(δa, δb)`: the changes for the clusters of `prop.old` and `prop.new`.

See also [`cluster_surface_delta`](@ref), [`commit_cluster_surface!`](@ref).
"""
@inline function cluster_surface_change(
        σ, cell, ctx, prop::Proposal{N}; relation = ctx.surface,
        T::Type = typeof(weight(relation, 1))
    ) where {N}
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    δa = zero(T)
    δb = δa
    a == b && return δa, δb
    for k in 1:length(relation)
        # bounds: k ≤ length(relation); inside sites have linear indices ≤ nsites
        inside, y = shift(ctx.lattice, prop.x, @inbounds relation.offsets[k])
        inside || continue
        n = cluster_of(cell, @inbounds σ[linear_index(ctx.lattice, y)])
        w = T(weight(relation, k))
        δa += ifelse(n == a, w, -w)
        δb += ifelse(n == b, -w, w)
    end
    return δa, δb
end

"""
    cluster_surface_delta(cell, prop, δ, E)

Compute the change of `Σ_clusters E(cluster_surface, k)` given
`δ = cluster_surface_change(…)`.

The result is zero when both cells are in the same cluster. The medium has no term.

# Arguments
- `cell`: the cell state, with `cluster` and `cluster_surface` columns.
- `prop::Proposal`: the copy attempt.
- `δ`: the pair from [`cluster_surface_change`](@ref).
- `E`: the energy term, `E(surface, k)` for a cluster `k`.

# Returns
- The energy change, of the type that `E` returns.

See also [`commit_cluster_surface!`](@ref), [`cluster_volume_delta`](@ref).
"""
@inline function cluster_surface_delta(cell, prop, δ, E::F) where {F}
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    S = cell.cluster_surface
    dH = zero(typeof(E(zero(eltype(S)), Int32(1))))
    a == b && return dH
    # bounds: a, b are cluster ids of cells, ≤ capacity = length(S)
    a != 0 && (s = @inbounds S[a]; dH += E(s + δ[1], a) - E(s, a))
    b != 0 && (s = @inbounds S[b]; dH += E(s + δ[2], b) - E(s, b))
    return dH
end

"""
    commit_cluster_surface!(cell, prop, δ) -> nothing

Add `δ = cluster_surface_change(…)` to `cell.cluster_surface` for an accepted copy.

The updates are atomic. With a weighted relation in a float column, the adds of two
copies into one cluster round in the order they happen, which a threaded or device
checkerboard phase does not fix.

# Arguments
- `cell`: the cell state, with `cluster` and `cluster_surface` columns.
- `prop::Proposal`: the accepted copy.
- `δ`: the pair from [`cluster_surface_change`](@ref).

# Returns
- `nothing`.

See also [`recompute_cluster_surface`](@ref).
"""
@inline function commit_cluster_surface!(cell, prop, δ)
    a, b = cluster_of(cell, prop.old), cluster_of(cell, prop.new)
    a == b && return nothing
    a != 0 && (Atomix.@atomic cell.cluster_surface[a] += δ[1])
    b != 0 && (Atomix.@atomic cell.cluster_surface[b] += δ[2])
    return nothing
end

# ---------------------------------------------------------------------------------------
# Lifecycle support (host)

_has_clusters(st) = haskey(st.cell, :cluster)

# Re-root clusters after lifecycle events (a root may have been removed or emptied) and
# make free slots their own cluster. Host arrays.
function _fix_clusters!(stats, st)
    cl = to_host(stats, st.cell.cluster)
    _normalize_clusters!(
        cl, _live(to_host(stats, st.ownership), length(cl));
        kind = to_host(stats, st.cell.kind)
    )
    counted_copy!(stats, st.cell.cluster, cl)
    return nothing
end

function _rebuild_cluster_trackers!(stats, st, σ, ctx)
    haskey(st.cell, :cluster_volume) || haskey(st.cell, :cluster_surface) || return nothing
    cl = to_host(stats, st.cell.cluster)
    haskey(st.cell, :cluster_volume) &&
        counted_copy!(stats, st.cell.cluster_volume, recompute_cluster_volume(σ, cl))
    if haskey(st.cell, :cluster_surface) && haskey(ctx, :surface)
        # in integer weight units for a weighted float column (as the device lifecycle)
        T = eltype(st.cell.cluster_surface)
        σK = map(s -> s == 0 ? Int32(0) : Int32(cl[s]), σ)
        counted_copy!(
            stats, st.cell.cluster_surface,
            _recompute_surface(
                T, σK, ctx.lattice, ctx.surface, length(cl),
                _units_for(T, ctx.surface, length(σ), CPU())
            )
        )
    end
    return nothing
end

# Cluster-mode division plan: the host evaluates `normal` for each dividing root on the
# cluster's own moments, and every member splits along that plane through the cluster
# centroid (`bias[m]` = (member centroid − cluster centroid) · normal).
function _cluster_planes!(stats, normals, bias, lc, st, p, ctx, key, mcs, roots, members)
    lat = host_lattice(stats, ctx.lattice)
    ctx = merge(ctx, (; lattice = lat))
    N = ndims(lat)
    T = eltype(normals)
    σ = to_host(stats, st.ownership)
    cl = to_host(stats, st.cell.cluster)
    cap = length(cl)
    σK = map(s -> s == 0 ? Int32(0) : cl[s], σ)
    mK = init_moments(σK, lat, cap)
    cellK = merge(
        mK, (;
            volume = recompute_cluster_volume(σ, cl),
            generation = to_host(stats, st.cell.generation),
            kind = to_host(stats, st.cell.kind), cluster = cl,
        )
    )
    stK = (; ownership = σK, cell = cellK)
    cell = (;
        volume = to_host(stats, st.cell.volume), anchor = to_host(stats, st.cell.anchor),
        m1 = to_host(stats, st.cell.m1),
    )
    nh = zeros(T, N, cap)
    bh = zeros(T, cap)
    for r in roots
        n = _plane(lc.cluster_normal, T)(stK, p, ctx, key, mcs, Int32(r))
        cK = centroid(T, cellK, lat, r)
        for m in members[r]
            cm = centroid(T, cell, lat, m)
            # member − cluster centroid
            δ = _min_image(T, lat, ntuple(d -> cm[d] - cK[d], Val(N)))
            s = zero(T)
            for d in 1:N
                s += T(δ[d]) * T(n[d])
                nh[d, m] = T(n[d])
            end
            bh[m] = s
        end
    end
    counted_copy!(stats, normals, nh)
    counted_copy!(stats, bias, bh)
    return nothing
end
