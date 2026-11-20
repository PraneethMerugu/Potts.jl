# Definitions of the old runtests.jl (its preamble) that other test files use.
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift

# ---------------------------------------------------------------------------------------
# A hand-written Graner–Glazier model (what the symbolic layer will generate).

kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
function gg_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
gg_temperature(st, p, prop, ctx) = p.T
const GG = CPMFunction(gg_delta_H; temperature = gg_temperature)
gg_params(T = Float64) = (; J = SMatrix{3, 3, T}(0, 16, 16, 16, 2, 11, 16, 11, 14),
    λ = T(1), V0 = T(40), T = T(10))

"""Blocky initial condition with cells of `side` sites per axis and alternating kinds."""
function blocks(dims::NTuple{N}, side; gap = 1) where {N}
    σ = zeros(Int32, dims)
    id = 0
    kinds = Int32[]
    for c in CartesianIndices(ntuple(d -> 1:(side + gap):(dims[d] - side + 1), N))
        id += 1
        push!(kinds, isodd(id) ? 1 : 2)
        σ[ntuple(d -> c[d]:(c[d] + side - 1), N)...] .= id
    end
    return σ, kinds
end

# Independent oracle: total H by brute force, each unordered contact pair counted once.
function total_H(st, lat, contact, p)
    H = 0.0
    k(c) = c == 0 ? 1 : Int(st.cell.kind[c]) + 1
    for i in 1:nsites(lat)
        x = coordinates(lat, i)
        for off in contact.offsets
            inside, y = shift(lat, x, off)
            inside || continue
            a, b = st.ownership[i], st.ownership[linear_index(lat, y)]
            a != b && (H += p.J[k(a), k(b)] / 2)
        end
    end
    vol = zeros(Int, length(st.cell.kind))
    for s in st.ownership
        s > 0 && (vol[s] += 1)
    end
    return H + sum(p.λ * (v - p.V0)^2 for v in vol)
end

# Graner–Glazier plus a surface (perimeter) constraint over a possibly weighted relation.
function gs_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    S(s, c) = p.λs * (s - p.S0)^2
    return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
           surface_delta(st.cell.surface, prop,
        surface_change(st.ownership, ctx, prop; T = eltype(st.cell.surface)), S
    )
end
function gs_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_surface!(st.cell.surface, prop,
        surface_change(st.ownership, ctx, prop; T = eltype(st.cell.surface))
    )
end
const GS = CPMFunction(gs_delta_H; commit! = gs_commit!, temperature = gg_temperature)
gs_params() = merge(gg_params(), (; λs = 0.5, S0 = 20.0))

function brute_surface(σ, lat, r, ncell)
    S = zeros(Float64, ncell)
    for i in 1:nsites(lat), (k, off) in enumerate(r.offsets)
        c = σ[i]
        inside, y = shift(lat, coordinates(lat, i), off)
        (c != 0 && inside && σ[linear_index(lat, y)] != c) || continue
        S[c] += r.weights === nothing ? 1.0 : Float64(r.weights[k])
    end
    return S
end
function total_H_surface(st, lat, ctx, p)
    H = 0.0
    k(c) = c == 0 ? 1 : Int(st.cell.kind[c]) + 1
    r = ctx.contact
    for i in 1:nsites(lat), (j, off) in enumerate(r.offsets)
        inside, y = shift(lat, coordinates(lat, i), off)
        inside || continue
        a, b = st.ownership[i], st.ownership[linear_index(lat, y)]
        w = r.weights === nothing ? 1.0 : Float64(r.weights[j])
        a != b && (H += w * p.J[k(a), k(b)] / 2)
    end
    n = length(st.cell.kind)
    vol = [count(==(c), st.ownership) for c in 1:n]
    S = brute_surface(st.ownership, lat, ctx.surface, n)
    return H + sum(p.λ * (v - p.V0)^2 for v in vol) + sum(p.λs * (s - p.S0)^2 for s in S)
end
surface_state(σ, kinds, lat, r; T = Float64) = initial_state(σ, kinds;
    cell = (; surface = recompute_surface(σ, lat, relation(r, lat), length(kinds); T)))
