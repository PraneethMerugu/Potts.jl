# Block checkerboard (P6.0bl prototype, `CheckerboardCPM(; scheme = :blocks)`; after Sultan et al.,
# arXiv 2312.09317).
#
# Each axis of length L is cut into nb = max(1, L ÷ 2b) blocks of two sub-regions each, the 2nb
# sub-regions of side `base` = L ÷ 2nb or base + 1 (the first L mod 2nb), so a block is about 2b
# wide and a block's 2^d sub-regions are about b wide. A phase
# activates the same sub-region (offset o ∈ {0, 1}^d) in every block. One work item per block
# makes `m` attempts in its active sub-region, one after another: a uniform site of the
# sub-region, a uniform direction, ΔH against the live state, the Metropolis draw, and on
# acceptance the write and `f.commit!` at once. Active sub-regions of two blocks are at least
# b + 1 apart, so with b ≥ read + write no two work items read or write each other's sites. Cells
# are not claimed: per-cell totals change by atomic adds, and a work item reads them as they
# are (another work item's copies to the same cell may be in flight). On a device the outcome
# depends on the timing of the work items (no determinism, user ruling 2026-11-04). The CPU runs
# the work items one after another, so each attempt sees every earlier one, as in
# `SequentialCPM`.
#
# Per MCS: P = 2^d · switches phases, each drawn uniformly from the 2^d offsets (with
# replacement), and m = |box| / switches attempts per work item per phase. An attempt draws a
# site of the box (side base + 1 on an axis with a remainder, else base) at the sub-region's
# start and is skipped when the site is past the sub-region's end, so every site is attempted
# once per MCS on average.

struct BlockLayout{N}
    nblocks::NTuple{N, Int}
    base::NTuple{N, Int}
    rem::NTuple{N, Int}               # sub-regions of side base + 1 on the axis
    box::NTuple{N, Int}
end

function BlockLayout(dims::NTuple{N, Int}, b::Int) where {N}
    nb = ntuple(d -> max(1, dims[d] ÷ (2b)), N)
    base = ntuple(d -> dims[d] ÷ (2nb[d]), N)
    r = ntuple(d -> dims[d] - 2nb[d] * base[d], N)
    return BlockLayout{N}(nb, base, r, ntuple(d -> base[d] + (r[d] > 0), N))
end
boxsize(l::BlockLayout) = prod(l.box)

# the target site of attempt draw `r` of block `blk` in phase offset `ph` (1-based; 0 bits per
# axis of `ph - 1` give o); `(false, x)` when outside the lattice
@inline function block_site(l::BlockLayout{N}, blk::Int, ph::Int, r::UInt32) where {N}
    u = bounded(r, boxsize(l))                           # 0:|box| - 1
    xs = ntuple(Val(N)) do d
        stride = prod(ntuple(e -> e < d ? l.nblocks[e] : 1, Val(N)))
        bstride = prod(ntuple(e -> e < d ? l.box[e] : 1, Val(N)))
        j = 2 * rem(div(blk - 1, stride), l.nblocks[d]) + (((ph - 1) >> (d - 1)) & 1)     # sub-region, 0-based
        ud = rem(div(u, bstride), l.box[d])
        size = l.base[d] + (j < l.rem[d])
        (ud < size, j * l.base[d] + min(j, l.rem[d]) + ud + 1)
    end
    return all(map(first, xs)), map(last, xs)
end

# one attempt (the `propose_body!` checks, then the commit at once)
@inline function block_attempt!(blk, k, st, f, p, ctx, law, key, mcs, layout, ph, lid, tk, cnt, status)
    lat = ctx.lattice
    rd, ra, rs, _ = draw(key, mcs, blk, STREAM_BLOCK, lid)
    inside, x = block_site(layout, blk, ph, rs)
    inside || return nothing
    t = linear_index(lat, x)
    dir = bounded(rd, length(ctx.proposal)) + 1
    inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
    (inside && is_mobile(ctx.mobility, t)) || return nothing
    s = linear_index(lat, y)
    is_mobile(ctx.mobility, s) || return nothing
    a = @inbounds st.σ[t]
    b = @inbounds st.σ[s]
    a == b && return nothing
    prop = Proposal(t, s, x, dir, a, b)
    f.constraint(st, p, prop, ctx) || return nothing
    dH0 = f.delta_H(st, p, prop, ctx)
    temperature = f.temperature(st, p, prop, ctx)
    T = typeof(temperature)
    dH = _effective_dH(f, dH0, temperature, st, p, prop, ctx)
    if !isfinite(dH)
        @inbounds Atomix.@atomic status[1] |= STATUS_NONFINITE     # status has 1 entry
    elseif accept(law, T(dH), temperature, uniform(T, ra))
        # t ≤ nsites: the track and the counts have one writer per site per phase
        tk === nothing || (@inbounds tk.acc[t] += tk.track(st, p, prop, ctx, dH0))
        @inbounds st.σ[t] = b
        f.commit!(st, p, prop, ctx)
        _count!(cnt, :accepted, t)
        _count!(cnt, :committed, t)
    end
    return nothing
end

# draw local index of attempt k (1:m) in the MCS's phase number q (1:P): both < 2^16 (checked)
@inline _block_lid(q, k) = UInt32(q) << 16 | UInt32(k)

@kernel function block_kernel!(st, f, p, ctx, law, key, mcs, layout, ph, m, q, tk, cnt, status)
    blk = @index(Global, Linear)
    for k in 1:m
        block_attempt!(blk, k, st, f, p, ctx, law, key, mcs, layout, ph, _block_lid(q, k), tk, cnt, status)
    end
end

struct BlockCache{N, B, TK, CN, K}
    layout::BlockLayout{N}
    m::Int                            # attempts per work item per phase
    order::Vector{Int}                # the MCS's phase offsets (1:2^N), P of them
    status::B
    track::TK                         # `nothing`, or `(; track, acc)` (acc per site)
    cnt::CN                           # `nothing`, or the per-site counts (`dropped` stays 0)
    kernel::K
    host::Bool                        # CPU: the work items run one after another
end

function BlockCache(backend, lat::Lattice{N}, f::CPMFunction, proposal; block = nothing, switches = 1,
        counts = false) where {N}
    (f.connectivity !== nothing || has_reads(f) || !(f.claims isa typeof(no_claims))) && throw(ArgumentError(
        "CheckerboardCPM(; scheme = :blocks) does not support a whole-cell connectivity veto or `claims`/`reads` hooks"))
    r, w = reach(f.footprint, proposal)
    need = max(r + w, 1)
    b = block === nothing ? need : block
    b >= need || throw(ArgumentError(
        "CheckerboardCPM(; block = $b): the model's copy footprint needs a block of at least $need"))
    # with two or more blocks on an axis, base ≥ b ≥ need (2·nb·b ≤ L), so active sub-regions of
    # two blocks are at least need + 1 apart, across a periodic seam too; one block on an axis has
    # no other block to meet there
    layout = BlockLayout(lat.dims, b)
    nbox = boxsize(layout)
    switches >= 1 && nbox % switches == 0 || throw(ArgumentError(
        "CheckerboardCPM(; switches = $switches): use a divisor of the block's sub-region box, $nbox sites"))
    m = nbox ÷ switches
    P = 2^N * switches
    (m < 2^16 && P < 2^16) || throw(ArgumentError("CheckerboardCPM(; scheme = :blocks): block $b is too large"))
    tk = f.track === nothing ? nothing :
         (; f.track, acc = KernelAbstractions.zeros(backend, track_eltype(f.track), nsites(lat)))
    cnt = counts ? (; accepted = KernelAbstractions.zeros(backend, Int32, nsites(lat)),
        committed = KernelAbstractions.zeros(backend, Int32, nsites(lat)),
        dropped = KernelAbstractions.zeros(backend, Int32, nsites(lat))) : nothing
    return BlockCache(layout, m, zeros(Int, P), KernelAbstractions.zeros(backend, UInt32, 1), tk, cnt,
        block_kernel!(backend), backend isa KernelAbstractions.CPU)
end

nblocks(l::BlockLayout) = prod(l.nblocks)

function checkerboard_mcs!(st, cache::BlockCache{N}, f::F, p, ctx, law::L, key::RNGKey, mcs::Integer) where {N, F, L}
    order = cache.order
    for q in eachindex(order)
        r, _, _, _ = draw(key, mcs, q, STREAM_COLOR_ORDER, 2)
        order[q] = bounded(r, 2^N) + 1
    end
    l, m, n = cache.layout, cache.m, nblocks(cache.layout)
    for (q, ph) in enumerate(order)
        if cache.host
            for blk in 1:n, k in 1:m
                block_attempt!(blk, k, st, f, p, ctx, law, key, mcs, l, ph, _block_lid(q, k), cache.track,
                    cache.cnt, cache.status)
            end
        else
            cache.kernel(st, f, p, ctx, law, key, mcs, l, ph, m, q, cache.track, cache.cnt, cache.status; ndrange = n)
        end
    end
    return length(order)
end

_fold_track!(stats, cache::BlockCache) = _fold_track!(stats, cache.track)
_fold_counts!(stats, cache::BlockCache) = _fold_counts!(stats, cache.cnt)
