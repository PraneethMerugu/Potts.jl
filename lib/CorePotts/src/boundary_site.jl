# Boundary-site dynamics on the host (`SequentialCPM(; skip_interior = true)`, D-177, D-198): `SequentialCPM`'s chain with
# the null picks outside the boundary set skipped exactly.
#
# The boundary set B is the set of mobile sites t with an offset o of the proposal such that
# s = t + o is on the lattice, mobile, and σ[s] ≠ σ[t]. A `SequentialCPM` attempt whose
# target lies outside B is a null move (off-lattice, frozen source or like owner). With
# n = |B| of the N mobile sites, the attempts up to and including the next one in B number
# G + 1, G geometric with success probability n/N, and that target is uniform in B; nothing
# changes in between, so drawing G at once and then a uniform site of B gives the same law.
# A run that would pass the MCS's N attempts ends the sweep (the rest are null; memoryless,
# so the next MCS draws afresh).
#
# B is kept incrementally: a dense list with positions, the number of unlike mobile proposal
# neighbours of every site (`unlike`; t ∈ B iff t is mobile and unlike[t] > 0), and host
# shadows of σ and of the frozen mask. A committed copy t: a → b changes `unlike` only at t
# (recounted) and at the sites whose proposal reaches t (the reversed offsets; ±1 each).
# Every other writer (lifecycle events, `reinit!`, a callback, `u_modified!` /
# `refresh_frozen!`) is caught by comparing σ and the mask against the shadows at the start
# of each sweep and at every read of B (`_boundary_sites`): a site that differs is recounted
# with the sites that read it. The comparison is one pass over two arrays (O(N) per MCS,
# about 0.25 ms on 1400²); quiet sites cost nothing else.

mutable struct BoundaryCache{N, K, FZ}
    const list::Vector{Int32}       # B in `list[1:n]`, any order
    const pos::Vector{Int32}        # position in `list`, 0 outside B
    const unlike::Vector{Int32}     # on-lattice mobile proposal neighbours of another owner
    const σ0::Vector{Int32}         # σ as B last saw it
    const frozen0::FZ               # the frozen mask as B last saw it (`nothing`: all mobile)
    const rev::NTuple{K, NTuple{N, Int32}}  # negated proposal offsets: the sites that read a site
    n::Int
    nq::Int                         # the `n` and the `N` of the cached `lq` (-1: none)
    Nq::Int
    lq::Float64                     # log(1 - n/N) for the geometric skip
end

function BoundaryCache(σ, mob, lat::Lattice{N}, proposal::Relation{N, K}) where {N, K}
    m = length(σ)
    rev = map(o -> map(-, o), proposal.offsets)
    B = BoundaryCache{N, K, _shadow_type(mob)}(zeros(Int32, m), zeros(Int32, m), zeros(Int32, m),
        zeros(Int32, m), _shadow_mask(mob, m), rev, 0, -1, -1, 0.0)
    _rebuild_boundary!(B, σ, mob, lat, proposal.offsets)
    return B
end
_shadow_type(::AllMobile) = Nothing
_shadow_type(::MaskMobility) = Vector{Bool}
_shadow_mask(::AllMobile, m) = nothing
_shadow_mask(::MaskMobility, m) = zeros(Bool, m)

"""The number of on-lattice mobile proposal neighbours of site `u` (coordinates `x`) owned
by another cell than `u`'s."""
@inline function _unlike(σ, mob, lat, offsets, u::Int, x)
    a = @inbounds σ[u]                      # u ∈ 1:length(σ)
    c = Int32(0)
    for o in offsets
        inside, y = shift(lat, x, o)
        inside || continue
        s = linear_index(lat, y)            # on the lattice
        c += (is_mobile(mob, s) && @inbounds(σ[s]) != a) % Int32
    end
    return c
end

@inline function _set_boundary!(B::BoundaryCache, u::Int, member::Bool)
    k = @inbounds B.pos[u]                  # u ∈ 1:length(pos); list entries are sites
    if member && k == 0
        n = B.n += 1
        @inbounds B.list[n] = u
        @inbounds B.pos[u] = n
    elseif !member && k != 0
        n = B.n
        last = @inbounds B.list[n]
        @inbounds B.list[k] = last
        @inbounds B.pos[last] = k
        @inbounds B.pos[u] = 0
        B.n = n - 1
    end
    return nothing
end
@inline _recount!(B::BoundaryCache, σ, mob, lat, offsets, u::Int, x) =
    (c = _unlike(σ, mob, lat, offsets, u, x); @inbounds B.unlike[u] = c; _set_boundary!(B, u, c > 0 && is_mobile(mob, u)))

# The committed copy t: a → b (t mobile, nothing else changed): t is recounted, and every
# site u whose proposal reaches t gains or loses one unlike neighbour.
@inline function _copied!(B::BoundaryCache, σ, mob, lat, offsets, t::Int, x, a, b)
    _recount!(B, σ, mob, lat, offsets, t, x)
    for r in B.rev
        inside, y = shift(lat, x, r)
        inside || continue
        u = linear_index(lat, y)
        u == t && continue                  # an origin offset: recounted above
        c = @inbounds σ[u]
        d = (c != b) % Int32 - (c != a) % Int32
        d == 0 && continue
        k = @inbounds(B.unlike[u]) + d      # u ∈ 1:length(σ)
        @inbounds B.unlike[u] = k
        _set_boundary!(B, u, k > 0 && is_mobile(mob, u))
    end
    return nothing
end

# Site t changed owner or mobility, perhaps with others at once: it and the sites that read
# it are recounted from σ.
@inline function _touch_boundary!(B::BoundaryCache, σ, mob, lat, offsets, t::Int, x)
    _recount!(B, σ, mob, lat, offsets, t, x)
    for r in B.rev
        inside, y = shift(lat, x, r)
        inside || continue
        u = linear_index(lat, y)
        _recount!(B, σ, mob, lat, offsets, u, y)
    end
    return nothing
end

function _rebuild_boundary!(B::BoundaryCache, σ, mob, lat, offsets)
    fill!(B.pos, Int32(0))
    B.n = 0
    for u in eachindex(B.σ0)
        _recount!(B, σ, mob, lat, offsets, u, coordinates(lat, u))
    end
    copyto!(B.σ0, vec(σ))
    _copy_mask!(B.frozen0, mob)
    return B
end
_copy_mask!(::Nothing, mob) = nothing
_copy_mask!(f0, mob::MaskMobility) = (copyto!(f0, vec(mob.frozen)); nothing)

# Bring B up to the current σ and mask: blocks of 64 sites are compared branch-free, and only
# a block that differs is visited site by site.
function _sync_boundary!(B::BoundaryCache, σ, mob, lat, offsets)
    σ0 = B.σ0
    m = length(σ0)
    for lo in 1:64:m
        hi = min(lo + 63, m)
        _block_changed(σ, σ0, B.frozen0, mob, lo, hi) || continue
        for i in lo:hi
            (@inbounds(σ[i]) != @inbounds(σ0[i]) || _mask_changed(B.frozen0, mob, i)) || continue
            @inbounds σ0[i] = σ[i]          # i ∈ lo:hi ⊆ 1:m, both of length m
            _note_mask!(B.frozen0, mob, i)
            _touch_boundary!(B, σ, mob, lat, offsets, i, coordinates(lat, i))
        end
    end
    return B
end
@inline function _block_changed(σ, σ0, f0, mob, lo, hi)
    d = false
    @simd for i in lo:hi
        d |= @inbounds(σ[i]) != @inbounds(σ0[i])            # lo:hi ⊆ 1:length(σ0) = 1:length(σ)
    end
    return d || _block_mask_changed(f0, mob, lo, hi)
end
@inline _block_mask_changed(::Nothing, mob, lo, hi) = false
@inline function _block_mask_changed(f0, mob::MaskMobility, lo, hi)
    d = false
    fz = mob.frozen
    @simd for i in lo:hi
        d |= @inbounds(fz[i]) != @inbounds(f0[i])           # the mask has the lattice's size
    end
    return d
end
@inline _mask_changed(::Nothing, mob, i) = false
@inline _mask_changed(f0, mob::MaskMobility, i) = @inbounds(mob.frozen[i]) != @inbounds(f0[i])
@inline _note_mask!(::Nothing, mob, i) = nothing
@inline _note_mask!(f0, mob::MaskMobility, i) = (@inbounds f0[i] = mob.frozen[i]; nothing)

# log(1 - n/N) of the geometric skip, cached for the pair (n, N): a mask change can move N
# (the mobile count) and leave n as it was
@inline function _skip_lq!(B::BoundaryCache, n::Int, N::Int)
    (n == B.nq && N == B.Nq) || (B.nq = n; B.Nq = N; B.lq = log1p(-n / N))
    return B.lq
end

"""
    _boundary_sites(integ)

The integrator's current boundary set (linear site indices, any order, each once), brought
up to date with its state. For tests; `integ.alg` must be `SequentialCPM(; skip_interior = true)`.
"""
function _boundary_sites(integ)
    B = integ.cache
    B isa BoundaryCache || throw(ArgumentError("_boundary_sites: the integrator runs $(integ.alg), not SequentialCPM(; skip_interior = true)"))
    _sync_boundary!(B, integ.state.σ, integ.ctx.mobility, integ.ctx.lattice, integ.ctx.proposal.offsets)
    return view(B.list, 1:B.n)
end

# Returns `(accepted, status, tracked)`, as `sequential_mcs!`. RNG: draw `j` of the MCS (the
# j-th boundary pick) gives the skip, the site in B, the direction and the acceptance.
function boundary_site_mcs!(st, f::F, p, ctx, law::L, key::RNGKey, mcs::Integer, B::BoundaryCache,
        track::TK = nothing) where {F, L, TK}
    σ = st.σ
    lat = ctx.lattice
    mob = ctx.mobility
    offsets = ctx.proposal.offsets
    nsite = nmobile(mob, lat)
    K = length(ctx.proposal)
    _sync_boundary!(B, σ, mob, lat, offsets)
    accepted = 0
    tracked = track === nothing ? nothing : 0.0
    attempts = 0                            # attempts of this MCS used so far (null skips included)
    j = 0
    while true
        n = B.n
        n == 0 && break
        j += 1
        rg, rt, rd, ra = draw(key, mcs, j, STREAM_BOUNDARY_SITE)
        if n < nsite
            g = log(uniform(Float64, rg)) / _skip_lq!(B, n, nsite)     # the null attempts before this one
            g < nsite - attempts || break
            attempts += unsafe_trunc(Int, g) + 1             # 0 ≤ g < nsite - attempts
        else
            attempts < nsite || break
            attempts += 1
        end
        t = Int(@inbounds B.list[bounded(rt, n) + 1])      # bounded(·, n) ∈ 0:n-1
        x = coordinates(lat, t)
        dir = bounded(rd, K) + 1
        inside, y = shift(lat, x, @inbounds offsets[dir])
        inside || continue
        s = linear_index(lat, y)
        is_mobile(mob, s) || continue
        a = @inbounds σ[t]
        b = @inbounds σ[s]
        a == b && continue
        prop = Proposal(t, s, x, dir, a, b)
        f.constraint(st, p, prop, ctx) || continue
        dH0 = f.delta_H(st, p, prop, ctx)
        temperature = f.temperature(st, p, prop, ctx)
        T = typeof(temperature)
        dH = _effective_dH(f, dH0, temperature, st, p, prop, ctx)
        isfinite(dH) || return accepted, STATUS_NONFINITE, tracked
        if accept(law, T(dH), temperature, uniform(T, ra))
            # the whole-cell veto (`Global`, P6.9a) after the draw: the same trajectory as
            # before ΔH, at a fraction of the cost (no code without it)
            has_post(f) && _post(f)(st, p, prop, ctx, GlobalSearch()) != GLOBAL_PASS && continue
            track === nothing || (tracked += Float64(track(st, p, prop, ctx, dH0)))
            @inbounds σ[t] = b
            f.commit!(st, p, prop, ctx)
            @inbounds B.σ0[t] = b
            _copied!(B, σ, mob, lat, offsets, t, x, a, b)
            accepted += 1
        end
    end
    return accepted, UInt32(0), tracked
end
