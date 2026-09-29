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

@testset "remake with symbolic maps; the sweep law" begin
    prob = symbolic_graner_problem(; nmcs = 5)
    λ = first(filter(x -> Potts.info(x).name === :λ, SORTING.sys.parameters))
    q = remake(prob; p = [λ => 3.0])
    @test q.p.λ == 3.0 && q.p.V₀ == prob.p.V₀ && q.f === prob.f
    @test remake(prob; p = Dict(:T => 2)).p.T === 2.0              # converted to the scalar type
    @test_throws ArgumentError remake(prob; p = [:nope => 1.0])
    σ, kinds = graner_state()
    r = remake(prob; u0 = [ownership => circshift(σ, (3, 0)), kind => kinds])
    @test r.u0.σ == circshift(σ, (3, 0)) && r.u0.cell.volume == prob.u0.cell.volume
    @test prob.f.acceptance === Metropolis()
end

@potts_model Spring begin
    @kinds medium blob
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        T = 10.0
        k = 2.0
        J[kind, kind] = [0 16; 16 2]
    end
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
        edges(bond) => k * (distance - rest)^2
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model Tissue begin
    @kinds medium leader follower
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables age(edge) = 0.0
    @relationship bond(cell, cell) capacity = 8
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @link bond when = new_contact(a, b) && (kind[a] == leader), every = 100
    @unlink bond when = distance > 100.0
    @sweep Metropolis(; temperature = T)
end

@testset "relationships: springs and link rules" begin
    σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[40:45, 12:17] .= 2
    prob = PottsProblem(Spring(; name = :spring), [ownership => σ, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000))
    @test CorePotts.linked(prob.u0.cell, 1, 2) && prob.u0.cell.link_rest[1, 1] == 12.0
    # self-check with edge energies (partner centroids move with the copy)
    worst = 0.0
    for (u, prop) in proposal_states(remake(prob; tspan = (0, 5)); mcs = (0, 5), n = 300)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u))))
    end
    @test worst < 1e-9
    ds = map(1:4) do seed
        u = solve(remake(prob; seed), CheckerboardCPM()).u[end]
        CorePotts.centroid_distance(Float64, u.cell, prob.lattice, 1, 2)
    end
    @test abs(sum(ds) / 4 - 12.0) < 2.5                 # relaxes from 25 to the rest length

    σb = zeros(Int32, 30, 30)
    for (c, (i, j)) in enumerate(Iterators.product(1:5:26, 1:5:26))
        σb[i:(i + 4), j:(j + 4)] .= c
    end
    n = maximum(σb)
    kinds = [isodd(c) ? :leader : :follower for c in 1:n]
    tp = PottsProblem(Tissue(; name = :tissue), [ownership => σb, kind => kinds], (0, 1))
    u = solve(tp, SequentialCPM()).u[end]            # the rule ran once, after MCS 0's sweep
    g = CorePotts.contact_graph(u.σ, tp.lattice, tp.contact, n)
    nlinks = 0
    for a in 1:n, b in (a + 1):n
        touching = b in CorePotts.neighbors(g, a)
        led = isodd(a) || isodd(b)
        @test CorePotts.linked(u.cell, a, b) == (touching && led)
        nlinks += CorePotts.linked(u.cell, a, b)
    end
    @test nlinks > 20
end
