# Symbolic front end (ROADMAP M3.1–M3.3): generated models equal the hand-written oracle
# ports proposal by proposal, and the derived ΔH equals H(after) − H(before) of the
# generated total energy.
using Random: Xoshiro

"""Random proposals (Moore(1) sources) on states along a trajectory of `prob`."""
function proposal_states(prob; mcs = (0, 5, 20), n = 400, rng = Xoshiro(11))
    sol = solve(remake(prob; tspan = (0, maximum(mcs))), SequentialCPM(; proposal = Moore(1)); saveat = collect(mcs))
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    out = Tuple{Any, Any}[]
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.σ)); x = CorePotts.coordinates(lat, t)
        d = rand(rng, 1:length(moore))
        ins, y = CorePotts.shift(lat, x, moore.offsets[d])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        push!(out, (u, CorePotts.Proposal(t, s, x, d, u.σ[t], u.σ[s])))
    end
    return out
end

ctx_of(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...)

@testset "symbolic models equal the hand-written ports: $name" for (name, sym, hand) in (
        ("graner", () -> symbolic_graner_problem(; nmcs = 20), () -> graner_problem(; nmcs = 20)),
        ("wortel", symbolic_wortel_problem, wortel_problem),
        ("merks", symbolic_merks_problem, merks_problem),
        ("openvt", symbolic_openvt_problem, openvt_problem))
    sp, hp = sym(), hand()
    ctx = merge(ctx_of(hp), ctx_of(sp))
    worst_h = 0.0; worst_e = 0.0
    agree_c = true; agree_commit = true
    for (u, prop) in proposal_states(sp)
        dHs = sp.f.delta_H(u, sp.p, prop, ctx)
        dHh = hp.f.delta_H(u, hp.p, prop, ctx)
        worst_h = max(worst_h, abs(dHs - dHh))
        agree_c &= sp.f.constraint(u, sp.p, prop, ctx) == hp.f.constraint(u, hp.p, prop, ctx)
        # commit: both applied to copies after the ownership write
        a = deepcopy(u); b = deepcopy(u)
        a.σ[prop.target] = prop.new; b.σ[prop.target] = prop.new
        sp.f.commit!(a, sp.p, prop, ctx); hp.f.commit!(b, hp.p, prop, ctx)
        agree_commit &= all(k -> getfield(a.cell, k) == getfield(b.cell, k), intersect(keys(a.cell), keys(b.cell))) &&
                        all(k -> getfield(a.site, k) == getfield(b.site, k), intersect(keys(a.site), keys(b.site)))
        # self-check: ΔE equals H(after) − H(before)
        H0 = total_energy(sp, u)
        H1 = total_energy(sp, a)
        worst_e = max(worst_e, abs(energy_change(sp, u, prop) - (H1 - H0)))
    end
    @test worst_h < 1e-9
    @test agree_c
    @test agree_commit
    @test worst_e < 1e-9
    # trajectories agree too (same address-keyed randomness, same functions)
    tspan = (0, 15)
    us = solve(remake(sp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
    uh = solve(remake(hp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
    @test us.σ == uh.σ
end

@testset "symbolic surface: generated code" begin
    ex = PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[]], (0, 1); expression = Val(true))
    s = string(ex.delta_H)
    @test occursin("p.J", s) && occursin("st.cell.volume", s)
    @test !occursin("^", s)                          # the volume term was expanded to closed form
    prob = symbolic_graner_problem(; nmcs = 5)
    @test remake(prob; p = merge(prob.p, (; λ = 2.0))).f === prob.f   # parameters change, code does not
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 4, 4)], (0, 1))
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[],
        first(filter(x -> Potts.info(x).name === :J, SORTING.sys.parameters)) => [0 1 1; 2 0 1; 1 1 0]], (0, 1))
end

@testset "rebuilding a problem reuses the generated code" begin
    a = symbolic_wortel_problem(; seed = 1)
    b = symbolic_wortel_problem(; seed = 2)
    @test typeof(a.f) === typeof(b.f)
    @test a.f.fingerprint == b.f.fingerprint
end
