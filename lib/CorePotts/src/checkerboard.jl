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
    c > 0 && Atomix.@atomic claim[c] max won
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

@inline function propose_body!(j, prio, source, claim, wclaim, status, st, f, p, ctx, law, key,
        mcs, color, idbits)
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
                dH = f.delta_H(st, p, prop, ctx)
                temperature = f.temperature(st, p, prop, ctx)
                T = typeof(temperature)
                dH = _effective_dH(f, dH, temperature, st, p, prop, ctx)
                if !isfinite(dH)
                    Atomix.@atomic status[1] |= STATUS_NONFINITE
                elseif accept(law, T(dH), temperature, uniform(T, ra))
                    # random high bits | color-local index: unique and nonzero
                    won = ((rp >> idbits) << idbits) | UInt32(j)
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
        ctx, color, nclear, nthreads)
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
        end
    end
end

struct CheckerboardCache{N, P, S, C, W, B, K1, K2}
    prio::P
    source::S
    claims::NTuple{2, C}
    # write claims; `nothing` without `f.reads`, so the kernels get ghost arguments and
    # compile as if the parameter were absent (P6.0b3: a dead buffer argument cost 3 % on Metal)
    wclaims::NTuple{2, W}
    status::B
    colors::Vector{Color{N}}
    groupsize::Vector{Int}            # per color; 0 = let the backend choose
    order::Vector{Int}
    buffer::Base.RefValue{Int}        # claim buffer the next color uses (always cleared)
    idbits::Int
    propose!::K1
    commit!::K2
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
        zeros_u32(1), Vector{Color{N}}(cs), [_groupsize(backend, ncolorsites(c)) for c in cs],
        collect(1:length(cs)), Ref(1), idbits,
        propose_kernel!(backend), commit_kernel!(backend))
end

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
        pargs = (cache.prio, cache.source, claim, wclaim, cache.status, st, f, p, ctx, law, key, mcs,
            color, cache.idbits)
        cargs = (st, claim, next_claim, wclaim, next_wclaim, cache.prio, cache.source, f, p, ctx, color, ncell, n)
        if g >= n                   # CPU, one workgroup: plain loops (see `_launch`)
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
    return length(order) * 2
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
