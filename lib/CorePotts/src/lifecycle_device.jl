# The lifecycle on a device (D-089, D-096): every lifecycle MCS enqueues a fixed sequence of
# kernels, with no host decision and no read-back. A quiet MCS costs the trigger kernel and
# launches whose work items return at once (they read the round's event flag on the device).
#
#   trigger    (cells)   events; the round's event flag; cluster ids that hold a dead root
#   plan       (one workgroup of PLAN_WG items) the D-035 host plan, on the device: daughter
#              ids lowest-first among free ids (prefix scans, no atomics-order dependence),
#              capacity deferral, cluster units and their planes, cell division normals
#   partition  (sites)   removed cells' sites → medium; each dividing cell's sites on the
#              positive side of its plane → the daughter; the daughter's volume and moment
#              sums accumulate in integer scratch (exact, order-independent)
#   copies     (cells)   daughter column copies, generation, cluster ids, links (removed
#              cells' links dropped, daughters unlinked), for every cell before any rule runs
#   rules      (cells)   the daughter state rules and transitions (they see the trackers as
#              the CPU path's rules do: not yet updated)
#   surface    (sites)   the surface change of each parent and daughter (only the moved sites)
#   finalize   (cells)   volume and moments of parents and daughters, removed cells' trackers
#   clusters   re-root clusters whose root died; cluster volume (cells) and surface (sites)
#   mask       (sites + one item) the P6.0d frozen-mask refresh and its counts, when the mask
#              follows the state
#
# Lifecycle statistics and the mask counts accumulate on the device and are folded into
# `integ.stats` only at host read points (saves, `integ.u`, `checkpoint`, the end of
# `solve!`), which synchronize anyway (`_fold_lifecycle!`).

# Items of the planner's (and the fused form's) single workgroup. Fewer cost time on a
# quiet MCS (each item runs the trigger of capacity/PLAN_WG slots; 128 measured about 1.2×
# slower on Akeeb Metal, `benchmark/ab.jl`). A kernel's pipeline may allow fewer threads
# per group (Metal: register-bound, 384 measured for Akeeb's fused kernel); that launch then
# fails on the host before anything is enqueued, and the next form takes over (`_FORM_*`,
# `run_lifecycle_device!`).
const PLAN_WG = 256

# The forms of the device lifecycle, tried in this order: one fused launch (small problems),
# one kernel per stage, the host planner (D-035; `_step_lifecycle!`)
const _FORM_FUSED = 1
const _FORM_STAGED = 2
const _FORM_HOST = 3
const _LAUNCH_FAULT = Ref(0)        # tests: the first launch of this form fails (not public API)

# device accumulators (`dv.acc`, cumulative Int32; the host folds the differences)
const _ACC_DIVISIONS = 1
const _ACC_REMOVALS = 2
const _ACC_TRANSITIONS = 3
const _ACC_DEFERRED = 4
const _ACC_EMPTY = 5
const _ACC_NOCLUSTER = 6            # EVENT_DIVIDE_CLUSTER without cluster state (an error)
const _ACC_LARGE = 7                # divisions deferred: the cell is too large for the Int32
                                    # moment scratch (`_scratch_ok`; also counted as deferred)
const _NACC = 7

# The bound of `_scratch_ok` (`typemax(Int32)`); a `Ref` read when the scratch is built, so
# that tests can lower it (not public API)
const _SCRATCH_LIMIT = Ref{Int64}(typemax(Int32))

# Cell columns that the lifecycle maintains itself (never copied from parent to daughter)
const _LIFECYCLE_OWNED = (:volume, :surface, :anchor, :m1, :m2, :generation, :cluster,
    :cluster_volume, :cluster_surface)

"""Device scratch of the lifecycle (sized by capacity) and the host buffers of its fold."""
function _device_scratch(backend, N::Int, cap::Int)
    z(T, dims...) = KernelAbstractions.zeros(backend, T, dims...)
    return (; flag = z(Int32, 2), held = z(Int32, cap), newborn = z(Int32, cap), req = z(Int32, cap),
        nmem = z(Int32, cap), nlive = z(Int32, cap), coff = z(Int32, cap), freelist = z(Int32, cap),
        dvol = z(Int32, cap), dm1 = z(Int32, N, cap), dm2 = z(Int32, npairs(N), cap),
        rootA = z(Int32, cap), rootB = z(Int32, cap), okc = z(Bool, cap), acc = z(Int32, _NACC),
        mcnt = z(Int32, 3), mask = z(Int64, 3), limit = _SCRATCH_LIMIT[])
end

"""Host side of the device lifecycle: the round counter, the kernel objects and the fold
buffers (`acc`/`mask` are read at host read points; `seen` are the values already folded)."""
struct DeviceLifecycle{DV, CO, LI, K, KF}
    dv::DV
    cols::CO            # the cell columns a daughter copies from its parent
    links::LI           # the adjacency matrices of the relationships
    plan!::K
    fused!::KF          # the whole lifecycle in one workgroup (small problems), or nothing
    form::Base.RefValue{Int}        # `_FORM_*`
    before_ran::Base.RefValue{Bool} # this MCS's `Lifecycle.before` was enqueued (with the trigger)
    proven::Base.RefValue{Bool}     # the form has launched once (its workgroup fits)
    round::Base.RefValue{Int}
    acc::Vector{Int32}
    acc_seen::Vector{Int32}
    mask::Vector{Int64}
    mask_seen::Vector{Int64}
end

# Up to these sizes the whole lifecycle runs as one launch of one workgroup (a quiet MCS
# then costs one launch, as the trigger alone did); larger problems launch one kernel per
# stage over all sites or cells. `Ref`s so that tests can exercise both forms.
const FUSE_SITES = Ref(1 << 16)
const FUSE_CELLS = Ref(1 << 13)

function DeviceLifecycle(backend, N::Int, cap::Int, st)
    names = keys(st.cell)
    cols = Tuple(getfield(st.cell, k) for k in names if !(k in _LIFECYCLE_OWNED) && !_is_link_data(k))
    links = Tuple(getfield(st.cell, k) for k in names if _is_adjacency(k))
    fused = length(st.σ) <= FUSE_SITES[] && cap <= FUSE_CELLS[] ? _fused_kernel!(backend, PLAN_WG) : nothing
    return DeviceLifecycle(_device_scratch(backend, N, cap), cols, links, _plan_kernel!(backend, PLAN_WG), fused,
        Ref(fused === nothing ? _FORM_STAGED : _FORM_FUSED), Ref(false), Ref(false), Ref(0), zeros(Int32, _NACC),
        zeros(Int32, _NACC), zeros(Int64, 3), zeros(Int64, 3))
end

# ---------------------------------------------------------------------------------------
# Trigger

# `before` (`Lifecycle.before`, or `nothing`) runs for cell `c` first, in the same work item:
# the trigger of `c` reads only `c`'s own values of what it writes (its contract), so no
# barrier is needed between them (F1, D-101)
@inline _before!(::Nothing, c, st, p, ctx, key, mcs) = nothing
@inline _before!(f::F, c, st, p, ctx, key, mcs) where {F} =
    (c <= ncells(st) && f(st, p, ctx, key, mcs, c % Int32); nothing)
@inline function _dtrigger_body!(c, events, dv, par, round, before::B, trigger::F, st, p, ctx, key, mcs,
        ::Val{CL}) where {B, F, CL}
    _before!(before, c, st, p, ctx, key, mcs)
    e = EVENT_NONE
    if @inbounds(st.cell.volume[c]) > 0
        e = trigger(st, p, ctx, key, mcs, c % Int32) % Int32
        # a dead root still names its cluster while members live: its id is held (not free)
        CL && (@inbounds dv.held[st.cell.cluster[c]] = round)
    end
    @inbounds events[c] = e
    e != EVENT_NONE && @inbounds Atomix.@atomic dv.flag[par] += Int32(1)    # par ∈ (1, 2) = axes(dv.flag)
    return nothing
end

@inline _on(dv, par) = @inbounds(dv.flag[par]) != Int32(0)

# ---------------------------------------------------------------------------------------
# Plan: one workgroup; item `t` owns the contiguous slots `_chunk(t, cap)`, so every scan is
# in slot order. Values that live across barriers are in workgroup memory (`cnt`, `tot`).

@inline function _chunk(t, cap)
    K = cld(cap, PLAN_WG)
    lo = (t - 1) * K + 1
    return lo, min(t * K, cap)
end

@inline _is_free(st, dv, round, e, c, ::Val{CL}) where {CL} =
    @inbounds(st.cell.volume[c]) == 0 && e == EVENT_NONE && (!CL || @inbounds(dv.held[c]) != round)

# exclusive prefix sum of `cnt[1:PLAN_WG, j]` in place; returns the total (one item runs it)
@inline function _scan!(cnt, j)
    s = Int32(0)
    for t in 1:PLAN_WG
        v = @inbounds cnt[t, j]
        @inbounds cnt[t, j] = s
        s += v
    end
    return s
end

# A: normalize events (only a cluster's root may divide it), reset the per-slot scratch,
# count free slots per item
@inline function _plan_a!(t, cnt, events, daughter, removed, bias, dv, par, round, ruled, st, cl::Val{CL}) where {CL}
    t == 1 && (@inbounds dv.flag[3 - par] = Int32(0))       # the next round's flag
    nfree = Int32(0)
    if _on(dv, par)
        lo, hi = _chunk(t, length(events))
        for c in lo:hi
            raw = @inbounds events[c]
            e = _event(ruled, raw)
            if e == EVENT_DIVIDE_CLUSTER && (!CL || @inbounds(st.cell.cluster[c]) != c)
                CL || Atomix.@atomic dv.acc[_ACC_NOCLUSTER] += Int32(1)
                e = EVENT_NONE
                @inbounds events[c] = EVENT_NONE
            end
            @inbounds removed[c] = e == EVENT_REMOVE
            @inbounds daughter[c] = Int32(0)
            @inbounds dv.newborn[c] = Int32(0)
            @inbounds dv.req[c] = Int32(0)
            @inbounds bias[c] = zero(eltype(bias))
            if CL
                @inbounds dv.nmem[c] = Int32(0)
                @inbounds dv.nlive[c] = Int32(0)
                @inbounds dv.rootA[c] = typemax(Int32)
                @inbounds dv.rootB[c] = typemax(Int32)
            end
            _is_free(st, dv, round, e, c, cl) && (nfree += Int32(1))
        end
    end
    @inbounds cnt[t, 1] = nfree
    return nothing
end

# B: live members per cluster, and the members (not being removed) of each dividing cluster
@inline function _plan_b!(t, events, dv, par, ruled, st, ::Val{CL}) where {CL}
    (CL && _on(dv, par)) || return nothing
    lo, hi = _chunk(t, length(events))
    for c in lo:hi
        @inbounds(st.cell.volume[c]) > 0 || continue
        r = @inbounds st.cell.cluster[c]
        Atomix.@atomic dv.nlive[r] += Int32(1)
        if _event(ruled, @inbounds events[r]) == EVENT_DIVIDE_CLUSTER &&
           _event(ruled, @inbounds events[c]) != EVENT_REMOVE
            Atomix.@atomic dv.nmem[r] += Int32(1)
        end
    end
    return nothing
end

# C: daughters requested by the dividing clusters rooted in each item's slots
@inline function _plan_c!(t, cnt, events, dv, par, ruled, ::Val{CL}) where {CL}
    dem = Int32(0)
    if CL && _on(dv, par)
        lo, hi = _chunk(t, length(events))
        for c in lo:hi
            _event(ruled, @inbounds events[c]) == EVENT_DIVIDE_CLUSTER && (dem += @inbounds dv.nmem[c])
        end
    end
    @inbounds cnt[t, 2] = dem
    return nothing
end

# D (one item): scans of the free slots and of the cluster demand. Clusters take daughters
# first, in root order; when they do not all fit, the D-035 greedy pass defers those that do
# not fit (a later, smaller cluster may still fit)
@inline function _plan_d!(t, cnt, tot, events, dv, par, ruled)
    (t == 1 && _on(dv, par)) || return nothing
    nfree = _scan!(cnt, 1)
    demand = _scan!(cnt, 2)
    @inbounds tot[1] = nfree
    if demand <= nfree
        @inbounds tot[2] = demand
        @inbounds tot[3] = Int32(0)
    else
        next = Int32(0)
        for r in 1:length(events)
            _event(ruled, @inbounds events[r]) == EVENT_DIVIDE_CLUSTER || continue
            n = @inbounds dv.nmem[r]
            if next + n <= nfree
                @inbounds dv.coff[r] = next
                next += n
            else
                @inbounds events[r] = EVENT_NONE
                Atomix.@atomic dv.acc[_ACC_DEFERRED] += Int32(1)
            end
        end
        @inbounds tot[2] = next
        @inbounds tot[3] = Int32(1)
    end
    @inbounds(tot[2]) > 0 && Atomix.@atomic dv.acc[_ACC_DIVISIONS] += tot[2]
    return nothing
end

# E: the free list in slot order; cluster offsets (no deferral); cells dividing alone
@inline function _plan_e!(t, cnt, tot, events, dv, par, round, ruled, st, cl::Val{CL}) where {CL}
    nreq = Int32(0)
    if _on(dv, par)
        lo, hi = _chunk(t, length(events))
        k = @inbounds cnt[t, 1]
        off = @inbounds cnt[t, 2]
        greedy = @inbounds(tot[3]) != 0
        for c in lo:hi
            e = _event(ruled, @inbounds events[c])
            if _is_free(st, dv, round, e, c, cl)
                k += Int32(1)
                @inbounds dv.freelist[k] = c % Int32
            end
            if CL && e == EVENT_DIVIDE_CLUSTER && !greedy
                @inbounds dv.coff[c] = off
                off += @inbounds dv.nmem[c]
            end
            if e == EVENT_DIVIDE
                # a member of a dividing cluster divides with it, not alone
                member = CL && _event(ruled, @inbounds events[st.cell.cluster[c]]) == EVENT_DIVIDE_CLUSTER
                if !member
                    @inbounds dv.req[c] = Int32(1)
                    nreq += Int32(1)
                end
            end
        end
    end
    @inbounds cnt[t, 3] = nreq
    return nothing
end

# F (one item): the cells dividing alone take the free slots left, in slot order
@inline function _plan_f!(t, cnt, tot, dv, par)
    (t == 1 && _on(dv, par)) || return nothing
    nreq = _scan!(cnt, 3)
    avail = @inbounds(tot[1]) - @inbounds(tot[2])
    ndiv = min(nreq, avail)
    ndiv > 0 && Atomix.@atomic dv.acc[_ACC_DIVISIONS] += ndiv
    nreq > ndiv && Atomix.@atomic dv.acc[_ACC_DEFERRED] += nreq - ndiv
    return nothing
end

# G: daughters and planes. A cell dividing alone takes its slot and its normal; the item of
# a dividing cluster's root assigns its members' daughters in slot order and evaluates the
# cluster plane on the cluster's moments
@inline function _plan_g!(t, cnt, tot, events, daughter, normals, bias, dv, par, normal::NF, cnormal::CF,
        ruled, st, p, ctx, key, mcs, ::Val{CL}) where {NF, CF, CL}
    _on(dv, par) || return nothing
    lo, hi = _chunk(t, length(events))
    rk = @inbounds(tot[2]) + @inbounds(cnt[t, 3])
    nfree = @inbounds tot[1]
    for c in lo:hi
        if @inbounds(dv.req[c]) == 1
            if rk < nfree
                if _scratch_ok(dv, st.cell, c, Val(ndims(ctx.lattice)))
                    @inbounds daughter[c] = dv.freelist[rk + 1]
                    n = normal(st, p, ctx, key, mcs, c % Int32)
                    for d in 1:length(n)
                        @inbounds normals[d, c] = n[d]
                    end
                else                            # deferred (its slot stays free this round)
                    _defer_large!(dv, Int32(1))
                end
            end
            rk += Int32(1)
        end
        # a root (its cluster id is itself) whose cluster divides: members are found by id
        if CL && @inbounds(st.cell.cluster[c]) == c && _event(ruled, @inbounds events[c]) == EVENT_DIVIDE_CLUSTER
            _plan_cluster!(c % Int32, events, daughter, normals, bias, dv, cnormal, ruled, st, p, ctx, key, mcs)
        end
    end
    return nothing
end

# A daughter's volume and moment sums about the parent's anchor accumulate in Int32 scratch
# (`_dpartition_body!`). With δ the integer offsets (site − parent anchor) of the daughter's
# sites, a subset of the parent's, and P_k = Σ_parent δ_k² (the parent's `m2[k, k]`, exact):
#   |Σ δ_k| ≤ Σ |δ_k| ≤ Σ δ_k² ≤ P_k                         (integers: |δ| ≤ δ²)
#   |Σ δ_k δ_l| ≤ Σ (δ_k² + δ_l²)/2 ≤ max(P_k, P_l)
#   0 ≤ Σ δ_k² ≤ P_k,   0 ≤ the daughter's volume ≤ the parent's (an Int32 site count)
# so every final sum fits in Int32 when every P_k ≤ `typemax(Int32)` (atomic adds wrap, so
# the order of the partial sums does not matter), and each site's own term
# |δ_k δ_l| ≤ max(P_k, P_l).
# A larger cell does not divide: its division is deferred and counted (`_ACC_LARGE`), the
# state stays exact, and the host warns at the next read point.
@inline function _scratch_ok(dv, cell, c, ::Val{N}) where {N}
    ok = true
    for k in 1:N
        ok &= @inbounds(cell.m2[_pair(N, k, k), c]) <= dv.limit
    end
    return ok
end

@inline function _defer_large!(dv, ndiv)
    Atomix.@atomic dv.acc[_ACC_DIVISIONS] -= ndiv
    Atomix.@atomic dv.acc[_ACC_DEFERRED] += Int32(1)
    Atomix.@atomic dv.acc[_ACC_LARGE] += Int32(1)
    return nothing
end

# Single-cell views of a cluster's moments for `cluster_normal` (index-free reads)
struct _OneValue{T}
    v::T
end
@inline Base.getindex(a::_OneValue, c) = a.v
struct _OneColumn{V}
    v::V
end
@inline Base.getindex(a::_OneColumn, d, c) = @inbounds a.v[d]

@inline function _plan_cluster!(r, events, daughter, normals, bias, dv, cnormal::CF, ruled, st, p, ctx, key,
        mcs) where {CF}
    cell = st.cell
    lat = ctx.lattice
    N = ndims(lat)
    T = eltype(normals)
    cap = length(events)
    raw_r = @inbounds events[r]
    # a member too large for the moment scratch defers the whole cluster's division
    ok = true
    for m in 1:cap
        (@inbounds(cell.volume[m]) > 0 && @inbounds(cell.cluster[m]) == r) || continue
        _event(ruled, @inbounds events[m]) == EVENT_REMOVE && continue
        ok &= _scratch_ok(dv, cell, m, Val(N))
    end
    if !ok
        _defer_large!(dv, @inbounds dv.nmem[r])
        return nothing
    end
    j = @inbounds dv.coff[r]
    ar = anchor(cell, r, Val(N))
    # cluster moments about the root's anchor, summed exactly over the live members
    VK = zero(eltype(cell.volume))
    m1K = ntuple(_ -> Int64(0), Val(N))
    m2K = ntuple(_ -> Int64(0), Val(npairs(N)))
    for m in 1:cap
        Vm = @inbounds cell.volume[m]
        (Vm > 0 && @inbounds(cell.cluster[m]) == r) || continue
        δa = min_image(lat, anchor(cell, m, Val(N)), ar)
        m1m = ntuple(d -> Int64(@inbounds cell.m1[d, m]), Val(N))
        inc2 = ntuple(Val(npairs(N))) do q
            d, e = _unpair(N, q)
            Int64(@inbounds cell.m2[q, m]) + δa[d] * m1m[e] + δa[e] * m1m[d] + Int64(Vm) * δa[d] * δa[e]
        end
        inc1 = ntuple(d -> m1m[d] + Int64(Vm) * δa[d], Val(N))
        VK += Vm
        m1K = map(+, m1K, inc1)
        m2K = map(+, m2K, inc2)
        em = _event(ruled, @inbounds events[m])
        em == EVENT_REMOVE && continue
        @inbounds daughter[m] = dv.freelist[j + 1]
        j += Int32(1)
        ev = em == EVENT_TRANSITION ? _EVENT_DIVIDE_CLUSTER_TRANSITION : EVENT_DIVIDE_CLUSTER
        @inbounds events[m] = _with_rule(ruled, ev, raw_r)            # members follow the root's rule
    end
    cellK = merge(cell, (; volume = _OneValue(VK), anchor = _OneColumn(ar), m1 = _OneColumn(m1K), m2 = _OneColumn(m2K)))
    n = cnormal((; σ = st.σ, cell = cellK), p, ctx, key, mcs, r)
    cK = centroid(T, cellK, lat, r)
    for m in 1:cap
        (@inbounds(cell.volume[m]) > 0 && @inbounds(cell.cluster[m]) == r) || continue
        cm = centroid(T, cell, lat, m)
        δ = _min_image(T, lat, ntuple(d -> cm[d] - cK[d], Val(N)))     # member − cluster centroid
        s = zero(T)
        for d in 1:N
            s += T(δ[d]) * T(n[d])
            @inbounds normals[d, m] = T(n[d])
        end
        @inbounds bias[m] = s
    end
    return nothing
end
@inline _with_rule(::Val{false}, ev, raw) = ev
@inline _with_rule(::Val{true}, ev, raw) = ev | ((raw >> _RULE_SHIFT) << _RULE_SHIFT)

# H: who is whose daughter; statistics; a daughter's surface starts from zero
@inline function _plan_h!(t, events, daughter, dv, par, ruled, surf)
    _on(dv, par) || return nothing
    lo, hi = _chunk(t, length(events))
    ntrans = Int32(0)
    nrem = Int32(0)
    for c in lo:hi
        d = @inbounds daughter[c]
        if d > 0
            @inbounds dv.newborn[d] = c % Int32
            surf === nothing || (@inbounds surf[d] = zero(eltype(surf)))
        end
        e = _event(ruled, @inbounds events[c])
        (e == EVENT_TRANSITION || e == _EVENT_DIVIDE_CLUSTER_TRANSITION) && (ntrans += Int32(1))
        e == EVENT_REMOVE && (nrem += Int32(1))
    end
    ntrans > 0 && Atomix.@atomic dv.acc[_ACC_TRANSITIONS] += ntrans
    nrem > 0 && Atomix.@atomic dv.acc[_ACC_REMOVALS] += nrem
    return nothing
end

# (KA's CPU backend splits the kernel at each `@synchronize` and needs `@index` as its own
# statement in each part)
@kernel function _plan_kernel!(events, daughter, removed, normals, bias, dv, par, round, normal, cnormal,
        ruled, st, p, ctx, key, mcs, clusters, surf)
    cnt = @localmem Int32 (PLAN_WG, 3)
    tot = @localmem Int32 (3,)
    ta = @index(Local, Linear)
    _plan_a!(ta, cnt, events, daughter, removed, bias, dv, par, round, ruled, st, clusters)
    @synchronize
    tb = @index(Local, Linear)
    _plan_b!(tb, events, dv, par, ruled, st, clusters)
    @synchronize
    tc = @index(Local, Linear)
    _plan_c!(tc, cnt, events, dv, par, ruled, clusters)
    @synchronize
    td = @index(Local, Linear)
    _plan_d!(td, cnt, tot, events, dv, par, ruled)
    @synchronize
    te = @index(Local, Linear)
    _plan_e!(te, cnt, tot, events, dv, par, round, ruled, st, clusters)
    @synchronize
    tf = @index(Local, Linear)
    _plan_f!(tf, cnt, tot, dv, par)
    @synchronize
    tg = @index(Local, Linear)
    _plan_g!(tg, cnt, tot, events, daughter, normals, bias, dv, par, normal, cnormal, ruled, st, p, ctx, key, mcs,
        clusters)
    @synchronize
    th = @index(Local, Linear)
    _plan_h!(th, events, daughter, dv, par, ruled, surf)
end

# ---------------------------------------------------------------------------------------
# Partition: removed cells' sites become medium; a dividing cell's sites on the positive
# side of its plane go to the daughter, whose volume and moment sums (about the parent's
# anchor) accumulate in integer scratch

@inline function _dpartition_body!(i, dv, par, σ, daughter, normals, bias, removed, cell, lat)
    _on(dv, par) || return nothing
    c = @inbounds σ[i]
    c > 0 || return nothing
    if @inbounds(removed[c])
        @inbounds σ[i] = Int32(0)
    elseif (d = @inbounds daughter[c]) > 0
        N = ndims(lat)
        δ = min_image(lat, coordinates(lat, i), anchor(cell, c, Val(N)))
        T = eltype(normals)
        V = T(@inbounds cell.volume[c])
        side = @inbounds bias[c]                     # 0 unless it divides with its cluster
        offset = embed(lat, ntuple(k -> T(δ[k]) - T(@inbounds cell.m1[k, c]) / V, Val(N)))   # site − centroid
        for k in 1:N
            side += T(offset[k]) * @inbounds(normals[k, c])
        end
        if side > 0
            @inbounds σ[i] = d
            Atomix.@atomic dv.dvol[d] += Int32(1)
            # `% Int32`: |δ_k|, |δ_k δ_l| ≤ the parent's m2[k, k] ≤ the scratch limit
            # (`_scratch_ok`), and the sums wrap (exact once complete)
            for k in 1:N
                Atomix.@atomic dv.dm1[k, d] += δ[k] % Int32
                for l in k:N
                    Atomix.@atomic dv.dm2[_pair(N, k, l), d] += (δ[k] * δ[l]) % Int32
                end
            end
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Cells: column copies, generation, cluster ids and links of every cell, then (after a
# barrier or a kernel boundary) the state rules, which may read or write any cell's columns
# or links (e.g. `add_link!(st.cell, parent, daughter)` in `divide!`)

@inline function _copy_column!(a::AbstractVector, c, d)
    @inbounds a[d] = a[c]
    return nothing
end
@inline function _copy_column!(a::AbstractArray, c, d)
    n = length(a) ÷ size(a, ndims(a))               # entries per cell
    for k in 1:n
        @inbounds a[(d - 1) * n + k] = a[(c - 1) * n + k]
    end
    return nothing
end

# links: a removed cell and a daughter (whose slot may be reused) lose every link; their
# partners drop them (each item writes only its own row: the store is symmetric)
@inline function _clean_links!(L, c, removed, newborn)
    clear = @inbounds(removed[c]) || @inbounds(newborn[c]) > 0
    for k in 1:size(L, 1)
        b = @inbounds L[k, c]
        b == 0 && continue
        (clear || @inbounds(removed[b]) || @inbounds(newborn[b]) > 0) && (@inbounds L[k, c] = zero(eltype(L)))
    end
    return nothing
end

@inline function _dcopies_body!(c, dv, par, events, daughter, removed, cols, links, st, ruled,
        ::Val{CL}) where {CL}
    _on(dv, par) || return nothing
    d = @inbounds daughter[c]
    if d > 0
        map(a -> _copy_column!(a, c, d), cols)
        @inbounds st.cell.generation[d] += one(eltype(st.cell.generation))
        if CL
            k = @inbounds st.cell.cluster[c]
            @inbounds st.cell.cluster[d] = _divides_with_cluster(_event(ruled, @inbounds events[c])) ?
                                           daughter[k] :              # the root's daughter names the new cluster
                                           dv.nlive[k] == 1 ? d : k   # a lone cell's daughter is lone
        end
    end
    map(L -> _clean_links!(L, c, removed, dv.newborn), links)
    return nothing
end

@inline function _drules_body!(c, dv, par, events, daughter, kindf::KF, divide!::DF, cluster_divide!::CF, st, p,
        ctx, key, mcs, ruled) where {KF, DF, CF}
    _on(dv, par) || return nothing
    _cell_rule_body!(c, events, daughter, kindf, divide!, cluster_divide!, st, p, ctx, key, mcs, ruled)
    return nothing
end

# ---------------------------------------------------------------------------------------
# Surface: only the parents and daughters change (a removed cell's neighbours still border
# another owner). For a site that moved from parent `pc` to daughter `s`: the daughter gains
# its bonds to non-daughter sites; the parent loses the site's old bonds to non-parent
# sites and gains the bonds of its remaining sites to the site (a symmetric relation)

@inline function _dsurface_body!(i, dv, par, σ, surf, rel, lat)
    _on(dv, par) || return nothing
    s = @inbounds σ[i]
    s > 0 || return nothing
    pc = @inbounds dv.newborn[s]
    pc > 0 || return nothing
    x = coordinates(lat, i)
    T = eltype(surf)
    sd = zero(T)
    sp = zero(T)
    for k in 1:length(rel)
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        n = @inbounds σ[linear_index(lat, y)]
        w = T(weight(rel, k))
        n != s && (sd += w)
        n == pc && (sp += w)
        (n != pc && n != s) && (sp -= w)
    end
    Atomix.@atomic surf[s] += sd
    Atomix.@atomic surf[pc] += sp
    return nothing
end

# ---------------------------------------------------------------------------------------
# Finalize: the trackers of parents, daughters and removed cells

@inline function _dfinalize_body!(c, dv, par, daughter, removed, cell, surf, lat)
    _on(dv, par) || return nothing
    N = ndims(lat)
    if @inbounds(removed[c])
        @inbounds cell.volume[c] = zero(eltype(cell.volume))
        for k in 1:N
            @inbounds cell.m1[k, c] = zero(eltype(cell.m1))
        end
        for q in 1:npairs(N)
            @inbounds cell.m2[q, c] = zero(eltype(cell.m2))
        end
        surf === nothing || (@inbounds surf[c] = zero(eltype(surf)))
    end
    d = @inbounds daughter[c]
    d > 0 || return nothing
    Vd = @inbounds dv.dvol[d]
    Vc = @inbounds(cell.volume[c]) - Vd
    @inbounds cell.volume[c] = Vc
    @inbounds cell.volume[d] = Vd
    for k in 1:N
        @inbounds cell.anchor[k, d] = cell.anchor[k, c]
        m = eltype(cell.m1)(@inbounds dv.dm1[k, d])
        @inbounds cell.m1[k, d] = m
        @inbounds cell.m1[k, c] -= m
        @inbounds dv.dm1[k, d] = Int32(0)
    end
    for q in 1:npairs(N)
        m = eltype(cell.m2)(@inbounds dv.dm2[q, d])
        @inbounds cell.m2[q, d] = m
        @inbounds cell.m2[q, c] -= m
        @inbounds dv.dm2[q, d] = Int32(0)
    end
    @inbounds dv.dvol[d] = Int32(0)
    _recenter!(cell, lat, c, Vc)
    _recenter!(cell, lat, d, Vd)
    Vd == 0 && Atomix.@atomic dv.acc[_ACC_EMPTY] += Int32(1)
    return nothing
end

# ---------------------------------------------------------------------------------------
# Clusters: re-root clusters whose root died (the lowest live member of the old root's kind,
# else the lowest live member; `_normalize_clusters!`), free slots are their own cluster;
# then the cluster trackers from scratch

@inline function _dcluster_mark_body!(c, dv, par, cell)
    _on(dv, par) || return nothing
    @inbounds(cell.volume[c]) > 0 || return nothing
    k = @inbounds cell.cluster[c]
    ok = @inbounds(cell.volume[k]) > 0 && @inbounds(cell.cluster[k]) == k
    @inbounds dv.okc[c] = ok
    if !ok
        @inbounds(cell.kind[c]) == @inbounds(cell.kind[k]) && Atomix.@atomic dv.rootA[k] min (c % Int32)
        Atomix.@atomic dv.rootB[k] min (c % Int32)
    end
    return nothing
end

@inline function _dcluster_root_body!(c, dv, par, cell, cvol, csurf)
    _on(dv, par) || return nothing
    if @inbounds(cell.volume[c]) == 0
        @inbounds cell.cluster[c] = c % Int32
    elseif !@inbounds(dv.okc[c])
        k = @inbounds cell.cluster[c]
        a = @inbounds dv.rootA[k]
        @inbounds cell.cluster[c] = a != typemax(Int32) ? a : dv.rootB[k]
    end
    cvol === nothing || (@inbounds cvol[c] = zero(eltype(cvol)))
    csurf === nothing || (@inbounds csurf[c] = zero(eltype(csurf)))
    return nothing
end

@inline function _dcluster_volume_body!(c, dv, par, cell, cvol)
    _on(dv, par) || return nothing
    V = @inbounds cell.volume[c]
    V > 0 || return nothing
    k = @inbounds cell.cluster[c]
    Atomix.@atomic cvol[k] += eltype(cvol)(V)
    return nothing
end

@inline function _dcluster_surface_body!(i, dv, par, σ, cell, csurf, rel, lat)
    _on(dv, par) || return nothing
    s = @inbounds σ[i]
    s > 0 || return nothing
    K = @inbounds cell.cluster[s]
    x = coordinates(lat, i)
    T = eltype(csurf)
    a = zero(T)
    for k in 1:length(rel)
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        cluster_of(cell, @inbounds σ[linear_index(lat, y)]) != K && (a += T(weight(rel, k)))
    end
    a != zero(T) && Atomix.@atomic csurf[K] += a
    return nothing
end

# ---------------------------------------------------------------------------------------
# The P6.0d mask on a device: refreshed on event rounds; the change of the mobile count is
# folded per round into `mask = [Σ d, Σ d·mcs, refreshes]` (Int64, one item), so the host
# corrects `stats.attempts` exactly at its next read point

@inline function _dfrozen_body!(i, dv, par, frozen, σ, kind, kinds, lat)
    _on(dv, par) || return nothing
    _frozen_body!(i, frozen, dv.mcnt, σ, kind, kinds, lat)
    return nothing
end

@inline function _dmask_fold_body!(_, dv, par, mcs)
    _on(dv, par) || return nothing
    d = Int64(@inbounds dv.mcnt[2])
    @inbounds dv.mask[1] += d
    @inbounds dv.mask[2] += d * Int64(mcs)
    @inbounds dv.mask[3] += Int64(1)
    @inbounds dv.mcnt[2] = Int32(0)
    @inbounds dv.mcnt[3] = Int32(0)
    return nothing
end

# ---------------------------------------------------------------------------------------
# Host orchestration (enqueue only)

# The built-in planes compute in the device's float type (the planner compiles every plane
# of the model, also those of rules that never fire: a `Float64` default must not reach Metal)
_plane(::AlongMinorAxis, ::Type{T}) where {T} = AlongMinorAxis{T}()
_plane(::AlongMajorAxis, ::Type{T}) where {T} = AlongMajorAxis{T}()
_plane(::RandomPlane, ::Type{T}) where {T} = RandomPlane{T}()
_plane(normal, ::Type) = normal

"""
Enqueue the lifecycle of MCS `mcs` on a device: no synchronization, no transfer.
`refresh` is `nothing` or `(frozen, kinds)` of a standard-rule frozen mask. Returns
the number of kernel launches, or -1 when no device form can launch (the host planner then
runs this MCS and every later one; `cache.device.before_ran[]` tells whether `lc.before`
already ran this MCS).
"""
function run_lifecycle_device!(lc::Lifecycle, cache, st, p, ctx, key, mcs, backend, refresh)
    D = cache.device
    D.before_ran[] = false
    if mcs % lc.every != 0
        n = _run_before(lc.before, st, p, ctx, key, mcs, backend)
        D.before_ran[] = true
        return n
    end
    r = (D.round[] += 1)
    par = Int32(isodd(r) ? 1 : 2)
    round = Int32(r % typemax(Int32))
    T = eltype(cache.normals)
    buf = (; cache.events, cache.daughter, cache.removed, cache.normals, cache.bias)
    fns = (; lc.before, lc.trigger, normal = _plane(lc.normal, T), cnormal = _plane(lc.cluster_normal, T), lc.kind, lc.divide!,
        lc.cluster_divide!)
    opt = (; surf = haskey(st.cell, :surface) && haskey(ctx, :surface) ? st.cell.surface : nothing,
        cvol = _has_clusters(st) && haskey(st.cell, :cluster_volume) ? st.cell.cluster_volume : nothing,
        csurf = _has_clusters(st) && haskey(st.cell, :cluster_surface) && haskey(ctx, :surface) ?
                st.cell.cluster_surface : nothing,
        rel = haskey(ctx, :surface) ? ctx.surface : nothing, refresh)
    CL = Val(_has_clusters(st))
    if D.form[] == _FORM_FUSED
        D.proven[] && return _run_fused!(D, buf, fns, opt, par, round, lc.rules, CL, st, p, ctx, key, mcs)
        n = try
            _LAUNCH_FAULT[] == _FORM_FUSED && throw(ArgumentError("launch refused (test)"))
            _run_fused!(D, buf, fns, opt, par, round, lc.rules, CL, st, p, ctx, key, mcs)
        catch e
            _form_failed!(D, e)
        end
        n > 0 && (D.proven[] = true; return n)
    end
    if D.form[] == _FORM_STAGED
        D.proven[] && return _run_staged!(D, buf, fns, opt, par, round, lc.rules, CL, st, p, ctx, key, mcs, backend)
        n = try
            _LAUNCH_FAULT[] == _FORM_STAGED && throw(ArgumentError("launch refused (test)"))
            _run_staged!(D, buf, fns, opt, par, round, lc.rules, CL, st, p, ctx, key, mcs, backend)
        catch e
            _form_failed!(D, e)
        end
        n > 0 && (D.proven[] = true; return n)
    end
    return -1
end

# The first launch of a form failed (e.g. its workgroup exceeds the kernel's limit): the
# next form takes over. The trigger may have run (staged form): the host planner, which
# reruns it, takes the MCS from scratch, and later device forms rerun it too
function _form_failed!(D, e)
    e isa InterruptException && throw(e)
    next = D.form[] == _FORM_FUSED ? "one kernel per stage" : "the host planner"
    @warn "device lifecycle: the $(D.form[] == _FORM_FUSED ? "fused" : "staged") form cannot launch " *
          "($(sprint(showerror, e))); using $next"
    D.form[] += 1
    D.proven[] = false
    return -1
end

function _run_fused!(D, buf, fns, opt, par, round, ruled, CL, st, p, ctx, key, mcs)
    D.fused!(buf, D.dv, D.cols, D.links, fns, opt, par, round, ruled, CL, st, p, ctx, key, mcs; ndrange = PLAN_WG)
    D.before_ran[] = true
    return 1
end

# one kernel per stage (large problems)
function _run_staged!(D, buf, fns, opt, par, round, ruled, CL, st, p, ctx, key, mcs, backend)
    dv = D.dv
    cap = length(st.cell.kind)
    n = length(st.σ)
    lat = ctx.lattice
    surf, cvol, csurf, refresh = opt.surf, opt.cvol, opt.csurf, opt.refresh
    _launch(_dtrigger_body!, backend, cap, (buf.events, dv, par, round, fns.before, fns.trigger, st, p, ctx, key, mcs, CL))
    D.before_ran[] = true
    D.plan!(buf.events, buf.daughter, buf.removed, buf.normals, buf.bias, dv, par, round, fns.normal, fns.cnormal,
        ruled, st, p, ctx, key, mcs, CL, surf; ndrange = PLAN_WG)
    _launch(_dpartition_body!, backend, n, (dv, par, st.σ, buf.daughter, buf.normals, buf.bias, buf.removed, st.cell, lat))
    _launch(_dcopies_body!, backend, cap, (dv, par, buf.events, buf.daughter, buf.removed, D.cols, D.links, st,
        ruled, CL))
    _launch(_drules_body!, backend, cap, (dv, par, buf.events, buf.daughter, fns.kind, fns.divide!,
        fns.cluster_divide!, st, p, ctx, key, mcs, ruled))
    launches = 5
    if surf !== nothing
        _launch(_dsurface_body!, backend, n, (dv, par, st.σ, surf, ctx.surface, lat))
        launches += 1
    end
    _launch(_dfinalize_body!, backend, cap, (dv, par, buf.daughter, buf.removed, st.cell, surf, lat))
    launches += 1
    if _has_clusters(st)
        _launch(_dcluster_mark_body!, backend, cap, (dv, par, st.cell))
        _launch(_dcluster_root_body!, backend, cap, (dv, par, st.cell, cvol, csurf))
        launches += 2
        if cvol !== nothing
            _launch(_dcluster_volume_body!, backend, cap, (dv, par, st.cell, cvol))
            launches += 1
        end
        if csurf !== nothing
            _launch(_dcluster_surface_body!, backend, n, (dv, par, st.σ, st.cell, csurf, ctx.surface, lat))
            launches += 1
        end
    end
    if refresh !== nothing
        _launch(_dfrozen_body!, backend, n, (dv, par, refresh.frozen, st.σ, st.cell.kind, refresh.kinds, lat))
        _launch(_dmask_fold_body!, backend, 1, (dv, par, mcs))
        launches += 2
    end
    return launches
end

# ---------------------------------------------------------------------------------------
# The fused form: every stage above as a section of one workgroup, the barriers between
# sections in place of the kernel boundaries (device memory is coherent within the
# workgroup across a barrier). Item `t` takes the slots or sites `t, t + PLAN_WG, …`.

@inline function _each!(body::B, t, n, args::A) where {B, A}
    i = Int(t)                          # a local index may be 32-bit on a device
    while i <= n
        body(i, args...)
        i += PLAN_WG
    end
    return nothing
end
# the stages after the trigger (`args` start with `dv, par`): a quiet round skips the loop
@inline _each_on!(body::B, t, n, args::A) where {B, A} =
    (_on(args[1], args[2]) && _each!(body, t, n, args); nothing)
@inline _each_if!(body::B, t, n, x::Nothing, args::A) where {B, A} = nothing
@inline _each_if!(body::B, t, n, x, args::A) where {B, A} = _each_on!(body, t, n, args)
@inline _clusters_each!(::Val{false}, body::B, t, n, args::A) where {B, A} = nothing
@inline _clusters_each!(::Val{true}, body::B, t, n, args::A) where {B, A} = _each_on!(body, t, n, args)
@inline _refresh_each!(body::B, t, n, ::Nothing, dv, par, st, lat) where {B} = nothing
@inline _refresh_each!(body::B, t, n, r, dv, par, st, lat) where {B} =
    _each_on!(body, t, n, (dv, par, r.frozen, st.σ, st.cell.kind, r.kinds, lat))
@inline _refresh_fold!(t, ::Nothing, dv, par, mcs) = nothing
@inline _refresh_fold!(t, r, dv, par, mcs) = (t == 1 && _dmask_fold_body!(1, dv, par, mcs); nothing)

@kernel function _fused_kernel!(buf, dv, cols, links, fns, opt, par, round, ruled, clusters, st, p, ctx, key, mcs)
    cnt = @localmem Int32 (PLAN_WG, 3)
    tot = @localmem Int32 (3,)
    t0 = @index(Local, Linear)
    _each!(_dtrigger_body!, t0, length(buf.events),
        (buf.events, dv, par, round, fns.before, fns.trigger, st, p, ctx, key, mcs, clusters))
    @synchronize
    ta = @index(Local, Linear)
    _plan_a!(ta, cnt, buf.events, buf.daughter, buf.removed, buf.bias, dv, par, round, ruled, st, clusters)
    @synchronize
    tb = @index(Local, Linear)
    _plan_b!(tb, buf.events, dv, par, ruled, st, clusters)
    @synchronize
    tc = @index(Local, Linear)
    _plan_c!(tc, cnt, buf.events, dv, par, ruled, clusters)
    @synchronize
    td = @index(Local, Linear)
    _plan_d!(td, cnt, tot, buf.events, dv, par, ruled)
    @synchronize
    te = @index(Local, Linear)
    _plan_e!(te, cnt, tot, buf.events, dv, par, round, ruled, st, clusters)
    @synchronize
    tf = @index(Local, Linear)
    _plan_f!(tf, cnt, tot, dv, par)
    @synchronize
    tg = @index(Local, Linear)
    _plan_g!(tg, cnt, tot, buf.events, buf.daughter, buf.normals, buf.bias, dv, par, fns.normal, fns.cnormal, ruled,
        st, p, ctx, key, mcs, clusters)
    @synchronize
    th = @index(Local, Linear)
    _plan_h!(th, buf.events, buf.daughter, dv, par, ruled, opt.surf)
    @synchronize
    tp = @index(Local, Linear)
    _each_on!(_dpartition_body!, tp, length(st.σ),
        (dv, par, st.σ, buf.daughter, buf.normals, buf.bias, buf.removed, st.cell, ctx.lattice))
    @synchronize
    tq = @index(Local, Linear)
    _each_on!(_dcopies_body!, tq, length(buf.events), (dv, par, buf.events, buf.daughter, buf.removed, cols, links,
        st, ruled, clusters))
    @synchronize
    tu = @index(Local, Linear)
    _each_on!(_drules_body!, tu, length(buf.events), (dv, par, buf.events, buf.daughter, fns.kind, fns.divide!,
        fns.cluster_divide!, st, p, ctx, key, mcs, ruled))
    @synchronize
    ts = @index(Local, Linear)
    _each_if!(_dsurface_body!, ts, length(st.σ), opt.surf, (dv, par, st.σ, opt.surf, opt.rel, ctx.lattice))
    @synchronize
    tz = @index(Local, Linear)
    _each_on!(_dfinalize_body!, tz, length(buf.events),
        (dv, par, buf.daughter, buf.removed, st.cell, opt.surf, ctx.lattice))
    @synchronize
    tk = @index(Local, Linear)
    _clusters_each!(clusters, _dcluster_mark_body!, tk, length(buf.events), (dv, par, st.cell))
    @synchronize
    tl = @index(Local, Linear)
    _clusters_each!(clusters, _dcluster_root_body!, tl, length(buf.events), (dv, par, st.cell, opt.cvol, opt.csurf))
    @synchronize
    tm = @index(Local, Linear)
    _each_if!(_dcluster_volume_body!, tm, length(buf.events), opt.cvol, (dv, par, st.cell, opt.cvol))
    _each_if!(_dcluster_surface_body!, tm, length(st.σ), opt.csurf,
        (dv, par, st.σ, st.cell, opt.csurf, opt.rel, ctx.lattice))
    _refresh_each!(_dfrozen_body!, tm, length(st.σ), opt.refresh, dv, par, st, ctx.lattice)
    @synchronize
    tr = @index(Local, Linear)
    _refresh_fold!(tr, opt.refresh, dv, par, mcs)
end

"""
Fold the device lifecycle's statistics and frozen-mask counts into `integ.stats` (and
`integ.nmobile`): one transfer each, at a host read point that synchronizes anyway. Warns
on the first deferred division of the run, as the CPU path does at the event, and on
divisions deferred for the moment scratch; throws on a cluster event without cluster
state. Every count, the errors included, is reported once (`acc_seen`). `report = false`
(`reinit!`) folds without warning or throwing: the old run's counts are dropped.
"""
function _fold_lifecycle!(integ; report::Bool = true)
    lc = integ.lcache
    (lc === nothing || lc.device === nothing) && return nothing
    D = lc.device
    stats = integ.stats
    _copy!(stats, D.acc, D.dv.acc)
    δ(i) = Int(D.acc[i] - D.acc_seen[i])             # Int32 differences (wrap-safe)
    s = stats.lifecycle
    deferred = δ(_ACC_DEFERRED)
    large = δ(_ACC_LARGE)              # of which for the moment scratch (warned below)
    deferred > large && s.deferred == 0 && report &&
        @warn "lifecycle: all $(length(lc.events)) cell slots are in use; " *
              "divisions are deferred until slots free up. Pass a larger `capacity`."
    s.divisions += δ(_ACC_DIVISIONS)
    s.removals += δ(_ACC_REMOVALS)
    s.transitions += δ(_ACC_TRANSITIONS)
    s.deferred += deferred
    s.empty_daughters += δ(_ACC_EMPTY)
    nocluster = δ(_ACC_NOCLUSTER)
    D.acc_seen .= D.acc
    if integ.mscratch !== nothing
        _copy!(stats, D.mask, D.dv.mask)
        dD = D.mask[1] - D.mask_seen[1]
        dM = D.mask[2] - D.mask_seen[2]
        # the MCS after a refresh at MCS m (m + 1 … t − 1) ran with the old mobile count
        integ.nmobile += Int(dD)
        stats.attempts += Int(dD * (integ.t - 1) - dM)
        stats.refreshes += Int(D.mask[3] - D.mask_seen[3])
        D.mask_seen .= D.mask
    end
    report || return nothing
    large > 0 && @warn "lifecycle: $large division(s) deferred: the dividing cell's second moments exceed the " *
                       "device planner's Int32 scratch (a cell far larger than any in use); such a cell divides " *
                       "only on the CPU"
    nocluster > 0 && throw(ArgumentError("lifecycle: EVENT_DIVIDE_CLUSTER needs cluster state (`init_clusters`)"))
    return nothing
end
