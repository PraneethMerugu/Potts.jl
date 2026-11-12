# Definitions of geometry_tests.jl that other test files use (moved here by TS1b).
using LinearAlgebra: eigvals, Symmetric

"""Brute-force geometry of cell c: unwrapped around its first site (cells < half box)."""
function brute_geometry(σ, lat::Lattice{N}, c) where {N}
    sites = [coordinates(lat, i) for i in 1:nsites(lat) if σ[i] == c]
    ref = first(sites)
    X = [collect(ref .+ min_image(lat, x, ref)) for x in sites]
    μ = sum(X) / length(X)
    C = sum((x - μ) * (x - μ)' for x in X) / length(X)
    wrapped = ntuple(d -> lat.periodic[d] ? mod(μ[d] - 1, lat.dims[d]) + 1 : μ[d], N)
    return wrapped, C
end
upper(C, N) = Tuple(C[d, e] for d in 1:N for e in d:N)

function gm_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx, prop)
end
const GM = CPMFunction(gg_delta_H; commit! = gm_commit!, temperature = gg_temperature)
moment_state(σ, kinds, lat) = initial_state(σ, kinds; cell = init_moments(σ, lat, length(kinds)))
