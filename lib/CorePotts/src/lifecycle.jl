# Cell lifecycle: division, removal, kind transition, creation and id reuse
# (ROADMAP M2.8, INTERNALS §1.7 as amended by D-035).
#
# Per checked MCS: one trigger kernel over cells writes an event code per cell and counts
# events atomically; the host reads the 4-byte count. Quiet MCS end there. Otherwise the
# host plans (allocates daughter ids lowest-first among free ids, defers on exhausted
# capacity), then kernels partition sites by plane, remove cells, set kinds and apply the
# daughter state rule, and the trackers are rebuilt exactly.
#
# Cell ids are `1:capacity`; an id is free when its volume is zero. Reusing an id increments
# its generation, so cell-addressed randomness never replays (F2).

const EVENT_NONE = Int32(0)
const EVENT_DIVIDE = Int32(1)
const EVENT_REMOVE = Int32(2)
const EVENT_TRANSITION = Int32(3)

"""
    Lifecycle(trigger; normal, kind, divide!, every = 1, clusters = false)

The lifecycle of a model (generated from `@divide`, `@remove`, `@transition` rules, or
hand-written):

- `trigger(st, p, ctx, key, mcs, c) -> Int32` — the event for live cell `c`: `EVENT_NONE`,
  `EVENT_DIVIDE`, `EVENT_REMOVE` or `EVENT_TRANSITION` (priorities are resolved inside).
- `normal(st, p, ctx, key, mcs, c) -> NTuple{N}` — division plane normal through the
  centroid (`along_minor_axis`, `along_major_axis`, `random_plane`, or any vector).
- `kind(st, p, ctx, key, mcs, c) -> Int32` — the destination kind of a transition.
- `divide!(st, p, ctx, key, mcs, parent, daughter)` — daughter state rule, run after the
  default `Copy` of every non-tracker cell quantity (e.g. halve extensive quantities).
- `every` — check triggers every `every` MCS.
- `clusters` — divide compartment clusters as a unit (`st.cell.cluster`, D-036): a cluster
  divides when its root triggers `EVENT_DIVIDE` (members' own divide events are ignored);
  `normal` is evaluated on the host with the cluster's moments (`st.cell` then holds cluster
  volume/moments, indexed by root), and every member splits along that plane through the
  cluster centroid. Daughters form a new cluster. Without `clusters`, a dividing
  compartment's daughter stays in its parent's cluster.

Division requires the moment trackers (`init_moments`).
"""
struct Lifecycle{TR, NO, KI, DV}
    trigger::TR
    normal::NO
    kind::KI
    divide!::DV
    every::Int
    clusters::Bool
end
Lifecycle(trigger; normal = AlongMinorAxis{Float64}(), kind = keep_kind, divide! = no_divide_rule,
    every::Integer = 1, clusters::Bool = false) =
    Lifecycle(trigger, normal, kind, divide!, Int(every), clusters)

@inline keep_kind(st, p, ctx, key, mcs, c) = @inbounds st.cell.kind[c]
@inline no_divide_rule(st, p, ctx, key, mcs, parent, daughter) = nothing

const STREAM_DIVISION_PLANE = stream_id("CorePotts.division_plane")

"""
    AlongMinorAxis{T}(), AlongMajorAxis{T}(), RandomPlane{T}()

Division plane normals, computed in float type `T` (use `Float32` on Metal):
`AlongMinorAxis` divides across the long axis (the plane contains the minor axis; normal =
major axis), `AlongMajorAxis` divides along it, `RandomPlane` draws a uniform plane
addressed by cell id and generation. `along_minor_axis` etc. are the `Float64` instances.
"""
struct AlongMinorAxis{T} end
struct AlongMajorAxis{T} end
struct RandomPlane{T} end
const along_minor_axis = AlongMinorAxis{Float64}()
const along_major_axis = AlongMajorAxis{Float64}()
const random_plane = RandomPlane{Float64}()

@inline (::AlongMinorAxis{T})(st, p, ctx, key, mcs, c) where {T} =
    principal_axis(T, st.cell, ctx.lattice, c, 1)
@inline (::AlongMajorAxis{T})(st, p, ctx, key, mcs, c) where {T} =
    principal_axis(T, st.cell, ctx.lattice, c, ndims(ctx.lattice))
@inline function (::RandomPlane{T})(st, p, ctx, key, mcs, c) where {T}
    r = draw(key, mcs, cell_entity(c, @inbounds st.cell.generation[c]), STREAM_DIVISION_PLANE)
    return _random_unit(T, r, Val(ndims(ctx.lattice)))
end
@inline function _random_unit(::Type{T}, r, ::Val{2}) where {T}
    θ = 2T(π) * uniform(T, r[1])
    return (cos(θ), sin(θ))
end
@inline function _random_unit(::Type{T}, r, ::Val{3}) where {T}
    z = 2uniform(T, r[1]) - one(T)
    φ = 2T(π) * uniform(T, r[2])
    s = sqrt(max(one(T) - z^2, zero(T)))
    return (s * cos(φ), s * sin(φ), z)
end

"""Unit eigenvector of cell `c`'s covariance for its `k`-th largest eigenvalue."""
@inline function principal_axis(::Type{T}, cell, l::Lattice{2}, c, k) where {T}
    C = covariance(T, cell, c, Val(2))
    λ = principal_moments(C)[k]
    a, b, d = C
    v = abs(b) > eps(T) * (abs(a) + abs(d)) ? (λ - d, b) :
        (a >= d) == (k == 1) ? (one(T), zero(T)) : (zero(T), one(T))
    n = sqrt(v[1]^2 + v[2]^2)
    return (v[1] / n, v[2] / n)
end
@inline function principal_axis(::Type{T}, cell, l::Lattice{3}, c, k) where {T}
    C = covariance(T, cell, c, Val(3))
    λ = principal_moments(C)[k]
    a, b, e, d, f, g = C[1], C[2], C[3], C[4], C[5], C[6]      # [a b e; b d f; e f g]
    r1 = (a - λ, b, e); r2 = (b, d - λ, f); r3 = (e, f, g - λ)
    cross(u, v) = (u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1])
    cands = (cross(r1, r2), cross(r1, r3), cross(r2, r3))
    best = cands[1]; nb = sum(abs2, best)
    for v in cands
        n = sum(abs2, v)
        n > nb && (best = v; nb = n)
    end
    o, z = one(T), zero(T)
    nb < eps(T)^2 && return k == 1 ? (o, z, z) : k == 2 ? (z, o, z) : (z, z, o)
    s = sqrt(nb)
    return (best[1] / s, best[2] / s, best[3] / s)
end

# ---------------------------------------------------------------------------------------
# Kernels

@kernel function _trigger_kernel!(events, count, trigger, st, p, ctx, key, mcs)
    c = @index(Global, Linear)
    e = EVENT_NONE
    if @inbounds(st.cell.volume[c]) > 0
        e = Int32(trigger(st, p, ctx, key, mcs, Int32(c)))
    end
    @inbounds events[c] = e
    e != EVENT_NONE && Atomix.@atomic count[1] += Int32(1)
end

@kernel function _normal_kernel!(normals, @Const(daughter), normal, st, p, ctx, key, mcs)
    c = @index(Global, Linear)
    if @inbounds(daughter[c]) > 0
        n = normal(st, p, ctx, key, mcs, Int32(c))
        for d in 1:length(n)
            @inbounds normals[d, c] = n[d]
        end
    end
end

@kernel function _partition_kernel!(σ, @Const(daughter), @Const(normals), @Const(bias), @Const(removed), cell, lat)
    i = @index(Global, Linear)
    c = @inbounds σ[i]
    if c > 0
        if @inbounds(removed[c])
            @inbounds σ[i] = Int32(0)
        elseif @inbounds(daughter[c]) > 0
            N = ndims(lat)
            δ = min_image(lat, coordinates(lat, i), anchor(cell, c, Val(N)))
            T = eltype(normals)
            V = T(@inbounds cell.volume[c])
            side = @inbounds bias[c]                                # 0 unless clusters divide
            for d in 1:N
                offset = T(δ[d]) - T(@inbounds cell.m1[d, c]) / V      # site − centroid
                side += offset * @inbounds(normals[d, c])
            end
            side > 0 && (@inbounds σ[i] = daughter[c])
        end
    end
end

@kernel function _cell_rule_kernel!(@Const(events), @Const(daughter), kindf, divide!, st, p, ctx, key, mcs)
    c = @index(Global, Linear)
    e = @inbounds events[c]
    if e == EVENT_TRANSITION
        @inbounds st.cell.kind[c] = kindf(st, p, ctx, key, mcs, Int32(c))
    elseif e == EVENT_DIVIDE && @inbounds(daughter[c]) > 0
        divide!(st, p, ctx, key, mcs, Int32(c), @inbounds daughter[c])
    end
end

# ---------------------------------------------------------------------------------------
# Host orchestration

"""Lifecycle scratch: device buffers sized by capacity, plus host mirrors."""
struct LifecycleCache{E, C, D, R, NM, B}
    events::E
    count::C
    daughter::D
    removed::R
    normals::NM
    bias::B
end

function LifecycleCache(backend, N::Int, capacity::Int)
    T = backend isa KernelAbstractions.CPU ? Float64 : Float32
    return LifecycleCache(KernelAbstractions.zeros(backend, Int32, capacity),
        KernelAbstractions.zeros(backend, Int32, 1),
        KernelAbstractions.zeros(backend, Int32, capacity),
        KernelAbstractions.zeros(backend, Bool, capacity),
        KernelAbstractions.zeros(backend, T, N, capacity),
        KernelAbstractions.zeros(backend, T, capacity))
end

Base.@kwdef mutable struct LifecycleStats
    divisions::Int = 0
    removals::Int = 0
    transitions::Int = 0
    deferred::Int = 0
    empty_daughters::Int = 0
end

"""
Run the lifecycle for MCS `mcs`. Returns the number of kernel launches. Synchronizes once
(reads the event count); quiet MCS return after the trigger kernel.
"""
function run_lifecycle!(lc::Lifecycle, cache::LifecycleCache, st, p, ctx, key, mcs, backend,
        stats::LifecycleStats)
    mcs % lc.every == 0 || return 0
    cap = length(st.cell.kind)
    fill!(cache.count, Int32(0))
    _trigger_kernel!(backend)(cache.events, cache.count, lc.trigger, st, p, ctx, key, mcs;
        ndrange = cap, workgroupsize = _phase_groupsize(backend, cap))
    launches = 1
    KernelAbstractions.synchronize(backend)
    Array(cache.count)[1] == 0 && return launches

    # plan (host): daughter ids lowest-first among free ids; defer when capacity is exhausted
    events = Array(cache.events)
    volume = Array(st.cell.volume)
    free = [c for c in 1:cap if volume[c] == 0 && events[c] == EVENT_NONE]
    daughter = zeros(Int32, cap)
    removed = zeros(Bool, cap)          # not a BitVector: copies to device arrays
    nextfree = 1
    clusters = lc.clusters && _has_clusters(st)
    if clusters
        cl = Array(st.cell.cluster)
        members = Dict{Int32, Vector{Int32}}()
        for c in 1:cap
            volume[c] > 0 && push!(get!(members, cl[c], Int32[]), Int32(c))
        end
        roots = Int32[]
        for c in 1:cap                                  # members' own divide events are ignored
            events[c] == EVENT_DIVIDE && cl[c] != c && (events[c] = EVENT_NONE)
        end
    end
    for c in 1:cap
        if clusters && events[c] == EVENT_DIVIDE
            cl[c] == c || continue                          # members follow their root
            ms = filter(m -> events[m] != EVENT_REMOVE, members[Int32(c)])
            if nextfree + length(ms) - 1 <= length(free)
                for m in ms
                    events[m] = EVENT_DIVIDE
                    daughter[m] = free[nextfree]
                    nextfree += 1
                end
                push!(roots, Int32(c))
                stats.divisions += length(ms)
            else
                stats.deferred += 1
            end
        elseif events[c] == EVENT_DIVIDE
            if nextfree <= length(free)
                daughter[c] = free[nextfree]
                nextfree += 1
                stats.divisions += 1
            else
                stats.deferred += 1
            end
        elseif events[c] == EVENT_REMOVE
            removed[c] = true
            stats.removals += 1
        elseif events[c] == EVENT_TRANSITION
            stats.transitions += 1
        end
    end
    copyto!(cache.daughter, daughter)
    copyto!(cache.removed, removed)
    clusters && copyto!(cache.events, events)

    if clusters
        isempty(roots) || _cluster_planes!(cache.normals, cache.bias, lc, st, p, ctx, key, mcs, roots, members)
    elseif any(>(0), daughter)
        _normal_kernel!(backend)(cache.normals, cache.daughter, lc.normal, st, p, ctx, key, mcs;
            ndrange = cap, workgroupsize = _phase_groupsize(backend, cap))
        launches += 1
    end
    n = length(st.σ)
    _partition_kernel!(backend)(st.σ, cache.daughter, cache.normals, cache.bias, cache.removed, st.cell,
        ctx.lattice; ndrange = n, workgroupsize = _phase_groupsize(backend, n))
    launches += 1

    # daughters: copy every non-tracker cell quantity from the parent, same kind, new generation
    parents = findall(>(0), daughter)
    if !isempty(parents)
        ds = daughter[parents]
        # `map` over (name, array) unrolls statically: no runtime dispatch per quantity
        map(keys(st.cell), values(st.cell)) do name, a
            (name in (:volume, :surface, :anchor, :m1, :m2, :generation) || _is_link_data(name)) ||
                _copy_columns!(a, ds, parents)          # daughters start unlinked
            nothing
        end
        gen = Array(st.cell.generation)
        gen[ds] .+= Int32(1)
        copyto!(st.cell.generation, gen)
        if clusters                                      # daughters form the root's daughter cluster
            clh = Array(st.cell.cluster)
            for m in parents
                clh[daughter[m]] = daughter[clh[m]]
            end
            copyto!(st.cell.cluster, clh)
        end
    end
    haskey(st.cell, :links) && (any(removed) || !isempty(parents)) &&
        _lifecycle_links!(st, findall(removed), daughter[parents])
    _cell_rule_kernel!(backend)(cache.events, cache.daughter, lc.kind, lc.divide!, st, p, ctx,
        key, mcs; ndrange = cap, workgroupsize = _phase_groupsize(backend, cap))
    launches += 1

    _has_clusters(st) && _fix_clusters!(st)
    rebuild_trackers!(st, ctx, backend)
    if !isempty(parents)
        v = Array(st.cell.volume)
        stats.empty_daughters += count(d -> v[d] == 0, daughter[parents])
    end
    return launches
end

function _copy_columns!(a::AbstractVector, dst, src)
    h = Array(a)
    h[dst] .= h[src]
    copyto!(a, h)
end
function _copy_columns!(a::AbstractArray, dst, src)
    h = Array(a)
    sel(x) = ntuple(d -> d == ndims(h) ? x : Colon(), ndims(h))
    h[sel(dst)...] .= h[sel(src)...]
    copyto!(a, h)
end

"""
    rebuild_trackers!(st, ctx, backend)

Recompute the built-in trackers present in `st.cell` exactly from `σ`: `volume`, `surface`
(over `ctx.surface`, if both exist), moments (`anchor`, `m1`, `m2`) and the cluster
trackers (`cluster_volume`, `cluster_surface`). Host-side; used at
lifecycle events and after host edits of `σ`.
"""
function rebuild_trackers!(st, ctx, backend)
    KernelAbstractions.synchronize(backend)
    σ = Array(st.σ)
    lat = ctx.lattice
    cap = length(st.cell.kind)
    volume = zeros(Int32, cap)
    for s in σ
        s > 0 && (volume[s] += Int32(1))
    end
    copyto!(st.cell.volume, volume)
    if haskey(st.cell, :surface) && haskey(ctx, :surface)
        copyto!(st.cell.surface, recompute_surface(σ, lat, ctx.surface, cap;
            T = eltype(st.cell.surface)))
    end
    if haskey(st.cell, :m1)
        m = init_moments(σ, lat, cap)
        copyto!(st.cell.anchor, m.anchor); copyto!(st.cell.m1, m.m1); copyto!(st.cell.m2, m.m2)
    end
    _has_clusters(st) && _rebuild_cluster_trackers!(st, σ, ctx)
    return st
end

"""
    with_capacity(st, capacity)

A copy of host state `st` whose cell quantities have `capacity` slots (free slots have
volume 0, kind 1, generation 0). Lifecycle models preallocate capacity (F11).
"""
function with_capacity(st::CPMState, capacity::Integer)
    n = length(st.cell.kind)
    capacity >= n || throw(ArgumentError("capacity $capacity < $n existing cells"))
    grow(a::AbstractVector) = (b = similar(a, capacity); fill!(b, zero(eltype(a))); b[1:n] .= a; b)
    function grow(a::AbstractArray)
        b = similar(a, (size(a)[1:(end - 1)]..., capacity)); fill!(b, zero(eltype(a)))
        b[ntuple(_ -> Colon(), ndims(a) - 1)..., 1:n] .= a; b
    end
    cell = map(grow, st.cell)
    cell.kind[(n + 1):end] .= Int32(1)
    haskey(cell, :cluster) && (cell.cluster[(n + 1):end] .= Int32.((n + 1):capacity))
    return CPMState(st.σ, cell, st.site, st.model, st.history)
end

_is_link_data(name::Symbol) = name === :links || startswith(String(name), "link_")

# RemoveIncident for removed cells; empty link rows for daughters (their ids may be reused).
function _lifecycle_links!(st, removed, daughters)
    names = Tuple(k for k in keys(st.cell) if _is_link_data(k))
    host = NamedTuple{names}(map(k -> Array(getfield(st.cell, k)), names))
    for c in Iterators.flatten((removed, daughters))
        remove_incident!(host, c)
    end
    foreach(k -> copyto!(getfield(st.cell, k), getfield(host, k)), names)
    return nothing
end
