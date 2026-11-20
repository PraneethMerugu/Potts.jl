# Sequential (random-site) dynamics on the host.
#
# Returns `(accepted, status, tracked)`: `tracked` is the Float64 sum of `track` (the
# CPMFunction's, D-140) over the committed copies, or `nothing` without a track (a type-level
# branch: no code when off).

# `part = (j, n)`: pass `j` of `n` of a sub-MCS `Repeat`, the attempts
# `(j-1)·N÷n+1 : j·N÷n` of the MCS (the whole MCS is `(1, 1)`)
function sequential_mcs!(st, f::F, p, ctx, law::L, key::RNGKey, mcs::Integer, track::TK = nothing,
        part::NTuple{2, Int} = (1, 1)) where {F, L, TK}
    σ = st.ownership
    lat = ctx.lattice
    mob = ctx.mobility
    nsite = nmobile(mob, lat)
    K = length(ctx.proposal)
    accepted = 0
    tracked = track === nothing ? nothing : 0.0
    j, n = part
    for attempt in ((j - 1) * nsite ÷ n + 1):(j * nsite ÷ n)
        rt, rd, ra, rx = draw(key, mcs, attempt, STREAM_SEQUENTIAL_TARGET)
        # the pick regime is the context's type (D-247): one word unless the caller marked it
        t = mobile_site(mob, site_pick(_pick_regime(ctx), rt, rx, nsite) + 1)
        x = coordinates(lat, t)
        dir = bounded(rd, K) + 1
        # bounds: dir ∈ 1:K, K = length(ctx.proposal); site indices ≤ nsites
        inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
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
            # the whole-cell veto (`Global`) after the draw: the same trajectory as
            # before ΔH, at a fraction of the cost (no code without it)
            has_post(f) && _post(f)(st, p, prop, ctx, GlobalSearch()) != GLOBAL_PASS && continue
            track === nothing || (tracked += Float64(track(st, p, prop, ctx, dH0)))
            @inbounds σ[t] = b
            f.commit!(st, p, prop, ctx)
            accepted += 1
        end
    end
    return accepted, UInt32(0), tracked
end
