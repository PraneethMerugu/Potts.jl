# Sequential (random-site) dynamics on the host.

function sequential_mcs!(st, f::F, p, ctx, law::L, key::RNGKey, mcs::Integer) where {F, L}
    σ = st.σ
    lat = ctx.lattice
    mob = ctx.mobility
    nsite = nmobile(mob, lat)
    K = length(ctx.proposal)
    accepted = 0
    for attempt in 1:nsite
        rt, rd, ra, _ = draw(key, mcs, attempt, STREAM_SEQUENTIAL_TARGET)
        t = mobile_site(mob, bounded(rt, nsite) + 1)
        x = coordinates(lat, t)
        dir = bounded(rd, K) + 1
        inside, y = shift(lat, x, @inbounds ctx.proposal.offsets[dir])
        inside || continue
        s = linear_index(lat, y)
        is_mobile(mob, s) || continue
        a = @inbounds σ[t]
        b = @inbounds σ[s]
        a == b && continue
        prop = Proposal(t, s, x, dir, a, b)
        f.constraint(st, p, prop, ctx) || continue
        dH = f.delta_H(st, p, prop, ctx)
        temperature = f.temperature(st, p, prop, ctx)
        T = typeof(temperature)
        dH = _effective_dH(f, dH, temperature, st, p, prop, ctx)
        isfinite(dH) || return accepted, STATUS_NONFINITE
        if accept(law, T(dH), temperature, uniform(T, ra))
            @inbounds σ[t] = b
            f.commit!(st, p, prop, ctx)
            accepted += 1
        end
    end
    return accepted, UInt32(0)
end
