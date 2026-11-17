# Definitions of compartments_tests.jl that other test files use (moved here by TS1b).
"""Nucleus/cytoplasm pairs: a `side`-box of kind 1 with a central nucleus of kind 2."""
function compartment_cells(dims, side, core)
    σ, kinds = blocks(dims, side; gap = 2)
    ncl = length(kinds)
    cluster = collect(Int32, 1:ncl)
    for c in 1:ncl
        idx = findall(==(c), σ)
        lo = minimum(idx); off = (side - core) ÷ 2
        box = ntuple(d -> (lo[d] + off):(lo[d] + off + core - 1), length(dims))
        σ[box...] .= ncl + c
        push!(cluster, c)
    end
    return σ, vcat(fill(Int32(1), ncl), fill(Int32(2), ncl)), cluster
end

function compartment_model(; λc = 1.0, Vc = 64.0, λs = 0.0, Sc = 32.0, Jint = 2.0)
    function dH(st, p, prop, ctx)
        J(a, b) = same_cluster(st.cell, a, b) ? p.Jint : @inbounds p.J[kindidx(st, a), kindidx(st, b)]
        E(v, c) = p.λ * (v - @inbounds(p.V0[st.cell.kind[c]]))^2
        EC(v, k) = p.λc * (v - p.Vc)^2
        ES(s, k) = p.λs * (s - p.Sc)^2
        return contact_delta(st.ownership, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
               cluster_volume_delta(st.cell, prop, EC) +
               cluster_surface_delta(st.cell, prop, cluster_surface_change(st.ownership, st.cell, ctx, prop), ES)
    end
    function commit!(st, p, prop, ctx)
        δ = cluster_surface_change(st.ownership, st.cell, ctx, prop)
        commit_volume!(st, p, prop, ctx)
        commit_cluster_volume!(st.cell, prop)
        commit_cluster_surface!(st.cell, prop, δ)
        haskey(st.cell, :m1) && commit_moments!(st.cell, ctx, prop)
        return nothing
    end
    p = (; J = SMatrix{3, 3}(0.0, 16, 30, 16, 14, 30, 30, 30, 14), Jint, λ = 1.0,
        V0 = (48.0, 16.0), λc, Vc, λs, Sc, T = 10.0)
    alive(st, p, prop, ctx) = forbid_extinction(st.cell.volume, prop)
    f = CPMFunction(dH; commit!, temperature = gg_temperature, constraint = alive)
    return f, p
end

"""Moment trackers of `u` exact: on the host planner equal to a recount from σ; on the device
planner (D-089), which keeps the parent's anchor for a daughter (a representation choice),
the same centroid and covariance of every live cell as the recount."""
function same_moments(u, lat::Lattice{N}, cap, alg) where {N}
    m = init_moments(u.ownership, lat, cap)
    device = CorePotts._FORCE_DEVICE_LIFECYCLE[] && alg isa CheckerboardCPM
    device || return u.cell.m1 == m.m1 && u.cell.m2 == m.m2
    ref = merge(m, (; volume = Int32[count(==(c), u.ownership) for c in 1:cap]))
    return all(1:cap) do c
        ref.volume[c] == 0 && return u.cell.volume[c] == 0
        all(isapprox.(centroid(u.cell, lat, c), centroid(ref, lat, c); atol = 1e-9)) &&
            all(isapprox.(CorePotts.covariance(Float64, u.cell, c, Val(N)), CorePotts.covariance(Float64, ref, c, Val(N)); atol = 1e-9))
    end
end
