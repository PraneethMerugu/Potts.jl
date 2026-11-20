# Definitions of contact_counts_tests.jl that other test files use.
function cc_brute(σ, kind, lat, rel, kinds, n)
    out = zeros(Int32, n)
    for i in 1:nsites(lat)
        c = σ[i]
        c == 0 && continue
        x = coordinates(lat, i)
        for o in rel.offsets
            inside, y = shift(lat, x, o)
            inside || continue
            q = σ[linear_index(lat, y)]
            q == c && continue
            (q == 0 ? 0 : kind[q]) in kinds && (out[c] += 1)
        end
    end
    return out
end

const CC_MED = UInt64(0b001)          # partner is the medium
const CC_TWO = UInt64(0b100)          # partner is of kind 2
function cc_commit!(st, p, prop, ctx)
    commit_volume!(st, p, prop, ctx)
    commit_moments!(st.cell, ctx, prop)
    commit_contact_count!(st.cell.n_med, st.ownership, st.cell.kind, ctx.contact, CC_MED, ctx.lattice, prop)
    commit_contact_count!(st.cell.n_two, st.ownership, st.cell.kind, ctx.vn, CC_TWO, ctx.lattice, prop)
    return nothing
end
# divisions of large cells every other MCS, and cell 1 changes kind at MCS 4
function cc_trigger(st, p, ctx, key, mcs, c)
    if mcs == 4 && c == 1
        return EVENT_TRANSITION
    elseif iseven(mcs) && st.cell.volume[c] >= 28
        return EVENT_DIVIDE
    else
        return EVENT_NONE
    end
end
cc_kind(st, p, ctx, key, mcs, c) = Int32(3 - st.cell.kind[c])

function cc_problem(; lifecycle = true)
    lat = Lattice((30, 24); boundary = (Periodic(), Closed()))
    σ = zeros(Int32, 30, 24)
    blocks = ((vcat(29:30, 1:3), 1:5), (8:12, 1:5), (13:17, 2:6), (5:9, 12:16), (20:24, 18:22))
    for (c, (xs, ys)) in enumerate(blocks)
        σ[xs, ys] .= c
    end
    kinds = Int32[1, 2, 1, 2, 1]
    cell = merge(
        init_moments(σ, lat, 5),
        (;
            n_med = recompute_contact_count(σ, kinds, lat, Moore(1), CC_MED, 5),
            n_two = recompute_contact_count(σ, kinds, lat, VonNeumann(1), CC_TWO, 5),
        )
    )
    st = with_capacity(initial_state(σ, kinds; cell), 32)
    cc = ContactCounts((ContactCount(:n_med, Moore(1), CC_MED), ContactCount(:n_two, VonNeumann(1), CC_TWO)))
    f = CPMFunction(
        gg_delta_H; commit! = cc_commit!, temperature = gg_temperature,
        lifecycle = lifecycle ? Lifecycle(cc_trigger; kind = cc_kind, normal = RandomPlane()) : nothing
    )
    p = merge(gg_params(), (; V0 = 36.0, T = 8.0))
    return PottsProblem(
        f, st, lat, (0, 30), p; contact = Moore(1), proposal = Moore(1),
        relations = (; vn = VonNeumann(1), contact_counts = cc), seed = 7
    )
end

function cc_bad(sol, lat)
    bad = 0
    for u in sol.u
        m = cc_brute(u.ownership, u.cell.kind, lat, relation(Moore(1), lat), (0,), length(u.cell.kind))
        t = cc_brute(u.ownership, u.cell.kind, lat, relation(VonNeumann(1), lat), (2,), length(u.cell.kind))
        bad += (u.cell.n_med != m) + (u.cell.n_two != t)
    end
    return bad
end
