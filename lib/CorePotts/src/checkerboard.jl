# Checkerboard dynamics (KernelAbstractions; CPU or GPU).
#
# Coloring. With stride s = read + write + 1 (`reach(footprint, proposal)`), a site's color is its
# residue class along every axis. On a periodic axis whose length is not a multiple of s
# the last (n mod s) columns form extra singleton classes, so no two same-color sites are
# closer than s across the seam. Each color is enumerated by a per-axis (start, step,
# count) triple.

struct Color{N}
    start::NTuple{N, Int}
    step::NTuple{N, Int}
    count::NTuple{N, Int}
end

function _axis_classes(n::Int, s::Int, periodic::Bool)
    s >= n && return [(k, 1, 1) for k in 1:n]           # every column its own class
    if !periodic || n % s == 0
        return [(a, s, cld(n - a + 1, s)) for a in 1:s]
    end
    q = n ÷ s
    main = [(a, s, q) for a in 1:s]
    tail = [(s * q + t, 1, 1) for t in 1:(n - s * q)]
    return vcat(main, tail)
end

function colors(l::Lattice{N}, s::Int) where {N}
    per_axis = ntuple(d -> _axis_classes(l.dims[d], s, l.periodic[d]), N)
    return [Color{N}(ntuple(d -> c[d][1], N), ntuple(d -> c[d][2], N),
                ntuple(d -> c[d][3], N))
            for c in Iterators.product(per_axis...)] |> vec
end

@inline function color_site(c::Color{N}, j::Int) where {N}
    # no captured mutable state in the closure (it would be boxed)
    return ntuple(Val(N)) do d
        stride = prod(ntuple(e -> e < d ? c.count[e] : 1, Val(N)))
        c.start[d] + rem(div(j - 1, stride), c.count[d]) * c.step[d]
    end
end
ncolorsites(c::Color) = prod(c.count)

@inline function _claim!(claim, c::Int32, won::UInt32)
    c > 0 && @inbounds Atomix.@atomic claim[c] max won      # 0 < c ≤ capacity = length(claim)
    return nothing
end
@inline _won(claim, c::Int32, won::UInt32) = c <= 0 || @inbounds(claim[c]) == won
# a shared read of `c` survives unless a higher-priority copy writes `c`
@inline _unwritten(wclaim, c::Int32, won::UInt32) = c <= 0 || @inbounds(wclaim[c]) <= won

# Claims. Every cell a copy touches (old, new, `f.claims`, `f.reads`) takes `claim[c] max won`;
# the cells it writes (old, new, `f.claims`) also take `wclaim[c] max won`. A copy commits
# if it has the top priority on every cell it writes and no higher-priority copy writes a
# cell it reads, so two committed copies never write the same cell nor one read what the
# other writes, while readers share. Without `f.reads`, `wclaim` is never touched.
#
# Track (D-140): `tk` is `nothing` (no track) or `(; track, dH, acc)`. An accepted proposal
# writes its tracked value into `dH[j]`; a committing copy adds it into `acc[t]` (one target
# per site per colour: no atomics, nothing zeroed per colour). The host reduces `acc` only at
# read points (`_fold_track!`). Without a track the kernels are the untracked ones
# (`propose_kernel!`, `commit_kernel!`): no `tk` argument at all, the same code as before the
# track existed.

@inline function propose_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key,
        mcs, color, idbits, tk = nothing)
    lat = ctx.lattice
    x = color_site(color, j)
    t = linear_index(lat, x)
    rd, ra, rp, _ = draw(key, mcs, t, STREAM_PROPOSAL)
    dir = bounded(rd, length(ctx.proposal)) + 1
    inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
    won = UInt32(0)
    s = 0
    if inside && is_mobile(ctx.mobility, t) && is_mobile(ctx.mobility, linear_index(lat, y))
        s = linear_index(lat, y)
        a = @inbounds st.σ[t]
        b = @inbounds st.σ[s]
        if a != b
            prop = Proposal(t, s, x, dir, a, b)
            if f.constraint(st, p, prop, ctx)
                dH0 = f.delta_H(st, p, prop, ctx)
                temperature = f.temperature(st, p, prop, ctx)
                T = typeof(temperature)
                dH = _effective_dH(f, dH0, temperature, st, p, prop, ctx)
                if !isfinite(dH)
                    @inbounds Atomix.@atomic status[1] |= STATUS_NONFINITE     # status has 1 entry
                elseif accept(law, T(dH), temperature, uniform(T, ra))
                    # random high bits | color-local index: unique and nonzero
                    won = ((rp >> idbits) << idbits) | (j % UInt32)          # j ≤ ncolorsites < 2^idbits
                    # j ≤ ncolorsites ≤ maxsites = length(tk.dH)
                    tk === nothing || (@inbounds tk.dH[j] = tk.track(st, p, prop, ctx, dH0))
                    _claim!(claim, a, won)
                    _claim!(claim, b, won)
                    writes = f.claims(st, p, prop, ctx)
                    for c in writes
                        _claim!(claim, Int32(c), won)
                    end
                    if has_reads(f)
                        _claim!(wclaim, a, won)
                        _claim!(wclaim, b, won)
                        for c in writes
                            _claim!(wclaim, Int32(c), won)
                        end
                        for c in f.reads(st, p, prop, ctx)
                            _claim!(claim, Int32(c), won)
                        end
                    end
                end
            end
        end
    end
    @inbounds prio[j] = won
    @inbounds source[j] = s
end

@inline function commit_body!(j, st, claim, next_claim, wclaim, next_wclaim, prio, source, f, p,
        ctx, color, nclear, nthreads, tk = nothing)
    c = j
    while c <= nclear                     # clear the other claim buffers for the next color
        @inbounds next_claim[c] = UInt32(0)
        has_reads(f) && (@inbounds next_wclaim[c] = UInt32(0))
        c += nthreads
    end
    won = @inbounds prio[j]
    if won != 0
        lat = ctx.lattice
        x = color_site(color, j)
        t = linear_index(lat, x)
        s = @inbounds source[j]
        a = @inbounds st.σ[t]
        b = @inbounds st.σ[s]
        prop = Proposal(t, s, x, 0, a, b)
        ok = _won(claim, a, won) && _won(claim, b, won)
        for extra in f.claims(st, p, prop, ctx)
            ok &= _won(claim, Int32(extra), won)
        end
        if has_reads(f)
            for r in f.reads(st, p, prop, ctx)
                ok &= _unwritten(wclaim, Int32(r), won)
            end
        end
        if ok
            @inbounds st.σ[t] = b
            f.commit!(st, p, prop, ctx)
            # t ≤ nsites = length(tk.acc); dH[j] was written by this proposal (won ≠ 0)
            tk === nothing || (@inbounds tk.acc[t] += tk.dH[j])
        end
    end
end

struct CheckerboardCache{N, P, S, C, W, B, TK, K1, K2, CO}
    prio::P
    source::S
    claims::NTuple{2, C}
    # write claims; `nothing` without `f.reads`, so the kernels get ghost (zero-size)
    # arguments instead of dead buffers (P6.0b3: two dead buffer arguments cost 3 % on Metal)
    wclaims::NTuple{2, W}
    status::B
    # track buffers (D-140): `nothing` without `f.track`, else `(; dH, acc)`: the per-colour
    # scratch (maxsites) and the per-site accumulator (nsites), in the track's scalar type
    track::TK
    colors::Vector{Color{N}}
    groupsize::Vector{Int}            # per color; 0 = let the backend choose
    order::Vector{Int}
    buffer::Base.RefValue{Int}        # claim buffer the next color uses (always cleared)
    idbits::Int
    propose!::K1
    commit!::K2
    # whole-cell connectivity (P6.9a): `nothing`, or the lists, counter and kernels of
    # `ConnBuffers`; without it the colour loop is exactly the one above
    conn::CO
end

# Dedicated kernels for the hot path (`@Const` marks read-only buffers for the device).
@kernel function propose_kernel!(prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits)
    j = @index(Global, Linear)
    propose_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits)
end
@kernel function commit_kernel!(st, claim, next_claim, wclaim, next_wclaim, @Const(prio), @Const(source), f, p, ctx,
        color, nclear, nthreads)
    j = @index(Global, Linear)
    commit_body!(j, st, claim, next_claim, wclaim, next_wclaim, prio, source, f, p, ctx, color, nclear, nthreads)
end
# the tracked kernels (D-140): the same bodies with the track buffers
@kernel function propose_track_kernel!(prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits, tk)
    j = @index(Global, Linear)
    propose_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits, tk)
end
@kernel function commit_track_kernel!(st, claim, next_claim, wclaim, next_wclaim, @Const(prio), @Const(source), f, p, ctx,
        color, nclear, nthreads, tk)
    j = @index(Global, Linear)
    commit_body!(j, st, claim, next_claim, wclaim, next_wclaim, prio, source, f, p, ctx, color, nclear, nthreads, tk)
end

function CheckerboardCache(backend, lat::Lattice{N}, f::CPMFunction, ncell::Int,
        proposal = relation(VonNeumann(1), lat)) where {N}
    r, w = reach(f.footprint, proposal)
    s = r + w + 1
    cs = colors(lat, s)
    maxsites = maximum(ncolorsites, cs)
    idbits = max(1, ceil(Int, log2(maxsites + 1)))
    idbits <= 24 || throw(ArgumentError(
        "a color class has $maxsites sites; 32-bit claim priorities support at most 2^24"))
    zeros_u32(n) = KernelAbstractions.zeros(backend, UInt32, n)
    return CheckerboardCache(zeros_u32(maxsites),
        KernelAbstractions.zeros(backend, Int, maxsites),
        (zeros_u32(max(ncell, 1)), zeros_u32(max(ncell, 1))),
        has_reads(f) ? (zeros_u32(max(ncell, 1)), zeros_u32(max(ncell, 1))) : (nothing, nothing),
        zeros_u32(1), _track_buffers(backend, f.track, maxsites, nsites(lat)), Vector{Color{N}}(cs), [_groupsize(backend, ncolorsites(c)) for c in cs],
        collect(1:length(cs)), Ref(1), idbits, _kernels(backend, f.track)...,
        _conn_buffers(backend, f.connectivity, maxsites))
end

_track_buffers(backend, ::Nothing, maxsites, n) = nothing
function _track_buffers(backend, track, maxsites, n)
    T = track_eltype(track)
    return (; track, dH = KernelAbstractions.zeros(backend, T, maxsites), acc = KernelAbstractions.zeros(backend, T, n))
end
_kernels(backend, ::Nothing) = (propose_kernel!(backend), commit_kernel!(backend))
_kernels(backend, track) = (propose_track_kernel!(backend), commit_track_kernel!(backend))
# kernel arguments: the track buffers are appended only when tracking (type-level)
_with_track(args, ::Nothing) = args
_with_track(args, tk) = (args..., tk)

# On the CPU backend every workgroup beyond the first is a spawned task. Small colors run
# inline as one workgroup; large ones split into one workgroup per thread of at least
# CPU_GRAIN sites. (Multithreaded launches of ~1000 sites were 6× slower than inline.)
const CPU_GRAIN = 8192
_groupsize(backend, n) = 0
_groupsize(::KernelAbstractions.CPU, n) = max(cld(n, Threads.nthreads()), min(n, CPU_GRAIN))

function checkerboard_mcs!(st, cache::CheckerboardCache, f::F, p, ctx, law::L,
        key::RNGKey, mcs::Integer) where {F, L}
    ncell = length(cache.claims[1])
    order = _color_order!(cache.order, key, mcs)
    buf = cache.buffer[]
    for ci in order
        color = cache.colors[ci]
        n = ncolorsites(color)
        claim, next_claim = cache.claims[buf], cache.claims[3 - buf]
        wclaim, next_wclaim = cache.wclaims[buf], cache.wclaims[3 - buf]
        g = cache.groupsize[ci]
        pargs = _with_track((cache.prio, cache.source, claim, wclaim, cache.status, st, f, p, ctx, law, key, mcs,
            color, cache.idbits), cache.track)
        cargs = _with_track((st, claim, next_claim, wclaim, next_wclaim, cache.prio, cache.source, f, p, ctx, color, ncell, n),
            cache.track)
        if cache.conn !== nothing           # whole-cell connectivity (a type-level branch)
            _conn_color!(cache.conn, g, n, (cache.prio, cache.source, claim, wclaim, cache.status, st, f, p, ctx, law,
                key, mcs, color, cache.idbits, cache.track), (st, claim, next_claim, wclaim, next_wclaim, cache.prio,
                cache.source, f, p, ctx, color, ncell, n, cache.track))
        elseif g >= n                   # CPU, one workgroup: plain loops (see `_launch`)
            for j in 1:n
                propose_body!(j, pargs...)
            end
            for j in 1:n
                commit_body!(j, cargs...)
            end
        else
            workgroupsize = g == 0 ? nothing : g
            cache.propose!(pargs...; ndrange = n, workgroupsize)
            cache.commit!(cargs...; ndrange = n, workgroupsize)
        end
        buf = 3 - buf
    end
    # the next color's buffer was cleared by the last commit; with an odd number of colors
    # that is not buffer 1, so the parity persists across MCS
    cache.buffer[] = buf
    return length(order) * _conn_launches(cache.conn)
end

function _color_order!(order, key::RNGKey, mcs::Integer)
    n = length(order)
    order .= 1:n
    for i in n:-1:2
        r, _, _, _ = draw(key, mcs, i, STREAM_COLOR_ORDER)
        j = bounded(r, i) + 1
        order[i], order[j] = order[j], order[i]
    end
    return order
end

# ---------------------------------------------------------------------------------------
# Whole-cell connectivity on the checkerboard (P6.9a, D-075 Q6)
#
# Per colour, between the propose and commit kernels:
#  - the copies that need the exact floods (`f.defer`: cell-scope `pieces`, an inline
#    `Global` without window) are listed by the propose kernel and run in list order by one
#    work item over the flood scratch (`serial_conn_kernel!`; a host loop on the CPU). They
#    read only cells no other copy of the colour writes (the claims), so σ is as at propose;
#  - the accepted copies whose `Global` local test fails are compacted into a list (an
#    atomic counter) instead of claiming. The deferred kernel searches each one (in its
#    window: an `MVector` stack and visited bits, no allocation), raises its claims if it
#    passes, so the commit is unchanged, and counts a refusal for want of window in
#    `deferred` (read into `stats.connectivity_deferred` at host read points). A veto
#    without window searches exactly over the flood scratch: the list then runs in order
#    on one work item (`global_serial_kernel!`).
# The commit kernel resets both counters. Extra launches per colour: one per list the model
# has (`_conn_launches`), so 4 per MCS in 2D (4 colours) for a `Global` veto.

struct ConnBuffers{G, K1, K2, K3, K4, K5}
    gl::G               # (; glist, gcount, slist, scount, deferred)
    host::Bool          # the CPU backend: the lists run as host loops
    post::Bool          # the model has a `Global` veto (the deferred list)
    exact::Bool         # some veto has no window: the deferred list runs serially
    defer::Bool         # the model defers copies to the serial floods (the serial list)
    propose!::K1
    serial!::K2
    global!::K3
    global_serial!::K4
    commit!::K5
end

_conn_buffers(backend, ::Nothing, maxsites) = nothing
function _conn_buffers(backend, h::ConnectivityHooks, maxsites)
    z(T, n) = KernelAbstractions.zeros(backend, T, n)
    gl = (; glist = z(Int32, maxsites), gcount = z(UInt32, 1), slist = z(Int32, maxsites), scount = z(UInt32, 1),
        deferred = z(UInt32, 1))
    return ConnBuffers(gl, backend isa KernelAbstractions.CPU, h.post !== nothing, h.exact_veto, h.defer !== nothing,
        propose_conn_kernel!(backend), serial_conn_kernel!(backend), global_conn_kernel!(backend),
        global_serial_kernel!(backend), commit_conn_kernel!(backend))
end

_conn_launches(::Nothing) = 2
_conn_launches(c::ConnBuffers) = 2 + c.post + c.defer

# the claims of an accepted copy (as `propose_body!`)
@inline function _raise_claims!(claim, wclaim, st, f, p, prop, ctx, won)
    a, b = prop.old, prop.new
    _claim!(claim, a, won)
    _claim!(claim, b, won)
    writes = f.claims(st, p, prop, ctx)
    for c in writes
        _claim!(claim, Int32(c), won)
    end
    if has_reads(f)
        _claim!(wclaim, a, won)
        _claim!(wclaim, b, won)
        for c in writes
            _claim!(wclaim, Int32(c), won)
        end
        for c in f.reads(st, p, prop, ctx)
            _claim!(claim, Int32(c), won)
        end
    end
    return nothing
end

# append colour index `j` to a list (each j at most once per colour: count ≤ maxsites = length)
@inline function _push_list!(list, count, j)
    i = Atomix.@atomic count[1] += UInt32(1)        # count has one entry
    @inbounds list[i] = Int32(j)
    return nothing
end

# `propose_body!` with the connectivity hooks: `SERIAL = false` in the propose kernel (copies
# that need the floods are listed, the veto runs its local test and lists undecided copies),
# `true` in the serial kernel (the floods run, the veto decides at once)
@inline function propose_conn_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key,
        mcs, color, idbits, tk, gl, ::Val{SERIAL}) where {SERIAL}
    lat = ctx.lattice
    x = color_site(color, j)
    t = linear_index(lat, x)
    rd, ra, rp, _ = draw(key, mcs, t, STREAM_PROPOSAL)
    dir = bounded(rd, length(ctx.proposal)) + 1
    inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
    won = UInt32(0)
    s = 0
    if inside && is_mobile(ctx.mobility, t) && is_mobile(ctx.mobility, linear_index(lat, y))
        s = linear_index(lat, y)
        a = @inbounds st.σ[t]
        b = @inbounds st.σ[s]
        if a != b
            prop = Proposal(t, s, x, dir, a, b)
            if !SERIAL && has_defer(f) && _defer(f)(st, p, prop, ctx)
                _push_list!(gl.slist, gl.scount, j)                     # the serial kernel runs it
            elseif f.constraint(st, p, prop, ctx)
                dH0 = f.delta_H(st, p, prop, ctx)
                temperature = f.temperature(st, p, prop, ctx)
                T = typeof(temperature)
                dH = _effective_dH(f, dH0, temperature, st, p, prop, ctx)
                if !isfinite(dH)
                    @inbounds Atomix.@atomic status[1] |= STATUS_NONFINITE     # status has 1 entry
                elseif accept(law, T(dH), temperature, uniform(T, ra))
                    won = ((rp >> idbits) << idbits) | (j % UInt32)          # as `propose_body!`
                    code = has_post(f) ? _post(f)(st, p, prop, ctx, SERIAL ? GlobalSearch() : GlobalLocal()) : GLOBAL_PASS
                    if code == GLOBAL_PASS || (code == GLOBAL_WINDOW && !SERIAL)
                        # j ≤ ncolorsites ≤ maxsites = length(tk.dH)
                        tk === nothing || (@inbounds tk.dH[j] = tk.track(st, p, prop, ctx, dH0))
                        if code == GLOBAL_PASS
                            _raise_claims!(claim, wclaim, st, f, p, prop, ctx, won)
                        else
                            _push_list!(gl.glist, gl.gcount, j)           # the deferred kernel decides
                        end
                    else
                        code == GLOBAL_WINDOW && Atomix.@atomic gl.deferred[1] += UInt32(1)
                        won = UInt32(0)
                    end
                end
            end
        end
    end
    @inbounds prio[j] = won
    @inbounds source[j] = s
end

# the deferred `Global` search of list entry `i` (its copy was accepted with priority prio[j])
@inline function global_deferred_body!(i, prio, source, claim, wclaim, st, f, p, ctx, color, gl)
    j = Int(@inbounds gl.glist[i])                   # i ≤ gcount ≤ maxsites
    won = @inbounds prio[j]
    lat = ctx.lattice
    x = color_site(color, j)
    t = linear_index(lat, x)
    s = @inbounds source[j]
    prop = Proposal(t, s, x, 0, @inbounds(st.σ[t]), @inbounds(st.σ[s]))
    code = _post(f)(st, p, prop, ctx, GlobalSearch())
    if code == GLOBAL_PASS
        _raise_claims!(claim, wclaim, st, f, p, prop, ctx, won)
    else
        code == GLOBAL_WINDOW && Atomix.@atomic gl.deferred[1] += UInt32(1)
        @inbounds prio[j] = UInt32(0)
    end
    return nothing
end

@kernel function propose_conn_kernel!(prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits, tk, gl)
    j = @index(Global, Linear)
    propose_conn_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits, tk, gl, Val(false))
end
# one work item: the listed copies in list order, over the flood scratch
@kernel function serial_conn_kernel!(prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits, tk, gl)
    _ = @index(Global, Linear)
    for i in 1:Int(@inbounds gl.scount[1])
        propose_conn_body!(Int(@inbounds gl.slist[i]), prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs,
            color, idbits, tk, gl, Val(true))
    end
end
@kernel function global_conn_kernel!(prio, @Const(source), claim, wclaim, st, f, p, ctx, color, gl)
    i = @index(Global, Linear)
    if i <= Int(@inbounds gl.gcount[1])
        global_deferred_body!(i, prio, source, claim, wclaim, st, f, p, ctx, color, gl)
    end
end
# one work item: the deferred list in order (a veto without window: the exact search)
@kernel function global_serial_kernel!(prio, @Const(source), claim, wclaim, st, f, p, ctx, color, gl)
    _ = @index(Global, Linear)
    for i in 1:Int(@inbounds gl.gcount[1])
        global_deferred_body!(i, prio, source, claim, wclaim, st, f, p, ctx, color, gl)
    end
end
@kernel function commit_conn_kernel!(st, claim, next_claim, wclaim, next_wclaim, @Const(prio), @Const(source), f, p, ctx,
        color, nclear, nthreads, tk, gl)
    j = @index(Global, Linear)
    commit_body!(j, st, claim, next_claim, wclaim, next_wclaim, prio, source, f, p, ctx, color, nclear, nthreads, tk)
    if j == 1                                        # the lists were consumed: empty them
        @inbounds gl.gcount[1] = UInt32(0)
        @inbounds gl.scount[1] = UInt32(0)
    end
end

# One colour with the connectivity hooks: propose, the serial list, the deferred list, commit.
function _conn_color!(c::ConnBuffers, g, n, pargs, cargs)
    gl = c.gl
    prio, source, claim, wclaim, status, st, f, p, ctx, law, key, mcs, color, idbits, tk = pargs
    if g >= n
        for j in 1:n
            propose_conn_body!(j, pargs..., gl, Val(false))
        end
    else
        c.propose!(pargs..., gl; ndrange = n, workgroupsize = g == 0 ? nothing : g)
    end
    if c.defer
        if c.host
            for i in 1:Int(gl.scount[1])
                propose_conn_body!(Int(gl.slist[i]), pargs..., gl, Val(true))
            end
        else
            c.serial!(pargs..., gl; ndrange = 1, workgroupsize = 1)
        end
    end
    if c.post
        if c.host
            for i in 1:Int(gl.gcount[1])
                global_deferred_body!(i, prio, source, claim, wclaim, st, f, p, ctx, color, gl)
            end
        elseif c.exact
            c.global_serial!(prio, source, claim, wclaim, st, f, p, ctx, color, gl; ndrange = 1, workgroupsize = 1)
        else
            c.global!(prio, source, claim, wclaim, st, f, p, ctx, color, gl; ndrange = n)
        end
    end
    if g >= n
        for j in 1:n
            commit_body!(j, cargs...)
        end
        gl.gcount[1] = UInt32(0)
        gl.scount[1] = UInt32(0)
    else
        c.commit!(cargs..., gl; ndrange = n, workgroupsize = g == 0 ? nothing : g)
    end
    return nothing
end

# Read point of the deferred-refusal counter: added into `stats.connectivity_deferred` and
# zeroed (one counted copy on a device).
_fold_deferred!(integ) = _fold_deferred!(integ.stats, integ.cache)
_fold_deferred!(stats, cache) = nothing
_fold_deferred!(stats, cache::CheckerboardCache) = _fold_deferred!(stats, cache.conn)
_fold_deferred!(stats, ::Nothing) = nothing
function _fold_deferred!(stats, c::ConnBuffers)
    d = c.gl.deferred
    h = _ondevice(d) ? _to_host(stats, d) : d
    stats.connectivity_deferred === nothing || (stats.connectivity_deferred += Int(h[1]))
    fill!(d, UInt32(0))
    return nothing
end
