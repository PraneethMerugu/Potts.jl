# Site conversion passes (R8, `@convert`; D-233) and the shared ownership-delta routine.
#
# A conversion pass moves sites from one cell of an entity (`from`) to another (`to`) at the
# MCS boundary, outside the copy sweep. Every candidate decides independently on the state at
# the start of the pass, with a counter-addressed draw, so the result depends neither on the
# thread count nor on the order of the work items. One implementation runs on the CPU (the
# kernels as plain loops, `_launch`) and on a device (KernelAbstractions kernels, enqueued
# without a host round trip):
#
#   reset      (cells)  the pass scratch and its flags
#   entities   (cells)  each entity's `from` and `to` (alive referents, else 0); `from`'s
#                       entity; the slots that name a live cell's cluster (never reused)
#   decide     (sites)  a site of an entity's `from` converts iff the model's `decide` holds
#                       (the condition `at` and `u < clamp(p, 0, 1)`); per-entity counts and
#                       the lowest converted site by atomics
#   allocate   (one item, only when an entity with conversions has no `to`): every reference
#                       to a dead cell reset first (D-066 item 5 (b), `release`), then each such
#                       entity, in slot order, takes the lowest free slot (as division
#                       daughters do, D-089): kind, generation + 1, the next `birth` serial,
#                       the entity's cluster, unlinked, its cell variables at their defaults
#   transfer   (cells)  once per entity with its conversion count (`transfer`)
#   writes     (sites)  the per-conversion compound writes (atomic adds)
#   paint      (sites)  the ownership-delta routine at every converted site (volume and moment
#                       deltas in integer scratch, surface bond deltas, the ownership hook),
#                       on the owners before the pass; then σ is written
#   finalize   (cells)  volumes and moments from the scratch, re-centred
#   recounts   contact counts, Euler columns and the cluster trackers (re-rooting), from σ,
#              as the device lifecycle rebuilds them; only after a pass that converted
#
# The scratch lives in the state (`convert_scratch`), so it follows the state to the device,
# through `with_capacity` and into checkpoints; its cell columns are never copied to a
# division daughter (`_is_scratch_column`).

const _SCRATCH_PREFIX = "#cv_"
"""
Whether cell column `name` is conversion scratch (`convert_scratch`): no daughter copies it.
"""
_is_scratch_column(name::Symbol) = startswith(String(name), _SCRATCH_PREFIX)

const _CV_FROM = Symbol("#cv_from")        # entity c's `from` (0: c is no entity this pass)
const _CV_TO = Symbol("#cv_to")            # entity c's `to` (0: none yet; the new slot once allocated)
const _CV_SRC = Symbol("#cv_src")          # the entity whose `from` is cell c (0: none)
const _CV_N = Symbol("#cv_n")              # conversions of entity c in this pass
const _CV_FIRST = Symbol("#cv_first")      # the lowest site entity c converts (its birthing conversion)
const _CV_NEW = Symbol("#cv_new")          # 1 when entity c's `to` was allocated in this pass
const _CV_HELD = Symbol("#cv_held")        # 1 when slot c names the cluster of a live cell
const _CV_DVOL = Symbol("#cv_dvol")        # volume change of cell c (paint → finalize)
const _CV_DM1 = Symbol("#cv_dm1")          # moment changes about cell c's anchor (N × capacity)
const _CV_DM2 = Symbol("#cv_dm2")          # (npairs(N) × capacity)
const _CV_OKC = Symbol("#cv_okc")          # cluster re-rooting scratch (`_dcluster_*_body!`)
const _CV_ROOTA = Symbol("#cv_rootA")
const _CV_ROOTB = Symbol("#cv_rootB")
const _CV_SITE = Symbol("#cv_site")        # the entity converting site i in this pass, or 0
"""
`st.model` key of the conversion flags (`Int32[4]`): sites converting in this pass, entities
asking for a slot in this pass, allocations deferred for want of a free slot (cumulative),
entities skipped because their cells are too large for the Int32 moment scratch
(cumulative). The cumulative counts are read once per solve (Potts' `report_run`).
"""
const CONVERT_FLAGS = Symbol("#cv_flag")
const _FLAG_CONVERTED = 1
const _FLAG_ALLOCATE = 2
const _FLAG_DEFERRED = 3
const _FLAG_LARGE = 4                     # entities skipped: too large for the Int32 moment scratch

"""
    convert_scratch(dims, ncell, N) -> (; cell, site, model)

The state slots a conversion pass needs (`ConvertPass`), as `name => array` pairs for the
cell, site and model state: cell columns for `ncell` slots (grown with the state by
`with_capacity`), one site array of size `dims`, the flags. Names start with `#cv_`.
"""
function convert_scratch(dims, ncell::Integer, N::Integer)
    z(T, d...) = zeros(T, d...)
    big(n) = fill(typemax(Int32), n)
    cell = Pair{Symbol, Any}[
        _CV_FROM => z(Int32, ncell), _CV_TO => z(Int32, ncell), _CV_SRC => z(Int32, ncell),
        _CV_N => z(Int32, ncell), _CV_FIRST => big(ncell), _CV_NEW => z(Int32, ncell), _CV_HELD => z(
            Int32, ncell),
        _CV_DVOL => z(Int32, ncell), _CV_DM1 => z(Int32, N, ncell), _CV_DM2 => z(Int32, npairs(N), ncell),
        _CV_OKC => z(Bool, ncell), _CV_ROOTA => big(ncell), _CV_ROOTB => big(ncell)]
    return (; cell, site = Pair{Symbol, Any}[_CV_SITE => z(Int32, dims...)],
        model = Pair{Symbol, Any}[CONVERT_FLAGS => z(Int32, 4)])
end

"""
    ConvertPass(entity, decide; init!, transfer!, writes!, owner_changed, release, fresh)

One site conversion pass (R8 `@convert`, D-233), a phase of the MCS order
(`phase(st, p, ctx, key, mcs, backend)`), generated by Potts from a `@convert` block:

  - `entity(st, p, ctx, key, mcs, c) -> (is_entity::Bool, from, to)` — whether live cell `c`
    is an entity of the pass, and its `from` and `to` cells (references; a dead referent or 0
    reads as none);
  - `decide(st, p, ctx, key, mcs, i, from, to) -> Bool` — whether site `i`, owned by `from`,
    converts (evaluated on the state at the start of the pass);
  - `init!(st, p, ctx, key, mcs, d, k)` — the cell variables of a slot `d` the pass allocates
    for kind `k` (their declared defaults);
  - `transfer!(st, p, ctx, key, mcs, r, from, to, n)` — once per entity `r` with `n`
    conversions, or `nothing`;
  - `writes!(st, p, ctx, key, mcs, i, from, to, created)` — once per converted site, or
    `nothing`; `created` is true for exactly one conversion of an entity whose `to` this pass
    allocated (the lowest such site);
  - `owner_changed(st, i)` — the ownership hook at every converted site (`Lifecycle`), or
    `nothing`; `release(st, c)` — the reference reset (`Lifecycle`), or `nothing`;
  - `fresh` — the kind of the cell allocated for an entity with conversions and no live `to`
    (0: such an entity converts nothing);
  - `links` — the names of the adjacency columns of the model's relationships (cell
    columns, `adjacency_name`; a slot the pass allocates starts unlinked);
  - `limit` — the bound of the Int32 moment scratch (as the device lifecycle's): an entity
    whose `from` (or `from` relative to `to`) has larger second moments converts nothing
    and is counted.

The pass needs the scratch of `convert_scratch` in the state and the moment trackers. It
makes no host round trip on a device.
"""
struct ConvertPass{EN, DE, IN, TR, WR, OC, RL, LK <: Tuple}
    entity::EN
    decide::DE
    init!::IN
    transfer!::TR
    writes!::WR
    owner_changed::OC
    release::RL
    fresh::Int32
    links::LK
    limit::Int64
end
function ConvertPass(entity, decide; init!, transfer! = nothing, writes! = nothing,
        owner_changed = nothing, release = nothing,
        fresh::Integer = 0, links::Tuple = (), limit::Integer = _SCRATCH_LIMIT[])
    ConvertPass(entity, decide, init!, transfer!, writes!,
        owner_changed, release, Int32(fresh), map(n -> Part((:cell, n)), links), Int64(limit))
end

# the pass scratch of a state (`convert_scratch`)
@inline function _cv(st)
    c = st.cell
    return (; from = getfield(c, _CV_FROM), to = getfield(c, _CV_TO),
        src = getfield(c, _CV_SRC), n = getfield(c, _CV_N),
        first = getfield(c, _CV_FIRST), new = getfield(c, _CV_NEW), held = getfield(c, _CV_HELD),
        dvol = getfield(c, _CV_DVOL), dm1 = getfield(c, _CV_DM1), dm2 = getfield(c, _CV_DM2),
        okc = getfield(c, _CV_OKC), rootA = getfield(c, _CV_ROOTA), rootB = getfield(c, _CV_ROOTB),
        site = getfield(st.site, _CV_SITE), flag = getfield(st.model, CONVERT_FLAGS))
end

# ---------------------------------------------------------------------------------------
# The shared ownership-delta routine (R8): one site of a round of simultaneous ownership
# changes, applied with atomics so that the round's sites run in parallel. `σ` holds the
# owners before the round (written after it), `after(j)` the owner of site `j` after it. The
# volume and moment changes accumulate in integer scratch (`sc.dvol`, `sc.dm1`, `sc.dm2`:
# exact in any order, about each cell's anchor; the anchor of a cell that is empty before the
# round must be set first), applied by `_ownership_finalize!`; the surface changes are added
# to `surf` bond by bond (each bond's change of a cell counted once: a changing site counts
# its own side, an unchanged neighbour's side is counted by the changing site).

@inline function _moment_delta!(sc, cell, lat, x, c, s::Int32)
    N = ndims(lat)
    δ = min_image(lat, x, anchor(cell, c, Val(N)))
    Atomix.@atomic sc.dvol[c] += s
    for k in 1:N
        # `% Int32`: offsets about a cell's anchor are small (the cell spans less than half of
        # a periodic axis, the moment tracker's own validity condition), and the sums wrap
        Atomix.@atomic sc.dm1[k, c] += s * (δ[k] % Int32)
        for l in k:N
            Atomix.@atomic sc.dm2[_pair(N, k, l), c] += s * ((δ[k] * δ[l]) % Int32)
        end
    end
    return nothing
end

@inline _surface_delta!(
    ::Nothing, rel, lat, σ, i, x, old, new, after::A) where {A} = nothing
@inline function _surface_delta!(surf, rel, lat, σ, i, x, old, new, after::A) where {A}
    T = eltype(surf)
    for k in 1:length(rel)
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        j = linear_index(lat, y)
        a = @inbounds σ[j]                  # the neighbour's owner before the round
        b = after(j)                        # and after
        w = T(weight(rel, k))
        # site i's side of the bond
        (old > 0 && old != a) && Atomix.@atomic surf[old] -= w
        (new > 0 && new != b) && Atomix.@atomic surf[new] += w
        # the neighbour's side, when the neighbour keeps its owner
        if a == b && a > 0
            a != old && Atomix.@atomic surf[a] -= w
            a != new && Atomix.@atomic surf[a] += w
        end
    end
    return nothing
end

"""
    _ownership_delta!(cell, sc, surf, rel, lat, σ, i, old, new, after)

Site `i` changes owner from `old` to `new` (0 is the medium) in a round of simultaneous
changes: the shared ownership-delta routine (R8). See above.
"""
@inline function _ownership_delta!(
        cell, sc, surf, rel, lat, σ, i, old, new, after::A) where {A}
    x = coordinates(lat, i)
    old > 0 && _moment_delta!(sc, cell, lat, x, old, Int32(-1))
    new > 0 && _moment_delta!(sc, cell, lat, x, new, Int32(1))
    _surface_delta!(surf, rel, lat, σ, i, x, old, new, after)
    return nothing
end

# cell c: the round's volume and moment changes applied, the scratch cleared, re-centred
# (bounds: c ∈ 1:capacity, every column's length; k ≤ N and q ≤ npairs(N), the row counts
# of `dm1`/`m1` and `dm2`/`m2`)
@inline function _ownership_finalize!(c, cell, sc, lat)
    N = ndims(lat)
    dv = @inbounds sc.dvol[c]
    any_m = dv != 0
    for k in 1:N
        any_m |= @inbounds(sc.dm1[k, c]) != 0
    end
    for q in 1:npairs(N)
        any_m |= @inbounds(sc.dm2[q, c]) != 0
    end
    any_m || return nothing                 # an untouched cell
    V = @inbounds(cell.volume[c]) + dv
    @inbounds cell.volume[c] = V
    @inbounds sc.dvol[c] = Int32(0)
    for k in 1:N
        @inbounds cell.m1[k, c] += eltype(cell.m1)(sc.dm1[k, c])
        @inbounds sc.dm1[k, c] = Int32(0)
    end
    for q in 1:npairs(N)
        @inbounds cell.m2[q, c] += eltype(cell.m2)(sc.dm2[q, c])
        @inbounds sc.dm2[q, c] = Int32(0)
    end
    _recenter!(cell, lat, c, V)
    return nothing
end

# ---------------------------------------------------------------------------------------
# Kernels of the pass (c ∈ 1:capacity, i ∈ 1:nsites: the launch ranges; every scratch
# column has the capacity's length and the site array the lattice's)

@inline function _cv_reset_body!(c, sc)
    if c == 1
        @inbounds sc.flag[_FLAG_CONVERTED] = Int32(0)
        @inbounds sc.flag[_FLAG_ALLOCATE] = Int32(0)
    end
    @inbounds begin
        sc.from[c] = Int32(0)
        sc.to[c] = Int32(0)
        sc.src[c] = Int32(0)
        sc.n[c] = Int32(0)
        sc.first[c] = typemax(Int32)
        sc.new[c] = Int32(0)
        sc.held[c] = Int32(0)
        sc.rootA[c] = typemax(Int32)
        sc.rootB[c] = typemax(Int32)
    end
    return nothing
end

@inline function _cv_entity_body!(
        c, entity::E, st, p, ctx, key, mcs, sc, limit, ::Val{CL}) where {E, CL}
    vol = st.cell.volume
    @inbounds(vol[c]) > 0 || return nothing
    # a live cell's cluster id is not a free slot, even when that slot's cell is dead
    CL && (@inbounds sc.held[st.cell.cluster[c]] = Int32(1))
    ok, f, t = entity(st, p, ctx, key, mcs, c % Int32)
    ok || return nothing
    _live_slot(vol, f) || return nothing
    t = _live_slot(vol, t) ? Int32(t) : Int32(0)
    t == f && return nothing
    if !_cv_moments_ok(st.cell, ctx.lattice, f, t, limit, Val(ndims(ctx.lattice)))
        Atomix.@atomic sc.flag[_FLAG_LARGE] += Int32(1)
        return nothing
    end
    @inbounds sc.from[c] = Int32(f)
    @inbounds sc.to[c] = t
    Atomix.@atomic sc.src[f] max (c % Int32)     # one entity per `from` (the highest)
    return nothing
end
# The moment scratch of a pass stays in Int32: about `from`'s anchor the converted sites' δ²
# sum to at most `m2[from]`; about `to`'s, |δ_to|² ≤ 2(|δ_from|² + |a_from − a_to|²), so with
# both terms ≤ limit/4 the sums of `to` stay ≤ limit (a fresh `to` takes `from`'s anchor).
# Bounds: f, t ∈ 1:capacity (live slots or 0), k ≤ N rows of m2.
@inline function _cv_moments_ok(cell, lat, f, t, limit, ::Val{N}) where {N}
    q = limit ÷ 4
    ok = true
    for k in 1:N
        ok &= Int64(@inbounds(cell.m2[_pair(N, k, k), f])) <= q
    end
    if t > 0
        d = min_image(lat, anchor(cell, f, Val(N)), anchor(cell, t, Val(N)))
        v = Int64(@inbounds cell.volume[f])
        for k in 1:N
            ok &= v * Int64(d[k])^2 <= q
        end
    end
    return ok
end
@inline _live_slot(vol, r) = (0 < r) & (r <= length(vol)) && @inbounds(vol[r] > 0)

@inline function _cv_decide_body!(i, decide::D, st, p, ctx, key, mcs, sc, fresh) where {D}
    @inbounds sc.site[i] = Int32(0)
    in_domain(ctx.lattice, i) || return nothing
    c = @inbounds st.σ[i]
    c > 0 || return nothing
    r = @inbounds sc.src[c]
    r > 0 || return nothing
    t = @inbounds sc.to[r]
    (t > 0 || fresh > 0) || return nothing
    decide(st, p, ctx, key, mcs, i, c, t) || return nothing
    @inbounds sc.site[i] = r
    Atomix.@atomic sc.n[r] += Int32(1)
    Atomix.@atomic sc.first[r] min (i % Int32)
    Atomix.@atomic sc.flag[_FLAG_CONVERTED] += Int32(1)
    t == 0 && Atomix.@atomic sc.flag[_FLAG_ALLOCATE] += Int32(1)
    return nothing
end

# one item: the reference reset, then the slots, lowest first, in entity (slot) order
@inline function _cv_allocate_body!(_, ph::P, st, p, ctx, key, mcs, sc, links::LI,
        surf, births, ::Val{CL}) where {P, LI, CL}
    @inbounds(sc.flag[_FLAG_ALLOCATE]) == 0 && return nothing
    cell = st.cell
    cap = length(cell.kind)
    _release_all!(ph.release, st, cap)
    cursor = 1
    for r in 1:cap
        (@inbounds(sc.n[r]) > 0 && @inbounds(sc.to[r]) == 0) || continue
        while cursor <= cap &&
              (@inbounds(cell.volume[cursor]) > 0 || @inbounds(sc.held[cursor]) != 0)
            cursor += 1
        end
        if cursor > cap                      # no free slot: the entity converts nothing this pass
            @inbounds sc.n[r] = Int32(0)
            Atomix.@atomic sc.flag[_FLAG_DEFERRED] += Int32(1)
            continue
        end
        d = cursor % Int32
        cursor += 1
        _fresh_slot!(cell, d, ph.fresh, r, @inbounds(sc.from[r]),
            links, surf, births, ctx.lattice, Val(CL))
        ph.init!(st, p, ctx, key, mcs, d, ph.fresh)
        @inbounds sc.to[r] = d
        @inbounds sc.new[r] = Int32(1)
    end
    return nothing
end
@inline _release_all!(::Nothing, st, cap) = nothing
@inline function _release_all!(f::F, st, cap) where {F}
    for c in 1:cap
        f(st, c % Int32)
    end
    return nothing
end

# A new cell in free slot `d` (as a division daughter, D-066 item 3): kind `k`, a new
# generation, the next serial, the cluster of entity `r`, no links (its partners drop it), no
# surface; anchored at its source `f`'s anchor (its first sites are `f`'s, D-066 X2)
@inline function _fresh_slot!(
        cell, d, k, r, f, links::LI, surf, births, lat, ::Val{CL}) where {LI, CL}
    N = ndims(lat)
    @inbounds cell.kind[d] = k
    @inbounds cell.generation[d] += one(eltype(cell.generation))
    if births !== nothing
        @inbounds births.col[d] = births.next[1]
        @inbounds births.next[1] += Int32(1)
    end
    CL && (@inbounds cell.cluster[d] = cell.cluster[r])
    for q in 1:N
        @inbounds cell.anchor[q, d] = cell.anchor[q, f]
    end
    surf === nothing || (@inbounds surf[d] = zero(eltype(surf)))
    map(L -> _unlink_slot!(L, d), links)
    return nothing
end
@inline function _unlink_slot!(L, d)
    for c in 1:size(L, 2), k in 1:size(L, 1)

        @inbounds L[k, c] == d && (@inbounds L[k, c] = zero(eltype(L)))
    end
    for k in 1:size(L, 1)
        @inbounds L[k, d] = zero(eltype(L))
    end
    return nothing
end

@inline function _cv_transfer_body!(c, transfer!::F, st, p, ctx, key, mcs, sc) where {F}
    n = @inbounds sc.n[c]
    n > 0 || return nothing
    t = @inbounds sc.to[c]
    t > 0 || return nothing
    transfer!(st, p, ctx, key, mcs, c % Int32, @inbounds(sc.from[c]), t, n)
    return nothing
end

@inline function _cv_writes_body!(i, writes!::F, st, p, ctx, key, mcs, sc) where {F}
    r = @inbounds sc.site[i]
    r > 0 || return nothing
    t = @inbounds sc.to[r]
    t > 0 || return nothing
    created = @inbounds(sc.new[r]) != 0 && @inbounds(sc.first[r]) == i % Int32
    writes!(st, p, ctx, key, mcs, i, @inbounds(sc.from[r]), t, created)
    return nothing
end

# the owner of site j after the pass (`_ownership_delta!`'s `after`)
struct _ConvertAfter{S, A, B}
    σ::S
    site::A
    to::B
end
@inline function (a::_ConvertAfter)(j)
    r = @inbounds a.site[j]
    r > 0 || return @inbounds a.σ[j]
    t = @inbounds a.to[r]
    return t > 0 ? t : @inbounds(a.σ[j])
end

@inline function _cv_paint_body!(i, st, ctx, sc, surf, rel, hook::H) where {H}
    @inbounds(sc.flag[_FLAG_CONVERTED]) == 0 && return nothing
    r = @inbounds sc.site[i]
    r > 0 || return nothing
    t = @inbounds sc.to[r]
    t > 0 || return nothing
    _ownership_delta!(st.cell, sc, surf, rel, ctx.lattice, st.σ, i, @inbounds(st.σ[i]), t,
        _ConvertAfter(st.σ, sc.site, sc.to))
    _owner_changed!(hook, st, i)
    return nothing
end

@inline function _cv_write_sigma_body!(i, σ, sc)
    @inbounds(sc.flag[_FLAG_CONVERTED]) == 0 && return nothing
    r = @inbounds sc.site[i]
    r > 0 || return nothing
    t = @inbounds sc.to[r]
    t > 0 && (@inbounds σ[i] = t)
    return nothing
end

@inline function _cv_finalize_body!(c, cell, sc, lat)
    @inbounds(sc.flag[_FLAG_CONVERTED]) == 0 && return nothing
    _ownership_finalize!(c, cell, sc, lat)
    return nothing
end

# CPU: the flags are host memory, so a quiet pass skips its later stages without a
# transfer; a device enqueues them (their work items return at once)
_quiet(backend, flag, j) = false
_quiet(::KernelAbstractions.CPU, flag, j) = @inbounds(flag[j]) == 0

function (ph::ConvertPass)(st, p, ctx, key, mcs, backend)
    sc = _cv(st)
    cap = length(st.cell.kind)
    n = length(st.σ)
    lat = ctx.lattice
    CL = Val(_has_clusters(st))
    _launch(_cv_reset_body!, backend, cap, (sc,))
    _launch(_cv_entity_body!, backend, cap, (ph.entity, st, p, ctx, key, mcs, sc, ph.limit, CL))
    _launch(_cv_decide_body!, backend, n, (ph.decide, st, p, ctx, key, mcs, sc, ph.fresh))
    launches = 3
    _quiet(backend, sc.flag, _FLAG_CONVERTED) && return launches
    surf = haskey(st.cell, :surface) && haskey(ctx, :surface) ? st.cell.surface : nothing
    rel = haskey(ctx, :surface) ? ctx.surface : nothing
    links = map(L -> L(st), ph.links)
    if ph.fresh > 0
        _launch(_cv_allocate_body!, backend, 1, (
            ph, st, p, ctx, key, mcs, sc, links, surf, _births(st), CL))
        launches += 1
    end
    if ph.transfer! !== nothing
        _launch(_cv_transfer_body!, backend, cap, (ph.transfer!, st, p, ctx, key, mcs, sc))
        launches += 1
    end
    if ph.writes! !== nothing
        _launch(_cv_writes_body!, backend, n, (ph.writes!, st, p, ctx, key, mcs, sc))
        launches += 1
    end
    _launch(_cv_paint_body!, backend, n, (st, ctx, sc, surf, rel, ph.owner_changed))
    _launch(_cv_write_sigma_body!, backend, n, (st.σ, sc))
    _launch(_cv_finalize_body!, backend, cap, (st.cell, sc, lat))
    launches += 3
    # the trackers rebuilt from σ, as the device lifecycle rebuilds them (`lifecycle_device.jl`)
    dv = (; flag = sc.flag, okc = sc.okc, rootA = sc.rootA, rootB = sc.rootB)
    par = Int32(_FLAG_CONVERTED)
    cc = _contact_counts(ctx)
    if cc !== nothing
        cols = _count_columns(st, cc)
        _launch(_dcount_zero_body!, backend, cap, (dv, par, cols))
        _launch(_dcount_body!, backend, n, (dv, par, st.σ, st.cell.kind, cc, cols, lat))
        launches += 2
    end
    eul = _euler_columns(st.cell)
    if eul !== nothing
        _launch(_deuler_zero_body!, backend, cap, (dv, par, eul))
        _launch(_deuler_body!, backend, _euler_anchors(lat), (dv, par, st.σ, eul, lat))
        launches += 2
    end
    if _has_clusters(st)
        cvol = haskey(st.cell, :cluster_volume) ? st.cell.cluster_volume : nothing
        csurf = haskey(st.cell, :cluster_surface) && haskey(ctx, :surface) ?
                st.cell.cluster_surface : nothing
        _launch(_dcluster_mark_body!, backend, cap, (dv, par, st.cell))
        _launch(_dcluster_root_body!, backend, cap, (dv, par, st.cell, cvol, csurf))
        launches += 2
        if cvol !== nothing
            _launch(_dcluster_volume_body!, backend, cap, (dv, par, st.cell, cvol))
            launches += 1
        end
        if csurf !== nothing
            _launch(_dcluster_surface_body!, backend, n, (
                dv, par, st.σ, st.cell, csurf, ctx.surface, lat))
            launches += 1
        end
    end
    return launches
end
