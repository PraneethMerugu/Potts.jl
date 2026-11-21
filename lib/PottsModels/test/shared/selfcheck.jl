# `selfcheck(prob)`: the largest difference, over sampled proposals along a short run,
# between the model's derived ΔH and the brute-force energy difference (`total_energy` after
# minus before, with the killing credit). A correct model gives rounding error only.
function selfcheck(prob; n = 200)
    sol = solve(remake(prob; tspan = (0, 3)), SequentialCPM(; proposal = Moore(1)))
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    moore = CorePotts.relation(Moore(1), lat)
    worst = 0.0
    for u in sol.u, i in 1:n
        t = mod1(i * 7919, length(u.ownership))
        x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, moore.offsets[mod1(i, length(moore))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.ownership[t] == u.ownership[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.ownership[t], u.ownership[s])
        a = deepcopy(u)
        a.ownership[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx)
        worst = max(
            worst,
            abs(
                energy_change(prob, u, prop) -
                    (
                    total_energy(prob, a) - total_energy(prob, u) +
                        Potts._killing_credit(prob, u, prop, a)
                )
            )
        )
    end
    return worst
end
