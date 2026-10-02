# Cell lifecycle: division, removal, kind transition, creation and id reuse
# (ROADMAP M2.8, INTERNALS §1.7 as amended by D-035 and D-089).
#
# Two planners with the same semantics:
# - On the CPU (the host path, D-035): per checked MCS one trigger kernel over cells writes
#   an event code per cell and counts events; quiet MCS end there. Otherwise the host plans
#   (allocates daughter ids lowest-first among free ids, defers on exhausted capacity), then
#   kernels partition sites by plane, remove cells, set kinds and apply the daughter state
#   rule, and the trackers are rebuilt exactly.
# - On a device (`lifecycle_device.jl`, D-089): the same plan and updates run as device
#   kernels every checked MCS, with no host decision and no read-back; the statistics are
#   folded into `integ.stats` at host read points.
#
# Cell ids are `1:capacity`; an id is free when its volume is zero. Reusing an id increments
# its generation, so cell-addressed randomness never replays (F2).

const EVENT_NONE = Int32(0)
const EVENT_DIVIDE = Int32(1)
const EVENT_REMOVE = Int32(2)
const EVENT_TRANSITION = Int32(3)
const EVENT_DIVIDE_CLUSTER = Int32(4)
# internal: a cluster member that transitions and divides with its cluster in the same MCS
const _EVENT_DIVIDE_CLUSTER_TRANSITION = Int32(5)

@inline _divides_with_cluster(e) = e == EVENT_DIVIDE_CLUSTER || e == _EVENT_DIVIDE_CLUSTER_TRANSITION

# Rule-carrying events (`Lifecycle(…; rules = true)`): the trigger returns
# `ruled_event(event, i)`, the event in the low byte and the index `i ≥ 1` of the rule that
# fired above it, so the daughter state rule of that rule alone runs.
const _RULE_SHIFT = 8
const _EVENT_MASK = Int32(0xff)
"""`ruled_event(event, i)`: `event` fired by rule `i` (for a `Lifecycle(…; rules = true)` trigger).
Return `EVENT_NONE` itself, not `ruled_event(EVENT_NONE, i)`, when no rule fires: a nonzero
value counts as an event and forces a host plan."""
@inline ruled_event(event, i) = Int32(event) | (Int32(i) << _RULE_SHIFT)
public ruled_event
@inline _event(::Val{false}, raw) = raw
@inline _event(::Val{true}, raw) = raw & _EVENT_MASK
@inline _rule(raw) = raw >> _RULE_SHIFT
# the daughter state rule: with rule-carrying events it also gets the index of the rule
@inline _divide_rule!(::Val{false}, f::F, st, p, ctx, key, mcs, parent, daughter, raw) where {F} =
    f(st, p, ctx, key, mcs, parent, daughter)
@inline _divide_rule!(::Val{true}, f::F, st, p, ctx, key, mcs, parent, daughter, raw) where {F} =
    f(st, p, ctx, key, mcs, parent, daughter, _rule(raw))

"""
    Lifecycle(trigger; normal, kind, divide!, rebuild!, every = 1, rules = false,
              cluster_normal = normal, cluster_divide! = divide!, before = nothing)

The lifecycle of a model (generated from `@divide`, `@remove`, `@transition` rules, or
hand-written):

- `trigger(st, p, ctx, key, mcs, c) -> Int32` — the event for live cell `c`: `EVENT_NONE`,
  `EVENT_DIVIDE` (the cell divides alone), `EVENT_DIVIDE_CLUSTER` (its compartment cluster
  divides as a unit), `EVENT_REMOVE` or `EVENT_TRANSITION` (priorities are resolved inside).
- `normal(st, p, ctx, key, mcs, c) -> NTuple{N}` — division plane normal through the
  centroid (`along_minor_axis`, `along_major_axis`, `random_plane`, or any vector).
- `kind(st, p, ctx, key, mcs, c) -> Int32` — the destination kind of a transition.
- `divide!(st, p, ctx, key, mcs, parent, daughter)` — daughter state rule, run after the
  default `Copy` of every non-tracker cell quantity (e.g. halve extensive quantities).
- `rebuild!(st, p, ctx, backend)` — host hook run after the built-in trackers are rebuilt
  (a lifecycle event moves sites between cells). Model-specific trackers that the lifecycle
  cannot know, e.g. `commit_site_sum!`/`commit_site_min!` arrays, **must** be recomputed
  here (`recompute_site_sum`, `recompute_site_min!(…; all = true)`), or they go stale.
  A host hook needs a host decision: on a device, a lifecycle with `rebuild!` (or a model
  with a custom `remake_frozen` rule) is planned on the host as on the CPU, with one
  synchronizing read-back per checked MCS; every other lifecycle runs entirely on
  the device.
- `every` — check triggers every `every` MCS.
- `rules` — rule-carrying events. With `rules = true` the trigger returns
  `ruled_event(event, i)`, naming the rule `i ≥ 1` that fired, and `divide!`/`cluster_divide!`
  take an eighth argument, that index (a cluster member gets its root's), so only the firing
  rule's daughter state rule runs. Needed only when two rules can fire for one cell.
- `cluster_normal`, `cluster_divide!` — `normal` and `divide!` for cluster divisions.
- `before(st, p, ctx, key, mcs, c)` — a cell update run for every cell `c` in
  `1:ncells(st)` at the start of the lifecycle of every MCS (also the MCS it does not check),
  as a `CellPhase` run just before it would. It must write only cell `c`'s own columns, and
  the trigger of cell `c` may read a column `before` writes only at index `c` (other values
  only if `before` does not write them). Then the device lifecycle runs `before` and the
  trigger of each cell in one work item, one launch for both; the host
  planner runs `before` as its own launch.

Both kinds of division can happen in one MCS:

- `EVENT_DIVIDE_CLUSTER` divides a compartment cluster as a unit (`st.cell.cluster`).
  Only the root's event counts (members' `EVENT_DIVIDE_CLUSTER` are ignored).
  `cluster_normal` is evaluated with the cluster's moments (`st.cell` then holds the
  cluster's volume and moments at the root's index), and every live member splits along that plane
  through the cluster centroid; `cluster_divide!` runs for each member. A portable
  `cluster_normal` reads `st.cell.volume`, `anchor`, `m1`, `m2` only at the root's index,
  any other cell column only as `generation`, `kind` or `cluster`, and not `st.σ`: the host
  planner passes a cluster-labelled `σ` and cluster moments at every root, the device planner
  the cell-labelled `σ`, the full cell columns, and the cluster's volume and moments
  at every index. The daughters form
  a new cluster. A dividing cluster takes precedence over its members' own `EVENT_DIVIDE`.
- `EVENT_DIVIDE` divides the cell alone along `normal`; `divide!` runs. A compartment's
  daughter (the parent shares its cluster with another live cell) stays in the parent's
  cluster; a lone cell's daughter is a lone cell (its own cluster).

Division requires the moment trackers (`init_moments`).
"""
struct Lifecycle{TR, NO, CN, KI, DV, CD, RB, RU <: Val, BE}
    trigger::TR
    normal::NO
    cluster_normal::CN
    kind::KI
    divide!::DV
    cluster_divide!::CD
    rebuild!::RB
    every::Int
    rules::RU                   # Val(true): rule-carrying events
    before::BE                  # a cell update fused with the trigger, or `nothing`
end
Lifecycle(trigger; normal = AlongMinorAxis{Float64}(), kind = keep_kind, divide! = no_divide_rule,
    rebuild! = no_rebuild, every::Integer = 1, cluster_normal = normal, cluster_divide! = divide!,
    rules::Bool = false, before = nothing) =
    Lifecycle(trigger, normal, cluster_normal, kind, divide!, cluster_divide!, rebuild!, Int(every), Val(rules), before)

# `before` as its own launch (the host planner; MCS the lifecycle does not check)
_run_before(::Nothing, st, p, ctx, key, mcs, backend) = 0
_run_before(f::F, st, p, ctx, key, mcs, backend) where {F} = CellPhase(f)(st, p, ctx, key, mcs, backend)

no_rebuild(st, p, ctx, backend) = nothing

@inline keep_kind(st, p, ctx, key, mcs, c) = @inbounds st.cell.kind[c]
@inline no_divide_rule(st, p, ctx, key, mcs, parent, daughter) = nothing
@inline no_divide_rule(st, p, ctx, key, mcs, parent, daughter, rule) = nothing

const STREAM_DIVISION_PLANE = stream_id("CorePotts.division_plane")

"""
    AlongMinorAxis{T}(), AlongMajorAxis{T}(), RandomPlane{T}()

Division plane normals, computed in float type `T` (on a device, in the device's float type,
`Float32`; a hand-written normal or state rule runs on the device and must be device code):
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
# 1D: the axis itself (a division cuts the cell across its length, A-16)
@inline principal_axis(::Type{T}, cell, l::Lattice{1}, c, k) where {T} = (one(T),)
@inline function principal_axis(::Type{T}, cell, l::Lattice{2}, c, k) where {T}
    C = embed_covariance(l, covariance(T, cell, c, Val(2)))     # Cartesian axes
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

# `count[slot]` counts this round's events; item 1 zeroes the other slot, the next round's (its
# value was read after the previous round), so no separate reset command is enqueued (T3)
@inline function _trigger_body!(c, events, count, slot, trigger, st, p, ctx, key, mcs)
    c == 1 && (@inbounds count[3 - slot] = Int32(0))     # count has 2 entries, slot ∈ (1, 2)
    e = EVENT_NONE
    if @inbounds(st.cell.volume[c]) > 0
        e = trigger(st, p, ctx, key, mcs, c % Int32) % Int32
    end
    @inbounds events[c] = e
    e != EVENT_NONE && @inbounds Atomix.@atomic count[slot] += Int32(1)     # slot ∈ (1, 2) = axes(count)
end

@inline function _normal_body!(c, normals, events, daughter, normal, st, p, ctx, key, mcs, ruled)
    if _event(ruled, @inbounds(events[c])) == EVENT_DIVIDE && @inbounds(daughter[c]) > 0    # cell divisions only
        n = normal(st, p, ctx, key, mcs, Int32(c))
        for d in 1:length(n)
            @inbounds normals[d, c] = n[d]
        end
    end
end

@inline function _partition_body!(i, σ, daughter, normals, bias, removed, cell, lat)
    c = @inbounds σ[i]
    if c > 0
        if @inbounds(removed[c])
            @inbounds σ[i] = Int32(0)
        elseif @inbounds(daughter[c]) > 0
            N = ndims(lat)
            δ = min_image(lat, coordinates(lat, i), anchor(cell, c, Val(N)))
            T = eltype(normals)
            V = T(@inbounds cell.volume[c])
            side = @inbounds bias[c]                     # 0 unless it divides with its cluster
            offset = embed(lat, ntuple(d -> T(δ[d]) - T(@inbounds cell.m1[d, c]) / V, Val(N)))   # site − centroid
            for d in 1:N
                side += T(offset[d]) * @inbounds(normals[d, c])
            end
            side > 0 && (@inbounds σ[i] = daughter[c])
        end
    end
end

@inline function _cell_rule_body!(c, events, daughter, kindf, divide!, cluster_divide!, st, p, ctx, key, mcs, ruled)
    raw = @inbounds events[c]
    e = _event(ruled, raw)
    if e == EVENT_TRANSITION
        @inbounds st.cell.kind[c] = kindf(st, p, ctx, key, mcs, Int32(c))
    elseif e == EVENT_DIVIDE && @inbounds(daughter[c]) > 0
        _divide_rule!(ruled, divide!, st, p, ctx, key, mcs, Int32(c), @inbounds(daughter[c]), raw)
    elseif _divides_with_cluster(e) && @inbounds(daughter[c]) > 0
        d = @inbounds daughter[c]
        _divide_rule!(ruled, cluster_divide!, st, p, ctx, key, mcs, Int32(c), d, raw)
        if e == _EVENT_DIVIDE_CLUSTER_TRANSITION         # both halves take the new kind
            k = kindf(st, p, ctx, key, mcs, Int32(c))
            @inbounds st.cell.kind[c] = k
            @inbounds st.cell.kind[d] = k
        end
    end
end

# ---------------------------------------------------------------------------------------
# Host orchestration

"""Lifecycle scratch: device buffers sized by capacity, plus host mirrors; `device` is the
device planner's state (`DeviceLifecycle`), or `nothing` for the host path."""
struct LifecycleCache{E, C, D, R, NM, B, DL}
    events::E
    count::C            # the event counts of alternate rounds (host path; `_trigger_body!`)
    host::Vector{Int32} # host copy of this round's count: one transfer per lifecycle MCS (host path)
    round::Base.RefValue{Int}   # host-path rounds run (selects the slot of `count`)
    daughter::D
    removed::R
    normals::NM
    bias::B
    device::DL
end

function LifecycleCache(backend, N::Int, capacity::Int, st = nothing, device::Bool = false)
    T = backend isa KernelAbstractions.CPU ? Float64 : Float32
    return LifecycleCache(KernelAbstractions.zeros(backend, Int32, capacity),
        KernelAbstractions.zeros(backend, Int32, 2), zeros(Int32, 1), Ref(0),
        KernelAbstractions.zeros(backend, Int32, capacity),
        KernelAbstractions.zeros(backend, Bool, capacity),
        KernelAbstractions.zeros(backend, T, N, capacity),
        KernelAbstractions.zeros(backend, T, capacity),
        device ? DeviceLifecycle(backend, N, capacity, st) : nothing)
end

Base.@kwdef mutable struct LifecycleStats
    divisions::Int = 0
    removals::Int = 0
    transitions::Int = 0
    deferred::Int = 0
    empty_daughters::Int = 0
end

"""A division with no free cell slot waits for one; the first per run warns (silently fewer
divisions otherwise skew any proliferation result)."""
function _defer!(stats, cap)
    stats.deferred == 0 && @warn "lifecycle: all $cap cell slots are in use; divisions are deferred until slots free up. Pass a larger `capacity`."
    stats.deferred += 1
    return nothing
end

"""
Run the lifecycle for MCS `mcs` with the host planner (the CPU path; on a device only for
host hooks, see `Lifecycle`). Returns `(launches, events)`: the number of kernel launches,
and whether any cell had an event (then kinds, owners and cell ids may have changed, and
the integrator refreshes the frozen mask). Synchronizes once and reads back the 4-byte event
count (counted on a device). Quiet MCS return after the trigger kernel.
`pstats` is the integrator's `PottsStats` (lifecycle counts, host transfers). `before = false`:
`lc.before` has already run this MCS (a device form that failed after launching it).
"""
function run_lifecycle!(lc::Lifecycle, cache::LifecycleCache, st, p, ctx, key, mcs, backend, pstats,
        before::Bool = true)
    nb = before ? _run_before(lc.before, st, p, ctx, key, mcs, backend) : 0
    mcs % lc.every == 0 || return nb, false
    stats = pstats.lifecycle
    cap = length(st.cell.kind)
    slot = Int32((cache.round[] += 1) % 2 + 1)
    _launch(_trigger_body!, backend, cap, (cache.events, cache.count, slot, lc.trigger, st, p, ctx, key, mcs))
    launches = 1 + nb
    _sync!(pstats, backend)
    _copy!(pstats, cache.host, 1, cache.count, slot, 1)
    cache.host[1] == 0 && return launches, false

    # plan (host): daughter ids lowest-first among free ids; defer when capacity is exhausted
    events = _to_host(pstats, cache.events)
    # rule-carrying events: split off the firing rules (`rule[c]`), re-attached for the device
    rule = lc.rules === Val(true) ? (r = events .>> _RULE_SHIFT; events .&= _EVENT_MASK; r) : nothing
    volume = _to_host(pstats, st.cell.volume)
    # a dead root still names its cluster while members live: never reuse its id
    held = _has_clusters(st) ? _referenced_clusters(_to_host(pstats, st.cell.cluster), volume) : Set{Int32}()
    free = [c for c in 1:cap if volume[c] == 0 && events[c] == EVENT_NONE && !(Int32(c) in held)]
    daughter = zeros(Int32, cap)
    removed = zeros(Bool, cap)          # not a BitVector: copies to device arrays
    nextfree = 1
    has_clusters = _has_clusters(st)
    roots = Int32[]
    if has_clusters
        cl = _to_host(pstats, st.cell.cluster)
        members = Dict{Int32, Vector{Int32}}()
        for c in 1:cap
            volume[c] > 0 && push!(get!(members, cl[c], Int32[]), Int32(c))
        end
        # pass 1: clusters divide as a unit, in root order; members follow their root and a
        # dividing cluster takes precedence over its members' own events except removal
        for c in 1:cap                                  # only the root's event counts
            events[c] == EVENT_DIVIDE_CLUSTER && cl[c] != c && (events[c] = EVENT_NONE)
        end
        for c in 1:cap
            events[c] == EVENT_DIVIDE_CLUSTER && cl[c] == c || continue
            ms = filter(m -> events[m] != EVENT_REMOVE, members[Int32(c)])
            if nextfree + length(ms) - 1 <= length(free)
                for m in ms
                    events[m] = events[m] == EVENT_TRANSITION ? _EVENT_DIVIDE_CLUSTER_TRANSITION :
                                EVENT_DIVIDE_CLUSTER
                    rule === nothing || (rule[m] = rule[c])      # members follow the root's rule
                    daughter[m] = free[nextfree]
                    nextfree += 1
                end
                push!(roots, Int32(c))
                stats.divisions += length(ms)
            else
                events[c] = EVENT_NONE
                _defer!(stats, cap)
            end
        end
    elseif any(==(EVENT_DIVIDE_CLUSTER), events)
        throw(ArgumentError("lifecycle: EVENT_DIVIDE_CLUSTER needs cluster state (`init_clusters`)"))
    end
    # pass 2: cells dividing alone, removals
    for c in 1:cap
        if events[c] == EVENT_DIVIDE && daughter[c] == 0
            if nextfree <= length(free)
                daughter[c] = free[nextfree]
                nextfree += 1
                stats.divisions += 1
            else
                _defer!(stats, cap)
            end
        elseif events[c] == EVENT_REMOVE
            removed[c] = true
            stats.removals += 1
        end
    end
    stats.transitions += count(e -> e == EVENT_TRANSITION || e == _EVENT_DIVIDE_CLUSTER_TRANSITION, events)
    _copy!(pstats, cache.daughter, daughter)
    _copy!(pstats, cache.removed, removed)
    _copy!(pstats, cache.events, rule === nothing ? events : events .| (rule .<< _RULE_SHIFT))

    if isempty(roots)
        fill!(cache.bias, zero(eltype(cache.bias)))
    else
        _cluster_planes!(pstats, cache.normals, cache.bias, lc, st, p, ctx, key, mcs, roots, members)
    end
    if any(c -> daughter[c] > 0 && events[c] == EVENT_DIVIDE, 1:cap)    # after the host planes
        _launch(_normal_body!, backend, cap, (cache.normals, cache.events, cache.daughter, lc.normal, st, p,
            ctx, key, mcs, lc.rules))
        launches += 1
    end
    n = length(st.σ)
    _launch(_partition_body!, backend, n, (st.σ, cache.daughter, cache.normals, cache.bias, cache.removed,
        st.cell, ctx.lattice))
    launches += 1

    # daughters: copy every non-tracker cell quantity from the parent, same kind, new generation
    parents = findall(>(0), daughter)
    if !isempty(parents)
        ds = daughter[parents]
        # `map` over (name, array) unrolls statically: no runtime dispatch per quantity
        map(keys(st.cell), values(st.cell)) do name, a
            (name in (:volume, :surface, :anchor, :m1, :m2, :generation) || _is_link_data(name)) ||
                _copy_columns!(pstats, a, ds, parents)          # daughters start unlinked
            nothing
        end
        gen = _to_host(pstats, st.cell.generation)
        gen[ds] .+= Int32(1)
        _copy!(pstats, st.cell.generation, gen)
        if has_clusters
            clh = _to_host(pstats, st.cell.cluster)
            for m in parents
                d = daughter[m]
                if _divides_with_cluster(events[m])      # the root's daughter names the new cluster
                    clh[d] = daughter[cl[m]]
                elseif length(members[cl[m]]) == 1       # a lone cell's daughter is lone
                    clh[d] = d
                end                                      # else it stays in the parent's cluster
            end
            _copy!(pstats, st.cell.cluster, clh)
        end
    end
    any(_is_adjacency, keys(st.cell)) && (any(removed) || !isempty(parents)) &&
        _lifecycle_links!(pstats, st, findall(removed), daughter[parents])
    _launch(_cell_rule_body!, backend, cap, (cache.events, cache.daughter, lc.kind, lc.divide!,
        lc.cluster_divide!, st, p, ctx, key, mcs, lc.rules))
    launches += 1

    _has_clusters(st) && _fix_clusters!(pstats, st)
    _rebuild_trackers!(pstats, st, ctx, backend)
    lc.rebuild!(st, p, ctx, backend)
    if !isempty(parents)
        v = _to_host(pstats, st.cell.volume)
        stats.empty_daughters += count(d -> v[d] == 0, daughter[parents])
    end
    return launches, true
end

function _copy_columns!(stats, a::AbstractVector, dst, src)
    h = _to_host(stats, a)
    h[dst] .= h[src]
    _copy!(stats, a, h)
end
function _copy_columns!(stats, a::AbstractArray, dst, src)
    h = _to_host(stats, a)
    sel(x) = ntuple(d -> d == ndims(h) ? x : Colon(), ndims(h))
    h[sel(dst)...] .= h[sel(src)...]
    _copy!(stats, a, h)
end

"""
    rebuild_trackers!(st, ctx, backend)

Recompute the built-in trackers present in `st.cell` exactly from `σ`: `volume`, `surface`
(over `ctx.surface`, if both exist), moments (`anchor`, `m1`, `m2`) and the cluster
trackers (`cluster_volume`, `cluster_surface`). Host-side; used at
lifecycle events and after host edits of `σ`.
"""
rebuild_trackers!(st, ctx, backend) = _rebuild_trackers!(nothing, st, ctx, backend)

# `stats`: the integrator's `PottsStats` counting the host transfers (D-085), or `nothing`
function _rebuild_trackers!(stats, st, ctx, backend)
    _sync!(stats, backend)
    σ = _to_host(stats, st.σ)
    lat = _host_lattice(stats, ctx.lattice)
    ctx = merge(ctx, (; lattice = lat))
    cap = length(st.cell.kind)
    volume = zeros(Int32, cap)
    for s in σ
        s > 0 && (volume[s] += Int32(1))
    end
    _copy!(stats, st.cell.volume, volume)
    if haskey(st.cell, :surface) && haskey(ctx, :surface)
        _copy!(stats, st.cell.surface, _recompute_surface(eltype(st.cell.surface), σ, lat, ctx.surface, cap))
    end
    if haskey(st.cell, :m1)
        m = init_moments(σ, lat, cap)
        _copy!(stats, st.cell.anchor, m.anchor); _copy!(stats, st.cell.m1, m.m1); _copy!(stats, st.cell.m2, m.m2)
    end
    _has_clusters(st) && _rebuild_cluster_trackers!(stats, st, σ, ctx)
    return st
end

"""
    with_capacity(st, capacity)

A copy of host state `st` whose cell quantities have `capacity` slots (free slots have
volume 0, kind 1, generation 0). History rings are not resized: build rings of cell
quantities after `with_capacity` (a `HistoryPush` with a mismatched ring is an error). Lifecycle models preallocate capacity.
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

_is_link_data(name::Symbol) = _is_adjacency(name) || startswith(String(name), "link_")

# RemoveIncident for removed cells; empty link rows for daughters (their ids may be reused),
# in every relationship's adjacency. Payloads are left: `add_link!` rewrites a slot's.
function _lifecycle_links!(stats, st, removed, daughters)
    # `map` over (name, array) unrolls statically: each adjacency has its concrete type
    map(keys(st.cell), values(st.cell)) do name, dev
        _is_adjacency(name) || return nothing
        host = (; links = _to_host(stats, dev))
        for c in Iterators.flatten((removed, daughters))
            remove_incident!(host, c)
        end
        _copy!(stats, dev, host.links)
        return nothing
    end
    return nothing
end
