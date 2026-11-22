# The lifecycle planner (D-089, D-096, D-332): one KernelAbstractions planner for every
# backend and every algorithm. Every lifecycle MCS enqueues a fixed sequence of kernels,
# with no host decision and no read-back on a device. A quiet device MCS costs the trigger
# kernel and launches whose work items return at once (they read the round's event flag on
# the device). On the CPU the flag is host memory: a quiet MCS ends after the trigger
# kernel. Host hooks (`Lifecycle.rebuild!`, a custom `remake_frozen`, cell-scope `pieces`)
# run as a host stage after the planner, on event rounds only (`_host_stage!` in
# `problem.jl`).
#
#   trigger    (cells)   events; the round's event flag; cluster ids that hold a dead root
#   plan       (one workgroup of up to PLAN_WG items) the id plan: daughter
#              ids lowest-first among free ids (prefix scans, no atomics-order dependence),
#              capacity deferral, cluster units and their planes, cell division normals
#   partition  (sites)   removed cells' sites → medium; each dividing cell's sites on the
#              positive side of its plane → the daughter; the daughter's volume and moment
#              sums accumulate in integer scratch (exact, order-independent)
#   copies     (cells)   daughter column copies, generation, cluster ids, links (removed
#              cells' links dropped, daughters unlinked), for every cell before any rule
#              runs
#   rules      (cells)   the daughter state rules and transitions (they see the trackers
#              not yet updated)
#   surface    (sites)   the surface change of each parent and daughter (only the moved
#                        sites)
#   counts     (cells, then sites) contact counts (`ctx.contact_counts`), zeroed and summed
#              from σ
#   euler      (cells, then grid vertices) the Euler columns (`euler.jl`), zeroed and summed
#              from σ
#   finalize   (cells)   volume and moments of parents and daughters, removed cells'
#                        trackers
#   clusters   re-root clusters whose root died; cluster volume (cells) and surface (sites)
#   mask       (sites + one item) the frozen-mask refresh and its counts, when the mask
#              follows the state
#
# Lifecycle statistics and the mask counts accumulate on the device and are folded into
# `integ.stats` at host read points (saves, `current_state`, `checkpoint`, the end of
# `solve!`), which synchronize anyway (`_fold_lifecycle!`); on the CPU also after every
# event round.
#
# Index bounds of the `@inbounds` below: cell ids (`c`, `d`, `k`, `r`, `m`: live cells,
# daughters, free slots and cluster ids) are ≤ cap, the length of every cell column and of
# each per-cell scratch of `dv` (`_device_scratch`); a site index `i` is ≤ length(σ); a
# planner item `t` is ≤ the workgroup `wg` ≤ PLAN_WG, the rows of `dv.cnt`;
# `par` ∈ (1, 2) = axes(dv.flag).

# The most items of the planner's (and the fused form's) single workgroup. Fewer cost time
# on a quiet device MCS (each item runs the trigger of capacity/`wg` slots; 128 measured
# about 1.2× slower on Akeeb Metal, `benchmark/ab.jl`). A kernel's pipeline may allow fewer
# threads per group (Metal: register-bound, 384 measured for Akeeb's fused kernel). The
# workgroup is a launch argument: the staged form fits it to the planner's limit before its
# first launch (`_fit_plan_wg!`, halving from `PLAN_WG`), so it always launches. The scans
# take any workgroup size, and the plan does not depend on it.
const PLAN_WG = 256
# tests (not public API): the largest planner workgroup tried (`_fit_plan_wg!`), and a
# simulated pipeline limit (a planner launch with a larger workgroup fails; 0 is off)
const _PLAN_WG_MAX = Ref(PLAN_WG)
const _PLAN_WG_LIMIT = Ref(0)

"""The error of a launch whose workgroup exceeds the simulated limit `_PLAN_WG_LIMIT`."""
struct _PlanWGLimitError <: Exception
    wg::Int
end
Base.showerror(io::IO, e::_PlanWGLimitError) =
    print(io, "workgroup of ", e.wg, " items exceeds the planner's simulated limit")

"""
    _workgroup_limit_error(e) -> Bool

Whether the launch error `e` says that the workgroup exceeds the kernel's limit. Only such
an error makes `_fit_plan_wg!` halve the workgroup; any other error (a compile error in a
user function, for example) is thrown at once. The backend extensions add their launch
errors.
"""
_workgroup_limit_error(e) = false
_workgroup_limit_error(::_PlanWGLimitError) = true

# The forms of the lifecycle: one fused launch (small device problems), then one kernel per
# stage, which always launches (the CPU uses it always: a quiet MCS ends after its trigger)
const _FORM_FUSED = 1
const _FORM_STAGED = 2
# tests: the first launch of the fused form fails (not public API)
const _LAUNCH_FAULT = Ref(0)

# device accumulators (`dv.acc`, cumulative Int32; the host folds the differences)
const _ACC_DIVISIONS = 1
const _ACC_REMOVALS = 2
const _ACC_TRANSITIONS = 3
const _ACC_DEFERRED = 4
const _ACC_EMPTY = 5
const _ACC_NOCLUSTER = 6            # EVENT_DIVIDE_CLUSTER without cluster state (an error)
# divisions deferred: the cell is too large for the Int32 moment scratch of a backend
# without 64-bit atomics (`_scratch_ok`; also counted as deferred)
const _ACC_LARGE = 7
# `transitioning` on an event other than a division (an error)
const _ACC_BADTRANS = 8
const _NACC = 8

# The bound of `_scratch_ok`: `nothing` is the scratch type's own (`typemax(Int64)` where
# `_atomic64(backend)` holds, else `typemax(Int32)`; `@convert` keeps `typemax(Int32)`); a
# `Ref` read when the scratch is built, so that tests can lower it (not public API)
const _SCRATCH_LIMIT = Ref{Union{Nothing, Int64}}(nothing)

# Cell columns that the lifecycle maintains itself (never copied from parent to daughter)
const _LIFECYCLE_OWNED = (
    :volume, :surface, :anchor, :m1, :m2, :generation, :birth, :cluster,
    :cluster_volume, :cluster_surface, :euler, :euler_full, :pieces,
    :largest_piece, :pieces_full, :largest_piece_full,
)

"""Device scratch of the lifecycle (sized by capacity) and the host buffers of its fold."""
function _device_scratch(backend, N::Int, cap::Int, nsite::Int)
    z(T, dims...) = KernelAbstractions.zeros(backend, T, dims...)
    # moment scratch: Int64 where the backend has 64-bit atomics (no large cell is deferred)
    M = _atomic64(backend) ? Int64 : Int32
    lim = _SCRATCH_LIMIT[]
    return (;
        flag = z(Int32, 2), held = z(Int32, cap), newborn = z(Int32, cap),
        req = z(Int32, cap),
        nmem = z(Int32, cap), nlive = z(Int32, cap), coff = z(Int32, cap),
        freelist = z(Int32, cap),
        dvol = z(Int32, cap), dm1 = z(M, N, cap), dm2 = z(M, npairs(N), cap),
        rootA = z(Int32, cap), rootB = z(Int32, cap), okc = z(Bool, cap),
        acc = z(Int32, _NACC),
        mcnt = z(_atomic64(backend) ? site_index_type(nsite) : Int32, 3),
        mask = z(Int64, 4), taken = z(Int32, 1),
        # the planner's scans (one workgroup; device memory is coherent across its barriers)
        cnt = z(Int32, PLAN_WG, 3), tot = z(Int32, 3),
        wacc = z(Int64, cap), wlo = z(UInt32, cap), whi = z(Int32, cap),
        limit = lim === nothing ? Int64(typemax(M)) : lim,
    )
end

"""Host side of the lifecycle planner: the round counter, the kernel objects and the fold
buffers (`acc`/`mask` are read at host read points, and on the CPU after every event round;
`seen` are the values already folded)."""
struct LifecyclePlanner{DV, CO, LI, K, KF}
    dv::DV
    cols::CO            # the cell columns a daughter copies from its parent
    links::LI           # the adjacency matrices of the relationships
    plan!::K
    fused!::KF          # the whole lifecycle in one workgroup (small problems), or nothing
    form::Base.RefValue{Int}        # `_FORM_*`
    proven::Base.RefValue{Bool}     # the form has launched once (its workgroup fits)
    wg::Base.RefValue{Int}          # the planner's workgroup (`_fit_plan_wg!`)
    round::Base.RefValue{Int}
    par::Base.RefValue{Int32}       # the event-flag slot of the last checked round
    flagh::Vector{Int32}            # host copy of that flag (`_events_on`, devices)
    acc::Vector{Int32}
    acc_seen::Vector{Int32}
    mask::Vector{Int64}
    mask_seen::Vector{Int64}
end

# The defaults of `CheckerboardCPM`'s `fused_lifecycle_max_sites` and
# `fused_lifecycle_max_cells`: up to these sizes the whole lifecycle runs as one launch of
# one workgroup (a quiet MCS then costs one launch, as the trigger alone did); larger
# problems launch one kernel per stage over all sites or cells.
const _FUSED_LIFECYCLE_MAX_SITES = 1 << 16
const _FUSED_LIFECYCLE_MAX_CELLS = 1 << 13

function LifecyclePlanner(
        backend, N::Int, cap::Int, st; max_sites::Int = _FUSED_LIFECYCLE_MAX_SITES,
        max_cells::Int = _FUSED_LIFECYCLE_MAX_CELLS
    )
    names = keys(st.cell)
    cols = Tuple(
        getfield(st.cell, k)
            for k in names
            if !(k in _LIFECYCLE_OWNED) && !_is_link_data(k) && !_is_scratch_column(k)
    )
    links = Tuple(getfield(st.cell, k) for k in names if _is_adjacency(k))
    # the CPU runs the staged form (its quiet MCS ends after the trigger kernel), unless a
    # test forces the fused one
    fusable = !(backend isa CPU) || _FORCE_FUSED_LIFECYCLE[]
    fused = if fusable && !_FORCE_STAGED_LIFECYCLE[] &&
            length(st.ownership) <= max_sites && cap <= max_cells
        _fused_kernel!(backend)
    else
        nothing
    end
    return LifecyclePlanner(
        _device_scratch(backend, N, cap, length(st.ownership)), cols, links,
        _plan_kernel!(backend), fused,
        Ref(fused === nothing ? _FORM_STAGED : _FORM_FUSED), Ref(false),
        Ref(min(PLAN_WG, _PLAN_WG_MAX[])), Ref(0), Ref(Int32(1)), zeros(Int32, 1),
        zeros(Int32, _NACC), zeros(Int32, _NACC), zeros(Int64, 4), zeros(Int64, 4)
    )
end

# ---------------------------------------------------------------------------------------
# Trigger

# `before` (`Lifecycle.before`, or `nothing`) runs for cell `c` first, in the same work
# item: the trigger of `c` reads only `c`'s own values of what it writes (its contract), so
# no barrier is needed between them (D-101)
@inline _before!(::Nothing, c, st, p, ctx, key, mcs) = nothing
@inline function _before!(f::F, c, st, p, ctx, key, mcs) where {F}
    c <= ncells(st) && f(st, p, ctx, key, mcs, c % Int32)
    return nothing
end
@inline function _dtrigger_body!(
        c, events, dv, par, round, before::B, trigger::F, st, p, ctx, key, mcs,
        ::Val{CL}
    ) where {B, F, CL}
    _before!(before, c, st, p, ctx, key, mcs)
    e = EVENT_NONE
    if @inbounds(st.cell.volume[c]) > 0
        e = trigger(st, p, ctx, key, mcs, c % Int32) % Int32
        # a dead root still names its cluster while members live: its id is held (not free)
        CL && (@inbounds dv.held[st.cell.cluster[c]] = round)
    end
    @inbounds events[c] = e
    # par ∈ (1, 2) = axes(dv.flag)
    e != EVENT_NONE && @inbounds Atomix.@atomic dv.flag[par] += Int32(1)
    return nothing
end

# bounds: par ∈ (1, 2) = axes(dv.flag)
@inline _on(dv, par) = @inbounds(dv.flag[par]) != Int32(0)

# ---------------------------------------------------------------------------------------
# Plan: one workgroup of `wg` items; item `t` owns the contiguous slots
# `_chunk(t, cap, wg)`, so every scan is in slot order. Values that live across barriers are
# in `dv.cnt` and `dv.tot` (device memory, coherent within the workgroup across a barrier,
# as the fused form relies on), so the workgroup size is a launch argument.

@inline function _chunk(t, cap, wg)
    K = cld(cap, wg)
    lo = (t - 1) * K + 1
    return lo, min(t * K, cap)
end

@inline function _is_free(st, dv, round, e, c, ::Val{CL}) where {CL}
    # bounds: c ≤ cap (cell columns and dv.held; see the file header)
    return @inbounds(st.cell.volume[c]) == 0 && e == EVENT_NONE &&
        (!CL || @inbounds(dv.held[c]) != round)
end

# exclusive prefix sum of `cnt[1:wg, j]` in place; returns the total (one item runs it)
@inline function _scan!(cnt, j, wg)
    s = Int32(0)
    for t in 1:wg
        # bounds: t ≤ wg ≤ PLAN_WG rows and j ≤ 3 columns of cnt
        v = @inbounds cnt[t, j]
        @inbounds cnt[t, j] = s
        s += v
    end
    return s
end

# A: normalize events (only a cluster's root may divide it), reset the per-slot scratch,
# count free slots per item
@inline function _plan_a!(
        t, wg, cnt, events, daughter, removed, bias, dv,
        par, round, ruled, st, cl::Val{CL}
    ) where {CL}
    t == 1 && (@inbounds dv.flag[3 - par] = Int32(0))       # the next round's flag
    nfree = Int32(0)
    if _on(dv, par)
        lo, hi = _chunk(t, length(events), wg)
        for c in lo:hi
            raw = @inbounds events[c]
            e = _event(ruled, raw)
            # counted, thrown on the host; the bit dropped
            if _bad_transition(e)
                Atomix.@atomic dv.acc[_ACC_BADTRANS] += Int32(1)
                e = _base_event(e)
                @inbounds events[c] = _with_rule(ruled, e, raw)
            end
            if _base_event(e) == EVENT_DIVIDE_CLUSTER &&
                    (!CL || @inbounds(st.cell.cluster[c]) != c)
                CL || Atomix.@atomic dv.acc[_ACC_NOCLUSTER] += Int32(1)
                # a transition (`transitioning`) stays
                e = _undivided(e)
                @inbounds events[c] = _with_rule(ruled, e, raw)
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
@inline function _plan_b!(t, wg, events, dv, par, ruled, st, ::Val{CL}) where {CL}
    (CL && _on(dv, par)) || return nothing
    lo, hi = _chunk(t, length(events), wg)
    for c in lo:hi
        # bounds: c ∈ _chunk(t, cap) ⊆ 1:cap; cluster ids r ≤ cap (file header)
        @inbounds(st.cell.volume[c]) > 0 || continue
        r = @inbounds st.cell.cluster[c]
        Atomix.@atomic dv.nlive[r] += Int32(1)
        if _base_event(_event(ruled, @inbounds events[r])) == EVENT_DIVIDE_CLUSTER &&
                _event(ruled, @inbounds events[c]) != EVENT_REMOVE
            Atomix.@atomic dv.nmem[r] += Int32(1)
        end
    end
    return nothing
end

# C: daughters requested by the dividing clusters rooted in each item's slots
@inline function _plan_c!(t, wg, cnt, events, dv, par, ruled, ::Val{CL}) where {CL}
    dem = Int32(0)
    if CL && _on(dv, par)
        lo, hi = _chunk(t, length(events), wg)
        for c in lo:hi
            # bounds: c ∈ _chunk(t, cap, wg) ⊆ 1:cap; t ≤ wg rows of cnt
            _base_event(_event(ruled, @inbounds events[c])) == EVENT_DIVIDE_CLUSTER &&
                (dem += @inbounds dv.nmem[c])
        end
    end
    @inbounds cnt[t, 2] = dem
    return nothing
end

# D (one item): scans of the free slots and of the cluster demand. Clusters take daughters
# first, in root order; when they do not all fit, the D-035 greedy pass defers those that do
# not fit (a later, smaller cluster may still fit)
@inline function _plan_d!(t, wg, cnt, tot, events, dv, par, ruled)
    (t == 1 && _on(dv, par)) || return nothing
    nfree = _scan!(cnt, 1, wg)
    demand = _scan!(cnt, 2, wg)
    @inbounds tot[1] = nfree
    if demand <= nfree
        @inbounds tot[2] = demand
        @inbounds tot[3] = Int32(0)
    else
        next = Int32(0)
        for r in 1:length(events)
            raw = @inbounds events[r]
            _base_event(_event(ruled, raw)) == EVENT_DIVIDE_CLUSTER || continue
            n = @inbounds dv.nmem[r]
            if next + n <= nfree
                @inbounds dv.coff[r] = next
                next += n
            else
                # a transition stays
                @inbounds events[r] = _with_rule(ruled, _undivided(_event(ruled, raw)), raw)
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
@inline function _plan_e!(
        t, wg, cnt, tot, events, dv, par, round, ruled, st, cl::Val{CL}
    ) where {CL}
    nreq = Int32(0)
    if _on(dv, par)
        lo, hi = _chunk(t, length(events), wg)
        k = @inbounds cnt[t, 1]
        off = @inbounds cnt[t, 2]
        greedy = @inbounds(tot[3]) != 0
        for c in lo:hi
            e = _event(ruled, @inbounds events[c])
            if _is_free(st, dv, round, e, c, cl)
                k += Int32(1)
                @inbounds dv.freelist[k] = c % Int32
            end
            if CL && _base_event(e) == EVENT_DIVIDE_CLUSTER && !greedy
                @inbounds dv.coff[c] = off
                off += @inbounds dv.nmem[c]
            end
            if _base_event(e) == EVENT_DIVIDE
                # a member of a dividing cluster divides with it, not alone
                member = CL &&
                    _base_event(_event(ruled, @inbounds events[st.cell.cluster[c]])) ==
                    EVENT_DIVIDE_CLUSTER
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
@inline function _plan_f!(t, wg, cnt, tot, dv, par)
    (t == 1 && _on(dv, par)) || return nothing
    nreq = _scan!(cnt, 3, wg)
    avail = @inbounds(tot[1]) - @inbounds(tot[2])
    ndiv = min(nreq, avail)
    ndiv > 0 && Atomix.@atomic dv.acc[_ACC_DIVISIONS] += ndiv
    nreq > ndiv && Atomix.@atomic dv.acc[_ACC_DEFERRED] += nreq - ndiv
    # free-list entries taken this round (serials): scratch, committed to the counter after
    # the partition (`_advance_births!`), so a staged launch that fails in the planner
    # leaves the state's counter as it was
    @inbounds dv.taken[1] = @inbounds(tot[2]) + ndiv          # taken has 1 entry, tot 3
    return nothing
end

# Cell serials (D-066 item 3; `Lifecycle`): the daughter in free-list entry `k + 1` (0-based
# `k`, the allocation order: slot order) takes serial `next + k`; after the round the
# counter advances past every entry taken (a division deferred for the moment scratch leaves
# its serial unused, never reused). `births` is `nothing` without a `birth` column.
@inline _birth!(::Nothing, d, k) = nothing
@inline function _birth!(b, d, k)
    # `next` has one entry; d is a free slot
    @inbounds b.col[d] = b.next[1] + k % Int32
    return nothing
end
@inline _advance_births!(::Nothing, dv) = nothing
# both have one entry
@inline _advance_births!(b, dv) = (@inbounds b.next[1] += dv.taken[1]; nothing)
function _births(st)
    if haskey(st.cell, :birth) && haskey(st.model, NEXT_BIRTH)
        return (; col = st.cell.birth, next = getfield(st.model, NEXT_BIRTH))
    else
        return nothing
    end
end

# G: daughters and planes. A cell dividing alone takes its slot and its normal; the item of
# a dividing cluster's root assigns its members' daughters in slot order and evaluates the
# cluster plane on the cluster's moments
@inline function _plan_g!(
        t, wg, cnt, tot, events, daughter, normals, bias, dv, par, normal::NF, cnormal::CF,
        ruled, st, p, ctx, key, mcs, ::Val{CL}, births
    ) where {NF, CF, CL}
    _on(dv, par) || return nothing
    lo, hi = _chunk(t, length(events), wg)
    rk = @inbounds(tot[2]) + @inbounds(cnt[t, 3])
    nfree = @inbounds tot[1]
    for c in lo:hi
        if @inbounds(dv.req[c]) == 1
            if rk < nfree
                if _scratch_ok(dv, st.cell, c, Val(ndims(ctx.lattice)))
                    @inbounds daughter[c] = dv.freelist[rk + 1]
                    _birth!(births, @inbounds(dv.freelist[rk + 1]), rk)
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
        if CL && @inbounds(st.cell.cluster[c]) == c &&
                _base_event(_event(ruled, @inbounds events[c])) == EVENT_DIVIDE_CLUSTER
            _plan_cluster!(
                c % Int32, events, daughter, normals, bias, dv,
                cnormal, ruled, st, p, ctx, key, mcs, births
            )
        end
    end
    return nothing
end

# A daughter's volume and moment sums about the parent's anchor accumulate in integer
# scratch (`_dpartition_body!`): Int64 where the backend has 64-bit atomics (the bound below
# then always holds, since `m2` is Int64), Int32 elsewhere (Metal). With δ the integer
# offsets (site − parent anchor) of the daughter's sites, a subset of the parent's, and
# P_k = Σ_parent δ_k² (the parent's `m2[k, k]`, exact):
#   |Σ δ_k| ≤ Σ |δ_k| ≤ Σ δ_k² ≤ P_k                         (integers: |δ| ≤ δ²)
#   |Σ δ_k δ_l| ≤ Σ (δ_k² + δ_l²)/2 ≤ max(P_k, P_l)
#   0 ≤ Σ δ_k² ≤ P_k,   0 ≤ the daughter's volume ≤ the parent's (an Int32 site count)
# so every final sum fits in the scratch type when every P_k ≤ its `typemax` (atomic adds
# wrap, so the order of the partial sums does not matter), and each site's own term
# |δ_k δ_l| ≤ max(P_k, P_l).
# A larger cell does not divide: its division is deferred and counted (`_ACC_LARGE`), the
# state stays exact, and the host warns at the next read point.
@inline function _scratch_ok(dv, cell, c, ::Val{N}) where {N}
    ok = true
    for k in 1:N
        # bounds: c ≤ cap; _pair(N, k, k) ≤ npairs(N), the rows of m2
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
# bounds: a.v is one cell's column (anchor, m1 or m2); d runs over that column's rows
@inline Base.getindex(a::_OneColumn, d, c) = @inbounds a.v[d]

@inline function _plan_cluster!(
        r, events, daughter, normals, bias, dv, cnormal::CF, ruled, st, p, ctx, key,
        mcs, births
    ) where {CF}
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
            Int64(@inbounds cell.m2[q, m]) + δa[d] * m1m[e] + δa[e] * m1m[d] +
                Int64(Vm) * δa[d] * δa[e]
        end
        inc1 = ntuple(d -> m1m[d] + Int64(Vm) * δa[d], Val(N))
        VK += Vm
        m1K = map(+, m1K, inc1)
        m2K = map(+, m2K, inc2)
        em = _event(ruled, @inbounds events[m])
        em == EVENT_REMOVE && continue
        @inbounds daughter[m] = dv.freelist[j + 1]
        _birth!(births, @inbounds(dv.freelist[j + 1]), j)
        j += Int32(1)
        # A-17: it transitions first
        ev = _transitions(em) ? _EVENT_DIVIDE_CLUSTER_TRANSITION : EVENT_DIVIDE_CLUSTER
        # members follow the root's rule
        @inbounds events[m] = _with_rule(ruled, ev, raw_r)
    end
    cellK = merge(
        cell,
        (;
            volume = _OneValue(VK), anchor = _OneColumn(ar),
            m1 = _OneColumn(m1K), m2 = _OneColumn(m2K),
        )
    )
    n = cnormal((; ownership = st.ownership, cell = cellK), p, ctx, key, mcs, r)
    cK = centroid(T, cellK, lat, r)
    for m in 1:cap
        (@inbounds(cell.volume[m]) > 0 && @inbounds(cell.cluster[m]) == r) || continue
        cm = centroid(T, cell, lat, m)
        # member − cluster centroid
        δ = _min_image(T, lat, ntuple(d -> cm[d] - cK[d], Val(N)))
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
@inline function _plan_h!(t, wg, events, daughter, dv, par, ruled, surf)
    _on(dv, par) || return nothing
    lo, hi = _chunk(t, length(events), wg)
    ntrans = Int32(0)
    nrem = Int32(0)
    for c in lo:hi
        # bounds: c ∈ _chunk(t, cap); daughters d ≤ cap (file header)
        d = @inbounds daughter[c]
        if d > 0
            @inbounds dv.newborn[d] = c % Int32
            surf === nothing || (@inbounds surf[d] = zero(eltype(surf)))
        end
        e = _event(ruled, @inbounds events[c])
        _transitions(e) && (ntrans += Int32(1))
        e == EVENT_REMOVE && (nrem += Int32(1))
    end
    ntrans > 0 && Atomix.@atomic dv.acc[_ACC_TRANSITIONS] += ntrans
    nrem > 0 && Atomix.@atomic dv.acc[_ACC_REMOVALS] += nrem
    return nothing
end

# `live = false` is the compile launch (compile before enqueue, and the fit of the workgroup
# `wg`, `_fit_plan_wg!`): one workgroup in which every stage is skipped, so nothing is read
# or written. The guard is an `if` around
# each stage, not around the kernel: `@synchronize` stays at the top level, where every
# work item reaches it. (KA's CPU backend splits the kernel at each `@synchronize` and needs
# `@index` as its own statement in each part.)
@kernel function _plan_kernel!(
        live, wg, events, daughter, removed, normals, bias, dv, par, round, normal,
        cnormal, ruled, st, p, ctx, key, mcs, clusters, surf, births
    )
    cnt = @uniform dv.cnt
    tot = @uniform dv.tot
    ta = @index(Local, Linear)
    if live
        _plan_a!(
            ta, wg, cnt, events, daughter, removed, bias, dv, par, round, ruled, st,
            clusters
        )
    end
    @synchronize
    tb = @index(Local, Linear)
    if live
        _plan_b!(tb, wg, events, dv, par, ruled, st, clusters)
    end
    @synchronize
    tc = @index(Local, Linear)
    if live
        _plan_c!(tc, wg, cnt, events, dv, par, ruled, clusters)
    end
    @synchronize
    td = @index(Local, Linear)
    if live
        _plan_d!(td, wg, cnt, tot, events, dv, par, ruled)
    end
    @synchronize
    te = @index(Local, Linear)
    if live
        _plan_e!(te, wg, cnt, tot, events, dv, par, round, ruled, st, clusters)
    end
    @synchronize
    tf = @index(Local, Linear)
    if live
        _plan_f!(tf, wg, cnt, tot, dv, par)
    end
    @synchronize
    tg = @index(Local, Linear)
    if live
        _plan_g!(
            tg, wg, cnt, tot, events, daughter, normals, bias, dv,
            par, normal, cnormal, ruled, st, p, ctx, key, mcs,
            clusters, births
        )
    end
    @synchronize
    th = @index(Local, Linear)
    if live
        _plan_h!(th, wg, events, daughter, dv, par, ruled, surf)
    end
end

# ---------------------------------------------------------------------------------------
# Partition: removed cells' sites become medium; a dividing cell's sites on the positive
# side of its plane go to the daughter, whose volume and moment sums (about the parent's
# anchor) accumulate in integer scratch

@inline function _dpartition_body!(
        i, dv, par, σ, daughter, normals, bias, removed, cell, lat, hook::H, st
    ) where {H}
    _on(dv, par) || return nothing
    c = @inbounds σ[i]
    c > 0 || return nothing
    if @inbounds(removed[c])
        @inbounds σ[i] = Int32(0)
        _owner_changed!(hook, st, i)
    elseif (d = @inbounds daughter[c]) > 0
        N = ndims(lat)
        δ = min_image(lat, coordinates(lat, i), anchor(cell, c, Val(N)))
        T = eltype(normals)
        V = T(@inbounds cell.volume[c])
        side = @inbounds bias[c]                     # 0 unless it divides with its cluster
        # site − centroid
        offset = embed(lat, ntuple(k -> T(δ[k]) - T(@inbounds cell.m1[k, c]) / V, Val(N)))
        for k in 1:N
            side += T(offset[k]) * @inbounds(normals[k, c])
        end
        if side > 0
            @inbounds σ[i] = d
            _owner_changed!(hook, st, i)
            Atomix.@atomic dv.dvol[d] += Int32(1)
            # `% M`: |δ_k|, |δ_k δ_l| ≤ the parent's m2[k, k] ≤ the scratch limit
            # (`_scratch_ok`), and the sums wrap (exact once complete)
            M = eltype(dv.dm1)
            for k in 1:N
                Atomix.@atomic dv.dm1[k, d] += δ[k] % M
                for l in k:N
                    Atomix.@atomic dv.dm2[_pair(N, k, l), d] += (δ[k] * δ[l]) % M
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

# `_copy_column!` and `_clean_links!` mapped over the columns: functors, not per-call
# closures
struct _CopyColumn{C, D}
    c::C
    d::D
end
@inline (f::_CopyColumn)(a) = _copy_column!(a, f.c, f.d)
struct _CleanLinks{C, R, B}
    c::C
    removed::R
    newborn::B
end
@inline (f::_CleanLinks)(L) = _clean_links!(L, f.c, f.removed, f.newborn)

@inline function _copy_column!(a::AbstractVector, c, d)
    # bounds: c, d ≤ cap = length(a)
    @inbounds a[d] = a[c]
    return nothing
end
@inline function _copy_column!(a::AbstractArray, c, d)
    n = length(a) ÷ size(a, ndims(a))               # entries per cell
    for k in 1:n
        # bounds: n entries per cell and c, d ≤ cap cells: both ranges are in a
        @inbounds a[(d - 1) * n + k] = a[(c - 1) * n + k]
    end
    return nothing
end

# links: a removed cell and a daughter (whose slot may be reused) lose every link; their
# partners drop them (each item writes only its own row: the store is symmetric)
@inline function _clean_links!(L, c, removed, newborn)
    # bounds: c ≤ cap columns of L; partners b > 0 are cell ids ≤ cap
    clear = @inbounds(removed[c]) || @inbounds(newborn[c]) > 0
    for k in 1:size(L, 1)
        b = @inbounds L[k, c]
        b == 0 && continue
        (clear || @inbounds(removed[b]) || @inbounds(newborn[b]) > 0) &&
            (@inbounds L[k, c] = zero(eltype(L)))
    end
    return nothing
end

@inline function _dcopies_body!(
        c, dv, par, events, daughter, removed, cols, links, st, ruled,
        ::Val{CL}, release::RL, births::BT
    ) where {CL, RL, BT}
    _on(dv, par) || return nothing
    # the serial counter passes the entries the planner took (the first stage writing state)
    c == 1 && _advance_births!(births, dv)
    # D-066 item 5 (a): cell c's references to dead cells reset first (no volume changes in
    # this stage, so a slot reused this round still reads as dead), and the daughter copies
    # the reset value; only a live cell's own columns are written (`Lifecycle.release`)
    _release!(release, st, c)
    # bounds: c, d, k ≤ cap (file header)
    d = @inbounds daughter[c]
    if d > 0
        map(_CopyColumn(c, d), cols)
        @inbounds st.cell.generation[d] += one(eltype(st.cell.generation))
        if CL
            k = @inbounds st.cell.cluster[c]
            @inbounds st.cell.cluster[d] = if _divides_with_cluster(
                    _event(ruled, @inbounds events[c])
                )
                daughter[k]               # the root's daughter names the new cluster
            elseif dv.nlive[k] == 1
                d                         # a lone cell's daughter is lone
            else
                k
            end
        end
    end
    map(_CleanLinks(c, removed, dv.newborn), links)
    return nothing
end

@inline function _drules_body!(
        c, dv, par, events, daughter, kindf::KF, divide!::DF, cluster_divide!::CF, st, p,
        ctx, key, mcs, ruled
    ) where {KF, DF, CF}
    _on(dv, par) || return nothing
    _cell_rule_body!(
        c, events, daughter, kindf, divide!, cluster_divide!, st, p, ctx, key, mcs, ruled
    )
    return nothing
end

# ---------------------------------------------------------------------------------------
# Surface: only the parents and daughters change (a removed cell's neighbours still border
# another owner). For a site that moved from parent `pc` to daughter `s`: the daughter gains
# its bonds to non-daughter sites; the parent loses the site's old bonds to non-parent
# sites and gains the bonds of its remaining sites to the site (a symmetric relation)

@inline function _dsurface_body!(i, dv, par, σ, surf, rel, lat, u)
    _on(dv, par) || return nothing
    # bounds: i ≤ length(σ); owners and newborn parents ≤ cap; k ≤ length(rel)
    s = @inbounds σ[i]
    s > 0 || return nothing
    pc = @inbounds dv.newborn[s]
    pc > 0 || return nothing
    x = coordinates(lat, i)
    T = eltype(surf)
    sd = _wzero(u, T)
    sp = _wzero(u, T)
    for k in 1:length(rel)
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        n = @inbounds σ[linear_index(lat, y)]
        w = _wt(u, rel, k, T)
        n != s && (sd += w)
        n == pc && (sp += w)
        (n != pc && n != s) && (sp -= w)
    end
    _wadd!(u, dv, surf, s, sd)
    _wadd!(u, dv, surf, pc, sp)
    return nothing
end

# A weighted surface in a float column adds integer weight units (`_units_for`) to
# `dv.wacc` (an exact, order-free sum); `_wfold!` adds the sum to the column once per cell
@inline _wadd!(::Nothing, dv, col, c, v) = (Atomix.@atomic col[c] += v; nothing)
@inline _wadd!(u::NamedTuple, dv, col, c, v) = _cr_add!(_wsc(dv), c, v, u.paired)
@inline _wsc(dv) = (; acc = dv.wacc, lo = dv.wlo, hi = dv.whi)
@inline _wfold!(::Nothing, dv, col, c, ::Val) = nothing
@inline function _wfold!(u::NamedTuple, dv, col, c, ::Val{ASSIGN}) where {ASSIGN}
    sc = _wsc(dv)
    a = _cr_acc(sc, c, u.paired)
    v = _wvalue(eltype(col), a, u.e)
    if ASSIGN
        @inbounds col[c] = v                              # c ≤ capacity = length(col)
    elseif a != 0
        @inbounds col[c] += v
    end
    @inbounds begin
        sc.acc[c] = 0
        sc.lo[c] = 0
        sc.hi[c] = 0
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Finalize: the trackers of parents, daughters and removed cells

@inline function _dfinalize_body!(c, dv, par, daughter, removed, cell, surf, lat, u)
    _on(dv, par) || return nothing
    # the surface stage's units (before a removal's reset)
    _wfold!(u, dv, surf, c, Val(false))
    N = ndims(lat)
    # bounds: c, d ≤ cap; k ≤ N and q ≤ npairs(N) rows of the moment columns
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
        @inbounds dv.dm1[k, d] = zero(eltype(dv.dm1))
    end
    for q in 1:npairs(N)
        m = eltype(cell.m2)(@inbounds dv.dm2[q, d])
        @inbounds cell.m2[q, d] = m
        @inbounds cell.m2[q, c] -= m
        @inbounds dv.dm2[q, d] = zero(eltype(dv.dm2))
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
    # bounds: c and its cluster id k ≤ cap (file header)
    @inbounds(cell.volume[c]) > 0 || return nothing
    k = @inbounds cell.cluster[c]
    ok = @inbounds(cell.volume[k]) > 0 && @inbounds(cell.cluster[k]) == k
    @inbounds dv.okc[c] = ok
    if !ok
        @inbounds(cell.kind[c]) == @inbounds(cell.kind[k]) &&
            Atomix.@atomic dv.rootA[k] min (c % Int32)
        Atomix.@atomic dv.rootB[k] min (c % Int32)
    end
    return nothing
end

@inline function _dcluster_root_body!(c, dv, par, cell, cvol, csurf)
    _on(dv, par) || return nothing
    # bounds: c and its cluster id k ≤ cap (file header)
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
    # bounds: c ≤ cap (file header)
    V = @inbounds cell.volume[c]
    V > 0 || return nothing
    k = @inbounds cell.cluster[c]
    Atomix.@atomic cvol[k] += eltype(cvol)(V)
    return nothing
end

@inline function _dcluster_surface_body!(i, dv, par, σ, cell, csurf, rel, lat, u)
    _on(dv, par) || return nothing
    # bounds: i ≤ length(σ); owners s > 0 ≤ cap (file header)
    s = @inbounds σ[i]
    s > 0 || return nothing
    K = @inbounds cell.cluster[s]
    x = coordinates(lat, i)
    T = eltype(csurf)
    a = _wzero(u, T)
    for k in 1:length(rel)
        inside, y = shift(lat, x, @inbounds rel.offsets[k])
        inside || continue
        cluster_of(cell, @inbounds σ[linear_index(lat, y)]) != K && (a += _wt(u, rel, k, T))
    end
    a != zero(a) && _wadd!(u, dv, csurf, K, a)
    return nothing
end

# the cluster surfaces from their units (weighted float columns only)
@inline function _dcluster_surface_fold_body!(c, dv, par, csurf, u)
    _on(dv, par) || return nothing
    _wfold!(u, dv, csurf, c, Val(true))
    return nothing
end

# ---------------------------------------------------------------------------------------
# The frozen mask: refreshed on event rounds; the change of the mobile count is folded per
# round into `mask = [Σ d, Σ d·mcs, refreshes, changed sites]` (Int64, one item), so the
# host corrects `stats.attempts` exactly at its next read point and rebuilds the host
# mobile-site list (`SequentialCPM`) when a site changed

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
    @inbounds dv.mask[4] += Int64(@inbounds dv.mcnt[3])
    @inbounds dv.mcnt[2] = zero(eltype(dv.mcnt))     # `site_index_type` (D-253)
    @inbounds dv.mcnt[3] = zero(eltype(dv.mcnt))
    return nothing
end

# ---------------------------------------------------------------------------------------
# Host orchestration (enqueue only)

# The built-in planes compute in the state's float type, on the host and on a device (the
# planner compiles every plane of the model, also those of rules that never fire: a
# `Float64` default must not reach Metal)
_plane(::AlongMinorAxis, ::Type{T}) where {T} = AlongMinorAxis{T}()
_plane(::AlongMajorAxis, ::Type{T}) where {T} = AlongMajorAxis{T}()
_plane(::RandomPlane, ::Type{T}) where {T} = RandomPlane{T}()
_plane(normal, ::Type) = normal

"""
Enqueue the lifecycle of MCS `mcs`. `refresh` is `nothing` or `(frozen, kinds)` of a
standard-rule frozen mask. Returns the number of kernel launches. On a device nothing is
synchronized or transferred; on the CPU a quiet round ends after the trigger kernel.
`cache.device.par[]` is the round's event-flag slot (`_events_on`).
"""
function run_lifecycle!(lc::Lifecycle, cache, st, p, ctx, key, mcs, backend, refresh)
    D = cache.device
    mcs % lc.every != 0 && return _run_before(lc.before, st, p, ctx, key, mcs, backend)
    r = (D.round[] += 1)
    par = Int32(isodd(r) ? 1 : 2)
    D.par[] = par
    round = Int32(r % typemax(Int32))
    T = eltype(cache.normals)
    buf = (; cache.events, cache.daughter, cache.removed, cache.normals, cache.bias)
    fns = (;
        lc.before, lc.trigger, normal = _plane(lc.normal, T),
        cnormal = _plane(lc.cluster_normal, T), lc.kind, lc.divide!,
        lc.cluster_divide!, lc.release, lc.owner_changed,
    )
    surface = haskey(st.cell, :surface) && haskey(ctx, :surface)
    csurface = _has_clusters(st) && haskey(st.cell, :cluster_surface) &&
        haskey(ctx, :surface)
    nsite = length(st.ownership)
    opt = (;
        surf = surface ? st.cell.surface : nothing,
        cvol = if _has_clusters(st) && haskey(st.cell, :cluster_volume)
            st.cell.cluster_volume
        else
            nothing
        end,
        csurf = csurface ? st.cell.cluster_surface : nothing,
        rel = haskey(ctx, :surface) ? ctx.surface : nothing, refresh,
        su = if surface
            _units_for(eltype(st.cell.surface), ctx.surface, nsite, backend)
        else
            nothing
        end,
        cu = if csurface
            _units_for(eltype(st.cell.cluster_surface), ctx.surface, nsite, backend)
        else
            nothing
        end,
        cc = _contact_counts(ctx), ccols = _count_columns(st, _contact_counts(ctx)),
        eul = _euler_columns(st.cell),
        births = _births(st),
    )
    CL = Val(_has_clusters(st))
    if D.form[] == _FORM_FUSED
        D.proven[] && return _run_fused!(
            D, buf, fns, opt, par, round, lc.rules, CL, st, p, ctx, key, mcs
        )
        n = try
            _LAUNCH_FAULT[] == _FORM_FUSED && throw(ArgumentError("launch refused (test)"))
            _run_fused!(D, buf, fns, opt, par, round, lc.rules, CL, st, p, ctx, key, mcs)
        catch e
            _form_failed!(D, e)
        end
        n > 0 && (D.proven[] = true; return n)
    end
    if !D.proven[]
        # The first launch of the staged form: every kernel is compiled (with this launch's
        # argument types) before any is enqueued, and the planner's workgroup is fitted to
        # its pipeline's limit (`_fit_plan_wg!`). Every other kernel's group is sized by the
        # backend from its own limit (`Exec.launch!`), so the form always launches.
        compile = _CompileOnly()
        _run_staged!(
            D, buf, fns, opt, par, round, lc.rules, CL,
            st, p, ctx, key, mcs, backend, compile
        )
        _compile!(compile, backend)
        D.proven[] = true
    end
    return _run_staged!(
        D, buf, fns, opt, par, round, lc.rules, CL,
        st, p, ctx, key, mcs, backend, _Enqueue()
    )
end

# The first launch of the fused form failed (e.g. its workgroup exceeds the kernel's
# limit): nothing was enqueued, and the staged form takes the MCS
function _form_failed!(D, e)
    isfatal(e) && throw(e)
    @warn "lifecycle: the fused form cannot launch ($(sprint(showerror, e))); using one " *
        "kernel per stage"
    D.form[] = _FORM_STAGED
    D.proven[] = false
    return -1
end

function _run_fused!(D, buf, fns, opt, par, round, ruled, CL, st, p, ctx, key, mcs)
    w = D.wg[]
    D.fused!(
        w, buf, D.dv, D.cols, D.links, fns, opt, par, round,
        ruled, CL, st, p, ctx, key, mcs; ndrange = w, workgroupsize = w
    )
    return 1
end

"""
Fit the planner's workgroup to its pipeline's limit: launch the planner with `live = false`
(no stage runs) over one workgroup of `D.wg[]` items, halving while the launch fails with a
workgroup-limit error (`_workgroup_limit_error`). A launch that exceeds the limit fails on
the host before anything is enqueued. Any other error is thrown at once. The plan does not
depend on the workgroup size.
"""
function _fit_plan_wg!(D, args::A) where {A}
    w = D.wg[]
    while true
        ok = try
            lim = _PLAN_WG_LIMIT[]
            lim > 0 && w > lim && throw(_PlanWGLimitError(w))
            D.plan!(false, w, args...; ndrange = w, workgroupsize = w)
            true
        catch e
            (w == 1 || isfatal(e) || !_workgroup_limit_error(e)) && rethrow()
            false
        end
        ok && break
        w ÷= 2
    end
    D.wg[] = w
    return nothing
end

# How `_run_staged!` issues its kernels: enqueue each (`_Enqueue`); or only collect each
# kernel's compile, with the argument types of the launch, enqueueing none (`_CompileOnly`,
# the first launch of the form; `_compile!` then compiles the set on host tasks)
struct _Enqueue end
struct _CompileOnly
    jobs::Vector{Any}                   # one compile per kernel (`Exec.compile_all!`)
end
_CompileOnly() = _CompileOnly(Any[])
_compile!(m::_CompileOnly, backend) = Exec.compile_all!(backend, m.jobs)

function _stage!(::_Enqueue, body::B, backend, n, args::A) where {B, A}
    return Exec.launch!(backend, body, n, args)
end
# Compile without enqueueing work: `Exec.compile!`, a launch of the kernel `Exec.launch!`
# runs, with `n = 0`, so no work item passes its guard (the kernel type does not depend on
# the ndrange: the launch that follows reuses the compile; a launch over an empty range is
# not used, since KA 0.10 returns before compiling it). Guarded by `test/device_ir.jl`
# (ROCm) and the CorePotts Metal suite. The host executor has no compilation step.
function _stage!(m::_CompileOnly, body::B, backend, n, args::A) where {B, A}
    push!(m.jobs, () -> Exec.compile!(backend, body, args))
    return nothing
end

function _stage_plan!(::_Enqueue, D, backend, args::A) where {A}
    w = D.wg[]
    D.plan!(true, w, args...; ndrange = w, workgroupsize = w)
    return nothing
end
# the planner's compile and workgroup fit, at once (one workgroup with `live = false`)
_stage_plan!(m::_CompileOnly, D, backend, args::A) where {A} = _fit_plan_wg!(D, args)

# A quiet round on the CPU ends after the trigger kernel: the event flag is host memory, so
# its read is free; the next round's flag (reset by the planner otherwise) is reset here. On
# a device the round goes on, every later work item returning at once.
_quiet_exit(::_CompileOnly, backend, dv, par) = false
_quiet_exit(::_Enqueue, backend, dv, par) = false
function _quiet_exit(::_Enqueue, ::CPU, dv, par)
    _on(dv, par) && return false
    @inbounds dv.flag[3 - par] = Int32(0)          # par ∈ (1, 2) = axes(dv.flag)
    return true
end

"""Whether the last checked round had an event (the CPU: a read of host memory; a device:
one synchronizing read of the 4-byte flag, counted in `stats`)."""
_events_on(stats, ::CPU, D) = _on(D.dv, D.par[])
function _events_on(stats, backend, D)
    sync!(stats, backend)
    counted_copy!(stats, D.flagh, 1, D.dv.flag, Int(D.par[]), 1)
    return D.flagh[1] != 0
end

# one kernel per stage (large problems)
function _run_staged!(
        D, buf, fns, opt, par, round, ruled, CL, st,
        p, ctx, key, mcs, backend, mode::M
    ) where {M}
    dv = D.dv
    cap = length(st.cell.kind)
    n = length(st.ownership)
    lat = ctx.lattice
    surf, cvol, csurf, refresh = opt.surf, opt.cvol, opt.csurf, opt.refresh
    _stage!(
        mode, _dtrigger_body!, backend, cap,
        (buf.events, dv, par, round, fns.before, fns.trigger, st, p, ctx, key, mcs, CL)
    )
    _quiet_exit(mode, backend, dv, par) && return 1
    _stage_plan!(
        mode, D,
        backend,
        (
            buf.events, buf.daughter, buf.removed, buf.normals, buf.bias, dv, par, round,
            fns.normal, fns.cnormal, ruled, st, p, ctx, key, mcs, CL, surf, opt.births,
        )
    )
    _stage!(
        mode, _dpartition_body!, backend, n,
        (
            dv, par, st.ownership, buf.daughter, buf.normals, buf.bias,
            buf.removed, st.cell, lat, fns.owner_changed, st,
        )
    )
    _stage!(
        mode, _dcopies_body!,
        backend,
        cap,
        (
            dv, par, buf.events, buf.daughter, buf.removed, D.cols, D.links, st,
            ruled, CL, fns.release, opt.births,
        )
    )
    _stage!(
        mode, _drules_body!,
        backend,
        cap,
        (
            dv, par, buf.events, buf.daughter, fns.kind, fns.divide!,
            fns.cluster_divide!, st, p, ctx, key, mcs, ruled,
        )
    )
    launches = 5
    if surf !== nothing
        _stage!(
            mode, _dsurface_body!, backend, n,
            (dv, par, st.ownership, surf, ctx.surface, lat, opt.su)
        )
        launches += 1
    end
    # contact counts: zeroed, then summed from σ (`contact_counts.jl`)
    if opt.cc !== nothing
        _stage!(mode, _dcount_zero_body!, backend, cap, (dv, par, opt.ccols))
        _stage!(
            mode, _dcount_body!, backend, n,
            (dv, par, st.ownership, st.cell.kind, opt.cc, opt.ccols, lat)
        )
        launches += 2
    end
    if opt.eul !== nothing         # Euler columns: zeroed, then summed from σ (`euler.jl`)
        _stage!(mode, _deuler_zero_body!, backend, cap, (dv, par, opt.eul))
        _stage!(
            mode, _deuler_body!, backend, _euler_anchors(lat),
            (dv, par, st.ownership, opt.eul, lat)
        )
        launches += 2
    end
    _stage!(
        mode, _dfinalize_body!,
        backend,
        cap,
        (
            dv, par, buf.daughter, buf.removed, st.cell, surf, lat,
            surf === nothing ? nothing : opt.su,
        )
    )
    launches += 1
    if _has_clusters(st)
        _stage!(mode, _dcluster_mark_body!, backend, cap, (dv, par, st.cell))
        _stage!(mode, _dcluster_root_body!, backend, cap, (dv, par, st.cell, cvol, csurf))
        launches += 2
        if cvol !== nothing
            _stage!(mode, _dcluster_volume_body!, backend, cap, (dv, par, st.cell, cvol))
            launches += 1
        end
        if csurf !== nothing
            _stage!(
                mode, _dcluster_surface_body!, backend, n,
                (dv, par, st.ownership, st.cell, csurf, ctx.surface, lat, opt.cu)
            )
            launches += 1
            if opt.cu !== nothing
                _stage!(
                    mode, _dcluster_surface_fold_body!,
                    backend, cap, (dv, par, csurf, opt.cu)
                )
                launches += 1
            end
        end
    end
    if refresh !== nothing
        _stage!(
            mode, _dfrozen_body!, backend, n,
            (dv, par, refresh.frozen, st.ownership, st.cell.kind, refresh.kinds, lat)
        )
        _stage!(mode, _dmask_fold_body!, backend, 1, (dv, par, mcs))
        launches += 2
    end
    return launches
end

# ---------------------------------------------------------------------------------------
# The fused form: every stage above as a section of one workgroup, the barriers between
# sections in place of the kernel boundaries (device memory is coherent within the
# workgroup across a barrier). Item `t` of the `wg` takes the slots or sites
# `t, t + wg, …` (`tw = (t, wg)`).

@inline function _each!(body::B, tw, n, args::A) where {B, A}
    i = Int(tw[1])                      # a local index may be 32-bit on a device
    w = Int(tw[2])
    while i <= n
        body(i, args...)
        i += w
    end
    return nothing
end
# the stages after the trigger (`args` start with `dv, par`): a quiet round skips the loop
@inline function _each_on!(body::B, t, n, args::A) where {B, A}
    _on(args[1], args[2]) && _each!(body, t, n, args)
    return nothing
end
@inline _each_if!(body::B, t, n, x::Nothing, args::A) where {B, A} = nothing
@inline _each_if!(body::B, t, n, x, args::A) where {B, A} = _each_on!(body, t, n, args)
@inline _clusters_each!(::Val{false}, body::B, t, n, args::A) where {B, A} = nothing
@inline function _clusters_each!(::Val{true}, body::B, t, n, args::A) where {B, A}
    return _each_on!(
        body,
        t, n, args
    )
end
@inline _refresh_each!(body::B, t, n, ::Nothing, dv, par, st, lat) where {B} = nothing
@inline function _refresh_each!(body::B, t, n, r, dv, par, st, lat) where {B}
    return _each_on!(
        body, t, n, (
            dv, par, r.frozen, st.ownership, st.cell.kind, r.kinds, lat,
        )
    )
end
@inline _refresh_fold!(t, ::Nothing, dv, par, mcs) = nothing
@inline function _refresh_fold!(t, r, dv, par, mcs)
    t == 1 && _dmask_fold_body!(1, dv, par, mcs)
    return nothing
end

@kernel function _fused_kernel!(
        wg, buf, dv, cols, links, fns, opt, par, round, ruled, clusters, st, p, ctx, key,
        mcs
    )
    cnt = @uniform dv.cnt
    tot = @uniform dv.tot
    t0 = @index(Local, Linear)
    _each!(
        _dtrigger_body!, (t0, wg), length(buf.events),
        (
            buf.events, dv, par, round, fns.before,
            fns.trigger, st, p, ctx, key, mcs, clusters,
        )
    )
    @synchronize
    ta = @index(Local, Linear)
    _plan_a!(
        ta, wg, cnt, buf.events, buf.daughter, buf.removed,
        buf.bias, dv, par, round, ruled, st, clusters
    )
    @synchronize
    tb = @index(Local, Linear)
    _plan_b!(tb, wg, buf.events, dv, par, ruled, st, clusters)
    @synchronize
    tc = @index(Local, Linear)
    _plan_c!(tc, wg, cnt, buf.events, dv, par, ruled, clusters)
    @synchronize
    td = @index(Local, Linear)
    _plan_d!(td, wg, cnt, tot, buf.events, dv, par, ruled)
    @synchronize
    te = @index(Local, Linear)
    _plan_e!(te, wg, cnt, tot, buf.events, dv, par, round, ruled, st, clusters)
    @synchronize
    tf = @index(Local, Linear)
    _plan_f!(tf, wg, cnt, tot, dv, par)
    @synchronize
    tg = @index(Local, Linear)
    _plan_g!(
        tg, wg, cnt, tot, buf.events, buf.daughter, buf.normals,
        buf.bias, dv, par, fns.normal, fns.cnormal, ruled,
        st, p, ctx, key, mcs, clusters, opt.births
    )
    @synchronize
    th = @index(Local, Linear)
    _plan_h!(th, wg, buf.events, buf.daughter, dv, par, ruled, opt.surf)
    @synchronize
    tp = @index(Local, Linear)
    _each_on!(
        _dpartition_body!, (tp, wg), length(st.ownership),
        (
            dv, par, st.ownership, buf.daughter, buf.normals, buf.bias,
            buf.removed, st.cell, ctx.lattice, fns.owner_changed, st,
        )
    )
    @synchronize
    tq = @index(Local, Linear)
    _each_on!(
        _dcopies_body!, (tq, wg),
        length(buf.events),
        (
            dv, par, buf.events, buf.daughter, buf.removed, cols, links,
            st, ruled, clusters, fns.release, opt.births,
        )
    )
    @synchronize
    tu = @index(Local, Linear)
    _each_on!(
        _drules_body!, (tu, wg),
        length(buf.events),
        (
            dv, par, buf.events, buf.daughter, fns.kind, fns.divide!,
            fns.cluster_divide!, st, p, ctx, key, mcs, ruled,
        )
    )
    @synchronize
    ts = @index(Local, Linear)
    _each_if!(
        _dsurface_body!, (ts, wg), length(st.ownership), opt.surf,
        (dv, par, st.ownership, opt.surf, opt.rel, ctx.lattice, opt.su)
    )
    _each_if!(
        _dcount_zero_body!, (ts, wg), length(buf.events), opt.cc, (dv, par, opt.ccols)
    )
    _each_if!(_deuler_zero_body!, (ts, wg), length(buf.events), opt.eul, (dv, par, opt.eul))
    @synchronize
    tz = @index(Local, Linear)
    _each_on!(
        _dfinalize_body!, (tz, wg), length(buf.events),
        (
            dv, par, buf.daughter, buf.removed, st.cell, opt.surf,
            ctx.lattice, opt.surf === nothing ? nothing : opt.su,
        )
    )
    _each_if!(
        _dcount_body!, (tz, wg), length(st.ownership), opt.cc,
        (dv, par, st.ownership, st.cell.kind, opt.cc, opt.ccols, ctx.lattice)
    )
    _each_if!(
        _deuler_body!, (tz, wg), _euler_anchors(ctx.lattice),
        opt.eul, (dv, par, st.ownership, opt.eul, ctx.lattice)
    )
    @synchronize
    tk = @index(Local, Linear)
    _clusters_each!(
        clusters, _dcluster_mark_body!, (tk, wg), length(buf.events), (dv, par, st.cell)
    )
    @synchronize
    tl = @index(Local, Linear)
    _clusters_each!(
        clusters, _dcluster_root_body!, (tl, wg), length(buf.events),
        (dv, par, st.cell, opt.cvol, opt.csurf)
    )
    @synchronize
    tm = @index(Local, Linear)
    _each_if!(
        _dcluster_volume_body!, (tm, wg), length(buf.events),
        opt.cvol, (dv, par, st.cell, opt.cvol)
    )
    _each_if!(
        _dcluster_surface_body!, (tm, wg), length(st.ownership), opt.csurf,
        (dv, par, st.ownership, st.cell, opt.csurf, opt.rel, ctx.lattice, opt.cu)
    )
    _refresh_each!(
        _dfrozen_body!, (tm, wg), length(st.ownership), opt.refresh, dv, par, st,
        ctx.lattice
    )
    @synchronize
    tr = @index(Local, Linear)
    _refresh_fold!(tr, opt.refresh, dv, par, mcs)
    _each_if!(
        _dcluster_surface_fold_body!, (tr, wg), length(buf.events),
        opt.cu, (dv, par, opt.csurf, opt.cu)
    )
end

"""
Fold the lifecycle planner's statistics and frozen-mask counts into `integ.stats` (and
`integ.nmobile`, and the host mobile-site list): one transfer each on a device, at a host
read point that synchronizes anyway; on the CPU also after every event round (`now`: the
MCS the next sweep runs, `integ.t + 1` there). Warns on the first deferred division of the
run and on divisions deferred for the moment scratch; throws on a cluster event without
cluster state. Every count, the errors included, is reported once (`acc_seen`).
`report = false` (`reinit!`) folds without warning or throwing: the old run's counts are
dropped.
"""
function _fold_lifecycle!(integ; report::Bool = true, now::Int = integ.t)
    lc = integ.lcache
    lc === nothing && return nothing
    D = lc.device
    stats = _stats(integ)
    counted_copy!(stats, D.acc, D.dv.acc)
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
    badtrans = δ(_ACC_BADTRANS)
    D.acc_seen .= D.acc
    if integ.mscratch !== nothing
        counted_copy!(stats, D.mask, D.dv.mask)
        dD = D.mask[1] - D.mask_seen[1]
        dM = D.mask[2] - D.mask_seen[2]
        # the MCS after a refresh at MCS m (m + 1 … now − 1) ran with the old mobile count
        integ.nmobile += Int(dD)
        stats.attempts += Int(dD * (now - 1) - dM)
        stats.refreshes += Int(D.mask[3] - D.mask_seen[3])
        # a site changed: the host mobile-site list (`SequentialCPM`, CPU) follows the mask
        m = integ.ctx.mobility
        D.mask[4] != D.mask_seen[4] && m isa MaskMobility && m.sites !== nothing &&
            _mobile_sites!(m.sites, m.frozen)
        D.mask_seen .= D.mask
    end
    report || return nothing
    large > 0 &&
        @warn "lifecycle: $large division(s) deferred: the dividing cell's second " *
        "moments exceed the planner's moment scratch (Int32 on a backend without 64-bit " *
        "atomics: a cell far larger than any in use); such a cell divides only on a " *
        "backend with 64-bit atomics (CPU, ROCm, CUDA)"
    nocluster > 0 &&
        throw(ArgumentError("lifecycle: EVENT_DIVIDE_CLUSTER needs cluster state \
            (`init_clusters`)"))
    badtrans > 0 && throw(_bad_transition_error(badtrans))
    return nothing
end
