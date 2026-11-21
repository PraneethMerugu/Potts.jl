# Exact transition-matrix oracle.
#
# For a tiny closed lattice, propagate the exact distribution over lattice states through
# m MCS of each algorithm's *stated* dynamics, then compare with the empirical distribution
# of m-MCS end states over many seeds (total-variation distance against its sampling
# noise). Nothing here calls production code except `solve`; neighbor tables, energies,
# the coloring and the claim resolution are re-derived from their specifications.

module Oracle

const State = Vector{Int8}

struct Tiny
    dims::Tuple{Int, Int}
    proposal::Vector{Tuple{Int, Int}}
    contact::Vector{Tuple{Int, Int}}
    kinds::Vector{Int}
    J::Matrix{Float64}          # indexed by kind + 1 (medium = 1)
    λ::Float64
    V0::Float64
    T::Float64
    periodic::Bool
    drive_x::Float64
end
function Tiny(dims, proposal, contact, kinds, J, λ, V0, T, periodic = false)
    return Tiny(dims, proposal, contact, kinds, J, λ, V0, T, periodic, 0.0)
end

nsite(m::Tiny) = prod(m.dims)
lin(m::Tiny, x, y) = x + (y - 1) * m.dims[1]
coords(m::Tiny, i) = (mod1(i, m.dims[1]), cld(i, m.dims[1]))
function nbr(m::Tiny, i, o)                     # closed: nothing outside; periodic: wrap
    x, y = coords(m, i)
    u, v = x + o[1], y + o[2]
    m.periodic && return lin(m, mod1(u, m.dims[1]), mod1(v, m.dims[2]))
    (1 <= u <= m.dims[1] && 1 <= v <= m.dims[2]) || return 0
    return lin(m, u, v)
end

kind(m::Tiny, c) = c == 0 ? 1 : m.kinds[c] + 1
function H(m::Tiny, σ::State)
    h = 0.0
    for i in 1:nsite(m), o in m.contact
        j = nbr(m, i, o)
        j == 0 && continue
        σ[i] != σ[j] && (h += m.J[kind(m, σ[i]), kind(m, σ[j])] / 2)
    end
    for c in eachindex(m.kinds)
        h += m.λ * (count(==(c), σ) - m.V0)^2
    end
    return h
end
pacc(m::Tiny, dH) = dH <= 0 ? 1.0 : exp(-dH / m.T)

add!(d, s, w) = (d[s] = get(d, s, 0.0) + w)

"""Signed x-displacement (target - source), minimum-image on periodic axes."""
function dx(m::Tiny, t, s)
    xt, _ = coords(m, t)
    xs, _ = coords(m, s)
    d = Float64(xt - xs)
    m.periodic || return d
    L = m.dims[1]
    return d - L * round(d / L)
end

"""
One random-site attempt over `sites`: target uniform over `sites`, direction uniform over
the relation.
"""
function attempt_sites(m::Tiny, dist, sites)
    out = Dict{State, Float64}()
    M, K = length(sites), length(m.proposal)
    M == 0 && return copy(dist)
    for (σ, w) in dist
        h = H(m, σ)
        for t in sites, o in m.proposal
            q = w / (M * K)
            s = nbr(m, t, o)
            if s == 0 || σ[s] == σ[t]
                add!(out, σ, q)
                continue
            end
            σ′ = copy(σ)
            σ′[t] = σ[s]
            dH = (H(m, σ′) - h) + m.drive_x * dx(m, t, s)
            a = pacc(m, dH)
            add!(out, σ′, q * a)
            add!(out, σ, q * (1 - a))
        end
    end
    return out
end

"""
One random-site attempt: target uniform over all sites, direction uniform over the relation.
"""
attempt(m::Tiny, dist) = attempt_sites(m, dist, 1:nsite(m))
sequential_mcs(m, dist) = foldl((d, _) -> attempt(m, d), 1:nsite(m); init = dist)

"""
One `CheckerboardCPM` MCS for general `BlockLayout` (`parts = k`, `region = b`,
`switches = 1`): each of the `P = k^2` phases activates a uniform offset in
`{0, ..., k-1}^2`, and each block makes `length(S)` uniform attempts inside its active
sub-region `S` in block order.
"""
function layout_mcs(m::Tiny, dist, k::Int, b::Int = 1, switches::Int = 1)
    dims = m.dims
    nb = ntuple(d -> max(1, dims[d] ÷ (k * b)), 2)
    base = ntuple(d -> dims[d] ÷ (k * nb[d]), 2)
    rem_ = ntuple(d -> dims[d] - k * nb[d] * base[d], 2)
    offsets = [(ox, oy) for oy in 0:(k - 1) for ox in 0:(k - 1)]
    blocks = [(bx, by) for by in 0:(nb[2] - 1) for bx in 0:(nb[1] - 1)]
    P = length(offsets) * switches

    function region_sites((bx, by), (ox, oy))
        jx = k * bx + ox
        jy = k * by + oy
        x0 = jx * base[1] + min(jx, rem_[1])
        y0 = jy * base[2] + min(jy, rem_[2])
        sx = base[1] + (jx < rem_[1])
        sy = base[2] + (jy < rem_[2])
        sites = Int[]
        for y in (y0 + 1):(y0 + sy), x in (x0 + 1):(x0 + sx)
            push!(sites, lin(m, x, y))
        end
        return sites
    end

    function phase(d)
        out = Dict{State, Float64}()
        w_off = 1.0 / length(offsets)
        for off in offsets
            d_off = copy(d)
            for blk in blocks
                sites = region_sites(blk, off)
                n = length(sites)
                n == 0 && continue
                q_lo, r_hi = divrem(n, switches)
                for _ in 1:q_lo
                    d_off = attempt_sites(m, d_off, sites)
                end
                if r_hi > 0
                    p_extra = r_hi / switches
                    d_stay = attempt_sites(m, d_off, sites)
                    d_mix = Dict{State, Float64}()
                    foreach(((σ, w),) -> add!(d_mix, σ, w * (1 - p_extra)), d_off)
                    foreach(((σ, w),) -> add!(d_mix, σ, w * p_extra), d_stay)
                    d_off = d_mix
                end
            end
            foreach(((σ, w),) -> add!(out, σ, w * w_off), d_off)
        end
        return out
    end
    return foldl((d, _) -> phase(d), 1:P; init = dist)
end

"""
One `CheckerboardCPM` MCS on a lattice that is one block of one-site sub-regions (every axis
shorter than `parts`, block 1): each of the `P` phases activates a uniform offset, which is
one site (an attempt there) or none, so a phase is an attempt with probability nsite/P and
no change otherwise.
"""
function block_mcs(m::Tiny, dist, P)
    q = nsite(m) / P
    function phase(d)
        out = Dict{State, Float64}()
        foreach(((σ, w),) -> add!(out, σ, w * (1 - q)), d)
        foreach(((σ, w),) -> add!(out, σ, w * q), attempt(m, d))
        return out
    end
    return foldl((d, _) -> phase(d), 1:P; init = dist)
end

function exact(m::Tiny, σ0::State, nmcs, step)
    d = Dict(σ0 => 1.0)
    for _ in 1:nmcs
        d = step(m, d)
    end
    return d
end

"""TV distance and its expected value under multinomial sampling noise of size R."""
function tv(exact, counts, R)
    keys_ = union(keys(exact), keys(counts))
    d = sum(abs(get(exact, k, 0.0) - get(counts, k, 0) / R) for k in keys_) / 2
    noise = sum(sqrt(2p * (1 - p) / (π * R)) for p in values(exact)) / 2
    return d, noise
end

"""
Pearson χ² of the counts against the exact distribution (states with expected count < 5
pooled into one bin), as a Wilson–Hilferty z-score: ≈ N(0, 1) when the sampler is exact.
"""
function chi2_z(exact, counts, R)
    X = 0.0
    k = -1
    pe = 0.0
    pc = 0
    for (σ, p) in exact
        c = get(counts, σ, 0)
        if R * p >= 5
            X += (c - R * p)^2 / (R * p)
            k += 1
        else
            pe += p
            pc += c
        end
    end
    pc += sum(c for (σ, c) in counts if !haskey(exact, σ); init = 0)   # impossible states
    pe > 0 && (X += (pc - R * pe)^2 / (R * pe); k += 1)
    pe == 0 && pc > 0 && return Inf
    return ((X / k)^(1 / 3) - (1 - 2 / (9k))) / sqrt(2 / (9k))
end

end # module Oracle
